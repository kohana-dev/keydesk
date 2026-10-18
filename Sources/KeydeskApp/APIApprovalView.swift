import SwiftUI
import KeydeskCore

struct APIApprovalView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    let approval: APIApproval
    var dialogHeight: CGFloat? = nil
    @State private var remember = false
    @State private var busy = false
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            DialogCloseBar(L10n.tr("거절하고 닫기", "Deny and close")) { model.rejectAPI() }
                .disabled(busy)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(L10n.tr("API 사용 요청", "API request"), systemImage: "network").font(.title2.bold())
                    Text("\(approval.projectName) · \(approval.request.environment.title)").font(.headline)
                    Label(approval.provider.name, systemImage: "checkmark.shield")
                    Text(L10n.tr("사용할 키: \(approval.request.variable)", "Key to use: \(approval.request.variable)"))
                    Text("\(approval.request.method) \(approval.request.url)").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        .padding(12).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
                    Text(L10n.tr("JSON 본문 \(approval.request.body?.utf8.count ?? 0)바이트 · 요청 확인값 \(approval.request.fingerprint.prefix(12))", "JSON body: \(approval.request.body?.utf8.count ?? 0) bytes · Request fingerprint: \(approval.request.fingerprint.prefix(12))")).font(.caption)
                    if let body = approval.request.body {
                        DisclosureGroup(L10n.tr("요청 본문 확인", "Review request body")) {
                            Text(body).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text(L10n.tr("앱이 공식 서비스 주소를 확인하고 인증값을 넣어 호출합니다. AI 호출 프로세스에는 키를 전달하지 않습니다. API 결과는 AI에게 전달되며, 이 요청으로 데이터 변경·삭제 또는 비용 지출이 발생할 수 있습니다.", "The app checks the official service URL, adds authentication, and makes the call. Keys are not passed to the calling AI process. API results are passed to AI, and this request may change or delete data or incur charges.")).font(.callout).foregroundStyle(.secondary)
                    Toggle(approval.request.environment == .production ? L10n.tr("동일한 요청을 5분간 최대 10회 재실행 허용", "Allow up to 10 repeats of this request for 5 minutes") : L10n.tr("동일한 요청을 30분간 최대 100회 재실행 허용", "Allow up to 100 repeats of this request for 30 minutes"), isOn: $remember)
                    Text(L10n.tr("주소·쿼리·메서드·본문·키가 같을 때만 재사용합니다. 허가는 이 Mac의 CLI·MCP에서 공유하며 특정 AI 세션에 한정되지 않습니다. 기간은 연장되지 않으며 잠금·키 변경·앱 종료 시 해제됩니다. 응답을 받기 전에 취소해도 외부 작업이 이미 완료됐을 수 있습니다.", "Permission is reused only when the URL, query, method, body, and key match. It is shared across CLI and MCP on this Mac, rather than limited to a specific AI session. Its duration is not extended, and it is cleared when the vault locks, keys change, or the app quits. An external action may already be complete even if you cancel before receiving a response.")).font(.caption).foregroundStyle(.secondary)
                }.padding(28)
            }
            DialogFooter {
                DialogDismissButton(L10n.tr("거절", "Deny"), prominent: false) { model.rejectAPI() }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(L10n.tr("이번 요청 허용", "Allow this request")) { busy = true; Task { await model.acceptAPI(remember: remember); busy = false } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(busy)
            }
        }.frame(width: 680, height: dialogHeight ?? DialogSizing.height(preferred: 640))
    }
}
