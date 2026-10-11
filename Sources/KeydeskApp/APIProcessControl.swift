import Foundation

final class APIProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    var cancelled: Bool { lock.withLock { stopped } }
    func start(_ process: Process) throws {
        try lock.withLock {
            guard !stopped else { throw CancellationError() }
            try process.run(); self.process = process
        }
    }
    func cancel() { lock.withLock { stopped = true; if let process, process.isRunning { process.terminate() } } }
    func finish() { lock.withLock { process = nil } }
}
