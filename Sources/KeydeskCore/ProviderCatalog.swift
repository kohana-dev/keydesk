import Foundation

public enum ProviderCatalog {
    public struct Category: Sendable, Identifiable {
        public let title: String
        public let providers: [String]
        public var id: String { title }
    }
    public static let categories: [Category] = [
        Category(title: "AI · 모델", providers: ["OpenAI", "Anthropic", "Replicate", "Hugging Face", "ElevenLabs", "DeepSeek", "Groq", "Mistral", "Perplexity", "FAL"]),
        Category(title: "클라우드 · 배포", providers: ["Google Cloud", "Azure", "AWS", "Cloudflare", "Vercel", "Netlify", "DigitalOcean", "Render", "Railway", "Fly.io"]),
        Category(title: "결제 · 구독", providers: ["Stripe", "Paddle", "RevenueCat"]),
        Category(title: "앱 · 플랫폼", providers: ["Apple API", "App Store Connect", "Google Play", "Android", "Google", "Google Ads"]),
        Category(title: "데이터 · 검색 · 백업", providers: ["Supabase", "Firebase", "MongoDB", "Neon", "PlanetScale", "Upstash", "Redis", "Turso", "Algolia", "Meilisearch", "Restic"]),
        Category(title: "인증", providers: ["Clerk", "Auth0"]),
        Category(title: "메일 · 메시지", providers: ["Resend", "SendGrid", "Mailgun", "Postmark", "Twilio"]),
        Category(title: "개발 · 협업", providers: ["GitHub", "GitLab", "Slack", "Discord", "Notion", "Linear"]),
        Category(title: "모니터링 · 분석", providers: ["Sentry", "PostHog", "Amplitude", "Mixpanel"]),
        Category(title: "기타", providers: ["Other"])
    ]
    private static let aliases: [String: String] = [
        "OpenAI": "오픈에이아이 챗지피티 chatgpt", "Anthropic": "앤트로픽 클로드 claude",
        "Paddle": "패들 결제 payment", "Stripe": "스트라이프 결제 payment",
        "RevenueCat": "레비뉴캣 구독 subscription", "Cloudflare": "클라우드플레어 d1 r2 workers",
        "Apple API": "애플 인증 signin", "App Store Connect": "애플 앱스토어 인앱결제 iap",
        "Google": "구글 oauth", "Google Ads": "구글 광고", "Google Play": "구글 플레이 안드로이드",
        "Android": "안드로이드 서명 signing", "Restic": "레스틱 백업 backup",
        "Resend": "리센드 이메일 email", "Supabase": "수파베이스 database", "Firebase": "파이어베이스"
    ]
    public static func matching(_ query: String) -> [Category] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return categories.compactMap { category in
            let providers = category.providers.filter { name in
                let haystack = (name + " " + category.title + " " + (aliases[name] ?? "")).lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
            return providers.isEmpty ? nil : Category(title: category.title, providers: providers)
        }
    }
    /// Classify only clear vendor prefixes, without inspecting secret values.
    public static func inferredProvider(for variable: String) -> String {
        var name = variable.uppercased()
        for prefix in ["NEXT_PUBLIC_", "EXPO_PUBLIC_", "VITE_", "PUBLIC_"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        let prefixes: [(String, String)] = [
            ("GOOGLE_ADS_", "Google Ads"), ("GOOGLE_CLOUD_", "Google Cloud"),
            ("GOOGLE_PLAY_", "Google Play"), ("GOOGLE_", "Google"),
            ("APPLE_IAP_", "App Store Connect"), ("APP_STORE_", "App Store Connect"), ("APPLE_", "Apple API"),
            ("ANDROID_UPLOAD_", "Android"), ("R2_BACKUP_", "Cloudflare"), ("D1_EXPORT_", "Cloudflare"),
            ("CLOUDFLARE_", "Cloudflare"), ("REVENUECAT_", "RevenueCat"), ("PADDLE_", "Paddle"),
            ("RESEND_", "Resend"), ("OPENAI_", "OpenAI"), ("ANTHROPIC_", "Anthropic"),
            ("SUPABASE_", "Supabase"), ("FIREBASE_", "Firebase"), ("STRIPE_", "Stripe"),
            ("AWS_", "AWS"), ("AZURE_", "Azure"), ("RESTIC_", "Restic"),
            ("CLERK_", "Clerk"), ("AUTH0_", "Auth0"), ("SENTRY_", "Sentry"),
            ("GITHUB_", "GitHub"), ("GITLAB_", "GitLab"), ("POSTHOG_", "PostHog")
        ]
        return prefixes.first { name.hasPrefix($0.0) }?.1 ?? "Other"
    }

}
