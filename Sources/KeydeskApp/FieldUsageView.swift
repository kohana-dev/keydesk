import SwiftUI
import KeydeskCore

/// Builds names-only commands. Selecting a field never reads its value into this view.
struct FieldUsageView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: VaultModel
    let binding: BindingRecord
    let storedProvider: String
    @State private var pointer = "/password"
    @State private var output = "SELECTED_VALUE"
    @State private var provider: String
    @State private var url: String

    init(model: VaultModel, binding: BindingRecord, storedProvider: String) {
        self.model = model; self.binding = binding; self.storedProvider = storedProvider
        let name = APIProvider.supported.first { $0.name == ProviderName.canonical(storedProvider) }?.name ?? "OpenAI"
        _provider = State(initialValue: name)
        _url = State(initialValue: APIProvider.supported.first { $0.name == name }?.defaultURL ?? "https://api.openai.com/")
    }

    private var selection: SecretFieldSelection? {
        guard let field = try? SecretFieldSelection(variable: output, source: binding.variable, pointer: pointer).validated() else { return nil }
        let request = CLIRequest(project: binding.projectID.uuidString, environment: binding.environment, command: ["npm", "run", "dev"], directory: "/", stdinKey: nil, selections: [field])
        guard (try? request.selectedSecrets(from: [output: ""])) != nil else { return nil }
        return field
    }
    private func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private var runCommand: String {
        "keydesk run --project \(binding.projectID.uuidString) --env \(binding.environment.rawValue) --select \(quoted("\(output)=\(binding.variable)#\(pointer)")) -- npm run dev"
    }
    private var apiRequest: APIRequest {
        APIRequest(project: binding.projectID.uuidString, environment: binding.environment, variable: binding.variable, method: "GET", url: url, field: pointer, provider: provider)
    }
    private var canCopyAPI: Bool { (try? APIProvider.resolve(provider: storedProvider, request: apiRequest)) != nil }
    private var apiCommand: String {
        "keydesk request --project \(binding.projectID.uuidString) --env \(binding.environment.rawValue) --key \(binding.variable) --field \(quoted(pointer)) --provider \(quoted(provider)) --method GET --url \(quoted(url))"
    }

    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            DialogCloseBar { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(L10n.tr("필드 하나만 사용", "Use one field"), systemImage: "list.bullet.rectangle").font(.title2.bold())
                    Text(L10n.tr("원본 참조: \(binding.variable) · \(binding.environment.title)", "Source reference: \(binding.variable) · \(binding.environment.title)"))
                        .font(.callout).textSelection(.enabled)
                    Text(L10n.tr("사용할 경로를 지정해 명령을 복사하세요. 값은 표시하거나 복사하지 않으며, 실제 실행할 때 금고에서 해당 필드만 꺼내 승인을 요청합니다.", "Specify a path and copy a command. No secret value is shown or copied here. The selected field is resolved in the vault when the command runs and requests approval."))
                        .font(.callout).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("JSON Pointer").font(.headline)
                        TextField("/database/password", text: $pointer).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("field-usage-pointer")
                        Text(L10n.tr("예: /password, /database/password, /accounts/0/token. 이름의 /는 ~1, ~는 ~0로 입력합니다. 빈 경로는 루트의 단일 값을 뜻합니다.", "Examples: /password, /database/password, /accounts/0/token. Escape / in a name as ~1, and ~ as ~0. An empty path selects a scalar at the document root."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("CLI 환경 변수", "CLI environment variable")).font(.headline)
                        TextField("SELECTED_VALUE", text: $output).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("field-usage-output")
                        command(runCommand)
                        Button(L10n.tr("CLI 명령 복사", "Copy CLI command")) { model.copyText(runCommand) }
                            .disabled(selection == nil).accessibilityIdentifier("field-usage-copy-cli")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("API 인증 · 문자열 필드만", "API authentication · String fields only")).font(.headline)
                        Picker(L10n.tr("제공사", "Provider"), selection: $provider) {
                            ForEach(APIProvider.supported, id: \.name) { Text($0.name).tag($0.name) }
                        }.disabled(ProviderName.canonical(storedProvider) != "Other")
                        TextField(L10n.tr("공식 HTTPS API 주소", "Official HTTPS API URL"), text: $url).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("field-usage-url")
                        Text(L10n.tr("해당 제공사의 공식 API 주소만 사용할 수 있습니다. 경로가 없거나 문자열 인증값이 아니면 실행을 거부합니다.", "Only official API hosts for this provider are allowed. Missing paths or non-string authentication values are rejected."))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(L10n.tr("API 명령 복사", "Copy API command")) { model.copyText(apiCommand) }
                            .disabled(!canCopyAPI).accessibilityIdentifier("field-usage-copy-api")
                    }
                }.padding(28)
            }
            DialogFooter {
                DialogDismissButton { dismiss() }
                Spacer()
            }
        }.frame(width: 650, height: DialogSizing.height(preferred: 720))
        .onChange(of: provider) {
            url = APIProvider.supported.first { $0.name == provider }?.defaultURL ?? "https://api.openai.com/"
        }
    }

    private func command(_ text: String) -> some View {
        Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
    }
}
