import Foundation
import Darwin
import KeydeskCore

final class CLIChannel: @unchecked Sendable {
    let fd: Int32
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "com.keydesk.cli-channel-writer")
    private var accepting = true
    private var closed = false
    private var queuedBytes = 0
    private var descriptorClosed = false // Accessed only by writer.
    private static let maximumQueuedBytes = 4 * 1024 * 1024

    init(fd: Int32) {
        self.fd = fd
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSig: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSig, socklen_t(MemoryLayout<Int32>.size))
    }
    @discardableResult func send(_ event: CLIEvent) -> Bool { sendValue(event) }

    /// Success means queued for ordered delivery, not acknowledged by the peer.
    @discardableResult func sendValue<T: Encodable>(_ value: T) -> Bool {
        let data: Data
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
            data = try encoder.encode(value) + Data([10])
        } catch { return false }
        lock.lock(); defer { lock.unlock() }
        guard accepting, !closed else { return false }
        guard data.count <= Self.maximumQueuedBytes - queuedBytes else {
            abortLocked()
            writer.async { self.closeDescriptor() }
            return false
        }
        queuedBytes += data.count
        writer.async {
            defer { self.lock.withLock { self.queuedBytes -= data.count } }
            guard self.lock.withLock({ !self.closed }) else { return }
            do { try self.write(data) }
            catch {
                self.lock.withLock { self.abortLocked() }
                self.closeDescriptor()
            }
        }
        return true
    }
    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return false }
        var byte: UInt8 = 0
        let count = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return count > 0 || (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
    }
    /// The input pump owns this descriptor until it stops, independently of channel close.
    func makeInputHandle() throws -> FileHandle {
        lock.lock(); defer { lock.unlock() }
        guard accepting, !closed else { throw VaultError.locked }
        let descriptor = fcntl(fd, F_DUPFD_CLOEXEC, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    /// Drain accepted events in order. Socket timeout bounds a peer that stops reading.
    func finish() {
        lock.lock(); defer { lock.unlock() }
        guard accepting else { return }
        accepting = false
        writer.async {
            guard !self.descriptorClosed else { return }
            self.lock.withLock { self.closed = true; shutdown(self.fd, SHUT_RDWR) }
            self.closeDescriptor()
        }
    }
    private func abortLocked() {
        accepting = false; closed = true
        // Interrupt an in-flight send without waiting for the writer's lock or reusing its fd.
        shutdown(fd, SHUT_RDWR)
    }
    private func closeDescriptor() {
        guard !descriptorClosed else { return }
        descriptorClosed = true
        close(fd)
    }
    private func write(_ data: Data) throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard DispatchTime.now().uptimeNanoseconds < deadline else { throw POSIXError(.ETIMEDOUT) }
                let count = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EPIPE) }
                offset += count
            }
        }
    }
}
