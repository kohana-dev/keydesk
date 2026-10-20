import SwiftUI
import KeydeskCore

struct SidebarToolsMenu: View {
    let backupStatus: String
    let openSettings: () -> Void
    let openAIConnections: () -> Void
    let openActivity: () -> Void
    let exportBackup: () -> Void
    let verifyRecovery: () -> Void

    var body: some View {
        Menu {
            Button(backupStatus, action: openSettings)
            Divider()
            Button(L10n.tr("AI 연결…", "AI connections…"), systemImage: "terminal", action: openAIConnections)
            Button(L10n.tr("활동 기록…", "Activity…"), systemImage: "clock.arrow.circlepath", action: openActivity)
            Divider()
            Button(L10n.tr("암호화 백업 내보내기…", "Export encrypted backup…"), systemImage: "externaldrive.badge.timemachine", action: exportBackup)
            Button(L10n.tr("복구 검증…", "Verify recovery…"), systemImage: "arrow.counterclockwise", action: verifyRecovery)
            Divider()
            Button(L10n.tr("설정…", "Settings…"), systemImage: "gearshape", action: openSettings)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .frame(width: 18)
                Text(L10n.tr("관리", "Manage"))
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(L10n.tr("관리", "Manage"))
        .accessibilityIdentifier("sidebar-tools-menu")
        .help(L10n.tr("관리 도구와 설정 열기", "Open management tools and settings"))
    }
}
