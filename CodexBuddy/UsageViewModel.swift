import AppKit
import Combine
import Foundation

enum UsageViewModelIssue: Equatable {
    case sourceUnavailable
    case unreadable
    case formatChanged
    case suspiciousQuotaRecovery
}

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var reading: UsageReading?
    @Published private(set) var isReloading = false
    @Published private(set) var issue: UsageViewModelIssue?

    private let source: UsageReadingSource
    private let clockFormatter: DateFormatter
    private var formatSignalCount = 0
    private var lastFormatEvidence: Date?

    init(source: UsageReadingSource) {
        self.source = source
        clockFormatter = DateFormatter()
        clockFormatter.dateFormat = "HH:mm"
    }

    var statusText: String {
        guard let reading else { return "H --% W --%" }
        return reading.completeStatusText + (reading.isOutdated() ? " ⚠︎" : "")
    }

    func reload() async {
        guard !isReloading else { return }
        isReloading = true
        defer { isReloading = false }

        do {
            let outcome = try await source.read()
            reading = outcome.reading
            apply(outcome.healthSignal)
        } catch let error as UsageReadError {
            switch error {
            case .unavailable:
                issue = .sourceUnavailable
            case .unreadable:
                issue = .unreadable
            case .formatChanged(let evidenceAt):
                apply(.sessionFormatChanged(evidenceAt: evidenceAt))
                if reading == nil, issue == nil { issue = .unreadable }
            }
        } catch {
            issue = .unreadable
        }
    }

    func confidenceText(language: AppLanguage, now: Date = Date()) -> String? {
        guard let reading else { return nil }
        let seconds = max(0, now.timeIntervalSince(reading.updatedAt))
        let freshness: String
        if seconds < 60 {
            freshness = L10n.text(.justNow, language: language)
        } else {
            let minutes = max(1, Int(seconds / 60))
            freshness = language.resolved == .simplifiedChinese
                ? "\(minutes)\(L10n.text(.minutesAgo, language: language))"
                : "\(minutes) \(L10n.text(.minutesAgo, language: language))"
        }

        var parts = [reading.source.displayName(language: language), freshness]
        if reading.isOutdated(at: now) {
            parts.append("⚠︎ \(L10n.text(.dataMayBeStale, language: language))")
        }
        return parts.joined(separator: " · ")
    }

    func sourceText(language: AppLanguage, now: Date = Date()) -> String? {
        confidenceText(language: language, now: now).map {
            "\(L10n.text(.dataSource, language: language)): \($0)"
        }
    }

    func updatedText(language: AppLanguage) -> String {
        guard let date = reading?.updatedAt else {
            return L10n.text(.neverUpdated, language: language)
        }
        clockFormatter.locale = Locale(
            identifier: language.resolved == .simplifiedChinese ? "zh_CN" : "en_US"
        )
        return "\(L10n.text(.updatedAt, language: language)): \(clockFormatter.string(from: date))"
    }

    func detailText(language: AppLanguage) -> String {
        if reading == nil {
            if let issue { return localized(issue, language: language) }
            return L10n.text(.loadingUsage, language: language)
        }
        return issue.map { localized($0, language: language) } ?? ""
    }

    func openOfficialUsagePage() {
        NSWorkspace.shared.open(ProductIdentity.officialUsageURL)
    }

    private func apply(_ signal: UsageHealthSignal?) {
        guard let signal else {
            formatSignalCount = 0
            lastFormatEvidence = nil
            issue = nil
            return
        }
        switch signal {
        case .suspiciousQuotaRecovery:
            formatSignalCount = 0
            lastFormatEvidence = nil
            issue = .suspiciousQuotaRecovery
        case .sessionFormatChanged(let evidenceAt):
            if evidenceAt != lastFormatEvidence {
                formatSignalCount += 1
                lastFormatEvidence = evidenceAt
            }
            issue = formatSignalCount >= 2 ? .formatChanged : nil
        }
    }

    private func localized(_ issue: UsageViewModelIssue, language: AppLanguage) -> String {
        switch issue {
        case .sourceUnavailable:
            return L10n.text(.dataSourceUnavailable, language: language)
        case .unreadable:
            return L10n.text(.unreadableUsage, language: language)
        case .formatChanged:
            return L10n.text(.schemaDrift, language: language)
        case .suspiciousQuotaRecovery:
            return L10n.text(.suspiciousQuotaRecovery, language: language)
        }
    }
}
