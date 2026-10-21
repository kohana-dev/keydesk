import Testing
import Foundation
import Darwin
import CryptoKit
import LocalAuthentication
import KeydeskCore
@testable import KeydeskApp

/// Holds authentication open so cancellation and lock races exercise the real await boundary.
@MainActor
private final class TimedApprovalKeyStore: VaultKeyStore {
    let backing = MemoryKeyStore()
    var authentications = 0
    var suspended = false
    private var continuation: CheckedContinuation<LAContext?, any Error>?
    var waiting: Bool { continuation != nil }

    func authenticate(reason: String) async throws -> LAContext? {
        authentications += 1
        if suspended { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return try await backing.authenticate(reason: reason)
    }
    func completeAuthentication() {
        let pending = continuation; continuation = nil
        pending?.resume(returning: nil)
    }
    func saveDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID) throws { try backing.saveDeviceKey(key, id: id, epoch: epoch) }
    func loadDeviceKey(envelope: VaultEnvelope, context: LAContext?) throws -> SymmetricKey { try backing.loadDeviceKey(envelope: envelope, context: context) }
    func removeDeviceKey(id: UUID, epoch: UUID) { backing.removeDeviceKey(id: id, epoch: epoch) }
    func restoreDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID, context: LAContext?) throws { try backing.restoreDeviceKey(key, id: id, epoch: epoch, context: context) }
    func saveDepositPublicKey(_ data: Data, vaultID: UUID) throws { try backing.saveDepositPublicKey(data, vaultID: vaultID) }
    func loadDepositPublicKey(vaultID: UUID) throws -> Data { try backing.loadDepositPublicKey(vaultID: vaultID) }
    func saveRecoveryKey(_ key: SymmetricKey, vaultID: UUID) -> Bool { backing.saveRecoveryKey(key, vaultID: vaultID) }
    func loadRecoveryKey(vaultID: UUID) -> SymmetricKey? { backing.loadRecoveryKey(vaultID: vaultID) }
    func knownRecoveryVaults() -> [UUID] { backing.knownRecoveryVaults() }
}

/// No network request occurs. An admitted API call can be completed after automatic approval ends.
private actor TimedApprovalTransport: APITransport {
    private(set) var calls = 0
    private var continuations: [CheckedContinuation<APIResponse, Never>] = []
    func execute(_ request: APIRequest, provider: APIProvider, secret: String) async throws -> APIResponse {
        calls += 1
        return await withCheckedContinuation { continuations.append($0) }
    }
    func complete() {
        let pending = continuations; continuations.removeAll()
        for continuation in pending { continuation.resume(returning: APIResponse(status: 200, body: "{\"fixture\":true}")) }
    }
}

@Suite(.serialized) @MainActor
struct TimedApprovalTests {
    private let api = APIBrokerTests()

    private func fixture(keys: (any VaultKeyStore)? = nil, transport: any APITransport = FixtureAPITransport()) async throws -> VaultModel {
        let model: VaultModel
        if let keys {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("timed-approval-\(UUID())")
            model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: keys, apiTransport: transport, serve: false, observeSystemEvents: false)
            await model.prepareFirstRun(startNew: true)
            _ = try model.deposit(SecretDeposit(project: "fixture", environment: .production, variable: "CLOUDFLARE_API_TOKEN", value: "DISPOSABLE_TIMED_APPROVAL_KEY"))
        } else { model = try await api.fixture(transport) }
        _ = try model.deposit(SecretDeposit(project: "fixture", environment: .development, variable: "CLOUDFLARE_API_TOKEN", value: "DISPOSABLE_TIMED_APPROVAL_DEVELOPMENT_KEY"))
        return model
    }

    private func cleanUp(_ model: VaultModel) {
        model.shutdown()
        try? FileManager.default.removeItem(at: model.store.directory)
    }
    private func idleFixture(autoLockMinutes: Int = 30) -> VaultModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("timed-idle-\(UUID())")
        let model = VaultModel(demo: true, directory: directory, defaultBackupDirectory: nil,
                               keys: MemoryKeyStore(), serve: false, observeSystemEvents: false)
        // Demo models keep this setting in memory, without changing user preferences.
        model.autoLockMinutes = autoLockMinutes
        return model
    }
    private func cli(environment: EnvironmentName = .production, project: String = "fixture", variables: [String] = ["CLOUDFLARE_API_TOKEN"], command: [String] = ["/usr/bin/true"]) -> CLIRequest {
        CLIRequest(project: project, environment: environment, command: command, directory: "/tmp", stdinKey: nil, variables: variables)
    }
    private func broker(_ model: VaultModel, environment: EnvironmentName = .production, tool: String = "list_connections", arguments: [String: JSONValue] = [:]) throws -> BrokerRequest {
        let project = try #require(model.snapshot?.projects.first { $0.name == "fixture" })
        return BrokerRequest(session: "timed-approval-fixture", project: project.id.uuidString, environment: environment, tool: tool, arguments: arguments)
    }
    private func awaitClosed(_ channel: CLIChannel) async throws {
        for _ in 0..<200 {
            if !channel.isConnected { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!channel.isConnected, "The disposable request did not finish")
    }
    private func closedEvents(_ channel: CLIChannel, _ client: Int32) async throws -> [CLIEvent] {
        try await awaitClosed(channel)
        return try api.events(client)
    }
    private func brokerResponse(_ client: Int32) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: #require(try SocketTransport.readLine(from: client)))
    }
    private func expectSuccessfulRun(_ events: [CLIEvent]) {
        #expect(events.contains { $0.kind == "started" })
        #expect(events.contains { $0.kind == "exit" && $0.exitCode == 0 })
        #expect(!events.contains { $0.kind == "error" })
    }

    @Test func activeTimedApprovalKeepsTheVaultOpenBeyondTheIdleTimeout() async throws {
        let model = idleFixture()
        defer { cleanUp(model) }
        try #require(model.snapshot != nil && model.autoLockMinutes == 30)
        await model.startTimedApproval(minutes: 480)
        let sessionID = try #require(model.currentTimedApprovalID())
        let generation = model.generation

        // Advance the idle check only; no timer, wall-clock change or real waiting is needed.
        model.lockIfIdle(now: Date().addingTimeInterval(31 * 60))

        #expect(model.snapshot != nil)
        #expect(model.generation == generation)
        #expect(model.currentTimedApprovalID() == sessionID)
    }

    @Test func stoppingTimedApprovalResumesTheExistingIdleDeadlineAndPreservesTheSetting() async throws {
        for minutes in [5, 15, 30, 60] {
            let model = idleFixture(autoLockMinutes: minutes)
            defer { cleanUp(model) }
            await model.startTimedApproval(minutes: 480)
            try #require(model.timedApprovalIsActive)
            let idleCheck = Date().addingTimeInterval(61 * 60)
            model.lockIfIdle(now: idleCheck)
            try #require(model.snapshot != nil)
            #expect(model.autoLockMinutes == minutes)

            model.stopTimedApproval()
            #expect(model.snapshot != nil && model.timedApprovalExpiresAt == nil)
            // Stopping consent must not reset lastActivity and silently add a new idle window.
            model.lockIfIdle(now: idleCheck)
            #expect(model.snapshot == nil)
            #expect(model.autoLockMinutes == minutes)
        }
    }

    @Test func wallClockExpiryAtTheBoundaryResumesIdleLockInTheSameCheck() async throws {
        let model = idleFixture()
        defer { cleanUp(model) }
        await model.startTimedApproval(minutes: 480)
        let expiresAt = try #require(model.timedApprovalExpiresAt)
        let instant = ContinuousClock().now

        model.lockIfIdle(now: expiresAt.addingTimeInterval(-1), instant: instant)
        try #require(model.snapshot != nil && model.timedApprovalIsActive)
        model.lockIfIdle(now: expiresAt, instant: instant)

        #expect(model.snapshot == nil)
        #expect(model.timedApprovalExpiresAt == nil && !model.timedApprovalIsActive)
        #expect(model.autoLockMinutes == 30)
    }

    @Test func monotonicExpiryEndsIdleDeferralEvenWhenTheWallClockMovesBackward() async throws {
        let model = idleFixture()
        defer { cleanUp(model) }
        await model.startTimedApproval(minutes: 480)
        try #require(model.timedApprovalIsActive)
        let expiredInstant = ContinuousClock().now.advanced(by: .seconds(481 * 60))

        // The wall clock alone still permits consent, but the monotonic deadline has passed.
        model.lockIfIdle(now: Date().addingTimeInterval(-3_600), instant: expiredInstant)
        #expect(model.timedApprovalExpiresAt == nil && !model.timedApprovalIsActive)
        #expect(model.snapshot != nil) // The original date-based idle policy is unchanged.
        model.lockIfIdle(now: Date().addingTimeInterval(31 * 60), instant: expiredInstant)
        #expect(model.snapshot == nil)
    }

    @Test func screenLockOnlySettingStaysDisabledAfterTimedApprovalStopsOrExpires() async throws {
        for stopManually in [true, false] {
            let model = idleFixture(autoLockMinutes: 0)
            defer { cleanUp(model) }
            await model.startTimedApproval(minutes: 1)
            try #require(model.timedApprovalIsActive)
            if stopManually { model.stopTimedApproval() }
            model.lockIfIdle(now: Date().addingTimeInterval(86_400),
                             instant: ContinuousClock().now.advanced(by: .seconds(86_400)))
            #expect(model.timedApprovalExpiresAt == nil && !model.timedApprovalIsActive)
            #expect(model.snapshot != nil && model.autoLockMinutes == 0)
        }
    }

    @Test func wallClockAndMonotonicDeadlinesBothEndConsentAtTheBoundary() {
        let now = Date(timeIntervalSince1970: 1_000), instant = ContinuousClock().now
        let session = TimedApprovalSession(minutes: 1, now: now, instant: instant)
        #expect(session.isActive(now: now.addingTimeInterval(59), instant: instant.advanced(by: .seconds(59))))
        #expect(!session.isActive(now: now.addingTimeInterval(60), instant: instant.advanced(by: .seconds(59))))
        // Moving the wall clock backward cannot extend the originally selected duration.
        #expect(!session.isActive(now: now.addingTimeInterval(-3_600), instant: instant.advanced(by: .seconds(60))))
        #expect(!session.isActive(now: now.addingTimeInterval(61), instant: instant.advanced(by: .seconds(61))))
    }

    @Test func modeDefaultsOffAndInvalidOrLockedActivationNeverAuthenticates() async throws {
        let model = try await fixture(); defer { cleanUp(model) }
        let keys = try #require(model.keys as? MemoryKeyStore)
        #expect(!model.timedApprovalIsActive && model.timedApprovalExpiresAt == nil && !model.timedApprovalStarting)
        let baseline = keys.authentications
        for minutes in [Int.min, -1, 0, 481, Int.max] { await model.startTimedApproval(minutes: minutes) }
        #expect(keys.authentications == baseline && !model.timedApprovalIsActive)
        model.lock()
        await model.startTimedApproval(minutes: 1)
        #expect(keys.authentications == baseline && model.timedApprovalExpiresAt == nil)
    }

    @Test func activationFailureDoesNotAuthorizeAnyRequests() async throws {
        let model = try await fixture(); defer { cleanUp(model) }
        let keys = try #require(model.keys as? MemoryKeyStore)
        keys.denyAuthentication = true
        await model.startTimedApproval(minutes: 10)
        #expect(!model.timedApprovalIsActive && model.timedApprovalExpiresAt == nil && !model.timedApprovalStarting)
        let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
        model.receiveAPI(api.request(), channel: channel)
        #expect(model.apiApproval != nil)
        #expect(await (model.apiTransport as? FixtureAPITransport)?.calls == 0)
        model.rejectAPI()
    }

    @Test func oneActivationAuthenticationCoversAllThreeRequestPathsAndEnvironmentsWithoutPanels() async throws {
        let transport = FixtureAPITransport(), model = try await fixture(transport: transport)
        defer { cleanUp(model) }
        let keys = try #require(model.keys as? MemoryKeyStore), baseline = keys.authentications
        var presentedApprovals = 0
        model.onApprovalChange = { [weak model] in if model?.hasPendingApproval == true { presentedApprovals += 1 } }
        await model.startTimedApproval(minutes: 5)
        #expect(model.timedApprovalIsActive && keys.authentications == baseline + 1)
        keys.denyAuthentication = true // Every subsequent Production path must use the timed decision.
        for environment in [EnvironmentName.development, .production] {
            let (run, runClient) = try RunnerTests().sockets(); defer { run.finish(); close(runClient) }
            model.receive(try CLIApproval(request: cli(environment: environment), channel: run))
            expectSuccessfulRun(try await closedEvents(run, runClient))

            let (request, requestClient) = try RunnerTests().sockets(); defer { request.finish(); close(requestClient) }
            model.receiveAPI(APIRequest(project: "fixture", environment: environment, variable: "CLOUDFLARE_API_TOKEN", method: "GET", url: api.request().url), channel: request)
            let output = try await closedEvents(request, requestClient)
            #expect(output.contains { $0.kind == "exit" && $0.exitCode == 0 })
            let payload = try #require(output.first { $0.kind == "stdout" }?.data)
            let report = try JSONDecoder().decode(JSONValue.self, from: payload)
            #expect(report["approval"]?.string == "timed")
            #expect(!String(decoding: payload, as: UTF8.self).contains("DISPOSABLE_"))

            let (metadata, metadataClient) = try RunnerTests().sockets(); defer { metadata.finish(); close(metadataClient) }
            model.receiveBroker(try broker(model, environment: environment), channel: metadata)
            let response = try brokerResponse(metadataClient)
            #expect(response["result"]?["variables"] != nil)
            #expect(!String(decoding: try JSONEncoder().encode(response), as: UTF8.self).contains("DISPOSABLE_"))
        }
        #expect(await transport.calls == 2)
        #expect(keys.authentications == baseline + 1 && presentedApprovals == 0 && !model.hasPendingApproval)
    }

    @Test func activatingModeResolvesAnAlreadyPendingRequestOfEachKind() async throws {
        for kind in 0..<3 {
            let transport = FixtureAPITransport(), model = try await fixture(transport: transport)
            defer { cleanUp(model) }
            let keys = try #require(model.keys as? MemoryKeyStore), baseline = keys.authentications
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            switch kind {
            case 0: model.receive(try CLIApproval(request: cli(), channel: channel))
            case 1: model.receiveAPI(api.request(), channel: channel)
            default: model.receiveBroker(try broker(model, tool: "request_access", arguments: ["operation": .string("metadata")]), channel: channel)
            }
            #expect(model.hasPendingApproval)
            await model.startTimedApproval(minutes: 1)
            if kind == 2 {
                let response = try brokerResponse(client)
                #expect(response["result"]?["grantId"] != nil)
            } else {
                let output = try await closedEvents(channel, client)
                #expect(output.contains { $0.kind == "exit" && $0.exitCode == 0 })
            }
            #expect(!model.hasPendingApproval && keys.authentications == baseline + 1)
        }
    }

    @Test func stopLockAndRevokeDuringAuthenticationCannotEnableModeLater() async throws {
        for action in 0..<3 {
            let keys = TimedApprovalKeyStore(), model = try await fixture(keys: keys)
            defer { cleanUp(model) }
            keys.suspended = true
            let start = Task { await model.startTimedApproval(minutes: 5) }
            for _ in 0..<100 { if keys.waiting { break }; await Task.yield() }
            try #require(keys.waiting && model.timedApprovalStarting)
            // A second activation while authentication is on screen must not open another prompt.
            await model.startTimedApproval(minutes: 10)
            #expect(keys.authentications == 1)
            switch action {
            case 0: model.stopTimedApproval()
            case 1: model.lock()
            default: model.revokeAllPermissions()
            }
            keys.completeAuthentication(); await start.value
            #expect(!model.timedApprovalIsActive && model.timedApprovalExpiresAt == nil && !model.timedApprovalStarting)
        }
    }

    @Test func timedApprovalDoesNotSurviveLockOrApplicationRestart() async throws {
        let model = try await fixture(), keys = try #require(model.keys as? MemoryKeyStore)
        defer { cleanUp(model) }
        await model.startTimedApproval(minutes: 480)
        #expect(model.timedApprovalIsActive)
        model.lock(); #expect(!model.timedApprovalIsActive && model.timedApprovalExpiresAt == nil)
        await model.unlock(); #expect(!model.timedApprovalIsActive)
        await model.startTimedApproval(minutes: 1)
        model.shutdown()
        let reopened = VaultModel(directory: model.store.directory, defaultBackupDirectory: nil, keys: keys, serve: false, observeSystemEvents: false)
        defer { reopened.shutdown() }
        await reopened.unlock()
        #expect(reopened.snapshot != nil && !reopened.timedApprovalIsActive && reopened.timedApprovalExpiresAt == nil)
    }

    @Test func stopExpiryAndRevokeRemoveGrantsThatCouldOutliveTheWindow() async throws {
        for action in 0..<3 {
            let model = try await fixture(); defer { cleanUp(model) }
            let (remembered, rememberedClient) = try RunnerTests().sockets(); defer { remembered.finish(); close(rememberedClient) }
            model.receiveAPI(api.request(), channel: remembered)
            await model.acceptAPI(remember: true)
            _ = try await closedEvents(remembered, rememberedClient)
            #expect(!model.apiApprovals.active().isEmpty)
            await model.startTimedApproval(minutes: 1)
            #expect(model.apiApprovals.active().isEmpty)
            let (grant, grantClient) = try RunnerTests().sockets(); defer { grant.finish(); close(grantClient) }
            model.receiveBroker(try broker(model, tool: "request_access", arguments: ["operation": .string("metadata"), "duration": .number(600)]), channel: grant)
            try await awaitClosed(grant)
            #expect(try brokerResponse(grantClient)["result"]?["grantId"] != nil)
            switch action {
            case 0: model.stopTimedApproval()
            case 1: model.expireTimedApproval(now: try #require(model.timedApprovalExpiresAt))
            default: model.revokeAllPermissions()
            }
            #expect(!model.timedApprovalIsActive && model.grants.isEmpty && model.apiApprovals.active().isEmpty)
            let (metadata, metadataClient) = try RunnerTests().sockets(); defer { metadata.finish(); close(metadataClient) }
            model.receiveBroker(try broker(model), channel: metadata)
            #expect(try brokerResponse(metadataClient)["error"] != nil)
            let (request, requestClient) = try RunnerTests().sockets(); defer { request.finish(); close(requestClient) }
            model.receiveAPI(api.request(), channel: request)
            #expect(model.apiApproval != nil)
            model.rejectAPI()
        }
    }

    @Test func rememberedCommandPermissionIsClearedAtBothTimedModeBoundaries() async throws {
        let model = try await fixture(); defer { cleanUp(model) }
        let invocation = cli(environment: .development)
        let (first, firstClient) = try RunnerTests().sockets(); defer { first.finish(); close(firstClient) }
        model.receive(try CLIApproval(request: invocation, channel: first)); await model.acceptCLI(remember: true)
        expectSuccessfulRun(try await closedEvents(first, firstClient))
        #expect(!model.rememberedRuns.isEmpty)
        await model.startTimedApproval(minutes: 1)
        #expect(model.rememberedRuns.isEmpty)
        model.stopTimedApproval()
        let (next, nextClient) = try RunnerTests().sockets(); defer { next.finish(); close(nextClient) }
        model.receive(try CLIApproval(request: invocation, channel: next))
        #expect(model.approval != nil && !model.reusingDevelopmentApproval)
        model.rejectCLI()
    }

    @Test func queuedAutomaticCommandCannotStartAfterStopOrExpiry() async throws {
        for expire in [false, true] {
            let model = try await fixture(); defer { cleanUp(model) }
            let marker = model.store.directory.appendingPathComponent("must-not-run")
            await model.startTimedApproval(minutes: 1)
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            let invocation = cli(command: ["/usr/bin/touch", marker.path])
            model.receive(try CLIApproval(request: invocation, channel: channel))
            if expire { model.expireTimedApproval(now: try #require(model.timedApprovalExpiresAt)) }
            else { model.stopTimedApproval() }
            let output = try await closedEvents(channel, client)
            #expect(!output.contains { $0.kind == "started" })
            #expect(output.contains { $0.kind == "error" })
            #expect(!FileManager.default.fileExists(atPath: marker.path))
        }
    }

    @Test func admittedAPIRequestsCompleteAfterStopOrExpiryButNextRequestNeedsApproval() async throws {
        for expire in [false, true] {
            let transport = TimedApprovalTransport(), model = try await fixture(transport: transport)
            defer { cleanUp(model) }
            await model.startTimedApproval(minutes: 1)
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            model.receiveAPI(api.request(), channel: channel)
            for _ in 0..<100 { if await transport.calls == 1 { break }; await Task.yield() }
            try #require(await transport.calls == 1)
            if expire { model.expireTimedApproval(now: try #require(model.timedApprovalExpiresAt)) }
            else { model.stopTimedApproval() }
            await transport.complete()
            let output = try await closedEvents(channel, client)
            #expect(output.contains { $0.kind == "stdout" })
            #expect(output.contains { $0.kind == "exit" && $0.exitCode == 0 })
            let (next, nextClient) = try RunnerTests().sockets(); defer { next.finish(); close(nextClient) }
            model.receiveAPI(api.request(), channel: next)
            #expect(model.apiApproval != nil)
            model.rejectAPI()
        }
    }

    @Test func queuedAutomaticAPICannotContactTransportAfterStopOrExpiry() async throws {
        for expire in [false, true] {
            let transport = FixtureAPITransport(), model = try await fixture(transport: transport)
            defer { cleanUp(model) }
            await model.startTimedApproval(minutes: 1)
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            model.receiveAPI(api.request(), channel: channel)
            if expire { model.expireTimedApproval(now: try #require(model.timedApprovalExpiresAt)) }
            else { model.stopTimedApproval() }
            let output = try await closedEvents(channel, client)
            #expect(await transport.calls == 0)
            #expect(output.contains { $0.kind == "error" } && !output.contains { $0.kind == "stdout" })
        }
    }

    @Test func queuedAutomaticCommandsStillRespectFourProcessCapacity() async throws {
        let model = try await fixture(); defer { cleanUp(model) }
        await model.startTimedApproval(minutes: 1)
        var requests: [(CLIChannel, Int32)] = []
        defer { for (channel, client) in requests { channel.finish(); close(client) } }
        // All five requests arrive before their automatic-accept tasks get an actor turn.
        for _ in 0..<5 {
            let (channel, client) = try RunnerTests().sockets(); requests.append((channel, client))
            model.receive(try CLIApproval(request: cli(command: ["/bin/sleep", "0.4"]), channel: channel))
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(model.runningCommands.count <= 4)
        var started = 0, denied = 0
        for (channel, client) in requests {
            let output = try await closedEvents(channel, client)
            if output.contains(where: { $0.kind == "started" }) { started += 1 }
            if output.contains(where: { $0.kind == "error" }) { denied += 1 }
        }
        #expect(started == 4 && denied == 1)
    }

    @Test func automaticAPIsKeepTheFourRequestConcurrencyLimit() async throws {
        let transport = TimedApprovalTransport(), model = try await fixture(transport: transport)
        defer { cleanUp(model) }
        await model.startTimedApproval(minutes: 1)
        var requests: [(CLIChannel, Int32)] = []
        defer { for (channel, client) in requests { channel.finish(); close(client) } }
        for _ in 0..<5 {
            let (channel, client) = try RunnerTests().sockets(); requests.append((channel, client))
            model.receiveAPI(api.request(), channel: channel)
        }
        for _ in 0..<100 { if await transport.calls == 4 { break }; await Task.yield() }
        #expect(await transport.calls == 4 && model.apiTasks.count == 4)
        await transport.complete()
        var succeeded = 0, denied = 0
        for (channel, client) in requests {
            let output = try await closedEvents(channel, client)
            if output.contains(where: { $0.kind == "exit" && $0.exitCode == 0 }) { succeeded += 1 }
            if output.contains(where: { $0.kind == "error" }) { denied += 1 }
        }
        #expect(succeeded == 4 && denied == 1)
    }

    @Test func automaticModePreservesAPIProviderProjectKeyAndMetadataValidation() async throws {
        let transport = FixtureAPITransport(), model = try await fixture(transport: transport)
        defer { cleanUp(model) }
        await model.startTimedApproval(minutes: 1)
        let invalidRequests = [
            APIRequest(project: "missing", environment: .production, variable: "CLOUDFLARE_API_TOKEN", method: "GET", url: api.request().url),
            APIRequest(project: "fixture", environment: .production, variable: "MISSING_KEY", method: "GET", url: api.request().url),
            APIRequest(project: "fixture", environment: .production, variable: "CLOUDFLARE_API_TOKEN", method: "GET", url: "https://api.openai.com/v1/models"),
            APIRequest(project: "fixture", environment: .production, variable: "CLOUDFLARE_API_TOKEN", method: "GET", url: "http://127.0.0.1/"),
        ]
        for request in invalidRequests {
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            model.receiveAPI(request, channel: channel)
            #expect(try await closedEvents(channel, client).contains { $0.kind == "error" })
        }
        #expect(await transport.calls == 0 && !model.hasPendingApproval)
        let malformed: [(String, [String: JSONValue])] = [
            ("list_connections", ["secret": .bool(true)]),
            ("request_access", ["duration": .string("600")]),
            ("request_access", ["duration": .number(601)]),
            ("request_access", ["maximumCalls": .number(21)]),
            ("request_access", ["operation": .string("read_secret")]),
            ("get_secret", [:]),
        ]
        for (tool, arguments) in malformed {
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            model.receiveBroker(try broker(model, tool: tool, arguments: arguments), channel: channel)
            #expect(try brokerResponse(client)["error"] != nil)
        }
        #expect(model.grants.isEmpty && !model.hasPendingApproval)
    }

    @Test func automaticModeStillRejectsUnknownCLIProjectKeyAndChangedExecutable() async throws {
        let model = try await fixture(); defer { cleanUp(model) }
        await model.startTimedApproval(minutes: 1)
        for invocation in [cli(project: "missing"), cli(variables: ["MISSING_KEY"])] {
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            model.receive(try CLIApproval(request: invocation, channel: channel))
            let output = try await closedEvents(channel, client)
            #expect(output.contains { $0.kind == "error" } && !output.contains { $0.kind == "started" })
        }
        let executable = model.store.directory.appendingPathComponent("disposable-command")
        let marker = model.store.directory.appendingPathComponent("must-not-run")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable); chmod(executable.path, 0o700)
        let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
        let pending = try CLIApproval(request: cli(command: [executable.path]), channel: channel)
        try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: executable)
        model.receive(pending)
        let output = try await closedEvents(channel, client)
        #expect(output.contains { $0.kind == "error" } && !output.contains { $0.kind == "started" })
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}
