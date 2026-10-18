import SwiftUI
import KeydeskCore

/// Keep the upper-right close control outside the scrollable dialog body.
struct DialogCloseBar: View {
    private let title: String
    private let action: () -> Void

    init(_ title: String = L10n.tr("닫기", "Close"), action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: action) {
                    Label(title, systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(Theme.canvas, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(title)
                .accessibilityLabel(title)
                .accessibilityIdentifier("dialog-top-close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.surface)
            Divider()
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dialog-header")
    }
}
