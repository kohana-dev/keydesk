import SwiftUI
import KeydeskCore

struct CredentialSheet: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var value = ""
    @State private var fileMode = false
    @State private var file: SecretFile?
    @State private var provider = "OpenAI"
    @State private var account = ""
    @State private var note = ""
    @State private var variable = ""
    @State private var linking = false
    @State private var existing: UUID?
    @State private var error: String?
    var body: some View {
        let _ = interfaceLanguage
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                CellarMark(size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("키 등록 또는 연결", "Add or connect a key")).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(L10n.tr("서비스와 프로젝트에 맞게 보관하세요.", "Organize credentials by service and project.")).font(.callout).foregroundStyle(.secondary)
                }
            }
            Divider()
            if model.selectedProject != nil {
                Toggle(L10n.tr("이미 보관된 키 연결", "Connect an existing key"), isOn: $linking)
                Text(model.environment.title).font(.caption).foregroundStyle(.secondary)
                TextField(L10n.tr("변수명 · 예: OPENAI_API_KEY", "Variable name · e.g. OPENAI_API_KEY"), text: $variable).textFieldStyle(.roundedBorder)
            }
            if linking {
                Picker(L10n.tr("기존 키", "Existing key"), selection: $existing) {
                    Text(L10n.tr("선택하세요", "Select a key")).tag(nil as UUID?)
                    ForEach(model.snapshot?.credentials ?? []) { Text("\($0.name) · \($0.provider)").tag(Optional($0.id)) }
                }
            } else {
                TextField(L10n.tr("키 이름", "Key name"), text: $name).textFieldStyle(.roundedBorder)
                ProviderPicker(provider: $provider)
                Toggle(L10n.tr("파일 원본 보관", "Store an original file"), isOn: $fileMode)
                if fileMode { SecretFileInput(file: $file) }
                else { SecretInput(title: L10n.tr("키 값 · 공백도 그대로 보관", "Key value · Whitespace is preserved"), value: $value) }
                TextField(L10n.tr("발급 계정 (선택)", "Account (optional)"), text: $account).textFieldStyle(.roundedBorder)
                TextField(L10n.tr("메모 (선택)", "Note (optional)"), text: $note).textFieldStyle(.roundedBorder)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L10n.tr("취소", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(linking ? L10n.tr("저장", "Connect key") : L10n.tr("저장", "Add key")) {
                    do {
                        let chosen = model.snapshot?.credentials.first { $0.id == existing }
                        try model.addCredential(name: linking ? chosen?.name ?? "" : name, value: linking ? "" : value, provider: provider, account: account, note: note, variable: variable, existingID: linking ? existing : nil, file: !linking && fileMode ? file : nil)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(linking ? existing == nil : name.isEmpty || (fileMode ? file == nil : value.isEmpty))
            }
        }.padding(28).frame(width: 540).controlSize(.large).background(Theme.surface)
        .onDisappear { value = ""; file = nil }
    }
}
