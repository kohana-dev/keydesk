import SwiftUI
import KeydeskCore
import AppKit

struct MenuBarView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let _ = interfaceLanguage
        Text("Cellar · \(model.snapshot == nil ? L10n.tr("잠김", "Locked") : L10n.tr("열림", "Unlocked"))")
        Text(model.menuBarBackupStatus)
        Divider()
        Button(L10n.tr("Cellar 열기", "Open Cellar"), systemImage: "macwindow") { showMain() }
        if model.snapshot == nil {
            Button(L10n.tr("금고 열기…", "Unlock vault…"), systemImage: "touchid") {
                showMain()
                Task { await model.unlock() }
            }.disabled(model.busy || !model.exists && !model.isDemo)
        } else {
            Button(L10n.tr("금고 잠금", "Lock vault"), systemImage: "lock") { model.lock() }
        }
        Button(model.snapshot == nil ? L10n.tr("새 키 맡기기…", "Deposit a new key…") : L10n.tr("새 키 등록…", "Add a new key…"), systemImage: "plus") {
            showMain()
            // Preserve any form already being edited instead of stacking sheets.
            if !NSApp.windows.contains(where: { $0.attachedSheet != nil }) { model.showQuickAdd = true }
        }.disabled(model.busy)
        Button(L10n.tr("대기 중인 승인 보기", "Show pending approval"), systemImage: "checkmark.circle") {
            model.showPendingApproval()
        }.disabled(!model.hasPendingApproval)
        Divider()
        Button(L10n.tr("Cellar 종료", "Quit Cellar")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
    private func showMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
