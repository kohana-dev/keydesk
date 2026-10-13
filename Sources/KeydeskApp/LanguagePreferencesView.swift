import SwiftUI
import KeydeskCore

struct LanguagePreferencesView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue

    var body: some View {
        let _ = interfaceLanguage
        Form {
            Picker(L10n.tr("앱 언어", "App language"), selection: $interfaceLanguage) {
                Text(L10n.tr("시스템 설정 따르기", "Follow system settings")).tag(AppLanguage.system.rawValue)
                Text("한국어").tag(AppLanguage.korean.rawValue)
                Text("English").tag(AppLanguage.english.rawValue)
            }
            Text(L10n.tr("언어 변경은 즉시 적용됩니다. 금고를 열기 전에도 언어를 선택할 수 있습니다.", "Language changes apply immediately, even while the vault is locked."))
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 420, height: 190)
        .environment(\.locale, L10n.locale)
    }
}
