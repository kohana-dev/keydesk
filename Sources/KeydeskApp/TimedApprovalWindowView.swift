import SwiftUI
import KeydeskCore

/// A compact control window opened by the menu bar without showing the full settings.
struct TimedApprovalWindowView: View {
    @Bindable var model: VaultModel
    @Binding var menuFailure: String?
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let _ = interfaceLanguage
        VStack(alignment: .leading, spacing: 14) {
            if let menuFailure {
                Label(menuFailure, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("timed-approval-menu-error")
            }
            TimedApprovalSection(model: model, initiallyCustom: true)
            HStack {
                Spacer()
                Button(L10n.tr("닫기", "Close")) { dismissWindow(id: "timed-approval") }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 510)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, L10n.locale)
        .onChange(of: model.timedApprovalStarting) { _, starting in
            if starting { menuFailure = nil }
        }
    }
}
