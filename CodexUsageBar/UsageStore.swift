import AppKit
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var providerError: UsageProviderError?

    private let provider: UsageProvider
    private let timeFormatter: DateFormatter
    private var consecutiveDriftCount = 0
    private var lastDriftEvidenceAt: Date?

    init(provider: UsageProvider) {
        self.provider = provider
        self.timeFormatter = DateFormatter()
        self.timeFormatter.locale = Locale(identifier: "zh_CN")
        self.timeFormatter.dateFormat = "HH:mm"
    }

    var statusText: String {
        if isLoading, snapshot == nil {
            return "H --% W --%"
        }

        if let snapshot {
            return snapshot.menuBarText + (snapshot.isStale() ? " ⚠︎" : "")
        }

        return "H --% W --%"
    }

    func sourceStatusText(language: AppLanguage, now: Date = Date()) -> String? {
        guard let confidenceStatus = confidenceStatusText(language: language, now: now) else {
            return nil
        }
        return "\(L10n.text(.dataSource, language: language)): \(confidenceStatus)"
    }

    func confidenceStatusText(language: AppLanguage, now: Date = Date()) -> String? {
        guard let snapshot else { return nil }

        let age = max(0, now.timeIntervalSince(snapshot.updatedAt))
        let freshness: String
        if age < 60 {
            freshness = L10n.text(.justNow, language: language)
        } else {
            let minutes = max(1, Int(age / 60))
            freshness = language.resolved == .simplifiedChinese
                ? "\(minutes)\(L10n.text(.minutesAgo, language: language))"
                : "\(minutes) \(L10n.text(.minutesAgo, language: language))"
        }

        var components = [snapshot.source.localizedName(language: language), freshness]
        if snapshot.isStale(at: now) {
            components.append("⚠︎ \(L10n.text(.dataMayBeStale, language: language))")
        }
        return components.joined(separator: " · ")
    }

    func updatedAtText(language: AppLanguage) -> String {
        guard let updatedAt = snapshot?.updatedAt else {
            return L10n.text(.neverUpdated, language: language)
        }

        timeFormatter.locale = Locale(identifier: language.resolved == .simplifiedChinese ? "zh_CN" : "en_US")
        return "\(L10n.text(.updatedAt, language: language)): \(timeFormatter.string(from: updatedAt))"
    }

    func detailMessage(language: AppLanguage) -> String {
        if let providerError, snapshot == nil {
            return localizedError(providerError, language: language)
        }

        if snapshot == nil {
            return L10n.text(.loadingUsage, language: language)
        }

        if let providerError {
            return localizedError(providerError, language: language)
        }

        return ""
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await provider.fetchUsageResult()
            snapshot = result.snapshot
            updateProviderDiagnostic(result.diagnostic)
        } catch {
            if case .schemaDriftEvidence(let evidenceAt) = error as? UsageProviderError {
                updateProviderDiagnostic(.sessionSchemaDrift(evidenceAt: evidenceAt))
                if snapshot == nil, providerError == nil {
                    providerError = .unreadableUsage
                }
            } else {
                providerError = error as? UsageProviderError ?? .unreadableUsage
            }
        }
    }

    func openOfficialUsage() {
        guard let url = URL(string: "https://chatgpt.com/codex/usage") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func localizedError(_ error: UsageProviderError, language: AppLanguage) -> String {
        switch error {
        case .dataSourceUnavailable:
            return L10n.text(.dataSourceUnavailable, language: language)
        case .notLoggedIn:
            return L10n.text(.notLoggedIn, language: language)
        case .unreadableUsage:
            return L10n.text(.unreadableUsage, language: language)
        case .schemaDrift:
            return L10n.text(.schemaDrift, language: language)
        case .schemaDriftEvidence:
            return L10n.text(.schemaDrift, language: language)
        }
    }

    private func updateProviderDiagnostic(_ diagnostic: UsageProviderDiagnostic?) {
        guard case .sessionSchemaDrift(let evidenceAt) = diagnostic else {
            consecutiveDriftCount = 0
            lastDriftEvidenceAt = nil
            providerError = nil
            return
        }

        if evidenceAt != lastDriftEvidenceAt {
            consecutiveDriftCount += 1
            lastDriftEvidenceAt = evidenceAt
        }
        providerError = consecutiveDriftCount >= 2 ? .schemaDrift : nil
    }
}
