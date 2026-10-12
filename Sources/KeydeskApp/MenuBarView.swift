import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var model: VaultModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Cellar · \(model.snapshot == nil ? "잠김" : "열림")")
        Text(model.menuBarBackupStatus)
        Divider()
        Button("Cellar 열기", systemImage: "macwindow") { showMain() }
        if model.snapshot == nil {
            Button("금고 열기…", systemImage: "touchid") {
                showMain()
                Task { await model.unlock() }
            }.disabled(model.busy || !model.exists && !model.isDemo)
        } else {
            Button("금고 잠금", systemImage: "lock") { model.lock() }
        }
        Button(model.snapshot == nil ? "새 키 맡기기…" : "새 키 등록…", systemImage: "plus") {
            showMain()
            // Preserve any form already being edited instead of stacking sheets.
            if !NSApp.windows.contains(where: { $0.attachedSheet != nil }) { model.showQuickAdd = true }
        }.disabled(model.busy)
        Button("대기 중인 승인 보기", systemImage: "checkmark.circle") {
            model.showPendingApproval()
        }.disabled(!model.hasPendingApproval)
        Divider()
        Button("Cellar 종료") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
    private func showMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
