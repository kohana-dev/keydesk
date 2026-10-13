import SwiftUI
import AppKit
import KeydeskCore

@main
struct KeydeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: VaultModel
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
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
        let _ = interfaceLanguage
        Window("Cellar", id: "main") {
            MainWindowView(model: model, delegate: delegate)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                SettingsLink { Text(L10n.tr("업데이트와 버그 제보…", "Updates and bug reports…")) }
            }
            CommandMenu(L10n.tr("금고", "Vault")) {
                Button(L10n.tr("대기 중인 실행 승인 보기", "Show pending approval")) { model.showPendingApproval() }
                    .disabled(model.approval == nil && model.brokerApproval == nil && model.apiApproval == nil)
                Button(L10n.tr("금고 잠금", "Lock vault"), systemImage: "lock") { model.lock() }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image).renderingMode(.template)
                .accessibilityLabel("Cellar")
        }.menuBarExtraStyle(.menu)
        Settings { LanguagePreferencesView() }
    }
}
