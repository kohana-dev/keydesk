import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: VaultModel?
    var reopenMainWindow: (() -> Void)?
    private var eventMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.regular)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.model?.activity() }; return event
        }
    }
    func applicationDidResignActive(_ notification: Notification) { model?.hideValue() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let reopenMainWindow else { return true }
        // The SwiftUI Window scene owns creation and restoration. Reuse it for closed,
        // minimized and already visible windows instead of retaining a closed NSWindow.
        reopenMainWindow()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        model?.shutdown()
    }
}
