import SwiftUI
import KeydeskCore

/// Builds a report locally; the only submission action opens GitHub's draft editor.
struct BugReportView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var draft = BugReportDraft()
    @State private var preview: BugReportPreview?
    @State private var confirmsNoSensitiveInformation = false
    @State private var error: String?
    @State private var openedDraft = false

    private let metadata = BugReportMetadata.currentApp

    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.tr("버그 제보", "Report a bug")).font(.title2.bold())
                    Text(L10n.tr("내용을 작성하고 검토한 뒤 GitHub 초안을 엽니다. GitHub에서 로그인하고 직접 제출하면 제보가 공개됩니다.", "Write and review your report, then open a GitHub draft. Sign in and submit it yourself on GitHub to make the report public."))
                        .font(.callout).foregroundStyle(.secondary)

                    if let preview {
                        review(preview)
                    } else {
                        compose
                    }

                }
                .padding(24)
            }
            .id(preview == nil)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
            if openedDraft {
                Text(L10n.tr("브라우저에 초안을 열었습니다. 제출 여부는 GitHub에서 결정하세요.", "The draft is open in your browser. Decide whether to submit it on GitHub."))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }

            DialogFooter {
                DialogDismissButton { dismiss() }
                if preview != nil {
                    Button(L10n.tr("내용 수정", "Edit report")) {
                        preview = nil
                        confirmsNoSensitiveInformation = false
                        openedDraft = false
                        error = nil
                    }
                    .controlSize(.large)
                }
                Spacer()
                if let preview {
                    Button(L10n.tr("GitHub 초안 열기", "Open GitHub draft"), systemImage: "arrow.up.right") {
                        guard confirmsNoSensitiveInformation else { return }
                        error = nil
                        openURL(preview.destination) { @Sendable accepted in
                            Task { @MainActor in
                                openedDraft = accepted
                                if !accepted {
                                    error = L10n.tr("브라우저를 열지 못했습니다. 다시 시도하세요.", "Could not open the browser. Try again.")
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!confirmsNoSensitiveInformation)
                } else {
                    Button(L10n.tr("보낼 내용 검토", "Review report")) { preparePreview() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
        .frame(width: 660, height: DialogSizing.height(preferred: 680))
        .environment(\.locale, L10n.locale)
        .onDisappear {
            draft = BugReportDraft()
            preview = nil
            confirmsNoSensitiveInformation = false
        }
    }

    private var compose: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("API 키, 비밀번호, 복구 키, 개인 정보는 적지 마세요. 금고, 로그, 파일, 스크린샷은 수집하지 않습니다.", "Do not include API keys, passwords, recovery keys, or personal information. Vaults, logs, files, and screenshots are not collected."))
                .font(.callout).foregroundStyle(.secondary)
            Link(L10n.tr("개인정보 처리방침", "Privacy policy"), destination: privacyURL)
                .font(.callout)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("제목", "Title")).font(.headline)
                TextField(L10n.tr("문제를 한 문장으로 설명하세요", "Describe the problem in one sentence"), text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.tr("버그 제보 제목", "Bug report title"))
                    .onChange(of: draft.title) { _, value in
                        draft.title = String(value.prefix(BugReportDraft.maximumTitleLength))
                    }
                counter(draft.title, limit: BugReportDraft.maximumTitleLength)
            }
            textArea(L10n.tr("재현 방법", "Steps to reproduce"), text: $draft.stepsToReproduce, limit: BugReportDraft.maximumStepsLength)
            textArea(L10n.tr("예상 결과", "Expected result"), text: $draft.expectedResult, limit: BugReportDraft.maximumResultLength)
            textArea(L10n.tr("실제 결과", "Actual result"), text: $draft.actualResult, limit: BugReportDraft.maximumResultLength)
            Toggle(L10n.tr("아래 앱·시스템 정보 포함 (선택)", "Include the app and system information below (optional)"), isOn: $draft.includesMetadata)
            Text("Cellar \(metadata.appVersion) (\(L10n.tr("빌드", "build")) \(metadata.appBuild)) · macOS \(metadata.operatingSystemVersion) · \(metadata.architecture)")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            securityNotice
        }
        .privacySensitive()
    }

    private func review(_ preview: BugReportPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("GitHub으로 전달할 전체 내용", "Full content to pass to GitHub")).font(.headline)
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("제목", "Title")).font(.headline)
                Text(preview.title).textSelection(.enabled)
                Divider()
                Text(L10n.tr("본문", "Body")).font(.headline)
                Text(preview.body).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
            .privacySensitive()
            Text(L10n.tr("목적지: github.com/kohana-dev/keydesk/issues/new. 흔한 비밀정보 패턴만 검사하므로 자동 검사만으로 안전을 보장하지 않습니다.", "Destination: github.com/kohana-dev/keydesk/issues/new. The local check covers common secret patterns and cannot guarantee that the report is safe."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.tr("‘GitHub 초안 열기’를 누르면 위 내용이 브라우저 주소(URL)를 통해 즉시 GitHub에 전달됩니다. 공개 제보의 최종 제출은 그 다음에 GitHub에서 결정합니다.", "Clicking ‘Open GitHub draft’ immediately passes the reviewed content to GitHub through the browser URL. You decide whether to submit a public report afterward on GitHub."))
                .font(.callout).foregroundStyle(.secondary)
            Link(L10n.tr("개인정보 처리방침", "Privacy policy"), destination: privacyURL)
                .font(.callout)
            Toggle(L10n.tr("전체 내용을 읽었으며 비밀정보와 개인 정보가 없음을 확인했습니다.", "I have read the full report and confirmed that it contains no secrets or personal information."), isOn: $confirmsNoSensitiveInformation)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyURL: URL {
        URL(string: L10n.language == .korean
            ? "https://www.kohanacloud.com/cellar/privacy"
            : "https://www.kohanacloud.com/cellar/en/privacy")!
    }

    private var securityNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr("보안 취약점은 공개 버그 제보에 적지 말고 비공개 보안 제보를 사용하세요.", "Use a private security report for vulnerabilities instead of a public bug report."))
                .font(.caption).foregroundStyle(.secondary)
            Link(L10n.tr("비공개 보안 제보 열기", "Open private security report"), destination: BugReportDraft.privateSecurityDestination)
                .font(.caption)
        }
    }

    private func textArea(_ label: String, text: Binding<String>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.headline)
            TextEditor(text: text)
                .font(.body)
                .frame(height: 75)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
                .accessibilityLabel(label)
                .onChange(of: text.wrappedValue) { _, value in
                    text.wrappedValue = String(value.prefix(limit))
                }
            counter(text.wrappedValue, limit: limit)
        }
    }

    private func counter(_ text: String, limit: Int) -> some View {
        Text(L10n.tr("\(text.count) / \(limit)자", "\(text.count) / \(limit) characters"))
            .font(.caption).foregroundStyle(.secondary)
    }

    private func preparePreview() {
        do {
            preview = try draft.preview(metadata: metadata, language: L10n.language)
            confirmsNoSensitiveInformation = false
            openedDraft = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension BugReportMetadata {
    static var currentApp: Self {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unavailable"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        return Self(appVersion: version, appBuild: build,
                    operatingSystemVersion: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)", architecture: architecture)
    }
}
