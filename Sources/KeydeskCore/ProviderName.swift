import Foundation

public enum ProviderName {
    // User-entered provider labels are free text; AI-facing output only uses this fixed list.
    public static let options = ["OpenAI", "Anthropic", "Google", "Google Ads", "Google Cloud", "Azure", "AWS", "Cloudflare", "Vercel", "Netlify", "Supabase", "Firebase", "Clerk", "Auth0", "Stripe", "Paddle", "RevenueCat", "Apple API", "App Store Connect", "Google Play", "Android", "GitHub", "GitLab", "Resend", "SendGrid", "Mailgun", "Postmark", "Twilio", "Slack", "Discord", "Notion", "Linear", "Sentry", "PostHog", "Amplitude", "Mixpanel", "Algolia", "Meilisearch", "MongoDB", "Neon", "PlanetScale", "Upstash", "Redis", "Turso", "DigitalOcean", "Render", "Railway", "Fly.io", "Replicate", "Hugging Face", "ElevenLabs", "DeepSeek", "Groq", "Mistral", "Perplexity", "FAL", "Restic", "Other"]
    public static func canonical(_ provider: String) -> String {
        let trimmed = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return options.first { $0.lowercased() == trimmed } ?? "Custom"
    }
}
