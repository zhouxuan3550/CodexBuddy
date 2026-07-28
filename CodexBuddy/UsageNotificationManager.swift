import Foundation
import UserNotifications

@MainActor
final class UsageNotificationManager {
    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults

    // One value key per notification kind instead of a bool key per reset cycle,
    // so long-running installs no longer accumulate dead keys in UserDefaults.
    private static let thresholdKeyPrefix = "notified.last."
    private static let countdownKeyPrefix = "resetCountdown.last."
    private static let depletionKeyPrefix = "depletionForecast.last."
    private static let surplusKeyPrefix = "surplusReminder.last."
    private static let weeklyReportCycleKey = "weeklyReport.lastReset"
    private static let weeklyReportRemainingKey = "weeklyReport.lastRemaining"
    private static let legacyCleanupKey = "notificationKeys.cleanedLegacyV1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cleanUpLegacyKeysIfNeeded()
    }

    /// Removes per-cycle bool keys written by earlier versions (one per reset
    /// window, never reclaimed). Runs once per install.
    private func cleanUpLegacyKeysIfNeeded() {
        guard !defaults.bool(forKey: Self.legacyCleanupKey) else { return }
        for key in defaults.dictionaryRepresentation().keys {
            let isLegacyThreshold = key.hasPrefix("notified.") && !key.hasPrefix(Self.thresholdKeyPrefix)
            let isLegacyCountdown = key.hasPrefix("resetCountdown.") && !key.hasPrefix(Self.countdownKeyPrefix)
            if isLegacyThreshold || isLegacyCountdown {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.set(true, forKey: Self.legacyCleanupKey)
    }

    func requestAuthorization() {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func evaluate(
        reading: UsageReading,
        threshold: Int,
        language: AppLanguage,
        enabled: Bool
    ) {
        guard enabled else { return }

        if let shortWindow = reading.shortWindow {
            scheduleIfNeeded(
                window: shortWindow,
                kind: "short",
                title: L10n.text(.shortWindowNotificationTitle, language: language),
                threshold: threshold,
                language: language
            )
        }
        if let weekWindow = reading.weekWindow {
            scheduleIfNeeded(
                window: weekWindow,
                kind: "week",
                title: L10n.text(.weekWindowNotificationTitle, language: language),
                threshold: threshold,
                language: language
            )
        }
    }

    /// Sends a notification when a window's reset is within 5 minutes.
    func evaluateResetCountdown(reading: UsageReading, language: AppLanguage, enabled: Bool) {
        guard enabled else { return }
        let now = Date()

        if let shortWindow = reading.shortWindow {
            scheduleResetCountdown(window: shortWindow, kind: "short", language: language, now: now)
        }
        if let weekWindow = reading.weekWindow {
            scheduleResetCountdown(window: weekWindow, kind: "week", language: language, now: now)
        }
    }

    /// Predictive alert: fires once per reset cycle when the recent burn rate
    /// says a window will run dry before it resets. Smarter than the fixed
    /// threshold alert because it reacts to pace, not just the level.
    func evaluateDepletionForecast(
        reading: UsageReading,
        records: [UsageHistoryStore.Record],
        language: AppLanguage,
        enabled: Bool
    ) {
        guard enabled else { return }
        let now = Date()

        if let shortWindow = reading.shortWindow {
            scheduleDepletionForecast(
                window: shortWindow,
                windowType: .short,
                kind: "short",
                leadMinutes: 90,
                records: records,
                language: language,
                now: now
            )
        }
        if let weekWindow = reading.weekWindow {
            scheduleDepletionForecast(
                window: weekWindow,
                windowType: .week,
                kind: "week",
                leadMinutes: 12 * 60,
                records: records,
                language: language,
                now: now
            )
        }
    }

    /// Weekly recap: when the weekly window rolls over into a new cycle,
    /// summarize the finished week (consumed percent, tokens, hottest project,
    /// week-over-week change). Cycle tracking runs even while notifications
    /// are disabled so enabling them later never replays an old cycle.
    func evaluateWeeklyReport(
        reading: UsageReading,
        dailyBreakdown: [String: UsageDayBreakdown],
        language: AppLanguage,
        enabled: Bool
    ) {
        guard let week = reading.weekWindow, let resetAt = week.resetAt else { return }
        let resetIdentifier = Int(resetAt.timeIntervalSince1970)
        let storedCycle = defaults.integer(forKey: Self.weeklyReportCycleKey)
        let storedRemaining = defaults.object(forKey: Self.weeklyReportRemainingKey) as? Int

        defer {
            defaults.set(resetIdentifier, forKey: Self.weeklyReportCycleKey)
            if storedCycle == resetIdentifier {
                // Same cycle: remember the lowest remaining seen, which is the
                // final consumption level right before the reset.
                defaults.set(
                    min(storedRemaining ?? 100, week.remainingPercent),
                    forKey: Self.weeklyReportRemainingKey
                )
            } else {
                defaults.set(week.remainingPercent, forKey: Self.weeklyReportRemainingKey)
            }
        }

        guard storedCycle != 0, storedCycle != resetIdentifier else { return }
        // Weekly resetAt can jitter by seconds between readings; only a jump
        // of at least a day is a genuine rollover.
        guard resetIdentifier - storedCycle >= 86_400 else { return }
        guard enabled else { return }

        let chinese = language.resolved == .simplifiedChinese
        let stats = UsageWeeklyReportStats.build(dailyBreakdown: dailyBreakdown)
        var parts: [String] = []
        if let remaining = storedRemaining {
            let consumed = 100 - max(0, min(100, remaining))
            parts.append(chinese ? "上周用掉 \(consumed)% 额度" : "Used \(consumed)% of last week's quota")
        }
        if stats.totalTokens > 0 {
            let tokens = TokenFormat.compact(stats.totalTokens, language: language)
            parts.append("\(tokens) tokens")
            if let project = stats.topProject {
                parts.append(chinese ? "最烧的项目是 \(project)" : "top project: \(project)")
            }
            if let delta = stats.deltaPercent {
                let signed = delta >= 0 ? "+\(delta)%" : "\(delta)%"
                parts.append(chinese ? "比前一周 \(signed)" : "\(signed) vs the week before")
            }
        }
        guard !parts.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.text(.weeklyReportTitle, language: language)
        content.body = parts.joined(separator: " · ")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(ProductIdentity.name).weeklyReport.\(resetIdentifier)",
            content: content,
            trigger: nil
        )
        Task { try? await center.add(request) }
    }

    /// The inverse of the depletion alert: shortly before the weekly reset,
    /// if most of the quota is still unused, nudge the user to spend it
    /// instead of letting it expire. Fires once per reset cycle.
    func evaluateSurplusReminder(reading: UsageReading, language: AppLanguage, enabled: Bool) {
        guard enabled, let week = reading.weekWindow, let resetAt = week.resetAt else { return }
        let now = Date()
        guard
            DepletionEstimator.surplusShouldFire(
                remainingPercent: week.remainingPercent,
                resetAt: resetAt,
                leadMinutes: 12 * 60,
                minimumRemainingPercent: 50,
                now: now
            )
        else { return }

        let resetIdentifier = Int(resetAt.timeIntervalSince1970)
        let notificationKey = Self.surplusKeyPrefix + "week"
        guard defaults.integer(forKey: notificationKey) != resetIdentifier else { return }
        let previousValue = defaults.object(forKey: notificationKey)
        defaults.set(resetIdentifier, forKey: notificationKey)

        let chinese = language.resolved == .simplifiedChinese
        let formatter = UIDateFormatters.formatter(
            dateFormat: chinese ? "M月d日 HH:mm" : "MMM d, HH:mm",
            localeIdentifier: chinese ? "zh_CN" : "en_US"
        )
        let time = formatter.string(from: resetAt)

        let content = UNMutableNotificationContent()
        content.title = L10n.text(.surplusReminderTitle, language: language)
        content.body = chinese
            ? "每周额度还剩 \(week.remainingPercent)%，\(time) 重置，放开用"
            : "\(week.remainingPercent)% of the weekly quota is still left — it resets \(time). Use it freely"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(ProductIdentity.name).surplusReminder.week.\(resetIdentifier)",
            content: content,
            trigger: nil
        )
        Task {
            do {
                try await center.add(request)
            } catch {
                if let previousValue {
                    defaults.set(previousValue, forKey: notificationKey)
                } else {
                    defaults.removeObject(forKey: notificationKey)
                }
            }
        }
    }

    private func scheduleDepletionForecast(
        window: QuotaWindow,
        windowType: DepletionEstimator.WindowType,
        kind: String,
        leadMinutes: Int,
        records: [UsageHistoryStore.Record],
        language: AppLanguage,
        now: Date
    ) {
        guard window.remainingPercent > 0 else { return }
        let estimate = DepletionEstimator.estimate(
            records: records,
            windowType: windowType,
            currentRemaining: window.remainingPercent,
            now: now
        )
        guard
            DepletionEstimator.forecastShouldFire(
                estimate: estimate,
                resetAt: window.resetAt,
                leadMinutes: leadMinutes,
                now: now
            ),
            let depletedAt = estimate.depletedAt,
            let resetAt = window.resetAt
        else { return }

        let resetIdentifier = Int(resetAt.timeIntervalSince1970)
        let notificationKey = Self.depletionKeyPrefix + kind
        guard defaults.integer(forKey: notificationKey) != resetIdentifier else { return }
        let previousValue = defaults.object(forKey: notificationKey)
        defaults.set(resetIdentifier, forKey: notificationKey)

        let chinese = language.resolved == .simplifiedChinese
        let formatter = UIDateFormatters.formatter(
            dateFormat: kind == "week"
                ? (chinese ? "M月d日 HH:mm" : "MMM d, HH:mm")
                : "HH:mm",
            localeIdentifier: chinese ? "zh_CN" : "en_US"
        )
        let time = formatter.string(from: depletedAt)

        let content = UNMutableNotificationContent()
        content.title = L10n.text(
            kind == "short" ? .depletionForecastShortTitle : .depletionForecastWeekTitle,
            language: language
        )
        content.body = chinese
            ? "按最近的消耗速度，预计 \(time) 耗尽（早于重置时间），可考虑放缓节奏"
            : "At the current pace, quota runs out around \(time) — before it resets. Consider pacing down"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(ProductIdentity.name).depletionForecast.\(kind).\(resetIdentifier)",
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await center.add(request)
            } catch {
                if let previousValue {
                    defaults.set(previousValue, forKey: notificationKey)
                } else {
                    defaults.removeObject(forKey: notificationKey)
                }
            }
        }
    }

    private func scheduleResetCountdown(window: QuotaWindow, kind: String, language: AppLanguage, now: Date) {
        guard let resetAt = window.resetAt else { return }
        let secondsUntilReset = resetAt.timeIntervalSince(now)
        // Only fire when within 5 minutes (300s) and not already past
        guard secondsUntilReset > 0, secondsUntilReset <= 300 else { return }

        let resetIdentifier = Int(resetAt.timeIntervalSince1970)
        let notificationKey = Self.countdownKeyPrefix + kind
        guard defaults.integer(forKey: notificationKey) != resetIdentifier else { return }
        let previousValue = defaults.object(forKey: notificationKey)
        defaults.set(resetIdentifier, forKey: notificationKey)

        let content = UNMutableNotificationContent()
        content.title = L10n.text(.resetCountdownTitle, language: language)
        content.body = L10n.text(.resetCountdownBody, language: language)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(ProductIdentity.name).resetCountdown.\(kind).\(resetIdentifier)",
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await center.add(request)
            } catch {
                if let previousValue {
                    defaults.set(previousValue, forKey: notificationKey)
                } else {
                    defaults.removeObject(forKey: notificationKey)
                }
            }
        }
    }

    private func scheduleIfNeeded(
        window: QuotaWindow,
        kind: String,
        title: String,
        threshold: Int,
        language: AppLanguage
    ) {
        guard window.remainingPercent <= threshold else { return }

        let resetIdentifier = Int(window.resetAt?.timeIntervalSince1970 ?? 0)
        let notificationKey = Self.thresholdKeyPrefix + kind
        let dedupValue = "\(resetIdentifier).\(threshold)"
        guard defaults.string(forKey: notificationKey) != dedupValue else { return }
        let previousValue = defaults.string(forKey: notificationKey)
        defaults.set(dedupValue, forKey: notificationKey)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "\(window.remainingPercent)% \(L10n.text(.percentRemaining, language: language))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(ProductIdentity.name).\(kind).\(resetIdentifier).\(threshold)",
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await center.add(request)
            } catch {
                if let previousValue {
                    defaults.set(previousValue, forKey: notificationKey)
                } else {
                    defaults.removeObject(forKey: notificationKey)
                }
                // A denied notification permission should not affect Usage refreshes.
            }
        }
    }
}
