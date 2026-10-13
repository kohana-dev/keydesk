import SwiftUI
import KeydeskCore
import AppKit

/// Reveals only the value being entered, never retrieves a saved credential.
struct SecretInput: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    let title: String
    @Binding var value: String
    @State private var shown = false
    @FocusState private var fieldFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        let _ = interfaceLanguage
        HStack {
            Group {
                if shown { TextField(title, text: $value).focused($fieldFocused) }
                else { SecureField(title, text: $value).focused($fieldFocused) }
            }.textFieldStyle(.roundedBorder).privacySensitive()
            Button(shown ? L10n.tr("숨기기", "Hide") : L10n.tr("보기", "Show"), systemImage: shown ? "eye.slash" : "eye") {
                fieldFocused = false
                shown.toggle()
            }
                .help(shown ? L10n.tr("입력한 비밀값 숨기기", "Hide entered secret") : L10n.tr("입력한 비밀값 보기", "Show entered secret"))
                .accessibilityLabel(shown ? L10n.tr("입력한 비밀값 숨기기", "Hide entered secret") : L10n.tr("입력한 비밀값 보기", "Show entered secret"))
        }
        .onChange(of: shown) {
            Task { @MainActor in
                await Task.yield()
                fieldFocused = true
            }
        }
        .onChange(of: scenePhase) { if scenePhase != .active { shown = false } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in shown = false }
        .onDisappear { shown = false }
    }
}
