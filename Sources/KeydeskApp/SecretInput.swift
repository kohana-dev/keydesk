import SwiftUI
import AppKit

/// Reveals only the value being entered, never retrieves a saved credential.
struct SecretInput: View {
    let title: String
    @Binding var value: String
    @State private var shown = false
    @FocusState private var fieldFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        HStack {
            Group {
                if shown { TextField(title, text: $value).focused($fieldFocused) }
                else { SecureField(title, text: $value).focused($fieldFocused) }
            }.textFieldStyle(.roundedBorder).privacySensitive()
            Button(shown ? "숨기기" : "보기", systemImage: shown ? "eye.slash" : "eye") {
                fieldFocused = false
                shown.toggle()
            }
                .help(shown ? "입력한 비밀값 숨기기" : "입력한 비밀값 보기")
                .accessibilityLabel(shown ? "입력한 비밀값 숨기기" : "입력한 비밀값 보기")
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
