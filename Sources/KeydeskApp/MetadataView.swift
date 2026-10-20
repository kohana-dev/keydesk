import SwiftUI
import KeydeskCore

struct MetadataView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    let credential: Credential
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var provider = ""
    @State private var account = ""
    @State private var note = ""
    @State private var value = ""
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    init(model: VaultModel, credential: Credential) {
        self.model = model; self.credential = credential
        _name = State(initialValue: credential.name)
        _provider = State(initialValue: credential.provider)
        _account = State(initialValue: credential.account)
        _note = State(initialValue: credential.note)
    }
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            DialogCloseBar { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        SecretItemIcon(credential: credential)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("항목 정보 편집", "Edit item details")).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(L10n.tr("이름, 서비스와 보관 정보를 수정하세요.", "Update the name, service, and stored details.")).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    TextField(L10n.tr("이름", "Name"), text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
                    ProviderPicker(provider: $provider)
                    if credential.currentFormat == .apiKey {
                        SecretInput(title: L10n.tr("새 키 값 (선택)", "New key value (optional)"), value: $value)
                        Text(L10n.tr("비워두면 기존 키 값을 유지합니다. 입력하면 새 버전으로 저장합니다.", "Leave blank to keep the current key value. Enter a value to save a new version.")).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField(L10n.tr("계정", "Account"), text: $account).textFieldStyle(.roundedBorder)
                    TextField(L10n.tr("메모", "Note"), text: $note).textFieldStyle(.roundedBorder)
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding(28)
            }
            DialogFooter { DialogDismissButton(L10n.tr("취소", "Cancel"), prominent: false) { dismiss() }; Spacer(); Button(L10n.tr("저장", "Save")) {
                do {
                    try model.mutate { next in
                        guard let i = next.credentials.firstIndex(where: { $0.id == credential.id }) else { throw VaultError.invalidData }
                        next.credentials[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines); next.credentials[i].provider = provider
                        next.credentials[i].account = account; next.credentials[i].note = note
                        if !value.isEmpty {
                            guard next.credentials[i].currentFormat == .apiKey else { throw VaultError.invalidData }
                            try SecretContent.validate(value, format: .apiKey)
                            next.credentials[i].rotate(to: value, format: .apiKey)
                        }
                        next.credentials[i].updatedAt = Date(); next.record("항목 정보 편집")
                    }; model.hideValue(); dismiss()
                } catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.frame(width: 540, height: DialogSizing.height(preferred: 522)).controlSize(.large).background(Theme.surface)
        .task { nameFocused = true }
        .onDisappear { value = "" }
    }
}
