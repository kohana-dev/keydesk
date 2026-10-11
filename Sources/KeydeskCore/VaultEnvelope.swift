import Foundation

public struct VaultEnvelope: Codable, Sendable {
    public var header: VaultHeader
    public let recoveryWrappedKey: Data
    public let ciphertext: Data
    public init(header: VaultHeader, recoveryWrappedKey: Data, ciphertext: Data) {
        self.header = header; self.recoveryWrappedKey = recoveryWrappedKey; self.ciphertext = ciphertext
    }
}
