import Foundation
import CryptoKit

public struct VaultSnapshot: Codable, Sendable {
    public var revision: UInt64 = 0
    public var projects: [Project] = []
    public var credentials: [Credential] = []
    public var bindings: [BindingRecord] = []
    public var activities: [ActivityRecord] = []
    public var backup: BackupSettings?
    /// Copy of the recovery key, encrypted with the rest of the vault so Settings can show it again.
    /// It only unwraps the data key that already protects this payload, so it adds no new exposure.
    public var depositPrivateKey: Data?
    public var recoveryCode: String?
    public init() {}

    public mutating func record(_ action: String) {
        activities.insert(ActivityRecord(action: action), at: 0)
        activities = Array(activities.prefix(200))
    }

    public func validated() throws -> Self {
        guard Set(projects.map(\.id)).count == projects.count,
              Set(credentials.map(\.id)).count == credentials.count,
              Set(bindings.map(\.id)).count == bindings.count else { throw VaultError.invalidData }
        var seen = Set<String>()
        for credential in credentials {
            guard !credential.name.isEmpty, !credential.versions.isEmpty,
                  credential.versions.allSatisfy({ $0.value.utf8.count <= 65_536 && !$0.value.contains("\0") }),
                  credential.versions.contains(where: { $0.id == credential.currentVersionID }),
                  Set(credential.versions.map(\.id)).count == credential.versions.count else { throw VaultError.invalidData }
        }
        guard projects.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 100 }) else { throw VaultError.invalidData }
        if let depositPrivateKey { _ = try P256.KeyAgreement.PrivateKey(rawRepresentation: depositPrivateKey) }
        if let recoveryCode { _ = try RecoveryCode.decode(recoveryCode) }
        for binding in bindings {
            guard projects.contains(where: { $0.id == binding.projectID }),
                  credentials.contains(where: { $0.id == binding.credentialID }),
                  EnvironmentName.allCases.contains(binding.environment),
                  Self.validVariable(binding.variable),
                  seen.insert("\(binding.projectID)/\(binding.environment.rawValue)/\(binding.variable)").inserted else { throw VaultError.invalidData }
        }
        return self
    }

    public static func validVariable(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }

    public func environment(projectID: UUID, environment: EnvironmentName) throws -> [String: String] {
        guard projects.contains(where: { $0.id == projectID }) else { throw VaultError.invalidData }
        var result = [String: String]()
        for binding in bindings where binding.projectID == projectID && binding.environment == environment {
            guard !Self.blockedVariable(binding.variable),
                  let credential = credentials.first(where: { $0.id == binding.credentialID }),
                  let value = credential.currentValue, !value.contains("\0") else { throw VaultError.unsafeEnvironment }
            result[binding.variable] = value
        }
        return result
    }

    public static func blockedVariable(_ value: String) -> Bool {
        let key = value.uppercased()
        return ["PATH", "HOME", "SHELL", "ENV", "BASH_ENV", "ZDOTDIR", "IFS", "NODE_OPTIONS", "NODE_PATH", "PYTHONPATH", "PYTHONHOME", "RUBYOPT", "PERL5OPT", "JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "GIT_CONFIG_COUNT", "GIT_CONFIG_SYSTEM", "GIT_CONFIG_GLOBAL"].contains(key)
            || key.hasPrefix("DYLD_") || key.hasPrefix("LD_")
    }
}
