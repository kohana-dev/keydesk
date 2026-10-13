import SwiftUI
import AppKit

@main
struct KeydeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: VaultModel
    init() {
        let args = CommandLine.arguments
        if args.contains("--keychain-self-test") {
            print(DeviceKeyStore.probe())
            Darwin.exit(0)
        }
        let demo = args.contains("--demo")
        let socket = args.firstIndex(of: "--demo-socket").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        _model = State(initialValue: VaultModel(demo: demo, demoSocket: demo ? socket : nil))
    }
    var body: some Scene {
        Window("Cellar", id: "main") {
            MainWindowView(model: model, delegate: delegate)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("금고") {
                Button("대기 중인 실행 승인 보기") { model.showPendingApproval() }
                    .disabled(model.approval == nil && model.brokerApproval == nil && model.apiApproval == nil)
                Button("금고 잠금", systemImage: "lock") { model.lock() }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image).renderingMode(.template)
                .accessibilityLabel("Cellar")
        }.menuBarExtraStyle(.menu)
    }
}
