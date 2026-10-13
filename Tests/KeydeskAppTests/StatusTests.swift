import Testing
import Foundation
import Darwin
import KeydeskCore
@testable import KeydeskApp

@Suite(.serialized) @MainActor
struct StatusTests {
    @Test func statusNeverReturnsSecretsAndReportsLockedQueue() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("status-test-\(UUID())")
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: MemoryKeyStore(), serve: false, observeSystemEvents: false)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun(startNew: true)
        _ = try model.deposit(SecretDeposit(project: "PRIVATE_PROJECT_SENTINEL", environment: .development, variable: "PRIVATE_VARIABLE_SENTINEL", value: "PRIVATE_VALUE_SENTINEL"))
        let unlocked = try await query(model)
        #expect(unlocked["locked"] == .bool(false))
        #expect(unlocked["backup"] == .string("pending"))
        model.lock()
        _ = try model.deposit(SecretDeposit(project: "OTHER_PRIVATE_PROJECT", environment: .development, variable: "PENDING_SECRET", value: "PENDING_VALUE"))
        let locked = try await query(model)
        #expect(locked["locked"] == .bool(true))
        #expect(locked["pendingDeposits"] == .number(1))
        #expect(locked["backup"] == .string("unknown_locked"))
        #expect(locked["cloudUpload"] == .string("unknown_locked"))
    }
    private func query(_ model: VaultModel) async throws -> JSONValue {
        let (channel, client) = try RunnerTests().sockets()
        defer { channel.finish(); close(client) }
        await model.receiveService(ServiceRequest(kind: "status"), channel: channel)
        let event = try JSONDecoder().decode(CLIEvent.self, from: #require(try SocketTransport.readLine(from: client)))
        let data = try #require(event.data)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("PRIVATE") && !text.contains("SECRET") && !text.contains("VALUE"))
        let result = try JSONDecoder().decode(JSONValue.self, from: data)
        let exit = try JSONDecoder().decode(CLIEvent.self, from: #require(try SocketTransport.readLine(from: client)))
        #expect(exit.kind == "exit" && exit.exitCode == 0)
        return result
    }
}
