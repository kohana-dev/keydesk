import Foundation

/// Stable, local identities keep editor rows bound to the right field while typing.
public struct SecretField: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id; self.key = key; self.value = value
    }
}
