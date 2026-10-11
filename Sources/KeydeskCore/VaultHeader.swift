import Foundation

public struct VaultHeader: Codable, Equatable, Sendable {
    public let format: Int
    public let vaultID: UUID
    public var revision: UInt64
    public let keyEpoch: UUID
    public let algorithm: String
    public init(vaultID: UUID = UUID()) {
        format = 1; self.vaultID = vaultID; revision = 0; keyEpoch = UUID(); algorithm = "AES-256-GCM"
    }
}
