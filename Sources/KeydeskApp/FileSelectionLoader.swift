import Foundation
import Observation
import KeydeskCore

/// One user selection. File-provider waits run on a worker; only the current selection is published.
@MainActor @Observable
final class FileSelectionLoader<Value: Sendable> {
    private(set) var isLoading = false
    private(set) var failed = false
    @ObservationIgnored private var selection = UUID()
    @ObservationIgnored private let read: @Sendable (URL) throws -> Value

    init(read: @escaping @Sendable (URL) throws -> Value) { self.read = read }

    func cancel() {
        selection = UUID()
        isLoading = false
        failed = false
    }

    @discardableResult
    func load(_ url: URL, onSuccess: @escaping @MainActor (Value) -> Void = { _ in }) -> Task<Value?, Never> {
        let token = UUID(), read = read
        selection = token
        isLoading = true
        failed = false
        return Task {
            do {
                let value = try await BackgroundIO.run {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try read(url)
                }
                guard token == selection else { return nil }
                isLoading = false
                guard !Task.isCancelled else { return nil }
                onSuccess(value)
                return value
            } catch {
                guard token == selection else { return nil }
                isLoading = false
                failed = !Task.isCancelled
                return nil
            }
        }
    }
}

struct DotenvFileSelection: Sendable {
    let name: String
    let rows: [DotenvRow]

    static func read(at url: URL) throws -> Self {
        let file = try SecretFile.read(at: url)
        guard let text = String(data: file.data, encoding: .utf8) else { throw VaultError.invalidData }
        return Self(name: file.name, rows: DotenvParser.parse(text))
    }
}
