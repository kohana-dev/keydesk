import Foundation

/// Deliberately fixed public destinations. Custom endpoints and private networks fail closed.
public struct APIProvider: Sendable {
    public let name: String
    public let hosts: Set<String>
    public let header: String
    public let prefix: String
    public let extraHeaders: [String: String]
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
        .init(name: "Sentry", hosts: ["sentry.io"], header: "Authorization", prefix: "Bearer ", extraHeaders: [:])
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
        return result
    }
}
