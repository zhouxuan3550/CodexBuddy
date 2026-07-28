import Foundation

/// Converts a weekly quota into a small, actionable daily plan. The reserve
/// is a user-selected buffer for the rest of the rolling week; it is never a
/// hard limit and does not affect Codex itself.
enum QuotaPacing {
    enum State: Equatable {
        case relaxed
        case onTrack
        case tight
        case protected
    }

    struct Plan: Equatable {
        let remainingPercent: Int
        let reservePercent: Int
        let daysRemaining: Int
        let dailyAllowancePercent: Int
        let expectedRemainingPercent: Int
        let paceDeltaPercent: Int
        let state: State

        var isReserveEnabled: Bool { reservePercent > 0 }
    }

    /// Builds a plan for a rolling weekly quota. The ideal line goes from
    /// 100% at the beginning of the cycle to the chosen reserve at reset.
    /// This makes the result useful even before enough history exists for a
    /// consumption-rate forecast.
    static func weeklyPlan(
        window: QuotaWindow?,
        reservePercent: Int,
        now: Date = Date()
    ) -> Plan? {
        guard
            let window,
            window.isWeekly,
            let resetAt = window.resetAt,
            resetAt > now
        else {
            return nil
        }

        let reserve = min(80, max(0, reservePercent))
        let remaining = min(100, max(0, window.remainingPercent))
        let secondsLeft = resetAt.timeIntervalSince(now)
        let totalSeconds = Double(window.minutes) * 60
        guard totalSeconds > 0 else { return nil }

        // Count today as a usable budget day. A plan that says "0 days" on
        // reset day is technically correct but not actionable.
        let daysRemaining = max(1, Int(ceil(secondsLeft / 86_400)))
        let availableBeyondReserve = max(0, remaining - reserve)
        let dailyAllowance = availableBeyondReserve / daysRemaining

        let timeFraction = min(1, max(0, secondsLeft / totalSeconds))
        let expectedRemaining = Int(
            (Double(reserve) + Double(100 - reserve) * timeFraction).rounded()
        )
        let paceDelta = remaining - expectedRemaining

        let state: State
        if remaining <= reserve {
            state = .protected
        } else if paceDelta >= 10 {
            state = .relaxed
        } else if paceDelta <= -10 {
            state = .tight
        } else {
            state = .onTrack
        }

        return Plan(
            remainingPercent: remaining,
            reservePercent: reserve,
            daysRemaining: daysRemaining,
            dailyAllowancePercent: dailyAllowance,
            expectedRemainingPercent: expectedRemaining,
            paceDeltaPercent: paceDelta,
            state: state
        )
    }
}
