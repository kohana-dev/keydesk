import SwiftUI
import KeydeskCore

struct SecretItemIcon: View {
    let credential: Credential
    var size: CGFloat = 42

    var body: some View {
        Group {
            if credential.currentFormat == .apiKey, !credential.provider.isEmpty, credential.provider != "Other" {
                ProviderLogo(provider: credential.provider, size: size * 0.57)
            } else {
                Image(systemName: credential.currentFormat.symbol)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: size * 0.26))
        .overlay(RoundedRectangle(cornerRadius: size * 0.26).stroke(Theme.border.opacity(0.7)))
        .accessibilityHidden(true)
    }
}
