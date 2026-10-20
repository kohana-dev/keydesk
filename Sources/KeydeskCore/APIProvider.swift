import Foundation

/// Deliberately fixed public destinations. Custom endpoints and private networks fail closed.
public struct APIProvider: Sendable {
    public let name: String
    public let hosts: Set<String>
    public let header: String
    public let prefix: String
    public let extraHeaders: [String: String]
    /// Authentication is added inside the app, after the names-only request is approved.
    public let queryParameter: String?
    public let methods: Set<String>
    public let defaultURL: String
    public let isWeather: Bool

    private init(name: String, hosts: Set<String>, header: String, prefix: String, extraHeaders: [String: String],
                 queryParameter: String? = nil, methods: Set<String> = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"],
                 defaultURL: String? = nil, isWeather: Bool = false) {
        self.name = name; self.hosts = hosts; self.header = header; self.prefix = prefix
        self.extraHeaders = extraHeaders; self.queryParameter = queryParameter; self.methods = methods
        self.defaultURL = defaultURL ?? "https://\(hosts.sorted().first ?? "")/"
        self.isWeather = isWeather
    }
    public static let supported: [APIProvider] = [
        .init(name: "OpenAI", hosts: ["api.openai.com"], header: "Authorization", prefix: "Bearer ", extraHeaders: [:]),
        .init(name: "Gemini", hosts: ["generativelanguage.googleapis.com"], header: "x-goog-api-key", prefix: "", extraHeaders: [:]),
        .init(name: "Anthropic", hosts: ["api.anthropic.com"], header: "x-api-key", prefix: "", extraHeaders: ["anthropic-version": "2023-06-01"]),
        .init(name: "GitHub", hosts: ["api.github.com"], header: "Authorization", prefix: "Bearer ", extraHeaders: ["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]),
        .init(name: "Cloudflare", hosts: ["api.cloudflare.com"], header: "Authorization", prefix: "Bearer ", extraHeaders: [:]),
        .init(name: "Paddle", hosts: ["api.paddle.com", "sandbox-api.paddle.com"], header: "Authorization", prefix: "Bearer ", extraHeaders: [:]),
        .init(name: "RevenueCat", hosts: ["api.revenuecat.com"], header: "Authorization", prefix: "Bearer ", extraHeaders: [:]),
        .init(name: "Stripe", hosts: ["api.stripe.com"], header: "Authorization", prefix: "Bearer ", extraHeaders: [:]),
        .init(name: "Resend", hosts: ["api.resend.com"], header: "Authorization", prefix: "Bearer ", extraHeaders: [:]),
        .init(name: "Vercel", hosts: ["api.vercel.com"], header: "Authorization", prefix: "Bearer ", extraHeaders: [:]),
        .init(name: "Sentry", hosts: ["sentry.io"], header: "Authorization", prefix: "Bearer ", extraHeaders: [:]),
        .init(name: "OpenWeather", hosts: ["api.openweathermap.org"], header: "", prefix: "", extraHeaders: [:], queryParameter: "appid", methods: ["GET"], defaultURL: "https://api.openweathermap.org/data/2.5/weather?lat=37.5665&lon=126.9780&units=metric", isWeather: true),
        .init(name: "WeatherAPI", hosts: ["api.weatherapi.com"], header: "", prefix: "", extraHeaders: [:], queryParameter: "key", methods: ["GET"], defaultURL: "https://api.weatherapi.com/v1/current.json?q=Seoul", isWeather: true),
        .init(name: "Tomorrow.io", hosts: ["api.tomorrow.io"], header: "apikey", prefix: "", extraHeaders: [:], methods: ["GET"], defaultURL: "https://api.tomorrow.io/v4/weather/realtime?location=37.5665,126.9780&units=metric", isWeather: true),
        .init(name: "Visual Crossing", hosts: ["weather.visualcrossing.com"], header: "", prefix: "", extraHeaders: [:], queryParameter: "key", methods: ["GET"], defaultURL: "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/Seoul?unitGroup=metric&contentType=json", isWeather: true),
        .init(name: "Weatherbit", hosts: ["api.weatherbit.io"], header: "", prefix: "", extraHeaders: [:], queryParameter: "key", methods: ["GET"], defaultURL: "https://api.weatherbit.io/v2.0/current?lat=37.5665&lon=126.9780", isWeather: true),
        .init(name: "AccuWeather", hosts: ["dataservice.accuweather.com"], header: "Authorization", prefix: "Bearer ", extraHeaders: [:], methods: ["GET"], defaultURL: "https://dataservice.accuweather.com/locations/v1/cities/search?q=Seoul", isWeather: true)
    ]
    public static func resolve(provider: String, request: APIRequest) throws -> APIProvider {
        let c = try request.validated()
        let stored = ProviderName.canonical(provider)
        let selected: String
        if let override = request.provider {
            let canonical = ProviderName.canonical(override)
            guard request.field != nil, stored == "Other" || stored == canonical else { throw VaultError.accessDenied }
            selected = canonical
        } else { selected = stored }
        guard let result = supported.first(where: { $0.name == selected }),
              result.hosts.contains(c.host ?? "") else { throw VaultError.accessDenied }
        try result.validate(request, components: c)
        return result
    }
    /// The uncredentialed URL remains unchanged for approval, fingerprints, grants and reports.
    public func validate(_ request: APIRequest, components: URLComponents) throws {
        guard hosts.contains(components.host ?? "") else { throw VaultError.accessDenied }
        if isWeather {
            // Weather queries are read-only. Bulk/management APIs are outside this broker's scope.
            guard methods.contains(request.method), request.body == nil else { throw APIProviderError.weatherGETOnly }
            // Reject caller-provided authentication even on services that support header auth.
            // Split both common separators; decode parameter names before comparison so encoded,
            // mixed-case or duplicate credential fields cannot override the broker's credential.
            let reserved: Set<String> = ["key", "apikey", "appid", "authorization", "auth", "accesstoken", "token", "xapikey", "clientsecret"]
            for part in (components.percentEncodedQuery ?? "").split(whereSeparator: { $0 == "&" || $0 == ";" }) {
                let rawName = String(part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0])
                var name = rawName
                for _ in 0..<8 {
                    guard let decoded = name.removingPercentEncoding else { throw APIProviderError.authenticationQueryNotAllowed }
                    if decoded == name { break }
                    name = decoded
                }
                // Deep/ambiguous encodings and delimiters in parameter names fail closed.
                guard !name.contains("%"), !name.contains("&"), !name.contains(";"), !name.contains("=") else { throw APIProviderError.authenticationQueryNotAllowed }
                name = name.replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.range(of: "^[A-Za-z0-9_.\\[\\]-]*$", options: .regularExpression) != nil else { throw APIProviderError.authenticationQueryNotAllowed }
                let rootName = name.split(whereSeparator: { $0 == "[" || $0 == "." }).first.map(String.init) ?? ""
                let normalized = rootName.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
                guard !reserved.contains(normalized) else { throw APIProviderError.authenticationQueryNotAllowed }
            }
        } else {
            guard methods.contains(request.method) else { throw VaultError.accessDenied }
        }
    }
}

public enum APIProviderError: Error, LocalizedError, Equatable {
    case authenticationQueryNotAllowed, weatherGETOnly
    public var code: String {
        switch self {
        case .authenticationQueryNotAllowed: "api_authentication_query_not_allowed"
        case .weatherGETOnly: "weather_api_get_only"
        }
    }
    public var errorDescription: String? {
        switch self {
        case .authenticationQueryNotAllowed:
            L10n.tr("주소에서 인증 쿼리(key·appid·apikey 등)를 빼 주세요. Cellar가 저장된 키를 내부에서 넣습니다.", "Remove authentication query parameters (key, appid, apikey, etc.) from the URL. Cellar adds the stored key internally.")
        case .weatherGETOnly:
            L10n.tr("날씨 API는 본문 없는 GET 조회만 지원합니다.", "Weather APIs support GET requests without a body.")
        }
    }
}
