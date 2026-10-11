import AppKit

@MainActor
final class ClipboardService {
    private let board: NSPasteboard
    init(board: NSPasteboard = .general) { self.board = board }
    private var timer: Timer?
    private var ownedCount: Int?
    func copy(_ value: String, secret: Bool) {
        timer?.invalidate()
        board.clearContents()
        if secret {
            let item = NSPasteboardItem()
            item.setString(value, forType: .string)
            item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            board.writeObjects([item])
            ownedCount = board.changeCount
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.clearOwned() }
            }
        } else { board.setString(value, forType: .string); ownedCount = nil }
    }
    func clearOwned() {
        timer?.invalidate(); timer = nil
        if board.changeCount == ownedCount { board.clearContents() }
        ownedCount = nil
    }
}
