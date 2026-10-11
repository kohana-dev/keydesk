import Foundation
import CryptoKit

public struct ServiceRequest: Codable, Sendable {
    public let kind: String
    public var project: String?
    public var environment: EnvironmentName?
    public var variable: String?
    public var value: String?
    public init(kind: String, project: String? = nil, environment: EnvironmentName? = nil, variable: String? = nil, value: String? = nil) {
        self.kind = kind; self.project = project; self.environment = environment; self.variable = variable; self.value = value
    }
}

public struct SecretDeposit: Codable, Sendable {
    public let id: UUID
    public let project: String
    public let environment: EnvironmentName
    public let variable: String
    public let value: String
    public init(id: UUID = UUID(), project: String, environment: EnvironmentName, variable: String, value: String) throws {
        guard !project.isEmpty, project.count <= 100, !project.contains("\0"), VaultSnapshot.validVariable(variable), !VaultSnapshot.blockedVariable(variable), !value.isEmpty, value.utf8.count <= 32768, !value.contains("\0") else { throw VaultError.invalidData }
        self.id = id; self.project = project; self.environment = environment; self.variable = variable; self.value = value
    }
    public func validated() throws -> Self {
        try Self(id: id, project: project, environment: environment, variable: variable, value: value)
    }
    public func adding(to original: VaultSnapshot) throws -> VaultSnapshot {
        var next = original
        if next.credentials.contains(where: { $0.id == id }) { return next }
        let matches = next.projects.filter { $0.name == project || $0.id.uuidString.lowercased() == project.lowercased() }
        guard matches.count <= 1 else { throw VaultError.invalidData }
        let target = matches.first ?? Project(name: project, colorIndex: next.projects.count)
        guard !next.bindings.contains(where: { $0.projectID == target.id && $0.environment == environment && $0.variable == variable }) else {
            throw NSError(domain: "Keydesk", code: 1, userInfo: [NSLocalizedDescriptionKey: "같은 변수 이름이 이미 있습니다. 기존 키를 자동으로 덮어쓰지 않습니다."])
        }
        if matches.isEmpty { next.projects.append(target) }
        next.credentials.append(Credential(id: id, name: variable, value: value, provider: ProviderCatalog.inferredProvider(for: variable)))
        next.bindings.append(BindingRecord(projectID: target.id, environment: environment, variable: variable, credentialID: id))
        return try next.validated()
    }
}

/// Ephemeral P-256 ECDH + HKDF-SHA256 + AES-GCM. Only the encrypted vault contains
/// the recipient private key; a locked app needs just the public key to accept new values.
public struct SealedDeposit: Codable, Sendable {
    public let version: Int
    public let recipient: Data
    public let ephemeral: Data
    public let salt: Data
    public var ciphertext: Data
    private static let context = Data("Keydesk.deposit.v1".utf8)
    public static func seal(_ deposit: SecretDeposit, publicKey: Data) throws -> Self {
        _ = try deposit.validated()
        let recipient = try P256.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: context + publicKey + ephemeral.publicKey.rawRepresentation, outputByteCount: 32)
        let encrypted = try AES.GCM.seal(JSONEncoder().encode(deposit), using: key, authenticating: context + publicKey)
        return Self(version: 1, recipient: publicKey, ephemeral: ephemeral.publicKey.rawRepresentation, salt: salt, ciphertext: try encrypted.combined ?? { throw VaultError.invalidData }())
    }
    public func open(privateKey: Data) throws -> SecretDeposit {
        guard version == 1, salt.count == 32, ciphertext.count <= 100000 else { throw VaultError.invalidData }
        let recipientKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        guard recipientKey.publicKey.rawRepresentation == recipient else { throw VaultError.accessDenied }
        let shared = try recipientKey.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(rawRepresentation: ephemeral))
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Self.context + recipient + ephemeral, outputByteCount: 32)
        let data = try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: key, authenticating: Self.context + recipient)
        return try JSONDecoder().decode(SecretDeposit.self, from: data).validated()
    }
}
