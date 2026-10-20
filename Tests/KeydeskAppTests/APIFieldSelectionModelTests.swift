import Foundation
import Darwin
import Testing
import KeydeskCore
@testable import KeydeskApp

private actor SelectedFieldTransport: APITransport {
    private(set) var requests: [APIRequest] = []
    private(set) var values: [String] = []
    let reflect: Bool
    init(reflect: Bool = false) { self.reflect = reflect }
    func execute(_ request: APIRequest, provider: APIProvider, secret: String) async throws -> APIResponse {
        requests.append(request); values.append(secret)
        return APIResponse(status: 200, body: reflect ? secret : #"{"synthetic":true}"#)
    }
}

@Suite(.serialized) @MainActor
struct APIFieldSelectionModelTests {
    private let helper = APIBrokerTests()
    private let projectName = "Synthetic field selection"
    private let content = #"{"services":{"primary":"SYNTHETIC_PRIMARY_TOKEN","secondary":"SYNTHETIC_SECONDARY_TOKEN"},"untouched":"SYNTHETIC_NEVER_DELIVERED","number":42,"boolean":true,"null":null,"array":["SYNTHETIC_ARRAY_TOKEN"],"empty":"","unsafe":"BAD\r\nX-Header: injected"}"#

    private func fixture(transport: SelectedFieldTransport, format: SecretFormat = .json, provider: String = "Other", value: String? = nil) async throws -> (VaultModel, Credential) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("api-selected-field-\(UUID())")
        let model = VaultModel(directory: directory, defaultBackupDirectory: nil, keys: MemoryKeyStore(), apiTransport: transport, serve: false, observeSystemEvents: false)
        await model.prepareFirstRun(startNew: true)
        try model.addProject(projectName)
        model.selectedProject = try #require(model.snapshot?.projects.first?.id)
        try model.addCredential(name: "Synthetic service settings", value: value ?? content, provider: provider, account: "", note: "", variable: "SETTINGS", format: format)
        return (model, try #require(model.snapshot?.credentials.last))
    }

    private func cleanup(_ model: VaultModel) { model.shutdown(); try? FileManager.default.removeItem(at: model.store.directory) }
    private func request(field: String? = "/services/primary", provider: String? = "OpenAI", url: String = "https://api.openai.com/v1/models") -> APIRequest {
        APIRequest(project: projectName, environment: .development, variable: "SETTINGS", method: "GET", url: url, field: field, provider: provider)
    }

    @Test func onlySelectedJSONStringOrKeyValueEntryReachesTheTransport() async throws {
        for format in [SecretFormat.json, .keyValue] {
            let transport = SelectedFieldTransport()
            let value = format == .keyValue ? #"{"primary":"SYNTHETIC_PRIMARY_TOKEN","untouched":"SYNTHETIC_NEVER_DELIVERED"}"# : content
            let (model, credential) = try await fixture(transport: transport, format: format, value: value)
            defer { cleanup(model) }
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            model.receiveAPI(request(field: format == .json ? "/services/primary" : "/primary"), channel: channel)
            let approval = try #require(model.apiApproval)
            #expect(approval.credentialID == credential.id && approval.versionID == credential.currentVersionID)
            #expect(approval.provider.name == "OpenAI" && approval.request.provider == "OpenAI")
            #expect(approval.credentialName == credential.name && approval.format == format)
            await model.acceptAPI(remember: true); try await helper.awaitCompletion(model)
            #expect(await transport.values == ["SYNTHETIC_PRIMARY_TOKEN"])
            let output = try helper.events(client)
            #expect(output.contains { $0.kind == "exit" && $0.exitCode == 0 })
            let encoded = String(decoding: try JSONEncoder().encode(output), as: UTF8.self)
            #expect(!encoded.contains("SYNTHETIC_PRIMARY_TOKEN") && !encoded.contains("SYNTHETIC_NEVER_DELIVERED"))
            let activities = try #require(model.snapshot?.activities.map(\.action).joined(separator: "\n"))
            #expect(!activities.contains("SYNTHETIC_PRIMARY_TOKEN") && !activities.contains("SYNTHETIC_NEVER_DELIVERED"))
        }
    }

    @Test func selectedFieldChangesNeedFreshApprovalAndCanonicalProviderCanReuseTheSameField() async throws {
        let transport = SelectedFieldTransport(), (model, _) = try await fixture(transport: transport)
        defer { cleanup(model) }
        let (first, firstClient) = try RunnerTests().sockets(); defer { first.finish(); close(firstClient) }
        model.receiveAPI(request(), channel: first); await model.acceptAPI(remember: true); try await helper.awaitCompletion(model)
        _ = try helper.events(firstClient)
        let (repeatCall, repeatClient) = try RunnerTests().sockets(); defer { repeatCall.finish(); close(repeatClient) }
        model.receiveAPI(request(provider: " openai "), channel: repeatCall)
        #expect(model.apiApproval == nil)
        try await helper.awaitCompletion(model); _ = try helper.events(repeatClient)
        #expect(await transport.values == ["SYNTHETIC_PRIMARY_TOKEN", "SYNTHETIC_PRIMARY_TOKEN"])
        let (changed, changedClient) = try RunnerTests().sockets(); defer { changed.finish(); close(changedClient) }
        model.receiveAPI(request(field: "/services/secondary"), channel: changed)
        #expect(model.apiApproval?.request.field == "/services/secondary")
        #expect(await transport.requests.count == 2)
        model.rejectAPI(); _ = try helper.events(changedClient)
    }

    @Test func invalidSelectionsWholeDocumentsAndUnsafeHeadersAreDeniedEvenDuringAllowAll() async throws {
        let transport = SelectedFieldTransport(), (model, _) = try await fixture(transport: transport)
        defer { cleanup(model) }
        await model.startTimedApproval(minutes: 1)
        try #require(model.timedApprovalIsActive)
        let invalid = [
            request(field: nil, provider: nil), request(field: ""), request(field: "/services"),
            request(field: "/array"), request(field: "/number"), request(field: "/boolean"), request(field: "/null"),
            request(field: "/empty"), request(field: "/unsafe"), request(field: "/missing"), request(field: "/bad~2escape"),
            request(provider: nil), request(provider: "Unsupported"), request(url: "https://evil.invalid/"),
        ]
        for request in invalid {
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            model.receiveAPI(request, channel: channel)
            #expect(model.apiApproval == nil)
            let events = try helper.events(client)
            #expect(events.contains { $0.kind == "error" } && !events.contains { $0.kind == "stdout" })
        }
        #expect(await transport.requests.isEmpty)
        let (array, arrayClient) = try RunnerTests().sockets(); defer { array.finish(); close(arrayClient) }
        model.receiveAPI(request(field: "/array/0"), channel: array); try await helper.awaitCompletion(model)
        #expect(try helper.events(arrayClient).contains { $0.kind == "exit" && $0.exitCode == 0 })
        #expect(await transport.values == ["SYNTHETIC_ARRAY_TOKEN"])
    }

    @Test func apiKeysAndTextCannotBeSelectedOrChangeTheirProvider() async throws {
        for format in [SecretFormat.apiKey, .text] {
            let transport = SelectedFieldTransport()
            let (model, _) = try await fixture(transport: transport, format: format, provider: "OpenAI", value: "SYNTHETIC_EXISTING_API_TOKEN")
            defer { cleanup(model) }
            for request in [request(), request(field: nil, provider: "OpenAI")] {
                let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
                model.receiveAPI(request, channel: channel)
                #expect(model.apiApproval == nil)
                #expect(try helper.events(client).contains { $0.kind == "error" })
            }
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test func storedProviderIsUsedAndCannotBeOverriddenWithAnotherService() async throws {
        let transport = SelectedFieldTransport(), (model, _) = try await fixture(transport: transport, provider: "OpenAI")
        defer { cleanup(model) }
        let (wrong, wrongClient) = try RunnerTests().sockets(); defer { wrong.finish(); close(wrongClient) }
        model.receiveAPI(request(provider: "GitHub", url: "https://api.github.com/user"), channel: wrong)
        let wrongEvents = try helper.events(wrongClient)
        #expect(model.apiApproval == nil && wrongEvents.contains { $0.kind == "error" })
        let (valid, validClient) = try RunnerTests().sockets(); defer { valid.finish(); close(validClient) }
        model.receiveAPI(request(provider: nil), channel: valid)
        #expect(model.apiApproval?.provider.name == "OpenAI")
        await model.acceptAPI(remember: false); try await helper.awaitCompletion(model)
        #expect(try helper.events(validClient).contains { $0.kind == "exit" && $0.exitCode == 0 })
        #expect(await transport.values == ["SYNTHETIC_PRIMARY_TOKEN"])
    }

    @Test func pendingSelectionIsRevalidatedAfterVersionChangeAndLock() async throws {
        let transport = SelectedFieldTransport(), (model, credential) = try await fixture(transport: transport)
        defer { cleanup(model) }
        let (stale, staleClient) = try RunnerTests().sockets(); defer { stale.finish(); close(staleClient) }
        model.receiveAPI(request(), channel: stale)
        try #require(model.apiApproval != nil)
        // Keep the pending panel to exercise its own version guard rather than grant invalidation.
        try model.mutate(invalidateGrants: false) { snapshot in
            let index = try #require(snapshot.credentials.firstIndex { $0.id == credential.id })
            snapshot.credentials[index].rotate(to: #"{"services":{"primary":"SYNTHETIC_CHANGED_VERSION"}}"#)
        }
        await model.acceptAPI(remember: true); try await helper.awaitCompletion(model)
        #expect(try helper.events(staleClient).contains { $0.kind == "error" })
        #expect(await transport.requests.isEmpty && model.apiApprovals.active().isEmpty)
        let (locked, lockedClient) = try RunnerTests().sockets(); defer { locked.finish(); close(lockedClient) }
        model.receiveAPI(request(), channel: locked); try #require(model.apiApproval != nil)
        model.lock(); await model.acceptAPI(remember: true)
        #expect(try helper.events(lockedClient).contains { $0.kind == "error" })
        #expect(await transport.requests.isEmpty && model.apiApprovals.active().isEmpty)
    }

    @Test func queuedAutomaticSelectionCannotUseAStaleVersion() async throws {
        let transport = SelectedFieldTransport(), (model, credential) = try await fixture(transport: transport)
        defer { cleanup(model) }
        await model.startTimedApproval(minutes: 1)
        let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
        model.receiveAPI(request(), channel: channel)
        // Change the version before the API task receives its next MainActor turn.
        try model.mutate(invalidateGrants: false) { snapshot in
            let index = try #require(snapshot.credentials.firstIndex { $0.id == credential.id })
            snapshot.credentials[index].rotate(to: #"{"services":{"primary":"SYNTHETIC_QUEUED_CHANGE"}}"#)
        }
        try await helper.awaitCompletion(model)
        #expect(try helper.events(client).contains { $0.kind == "error" })
        #expect(await transport.requests.isEmpty)
    }

    @Test func reflectedSelectedTokensAreNeverReturnedToTheCaller() async throws {
        let transport = SelectedFieldTransport(reflect: true), (model, _) = try await fixture(transport: transport)
        defer { cleanup(model) }
        let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
        model.receiveAPI(request(), channel: channel); await model.acceptAPI(remember: false); try await helper.awaitCompletion(model)
        let events = try helper.events(client)
        #expect(events.contains { $0.kind == "error" } && !events.contains { $0.kind == "stdout" })
        #expect(!String(decoding: try JSONEncoder().encode(events), as: UTF8.self).contains("SYNTHETIC_PRIMARY_TOKEN"))
    }
}
