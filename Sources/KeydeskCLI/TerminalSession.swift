import Foundation
import Darwin
import KeydeskCore

final class TerminalSession: @unchecked Sendable {
    private var original: termios?
    private var terminatingCode: Int32?
    private let lock = NSLock()
    func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard isatty(STDIN_FILENO) == 1 else { throw VaultError.invalidData }
        var attributes = termios()
        guard tcgetattr(STDIN_FILENO, &attributes) == 0 else { throw POSIXError(.EIO) }
        original = attributes; cfmakeraw(&attributes)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &attributes) == 0 else { throw POSIXError(.EIO) }
    }
    func restore() {
        lock.lock(); defer { lock.unlock() }
        if var original { _ = tcsetattr(STDIN_FILENO, TCSANOW, &original) }
        original = nil
    }
    var terminationExitCode: Int32? {
        lock.lock(); defer { lock.unlock() }
        return terminatingCode
    }
    func markTerminated(code: Int32) {
        lock.lock(); terminatingCode = code; lock.unlock()
        restore()
    }
    static func size() -> CLIInput {
        var size = winsize()
        _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &size)
        return CLIInput(kind: "resize", columns: size.ws_col == 0 ? 80 : size.ws_col, rows: size.ws_row == 0 ? 24 : size.ws_row)
    }
}
