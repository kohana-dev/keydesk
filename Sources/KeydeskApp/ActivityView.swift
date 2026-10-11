import SwiftUI

struct ActivityView: View {
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("활동 기록").font(.title2.bold())
            Text("최근 200개 이벤트를 금고 안에 암호화해 보관합니다. 비밀 값은 기록하지 않으며, 변조 불가능한 감사 로그는 아닙니다.").font(.caption).foregroundStyle(.secondary)
            List(model.snapshot?.activities ?? []) { record in
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.action)
                    Text(record.date, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(height: 300)
            HStack { Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width: 580)
    }
}
