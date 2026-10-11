import Testing
@testable import KeydeskCore

struct ProviderCatalogTests {
    @Test func categoriesPartitionEveryProviderExactlyOnce() {
        let all = ProviderCatalog.categories.flatMap(\.providers)
        #expect(all.count == Set(all).count)
        #expect(Set(all) == Set(ProviderName.options))
    }
    @Test func recommendationsMatchNameKoreanAliasAndCategory() {
        #expect(ProviderCatalog.matching("pAdDlE").flatMap(\.providers) == ["Paddle"])
        #expect(ProviderCatalog.matching("레비뉴캣").flatMap(\.providers) == ["RevenueCat"])
        #expect(ProviderCatalog.matching("r2").flatMap(\.providers) == ["Cloudflare"])
        #expect(ProviderCatalog.matching("결제").flatMap(\.providers).contains("Paddle"))
        #expect(ProviderCatalog.matching("unknown service").isEmpty)
        #expect(ProviderCatalog.matching("  ").flatMap(\.providers).count == ProviderName.options.count)
        #expect(ProviderName.canonical("앱 내부 인증") == "Custom")
    }
    @Test func importClassifiesClearNamesWithoutGuessingGenericKeys() throws {
        #expect(ProviderCatalog.inferredProvider(for: "EXPO_PUBLIC_REVENUECAT_GOOGLE_API_KEY") == "RevenueCat")
        #expect(ProviderCatalog.inferredProvider(for: "GOOGLE_ADS_DEVELOPER_TOKEN") == "Google Ads")
        #expect(ProviderCatalog.inferredProvider(for: "APPLE_IAP_PRIVATE_KEY") == "App Store Connect")
        #expect(ProviderCatalog.inferredProvider(for: "API_KEY") == "Other")
        #expect(ProviderCatalog.inferredProvider(for: "TOKEN_ENCRYPTION_KEY") == "Other")
        let snapshot = try SecretDeposit(project: "Fixture", environment: .development, variable: "PADDLE_API_KEY", value: "FAKE_ONLY").adding(to: VaultSnapshot())
        #expect(snapshot.credentials.first?.provider == "Paddle")
    }

}
