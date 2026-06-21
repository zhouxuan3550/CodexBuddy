import Foundation

struct CodexUsageProvider: UsageProvider {
    private let sqlitePath = "/usr/bin/sqlite3"

    func fetchUsage() async throws -> UsageSnapshot {
        let body = try await latestUsageLogBody()
        return try parseUsage(from: body)
    }

    private func latestUsageLogBody() async throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/.codex/logs_2.sqlite"

        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw UsageProviderError.dataSourceUnavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = [
            "-readonly",
            dbPath,
            """
            select feedback_log_body
            from logs
            where feedback_log_body like '%x-codex-primary-used-percent%'
            order by ts desc, ts_nanos desc, id desc
            limit 1;
            """
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let body = String(data: output, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errorText = String(data: errorOutput, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0, !body.isEmpty {
                    continuation.resume(returning: body)
                } else {
                    debugLog("sqlite usage query failed: \(errorText)")
                    continuation.resume(throwing: UsageProviderError.unreadableUsage)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: UsageProviderError.unreadableUsage)
            }
        }
    }

    private func parseUsage(from body: String) throws -> UsageSnapshot {
        guard
            let primaryUsedPercent = intHeader("x-codex-primary-used-percent", in: body),
            let secondaryUsedPercent = intHeader("x-codex-secondary-used-percent", in: body)
        else {
            throw UsageProviderError.unreadableUsage
        }

        let primaryMinutes = intHeader("x-codex-primary-window-minutes", in: body) ?? 300
        let secondaryMinutes = intHeader("x-codex-secondary-window-minutes", in: body) ?? 10_080
        let primaryRemainingPercent = remainingPercent(fromUsedPercent: primaryUsedPercent)
        let secondaryRemainingPercent = remainingPercent(fromUsedPercent: secondaryUsedPercent)

        return UsageSnapshot(
            shortWindowLabel: windowLabel(minutes: primaryMinutes),
            shortWindowPercent: primaryRemainingPercent,
            shortWindowResetText: resetText(
                epochSeconds: intHeader("x-codex-primary-reset-at", in: body),
                fallbackAfterSeconds: intHeader("x-codex-primary-reset-after-seconds", in: body),
                style: .time
            ),
            weekWindowLabel: windowLabel(minutes: secondaryMinutes),
            weekWindowPercent: secondaryRemainingPercent,
            weekWindowResetText: resetText(
                epochSeconds: intHeader("x-codex-secondary-reset-at", in: body),
                fallbackAfterSeconds: intHeader("x-codex-secondary-reset-after-seconds", in: body),
                style: .date
            ),
            updatedAt: Date()
        )
    }

    private func remainingPercent(fromUsedPercent usedPercent: Int) -> Int {
        min(100, max(0, 100 - usedPercent))
    }

    private func intHeader(_ name: String, in body: String) -> Int? {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: name))\"\\s*:\\s*\"?([0-9]+)\"?"
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
            let range = Range(match.range(at: 1), in: body)
        else {
            return nil
        }

        return Int(body[range])
    }

    private enum ResetTextStyle {
        case time
        case date
    }

    private func resetText(epochSeconds: Int?, fallbackAfterSeconds: Int?, style: ResetTextStyle) -> String {
        let date: Date
        if let epochSeconds {
            date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        } else if let fallbackAfterSeconds {
            date = Date().addingTimeInterval(TimeInterval(fallbackAfterSeconds))
        } else {
            return "--"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = style == .time ? "HH:mm" : "M月d日"
        return formatter.string(from: date)
    }

    private func windowLabel(minutes: Int) -> String {
        if minutes % 10_080 == 0 {
            return "\(minutes / 10_080) 周"
        }

        if minutes % 60 == 0 {
            return "\(minutes / 60) 小时"
        }

        return "\(minutes) 分钟"
    }

    private func debugLog(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        let url = URL(fileURLWithPath: "/tmp/CodexUsageBar.log")
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
