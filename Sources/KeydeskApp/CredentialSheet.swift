import SwiftUI
import KeydeskCore

struct CredentialSheet: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var format = SecretFormat.apiKey
    @State private var apiValue = ""
    @State private var jsonValue = ""
    @State private var textValue = ""
    @State private var fields = [SecretField(key: "", value: "")]
    @State private var file: SecretFile?
    @State private var apiProvider = "OpenAI"
    @State private var contentProvider = "Other"
    @State private var account = ""
    @State private var note = ""
    @State private var detailsExpanded = false
    @State private var variable = ""
    @State private var linking = false
    @State private var existing: UUID?
    @State private var error: String?

    private var editorValue: Binding<String> {
        switch format {
        case .json: $jsonValue
        case .text: $textValue
        case .apiKey, .keyValue, .file: $apiValue
        }
    }

    private var provider: Binding<String> {
        format == .apiKey ? $apiProvider : $contentProvider
    }

    private var selectedExisting: Credential? {
        model.snapshot?.credentials.first { $0.id == existing }
    }

    private var canSave: Bool {
        if linking { return existing != nil }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch format {
        case .file: return file != nil
        case .keyValue: return (try? SecretContent.encode(fields: fields)) != nil
        case .apiKey:
            return !apiValue.isEmpty && (try? SecretContent.validate(apiValue, format: .apiKey)) != nil
        case .json, .text:
            return (try? SecretContent.validate(editorValue.wrappedValue, format: format)) != nil
        }
    }

    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            DialogCloseBar { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if model.selectedProject != nil { projectConnection }
                    if linking { existingItemPicker }
                    else { newItemForm }
                    if let error {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("secret-save-error")
                    }
                }
                .padding(28)
            }
            DialogFooter {
                DialogDismissButton(L10n.tr("취소", "Cancel"), prominent: false) { dismiss() }
                Spacer()
                Button(linking ? L10n.tr("연결", "Connect item") : L10n.tr("저장", "Save item"), action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .accessibilityIdentifier("secret-save")
            }
        }
        .frame(width: 640, height: DialogSizing.height(preferred: 720))
        .controlSize(.large)
        .background(Theme.surface)
        .onChange(of: format) { error = nil }
        .onChange(of: linking) { error = nil }
        .onDisappear(perform: clearDrafts)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.doc")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.selection, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.tr("비밀 항목 추가", "Add a secret"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(L10n.tr("키부터 설정 문서까지, 필요한 형식으로 암호화해 보관하세요.", "Keep keys and configuration documents encrypted in one place."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var projectConnection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.tr("이미 보관된 항목 연결", "Connect an existing item"), isOn: $linking)
                .accessibilityIdentifier("secret-link-existing")
            HStack {
                Text(L10n.tr("프로젝트 참조", "Project reference")).font(.caption.weight(.semibold))
                Spacer()
                Text(model.environment.title).font(.caption).foregroundStyle(.secondary)
            }
            TextField(L10n.tr("변수명 / 참조 이름 · 예: APP_CONFIG", "Variable / reference name · e.g. APP_CONFIG"), text: $variable)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("secret-reference-name")
        }
        .padding(14)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
    }

    private var existingItemPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L10n.tr("보관된 항목", "Saved item"), selection: $existing) {
                Text(L10n.tr("선택하세요", "Select an item")).tag(nil as UUID?)
                ForEach(model.snapshot?.credentials ?? []) { credential in
                    Text("\(credential.name) · \(credential.currentFormat.shortTitle)").tag(Optional(credential.id))
                }
            }
            .accessibilityIdentifier("secret-existing-item")
            if let selectedExisting, selectedExisting.currentFormat != .apiKey, selectedExisting.currentFormat != .file {
                referenceNotice
            }
        }
    }

    private var newItemForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            SecretFormatPicker(format: $format)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("이름", "Name")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField(L10n.tr("예: 서비스 인증 정보 또는 앱 설정", "e.g. Service credentials or app configuration"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("secret-name")
            }
            ProviderPicker(provider: provider)
                .id(format == .apiKey)
            if format != .apiKey {
                Text(L10n.tr("서비스는 선택 사항입니다. 지정하지 않으면 기타로 보관합니다.", "Service is optional. Use Other when no service applies."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SecretPayloadEditor(format: format, value: editorValue, fields: $fields, file: $file)
            DisclosureGroup(L10n.tr("계정 및 메모 (선택)", "Account and notes (optional)"), isExpanded: $detailsExpanded) {
                VStack(spacing: 10) {
                    TextField(L10n.tr("발급 계정", "Account"), text: $account)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("secret-account")
                    TextField(L10n.tr("메모", "Notes"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("secret-notes")
                }
                .padding(.top, 10)
            }
            .font(.callout)
            if format != .apiKey, format != .file { referenceNotice }
        }
    }

    private var referenceNotice: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(L10n.tr("이 형식은 앱에서 보관·복사할 수 있습니다. CLI·API 요청에 자동으로 전달되지 않습니다.", "Store and copy this format in the app. It is not automatically passed to CLI or API requests."), systemImage: "info.circle")
            Text(L10n.tr("이 형식의 금고와 백업은 Cellar 0.7.19 이상에서 사용하세요.", "Use Cellar 0.7.19 or later to open vaults and backups containing this format."))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        do {
            let chosen = selectedExisting
            let payload: String
            if linking || format == .file { payload = "" }
            else if format == .keyValue { payload = try SecretContent.encode(fields: fields) }
            else {
                payload = editorValue.wrappedValue
                try SecretContent.validate(payload, format: format)
            }
            let service = provider.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            try model.addCredential(
                name: linking ? chosen?.name ?? "" : name,
                value: payload,
                provider: service.isEmpty ? "Other" : service,
                account: account,
                note: note,
                variable: variable,
                existingID: linking ? existing : nil,
                file: !linking && format == .file ? file : nil,
                format: linking ? chosen?.currentFormat ?? .apiKey : format
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func clearDrafts() {
        name = ""
        apiValue = ""
        jsonValue = ""
        textValue = ""
        fields.removeAll()
        file = nil
        account = ""
        note = ""
        variable = ""
    }
}
