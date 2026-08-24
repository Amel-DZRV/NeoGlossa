import Foundation

/// Decides how many new cards to introduce today.
///
/// There is no new-cards-per-day setting. There is one number — target daily
/// minutes — and the throttle spends whatever the day's reviews leave over.
///
/// Reviews are always served first. New cards are what fits afterwards, which
/// is what makes the system self-correcting: a heavy review day introduces
/// nothing, and the backlog never compounds.
public struct NewCardThrottle: Sendable {

    /// Assumed cost of a first exposure, in seconds. Refine from real data.
    public static let assumedNewCardSeconds = 25.0

    /// Fallback until the rolling average has data.
    public static let assumedReviewSeconds = 12.0

    public let targetMinutes: Double

    public init(targetMinutes: Double = 45) {
        self.targetMinutes = targetMinutes
    }

    /// The ramp that prevents the classic collapse.
    ///
    /// Week one at 25/day feels effortless because there are no reviews yet.
    /// Week five that same rate is 100+ minutes of daily review and the user
    /// quits. The cap exists to stop exactly that.
    public static func dailyCap(weeksSinceStart: Int) -> Int {
        switch weeksSinceStart {
        case ..<2: 15
        case ..<4: 10
        default: 8
        }
    }

    /// Rolling mean seconds per card over the last 14 days of reviews.
    public static func rollingAverageSeconds(
        _ durations: [TimeInterval], fallback: Double = NewCardThrottle.assumedReviewSeconds
    ) -> Double {
        guard !durations.isEmpty else { return fallback }
        return durations.reduce(0, +) / Double(durations.count)
    }

    public func newCardCount(
        dueReviewCount: Int,
        averageSecondsPerCard: Double,
        weeksSinceStart: Int
    ) -> Int {
        let targetSeconds = targetMinutes * 60
        let reviewSeconds = Double(dueReviewCount) * averageSecondsPerCard
        let remaining = targetSeconds - reviewSeconds
        guard remaining > 0 else { return 0 }

        let affordable = Int(remaining / Self.assumedNewCardSeconds)
        return min(max(affordable, 0), Self.dailyCap(weeksSinceStart: weeksSinceStart))
    }

    /// Whole weeks elapsed since the user's first session.
    public static func weeksSinceStart(
        from start: Date, to now: Date = Date(), calendar: Calendar = .current
    ) -> Int {
        max(calendar.dateComponents([.weekOfYear], from: start, to: now).weekOfYear ?? 0, 0)
    }
}
