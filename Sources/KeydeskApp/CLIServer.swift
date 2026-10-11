import Foundation
import Darwin
import KeydeskCore

final class CLIServer: @unchecked Sendable {
    private var listener: Int32 = -1
    private let path: String
    private let trustedHelper: URL?
    init(path: String = SocketTransport.socketPath, trustedHelper: URL? = nil) { self.path = path; self.trustedHelper = trustedHelper }
    func start(deliver: @escaping @Sendable (CLIApproval) -> Void, broker: @escaping @Sendable (BrokerRequest, CLIChannel) -> Void, service: @escaping @Sendable (ServiceRequest, CLIChannel) -> Void = { _, channel in channel.finish() }) throws {
        let requirement = try trustedHelper.map { try PeerVerifier.requirement(for: $0) }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try VaultFileStore.preparePrivateDirectory(directory)
        // Never unlink an active server's socket.
        if FileManager.default.fileExists(atPath: path) {
            let probe = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = try SocketTransport.address(path)
            let result = withUnsafePointer(to: &address) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            close(probe)
            guard result != 0 else { throw NSError(domain: "Keydesk", code: 1, userInfo: [NSLocalizedDescriptionKey: "다른 Keydesk 앱이 실행 중입니다."]) }
            try FileManager.default.removeItem(atPath: path)
        }
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        _ = fcntl(listener, F_SETFD, FD_CLOEXEC)
        var address = try SocketTransport.address(path)
        let bound = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(listener, 8) == 0 else { throw POSIXError(.EACCES) }
        let fd = listener
        DispatchQueue.global().async {
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { break }
                var user: uid_t = 0, group: gid_t = 0
                guard getpeereid(client, &user, &group) == 0, user == getuid() else { close(client); continue }
                guard let peerPID = try? PeerVerifier.pid(for: client),
                      requirement.map({ PeerVerifier.matches(pid: peerPID, requirement: $0) }) ?? true else { close(client); continue }
                var timeout = timeval(tv_sec: 10, tv_usec: 0)
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var sendTimeout = timeval(tv_sec: 2, tv_usec: 0)
                setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
                _ = fcntl(client, F_SETFD, FD_CLOEXEC)
                var noSig: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSig, socklen_t(MemoryLayout<Int32>.size))
                // Bounded serial request decoding: no unbounded background threads before approval.
                let channel = CLIChannel(fd: client)
                do {
                    guard let data = try SocketTransport.readLine(from: client, maximum: 2 * 1024 * 1024, deadlineSeconds: 10) else { channel.finish(); continue }
                    timeout = timeval(tv_sec: 0, tv_usec: 0)
                    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    let json = try JSONDecoder().decode(JSONValue.self, from: data)
                    if json["kind"]?.string == "mcp" {
                        let request = try JSONDecoder().decode(BrokerRequest.self, from: data)
                        guard request.session.count <= 128, request.project.count <= 128, request.tool.count <= 64 else { throw VaultError.invalidData }
                        let bound = BrokerRequest(session: "pid:\(peerPID):\(request.session)", project: request.project, environment: request.environment, tool: request.tool, arguments: request.arguments)
                        broker(bound, channel)
                    } else if ["store", "store-file", "verify-recovery", "lock", "delete-project", "status", "revoke-runs"].contains(json["kind"]?.string ?? "") {
                        service(try JSONDecoder().decode(ServiceRequest.self, from: data), channel)
                    } else {
                        let request = try JSONDecoder().decode(CLIRequest.self, from: data)
                        guard !request.command.isEmpty, request.command.count <= 128, request.command.allSatisfy({ !$0.contains("\0") }), !request.directory.contains("\0") else { throw VaultError.invalidData }
                    deliver(try CLIApproval(request: request, channel: channel))
                    }
                } catch { channel.send(CLIEvent(kind: "error", text: "유효하지 않은 CLI 요청입니다.")); channel.finish() }
            }
        }
    }
    func stop() {
        if listener >= 0 { shutdown(listener, SHUT_RDWR); close(listener); listener = -1; unlink(path) }
    }
}
