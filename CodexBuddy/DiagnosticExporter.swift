import AppKit
import Foundation

/// Exports a diagnostic report with sensitive information automatically redacted.
@MainActor
enum DiagnosticExporter {
    static func export(
        reading: UsageReading?,
        settings: AppSettings,
        historyStore: UsageHistoryStore,
        language: AppLanguage
    ) {
        let report = generateReport(
            reading: reading,
            settings: settings,
            historyStore: historyStore,
            language: language
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(ProductIdentity.name)-Diagnostic-\(dateStamp()).txt"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? report.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func generateReport(
        reading: UsageReading?,
        settings: AppSettings,
        historyStore: UsageHistoryStore,
        language: AppLanguage
    ) -> String {
        var lines: [String] = []
        let isChinese = language.resolved == .simplifiedChinese

        lines.append("=== \(ProductIdentity.name) \(L10n.text(.about, language: language)) ===")
        lines.append("")

        // App info
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        lines.append("[App]")
        lines.append("Version: \(version) (Build \(build))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Arch: \(ProcessInfo.processInfo.machineArchitecture)")
        lines.append("")

        // Current snapshot (redacted)
        lines.append("[Current Usage]")
        if let reading {
            lines.append("Short window: \(reading.shortWindow.map { "\($0.remainingPercent)% remaining, resets \($0.resetAt.map { "\($0)" } ?? "unknown")" } ?? "N/A")")
            lines.append("Week window: \(reading.weekWindow.map { "\($0.remainingPercent)% remaining, resets \($0.resetAt.map { "\($0)" } ?? "unknown")" } ?? "N/A")")
            lines.append("Plan: \(reading.planName ?? "unknown")")
            lines.append("Credits: \(reading.credits.map { $0.isUnlimited ? "unlimited" : ($0.balance ?? "N/A") } ?? "N/A")")
            lines.append("Source: \(reading.source)")
            lines.append("Updated: \(reading.updatedAt)")
            lines.append("Stale: \(reading.isOutdated())")
        } else {
            lines.append("No data available")
        }
        lines.append("")

        // Settings (no sensitive data)
        lines.append("[Settings]")
        lines.append("Refresh interval: \(Int(settings.refreshInterval))s")
        lines.append("Notifications: \(settings.notificationsEnabled ? "on" : "off") (threshold \(settings.notificationThreshold)%)")
        lines.append("Language: \(settings.language.rawValue)")
        lines.append("Launch at login: \(settings.launchAtLoginEnabled)")
        lines.append("Floating widget: \(settings.floatingWidgetEnabled)")
        lines.append("")

        // History summary (no conversation content)
        let records7d = historyStore.records7d()
        lines.append("[History]")
        lines.append("Total records (7d): \(records7d.count)")
        if let first = records7d.first, let last = records7d.last {
            lines.append("Range: \(first.timestamp) → \(last.timestamp)")
        }
        lines.append("")

        // Data source availability
        lines.append("[Data Sources]")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsExist = FileManager.default.fileExists(atPath: "\(home)/.codex/sessions")
        let sqliteExists = FileManager.default.fileExists(atPath: "\(home)/.codex/logs_2.sqlite")
        lines.append("Sessions dir: \(sessionsExist ? "present" : "missing")")
        lines.append("SQLite log: \(sqliteExists ? "present" : "missing")")
        lines.append("")

        lines.append("=== \(isChinese ? "报告结束（已自动隐藏对话内容和敏感信息）" : "End of report (conversation content and sensitive data redacted)") ===")

        return lines.joined(separator: "\n")
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
