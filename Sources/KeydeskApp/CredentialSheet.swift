import SwiftUI
import KeydeskCore

struct CredentialSheet: View {
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
        VStack(alignment: .leading, spacing: 18) {
            Text("키 등록 또는 연결").font(.title2.bold())
            if model.selectedProject != nil {
                Toggle("이미 보관된 키 연결", isOn: $linking)
                Text(model.environment.title).font(.caption).foregroundStyle(.secondary)
                TextField("변수명 · 예: OPENAI_API_KEY", text: $variable).textFieldStyle(.roundedBorder)
            }
            if linking {
                Picker("기존 키", selection: $existing) {
                    Text("선택하세요").tag(nil as UUID?)
                    ForEach(model.snapshot?.credentials ?? []) { Text("\($0.name) · \($0.provider)").tag(Optional($0.id)) }
                }
            } else {
                TextField("키 이름", text: $name).textFieldStyle(.roundedBorder)
                ProviderPicker(provider: $provider)
                Toggle("파일 원본 보관", isOn: $fileMode)
                if fileMode { SecretFileInput(file: $file) }
                else { SecretInput(title: "키 값 · 공백도 그대로 보관", value: $value) }
                TextField("발급 계정 (선택)", text: $account).textFieldStyle(.roundedBorder)
                TextField("메모 (선택)", text: $note).textFieldStyle(.roundedBorder)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("저장") {
                    do {
                        let chosen = model.snapshot?.credentials.first { $0.id == existing }
                        try model.addCredential(name: linking ? chosen?.name ?? "" : name, value: linking ? "" : value, provider: provider, account: account, note: note, variable: variable, existingID: linking ? existing : nil, file: !linking && fileMode ? file : nil)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(linking ? existing == nil : name.isEmpty || (fileMode ? file == nil : value.isEmpty))
            }
        }.padding(28).frame(width: 520)
        .onDisappear { value = ""; file = nil }
    }
}
