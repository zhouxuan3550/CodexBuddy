import Foundation
import UserNotifications

@MainActor
final class UsageNotificationManager {
    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    private func scheduleResetCountdown(window: QuotaWindow, kind: String, language: AppLanguage, now: Date) {
        guard let resetAt = window.resetAt else { return }
        let secondsUntilReset = resetAt.timeIntervalSince(now)
        // Only fire when within 5 minutes (300s) and not already past
        guard secondsUntilReset > 0, secondsUntilReset <= 300 else { return }

        let resetIdentifier = Int(resetAt.timeIntervalSince1970)
        let notificationKey = "resetCountdown.\(kind).\(resetIdentifier)"
        guard !defaults.bool(forKey: notificationKey) else { return }
        defaults.set(true, forKey: notificationKey)

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
                defaults.removeObject(forKey: notificationKey)
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
        let notificationKey = "notified.\(kind).\(resetIdentifier).\(threshold)"
        guard !defaults.bool(forKey: notificationKey) else { return }
        defaults.set(true, forKey: notificationKey)

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
                defaults.removeObject(forKey: notificationKey)
                // A denied notification permission should not affect Usage refreshes.
            }
        }
    }
}
