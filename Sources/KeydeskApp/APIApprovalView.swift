import SwiftUI
import KeydeskCore

struct APIApprovalView: View {
    @Bindable var model: VaultModel
    let approval: APIApproval
    @State private var remember = false
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("API 사용 요청", systemImage: "network").font(.title2.bold())
            Text("\(approval.projectName) · \(approval.request.environment.title)").font(.headline)
            Label(approval.provider.name, systemImage: "checkmark.shield")
            Text("사용할 키: \(approval.request.variable)")
            Text("\(approval.request.method) \(approval.request.url)").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .lineLimit(8).padding(12).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
            Text("JSON 본문 \(approval.request.body?.utf8.count ?? 0)바이트 · 요청 확인값 \(approval.request.fingerprint.prefix(12))").font(.caption)
            if let body = approval.request.body {
                DisclosureGroup("요청 본문 확인") { ScrollView { Text(body).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }.frame(maxHeight: 140) }
            }
            Text("앱이 공식 서비스 주소를 확인하고 인증값을 넣어 호출합니다. AI 호출 프로세스에는 키를 전달하지 않습니다. API 결과는 AI에게 전달되며, 이 요청으로 데이터 변경·삭제 또는 비용 지출이 발생할 수 있습니다.").font(.callout).foregroundStyle(.secondary)
            Toggle(approval.request.environment == .production ? "동일한 요청을 5분간 최대 10회 재실행 허용" : "동일한 요청을 30분간 최대 100회 재실행 허용", isOn: $remember)
            Text("주소·쿼리·메서드·본문·키가 같을 때만 재사용합니다. 허가는 이 Mac의 CLI·MCP에서 공유하며 특정 AI 세션에 한정되지 않습니다. 기간은 연장되지 않으며 잠금·키 변경·앱 종료 시 해제됩니다. 응답을 받기 전에 취소해도 외부 작업이 이미 완료됐을 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("거절") { model.rejectAPI() }.keyboardShortcut(.cancelAction)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("이번 요청 허용") { busy = true; Task { await model.acceptAPI(remember: remember); busy = false } }.buttonStyle(.borderedProminent).disabled(busy)
            }
        }.padding(28).frame(width: 680)
    }
}
