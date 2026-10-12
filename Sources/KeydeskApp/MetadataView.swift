import SwiftUI
import KeydeskCore

struct MetadataView: View {
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ProviderIcon(provider: provider)
                VStack(alignment: .leading, spacing: 4) {
                    Text("키 정보 편집").font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("이름, 서비스와 보관 정보를 수정하세요.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Divider()
            TextField("이름", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
            ProviderPicker(provider: $provider)
            if credential.currentFile == nil { SecretInput(title: "새 키 값 (선택)", value: $value) }
            Text("비워두면 기존 키 값을 유지합니다. 입력하면 새 버전으로 저장합니다.").font(.caption).foregroundStyle(.secondary)
            TextField("계정", text: $account).textFieldStyle(.roundedBorder)
            TextField("메모", text: $note).textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("취소") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("저장") {
                do {
                    try model.mutate { next in
                        guard let i = next.credentials.firstIndex(where: { $0.id == credential.id }) else { throw VaultError.invalidData }
                        next.credentials[i].name = name; next.credentials[i].provider = provider
                        next.credentials[i].account = account; next.credentials[i].note = note
                        if !value.isEmpty {
                            guard value.utf8.count <= 65_536, !value.contains("\0") else { throw VaultError.invalidData }
                            next.credentials[i].rotate(to: value)
                        }
                        next.credentials[i].updatedAt = Date(); next.record("키 정보 편집")
                    }; dismiss()
                } catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(28).frame(width: 540).controlSize(.large).background(Theme.surface)
        .task { nameFocused = true }
        .onDisappear { value = "" }
    }
}
