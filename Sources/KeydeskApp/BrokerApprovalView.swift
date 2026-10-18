import SwiftUI
import KeydeskCore

struct BrokerApprovalView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    let approval: BrokerApproval
    var dialogHeight: CGFloat? = nil
    @State private var busy = false
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            DialogCloseBar(L10n.tr("거절하고 닫기", "Deny and close")) { model.rejectBroker() }
                .disabled(busy)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(L10n.tr("AI가 키 이름 목록을 요청합니다", "AI is requesting key names"), systemImage: "sparkles").font(.title2.bold())
                    Text(L10n.tr("프로젝트: \(approval.projectName) · \(approval.request.environment.title)", "Project: \(approval.projectName) · \(approval.request.environment.title)"))
                    Text(L10n.tr("허용하면 이 프로젝트·환경에 연결된 환경변수 이름(예: OPENAI_API_KEY)과 서비스 이름을 AI가 볼 수 있습니다. 키 값은 전달하지 않습니다.", "If allowed, AI can see the environment variable names (e.g. OPENAI_API_KEY) and service names associated with this project and environment. Key values are not passed."))
                    Text(L10n.tr("만료: \(approval.grant.expiresAt.formatted(Date.FormatStyle().locale(L10n.locale))) · 최대 \(approval.grant.maximumCalls)회 조회", "Expires: \(approval.grant.expiresAt.formatted(Date.FormatStyle().locale(L10n.locale))) · Up to \(approval.grant.maximumCalls) lookups")).font(.callout)
                    Text(L10n.tr("AI가 키를 실제로 사용하려면 실행할 때마다 이 앱에서 따로 승인해야 합니다.", "For AI to actually use keys, each execution must be approved separately in this app.")).font(.callout).foregroundStyle(.secondary)
                }.padding(28)
            }
            DialogFooter {
                DialogDismissButton(L10n.tr("거절", "Deny"), prominent: false) { model.rejectBroker() }
                Spacer()
                if busy { ProgressView() }
                Button(L10n.tr("이름 목록 허용", "Allow key-name lookup")) { busy = true; Task { await model.acceptBroker(); busy = false } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(busy)
            }
        }.frame(width: 600, height: dialogHeight ?? DialogSizing.height(preferred: 440)).interactiveDismissDisabled(busy)
    }
}
