import Foundation
import Darwin
import Testing
import KeydeskCore
@testable import KeydeskApp

private actor WeatherFixtureTransport: APITransport {
    enum Outcome: Sendable { case success, reflectURL, fail }
    let outcome: Outcome
    private(set) var requests: [APIRequest] = []
    private(set) var secrets: [String] = []
    private(set) var configurations: [String] = []
    init(_ outcome: Outcome = .success) { self.outcome = outcome }
    func execute(_ request: APIRequest, provider: APIProvider, secret: String) async throws -> APIResponse {
        let config = try CurlAPITransport.configuration(request, provider: provider, secret: secret, address: "1.1.1.1")
        requests.append(request); secrets.append(secret); configurations.append(config)
        let encoded = secret.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? secret
        switch outcome {
        case .success: return APIResponse(status: 200, body: #"{"syntheticWeather":true}"#)
        case .reflectURL: return APIResponse(status: 401, body: "https://api.weatherapi.com/v1/current.json?key=" + encoded)
        case .fail: throw NSError(domain: "SyntheticTransport", code: 1, userInfo: [NSLocalizedDescriptionKey: "https://api.weatherapi.com/?key=" + encoded])
        }
    }
}

struct APIWeatherTransportTests {
    @Test func credentialsAreAddedOnlyInsideTheStdinConfiguration() throws {
        let secret = "SYNTHETIC_Keep-._~+&=/%?\"한글"
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = try #require(secret.addingPercentEncoding(withAllowedCharacters: safe))
        for provider in APIProvider.supported {
            let request = APIRequest(project: "Synthetic weather", environment: .development, variable: "WEATHER_API_KEY", method: "GET", url: provider.defaultURL)
            let fingerprint = request.fingerprint
            let config = try CurlAPITransport.configuration(request, provider: provider, secret: secret, address: "1.1.1.1")
            #expect(config.contains("resolve = \"\(URLComponents(string: provider.defaultURL)!.host!):443:1.1.1.1\""))
            #expect(request.url == provider.defaultURL && request.fingerprint == fingerprint)
            #expect(!String(decoding: try JSONEncoder().encode(request), as: UTF8.self).contains(secret))
            if let parameter = provider.queryParameter {
                #expect(config.contains("\(parameter)=\(encoded)"))
                #expect(!config.contains("header = \"Authorization:"))
                let line = try #require(config.split(separator: "\n").first)
                let quotedURL = String(line.dropFirst("url = ".count))
                let url = try JSONDecoder().decode(String.self, from: Data(quotedURL.utf8))
                let components = try #require(URLComponents(string: url))
                #expect(components.queryItems?.filter { $0.name == parameter }.map(\.value) == [secret])
                #expect(components.queryItems?.count == (URLComponents(string: request.url)?.queryItems?.count ?? 0) + 1)
            } else {
                #expect(config.contains(CurlAPITransport.quoted("\(provider.header): \(provider.prefix)\(secret)")))
                #expect(config.contains("url = \(CurlAPITransport.quoted(request.url))\n"))
            }
            for badSecret in ["bad\r\nheader: injected", "bad\0value", String(repeating: "x", count: 32_769)] {
                #expect(throws: (any Error).self) { try CurlAPITransport.configuration(request, provider: provider, secret: badSecret, address: "1.1.1.1") }
            }
        }
    }
}

@Suite(.serialized) @MainActor
struct APIWeatherBrokerTests {
    private let helper = APIBrokerTests()
    private let secret = "SYNTHETIC_WEATHER_Keep-._~+/=&?"
    private func fixture(_ transport: WeatherFixtureTransport, provider: String, format: SecretFormat = .apiKey) async throws -> VaultModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-weather-\(UUID())")
        let model = VaultModel(directory: directory, defaultBackupDirectory: nil, keys: MemoryKeyStore(), apiTransport: transport, serve: false, observeSystemEvents: false)
        await model.prepareFirstRun(startNew: true)
        try model.addProject("Synthetic weather")
        model.selectedProject = try #require(model.snapshot?.projects.first?.id)
        let document = String(decoding: try JSONSerialization.data(withJSONObject: ["weather": ["token": secret], "untouched": "SYNTHETIC_NEVER_DELIVERED"]), as: UTF8.self)
        try model.addCredential(name: "Synthetic weather credential", value: format == .apiKey ? secret : document,
                                provider: provider, account: "", note: "", variable: "WEATHER_SETTINGS", format: format)
        return model
    }
    private func cleanup(_ model: VaultModel) { model.shutdown(); try? FileManager.default.removeItem(at: model.store.directory) }
    private func request(_ provider: APIProvider, field: String? = nil, override: String? = nil, suffix: String = "", method: String = "GET") -> APIRequest {
        APIRequest(project: "Synthetic weather", environment: .development, variable: "WEATHER_SETTINGS", method: method,
                   url: provider.defaultURL + suffix, field: field, provider: override)
    }

    @Test func everyWeatherServiceSupportsStoredKeysAndSelectedJSONStringFields() async throws {
        for provider in APIProvider.supported.filter(\.isWeather) {
            for format in [SecretFormat.apiKey, .json] {
                let transport = WeatherFixtureTransport(), model = try await fixture(transport, provider: format == .json ? "Other" : provider.name, format: format)
                defer { cleanup(model) }
                let selected = format == .json
                let req = request(provider, field: selected ? "/weather/token" : nil, override: selected ? provider.name : nil)
                let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
                model.receiveAPI(req, channel: channel)
                let approval = try #require(model.apiApproval)
                #expect(approval.request.url == req.url && approval.provider.name == provider.name)
                let approvalWire = String(decoding: try JSONEncoder().encode(approval.request), as: UTF8.self)
                #expect(!approvalWire.contains(secret) && !approvalWire.contains("SYNTHETIC_NEVER_DELIVERED"))
                await model.acceptAPI(remember: true); try await helper.awaitCompletion(model)
                #expect(await transport.secrets == [secret])
                #expect(await transport.requests.map(\.url) == [req.url])
                let events = try helper.events(client)
                #expect(events.contains { $0.kind == "exit" && $0.exitCode == 0 })
                let output = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
                let activity = model.snapshot?.activities.map(\.action).joined(separator: "\n") ?? ""
                #expect(!output.contains(secret) && !output.contains("SYNTHETIC_NEVER_DELIVERED") && !activity.contains(secret))
                #expect(model.apiApprovals.active().first?.request.url == req.url)
            }
        }
    }

    @Test func callerAuthenticationAndUnsupportedMethodsAreDeniedEvenDuringAllowAll() async throws {
        let provider = try #require(APIProvider.supported.first { $0.name == "OpenWeather" })
        let transport = WeatherFixtureTransport(), model = try await fixture(transport, provider: provider.name)
        defer { cleanup(model) }
        await model.startTimedApproval(minutes: 1)
        for (req, expected) in [(request(provider, suffix: "&%2561ppid=CALLER_SYNTHETIC_VALUE"), "api_authentication_query_not_allowed"), (request(provider, method: "POST"), "weather_api_get_only")] {
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            model.receiveAPI(req, channel: channel)
            #expect(model.apiApproval == nil)
            let events = try helper.events(client)
            #expect(events.contains { $0.kind == "error" && $0.text == expected })
            #expect(!String(decoding: try JSONEncoder().encode(events), as: UTF8.self).contains("CALLER_SYNTHETIC_VALUE"))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func reflectedURLsAndTransportErrorsDoNotReachReportsOrActivity() async throws {
        let provider = try #require(APIProvider.supported.first { $0.name == "WeatherAPI" })
        for outcome in [WeatherFixtureTransport.Outcome.reflectURL, .fail] {
            let transport = WeatherFixtureTransport(outcome), model = try await fixture(transport, provider: provider.name)
            defer { cleanup(model) }
            let (channel, client) = try RunnerTests().sockets(); defer { channel.finish(); close(client) }
            model.receiveAPI(request(provider), channel: channel)
            await model.acceptAPI(remember: false); try await helper.awaitCompletion(model)
            let events = try helper.events(client)
            #expect(events.contains { $0.kind == "error" && $0.text == "api_failed_or_cancelled_no_automatic_retry" })
            #expect(!events.contains { $0.kind == "stdout" })
            let wire = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
            #expect(!wire.contains(secret) && !wire.contains("https://api.weatherapi.com"))
            #expect(model.snapshot?.activities.allSatisfy { !$0.action.contains(secret) && !$0.action.contains("https://api.weatherapi.com") } == true)
        }
    }
}
