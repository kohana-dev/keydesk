import SwiftUI
import KeydeskCore

struct DepositView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    let model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var project = ""
    @State private var variable = ""
    @State private var value = ""
    @State private var fileMode = false
    @State private var file: SecretFile?
    @State private var environment = EnvironmentName.development
    @State private var result: String?
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.tr("잠금 중 새 키 맡기기", "Deposit a new key while locked")).font(.title2.bold())
                    Text(L10n.tr("새 키만 암호화 접수합니다. 기존 키는 읽거나 변경할 수 없습니다. 잠금을 해제할 때 금고에 편입되고 iCloud 백업됩니다.", "Only new keys can be received and encrypted. Existing keys cannot be read or changed. Deposits are added to the vault and backed up to iCloud when you unlock it.")).foregroundStyle(.secondary)
                    TextField(L10n.tr("프로젝트 이름", "Project name"), text: $project)
                    Picker(L10n.tr("환경", "Environment"), selection: $environment) { ForEach(EnvironmentName.allCases, id: \.self) { Text($0.title).tag($0) } }
                    TextField(L10n.tr("환경변수 이름 (예: API_KEY)", "Environment variable name (e.g. API_KEY)"), text: $variable)
                    Toggle(L10n.tr("파일 원본 보관", "Store original key file"), isOn: $fileMode)
                    if fileMode { SecretFileInput(file: $file) }
                    else { SecretInput(title: L10n.tr("새 키 값", "New key value"), value: $value) }
                    if let result { Text(result).font(.callout) }
                }.padding(28)
            }
            DialogFooter {
                DialogDismissButton(prominent: false) { dismiss() }
                Spacer()
                Button(L10n.tr("암호화 접수", "Encrypt and deposit")) {
                    do { result = try model.deposit(SecretDeposit(project: project, environment: environment, variable: variable, value: fileMode ? "" : value, file: fileMode ? file : nil)); value = ""; file = nil }
                    catch { result = L10n.tr("접수하지 못했습니다. 금고를 한 번 열어 접수 키를 준비하거나 입력을 확인하세요.", "Could not accept the deposit. Unlock the vault once to prepare its deposit key, or check your input.") }
                }.buttonStyle(.borderedProminent).disabled(project.isEmpty || variable.isEmpty || (fileMode ? file == nil : value.isEmpty))
            }
        }.frame(width: 560, height: DialogSizing.height(preferred: 532)).textFieldStyle(.roundedBorder)
        .onDisappear { value = ""; file = nil }
    }
}
