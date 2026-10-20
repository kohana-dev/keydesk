import SwiftUI
import KeydeskCore

struct SidebarBackupNotice: View {
    let model: VaultModel
    let openSettings: () -> Void

    var body: some View {
        if let notice = attention {
            Button(action: openSettings) {
                Label(notice.title, systemImage: notice.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(notice.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar-backup-attention")
            .help(L10n.tr("백업 설정 열기", "Open backup settings"))
        }
    }

    private var attention: (title: String, symbol: String, color: Color)? {
        guard !model.isDemo else { return nil }
        if !model.recoveryKeySaved {
            return (L10n.tr("복구 키 직접 보관 필요", "Save your recovery key"), "exclamationmark.triangle.fill", .red)
        }
        if model.backupDirectory == nil {
            return (L10n.tr("백업 폴더 없음", "No backup folder"), "exclamationmark.triangle.fill", .red)
        }
        if model.backupFailure != nil {
            return (L10n.tr("백업 실패", "Backup failed"), "exclamationmark.triangle.fill", .red)
        }
        if model.hasUnbackedChanges {
            return (L10n.tr("백업 대기 중", "Backup pending"), "arrow.triangle.2.circlepath", .orange)
        }
        guard model.backupDestination != .googleDrive else { return nil }
        if model.cloudUpload == .failed {
            return (L10n.tr("iCloud 업로드 안 됨", "iCloud upload failed"), "exclamationmark.icloud", .red)
        }
        if model.cloudUpload == .pending {
            return (L10n.tr("iCloud 업로드 대기 중", "iCloud upload pending"), "icloud.and.arrow.up", .orange)
        }
        return nil
    }
}
