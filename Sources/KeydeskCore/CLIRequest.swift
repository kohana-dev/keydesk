import Foundation

public struct CLIRequest: Codable, Sendable, Equatable {
    public let project: String
    public let environment: EnvironmentName
    public let command: [String]
    public let directory: String
    public let stdinKey: String?
    public let variables: [String]?
    public let fileVariables: [String]?
    public let interactive: Bool?
    public let keepRunning: Bool?
    public let selections: [SecretFieldSelection]?
    public init(project: String, environment: EnvironmentName, command: [String], directory: String, stdinKey: String?, variables: [String]? = nil, interactive: Bool = false, keepRunning: Bool = false, fileVariables: [String]? = nil, selections: [SecretFieldSelection]? = nil) {
        self.project = project; self.environment = environment; self.command = command; self.directory = directory; self.stdinKey = stdinKey
        self.variables = variables; self.fileVariables = fileVariables; self.interactive = interactive; self.keepRunning = keepRunning
        self.selections = selections
    }
    public func selectedSecrets(from available: [String: String]) throws -> [String: String] {
        try validateSelectionLayout()
        let names = (variables ?? []) + (selections ?? []).map(\.variable)
        guard !names.isEmpty || stdinKey != nil || fileVariables?.isEmpty == false, names.count <= 100,
              Set(names).count == names.count, names.allSatisfy({ VaultSnapshot.validVariable($0) && available[$0] != nil }),
              !(interactive == true && stdinKey != nil) else { throw VaultError.accessDenied }
        var selected = available.filter { names.contains($0.key) }
        if let stdinKey {
            guard let value = available[stdinKey] else { throw VaultError.accessDenied }
            selected[stdinKey] = value
        }
        for name in names where name != stdinKey {
            guard !VaultSnapshot.blockedVariable(name), !Self.executionControlVariables.contains(name.uppercased()) else {
                throw VaultError.accessDenied
            }
        }
        return selected
    }
    public func selectedFiles(from available: [String: SecretFile]) throws -> [String: SecretFile] {
        try validateSelectionLayout()
        let names = fileVariables ?? []
        guard names.count <= 16, Set(names).count == names.count,
              names.allSatisfy({ VaultSnapshot.validVariable($0) && available[$0] != nil && !VaultSnapshot.blockedVariable($0) && !Self.executionControlVariables.contains($0.uppercased()) }),
              Set(names).isDisjoint(with: Set((variables ?? []) + (selections ?? []).map(\.variable))), !names.contains(stdinKey ?? "") else { throw VaultError.accessDenied }
        return available.filter { names.contains($0.key) }
    }
    private func validateSelectionLayout() throws {
        let selections = selections ?? []
        try SecretFieldSelection.validate(selections)
        let targets = Set(selections.map(\.variable))
        guard targets.isDisjoint(with: Set(variables ?? [])),
              targets.isDisjoint(with: Set(fileVariables ?? [])),
              Set(variables ?? []).isDisjoint(with: Set(fileVariables ?? [])),
              targets.allSatisfy({ !Self.executionControlVariables.contains($0.uppercased()) }) else {
            throw VaultError.accessDenied
        }
        if let stdinKey { guard VaultSnapshot.validVariable(stdinKey) else { throw VaultError.accessDenied } }
    }
    private static let executionControlVariables: Set<String> = [
        "PATH", "HOME", "USER", "LOGNAME", "TMPDIR", "TERM", "SHELL", "ENV", "BASH_ENV",
        "PYTHONPATH", "PYTHONHOME", "NODE_OPTIONS", "RUBYOPT", "PERL5OPT", "PERL5LIB"
    ]
}
