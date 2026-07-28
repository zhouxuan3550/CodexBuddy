import Foundation

/// Estimates when usage will be depleted based on historical consumption rate.
@MainActor
enum DepletionEstimator {
    struct Estimate {
        let depletedAt: Date?
        let ratePerHour: Double  // percent consumed per hour

        var isDepleting: Bool { ratePerHour > 0.01 }
    }

    /// Estimates depletion for a specific window type using history records.
    static func estimate(
        records: [UsageHistoryStore.Record],
        windowType: WindowType,
        currentRemaining: Int,
        now: Date = Date()
    ) -> Estimate {
        guard let ratePerMinute = recentConsumptionRatePerMinute(
            records: records,
            windowType: windowType,
            now: now
        ) else {
            return Estimate(depletedAt: nil, ratePerHour: 0)
        }

        let ratePerHour = ratePerMinute * 60
        let hoursToDeplete = Double(currentRemaining) / ratePerHour
        let depletedAt = now.addingTimeInterval(hoursToDeplete * 3600)
        return Estimate(depletedAt: depletedAt, ratePerHour: ratePerHour)
    }

    enum WindowType {
        case short
        case week
    }

    static func runwayMinutes(
        records: [UsageHistoryStore.Record],
        windowType: WindowType,
        currentRemaining: Int,
        now: Date = Date()
    ) -> Int? {
        guard let ratePerMinute = recentConsumptionRatePerMinute(
            records: records,
            windowType: windowType,
            now: now
        ) else {
            return nil
        }
        return max(0, Int((Double(currentRemaining) / ratePerMinute).rounded()))
    }

    private static func recentConsumptionRatePerMinute(
        records: [UsageHistoryStore.Record],
        windowType: WindowType,
        now: Date
    ) -> Double? {
        let cutoff = now.addingTimeInterval(-15 * 60)
        let points = records.compactMap { record -> (time: Date, remaining: Int)? in
            let remaining: Int?
            switch windowType {
            case .short: remaining = record.shortRemaining
            case .week: remaining = record.weekRemaining
            }
            guard let remaining, record.timestamp >= cutoff, record.timestamp <= now else {
                return nil
            }
            return (record.timestamp, remaining)
        }.sorted { $0.time < $1.time }

        var uniquePoints: [(time: Date, remaining: Int)] = []
        for point in points {
            if uniquePoints.last?.time == point.time {
                uniquePoints[uniquePoints.count - 1] = point
            } else {
                uniquePoints.append(point)
            }
        }

        guard uniquePoints.count >= 3 else { return nil }

        var segmentStart = uniquePoints.count - 1
        while segmentStart > 0,
              uniquePoints[segmentStart - 1].remaining >= uniquePoints[segmentStart].remaining {
            segmentStart -= 1
        }
        let segment = Array(uniquePoints[segmentStart...])
        guard let first = segment.first, let last = segment.last else { return nil }

        let durationMinutes = last.time.timeIntervalSince(first.time) / 60
        guard durationMinutes >= 5, segment.count >= 3 else { return nil }

        let consumed = Double(first.remaining - last.remaining)
        let ratePerMinute = consumed / durationMinutes
        guard ratePerMinute > 0.2 else { return nil }
        return ratePerMinute
    }

    /// Gate for the depletion-forecast notification: fire only when the
    /// window is predicted to run out BEFORE its reset, within `leadMinutes`
    /// from now. A depletion past the reset resolves itself, so stay quiet.
    static func forecastShouldFire(
        estimate: Estimate,
        resetAt: Date?,
        leadMinutes: Int,
        now: Date = Date()
    ) -> Bool {
        guard estimate.isDepleting, let depletedAt = estimate.depletedAt else { return false }
        guard let resetAt, depletedAt < resetAt else { return false }
        let interval = depletedAt.timeIntervalSince(now)
        return interval > 0 && interval <= Double(leadMinutes) * 60
    }

    /// Gate for the surplus reminder (the inverse of the depletion alert):
    /// fire when the reset is close but plenty of quota is still unused, so
    /// the user knows they can spend freely instead of letting it expire.
    static func surplusShouldFire(
        remainingPercent: Int,
        resetAt: Date?,
        leadMinutes: Int,
        minimumRemainingPercent: Int,
        now: Date = Date()
    ) -> Bool {
        guard remainingPercent >= minimumRemainingPercent, let resetAt else { return false }
        let interval = resetAt.timeIntervalSince(now)
        return interval > 0 && interval <= Double(leadMinutes) * 60
    }

    /// Formats the consumption rate for display (e.g. "~2.3%/h").
    static func formatRate(_ estimate: Estimate) -> String? {
        guard estimate.isDepleting else { return nil }
        let rate = estimate.ratePerHour
        if rate >= 1 {
            return "~\(String(format: "%.0f", rate))%/h"
        }
        return "~\(String(format: "%.1f", rate))%/h"
    }

    /// Formats the estimate for display.
    static func formatEstimate(_ estimate: Estimate, language: AppLanguage) -> String? {
        guard estimate.isDepleting, let depletedAt = estimate.depletedAt else { return nil }

        let interval = depletedAt.timeIntervalSince(Date())
        guard interval > 0 else {
            return language.resolved == .simplifiedChinese ? "即将耗尽" : "Depleting soon"
        }

        let isChinese = language.resolved == .simplifiedChinese
        if interval >= 86_400 {
            let days = Int(interval / 86_400)
            return isChinese ? "预计 \(days) 天后耗尽" : "Est. depleted in \(days)d"
        } else if interval >= 3600 {
            let hours = Int(interval / 3600)
            return isChinese ? "预计 \(hours) 小时后耗尽" : "Est. depleted in \(hours)h"
        } else {
            let minutes = max(1, Int(interval / 60))
            return isChinese ? "预计 \(minutes) 分钟后耗尽" : "Est. depleted in \(minutes)m"
        }
    }
}
