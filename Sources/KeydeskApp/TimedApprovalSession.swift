import Foundation

/// Memory-only consent. The monotonic deadline prevents a clock adjustment from extending it.
struct TimedApprovalSession: Sendable {
    let id = UUID()
    let expiresAt: Date
    let deadline: ContinuousClock.Instant

    init(minutes: Int, now: Date = Date(), instant: ContinuousClock.Instant = ContinuousClock().now) {
        expiresAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        deadline = instant.advanced(by: .seconds(minutes * 60))
    }

    func isActive(now: Date = Date(), instant: ContinuousClock.Instant = ContinuousClock().now) -> Bool {
        now < expiresAt && instant < deadline
    }
}
