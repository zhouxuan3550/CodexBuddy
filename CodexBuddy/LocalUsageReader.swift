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
        let signal = sessionScan.formatEvidence.map {
            UsageHealthSignal.sessionFormatChanged(evidenceAt: $0)
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
            where target = 'codex_http_client::default_client'
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
    }

    private enum SessionFileResult {
        case reading(UsageReading)
        case malformed(Date)
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
                return .reading(UsageReading(
                    shortWindow: short,
                    weekWindow: week,
                    updatedAt: eventDate,
                    source: .sessionLog,
                    planName: limits["plan_type"] as? String,
                    credits: creditState
                ))
            }
        } catch {
            return .noRelevantEvent
        }
        return .noRelevantEvent
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
        guard let used = headerInteger("x-codex-\(name)-used-percent", body: body) else {
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
            remainingPercent: min(100, max(0, 100 - used)),
            resetAt: resetAt
        )
    }

    private static func headerInteger(_ name: String, body: String) -> Int? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\"\(escaped)\"\\s*:\\s*\"?([0-9]+)\"?"
        guard
            let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = expression.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
            let valueRange = Range(match.range(at: 1), in: body)
        else { return nil }
        return Int(body[valueRange])
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
