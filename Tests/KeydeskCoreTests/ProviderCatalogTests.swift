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
        #expect(ProviderCatalog.matching("gemi").flatMap(\.providers) == ["Gemini"])
        #expect(ProviderCatalog.matching("제미나이").flatMap(\.providers) == ["Gemini"])
        #expect(ProviderName.canonical("Gemini") == "Gemini")
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
        #expect(ProviderCatalog.inferredProvider(for: "GEMINI_API_KEY") == "Gemini")
        #expect(ProviderCatalog.inferredProvider(for: "GOOGLE_GEMINI_API_KEY") == "Gemini")
        #expect(ProviderCatalog.inferredProvider(for: "APPLE_IAP_PRIVATE_KEY") == "App Store Connect")
        #expect(ProviderCatalog.inferredProvider(for: "API_KEY") == "Other")
        #expect(ProviderCatalog.inferredProvider(for: "TOKEN_ENCRYPTION_KEY") == "Other")
        let snapshot = try SecretDeposit(project: "Fixture", environment: .development, variable: "PADDLE_API_KEY", value: "FAKE_ONLY").adding(to: VaultSnapshot())
        #expect(snapshot.credentials.first?.provider == "Paddle")
    }

    @Test func weatherServicesAreSearchableInBothLanguagesAndByKnownAliases() {
        let weather = ["OpenWeather", "WeatherAPI", "Tomorrow.io", "Visual Crossing", "Weatherbit", "AccuWeather"]
        #expect(ProviderName.weatherProviders == weather)
        #expect(ProviderCatalog.matching("날씨").flatMap(\.providers) == weather)
        #expect(ProviderCatalog.matching("weather environment").flatMap(\.providers) == weather)
        for query in ["openweathermap", "openwheater", "오픈웨더맵"] {
            #expect(ProviderCatalog.matching(query).flatMap(\.providers) == ["OpenWeather"])
        }
        #expect(ProviderCatalog.matching("weatherapi.com").flatMap(\.providers) == ["WeatherAPI"])
        #expect(ProviderCatalog.matching("웨더에이피아이").flatMap(\.providers) == ["WeatherAPI"])
        #expect(ProviderCatalog.matching("tomorrowio").flatMap(\.providers) == ["Tomorrow.io"])
        #expect(ProviderCatalog.matching("투모로우").flatMap(\.providers) == ["Tomorrow.io"])
        #expect(ProviderCatalog.matching("visualcrossing").flatMap(\.providers) == ["Visual Crossing"])
        #expect(ProviderCatalog.matching("비주얼 크로싱").flatMap(\.providers) == ["Visual Crossing"])
        #expect(ProviderCatalog.matching("weatherbit.io").flatMap(\.providers) == ["Weatherbit"])
        #expect(ProviderCatalog.matching("웨더비트").flatMap(\.providers) == ["Weatherbit"])
        #expect(ProviderCatalog.matching("accu weather").flatMap(\.providers) == ["AccuWeather"])
        #expect(ProviderCatalog.matching("아큐웨더").flatMap(\.providers) == ["AccuWeather"])
    }

    @Test func weatherCanonicalNamesRemainFixedAndSupportCommonVendorLabels() {
        let aliases = [
            " OpenWeatherMap ": "OpenWeather", "OpenWeather Map": "OpenWeather", "openwheater": "OpenWeather",
            "WeatherAPI.com": "WeatherAPI", "Weather API": "WeatherAPI",
            "TomorrowIO": "Tomorrow.io", "Tomorrow IO": "Tomorrow.io",
            "VisualCrossing": "Visual Crossing", "Weatherbit.io": "Weatherbit", "Accu Weather": "AccuWeather"
        ]
        for (alias, expected) in aliases { #expect(ProviderName.canonical(alias) == expected) }
        #expect(ProviderName.canonical("OpenWeather secret contents") == "Custom")
        #expect(ProviderName.canonical("https://api.openweathermap.org") == "Custom")
    }

    @Test func importRecognizesWeatherVendorPrefixesWithoutGuessingGenericWeatherKeys() throws {
        let variables = [
            "OPENWEATHERMAP_API_KEY": "OpenWeather", "OPENWEATHER_API_KEY": "OpenWeather",
            "OPEN_WEATHER_MAP_KEY": "OpenWeather", "OPEN_WEATHER_KEY": "OpenWeather",
            "WEATHERAPI_KEY": "WeatherAPI", "NEXT_PUBLIC_WEATHERAPI_KEY": "WeatherAPI",
            "TOMORROW_IO_API_KEY": "Tomorrow.io", "TOMORROWIO_API_KEY": "Tomorrow.io", "TOMORROW_API_KEY": "Tomorrow.io",
            "VISUAL_CROSSING_API_KEY": "Visual Crossing", "VISUALCROSSING_KEY": "Visual Crossing",
            "WEATHERBIT_API_KEY": "Weatherbit", "ACCUWEATHER_API_KEY": "AccuWeather", "ACCU_WEATHER_API_KEY": "AccuWeather"
        ]
        for (variable, expected) in variables { #expect(ProviderCatalog.inferredProvider(for: variable) == expected) }
        #expect(ProviderCatalog.inferredProvider(for: "WEATHER_API_KEY") == "Other")
        #expect(ProviderCatalog.inferredProvider(for: "WEATHER_KEY") == "Other")
        #expect(ProviderCatalog.inferredProvider(for: "FORECAST_API_KEY") == "Other")
        #expect(ProviderCatalog.inferredProvider(for: "OPENWEATHERMAPS_KEY") == "Other")
        let snapshot = try SecretDeposit(project: "Weather fixture", environment: .development, variable: "OPENWEATHERMAP_API_KEY", value: "FAKE_WEATHER_ONLY").adding(to: VaultSnapshot())
        #expect(snapshot.credentials.first?.provider == "OpenWeather")
    }

}
