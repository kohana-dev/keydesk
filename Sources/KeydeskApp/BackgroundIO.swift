import Foundation

/// Blocking filesystem work uses dedicated threads rather than Swift's cooperative executor.
enum BackgroundIO {
    private static let queue = DispatchQueue(label: "com.keydesk.file-io", qos: .utility, attributes: .concurrent)
    static func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: operation)) }
        }
    }
}
