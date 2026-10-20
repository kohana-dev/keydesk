import SwiftUI
import KeydeskCore

struct SecretFormatPicker: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Binding var format: SecretFormat

    var body: some View {
        let _ = interfaceLanguage
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("보관 형식", "Format"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(L10n.tr("보관 형식", "Format"), selection: $format) {
                ForEach(SecretFormat.allCases) { item in
                    Text(item.shortTitle).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("secret-format-picker")
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("secret-format-description")
        }
    }

    private var description: String {
        switch format {
        case .apiKey:
            L10n.tr("API 키나 토큰 하나를 보관하고, 필요한 도구에 안전하게 전달합니다.", "Store one API key or token and securely pass it to your tools.")
        case .keyValue:
            L10n.tr("사용자 이름·비밀번호처럼 관련된 이름과 값을 한 항목으로 묶습니다.", "Keep related names and values together, such as a username and password.")
        case .json:
            L10n.tr("객체·배열 등 JSON 문서를 검사하고 원문 그대로 보관합니다.", "Validate a JSON document, including objects and arrays, and keep its original text.")
        case .text:
            L10n.tr("복구 코드나 여러 줄 메모를 줄바꿈과 공백 그대로 보관합니다.", "Keep recovery codes or multiline notes with their whitespace and line breaks.")
        case .file:
            L10n.tr("인증서나 개인 키 파일을 원본 바이트 그대로 암호화합니다.", "Encrypt an original certificate or private key file without changing its bytes.")
        }
    }
}
