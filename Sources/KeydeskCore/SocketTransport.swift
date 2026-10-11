import Foundation
import Darwin

public enum SocketTransport {
    public static var socketPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Keydesk/cli.sock").path
    }
    public static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { pointer in
            for i in bytes.indices { pointer[i] = UInt8(bitPattern: bytes[i]) }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
    public static func send<T: Encodable>(_ value: T, to fd: Int32) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value) + Data([10])
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EPIPE) }
                offset += count
            }
        }
    }
    public static func readLine(from fd: Int32, maximum: Int = 1_048_576, deadlineSeconds: Double? = nil) throws -> Data? {
        var result = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        var fileInfo = stat()
        guard fstat(fd, &fileInfo) == 0 else { throw POSIXError(.EBADF) }
        let isSocket = (fileInfo.st_mode & S_IFMT) == S_IFSOCK
        let deadline = deadlineSeconds.map { DispatchTime.now().uptimeNanoseconds + UInt64(max(0, min($0, 60)) * 1_000_000_000) }
        while result.count < maximum {
            if let deadline {
                let now = DispatchTime.now().uptimeNanoseconds
                guard now < deadline else { throw POSIXError(.ETIMEDOUT) }
                var readiness = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let remaining = Int32(max(1, (deadline - now) / 1_000_000))
                let ready = poll(&readiness, 1, remaining)
                if ready < 0 && errno == EINTR { continue }
                guard ready > 0 else { throw POSIXError(.ETIMEDOUT) }
            }
            if !isSocket {
                var byte: UInt8 = 0
                let count = Darwin.read(fd, &byte, 1)
                if count < 0 && errno == EINTR { continue }
                if count == 0 { return result.isEmpty ? nil : result }
                guard count > 0 else { throw POSIXError(.EIO) }
                if byte == 10 { return result }
                result.append(byte); continue
            }
            let peeked = recv(fd, &buffer, buffer.count, MSG_PEEK)
            if peeked < 0 && errno == EINTR { continue }
            if peeked == 0 { return result.isEmpty ? nil : result }
            guard peeked > 0 else { throw POSIXError(.EIO) }
            let newline = buffer.prefix(peeked).firstIndex(of: 10)
            let consume = newline.map { $0 + 1 } ?? peeked
            var remaining = consume
            while remaining > 0 {
                let count = Darwin.read(fd, &buffer, remaining)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                let content = count == remaining && newline != nil ? count - 1 : count
                guard result.count + content < maximum else { throw VaultError.invalidData }
                result.append(contentsOf: buffer.prefix(content)); remaining -= count
            }
            if newline != nil { return result }
        }
        throw VaultError.invalidData
    }
}
