import Foundation

struct CodexUsageProvider: UsageProvider {
    private let sqlitePath = "/usr/bin/sqlite3"
    private let databasePath: String?
    private let sessionsPath: String?

    init(databasePath: String? = nil, sessionsPath: String? = nil) {
        self.databasePath = databasePath
        self.sessionsPath = sessionsPath
    }

    func fetchUsage() async throws -> UsageSnapshot {
        try await fetchUsageResult().snapshot
    }

    func fetchUsageResult() async throws -> UsageFetchResult {
        let sessionResult = await latestSessionUsage()

        do {
            let headerSnapshot = try await latestUsageLogSnapshot()
            switch sessionResult {
            case .success(let sessionSnapshot):
                let snapshot = sessionSnapshot.updatedAt >= headerSnapshot.updatedAt
                    ? sessionSnapshot
                    : headerSnapshot
                return UsageFetchResult(snapshot: snapshot, diagnostic: nil)
            case .driftSuspected(let evidenceAt):
                return UsageFetchResult(
                    snapshot: headerSnapshot,
                    diagnostic: .sessionSchemaDrift(evidenceAt: evidenceAt)
                )
            case .noData:
                return UsageFetchResult(snapshot: headerSnapshot, diagnostic: nil)
            }
        } catch {
            switch sessionResult {
            case .success(let sessionSnapshot):
                return UsageFetchResult(snapshot: sessionSnapshot, diagnostic: nil)
            case .driftSuspected(let evidenceAt):
                throw UsageProviderError.schemaDriftEvidence(evidenceAt)
            case .noData:
                throw error
            }
        }
    }

    private enum SessionReadResult {
        case success(UsageSnapshot)
        case driftSuspected(evidenceAt: Date)
        case noData
    }

    private enum SessionFileReadResult {
        case success(snapshot: UsageSnapshot, eventDate: Date)
        case malformedTokenCount(evidenceAt: Date)
        case noTokenCount
    }

    private func latestSessionUsage() async -> SessionReadResult {
        let rootPath = sessionsPath
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/sessions")
                .path

        return await Task.detached {
            Self.readLatestSessionUsage(at: rootPath)
        }.value
    }

    private static func readLatestSessionUsage(at rootPath: String) -> SessionReadResult {
        diagnosticLog("sessions root: \(rootPath)")
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return .noData
        }

        var files: [(url: URL, modifiedAt: Date)] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard
                let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                values.isRegularFile == true
            else { continue }
            files.append((fileURL, values.contentModificationDate ?? .distantPast))
        }

        diagnosticLog("session files found: \(files.count)")
        var latestSnapshot: (snapshot: UsageSnapshot, eventDate: Date)?
        var latestDriftEvidence: Date?
        for file in files.sorted(by: { $0.modifiedAt > $1.modifiedAt }).prefix(20) {
            switch latestRateLimits(in: file.url) {
            case .success(let snapshot, let eventDate):
                if latestSnapshot == nil || eventDate > latestSnapshot!.eventDate {
                    latestSnapshot = (snapshot, eventDate)
                }
            case .malformedTokenCount(let evidenceAt):
                let isFresh = Date().timeIntervalSince(file.modifiedAt) <= 10 * 60
                if isFresh, latestDriftEvidence == nil || evidenceAt > latestDriftEvidence! {
                    latestDriftEvidence = evidenceAt
                }
            case .noTokenCount:
                diagnosticLog("no rate limits in: \(file.url.lastPathComponent)")
            }
        }

        if let latestDriftEvidence,
           latestSnapshot == nil || latestDriftEvidence > latestSnapshot!.eventDate {
            diagnosticLog("session schema drift suspected at: \(latestDriftEvidence)")
            return .driftSuspected(evidenceAt: latestDriftEvidence)
        }
        if let latestSnapshot {
            diagnosticLog("selected realtime usage: \(latestSnapshot.snapshot.menuBarText)")
            return .success(latestSnapshot.snapshot)
        }
        return .noData
    }

    private static func latestRateLimits(in fileURL: URL) -> SessionFileReadResult {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
            let fileSize = (attributes[.size] as? NSNumber)?.uint64Value,
            let handle = try? FileHandle(forReadingFrom: fileURL)
        else {
            return .noTokenCount
        }
        defer { try? handle.close() }

        let maximumBytes: UInt64 = 8 * 1_024 * 1_024
        let offset = fileSize > maximumBytes ? fileSize - maximumBytes : 0
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            var text = String(decoding: data, as: UTF8.self)
            if offset > 0, let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }

            for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
                guard
                    let lineData = String(line).data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                    let payload = object["payload"] as? [String: Any],
                    payload["type"] as? String == "token_count"
                else { continue }

                let eventDate = eventDate(from: object["timestamp"] as? String)
                    ?? (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? Date()
                guard let rateLimits = payload["rate_limits"] as? [String: Any] else {
                    return .malformedTokenCount(evidenceAt: eventDate)
                }

                let windows = ["primary", "secondary"].compactMap { key -> UsageWindow? in
                    guard
                        let value = rateLimits[key] as? [String: Any],
                        let usedPercent = (value["used_percent"] as? NSNumber)?.doubleValue,
                        let minutes = (value["window_minutes"] as? NSNumber)?.intValue,
                        minutes > 0
                    else { return nil }

                    let resetAt = (value["resets_at"] as? NSNumber).map {
                        Date(timeIntervalSince1970: $0.doubleValue)
                    }
                    return UsageWindow(
                        minutes: minutes,
                        remainingPercent: min(100, max(0, 100 - Int(usedPercent.rounded()))),
                        resetAt: resetAt
                    )
                }

                let shortWindow = windows
                    .filter { $0.minutes < 10_080 }
                    .min { $0.minutes < $1.minutes }
                let weekWindow = windows
                    .filter { $0.minutes >= 10_080 }
                    .max { $0.minutes < $1.minutes }
                guard shortWindow != nil || weekWindow != nil else {
                    return .malformedTokenCount(evidenceAt: eventDate)
                }

                let planType = rateLimits["plan_type"] as? String
                let credits: CreditsInfo? = (rateLimits["credits"] as? [String: Any]).map { dict in
                    CreditsInfo(
                        hasCredits: (dict["has_credits"] as? Bool) ?? false,
                        unlimited: (dict["unlimited"] as? Bool) ?? false,
                        balance: (dict["balance"] as? String)
                            ?? (dict["balance"] as? NSNumber).map { "\($0)" }
                    )
                }

                return .success(
                    snapshot: UsageSnapshot(
                        shortWindow: shortWindow,
                        weekWindow: weekWindow,
                        updatedAt: eventDate,
                        source: .sessionEvent,
                        planType: planType,
                        credits: credits
                    ),
                    eventDate: eventDate
                )
            }
        } catch {
            return .noTokenCount
        }
        return .noTokenCount
    }

    private static func eventDate(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func diagnosticLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["CODEX_USAGE_DEBUG"] == "1" else { return }
        fputs("CodexUsage: \(message)\n", stderr)
    }

    private func latestUsageLogSnapshot() async throws -> UsageSnapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = databasePath ?? "\(home)/.codex/logs_2.sqlite"

        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw UsageProviderError.dataSourceUnavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = [
            "-separator",
            "\u{1F}",
            "-readonly",
            dbPath,
            """
            select ts, feedback_log_body
            from logs
            where target = 'codex_http_client::default_client'
              and feedback_log_body like '%x-codex-primary-used-percent%'
            order by ts desc, ts_nanos desc, id desc
            limit 1;
            """
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let entry: (timestamp: TimeInterval, body: String) = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: output, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errorText = String(data: errorOutput, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let parts = result.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
                if process.terminationStatus == 0,
                   parts.count == 2,
                   let timestamp = TimeInterval(parts[0]) {
                    continuation.resume(returning: (timestamp, String(parts[1])))
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

        return try parseUsage(
            from: entry.body,
            updatedAt: Date(timeIntervalSince1970: entry.timestamp)
        )
    }

    private func parseUsage(from body: String, updatedAt: Date) throws -> UsageSnapshot {
        let windows = [
            usageWindow(prefix: "primary", defaultMinutes: 300, in: body),
            usageWindow(prefix: "secondary", defaultMinutes: 10_080, in: body)
        ].compactMap { $0 }

        let shortWindow = windows
            .filter { $0.minutes < 10_080 }
            .min { $0.minutes < $1.minutes }
        let weekWindow = windows
            .filter { $0.minutes >= 10_080 }
            .max { $0.minutes < $1.minutes }

        guard shortWindow != nil || weekWindow != nil else {
            throw UsageProviderError.unreadableUsage
        }

        return UsageSnapshot(
            shortWindow: shortWindow,
            weekWindow: weekWindow,
            updatedAt: updatedAt,
            source: .responseHeader,
            planType: nil,
            credits: nil
        )
    }

    private func usageWindow(prefix: String, defaultMinutes: Int, in body: String) -> UsageWindow? {
        guard let usedPercent = intHeader("x-codex-\(prefix)-used-percent", in: body) else {
            return nil
        }

        let minutes = intHeader("x-codex-\(prefix)-window-minutes", in: body) ?? defaultMinutes
        guard minutes > 0 else { return nil }

        return UsageWindow(
            minutes: minutes,
            remainingPercent: remainingPercent(fromUsedPercent: usedPercent),
            resetAt: resetDate(
                epochSeconds: intHeader("x-codex-\(prefix)-reset-at", in: body),
                fallbackAfterSeconds: intHeader("x-codex-\(prefix)-reset-after-seconds", in: body)
            )
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

    private func resetDate(epochSeconds: Int?, fallbackAfterSeconds: Int?) -> Date? {
        if let epochSeconds {
            return Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        }
        if let fallbackAfterSeconds {
            return Date().addingTimeInterval(TimeInterval(fallbackAfterSeconds))
        }
        return nil
    }

    private func debugLog(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        let url = URL(fileURLWithPath: "/tmp/CodexUsage.log")
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
