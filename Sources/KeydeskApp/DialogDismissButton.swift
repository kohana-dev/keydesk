import SwiftUI
import KeydeskCore

/// A clear, consistently sized way to leave a dialog, with Escape preserved.
struct DialogDismissButton: View {
    private let title: String
    private let prominent: Bool
    private let action: () -> Void

    init(_ title: String = L10n.tr("닫기", "Close"), prominent: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "xmark")
                .font(.body.weight(.semibold))
                .frame(minWidth: 96, minHeight: 44)
        }
        .buttonStyle(DialogDismissButtonStyle(prominent: prominent))
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("dialog-dismiss")
    }
}

private struct DialogDismissButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .foregroundStyle(prominent ? Color.white : Theme.ink)
            .background(prominent ? Theme.accent : Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(prominent ? Color.clear : Theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}
