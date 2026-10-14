import Foundation
import ServiceManagement

@MainActor
struct SystemLoginItemService: LoginItemService {
    private let available: Bool

    init(bundle: Bundle = .main, arguments: [String] = CommandLine.arguments) {
        available = Self.canManageLoginItem(bundleIdentifier: bundle.bundleIdentifier,
                                            bundleURL: bundle.bundleURL, arguments: arguments)
    }

    /// Test executables and separate QA/demo bundles must never alter login items.
    static func canManageLoginItem(bundleIdentifier: String?, bundleURL: URL, arguments: [String]) -> Bool {
        bundleIdentifier == "com.keydesk.local"
            && bundleURL.pathExtension == "app"
            && !arguments.contains("--demo")
            && !arguments.contains("--keychain-self-test")
    }

    var status: LoginItemStatus {
        guard available else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    func register() throws {
        guard available else { return }
        try SMAppService.mainApp.register()
    }

    func unregister() async throws {
        guard available else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            SMAppService.mainApp.unregister { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func openSystemSettings() {
        guard available else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
