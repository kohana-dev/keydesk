import SwiftUI
import KeydeskCore

struct ContentView: View {
    @Bindable var model: VaultModel
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    var body: some View {
        let _ = interfaceLanguage
        Group {
            if model.snapshot == nil { LockedView(model: model) }
            else { WorkspaceView(model: model) }
        }
        .sheet(isPresented: $model.showQuickAdd) {
            if model.snapshot == nil { DepositView(model: model) }
            else { CredentialSheet(model: model) }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.light)
        .environment(\.locale, L10n.locale)
        .alert(L10n.tr("작업을 완료하지 못했습니다", "Could not complete the action"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(L10n.tr("확인", "OK")) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
