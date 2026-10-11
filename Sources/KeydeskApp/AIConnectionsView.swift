import SwiftUI
import KeydeskCore

struct AIConnectionsView: View {
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var project: UUID?
    @State private var environment = EnvironmentName.development
    private func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private var command: String { "\(quoted(model.cliURL.path)) mcp --project \(project?.uuidString ?? "") --env \(environment.rawValue)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("AI 연결 · 승인 상태", systemImage: "sparkles").font(.title2.bold())
            Text("CLI 명령은 선택한 키·파일을 실행 프로그램에 전달하고, API 요청은 앱이 인증값을 넣어 호출합니다. 최초 승인이 필요하며 동일한 요청은 제한된 허가를 재사용할 수 있습니다. MCP 키 이름 조회 허가는 별도입니다.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("프로젝트", selection: $project) { ForEach(model.snapshot?.projects ?? []) { Text($0.name).tag(Optional($0.id)) } }
                Picker("환경", selection: $environment) { ForEach(EnvironmentName.allCases, id: \.self) { Text($0.title).tag($0) } }
            }
            HStack {
                Button("Codex 연결 명령 복사") { model.copyText("codex mcp add keydesk -- \(command)") }.disabled(project == nil)
                Button("Claude Code 연결 명령 복사") { model.copyText("claude mcp add --scope project keydesk -- \(command)") }.disabled(project == nil)
                Button("설정 JSON 저장") { export() }.disabled(project == nil)
            }
            ApprovalStatusView(model: model).frame(height: 380)
            Text("철회는 새 실행을 막습니다. 이미 실행 중인 작업은 종료·취소를 따로 요청하세요. 외부 API에 이미 반영된 작업은 취소되지 않을 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("모든 반복·조회 허가 철회", role: .destructive) { model.revokeAllPermissions() }; Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width: 780)
        .onAppear { project = model.selectedProject ?? model.snapshot?.projects.first?.id; environment = model.environment }
    }
    private func export() {
        guard let project else { return }
        let entry = JSONValue.object(["command": .string(model.cliURL.path), "args": .array(["mcp", "--project", project.uuidString, "--env", environment.rawValue].map(JSONValue.string))])
        let config = JSONValue.object(["mcpServers": .object(["keydesk": entry])])
        let panel = NSSavePanel(); panel.nameFieldStringValue = "keydesk-mcp.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; try encoder.encode(config).write(to: url, options: .atomic); model.notify("값 없는 MCP 설정을 저장했습니다.") }
        catch { model.error = error.localizedDescription }
    }
}
