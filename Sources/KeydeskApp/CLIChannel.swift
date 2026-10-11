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
    func finish() {
        lock.lock(); defer { lock.unlock() }
        if !closed { closed = true; shutdown(fd, SHUT_RDWR); close(fd) }
    }
}
