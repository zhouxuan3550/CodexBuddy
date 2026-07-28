import AppKit
import Foundation

/// Exports usage history as CSV for external analysis.
@MainActor
enum CSVExporter {
    static func export(historyStore: UsageHistoryStore, language: AppLanguage) {
        let records = historyStore.records7d()
        guard !records.isEmpty else { return }

        var lines: [String] = ["timestamp,short_remaining,week_remaining,plan_type,credits_balance"]
        let formatter = ISO8601DateFormatter()

        for record in records {
            let ts = formatter.string(from: record.timestamp)
            let short = record.shortRemaining.map(String.init) ?? ""
            let week = record.weekRemaining.map(String.init) ?? ""
            let plan = record.planType ?? ""
            let credits = record.creditsBalance ?? ""
            lines.append("\(ts),\(short),\(week),\(plan),\(credits)")
        }

        let csv = lines.joined(separator: "\n")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(ProductIdentity.name)-History-\(dateStamp()).csv"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Exports the per-day token totals shown in the usage dashboard.
    static func exportDailyTokens(_ dailyTokens: [String: Int64]) {
        guard !dailyTokens.isEmpty else { return }

        var lines: [String] = ["date,tokens"]
        for key in dailyTokens.keys.sorted() {
            lines.append("\(key),\(dailyTokens[key] ?? 0)")
        }
        let csv = lines.joined(separator: "\n")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(ProductIdentity.name)-DailyTokens-\(dateStamp()).csv"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
