import Foundation

struct LocalUsageReader: UsageReadingSource {
    private let databaseURL: URL
    private let sessionsURL: URL

    init(databaseURL: URL? = nil, sessionsURL: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.databaseURL = databaseURL ?? home.appendingPathComponent(".codex/logs_2.sqlite")
        self.sessionsURL = sessionsURL ?? home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    func read() async throws -> UsageReadOutcome {
        let root = sessionsURL
        let sessionScan = await Task.detached {
            Self.scanSessionDirectory(root)
        }.value
        let headerReading = try? await newestHeaderReading()
        guard let reading = [sessionScan.reading, headerReading]
            .compactMap({ $0 })
            .max(by: { $0.updatedAt < $1.updatedAt })
        else {
            if let evidence = sessionScan.formatEvidence {
                throw UsageReadError.formatChanged(evidence)
            }
            throw UsageReadError.unavailable
        }
        let signal: UsageHealthSignal?
        if let evidence = sessionScan.suspiciousRecoveryEvidence {
            signal = .suspiciousQuotaRecovery(evidenceAt: evidence)
        } else if let evidence = sessionScan.formatEvidence {
            signal = .sessionFormatChanged(evidenceAt: evidence)
        } else {
            signal = nil
        }
        return UsageReadOutcome(reading: reading, healthSignal: signal)
    }

    private func newestHeaderReading() async throws -> UsageReading {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw UsageReadError.unavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            "-json",
            databaseURL.path,
            """
            select ts, feedback_log_body
            from logs
            where target like 'codex_http_client%'
              and feedback_log_body like '%x-codex-primary-used-percent%'
            order by ts desc, ts_nanos desc, id desc
            limit 1;
            """
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: UsageReadError.unreadable)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: UsageReadError.unreadable)
            }
        }

        guard
            let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let row = rows.first,
            let timestamp = (row["ts"] as? NSNumber)?.doubleValue,
            let body = row["feedback_log_body"] as? String
        else { throw UsageReadError.unreadable }

        let windows = [
            Self.headerWindow(named: "primary", defaultMinutes: 300, body: body),
            Self.headerWindow(named: "secondary", defaultMinutes: 10_080, body: body)
        ].compactMap { $0 }
        let short = windows.filter { !$0.isWeekly }.min { $0.minutes < $1.minutes }
        let week = windows.filter(\.isWeekly).max { $0.minutes < $1.minutes }
        guard short != nil || week != nil else { throw UsageReadError.unreadable }

        return UsageReading(
            shortWindow: short,
            weekWindow: week,
            updatedAt: Date(timeIntervalSince1970: timestamp),
            source: .responseHeaders,
            planName: nil,
            credits: nil
        )
    }

    private struct SessionScan {
        var reading: UsageReading?
        var formatEvidence: Date?
        var suspiciousRecoveryEvidence: Date?
    }

    private enum SessionFileResult {
        case reading(UsageReading)
        case malformed(Date)
        case suspiciousRecovery(UsageReading, evidence: Date)
        case noRelevantEvent
    }

    private static func scanSessionDirectory(_ root: URL) -> SessionScan {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return SessionScan() }

        var candidates: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else {
                continue
            }
            candidates.append((url, values.contentModificationDate ?? .distantPast))
        }

        var scan = SessionScan()
        for candidate in candidates.sorted(by: { $0.modifiedAt > $1.modifiedAt }).prefix(20) {
            // Candidates are mtime-descending: once we hold a reading newer than the
            // next file's mtime, later files cannot contain a fresher event.
            if let reading = scan.reading, reading.updatedAt >= candidate.modifiedAt {
                break
            }
            switch latestEvent(in: candidate.url) {
            case .reading(let reading):
                if scan.reading == nil || reading.updatedAt > scan.reading!.updatedAt {
                    scan.reading = reading
                }
            case .malformed(let evidence):
                guard Date().timeIntervalSince(candidate.modifiedAt) <= 10 * 60 else { continue }
                if scan.formatEvidence == nil || evidence > scan.formatEvidence! {
                    scan.formatEvidence = evidence
                }
            case .suspiciousRecovery(let reading, let evidence):
                if scan.reading == nil || reading.updatedAt > scan.reading!.updatedAt {
                    scan.reading = reading
                }
                if scan.suspiciousRecoveryEvidence == nil || evidence > scan.suspiciousRecoveryEvidence! {
                    scan.suspiciousRecoveryEvidence = evidence
                }
            case .noRelevantEvent:
                break
            }
        }
        if let evidence = scan.formatEvidence,
           let reading = scan.reading,
           evidence <= reading.updatedAt {
            scan.formatEvidence = nil
        }
        return scan
    }

    private static func latestEvent(in file: URL) -> SessionFileResult {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return .noRelevantEvent }
        defer { try? handle.close() }

        do {
            let fileSize = try handle.seekToEnd()
            let tailLimit: UInt64 = 8 * 1_024 * 1_024
            let start = fileSize > tailLimit ? fileSize - tailLimit : 0
            try handle.seek(toOffset: start)
            var text = String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
            if start > 0, let newline = text.firstIndex(of: "\n") {
                text.removeSubrange(...newline)
            }

            var newestReading: UsageReading?
            for rawLine in text.split(separator: "\n").reversed() {
                guard
                    let data = String(rawLine).data(using: .utf8),
                    let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let payload = event["payload"] as? [String: Any],
                    payload["type"] as? String == "token_count"
                else { continue }

                let eventDate = parseTimestamp(event["timestamp"] as? String)
                    ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? Date()
                guard let limits = payload["rate_limits"] as? [String: Any] else {
                    return .malformed(eventDate)
                }

                let windows = ["primary", "secondary"].compactMap { key in
                    parseWindow(limits[key])
                }
                let short = windows.filter { !$0.isWeekly }.min { $0.minutes < $1.minutes }
                let week = windows.filter(\.isWeekly).max { $0.minutes < $1.minutes }
                guard short != nil || week != nil else { return .malformed(eventDate) }

                let creditState = (limits["credits"] as? [String: Any]).map { values in
                    CreditState(
                        isAvailable: values["has_credits"] as? Bool ?? false,
                        isUnlimited: values["unlimited"] as? Bool ?? false,
                        balance: values["balance"] as? String
                            ?? (values["balance"] as? NSNumber).map(String.init(describing:))
                    )
                }
                let reading = UsageReading(
                    shortWindow: short,
                    weekWindow: week,
                    updatedAt: eventDate,
                    source: .sessionLog,
                    planName: limits["plan_type"] as? String,
                    credits: creditState
                )

                guard let newerReading = newestReading else {
                    newestReading = reading
                    continue
                }
                if hasSuspiciousQuotaRecovery(newerReading, replacing: reading) {
                    return .suspiciousRecovery(reading, evidence: newerReading.updatedAt)
                }
                return .reading(newerReading)
            }
            if let newestReading { return .reading(newestReading) }
        } catch {
            return .noRelevantEvent
        }
        return .noRelevantEvent
    }

    /// Rate-limit events are occasionally emitted from a stale or different
    /// local session. A large increase before the previously advertised reset
    /// cannot be a normal quota reset, so it must not replace a trusted value.
    private static func hasSuspiciousQuotaRecovery(
        _ candidate: UsageReading,
        replacing previous: UsageReading
    ) -> Bool {
        let previousWindows = [previous.shortWindow, previous.weekWindow].compactMap { $0 }
        let candidateWindows = [candidate.shortWindow, candidate.weekWindow].compactMap { $0 }

        return candidateWindows.contains { candidateWindow in
            guard let previousWindow = previousWindows.first(where: { $0.isWeekly == candidateWindow.isWeekly }) else {
                return false
            }
            guard candidateWindow.remainingPercent - previousWindow.remainingPercent >= 15 else {
                return false
            }
            guard let previousReset = previousWindow.resetAt else {
                return false
            }
            return candidate.updatedAt.addingTimeInterval(60) < previousReset
        }
    }

    private static func parseWindow(_ rawValue: Any?) -> QuotaWindow? {
        guard
            let values = rawValue as? [String: Any],
            let used = (values["used_percent"] as? NSNumber)?.doubleValue,
            let minutes = (values["window_minutes"] as? NSNumber)?.intValue,
            minutes > 0
        else { return nil }

        let resetAt = (values["resets_at"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
        return QuotaWindow(
            minutes: minutes,
            remainingPercent: min(100, max(0, 100 - Int(used.rounded()))),
            resetAt: resetAt
        )
    }

    private static func headerWindow(named name: String, defaultMinutes: Int, body: String) -> QuotaWindow? {
        guard let used = headerDouble("x-codex-\(name)-used-percent", body: body) else {
            return nil
        }
        let minutes = headerInteger("x-codex-\(name)-window-minutes", body: body) ?? defaultMinutes
        guard minutes > 0 else { return nil }

        let resetAt: Date?
        if let epoch = headerInteger("x-codex-\(name)-reset-at", body: body) {
            resetAt = Date(timeIntervalSince1970: TimeInterval(epoch))
        } else if let delay = headerInteger("x-codex-\(name)-reset-after-seconds", body: body) {
            resetAt = Date().addingTimeInterval(TimeInterval(delay))
        } else {
            resetAt = nil
        }
        return QuotaWindow(
            minutes: minutes,
            remainingPercent: min(100, max(0, 100 - Int(used.rounded()))),
            resetAt: resetAt
        )
    }

    private static func headerInteger(_ name: String, body: String) -> Int? {
        headerDouble(name, body: body).map { Int($0) }
    }

    private static func headerDouble(_ name: String, body: String) -> Double? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\"\(escaped)\"\\s*:\\s*\"?([0-9]+(?:\\.[0-9]+)?)\"?"
        guard
            let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = expression.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
            let valueRange = Range(match.range(at: 1), in: body)
        else { return nil }
        return Double(body[valueRange])
    }

    // ISO8601DateFormatter is thread-safe; cache instances since creation is expensive
    // and parseTimestamp runs inside the per-line parsing loop.
    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainISOFormatter = ISO8601DateFormatter()

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalISOFormatter.date(from: value) ?? plainISOFormatter.date(from: value)
    }
}
