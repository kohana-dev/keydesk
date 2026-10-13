import SwiftUI
import KeydeskCore

/// Shows the recovery key after OS authentication, for keeping a copy outside the Apple Account.
struct RecoveryKeyView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var error: String?
    var body: some View {
        let _ = interfaceLanguage
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("복구 키", "Recovery key")).font(.title2.bold())
            Text(L10n.tr("복구 키는 iCloud 키체인에 자동 저장되어 같은 Apple 계정의 다른 Mac에서 iCloud Drive 백업을 열 때 쓰입니다. Apple 계정에 접근하지 못하게 될 때를 대비하려면 이 키를 종이나 다른 비밀번호 관리자에 따로 보관하세요.", "The recovery key is saved automatically in iCloud Keychain and opens your iCloud Drive backup on another Mac using the same Apple Account. Keep a separate copy on paper or in another password manager in case you lose access to your Apple Account.")).foregroundStyle(.secondary)
            if let code {
                Text(code).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12)).privacySensitive()
                Button(L10n.tr("복구 키 복사 · 30초 후 삭제", "Copy recovery key · Clear clipboard after 30 seconds"), systemImage: "doc.on.doc") { model.copyRecovery(code) }
            } else if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            } else {
                ProgressView()
            }
            HStack { Spacer(); Button(L10n.tr("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width: 560)
        .task {
            do {
                guard let value = try await model.authenticatedRecoveryCode() else { error = L10n.tr("이 금고에는 앱에 저장된 복구 키 사본이 없습니다.", "The app has no stored copy of the recovery key for this vault."); return }
                code = value
            } catch { self.error = L10n.tr("인증하지 않아 복구 키를 표시하지 않았습니다.", "The recovery key was not shown because authentication was not completed.") }
        }
        .onDisappear { code = nil }
    }
}
