import SwiftUI
import KeydeskCore

struct SecretValueCard: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    let credential: Credential
    let editContent: () -> Void

    private var revealedText: String? {
        guard model.revealID == credential.id else { return nil }
        return model.revealedValue
    }

    private var copyTitle: String {
        switch credential.currentFormat {
        case .apiKey: L10n.tr("키 복사", "Copy key")
        case .keyValue, .json: L10n.tr("JSON 복사", "Copy JSON")
        case .text, .file: L10n.tr("내용 복사", "Copy contents")
        }
    }

    var body: some View {
        let _ = interfaceLanguage
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(credential.currentFormat.title, systemImage: credential.currentFormat.symbol)
                    .font(.headline)
                Spacer()
                Text(L10n.tr("보기 15초 · 복사 30초", "Reveal: 15s · Clipboard: 30s"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(L10n.tr("표시한 내용은 15초 뒤 가려지고, 복사한 내용은 30초 뒤 클립보드에서 지워집니다.", "Revealed contents are hidden after 15 seconds. Copied contents are cleared from the clipboard after 30 seconds."))
            }

            Group {
                if let value = revealedText {
                    revealedContent(value)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("••••••••••••••••••••••••")
                            .font(.system(.body, design: .monospaced))
                            .accessibilityHidden(true)
                        if credential.currentFormat == .keyValue {
                            Text(L10n.tr("필드 이름과 값을 함께 숨겼습니다.", "Field names and values are hidden."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
                    .accessibilityLabel(L10n.tr("내용 숨김", "Contents hidden"))
                }
            }
            .padding(12)
            .foregroundStyle(Theme.ink)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
            .privacySensitive()
            .accessibilityIdentifier("secret-value-display")

            ViewThatFits(in: .horizontal) {
                HStack {
                    revealButton
                    copyButton
                    Spacer(minLength: 6)
                    editButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { revealButton; copyButton }
                    editButton
                }
            }
        }
        .padding(20)
        .cellarCard()
    }

    private var revealButton: some View {
        Button(revealedText == nil ? L10n.tr("내용 보기", "Reveal contents") : L10n.tr("숨기기", "Hide"), systemImage: revealedText == nil ? "eye" : "eye.slash") {
            if revealedText == nil {
                Task { await model.reveal(credential.id) }
            } else {
                model.hideValue()
            }
        }
        .accessibilityIdentifier("secret-reveal")
    }

    private var copyButton: some View {
        Button(copyTitle, systemImage: "doc.on.doc") {
            Task { await model.copyValue(credential.id) }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("secret-copy")
    }

    private var editButton: some View {
        Button(credential.currentFormat == .apiKey ? L10n.tr("키 교체", "Replace key") : L10n.tr("내용 편집", "Edit contents"), systemImage: "pencil") {
            editContent()
        }
        .accessibilityIdentifier("secret-edit-contents")
    }

    @ViewBuilder
    private func revealedContent(_ value: String) -> some View {
        if credential.currentFormat == .apiKey {
            ScrollView(.horizontal) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: 45, alignment: .leading)
            }
        } else if credential.currentFormat == .keyValue,
                  let fields = try? SecretContent.fields(from: value) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(fields, id: \.key) { field in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(field.key)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(field.value)
                                .font(.system(.body, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if field.key != fields.last?.key { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60, maxHeight: 260)
        } else {
            ScrollView {
                Text(value)
                    .font(credential.currentFormat == .text ? .body : .system(.body, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60, maxHeight: 260)
        }
    }
}
