import SwiftUI
import KeydeskCore

struct ActivityView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let _ = interfaceLanguage
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.tr("활동 기록", "Activity")).font(.title2.bold())
            Text(L10n.tr("최근 200개 이벤트를 금고 안에 암호화해 보관합니다. 비밀 값은 기록하지 않으며, 변조 불가능한 감사 로그는 아닙니다.", "The latest 200 events are encrypted in the vault. Secret values are not recorded. This is not a tamper-proof audit log.")).font(.caption).foregroundStyle(.secondary)
            List(model.snapshot?.activities ?? []) { record in
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.activity(record.action))
                    Text(record.date, format: .dateTime.year().month().day().hour().minute().locale(L10n.locale)).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(height: 300)
            HStack { Spacer(); Button(L10n.tr("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width: 580)
    }
}
