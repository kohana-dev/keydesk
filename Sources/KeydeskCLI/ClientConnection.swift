import Foundation
import Darwin
import KeydeskCore

final class ClientConnection: @unchecked Sendable {
    let fd: Int32
    private let lock = NSLock()
    private var closed = false
    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        let addressValue: sockaddr_un
        do { addressValue = try SocketTransport.address(path) } catch { close(fd); throw error }
        var address = addressValue
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if result != 0 { close(fd); throw VaultError.locked }
        var sendTimeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        var timeout = timeval(tv_sec: 120, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    func send<T: Encodable>(_ value: T) throws {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { throw VaultError.locked }
        try SocketTransport.send(value, to: fd)
    }
    func closeConnection() {
        lock.lock(); defer { lock.unlock() }
        if !closed { closed = true; shutdown(fd, SHUT_RDWR); close(fd) }
    }
    func allowLongRunningRead() { var timeout = timeval(tv_sec: 0, tv_usec: 0); _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) }
}
