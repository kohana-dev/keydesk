import SwiftUI
import KeydeskCore

struct ApprovalStatusView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    private func lifetime(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return L10n.tr("\(seconds / 60)분 \(seconds % 60)초 남음", "\(seconds / 60)m \(seconds % 60)s remaining")
    }
    var body: some View {
        let _ = interfaceLanguage
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List {
                TimedApprovalSection(model: model)
                Section(L10n.tr("CLI 명령 · 키/파일을 실행 프로그램에 전달", "CLI commands · Keys/files passed to the program")) {
                    ForEach(model.rememberedRuns.filter { $0.expiresAt > context.date }) { grant in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(grant.invocation.project) · \(grant.invocation.environment.title)").font(.headline)
                                Text(grant.invocation.command.joined(separator: " ")).font(.system(.caption, design: .monospaced)).lineLimit(3)
                                Text(L10n.tr("작업 폴더: \(grant.invocation.directory)", "Working directory: \(grant.invocation.directory)")).font(.caption).foregroundStyle(.secondary)
                                Text(L10n.tr("키/파일: \(((grant.invocation.variables ?? []) + (grant.invocation.fileVariables ?? []) + (grant.invocation.stdinKey.map { [$0] } ?? [])).joined(separator: ", "))", "Keys/files: \(((grant.invocation.variables ?? []) + (grant.invocation.fileVariables ?? []) + (grant.invocation.stdinKey.map { [$0] } ?? [])).joined(separator: ", "))")).font(.caption)
                                ForEach(grant.invocation.selections ?? [], id: \.variable) { field in
                                    Text("\(field.variable) ← \(field.source)#\(field.pointer)").font(.system(.caption, design: .monospaced))
                                }
                                Text("\(lifetime(grant.expiresAt, now: context.date)) · \(grant.invocation.environment != .production ? L10n.tr("기간 내 재실행", "Reruns during this period") : L10n.tr("재실행 \(grant.remainingUses)회 남음", "\(grant.remainingUses) reruns remaining"))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Button(L10n.tr("철회", "Revoke")) { model.revokeRun(grant.id) }.accessibilityLabel(L10n.tr("이 명령의 반복 실행 허가 철회", "Revoke permission to repeat this command"))
                        }.padding(.vertical, 5)
                    }
                    if model.rememberedRuns.isEmpty { Text(L10n.tr("기억한 명령 승인이 없습니다.", "No remembered command approvals.")).foregroundStyle(.secondary) }
                }
                Section(L10n.tr("API 요청 · 앱이 인증값을 넣어 호출", "API requests · App adds authentication and calls")) {
                    ForEach(model.apiApprovals.active(now: context.date)) { grant in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(model.snapshot?.projects.first(where: { $0.id.uuidString == grant.request.project })?.name ?? grant.request.project) · \(grant.request.environment.title) · \(grant.request.variable)").font(.headline)
                                let url = URLComponents(string: grant.request.url)
                                if let field = grant.request.field {
                                    Text("\(grant.request.variable)#\(field) · \(grant.request.provider ?? "")").font(.system(.caption, design: .monospaced))
                                }
                                Text("\(grant.request.method) \(url?.host ?? "")\(url?.path ?? "")").font(.system(.caption, design: .monospaced))
                                Text(L10n.tr("쿼리·본문 포함 확인값 \(grant.request.fingerprint.prefix(12))", "Fingerprint including query and body: \(grant.request.fingerprint.prefix(12))")).font(.caption)
                                Text(L10n.tr("\(lifetime(grant.expiresAt, now: context.date)) · 재실행 \(grant.remainingUses)회 남음", "\(lifetime(grant.expiresAt, now: context.date)) · \(grant.remainingUses) repeats remaining")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Button(L10n.tr("철회", "Revoke")) { model.revokeAPI(grant.id) }.accessibilityLabel(L10n.tr("이 API 요청의 반복 사용 허가 철회", "Revoke permission to repeat this API request"))
                        }.padding(.vertical, 5)
                    }
                    if model.apiApprovals.active(now: context.date).isEmpty { Text(L10n.tr("기억한 API 승인이 없습니다.", "No remembered API approvals.")).foregroundStyle(.secondary) }
                }
                Section(L10n.tr("MCP 키 이름 조회 · 값은 전달하지 않음", "MCP key-name lookup · Values are not passed")) {
                    ForEach(Array(model.grants.values).filter { $0.expiresAt > context.date }.sorted { $0.expiresAt < $1.expiresAt }) { grant in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(model.snapshot?.projects.first(where: { $0.id == grant.projectID })?.name ?? L10n.tr("프로젝트", "Project")) · \(grant.environment.title)")
                                Text(L10n.tr("\(lifetime(grant.expiresAt, now: context.date)) · 조회 \(max(0, grant.maximumCalls - grant.usedCalls))회 남음", "\(lifetime(grant.expiresAt, now: context.date)) · \(max(0, grant.maximumCalls - grant.usedCalls)) lookups remaining")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Button(L10n.tr("철회", "Revoke")) { model.revokeGrant(grant.id) }
                        }
                    }
                    if model.grants.isEmpty { Text(L10n.tr("키 이름 조회 허가가 없습니다.", "No key-name lookup permissions.")).foregroundStyle(.secondary) }
                }
                Section(L10n.tr("실행 중 · 철회와 종료는 별도", "Running · Revoking and stopping are separate")) {
                    ForEach(model.runningCommands, id: \.0) { id, _ in
                        HStack {
                            VStack(alignment: .leading) {
                                Label(L10n.tr("CLI 실행 · \(id.uuidString.prefix(8))", "CLI run · \(id.uuidString.prefix(8))"), systemImage: "terminal")
                                if let request = model.runningInvocations[id] { Text("\(request.project) · \(request.environment.title) · \(request.command.joined(separator: " "))").font(.caption).lineLimit(2) }
                            }
                            Spacer(); Button(L10n.tr("종료 요청", "Request termination")) { model.terminateRun(id) }
                        }
                    }
                    ForEach(Array(model.apiRunning.keys).sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                        HStack { Label(L10n.tr("API 요청 · \(id.uuidString.prefix(8))", "API request · \(id.uuidString.prefix(8))"), systemImage: "network"); Spacer(); Button(L10n.tr("취소 요청", "Request cancellation")) { model.cancelAPI(id) } }
                    }
                    if model.runningCommands.isEmpty && model.apiRunning.isEmpty { Text(L10n.tr("실행 중인 작업이 없습니다.", "No work is currently running.")).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
