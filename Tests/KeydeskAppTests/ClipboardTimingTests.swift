import Testing
import AppKit
@testable import KeydeskApp

@MainActor struct ClipboardTimingTests {
    @Test func actualThirtySecondTimerClearsOnlyOwnedCopy() async throws {
        let board = NSPasteboard(name: .init("Keydesk-timer-QA-\(UUID())"))
        let service = ClipboardService(board: board)
        defer { board.clearContents() }
        service.copy("DISPOSABLE_TIMER_SENTINEL", secret: true)
        try await Task.sleep(for: .seconds(31))
        #expect(board.string(forType: .string) == nil)
    }
}
