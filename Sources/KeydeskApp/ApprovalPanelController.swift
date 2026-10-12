import AppKit
import SwiftUI

/// Owns approval windows independently of the main SwiftUI window's appearance lifecycle.
/// Requests activation and provides a floating panel that can also be reopened from the vault menu.
@MainActor
final class ApprovalPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private weak var model: VaultModel?
    private var closingFromModel = false

    func attach(_ model: VaultModel) {
        self.model = model
        model.onApprovalChange = { [weak self] in self?.update() }
        update()
    }

    func update() {
        guard let model else { return }
        if let approval = model.approval {
            guard !model.reusingDevelopmentApproval else { return }
            show(CLIApprovalView(model: model, approval: approval), title: "Cellar · 실행 승인")
        } else if let approval = model.apiApproval {
            show(APIApprovalView(model: model, approval: approval), title: "Cellar · API 사용 승인")
        } else if let approval = model.brokerApproval {
            show(BrokerApprovalView(model: model, approval: approval), title: "Cellar · AI 연결 승인")
        } else {
            closingFromModel = true
            panel?.close(); panel = nil
            closingFromModel = false
        }
    }

    private func show(_ view: some View, title: String) {
        let hosting = NSHostingView(rootView: view.tint(Theme.accent).preferredColorScheme(.light))
        let panel = self.panel ?? {
            let created = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            created.level = .floating
            created.hidesOnDeactivate = false
            created.isReleasedWhenClosed = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.delegate = self
            return created
        }()
        panel.title = title
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        // Open on the display the user is working on (where the pointer is), not the main window's display.
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            let area = screen.visibleFrame, size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
        } else { panel.center() }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        self.panel = panel
        NSApp.requestUserAttention(.criticalRequest)
    }

    /// Closing the panel with its close button counts as rejecting the request.
    func windowWillClose(_ notification: Notification) {
        guard !closingFromModel, let model else { return }
        panel = nil
        if model.approval != nil { model.rejectCLI() }
        if model.apiApproval != nil { model.rejectAPI() }
        if model.brokerApproval != nil { model.rejectBroker() }
    }
}
