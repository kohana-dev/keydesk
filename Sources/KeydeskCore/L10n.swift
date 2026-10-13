import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case korean = "ko"
    case english = "en"

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            switch identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first {
            case "ko": return .korean
            case "en": return .english
            default: continue
            }
        }
        return .english
    }
}

/// Shared by the desktop UI and human-readable Core errors. Stored values and
/// transport identifiers never depend on the presentation language.
public enum L10n {
    public static let preferenceKey = "Cellar.interfaceLanguage"

    public static var preference: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "system") ?? .system
    }

    public static var language: AppLanguage { preference.resolved() }
    public static var locale: Locale { Locale(identifier: language.rawValue) }

    public static func tr(_ korean: String, _ english: String, language: AppLanguage? = nil) -> String {
        (language ?? preference).resolved() == .korean ? korean : english
    }

    /// Translate legacy audit labels for display without rewriting the vault.
    public static func activity(_ action: String, language: AppLanguage? = nil) -> String {
        guard (language ?? preference).resolved() == .english else { return action }
        let labels: [String: String] = [
            "금고 생성": "Created vault",
            "프로젝트 추가": "Added project",
            "프로젝트 정보 수정": "Updated project details",
            "키 등록": "Added key",
            "기존 키 연결": "Linked existing key",
            "키 버전 교체 · 제공사 폐기는 별도": "Rotated key version · Provider revocation is separate",
            "프로젝트 연결 해제": "Unlinked key from project",
            "금고에서 키 삭제 · 과거 백업과 제공사 키는 별도": "Deleted key from vault · Previous backups and provider keys are separate",
            "백업 복원 · 제공사 유효성 재확인 필요": "Restored backup · Recheck provider validity",
            "dotenv 가져오기": "Imported dotenv",
            "자동 백업 해제": "Turned off automatic backup",
            "자동 백업 설정": "Configured automatic backup",
            "데이터 키 교체": "Rotated data key",
            "복구 키 교체": "Rotated recovery key",
            "잠금 중 키 접수 준비": "Prepared locked-vault key deposit",
            "맡긴 키 금고 편입": "Added deposited key to vault",
            "CLI 새 키 저장": "Saved new key from CLI",
            "프로젝트와 전용 키 삭제 · 과거 백업과 제공사 키는 별도": "Deleted project and exclusive keys · Previous backups and provider keys are separate",
            "키 정보 편집": "Edited key details",
            "키 또는 파일 새 버전 저장": "Saved new key or file version"
        ]
        if let translated = labels[action] { return translated }
        let prefixes: [(String, String)] = [
            ("API 시작 · ", "API started · "),
            ("API 완료 · ", "API completed · "),
            ("API 중단 또는 결과 미확인 · ", "API interrupted or result unconfirmed · "),
            ("CLI 실행 승인 · ", "Approved CLI run · "),
            ("AI 키 이름 조회 허가 · ", "Allowed AI key-name lookup · ")
        ]
        for (korean, english) in prefixes where action.hasPrefix(korean) {
            return english + action.dropFirst(korean.count)
                .replacingOccurrences(of: "승인 재사용", with: "Reused approval")
                .replacingOccurrences(of: "기억한 승인", with: "Remembered approval")
                .replacingOccurrences(of: "새 승인", with: "New approval")
        }
        return action
    }
}
