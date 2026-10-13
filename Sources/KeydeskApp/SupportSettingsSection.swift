import SwiftUI
import KeydeskCore

/// Support remains available without unlocking or passing any vault model.
struct SupportSettingsSection: View {
    @State private var showingBugReport = false
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue

    var body: some View {
        let _ = interfaceLanguage
        VStack(alignment: .leading, spacing: 18) {
            UpdateCheckView()
            GroupBox(L10n.tr("도움말과 버그 제보", "Help and bug reports")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("작성한 내용을 검토한 뒤 GitHub에서 제보할 수 있습니다. 금고·키·로그·스크린샷은 자동 첨부하지 않습니다.", "Review your report before opening it on GitHub. Vaults, keys, logs, and screenshots are never attached automatically."))
                        .font(.callout).foregroundStyle(.secondary)
                    Button(L10n.tr("버그 제보 작성…", "Write a bug report…"), systemImage: "bubble.left.and.text.bubble.right") {
                        showingBugReport = true
                    }
                    Link(L10n.tr("설치·사용 안내", "Installation and usage guide"), destination: URL(string: "https://github.com/kohana-dev/keydesk/blob/main/docs/installation.md")!)
                    Link(L10n.tr("보안 취약점 비공개 제보", "Report a vulnerability privately"), destination: URL(string: "https://github.com/kohana-dev/keydesk/security/advisories/new")!)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .sheet(isPresented: $showingBugReport) { BugReportView() }
    }
}
