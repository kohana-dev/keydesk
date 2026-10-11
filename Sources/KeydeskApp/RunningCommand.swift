import Foundation
import Darwin

final class RunningCommand: @unchecked Sendable {
    let keepRunning: Bool
    private let process: Process?
    private let pid: pid_t?
    private let lock = NSLock()
    private var finished = false
    private let cleanup: @Sendable () -> Void
    init(process: Process, keepRunning: Bool, cleanup: @escaping @Sendable () -> Void = {}) { self.process = process; self.pid = nil; self.keepRunning = keepRunning; self.cleanup = cleanup }
    init(pid: pid_t, keepRunning: Bool, cleanup: @escaping @Sendable () -> Void = {}) { self.pid = pid; self.process = nil; self.keepRunning = keepRunning; self.cleanup = cleanup }
    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return !finished && (process?.isRunning ?? true)
    }
    func didFinish() { lock.lock(); finished = true; lock.unlock(); cleanup() }
    func terminate() {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        if let process { if process.isRunning { process.terminate() } }
        else if let pid { _ = kill(-pid, SIGTERM) }
        cleanup()
    }
}
