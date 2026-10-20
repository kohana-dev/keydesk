import Foundation

/// An invocation-scoped mapping from one explicitly selected document field to an output variable.
/// It is part of the approved request, never a persisted vault binding.
public struct SecretFieldSelection: Codable, Sendable, Equatable, Hashable {
    public let variable: String
    public let source: String
    public let pointer: String

    public init(variable: String, source: String, pointer: String) {
        self.variable = variable; self.source = source; self.pointer = pointer
    }

    /// `OUTPUT=SOURCE#/path`; the empty pointer after `#` selects a scalar JSON root.
    public static func parse(_ argument: String) throws -> Self {
        guard let equals = argument.firstIndex(of: "=") else { throw VaultError.accessDenied }
        let remainder = argument[argument.index(after: equals)...]
        guard let hash = remainder.firstIndex(of: "#") else { throw VaultError.accessDenied }
        return try Self(variable: String(argument[..<equals]), source: String(remainder[..<hash]),
                        pointer: String(remainder[remainder.index(after: hash)...])).validated()
    }

    @discardableResult
    public func validated() throws -> Self {
        guard VaultSnapshot.validVariable(variable), !VaultSnapshot.blockedVariable(variable),
              VaultSnapshot.validVariable(source), !VaultSnapshot.blockedVariable(source) else {
            throw VaultError.accessDenied
        }
        _ = try SecretValueSelector.pointerTokens(pointer)
        return self
    }

    public static func validate(_ selections: [Self]) throws {
        guard selections.count <= 100, Set(selections.map(\.variable)).count == selections.count else {
            throw VaultError.accessDenied
        }
        for selection in selections { _ = try selection.validated() }
    }
}
