import Testing
import AppKit
import KeydeskCore
@testable import KeydeskApp

@Suite(.serialized) @MainActor
struct ApprovalPanelTests {
    @Test func pendingRequestCreatesVisibleUsablePanel() throws {
        _ = NSApplication.shared
        let model = VaultModel(demo: true, serve: false, observeSystemEvents: false)
        let (channel, client) = try RunnerTests().sockets()
        defer { model.shutdown(); channel.finish(); close(client) }
        let controller = ApprovalPanelController()
        controller.attach(model)
        model.approval = try CLIApproval(request: CLIRequest(project: "Studio Notes", environment: .development, command: ["/usr/bin/true"], directory: "/tmp", stdinKey: nil, variables: ["OPENAI_API_KEY"]), channel: channel)
        let window = try #require(NSApp.windows.first { $0.title == L10n.tr("Cellar · 실행 승인", "Cellar · Execution approval") })
        #expect(window.isVisible)
        #expect(window.frame.width >= 600)
        #expect(window.frame.height >= 300)
        #expect(NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) })
        model.rejectCLI()
        #expect(!window.isVisible)
    }
    @Test func servingModelPresentsWithoutMainWindowAppearance() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keydesk-panel-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = VaultModel(demo: true, demoSocket: directory.appendingPathComponent("cli.sock").path)
        let (channel, client) = try RunnerTests().sockets()
        defer { model.shutdown(); channel.finish(); close(client); try? FileManager.default.removeItem(at: directory) }
        model.approval = try CLIApproval(request: CLIRequest(project: "Studio Notes", environment: .development, command: ["/usr/bin/true"], directory: "/tmp", stdinKey: nil, variables: ["OPENAI_API_KEY"]), channel: channel)
        let window = try #require(NSApp.windows.first { $0.title == L10n.tr("Cellar · 실행 승인", "Cellar · Execution approval") && $0.isVisible })
        #expect(window.frame.width >= 600 && window.frame.height >= 300)
        model.rejectCLI()
        #expect(!window.isVisible)
    }

    @Test func defaultIdleWindowIsThirtyMinutesAndCanFollowScreenLock() {
        let model = VaultModel(demo: true, serve: false, observeSystemEvents: false)
        defer { model.shutdown() }
        #expect(model.autoLockMinutes == 30)
        model.lockIfIdle(now: Date().addingTimeInterval(301))
        #expect(model.snapshot != nil)
        model.lockIfIdle(now: Date().addingTimeInterval(1801))
        #expect(model.snapshot == nil)
        let screenOnly = VaultModel(demo: true, serve: false, observeSystemEvents: false)
        defer { screenOnly.shutdown() }
        screenOnly.autoLockMinutes = 0
        screenOnly.lockIfIdle(now: Date().addingTimeInterval(86400))
        #expect(screenOnly.snapshot != nil)
        screenOnly.lock()
        #expect(screenOnly.snapshot == nil)
    }

    @Test func rememberedRunReusesApprovalAndVaultChangesRevokeIt() async throws {
        let model = VaultModel(demo: true, serve: false, observeSystemEvents: false)
        defer { model.shutdown() }
        let invocation = CLIRequest(project: "Studio Notes", environment: .development, command: ["/usr/bin/true"], directory: "/tmp", stdinKey: nil, variables: ["OPENAI_API_KEY"])
        let (first, firstClient) = try RunnerTests().sockets()
        defer { first.finish(); close(firstClient) }
        model.receive(try CLIApproval(request: invocation, channel: first))
        #expect(model.approval != nil)
        await model.acceptCLI(remember: true)
        #expect(model.approval == nil)
        let (second, secondClient) = try RunnerTests().sockets()
        defer { second.finish(); close(secondClient) }
        model.receive(try CLIApproval(request: invocation, channel: second))
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.approval == nil)
        var events: [String] = []
        while let line = try SocketTransport.readLine(from: secondClient) {
            let event = try JSONDecoder().decode(CLIEvent.self, from: line)
            events.append(event.kind)
            if event.kind == "exit" { #expect(event.exitCode == 0); break }
        }
        #expect(events.contains("started") && events.contains("exit"))
        try model.addProject("changed vault")
        let (third, thirdClient) = try RunnerTests().sockets()
        defer { third.finish(); close(thirdClient) }
        model.receive(try CLIApproval(request: invocation, channel: third))
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.approval != nil)
        await model.acceptCLI(remember: true)
        model.lock()
        await model.unlock()
        let (fourth, fourthClient) = try RunnerTests().sockets()
        defer { fourth.finish(); close(fourthClient) }
        model.receive(try CLIApproval(request: invocation, channel: fourth))
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.approval != nil)
        model.rejectCLI()
    }

}
