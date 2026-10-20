import SwiftUI
import KeydeskCore

struct SecretFormatBadge: View {
    let format: SecretFormat

    var body: some View {
        Label(format.shortTitle, systemImage: format.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.selection, in: Capsule())
    }
}
