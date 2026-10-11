import SwiftUI
import KeydeskCore

struct ApprovalStatusView: View {
    @Bindable var model: VaultModel
    private func lifetime(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return "\(seconds / 60)분 \(seconds % 60)초 남음"
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List {
                Section("CLI 명령 · 키/파일을 실행 프로그램에 전달") {
                    ForEach(model.rememberedRuns.filter { $0.expiresAt > context.date }) { grant in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(grant.invocation.project) · \(grant.invocation.environment.title)").font(.headline)
                                Text(grant.invocation.command.joined(separator: " ")).font(.system(.caption, design: .monospaced)).lineLimit(3)
                                Text("작업 폴더: \(grant.invocation.directory)").font(.caption).foregroundStyle(.secondary)
                                Text("키/파일: \(((grant.invocation.variables ?? []) + (grant.invocation.fileVariables ?? []) + (grant.invocation.stdinKey.map { [$0] } ?? [])).joined(separator: ", "))").font(.caption)
                                Text("\(lifetime(grant.expiresAt, now: context.date)) · \(grant.invocation.environment != .production ? "기간 내 재실행" : "재실행 \(grant.remainingUses)회 남음")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Button("철회") { model.revokeRun(grant.id) }.accessibilityLabel("이 명령의 반복 실행 허가 철회")
                        }.padding(.vertical, 5)
                    }
                    if model.rememberedRuns.isEmpty { Text("기억한 명령 승인이 없습니다.").foregroundStyle(.secondary) }
                }
                Section("API 요청 · 앱이 인증값을 넣어 호출") {
                    ForEach(model.apiApprovals.active(now: context.date)) { grant in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(model.snapshot?.projects.first(where: { $0.id.uuidString == grant.request.project })?.name ?? grant.request.project) · \(grant.request.environment.title) · \(grant.request.variable)").font(.headline)
                                let url = URLComponents(string: grant.request.url)
                                Text("\(grant.request.method) \(url?.host ?? "")\(url?.path ?? "")").font(.system(.caption, design: .monospaced))
                                Text("쿼리·본문 포함 확인값 \(grant.request.fingerprint.prefix(12))").font(.caption)
                                Text("\(lifetime(grant.expiresAt, now: context.date)) · 재실행 \(grant.remainingUses)회 남음").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Button("철회") { model.revokeAPI(grant.id) }.accessibilityLabel("이 API 요청의 반복 사용 허가 철회")
                        }.padding(.vertical, 5)
                    }
                    if model.apiApprovals.active(now: context.date).isEmpty { Text("기억한 API 승인이 없습니다.").foregroundStyle(.secondary) }
                }
                Section("MCP 키 이름 조회 · 값은 전달하지 않음") {
                    ForEach(Array(model.grants.values).filter { $0.expiresAt > context.date }.sorted { $0.expiresAt < $1.expiresAt }) { grant in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(model.snapshot?.projects.first(where: { $0.id == grant.projectID })?.name ?? "프로젝트") · \(grant.environment.title)")
                                Text("\(lifetime(grant.expiresAt, now: context.date)) · 조회 \(max(0, grant.maximumCalls - grant.usedCalls))회 남음").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Button("철회") { model.revokeGrant(grant.id) }
                        }
                    }
                    if model.grants.isEmpty { Text("키 이름 조회 허가가 없습니다.").foregroundStyle(.secondary) }
                }
                Section("실행 중 · 철회와 종료는 별도") {
                    ForEach(model.runningCommands, id: \.0) { id, _ in
                        HStack {
                            VStack(alignment: .leading) {
                                Label("CLI 실행 · \(id.uuidString.prefix(8))", systemImage: "terminal")
                                if let request = model.runningInvocations[id] { Text("\(request.project) · \(request.environment.title) · \(request.command.joined(separator: " "))").font(.caption).lineLimit(2) }
                            }
                            Spacer(); Button("종료 요청") { model.terminateRun(id) }
                        }
                    }
                    ForEach(Array(model.apiRunning.keys).sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                        HStack { Label("API 요청 · \(id.uuidString.prefix(8))", systemImage: "network"); Spacer(); Button("취소 요청") { model.cancelAPI(id) } }
                    }
                    if model.runningCommands.isEmpty && model.apiRunning.isEmpty { Text("실행 중인 작업이 없습니다.").foregroundStyle(.secondary) }
                }
            }
        }
    }
}
