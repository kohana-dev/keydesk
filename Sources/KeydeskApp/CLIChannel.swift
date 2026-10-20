import Foundation
import Darwin
import KeydeskCore

final class CLIChannel: @unchecked Sendable {
    let fd: Int32
    private let lock = NSLock()
    private var closed = false
    init(fd: Int32) { self.fd = fd }
    @discardableResult func send(_ event: CLIEvent) -> Bool {
        sendValue(event)
    }
    @discardableResult func sendValue<T: Encodable>(_ value: T) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return false }
        do { try SocketTransport.send(value, to: fd); return true } catch { return false }
    }
    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return false }
        var byte: UInt8 = 0
        let count = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return count > 0 || (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
    }
    /// The input pump owns this descriptor until it stops. Reading the channel's raw fd after
    /// finish could otherwise read an unrelated request that reused the same descriptor number.
    func makeInputHandle() throws -> FileHandle {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { throw VaultError.locked }
        let descriptor = fcntl(fd, F_DUPFD_CLOEXEC, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        if !closed { closed = true; shutdown(fd, SHUT_RDWR); close(fd) }
    }
}
