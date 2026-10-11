import SwiftUI
import KeydeskCore

struct BrokerApprovalView: View {
    @Bindable var model: VaultModel
    let approval: BrokerApproval
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("AI가 키 이름 목록을 요청합니다", systemImage: "sparkles").font(.title2.bold())
            Text("프로젝트: \(approval.projectName) · \(approval.request.environment.title)")
            Text("허용하면 이 프로젝트·환경에 연결된 환경변수 이름(예: OPENAI_API_KEY)과 서비스 이름을 AI가 볼 수 있습니다. 키 값은 전달하지 않습니다.")
            Text("만료: \(approval.grant.expiresAt.formatted()) · 최대 \(approval.grant.maximumCalls)회 조회").font(.callout)
            Text("AI가 키를 실제로 사용하려면 실행할 때마다 이 앱에서 따로 승인해야 합니다.").font(.callout).foregroundStyle(.secondary)
            HStack { Button("거절") { model.rejectBroker() }.keyboardShortcut(.cancelAction); Spacer(); if busy { ProgressView() }; Button("이름 목록 허용") { busy = true; Task { await model.acceptBroker(); busy = false } }.buttonStyle(.borderedProminent).disabled(busy) }
        }.padding(28).frame(width: 600).interactiveDismissDisabled(busy)
    }
}
