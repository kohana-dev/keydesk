import SwiftUI
import KeydeskCore

struct CLIApprovalView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    let approval: CLIApproval
    let dialogHeight: CGFloat?
    @State private var busy = false
    @State private var remember = false
    init(model: VaultModel, approval: CLIApproval, dialogHeight: CGFloat? = nil) {
        self.model = model; self.approval = approval
        self.dialogHeight = dialogHeight
        _remember = State(initialValue: approval.request.environment != .production)
    }
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            DialogCloseBar(L10n.tr("거절하고 닫기", "Deny and close")) { model.rejectCLI() }
                .disabled(busy)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(L10n.tr("CLI 실행 요청", "CLI execution request"), systemImage: "terminal").font(.title2.bold())
                    Text(L10n.tr("프로젝트: \(approval.request.project)", "Project: \(approval.request.project)"))
                    Text(L10n.tr("환경: \(approval.request.environment.title)", "Environment: \(approval.request.environment.title)")).foregroundStyle(approval.request.environment == .production ? .orange : .primary)
                    Text(L10n.tr("작업 폴더: \(approval.request.directory)", "Working directory: \(approval.request.directory)")).font(.caption).textSelection(.enabled)
                    Text(L10n.tr("실행 파일: \(approval.executable.path)", "Executable: \(approval.executable.path)")).font(.caption).textSelection(.enabled)
                    Text(approval.request.command.joined(separator: "\n")).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
                    let warnings = CommandRisk.warnings(for: approval.request.command)
                    if !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(L10n.tr("키가 노출될 수 있는 명령입니다", "This command may expose keys"), systemImage: "exclamationmark.triangle.fill").font(.headline)
                            ForEach(warnings, id: \.self) { Text("• " + $0).font(.callout) }
                            Text(L10n.tr("AI가 만든 명령이라면 내용을 확인한 뒤 허용하세요.", "If AI generated this command, review it before allowing it.")).font(.callout)
                        }.foregroundStyle(.orange).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let key = approval.request.stdinKey { Text(L10n.tr("표준입력에만 전달: \(key)", "Pass only through standard input: \(key)")).font(.caption) }
                    if let files = approval.request.fileVariables { Text(L10n.tr("임시 파일 경로로 전달: \(files.joined(separator: ", "))", "Pass as temporary file paths: \(files.joined(separator: ", "))")).font(.caption) }
                    if let variables = approval.request.variables { Text(L10n.tr("선택 변수: \(variables.joined(separator: ", "))", "Selected variables: \(variables.joined(separator: ", "))")).font(.caption) }
                    if let selections = approval.request.selections, !selections.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(L10n.tr("문서에서 선택한 필드", "Selected document fields"), systemImage: "list.bullet.rectangle").font(.headline)
                            ForEach(selections, id: \.variable) { field in
                                Text("\(field.variable) ← \(field.source)#\(field.pointer)")
                                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                            Text(L10n.tr("표시한 필드만 전달하며 문서 전체와 다른 필드는 전달하지 않습니다.", "Only these fields are passed. The full document and other fields stay in the vault."))
                                .font(.caption).foregroundStyle(.secondary)
                        }.accessibilityIdentifier("cli-selected-fields")
                    }
                    Text(L10n.tr("명시한 키만 전달합니다. 실행 코드는 키를 읽거나 외부로 전송할 수 있습니다. 요청의 프로젝트·경로·명령은 호출자가 제공한 정보입니다. 승인 후 실행 파일이 바뀌면 거부합니다. 스크립트와 하위 프로그램까지 검증하지는 않습니다.", "Only the specified keys are passed. The code being run can read or transmit them externally. The caller supplies the project, path, and command in this request. If the executable changes after approval, execution is denied. Scripts and child programs are not verified.")).font(.callout).foregroundStyle(.secondary)
                    Text(approval.request.interactive == true ? L10n.tr("대화형 터미널 · TTY 사용", "Interactive terminal · Uses a TTY") : L10n.tr("표준입력과 출력 전달", "Forward standard input and output")).font(.caption)
                    Text(approval.request.keepRunning == true ? L10n.tr("금고 잠금 후에도 이 실행을 유지합니다. 이미 전달된 키도 프로세스에 남습니다. CLI 연결이나 앱 종료 시 종료를 요청합니다.", "Keep this run active after the vault locks. Keys already passed remain in the process. Termination is requested when the CLI connection ends or the app quits.") : L10n.tr("금고 잠금 시 종료를 요청합니다.", "Termination is requested when the vault locks.")).font(.caption).foregroundStyle(.secondary)
                    if DevelopmentApprovalCache.eligible(approval.request) {
                        Toggle(approval.request.environment == .production ? L10n.tr("동일한 운영 명령을 5분간 최대 10회 재실행 허용", "Allow up to 10 reruns of this production command for 5 minutes") : L10n.tr("동일한 개발 명령을 30분간 허용", "Allow this same development command for 30 minutes"), isOn: $remember)
                        if approval.request.environment == .production {
                            Text(L10n.tr("최초 허용 시 OS 인증이 필요합니다. 기간은 재실행으로 연장되지 않습니다. 직접 지정한 파일과 일부 패키지 설정도 확인하지만, 불러오는 의존성과 하위 프로그램은 검증하지 않습니다. 재사용은 매번 승인하는 것보다 확인 기회를 줄입니다.", "Initial approval requires OS authentication. Reruns do not extend the permission period. Explicitly specified files and some package settings are checked, but loaded dependencies and child programs are not verified. Reusing permission provides fewer review opportunities than approving each run.")).font(.caption).foregroundStyle(.orange)
                        }
                        Text(L10n.tr("프로젝트·키 이름·필드 경로·출력 변수·폴더·명령·실행 파일이 같을 때 재사용합니다. 잠금·키 변경·앱 종료 시 해제됩니다. 이 도구가 불러오는 코드와 하위 프로그램은 바뀔 수 있습니다.", "Permission is reused only when the project, key names, field paths, output variables, directory, command, and executable match. It is cleared when the vault locks, keys change, or the app quits. Code loaded by this tool and its child programs can change.")).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(28)
            }
            DialogFooter {
                DialogDismissButton(L10n.tr("거절", "Deny"), prominent: false) { model.rejectCLI() }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(L10n.tr("이번 실행 허용", "Allow this run")) { busy = true; Task { await model.acceptCLI(remember: remember); busy = false } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(busy)
            }
        }.frame(width: 650, height: dialogHeight ?? DialogSizing.height(preferred: 640))
        .interactiveDismissDisabled(busy)
    }
}
