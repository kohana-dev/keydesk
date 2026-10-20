import Foundation

public enum ProviderCatalog {
    public struct Category: Sendable, Identifiable {
        public let id: String
        public let providers: [String]
        public var title: String { L10n.tr(id, englishTitle) }
        fileprivate var englishTitle: String {
            switch id {
            case "AI · 모델": "AI · Models"
            case "클라우드 · 배포": "Cloud · Deployment"
            case "결제 · 구독": "Payments · Subscriptions"
            case "앱 · 플랫폼": "Apps · Platforms"
            case "데이터 · 검색 · 백업": "Data · Search · Backup"
            case "인증": "Authentication"
            case "메일 · 메시지": "Email · Messaging"
            case "개발 · 협업": "Development · Collaboration"
            case "모니터링 · 분석": "Monitoring · Analytics"
            case "날씨 · 환경": "Weather · Environment"
            case "기타": "Other"
            default: id
            }
        }
        init(title: String, providers: [String]) {
            self.id = title
            self.providers = providers
        }
    }
    public static let categories: [Category] = [
        Category(title: "AI · 모델", providers: ["OpenAI", "Anthropic", "Gemini", "Replicate", "Hugging Face", "ElevenLabs", "DeepSeek", "Groq", "Mistral", "Perplexity", "FAL"]),
        Category(title: "클라우드 · 배포", providers: ["Google Cloud", "Azure", "AWS", "Cloudflare", "Vercel", "Netlify", "DigitalOcean", "Render", "Railway", "Fly.io"]),
        Category(title: "결제 · 구독", providers: ["Stripe", "Paddle", "RevenueCat"]),
        Category(title: "앱 · 플랫폼", providers: ["Apple API", "App Store Connect", "Google Play", "Android", "Google", "Google Ads"]),
        Category(title: "데이터 · 검색 · 백업", providers: ["Supabase", "Firebase", "MongoDB", "Neon", "PlanetScale", "Upstash", "Redis", "Turso", "Algolia", "Meilisearch", "Restic"]),
        Category(title: "인증", providers: ["Clerk", "Auth0"]),
        Category(title: "메일 · 메시지", providers: ["Resend", "SendGrid", "Mailgun", "Postmark", "Twilio"]),
        Category(title: "개발 · 협업", providers: ["GitHub", "GitLab", "Slack", "Discord", "Notion", "Linear"]),
        Category(title: "모니터링 · 분석", providers: ["Sentry", "PostHog", "Amplitude", "Mixpanel"]),
        Category(title: "날씨 · 환경", providers: ProviderName.weatherProviders),
        Category(title: "기타", providers: ["Other"])
    ]
    private static let aliases: [String: String] = [
        "OpenAI": "오픈에이아이 챗지피티 chatgpt", "Anthropic": "앤트로픽 클로드 claude",
        "Gemini": "제미나이 gem google gemini 구글 ai studio",
        "Paddle": "패들 결제 payment", "Stripe": "스트라이프 결제 payment",
        "RevenueCat": "레비뉴캣 구독 subscription", "Cloudflare": "클라우드플레어 d1 r2 workers",
        "Apple API": "애플 인증 signin", "App Store Connect": "애플 앱스토어 인앱결제 iap",
        "Google": "구글 oauth", "Google Ads": "구글 광고", "Google Play": "구글 플레이 안드로이드",
        "Android": "안드로이드 서명 signing", "Restic": "레스틱 백업 backup",
        "Resend": "리센드 이메일 email", "Supabase": "수파베이스 database", "Firebase": "파이어베이스",
        "OpenWeather": "오픈웨더 오픈웨더맵 openweathermap openweather map open weather openwheater forecast climate air quality 대기질 예보 기상",
        "WeatherAPI": "웨더에이피아이 웨더API weatherapi.com weather api forecast 예보 기상",
        "Tomorrow.io": "투모로우 투모로 tomorrowio tomorrow io forecast 예보 기상",
        "Visual Crossing": "비주얼크로싱 비주얼 크로싱 visualcrossing historical forecast 과거 예보 기상",
        "Weatherbit": "웨더비트 weatherbit.io forecast air quality 대기질 예보 기상",
        "AccuWeather": "아큐웨더 애큐웨더 아큐 accu weather forecast 예보 기상"
    ]
    public static func matching(_ query: String) -> [Category] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return categories.compactMap { category in
            let providers = category.providers.filter { name in
                let haystack = (name + " " + category.id + " " + category.englishTitle + " " + (aliases[name] ?? "")).lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
            return providers.isEmpty ? nil : Category(title: category.id, providers: providers)
        }
    }
    /// Classify only clear vendor prefixes, without inspecting secret values.
    public static func inferredProvider(for variable: String) -> String {
        var name = variable.uppercased()
        for prefix in ["NEXT_PUBLIC_", "EXPO_PUBLIC_", "VITE_", "PUBLIC_"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        let prefixes: [(String, String)] = [
            ("GEMINI_", "Gemini"), ("GOOGLE_GEMINI_", "Gemini"), ("GOOGLE_GENERATIVE_AI_", "Gemini"),
            ("GOOGLE_ADS_", "Google Ads"), ("GOOGLE_CLOUD_", "Google Cloud"),
            ("GOOGLE_PLAY_", "Google Play"), ("GOOGLE_", "Google"),
            ("APPLE_IAP_", "App Store Connect"), ("APP_STORE_", "App Store Connect"), ("APPLE_", "Apple API"),
            ("ANDROID_UPLOAD_", "Android"), ("R2_BACKUP_", "Cloudflare"), ("D1_EXPORT_", "Cloudflare"),
            ("CLOUDFLARE_", "Cloudflare"), ("REVENUECAT_", "RevenueCat"), ("PADDLE_", "Paddle"),
            ("RESEND_", "Resend"), ("OPENAI_", "OpenAI"), ("ANTHROPIC_", "Anthropic"),
            ("SUPABASE_", "Supabase"), ("FIREBASE_", "Firebase"), ("STRIPE_", "Stripe"),
            ("AWS_", "AWS"), ("AZURE_", "Azure"), ("RESTIC_", "Restic"),
            ("CLERK_", "Clerk"), ("AUTH0_", "Auth0"), ("SENTRY_", "Sentry"),
            ("GITHUB_", "GitHub"), ("GITLAB_", "GitLab"), ("POSTHOG_", "PostHog"),
            ("OPENWEATHERMAP_", "OpenWeather"), ("OPENWEATHER_", "OpenWeather"),
            ("OPEN_WEATHER_MAP_", "OpenWeather"), ("OPEN_WEATHER_", "OpenWeather"),
            ("WEATHERAPI_", "WeatherAPI"), ("TOMORROW_IO_", "Tomorrow.io"), ("TOMORROWIO_", "Tomorrow.io"),
            ("TOMORROW_", "Tomorrow.io"), ("VISUAL_CROSSING_", "Visual Crossing"), ("VISUALCROSSING_", "Visual Crossing"),
            ("WEATHERBIT_", "Weatherbit"), ("ACCUWEATHER_", "AccuWeather"), ("ACCU_WEATHER_", "AccuWeather")
        ]
        return prefixes.first { name.hasPrefix($0.0) }?.1 ?? "Other"
    }

}
