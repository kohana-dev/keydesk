import Testing
import Foundation
import KeydeskCore
@testable import KeydeskApp

@Suite(.serialized) @MainActor
struct DepositTests {
    @Test func lockedDepositIsEncryptedAndMergedAfterAuthentication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("deposit-test-\(UUID())")
        let keyStore = MemoryKeyStore()
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: keyStore, serve: false, observeSystemEvents: false)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun()
        model.lock()
        let payload = try SecretDeposit(project: "fixture", environment: .development, variable: "API_KEY", value: "DISPOSABLE_LOCKED_SENTINEL")
        let before = keyStore.authentications
        let result = try model.deposit(payload)
        #expect(result.hasPrefix("queued") && model.snapshot == nil)
        #expect(keyStore.authentications == before)
        let directory = root.appendingPathComponent("deposits")
        let url = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains(payload.value))
        keyStore.denyAuthentication = true
        await model.unlock()
        #expect(model.snapshot == nil && FileManager.default.fileExists(atPath: url.path))
        keyStore.denyAuthentication = false
        await model.unlock()
        #expect(model.snapshot?.credentials.first?.currentValue == payload.value)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let duplicate = try SecretDeposit(project: "fixture", environment: .development, variable: "API_KEY", value: "OTHER")
        model.lock()
        _ = try model.deposit(duplicate)
        await model.unlock()
        #expect(model.snapshot?.credentials.first?.currentValue == payload.value)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
    }
    @Test func productionRunRequiresAuthenticationAndCannotBeRemembered() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prod-auth-test-\(UUID())")
        let keys = MemoryKeyStore()
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: keys, serve: false, observeSystemEvents: false)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun()
        _ = try model.deposit(SecretDeposit(project: "fixture", environment: .production, variable: "PROD_KEY", value: "FAKE_PRODUCTION_ONLY"))
        let invocation = CLIRequest(project: "fixture", environment: .production, command: ["/usr/bin/true"], directory: "/tmp", stdinKey: nil, variables: ["PROD_KEY"])
        let baseline = keys.authentications
        keys.denyAuthentication = true
        let (denied, deniedClient) = try RunnerTests().sockets()
        defer { denied.finish(); close(deniedClient) }
        model.receive(try CLIApproval(request: invocation, channel: denied))
        await model.acceptCLI(remember: true)
        var deniedEvents: [String] = []
        while let line = try SocketTransport.readLine(from: deniedClient) { deniedEvents.append(try JSONDecoder().decode(CLIEvent.self, from: line).kind) }
        #expect(keys.authentications == baseline + 1)
        #expect(deniedEvents.contains("error") && !deniedEvents.contains("started"))
        keys.denyAuthentication = false
        let (accepted, acceptedClient) = try RunnerTests().sockets()
        defer { accepted.finish(); close(acceptedClient) }
        model.receive(try CLIApproval(request: invocation, channel: accepted))
        await model.acceptCLI(remember: true)
        #expect(keys.authentications == baseline + 2)
        let (again, againClient) = try RunnerTests().sockets()
        defer { again.finish(); close(againClient) }
        model.receive(try CLIApproval(request: invocation, channel: again))
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.approval != nil)
        model.rejectCLI()
    }

}
