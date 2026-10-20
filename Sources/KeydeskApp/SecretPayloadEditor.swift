import SwiftUI
import KeydeskCore

/// Edits only supplied drafts. Saved vault contents are never fetched by this view.
struct SecretPayloadEditor: View {
    let format: SecretFormat
    @Binding var value: String
    @Binding var fields: [SecretField]
    @Binding var file: SecretFile?

    var body: some View {
        Group {
            switch format {
            case .apiKey:
                VStack(alignment: .leading, spacing: 8) {
                    SecretInput(title: L10n.tr("API 키 · 공백도 그대로 보관", "API key · Whitespace is preserved"), value: $value)
                        .accessibilityIdentifier("secret-content-input")
                    HStack {
                        Text(L10n.tr("최대 64 KiB", "Up to 64 KiB"))
                        Spacer()
                        Text("\(value.utf8.count) / \(SecretContent.maximumBytes) B")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(value.utf8.count > SecretContent.maximumBytes ? .red : .secondary)
                    if value.contains("\0") {
                        Text(L10n.tr("내용에 NUL 문자를 넣을 수 없습니다.", "Content cannot contain a NUL character."))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("secret-content-error")
                    }
                }
            case .keyValue:
                KeyValueEditor(fields: $fields)
            case .json, .text:
                MultilineSecretInput(format: format, value: $value)
                    .id(format)
            case .file:
                SecretFileInput(file: $file)
                    .accessibilityIdentifier("secret-content-input")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
