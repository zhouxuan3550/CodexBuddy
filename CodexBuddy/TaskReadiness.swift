import Foundation

/// A conservative, explainable preflight check for starting a longer Codex
/// task. It intentionally does not claim to estimate a prompt's exact cost;
/// the verdict is based only on quota, reset time, the selected reserve and
/// recent observed burn rate.
@MainActor
enum TaskReadiness {
    enum Verdict: Equatable {
        case ready
        case pace
        case conserve
        case unavailable
    }

    struct Report: Equatable {
        let verdict: Verdict
        let weekRemainingPercent: Int?
        let resetAt: Date?
        let plan: QuotaPacing.Plan?
        let forecastDepletesBeforeReset: Bool
        let isStale: Bool
    }

    static func report(
        reading: UsageReading?,
        reservePercent: Int,
        records: [UsageHistoryStore.Record],
        now: Date = Date()
    ) -> Report {
        guard let reading, let week = reading.weekWindow else {
            return Report(
                verdict: .unavailable,
                weekRemainingPercent: nil,
                resetAt: nil,
                plan: nil,
                forecastDepletesBeforeReset: false,
                isStale: false
            )
        }

        let plan = QuotaPacing.weeklyPlan(
            window: week,
            reservePercent: reservePercent,
            now: now
        )
        let estimate = DepletionEstimator.estimate(
            records: records,
            windowType: .week,
            currentRemaining: week.remainingPercent,
            now: now
        )
        let depletesBeforeReset: Bool
        if let depletedAt = estimate.depletedAt, let resetAt = week.resetAt {
            depletesBeforeReset = depletedAt > now && depletedAt < resetAt
        } else {
            depletesBeforeReset = false
        }
        let stale = reading.isOutdated(at: now)

        let verdict: Verdict
        if stale {
            verdict = .unavailable
        } else if week.remainingPercent < 20 || plan?.state == .protected || depletesBeforeReset {
            verdict = .conserve
        } else if plan?.state == .tight {
            verdict = .pace
        } else {
            verdict = .ready
        }

        return Report(
            verdict: verdict,
            weekRemainingPercent: week.remainingPercent,
            resetAt: week.resetAt,
            plan: plan,
            forecastDepletesBeforeReset: depletesBeforeReset,
            isStale: stale
        )
    }
}
