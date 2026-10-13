import SwiftUI
import AppKit
import KeydeskCore

struct MainWindowView: View {
    let model: VaultModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 1000, minHeight: 680)
            .onChange(of: interfaceLanguage) { model.languageDidChange() }
            .onAppear {
                delegate.model = model
                delegate.reopenMainWindow = {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                NSApp.activate()
            }
    }
}
