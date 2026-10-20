import SwiftUI
import KeydeskCore

struct RotateView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    let credential: Credential
    @Environment(\.dismiss) private var dismiss
    @State private var editingVersionID: UUID
    @State private var editingFormat: SecretFormat
    @State private var value = ""
    @State private var fields: [SecretField] = []
    @State private var file: SecretFile?
    @State private var error: String?
    @State private var loading = false
    @State private var loaded = false
    @State private var loadAttempt = 0

    init(model: VaultModel, credential: Credential) {
        self.model = model
        self.credential = credential
        _editingVersionID = State(initialValue: credential.currentVersionID)
        _editingFormat = State(initialValue: credential.currentFormat)
    }

    private var needsExistingContent: Bool { editingFormat != .apiKey }
    private var canSave: Bool {
        guard !loading, !needsExistingContent || loaded else { return false }
        switch editingFormat {
        case .keyValue: return (try? SecretContent.encode(fields: fields)) != nil
        case .file: return false
        case .apiKey: return !value.isEmpty && (try? SecretContent.validate(value, format: .apiKey)) != nil
        case .json, .text: return (try? SecretContent.validate(value, format: editingFormat)) != nil
        }
    }

    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            DialogCloseBar { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(needsExistingContent ? L10n.tr("내용 편집", "Edit contents") : L10n.tr("새 키 버전 저장", "New key version")).font(.title2.bold())
                        Spacer()
                        SecretFormatBadge(format: editingFormat)
                    }
                    Text(credential.name).font(.headline)
                    if loading {
                        ProgressView(L10n.tr("인증 후 내용을 불러오는 중…", "Authenticating to load contents…"))
                    } else if needsExistingContent && !loaded {
                        Text(L10n.tr("저장된 내용을 편집하려면 Mac에서 인증해 주세요.", "Authenticate on your Mac to edit stored contents.")).foregroundStyle(.secondary)
                        Button(L10n.tr("인증하고 불러오기", "Authenticate and load")) { loadAttempt += 1 }
                    } else {
                        SecretPayloadEditor(format: editingFormat, value: $value, fields: $fields, file: $file)
                    }
                    if editingFormat == .apiKey {
                        Text(L10n.tr("제공사에서 발급한 새 값을 입력하세요. 아래 연결이 모두 새 버전을 사용합니다.", "Enter the new value issued by the provider. Every connection below will use the new version.")).font(.caption).foregroundStyle(.secondary)
                        ForEach(model.snapshot?.bindings.filter { $0.credentialID == credential.id } ?? []) { binding in
                            Text("\(model.snapshot?.projects.first { $0.id == binding.projectID }?.name ?? "") · \(binding.environment.title) · \(binding.variable)").font(.caption)
                        }
                    }
                    Text(L10n.tr("저장하면 새 버전이 생성되고 이전 내용은 이력에 남습니다.", "Saving creates a new version and keeps the previous contents in history.")).font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("secret-edit-error") }
                }.padding(28)
            }
            DialogFooter {
                DialogDismissButton(L10n.tr("취소", "Cancel"), prominent: false) { dismiss() }
                Spacer()
                Button(L10n.tr("새 버전 저장", "Save new version")) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .accessibilityIdentifier("secret-save-version")
            }
        }
        .frame(width: 640, height: DialogSizing.height(preferred: 680))
        .background(Theme.surface)
        .task(id: loadAttempt) { if needsExistingContent { await loadContents() } }
        .onDisappear { value = ""; fields = []; file = nil; loaded = false }
    }

    private func loadContents() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let content = try await model.authenticatedContentForEditing(credential.id, versionID: editingVersionID)
            try Task.checkCancellation()
            if editingFormat == .keyValue { fields = try SecretContent.fields(from: content) }
            else { value = content }
            loaded = true
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            let content = editingFormat == .keyValue ? try SecretContent.encode(fields: fields) : value
            try model.rotate(credential.id, value: content, format: editingFormat, expectedVersionID: editingVersionID)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
