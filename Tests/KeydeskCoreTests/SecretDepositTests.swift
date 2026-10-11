import Testing
import Foundation
import CryptoKit
@testable import KeydeskCore

struct SecretDepositTests {
    @Test func publicKeySealingRejectsWrongKeysAndTampering() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let payload = try SecretDeposit(project: "fixture", environment: .production, variable: "API_KEY", value: "DISPOSABLE_DEPOSIT_SENTINEL")
        var sealed = try SealedDeposit.seal(payload, publicKey: recipient.publicKey.rawRepresentation)
        let bytes = try JSONEncoder().encode(sealed)
        #expect(!String(decoding: bytes, as: UTF8.self).contains(payload.value))
        let restored = try sealed.open(privateKey: recipient.rawRepresentation)
        #expect(restored.id == payload.id && restored.value == payload.value)
        #expect(throws: (any Error).self) { try sealed.open(privateKey: P256.KeyAgreement.PrivateKey().rawRepresentation) }
        sealed.ciphertext[sealed.ciphertext.startIndex] ^= 1
        #expect(throws: (any Error).self) { try sealed.open(privateKey: recipient.rawRepresentation) }
    }
    @Test func insertsOnceAndNeverOverwritesAnExistingVariable() throws {
        let payload = try SecretDeposit(project: "fixture", environment: .development, variable: "API_KEY", value: "FAKE")
        let first = try payload.adding(to: VaultSnapshot())
        let replay = try payload.adding(to: first)
        #expect(replay.credentials.count == 1 && replay.bindings.count == 1)
        let collision = try SecretDeposit(project: "fixture", environment: .development, variable: "API_KEY", value: "OTHER")
        #expect(throws: (any Error).self) { try collision.adding(to: first) }
        #expect(first.credentials.first?.currentValue == "FAKE")
        #expect(throws: (any Error).self) { try SecretDeposit(project: "fixture", environment: .development, variable: "PATH", value: "BAD") }
    }
}
