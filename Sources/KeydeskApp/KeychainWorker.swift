import Foundation
import LocalAuthentication

/// Security.framework can wait on securityd or iCloud. Keep those waits off the UI executor
/// and serialize requests so protected Keychain mutations retain their original order.
final class KeychainWorker: Sendable {
    private let queue = DispatchQueue(label: "com.keydesk.keychain", qos: .userInitiated)

    func run<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: operation()) }
        }
    }

    func runThrowing<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: operation)) }
        }
    }
}

/// A completed authentication context is handed to one serialized Security call. No UI or
/// other task changes this context while that call is in progress; it is never re-evaluated here.
final class KeychainAuthenticationContext: @unchecked Sendable {
    let context: LAContext?
    init(_ context: LAContext?) { self.context = context }
}
