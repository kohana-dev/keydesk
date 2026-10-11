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
            Label("AI 연결", systemImage: "sparkles").font(.title2.bold())
            Text("Codex·Claude Code가 이 프로젝트의 키 이름(예: OPENAI_API_KEY)을 조회할 수 있게 합니다. 키 값은 전달하지 않습니다. AI가 키를 실제로 쓰려면 keydesk run 실행을 이 앱에서 매번 승인해야 하고, 승인한 명령은 키를 읽을 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("프로젝트", selection: $project) { ForEach(model.snapshot?.projects ?? []) { Text($0.name).tag(Optional($0.id)) } }
                Picker("환경", selection: $environment) { ForEach(EnvironmentName.allCases, id: \.self) { Text($0.title).tag($0) } }
            }
            HStack {
                Button("Codex 연결 명령 복사") { model.copyText("codex mcp add keydesk -- \(command)") }.disabled(project == nil)
                Button("Claude Code 연결 명령 복사") { model.copyText("claude mcp add --scope project keydesk -- \(command)") }.disabled(project == nil)
                Button("설정 JSON 저장") { export() }.disabled(project == nil)
            }
            Text("활성 이름 조회 허가").font(.caption.bold())
            List {
                ForEach(Array(model.grants.values).sorted { $0.expiresAt < $1.expiresAt }) { grant in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("키 이름 조회 · \(grant.environment.title)").font(.headline)
                            Text("\(grant.usedCalls)/\(grant.maximumCalls)회 · \(grant.expiresAt.formatted())까지").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("철회", role: .destructive) { model.revokeGrant(grant.id) }
                    }
                }
                if model.grants.isEmpty { Text("활성 사용 허가가 없습니다.").foregroundStyle(.secondary) }
            }.frame(height: 200)
            HStack { Button("모든 AI 허가 철회", role: .destructive) { model.revokeAllGrants() }; Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction) }
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
