import SwiftUI
import KeydeskCore

struct AIConnectionsView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var project: UUID?
    @State private var environment = EnvironmentName.development
    private func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private var command: String { "\(quoted(model.cliURL.path)) mcp --project \(project?.uuidString ?? "") --env \(environment.rawValue)" }
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "terminal").font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.violet)
                            .frame(width: 48, height: 48).background(Theme.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("AI 연결 · 승인 상태", "AI connections · Approval status")).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(L10n.tr("개발 도구 연결과 사용 허가를 관리하세요.", "Manage developer tool connections and permissions.")).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Text(L10n.tr("CLI 명령은 선택한 키·파일을 실행 프로그램에 전달하고, API 요청은 앱이 인증값을 넣어 호출합니다. 기본은 개별 승인 방식이며 동일한 요청은 제한된 허가를 재사용할 수 있습니다. 일정 시간 모든 요청 허용을 켜면 해당 시간 동안 자동 승인합니다.", "CLI commands pass selected keys and files to the program being run. For API requests, the app adds authentication and makes the call. Individual approval is the default; identical requests can reuse a limited permission. A temporary all-request session automatically approves requests while it is active.")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Picker(L10n.tr("프로젝트", "Project"), selection: $project) { ForEach(model.snapshot?.projects ?? []) { Text($0.name).tag(Optional($0.id)) } }
                        Picker(L10n.tr("환경", "Environment"), selection: $environment) { ForEach(EnvironmentName.allCases, id: \.self) { Text($0.title).tag($0) } }
                    }
                    HStack {
                        Button(L10n.tr("Codex 연결 명령 복사", "Copy Codex connection command")) { model.copyText("codex mcp add keydesk -- \(command)") }.disabled(project == nil)
                        Button(L10n.tr("Claude Code 연결 명령 복사", "Copy Claude Code connection command")) { model.copyText("claude mcp add --scope project keydesk -- \(command)") }.disabled(project == nil)
                        Button(L10n.tr("설정 JSON 저장", "Save configuration JSON")) { export() }.disabled(project == nil)
                    }
                    ApprovalStatusView(model: model).frame(height: 380).cellarCard()
                    Text(L10n.tr("철회는 새 실행을 막습니다. 이미 실행 중인 작업은 종료·취소를 따로 요청하세요. 외부 API에 이미 반영된 작업은 취소되지 않을 수 있습니다.", "Revoking permission blocks new runs. Separately request termination or cancellation for work already running. Actions already applied by an external API may not be reversible.")).font(.caption).foregroundStyle(.secondary)
                }.padding(28)
            }
            DialogFooter {
                Button(L10n.tr("모든 허가 철회", "Revoke all permissions"), role: .destructive) { model.revokeAllPermissions() }
                Spacer()
                DialogDismissButton { dismiss() }
            }
        }
        .frame(width: 780, height: DialogSizing.height(preferred: 720))
        .background(Theme.canvas)
        .onAppear { project = model.selectedProject ?? model.snapshot?.projects.first?.id; environment = model.environment }
    }
    private func export() {
        guard let project else { return }
        let entry = JSONValue.object(["command": .string(model.cliURL.path), "args": .array(["mcp", "--project", project.uuidString, "--env", environment.rawValue].map(JSONValue.string))])
        let config = JSONValue.object(["mcpServers": .object(["keydesk": entry])])
        let panel = NSSavePanel(); panel.nameFieldStringValue = "keydesk-mcp.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; try encoder.encode(config).write(to: url, options: .atomic); model.notify(L10n.tr("값 없는 MCP 설정을 저장했습니다.", "Saved the MCP configuration without secret values.")) }
        catch { model.error = error.localizedDescription }
    }
}
