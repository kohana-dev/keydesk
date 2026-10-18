import AppKit

@MainActor
enum DialogSizing {
    /// Leave space for the title bar, menu bar and screen edges on smaller displays.
    static func height(preferred: CGFloat, on targetScreen: NSScreen? = nil) -> CGFloat {
        let screen = targetScreen ?? NSApp.keyWindow?.screen ?? NSScreen.main
        return min(preferred, max(300, (screen?.visibleFrame.height ?? 840) - 120))
    }
}
