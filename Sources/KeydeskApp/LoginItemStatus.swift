import Foundation

enum LoginItemStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unavailable

    /// A pending registration can also be removed with the settings toggle.
    var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}
