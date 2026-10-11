import Foundation
import Darwin

final class RunningCommand: @unchecked Sendable {
    let keepRunning: Bool
    private let process: Process?
    private let pid: pid_t?
    private let lock = NSLock()
    private var finished = false
    init(process: Process, keepRunning: Bool) { self.process = process; self.pid = nil; self.keepRunning = keepRunning }
    init(pid: pid_t, keepRunning: Bool) { self.pid = pid; self.process = nil; self.keepRunning = keepRunning }
    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return !finished && (process?.isRunning ?? true)
    }
    func didFinish() { lock.lock(); finished = true; lock.unlock() }
    func terminate() {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        if let process { if process.isRunning { process.terminate() } }
        else if let pid { _ = kill(-pid, SIGTERM) }
    }
}
