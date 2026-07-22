import Foundation

enum MenuBarMode: String, CaseIterable {
    case dual
    case worst
}

struct MenuBarSegment: Equatable {
    let text: String
    let percent: Int
}

struct UsageWindow: Equatable, Codable {
    let minutes: Int
    let remainingPercent: Int
    let resetAt: Date?

    var usedPercent: Int {
        min(100, max(0, 100 - remainingPercent))
    }
}

enum UsageColorLevel: Equatable {
    case low
    case normal
    case high

    static func classify(percent: Int) -> UsageColorLevel {
        if percent < 20 { return .low }
        if percent > 80 { return .high }
        return .normal
    }
}

enum UsageDataSource: Equatable, Codable {
    case sessionEvent
    case responseHeader

    func localizedName(language: AppLanguage) -> String {
        switch self {
        case .sessionEvent:
            return L10n.text(.sessionEvent, language: language)
        case .responseHeader:
            return L10n.text(.responseHeaderFallback, language: language)
        }
    }
}

struct CreditsInfo: Equatable, Codable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    var displayBalance: String? {
        guard hasCredits, !unlimited else { return nil }
        return balance
    }
}

struct UsageSnapshot: Equatable {
    let shortWindow: UsageWindow?
    let weekWindow: UsageWindow?
    let updatedAt: Date
    let source: UsageDataSource
    let planType: String?
    let credits: CreditsInfo?

    var featuredWindow: UsageWindow? {
        [weekWindow, shortWindow]
            .compactMap { $0 }
            .min { $0.remainingPercent < $1.remainingPercent }
    }

    var menuBarText: String {
        var parts: [String] = []
        if let shortWindow {
            parts.append("H \(shortWindow.remainingPercent)%")
        }
        if let weekWindow {
            parts.append("W \(weekWindow.remainingPercent)%")
        }
        return parts.isEmpty ? "H --% W --%" : parts.joined(separator: " ")
    }

    func menuBarSegments(
        mode: MenuBarMode,
        showShortWindow: Bool,
        showWeekWindow: Bool
    ) -> [MenuBarSegment] {
        if mode == .worst {
            guard let window = featuredWindow else { return [] }
            return [MenuBarSegment(
                text: "\(menuPrefix(for: window)) \(window.remainingPercent)%",
                percent: window.remainingPercent
            )]
        }

        var segments: [MenuBarSegment] = []
        if showShortWindow, let shortWindow {
            segments.append(MenuBarSegment(
                text: "H \(shortWindow.remainingPercent)%",
                percent: shortWindow.remainingPercent
            ))
        }
        if showWeekWindow, let weekWindow {
            segments.append(MenuBarSegment(
                text: "W \(weekWindow.remainingPercent)%",
                percent: weekWindow.remainingPercent
            ))
        }
        return segments
    }

    func isStale(at date: Date = Date(), maximumAge: TimeInterval = 1_800) -> Bool {
        let resetDates = [shortWindow?.resetAt, weekWindow?.resetAt].compactMap { $0 }

        // A window that has already reset makes the percentage definitively wrong.
        if resetDates.contains(where: { date >= $0 }) {
            return true
        }

        // Idle time alone doesn't invalidate the data while every window is
        // still before its reset; only fall back to age when there is no
        // reset schedule to verify against.
        return resetDates.isEmpty && date.timeIntervalSince(updatedAt) > maximumAge
    }

    func line(for window: UsageWindow, language: AppLanguage) -> String {
        "\(windowLabel(minutes: window.minutes, language: language)) \(window.remainingPercent)% · \(resetText(for: window, language: language))"
    }

    func menuPrefix(for window: UsageWindow) -> String {
        window.minutes >= 10_080 ? "W" : "H"
    }

    private func resetText(for window: UsageWindow, language: AppLanguage) -> String {
        guard let resetAt = window.resetAt else { return "--" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.resolved == .simplifiedChinese ? "zh_CN" : "en_US")
        formatter.dateFormat = window.minutes >= 10_080
            ? (language.resolved == .simplifiedChinese ? "M月d日" : "MMM d")
            : "HH:mm"
        return formatter.string(from: resetAt)
    }

    private func windowLabel(minutes: Int, language: AppLanguage) -> String {
        let isChinese = language.resolved == .simplifiedChinese
        if minutes % 10_080 == 0 {
            let value = minutes / 10_080
            return isChinese ? "\(value) 周" : "\(value) \(value == 1 ? "week" : "weeks")"
        }
        if minutes % 60 == 0 {
            let value = minutes / 60
            return isChinese ? "\(value) 小时" : "\(value) \(value == 1 ? "hour" : "hours")"
        }
        return isChinese ? "\(minutes) 分钟" : "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
}
