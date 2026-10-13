import Testing
@testable import KeydeskCore

struct LocalizationTests {
    @Test func systemLanguageMatchesSupportedRegionalIdentifiers() {
        #expect(AppLanguage.system.resolved(preferredLanguages: ["ko-KR", "en-US"]) == .korean)
        #expect(AppLanguage.system.resolved(preferredLanguages: ["en_GB", "ko"]) == .english)
        #expect(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "ko-KR"]) == .korean)
        #expect(AppLanguage.system.resolved(preferredLanguages: ["de-DE"]) == .english)
        #expect(AppLanguage.system.resolved(preferredLanguages: []) == .english)
    }

    @Test func explicitChoiceOverridesSystemAndPreservesInterpolatedContent() {
        #expect(AppLanguage.english.resolved(preferredLanguages: ["ko-KR"]) == .english)
        #expect(AppLanguage.korean.resolved(preferredLanguages: ["en-US"]) == .korean)
        let variable = "SERVICE_API_KEY", count = 12
        #expect(L10n.tr("\(variable) · \(count)개", "\(variable) · \(count) keys", language: .english) == "SERVICE_API_KEY · 12 keys")
        #expect(L10n.tr("금고 잠금", "Lock vault", language: .korean) == "금고 잠금")
    }

    @Test func auditLocalizationDoesNotChangeStoredActionsOrUnknownData() {
        let stored = "API 시작 · fixture-id · prod · 새 승인"
        #expect(L10n.activity(stored, language: .english) == "API started · fixture-id · prod · New approval")
        #expect(L10n.activity(stored, language: .korean) == stored)
        #expect(L10n.activity("키 정보 편집", language: .english) == "Edited key details")
        #expect(L10n.activity("Custom action / 사용자 데이터", language: .english) == "Custom action / 사용자 데이터")
        #expect(EnvironmentName.development.rawValue == "dev")
        #expect(AppLanguage.korean.rawValue == "ko")
    }
}
