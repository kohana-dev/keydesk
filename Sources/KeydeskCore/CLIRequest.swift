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
    public init(project: String, environment: EnvironmentName, command: [String], directory: String, stdinKey: String?, variables: [String]? = nil, interactive: Bool = false, keepRunning: Bool = false, fileVariables: [String]? = nil) {
        self.project = project; self.environment = environment; self.command = command; self.directory = directory; self.stdinKey = stdinKey
        self.variables = variables; self.fileVariables = fileVariables; self.interactive = interactive; self.keepRunning = keepRunning
    }
    public func selectedSecrets(from available: [String: String]) throws -> [String: String] {
        let names = variables ?? []
        guard !names.isEmpty || stdinKey != nil || fileVariables?.isEmpty == false, names.count <= 100,
              Set(names).count == names.count, names.allSatisfy({ available[$0] != nil }),
              !(interactive == true && stdinKey != nil) else { throw VaultError.accessDenied }
        var selected = available.filter { names.contains($0.key) }
        if let stdinKey {
            guard let value = available[stdinKey] else { throw VaultError.accessDenied }
            selected[stdinKey] = value
        }
        for name in names where name != stdinKey {
            guard !Self.executionControlVariables.contains(name),
                  !name.hasPrefix("DYLD_"), !name.hasPrefix("LD_") else { throw VaultError.accessDenied }
        }
        return selected
    }
    public func selectedFiles(from available: [String: SecretFile]) throws -> [String: SecretFile] {
        let names = fileVariables ?? []
        guard names.count <= 16, Set(names).count == names.count,
              names.allSatisfy({ available[$0] != nil && !VaultSnapshot.blockedVariable($0) && !Self.executionControlVariables.contains($0) }),
              Set(names).isDisjoint(with: Set(variables ?? [])), !names.contains(stdinKey ?? "") else { throw VaultError.accessDenied }
        return available.filter { names.contains($0.key) }
    }
    private static let executionControlVariables: Set<String> = [
        "PATH", "HOME", "USER", "LOGNAME", "TMPDIR", "TERM", "SHELL", "ENV", "BASH_ENV",
        "PYTHONPATH", "PYTHONHOME", "NODE_OPTIONS", "RUBYOPT", "PERL5OPT", "PERL5LIB"
    ]
}
