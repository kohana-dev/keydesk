import Testing
import Foundation
import Darwin
import KeydeskCore
@testable import KeydeskApp

actor FixtureAPITransport: APITransport {
    var calls = 0
    let reflect: Bool
    init(reflect: Bool = false) { self.reflect = reflect }
    func execute(_ request: APIRequest, provider: APIProvider, secret: String) async throws -> APIResponse {
        calls += 1
        return APIResponse(status: 200, body: reflect ? secret : "{\"fixture\":true}")
    }
}

@Suite(.serialized) @MainActor
struct APIBrokerTests {
    func fixture(_ transport: any APITransport) async throws -> VaultModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("api-model-\(UUID())")
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: MemoryKeyStore(), apiTransport: transport, serve: false, observeSystemEvents: false)
        await model.prepareFirstRun(startNew: true)
        _ = try model.deposit(SecretDeposit(project: "fixture", environment: .production, variable: "CLOUDFLARE_API_TOKEN", value: "DISPOSABLE_BROKER_ONLY_KEY"))
        return model
    }
    func request(method: String = "GET") -> APIRequest {
        APIRequest(project: "fixture", environment: .production, variable: "CLOUDFLARE_API_TOKEN", method: method, url: "https://api.cloudflare.com/client/v4/user/tokens/verify")
    }
    func awaitCompletion(_ model: VaultModel) async throws {
        for _ in 0..<100 { if model.apiTasks.isEmpty { return }; try await Task.sleep(for: .milliseconds(10)) }
        Issue.record("API task did not complete")
    }
    func events(_ fd: Int32) throws -> [CLIEvent] {
        var result: [CLIEvent] = []
        while let line = try SocketTransport.readLine(from: fd, maximum: 2_100_000) { result.append(try JSONDecoder().decode(CLIEvent.self, from: line)) }
        return result
    }
    @Test func productionAuthenticationReuseRevocationAndChangedRequest() async throws {
        let transport = FixtureAPITransport(), model = try await fixture(transport)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: model.store.directory) }
        let keys = try #require(model.keys as? MemoryKeyStore), baseline = keys.authentications
        let (first, client) = try RunnerTests().sockets(); defer { close(client) }
        model.receiveAPI(request(), channel: first)
        #expect(model.apiApproval != nil); #expect(await transport.calls == 0)
        await model.acceptAPI(remember: true); try await awaitCompletion(model)
        #expect(keys.authentications == baseline + 1)
        let output = try events(client)
        #expect(output.contains { $0.kind == "exit" && $0.exitCode == 0 })
        #expect(!String(decoding: try JSONEncoder().encode(output), as: UTF8.self).contains("DISPOSABLE_BROKER_ONLY_KEY"))
        keys.denyAuthentication = true
        let (second, secondClient) = try RunnerTests().sockets(); defer { close(secondClient) }
        model.receiveAPI(request(), channel: second); #expect(model.apiApproval == nil)
        try await awaitCompletion(model)
        #expect(keys.authentications == baseline + 1 && model.apiApprovals.active()[0].remainingUses == 9)
        #expect(try events(secondClient).contains { $0.kind == "exit" && $0.exitCode == 0 })
        #expect(await transport.calls == 2)
        let (changed, changedClient) = try RunnerTests().sockets(); defer { close(changedClient) }
        model.receiveAPI(request(method: "DELETE"), channel: changed); #expect(model.apiApproval != nil); model.rejectAPI()
        model.revokeAPI(model.apiApprovals.active()[0].id)
        let (revoked, revokedClient) = try RunnerTests().sockets(); defer { close(revokedClient) }
        model.receiveAPI(request(), channel: revoked); #expect(model.apiApproval != nil); model.rejectAPI()
        #expect(await transport.calls == 2)
        #expect(model.snapshot?.activities.contains { $0.action.contains("API 완료") } == true)
    }
    @Test func denialLockMutationAndReflectionDoNotReturnKeys() async throws {
        let transport = FixtureAPITransport(reflect: true), model = try await fixture(transport)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: model.store.directory) }
        let keys = try #require(model.keys as? MemoryKeyStore)
        keys.denyAuthentication = true
        let (denied, deniedClient) = try RunnerTests().sockets(); defer { close(deniedClient) }
        model.receiveAPI(request(), channel: denied); await model.acceptAPI(remember: true)
        #expect(await transport.calls == 0); #expect(model.apiApprovals.active().isEmpty)
        keys.denyAuthentication = false
        let (reflected, reflectedClient) = try RunnerTests().sockets(); defer { close(reflectedClient) }
        model.receiveAPI(request(), channel: reflected); await model.acceptAPI(remember: true); try await awaitCompletion(model)
        let output = try events(reflectedClient)
        #expect(output.contains { $0.kind == "error" }); #expect(!output.contains { $0.kind == "stdout" })
        try model.addProject("change"); #expect(model.apiApprovals.active().isEmpty)
        let (pending, pendingClient) = try RunnerTests().sockets(); defer { close(pendingClient) }
        model.receiveAPI(request(), channel: pending); #expect(model.apiApproval != nil)
        model.lock(); #expect(model.apiApproval == nil && model.apiApprovals.active().isEmpty)
        let (locked, lockedClient) = try RunnerTests().sockets(); defer { close(lockedClient) }
        model.receiveAPI(request(), channel: locked)
        #expect(try events(lockedClient).first?.text == "vault_locked")
    }
    @Test func curlConfigurationCannotInjectOptionsOrLeakIntoArguments() throws {
        let req = request(), provider = try APIProvider.resolve(provider: "Cloudflare", request: req)
        let config = try CurlAPITransport.configuration(req, provider: provider, secret: "FAKE_\"_\\_ONLY", address: "1.1.1.1")
        #expect(config.contains("resolve = \"api.cloudflare.com:443:1.1.1.1\""))
        #expect(config.contains("Authorization: Bearer"))
        #expect(throws: (any Error).self) { try CurlAPITransport.configuration(req, provider: provider, secret: "BAD\nurl = evil", address: "1.1.1.1") }
        #expect(throws: (any Error).self) { try CurlAPITransport.configuration(req, provider: provider, secret: "FAKE", address: "127.0.0.1") }
    }
}

actor SlowFixtureAPITransport: APITransport {
    private(set) var entered = false
    func execute(_ request: APIRequest, provider: APIProvider, secret: String) async throws -> APIResponse {
        entered = true
        try await Task.sleep(for: .seconds(30))
        return APIResponse(status: 200, body: "{}")
    }
}

@Suite(.serialized) @MainActor
struct APICancellationTests {
    @Test func lockCancelsInflightAndDoesNotDeliverLateResponse() async throws {
        let helper = APIBrokerTests(), transport = SlowFixtureAPITransport(), model = try await helper.fixture(transport)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: model.store.directory) }
        let (channel, client) = try RunnerTests().sockets(); defer { close(client) }
        model.receiveAPI(helper.request(), channel: channel); await model.acceptAPI(remember: true)
        for _ in 0..<100 { if await transport.entered { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(await transport.entered)
        model.lock(); try await helper.awaitCompletion(model)
        let events = try helper.events(client)
        #expect(events.contains { $0.kind == "error" }); #expect(!events.contains { $0.kind == "stdout" })
        #expect(model.apiRunning.isEmpty && model.apiApprovals.active().isEmpty)
    }
    @Test func disconnectCancelsBeforeReturningData() async throws {
        let helper = APIBrokerTests(), transport = SlowFixtureAPITransport(), model = try await helper.fixture(transport)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: model.store.directory) }
        let (channel, client) = try RunnerTests().sockets()
        model.receiveAPI(helper.request(), channel: channel); await model.acceptAPI(remember: true)
        for _ in 0..<100 { if await transport.entered { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(await transport.entered)
        close(client)
        try await helper.awaitCompletion(model)
        #expect(model.apiRunning.isEmpty)
    }
}

@Suite(.serialized) @MainActor
struct APIDemoIsolationTests {
    @Test func defaultDemoCanStoreValuesAndFilesWithoutSystemKeychain() throws {
        let model = VaultModel(demo: true, serve: false, observeSystemEvents: false)
        defer { model.shutdown() }
        #expect(model.keys is DemoKeyStore)
        _ = try model.deposit(SecretDeposit(project: "demo-deposit", environment: .development, variable: "CLOUDFLARE_API_TOKEN", value: "DISPOSABLE_DEMO_VALUE"))
        let file = try SecretFile(name: "fake.p8", data: Data([0, 255, 13, 10]))
        _ = try model.deposit(SecretDeposit(project: "demo-deposit", environment: .development, variable: "APPLE_KEY_PATH", file: file))
        #expect(model.snapshot?.credentials.contains { $0.currentFile?.data == file.data } == true)
        #expect(model.keys.knownRecoveryVaults().isEmpty)
    }
}
