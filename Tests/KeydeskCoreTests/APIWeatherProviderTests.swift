import Foundation
import Testing
import KeydeskCore

struct APIWeatherProviderTests {
    let names = ["OpenWeather", "WeatherAPI", "Tomorrow.io", "Visual Crossing", "Weatherbit", "AccuWeather"]
    func request(_ provider: APIProvider, method: String = "GET", suffix: String = "", field: String? = nil, override: String? = nil) -> APIRequest {
        APIRequest(project: "Synthetic weather", environment: .development, variable: "WEATHER_SETTINGS", method: method,
                   url: provider.defaultURL + suffix, field: field, provider: override)
    }

    @Test func officialWeatherHostsAndDefaultsResolveWithoutCallerCredentials() throws {
        let weather = APIProvider.supported.filter(\.isWeather)
        #expect(weather.map(\.name) == names)
        #expect(weather.count == 6 && APIProvider.supported.count == 17)
        for provider in weather {
            #expect(provider.methods == ["GET"])
            #expect(try APIProvider.resolve(provider: provider.name, request: request(provider)).name == provider.name)
            let components = try request(provider).validated()
            #expect(provider.hosts.contains(components.host ?? ""))
            #expect(!provider.defaultURL.contains("API_KEY"))
            #expect(try APIProvider.resolve(provider: "Other", request: request(provider, field: "/weather/token", override: provider.name)).name == provider.name)
        }
        #expect(weather.first { $0.name == "OpenWeather" }?.queryParameter == "appid")
        #expect(weather.filter { $0.queryParameter == "key" }.map(\.name) == ["WeatherAPI", "Visual Crossing", "Weatherbit"])
        #expect(weather.first { $0.name == "Tomorrow.io" }?.header == "apikey")
        #expect(weather.first { $0.name == "AccuWeather" }?.prefix == "Bearer ")
    }

    @Test func authenticationQueryVariantsAreRejectedBeforeApproval() throws {
        let forbidden = ["key=CALLER_VALUE", "KEY=CALLER_VALUE", "appid=CALLER_VALUE", "ApPiD", "apikey=CALLER_VALUE", "API_KEY=CALLER_VALUE", "api-key=CALLER_VALUE", "authorization=CALLER_VALUE", "access_token=CALLER_VALUE", "token=CALLER_VALUE", "auth=CALLER_VALUE", "client_secret=CALLER_VALUE", "%6bey=CALLER_VALUE", "k%65y=CALLER_VALUE", "%256Bey=CALLER_VALUE", "key[]=CALLER_VALUE", "key.token=CALLER_VALUE", "%20key%20=CALLER_VALUE", "+key+=CALLER_VALUE", "key%00junk=CALLER_VALUE", "q=Seoul;key=CALLER_VALUE", "q=Seoul&key=one&key=two"]
        for provider in APIProvider.supported.filter(\.isWeather) {
            for parameter in forbidden {
                let req = request(provider, suffix: "&" + parameter)
                #expect(throws: APIProviderError.authenticationQueryNotAllowed) { try req.validated() }
                #expect(throws: APIProviderError.authenticationQueryNotAllowed) { try APIProvider.resolve(provider: provider.name, request: req) }
            }
        }
    }

    @Test func weatherOnlyAllowsBodylessGETAndExactHTTPSHost() throws {
        for provider in APIProvider.supported.filter(\.isWeather) {
            for method in ["HEAD", "POST", "PUT", "PATCH", "DELETE"] {
                #expect(throws: APIProviderError.weatherGETOnly) { try APIProvider.resolve(provider: provider.name, request: request(provider, method: method)) }
            }
            let host = try #require(URLComponents(string: provider.defaultURL)?.host)
            for badURL in [provider.defaultURL.replacingOccurrences(of: host, with: host + ".evil.test"), provider.defaultURL.replacingOccurrences(of: "https://", with: "http://"), provider.defaultURL.replacingOccurrences(of: host, with: "user@" + host), provider.defaultURL.replacingOccurrences(of: host, with: host + ":444")] {
                let req = APIRequest(project: "Synthetic weather", environment: .development, variable: "WEATHER_SETTINGS", method: "GET", url: badURL)
                #expect(throws: (any Error).self) { try APIProvider.resolve(provider: provider.name, request: req) }
            }
        }
    }

    @Test func ordinaryEncodedWeatherQueryValuesAndLegacyProvidersRemainCompatible() throws {
        for provider in APIProvider.supported.filter(\.isWeather) {
            #expect(try request(provider, suffix: "&language=ko&region=KR&q=New%20York%26More&fields[]=temperature").validated().host != nil)
        }
        let legacy = try #require(APIProvider.supported.first { $0.name == "Cloudflare" })
        #expect(legacy.methods == ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"])
        #expect(try request(legacy, suffix: "?key=non-auth-resource-name").validated().host == "api.cloudflare.com")
        #expect(try APIProvider.resolve(provider: "Cloudflare", request: request(legacy, method: "DELETE")).name == "Cloudflare")
    }

    @Test func mixedCasePercentEncodedCredentialReflectionsAndRedirectsFailClosed() throws {
        let secret = "SYNTHETIC_Keep-._~+/=&?"
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = try #require(secret.addingPercentEncoding(withAllowedCharacters: safe))
        for reflected in [secret, encoded, encoded.replacingOccurrences(of: "%2B", with: "%2b"), encoded.replacingOccurrences(of: "%3D", with: "%3d").replacingOccurrences(of: "%2F", with: "%2f")] {
            #expect(throws: (any Error).self) { try APIResponse(status: 200, body: "{\"url\":\"https://api.weatherapi.com/v1/current.json?key=" + reflected + "\"}").validated(secret: secret) }
        }
        #expect(throws: (any Error).self) { try APIResponse(status: 307, body: "").validated(secret: secret) }
        #expect(try APIResponse(status: 401, body: "{\"error\":\"invalid API key\"}").validated(secret: secret).status == 401)
    }
}
