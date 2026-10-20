import AppKit
import SwiftUI
import KeydeskCore

struct KeyValueEditor: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Binding var fields: [SecretField]
    @Environment(\.scenePhase) private var scenePhase
    @State private var showValues = false

    private var encodedBytes: Int? {
        (try? SecretContent.encode(fields: fields))?.utf8.count
    }

    var body: some View {
        let _ = interfaceLanguage
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("이름과 값", "Names and values")).font(.callout.weight(.semibold))
                Spacer()
                Button(showValues ? L10n.tr("값 숨기기", "Hide values") : L10n.tr("값 보기", "Show values"), systemImage: showValues ? "eye.slash" : "eye") {
                    showValues.toggle()
                }
                .accessibilityIdentifier("secret-fields-visibility")
            }
            VStack(spacing: 10) {
                ForEach($fields) { $field in
                    HStack(alignment: .center, spacing: 8) {
                        TextField(L10n.tr("이름 · 예: username", "Name · e.g. username"), text: $field.key)
                            .frame(width: 190)
                            .accessibilityLabel(L10n.tr("필드 이름", "Field name"))
                            .accessibilityIdentifier("secret-field-name-\(field.id.uuidString)")
                        Group {
                            if showValues {
                                TextField(L10n.tr("값", "Value"), text: $field.value)
                            } else {
                                SecureField(L10n.tr("값", "Value"), text: $field.value)
                            }
                        }
                        .privacySensitive()
                        .accessibilityLabel(L10n.tr("필드 값", "Field value"))
                        .accessibilityIdentifier("secret-field-value-\(field.id.uuidString)")
                        Button(L10n.tr("필드 삭제", "Remove field"), systemImage: "minus.circle") {
                            fields.removeAll { $0.id == field.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .disabled(fields.count == 1)
                        .accessibilityIdentifier("secret-field-remove-\(field.id.uuidString)")
                    }
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(12)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button(L10n.tr("필드 추가", "Add field"), systemImage: "plus") {
                    fields.append(SecretField(key: "", value: ""))
                }
                .accessibilityIdentifier("secret-field-add")
                Spacer()
                if let encodedBytes {
                    Text("\(encodedBytes) / \(SecretContent.maximumBytes) B")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("secret-byte-count")
                }
            }
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("secret-content-error")
            }
        }
        .onChange(of: scenePhase) { if scenePhase != .active { showValues = false } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in showValues = false }
        .onDisappear { showValues = false }
    }

    private var validationMessage: String? {
        let keys = fields.map(\.key)
        let nonempty = keys.filter { !$0.isEmpty }
        if Set(nonempty).count != nonempty.count {
            return L10n.tr("필드 이름이 중복됩니다. 이름은 각각 달라야 합니다.", "Field names must be unique.")
        }
        if fields.contains(where: { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), fields.contains(where: { !$0.key.isEmpty || !$0.value.isEmpty }) {
            return L10n.tr("각 필드에 이름을 입력하거나 사용하지 않는 필드를 삭제하세요.", "Give each field a name or remove unused fields.")
        }
        if encodedBytes == nil, fields.contains(where: { !$0.key.isEmpty }) {
            return L10n.tr("입력한 내용을 확인해 주세요. 전체 내용은 최대 64 KiB까지 보관할 수 있습니다.", "Check the fields. Their combined content must be no larger than 64 KiB.")
        }
        return nil
    }
}
