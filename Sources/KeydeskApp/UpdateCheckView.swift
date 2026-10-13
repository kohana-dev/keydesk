import SwiftUI
import KeydeskCore

struct UpdateCheckView: View {
    @State private var model: UpdateCheckModel
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue

    init(model: UpdateCheckModel = UpdateCheckModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        let _ = interfaceLanguage
        GroupBox(L10n.tr("앱 업데이트", "App updates")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.installationLabel)
                    .font(.callout)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Button(L10n.tr("업데이트 확인", "Check for updates"), systemImage: "arrow.triangle.2.circlepath") {
                        Task { await model.check() }
                    }
                    .disabled(model.state == .checking)
                    .accessibilityIdentifier("check-for-updates")
                    if model.state == .checking {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel(L10n.tr("업데이트 확인 중", "Checking for updates"))
                    }
                }
                status
                Text(L10n.tr("버튼을 누를 때만 GitHub의 공개 릴리스를 확인합니다. GitHub에 IP 등 접속 정보가 전달되며, 금고 내용은 전송하지 않습니다. 설치는 다운로드 후 직접 진행합니다.", "The button checks GitHub's public release only when clicked. GitHub receives connection information such as your IP address; no vault contents are sent. Download and install updates yourself."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .checking:
            Text(L10n.tr("공개 릴리스 확인 중…", "Checking the public release…"))
                .font(.callout).foregroundStyle(.secondary)
        case .current(let version):
            Label(L10n.tr("최신 공개 버전 \(version.rawValue)을 사용 중이거나 더 새 버전입니다.", "You are running the latest public version \(version.rawValue) or a newer version."), systemImage: "checkmark.circle")
                .font(.callout)
        case .available(let release):
            Text(L10n.tr("새 버전 \(release.version.rawValue)을 사용할 수 있습니다.", "Version \(release.version.rawValue) is available."))
                .font(.callout)
            releaseLink(release)
        case .development(let release):
            Text(L10n.tr("최신 공개 버전은 \(release.version.rawValue)입니다. 개발 빌드는 설치된 버전과 비교할 수 없습니다.", "The latest public version is \(release.version.rawValue). This development build has no installed version to compare."))
                .font(.callout)
            releaseLink(release)
        case .failed(let failure):
            Label(failure.message, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func releaseLink(_ release: AppRelease) -> some View {
        Link(destination: release.pageURL) {
            Label(L10n.tr("공식 릴리스에서 다운로드", "Download from the official release"), systemImage: "arrow.up.right.square")
        }
        .accessibilityIdentifier("official-update-release")
    }
}
