import AppKit
import SwiftUI
import KeydeskCore

/// Configuration text must never be rewritten by macOS smart quotes, dashes or replacements.
struct SecretTextEditor: NSViewRepresentable {
    @Binding var text: String
    let format: SecretFormat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 190))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = ContentTextView(frame: scroll.bounds)
        editor.minSize = NSSize(width: 0, height: 190)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.smartInsertDeleteEnabled = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.textColor = .labelColor
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.setAccessibilityIdentifier("secret-content-input")
        scroll.documentView = editor
        update(editor)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        update(editor)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? ContentTextView else { return }
        editor.delegate = nil
        editor.contentUndoManager.removeAllActions()
        editor.allowsUndo = false
        editor.string = ""
        scroll.documentView = nil
    }

    @MainActor
    final class ContentTextView: NSTextView {
        let contentUndoManager = UndoManager()
        override var undoManager: UndoManager? { contentUndoManager }
    }

    private func update(_ editor: NSTextView) {
        editor.font = format == .json ? .monospacedSystemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 13)
        editor.setAccessibilityLabel(format == .json ? L10n.tr("JSON 내용", "JSON content") : L10n.tr("텍스트 내용", "Text content"))
        if editor.string != text {
            let range = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(range.location, (text as NSString).length), length: 0))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SecretTextEditor
        init(_ parent: SecretTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}
