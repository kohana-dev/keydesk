import AppKit
import SwiftUI
import KeydeskCore

/// Reads only the keyboard's Caps Lock state while this status is visible.
struct CapsLockIndicator: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @State private var enabled = NSEvent.modifierFlags.contains(.capsLock)

    var body: some View {
        let _ = interfaceLanguage
        let status = enabled
            ? L10n.tr("Caps Lock 켜짐", "Caps Lock is on")
            : L10n.tr("Caps Lock 꺼짐", "Caps Lock is off")

        Label(status, systemImage: enabled ? "capslock.fill" : "capslock")
            .font(.caption)
            .foregroundStyle(enabled ? Color.orange : Color.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status)
            .accessibilityIdentifier("caps-lock-indicator")
            .allowsHitTesting(false)
            .task {
                while !Task.isCancelled {
                    let current = NSEvent.modifierFlags.contains(.capsLock)
                    if enabled != current { enabled = current }
                    do {
                        try await Task.sleep(for: .milliseconds(250))
                    } catch {
                        break
                    }
                }
            }
    }
}
