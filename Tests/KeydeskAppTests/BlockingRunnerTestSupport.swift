import Foundation
import KeydeskCore
@testable import KeydeskApp

/// Socket reads and waitUntilExit block an OS thread. Keep them off Swift Testing's
/// cooperative executor while retaining concurrency between independent runner suites.
enum BlockingRunnerTestSupport {
    static func start(_ request: CLIRequest, secrets: [String: String], channel: CLIChannel,
                      files: [String: SecretFile] = [:]) async throws -> RunningCommand {
        try await run {
            try CommandRunner.start(request, secrets: secrets, channel: channel, files: files, completion: {})
        }
    }
    static func readLine(from descriptor: Int32) async throws -> Data? {
        try await run { try SocketTransport.readLine(from: descriptor) }
    }
    static func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
