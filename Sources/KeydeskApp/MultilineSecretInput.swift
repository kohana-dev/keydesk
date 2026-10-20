import AppKit
import SwiftUI
import KeydeskCore

/// Multiline editing is removed from the view tree when the app loses focus.
struct MultilineSecretInput: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    let format: SecretFormat
    @Binding var value: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = true
    @State private var formattingError: String?

    private var byteCount: Int { value.utf8.count }
    private var isValidJSON: Bool {
        format == .json && (try? SecretContent.validate(value, format: .json)) != nil
    }

    var body: some View {
        let _ = interfaceLanguage
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(format == .json ? L10n.tr("JSON 문서", "JSON document") : L10n.tr("비밀 텍스트", "Secret text"))
                    .font(.callout.weight(.semibold))
                Spacer()
                Button(visible ? L10n.tr("숨기기", "Hide") : L10n.tr("보기 및 편집", "Show and edit"), systemImage: visible ? "eye.slash" : "eye") {
                    visible.toggle()
                }
                .accessibilityIdentifier("secret-editor-visibility")
            }
            Group {
                if visible {
                    SecretTextEditor(text: $value, format: format)
                        .privacySensitive()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.doc").font(.title2)
                        Text(L10n.tr("내용이 숨겨져 있습니다.", "Content is hidden."))
                        Text(L10n.tr("보기를 눌러 편집을 계속하세요.", "Choose Show and edit to continue."))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("secret-content-hidden")
                }
            }
            .frame(height: 190)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
            HStack(alignment: .center) {
                if format == .json {
                    Button(L10n.tr("JSON 정렬", "Format JSON"), action: formatJSON)
                        .disabled(!isValidJSON)
                        .accessibilityIdentifier("secret-format-json")
                } else {
                    Text(L10n.tr("공백·줄바꿈 그대로 보관", "Whitespace and line breaks are preserved"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(byteCount) / \(SecretContent.maximumBytes) B")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(byteCount > SecretContent.maximumBytes ? .red : .secondary)
                    .accessibilityIdentifier("secret-byte-count")
            }
            if let message = validationMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("secret-content-error")
            } else if format == .json, !value.isEmpty {
                Label(L10n.tr("올바른 JSON 형식입니다. 정렬은 버튼을 눌렀을 때만 적용됩니다.", "Valid JSON. Formatting is applied only when you choose Format JSON."), systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("secret-json-valid")
            }
        }
        .onChange(of: value) { formattingError = nil }
        .onChange(of: scenePhase) { if scenePhase != .active { hide() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in hide() }
        .onDisappear(perform: hide)
    }

    private var validationMessage: String? {
        if let formattingError { return formattingError }
        if byteCount > SecretContent.maximumBytes {
            return L10n.tr("내용은 최대 64 KiB까지 보관할 수 있습니다.", "Content must be no larger than 64 KiB.")
        }
        if value.contains("\0") {
            return L10n.tr("내용에 NUL 문자를 넣을 수 없습니다.", "Content cannot contain a NUL character.")
        }
        if format == .json, !value.isEmpty, !isValidJSON {
            return L10n.tr("JSON 형식을 확인해 주세요. 따옴표·쉼표·괄호가 올바른지 확인하세요.", "Check the JSON syntax, including quotes, commas, and brackets.")
        }
        return nil
    }

    private func formatJSON() {
        do { value = try SecretContent.formattedJSON(value) }
        catch { formattingError = L10n.tr("JSON을 정렬하지 못했습니다. 원래 내용은 유지됩니다.", "Could not format the JSON. Your original content is unchanged.") }
    }

    private func hide() {
        visible = false
    }
}
