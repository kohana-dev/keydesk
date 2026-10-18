import SwiftUI
import KeydeskCore

/// A session-only permission window, shared by both settings entry points and approval status.
struct TimedApprovalSection: View {
    @Bindable var model: VaultModel
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @State private var selectedMinutes = 15
    @State private var customMinutes = 15
    @State private var startFailure: String?

    init(model: VaultModel, initiallyCustom: Bool = false) {
        self.model = model
        _selectedMinutes = State(initialValue: initiallyCustom ? 0 : 15)
    }

    private var duration: Int { selectedMinutes == 0 ? customMinutes : selectedMinutes }

    var body: some View {
        let _ = interfaceLanguage
        GroupBox(L10n.tr("일정 시간 모든 요청 허용", "Allow all requests temporarily")) {
            VStack(alignment: .leading, spacing: 12) {
                if let expiresAt = model.timedApprovalExpiresAt, model.timedApprovalIsActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(L10n.tr("모든 요청 자동 허용 중", "All requests are being allowed automatically"), systemImage: "clock.badge.checkmark")
                                .font(.callout.bold())
                                .foregroundStyle(.orange)
                            Text(remaining(until: expiresAt, now: context.date))
                                .font(.callout.monospacedDigit())
                            Text(L10n.tr("종료: \(deadline(expiresAt))", "Ends: \(deadline(expiresAt))"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("timed-approval-status")
                    }
                    Button(L10n.tr("지금 중지", "Stop now"), systemImage: "stop.circle") {
                        model.stopTimedApproval()
                    }
                    .accessibilityIdentifier("timed-approval-stop")
                } else {
                    Label(L10n.tr("자동 허용 꺼짐", "Automatic approval is off"), systemImage: "clock")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("timed-approval-status")
                    Picker(L10n.tr("허용 시간", "Duration"), selection: $selectedMinutes) {
                        Text(L10n.tr("15분", "15 minutes")).tag(15)
                        Text(L10n.tr("30분", "30 minutes")).tag(30)
                        Text(L10n.tr("1시간", "1 hour")).tag(60)
                        Text(L10n.tr("2시간", "2 hours")).tag(120)
                        Text(L10n.tr("직접 입력", "Custom")).tag(0)
                    }
                    .disabled(model.snapshot == nil || model.timedApprovalStarting || model.busy)
                    .accessibilityIdentifier("timed-approval-duration")

                    if selectedMinutes == 0 {
                        Stepper(value: $customMinutes, in: 1...480) {
                            HStack {
                                Text(L10n.tr("분 (1–480)", "Minutes (1–480)"))
                                TextField(L10n.tr("허용 시간(분)", "Duration in minutes"), value: $customMinutes, format: .number.grouping(.never))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                    .accessibilityIdentifier("timed-approval-duration-custom")
                            }
                        }
                        .disabled(model.snapshot == nil || model.timedApprovalStarting || model.busy)
                    }

                    HStack(spacing: 8) {
                        Button(L10n.tr("모든 요청 허용 시작", "Start allowing all requests"), systemImage: "clock.badge.checkmark") {
                            startFailure = nil
                            let requestedMinutes = duration
                            Task {
                                await model.startTimedApproval(minutes: requestedMinutes)
                                if !model.timedApprovalIsActive { startFailure = model.error }
                            }
                        }
                        .disabled(model.snapshot == nil || model.timedApprovalStarting || model.busy || !(1...480).contains(duration))
                        .accessibilityIdentifier("timed-approval-start")
                        if model.timedApprovalStarting {
                            ProgressView().controlSize(.small)
                                .accessibilityLabel(L10n.tr("Mac 인증 중", "Authenticating with your Mac"))
                        }
                    }
                    if model.snapshot == nil {
                        Text(L10n.tr("금고를 연 다음 시작할 수 있습니다.", "Unlock the vault before starting."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let startFailure {
                        Text(startFailure)
                            .font(.caption).foregroundStyle(.red)
                            .accessibilityIdentifier("timed-approval-error")
                    }
                }

                Text(L10n.tr("선택한 시간 동안 모든 프로젝트의 개발·스테이징·운영 환경에서 CLI·API·MCP 요청을 추가 승인 없이 허용합니다. 시작할 때 Mac 인증을 한 번 진행합니다.", "During this period, CLI, API, and MCP requests for all projects and development, staging, and production environments are allowed without further approval. Starting requires one Mac authentication."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.tr("시간이 만료되거나 금고를 잠그거나 앱을 종료하면 끝납니다. 중지해도 이미 시작한 작업은 계속됩니다.", "Ends when the time expires, the vault locks, or the app quits. Work already started continues after you stop."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private func remaining(until expiresAt: Date, now: Date) -> String {
        let seconds = max(0, Int(ceil(expiresAt.timeIntervalSince(now))))
        return L10n.tr("\(seconds / 60)분 \(seconds % 60)초 남음", "\(seconds / 60)m \(seconds % 60)s remaining")
    }

    private func deadline(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(L10n.locale))
    }
}
