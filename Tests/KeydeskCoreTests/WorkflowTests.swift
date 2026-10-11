import Testing
import Foundation
import CryptoKit
@testable import KeydeskCore

struct WorkflowTests {
    func fixture() throws -> (VaultSnapshot, VaultEnvelope, SymmetricKey, String) {
        let snapshot = VaultSnapshot(), header = VaultHeader(), key = SymmetricKey(size: .bits256)
        let recovery = SymmetricKey(size: .bits256)
        let wrapped = try VaultCrypto.wrap(key, recoveryKey: recovery, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        return (snapshot, try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key), key, RecoveryCode.encode(recovery))
    }
    @Test func keyRotationPreservesHistoricalRecoveryAndInvalidatesNewEpoch() throws {
        let (snapshot, old, key, oldCode) = try fixture()
        let newCode = RecoveryCode.encode(SymmetricKey(size: .bits256))
        for rotatesData in [false, true] {
            let (updated, newKey) = try KeyRotation.rotate(snapshot, current: old, newRecoveryCode: newCode, rotateDataKey: rotatesData, currentKey: key)
            #expect(updated.header.vaultID == old.header.vaultID)
            #expect((updated.header.keyEpoch != old.header.keyEpoch) == rotatesData)
            #expect(try VaultCrypto.open(updated, key: newKey).revision == 1)
            #expect(throws: (any Error).self) { try VaultCrypto.recover(updated, code: oldCode) }
            #expect(try VaultCrypto.open(updated, key: VaultCrypto.recover(updated, code: newCode)).revision == 1)
            #expect(try VaultCrypto.open(old, key: VaultCrypto.recover(old, code: oldCode)).revision == 0)
            if rotatesData { #expect(throws: (any Error).self) { try VaultCrypto.open(updated, key: key) } }
        }
    }
    @Test func verifiedBackupRetentionPreservesUnknownAndOtherEpochFiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-backup-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, envelope, key, _) = try fixture()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let unknown = root.appendingPathComponent("Keydesk-\(envelope.header.vaultID)-unknown.keydesk")
        try Data("unknown-format".utf8).write(to: unknown)
        let unrelated = root.appendingPathComponent("personal.txt"); try Data("keep".utf8).write(to: unrelated)
        for day in (0..<40).reversed() { _ = try BackupManager.save(envelope, key: key, directory: root, now: now.addingTimeInterval(Double(-day) * 86400)) }
        let names = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        #expect(names.count <= 13 && names.count >= 9)
        #expect(FileManager.default.fileExists(atPath: unknown.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        for file in names where file.lastPathComponent != unknown.lastPathComponent && file.lastPathComponent != unrelated.lastPathComponent {
            #expect(try VaultCrypto.open(VaultFileStore.read(at: file), key: key).revision == 0)
            let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o600)
        }
    }
    @Test func grantsRejectEveryScopeMismatchAndExhaustion() throws {
        let now = Date(), project = UUID(), connection = UUID()
        var grant = AccessGrant(session: "s", projectID: project, environment: .development, connectionID: connection, operation: "github_repo_info", resource: "owner/repo", duration: 10, maximumCalls: 1, now: now)
        for (session, p, env, c, op, resource, date) in [
            ("other", project, EnvironmentName.development, connection, "github_repo_info", "owner/repo", now),
            ("s", UUID(), .development, connection, "github_repo_info", "owner/repo", now),
            ("s", project, .production, connection, "github_repo_info", "owner/repo", now),
            ("s", project, .development, UUID(), "github_repo_info", "owner/repo", now),
            ("s", project, .development, connection, "check_connection", "owner/repo", now),
            ("s", project, .development, connection, "github_repo_info", "owner/other", now),
            ("s", project, .development, connection, "github_repo_info", "owner/repo", now.addingTimeInterval(10))
        ] { #expect(throws: (any Error).self) { try grant.reserve(session: session, projectID: p, environment: env, connectionID: c, operation: op, resource: resource, now: date) } }
        #expect(grant.usedCalls == 0)
        try grant.reserve(session: "s", projectID: project, environment: .development, connectionID: connection, operation: "github_repo_info", resource: "owner/repo", now: now)
        #expect(throws: (any Error).self) { try grant.reserve(session: "s", projectID: project, environment: .development, connectionID: connection, operation: "github_repo_info", resource: "owner/repo", now: now) }
    }
    @Test func providerLabelsShownToAIAreFixedNames() {
        #expect(ProviderName.canonical("UNTRUSTED_SECRET_IN_PROVIDER_LABEL") == "Custom")
        #expect(ProviderName.canonical(" openai ") == "OpenAI")
    }
    @Test func approvalWarnsAboutCommandsThatCanLeakKeys() {
        for command in [["/bin/sh", "-c", "echo $KEY | base64"], ["bash", "-lc", "x"], ["/usr/bin/env", "FOO=1", "zsh", "-c", "x"], ["python3.12", "-c", "x"],
                        ["node", "-e", "x"], ["curl", "https://example.com"], ["printenv"], ["env"], ["echo", "$KEY"]] {
            #expect(!CommandRisk.warnings(for: command).isEmpty, "\(command)")
        }
        for command in [["npm", "run", "dev"], ["/usr/bin/python3", "manage.py", "runserver"], ["node", "server.js"], ["supabase", "db", "push"], ["sh", "deploy.sh"]] {
            #expect(CommandRisk.warnings(for: command).isEmpty, "\(command)")
        }
    }
    @Test func promptStreamsBeforeProcessExit() {
        var redactor = StreamingRedactor(secrets: ["VERY_LONG_SECRET_SENTINEL"])
        #expect(String(decoding: redactor.push(Data("Enter API key: ".utf8)), as: UTF8.self) == "Enter API key: ")
        #expect(redactor.push(Data("VERY_LONG_".utf8)).isEmpty)
        #expect(String(decoding: redactor.push(Data("SECRET_SENTINEL\n".utf8)), as: UTF8.self) == "[REDACTED]\n")
    }
    @Test func installerIsIdempotentAndRefusesExistingFiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-installer-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("tool")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let link = try CLIInstaller.install(executable: executable, home: root)
        #expect(try CLIInstaller.install(executable: executable, home: root) == link)
        let bundled = root.appendingPathComponent("bundled-tool")
        try FileManager.default.copyItem(at: executable, to: bundled)
        #expect(try CLIInstaller.install(executable: bundled, home: root) == link)
        #expect(link.resolvingSymlinksInPath() == bundled)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/missing/keydesk")
        #expect(throws: (any Error).self) { try CLIInstaller.install(executable: executable, home: root) }
    }
}
