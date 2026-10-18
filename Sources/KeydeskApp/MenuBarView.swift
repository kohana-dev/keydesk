import SwiftUI
import KeydeskCore
import AppKit

struct MenuBarView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @Binding var timedApprovalMenuFailure: String?
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let _ = interfaceLanguage
        Text("Cellar · \(model.snapshot == nil ? L10n.tr("잠김", "Locked") : L10n.tr("열림", "Unlocked"))")
        Text(model.menuBarBackupStatus)
        if let expiresAt = model.timedApprovalExpiresAt, model.timedApprovalIsActive {
            Text(L10n.tr("모든 요청 자동 허용 중", "All requests allowed automatically"))
                .foregroundStyle(.orange)
                .accessibilityIdentifier("timed-approval-menu-status")
            Text(L10n.tr("종료: \(expiresAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))", "Ends: \(expiresAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))"))
            Button(L10n.tr("자동 허용 지금 중지", "Stop automatic approval now"), systemImage: "stop.circle") {
                model.stopTimedApproval()
            }
            .accessibilityIdentifier("timed-approval-stop")
        }
        Menu(L10n.tr("일정 시간 모든 요청 허용", "Allow all requests temporarily"), systemImage: "clock.badge.checkmark") {
            Text(L10n.tr("모든 프로젝트 · 운영 환경 포함", "All projects · Including Production"))
            if model.timedApprovalStarting {
                Text(L10n.tr("Mac 인증 중…", "Authenticating with your Mac…"))
            } else if model.timedApprovalIsActive {
                Text(L10n.tr("시간을 선택하면 인증 후 다시 시작합니다", "Choose a duration to authenticate and restart"))
            }
            Button(L10n.tr("15분 허용", "Allow for 15 minutes")) { startTimedApprovalFromMenu(minutes: 15) }
                .accessibilityIdentifier("timed-approval-menu-start-15")
            Button(L10n.tr("30분 허용", "Allow for 30 minutes")) { startTimedApprovalFromMenu(minutes: 30) }
                .accessibilityIdentifier("timed-approval-menu-start-30")
            Button(L10n.tr("1시간 허용", "Allow for 1 hour")) { startTimedApprovalFromMenu(minutes: 60) }
                .accessibilityIdentifier("timed-approval-menu-start-60")
            Button(L10n.tr("2시간 허용", "Allow for 2 hours")) { startTimedApprovalFromMenu(minutes: 120) }
                .accessibilityIdentifier("timed-approval-menu-start-120")
            Divider()
            Button(L10n.tr("시간 직접 입력…", "Custom duration…")) {
                timedApprovalMenuFailure = nil
                showTimedApproval()
            }
            .accessibilityIdentifier("timed-approval-menu-custom")
        }
        .disabled(model.snapshot == nil || model.busy || model.timedApprovalStarting)
        .accessibilityIdentifier("timed-approval-menu-controls")
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

    private func showTimedApproval() {
        openWindow(id: "timed-approval")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startTimedApprovalFromMenu(minutes: Int) {
        timedApprovalMenuFailure = nil
        model.error = nil
        NSApp.activate(ignoringOtherApps: true)
        Task {
            await model.startTimedApproval(minutes: minutes)
            if let failure = model.error {
                // Keep a menu-triggered failure visible even when the main window is closed.
                model.error = nil
                timedApprovalMenuFailure = failure
                showTimedApproval()
            }
        }
    }
}
