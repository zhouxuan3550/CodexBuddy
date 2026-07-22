import Foundation

struct QuotaWindow: Codable, Equatable {
    let minutes: Int
    let remainingPercent: Int
    let resetAt: Date?

    var consumedPercent: Int {
        100 - min(100, max(0, remainingPercent))
    }

    var isWeekly: Bool { minutes >= 7 * 24 * 60 }
}

enum QuotaLevel: Equatable {
    case critical
    case standard
    case healthy

    static func forRemaining(_ percent: Int) -> QuotaLevel {
        if percent < 20 { return .critical }
        if percent > 60 { return .healthy }
        return .standard
    }
}

enum UsageSource: Codable, Equatable {
    case sessionLog
    case responseHeaders

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .sessionLog:
            return L10n.text(.sessionEvent, language: language)
        case .responseHeaders:
            return L10n.text(.responseHeaderFallback, language: language)
        }
    }
}

struct CreditState: Codable, Equatable {
    let isAvailable: Bool
    let isUnlimited: Bool
    let balance: String?

    var finiteBalance: String? {
        isAvailable && !isUnlimited ? balance : nil
    }
}

enum StatusDisplayMode: String, CaseIterable {
    case allWindows = "dual"
    case tightest = "worst"
}

struct StatusSegment: Equatable {
    let text: String
    let percent: Int
}

struct UsageReading: Equatable {
    let shortWindow: QuotaWindow?
    let weekWindow: QuotaWindow?
    let updatedAt: Date
    let source: UsageSource
    let planName: String?
    let credits: CreditState?

    var tightestWindow: QuotaWindow? {
        [shortWindow, weekWindow]
            .compactMap { $0 }
            .min { $0.remainingPercent < $1.remainingPercent }
    }

    var completeStatusText: String {
        let values = [
            shortWindow.map { "H \($0.remainingPercent)%" },
            weekWindow.map { "W \($0.remainingPercent)%" }
        ].compactMap { $0 }
        return values.isEmpty ? "H --% W --%" : values.joined(separator: " ")
    }

    func menuBarSegments(
        mode: StatusDisplayMode,
        showShortWindow: Bool,
        showWeekWindow: Bool
    ) -> [StatusSegment] {
        if mode == .tightest {
            guard let window = tightestWindow else { return [] }
            return [segment(for: window)]
        }

        var values: [StatusSegment] = []
        if showShortWindow, let shortWindow {
            values.append(segment(for: shortWindow))
        }
        if showWeekWindow, let weekWindow {
            values.append(segment(for: weekWindow))
        }
        return values
    }

    func isOutdated(at date: Date = Date(), maximumAge: TimeInterval = 30 * 60) -> Bool {
        let resetTimes = [shortWindow?.resetAt, weekWindow?.resetAt].compactMap { $0 }
        if resetTimes.contains(where: { date >= $0 }) { return true }
        return resetTimes.isEmpty && date.timeIntervalSince(updatedAt) > maximumAge
    }

    func prefix(for window: QuotaWindow) -> String {
        window.isWeekly ? "W" : "H"
    }

    func detailLine(for window: QuotaWindow, language: AppLanguage) -> String {
        "\(durationLabel(window.minutes, language: language)) \(window.remainingPercent)% · \(resetLabel(window, language: language))"
    }

    private func segment(for window: QuotaWindow) -> StatusSegment {
        StatusSegment(
            text: "\(prefix(for: window)) \(window.remainingPercent)%",
            percent: window.remainingPercent
        )
    }

    private func resetLabel(_ window: QuotaWindow, language: AppLanguage) -> String {
        guard let resetAt = window.resetAt else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.resolved == .simplifiedChinese ? "zh_CN" : "en_US")
        formatter.dateFormat = window.isWeekly
            ? (language.resolved == .simplifiedChinese ? "M月d日" : "MMM d")
            : "HH:mm"
        return formatter.string(from: resetAt)
    }

    private func durationLabel(_ minutes: Int, language: AppLanguage) -> String {
        let chinese = language.resolved == .simplifiedChinese
        if minutes.isMultiple(of: 7 * 24 * 60) {
            let weeks = minutes / (7 * 24 * 60)
            return chinese ? "\(weeks) 周" : "\(weeks) \(weeks == 1 ? "week" : "weeks")"
        }
        if minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return chinese ? "\(hours) 小时" : "\(hours) \(hours == 1 ? "hour" : "hours")"
        }
        return chinese ? "\(minutes) 分钟" : "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
}
