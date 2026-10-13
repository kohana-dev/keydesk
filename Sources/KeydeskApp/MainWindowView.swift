import SwiftUI
import AppKit

struct MainWindowView: View {
    let model: VaultModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 1000, minHeight: 680)
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
