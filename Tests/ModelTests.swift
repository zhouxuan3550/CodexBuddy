import Foundation

@main
struct ModelTests {
    @MainActor
    static func main() async {
        let snapshot = UsageSnapshot(
            shortWindow: UsageWindow(minutes: 300, remainingPercent: 89, resetAt: nil),
            weekWindow: UsageWindow(minutes: 10_080, remainingPercent: 32, resetAt: nil),
            updatedAt: Date(timeIntervalSince1970: 0),
            source: .sessionEvent,
            planType: "plus",
            credits: CreditsInfo(hasCredits: true, unlimited: false, balance: "2500")
        )

        expect(snapshot.menuBarText == "H 89% W 32%", "menu bar percentage format")
        expect(snapshot.featuredWindow == snapshot.weekWindow, "summary features the most urgent window")
        expect(snapshot.weekWindow?.usedPercent == 68, "summary derives used percent from remaining percent")
        if let weekWindow = snapshot.weekWindow {
            expect(snapshot.menuPrefix(for: weekWindow) == "W", "weekly summary uses the W prefix")
        }
        if let shortWindow = snapshot.shortWindow {
            expect(
                snapshot.line(for: shortWindow, language: .simplifiedChinese).hasPrefix("5 小时 89%"),
                "Chinese short-window formatting"
            )
        } else {
            expect(false, "Chinese short-window formatting")
        }
        if let weekWindow = snapshot.weekWindow {
            expect(
                snapshot.line(for: weekWindow, language: .english).hasPrefix("1 week 32%"),
                "English week-window formatting"
            )
        } else {
            expect(false, "English week-window formatting")
        }
        expect(
            L10n.text(.refresh, language: .simplifiedChinese) == "刷新用量",
            "Chinese localization"
        )
        expect(
            L10n.text(.refresh, language: .english) == "Refresh Usage",
            "English localization"
        )
        expect(UsageColorLevel.classify(percent: 19) == .low, "under 20 percent is red")
        expect(UsageColorLevel.classify(percent: 20) == .normal, "20 percent stays normal")
        expect(UsageColorLevel.classify(percent: 80) == .normal, "80 percent stays normal")
        expect(UsageColorLevel.classify(percent: 81) == .high, "over 80 percent is green")
        expect(snapshot.source == .sessionEvent, "snapshot records its data source")
        expect(
            UpdateChecker.defaultRepository == "zhouxuan3550/CodexUsage",
            "update checks use the public release repository"
        )
        let compactSegments = snapshot.menuBarSegments(
            mode: .worst,
            showShortWindow: true,
            showWeekWindow: true
        )
        expect(compactSegments.count == 1, "compact mode shows one menu bar value")
        expect(compactSegments.first?.text == "W 32%", "compact mode keeps the urgent window prefix")
        expect(
            snapshot.source.localizedName(language: .simplifiedChinese) == "实时事件",
            "session source is localized"
        )
        expect(
            snapshot.source.localizedName(language: .english) == "Live event",
            "session source is localized in English"
        )
        expect(
            !snapshot.isStale(at: Date(timeIntervalSince1970: 1_799), maximumAge: 1_800),
            "fresh snapshots are not stale"
        )
        expect(
            snapshot.isStale(at: Date(timeIntervalSince1970: 1_801), maximumAge: 1_800),
            "old snapshots are stale"
        )
        expect(
            SingleInstanceCoordinator.otherProcessIDs(
                currentPID: 7,
                runningPIDs: [4, 7, 4, 9]
            ) == [4, 9],
            "single-instance coordinator excludes the current process"
        )

        await testUsageLogIgnoresNewerNonHTTPMatches()
        await testSessionRateLimitsTakePriorityOverOlderHeaders()
        await testNewestSessionEventWinsAcrossFiles()
        await testStandardSessionFixture()
        await testMalformedSessionReportsDiagnosticWhileUsingHeaderFallback()
        await testSingleMalformedSessionWithoutFallbackStaysProvisional()
        await testSchemaDriftRequiresTwoDistinctEvents()
        testMenuBarModeDefaultsToDual()
        testHistoryDoesNotRepeatSameEvent()
        testRunwayUsesRecentConsumptionRate()
        testRunwayRequiresDistinctEventTimes()
        testDepletionEstimateIgnoresPreviousResetCycle()
        testFileMonitorDetectsAppend()

        print("Model tests passed")
    }

    private static func testUsageLogIgnoresNewerNonHTTPMatches() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageTests-\(UUID().uuidString)")
        let databaseURL = directory.appendingPathComponent("logs.sqlite")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            try runSQLite(
                databasePath: databaseURL.path,
                sql: """
                create table logs (
                    id integer primary key,
                    ts integer not null,
                    ts_nanos integer not null,
                    level text not null,
                    target text not null,
                    feedback_log_body text,
                    module_path text,
                    file text,
                    line integer,
                    thread_id text,
                    process_uuid text,
                    estimated_bytes integer not null default 0
                );
                insert into logs (id, ts, ts_nanos, level, target, feedback_log_body)
                values (
                    1, 100, 0, 'INFO', 'codex_http_client::default_client',
                    '{"x-codex-primary-used-percent":"65","x-codex-primary-window-minutes":"10080","x-codex-primary-reset-at":"2000000000","x-codex-secondary-used-percent":"0","x-codex-secondary-window-minutes":"0"}'
                );
                insert into logs (id, ts, ts_nanos, level, target, feedback_log_body)
                values (
                    2, 200, 0, 'INFO', 'codex_core::stream_events_utils',
                    'query text mentions x-codex-primary-used-percent but contains no header value'
                );
                """
            )

            let snapshot = try await CodexUsageProvider(
                databasePath: databaseURL.path,
                sessionsPath: directory.appendingPathComponent("empty-sessions").path
            ).fetchUsage()
            expect(snapshot.menuBarText == "W 35%", "latest non-HTTP log entries are ignored")
            expect(snapshot.shortWindow == nil, "zero-minute windows are ignored")
            expect(snapshot.weekWindow?.remainingPercent == 35, "window roles follow their reported duration")
            expect(snapshot.source == .responseHeader, "fallback snapshots report the response-header source")
            expect(snapshot.updatedAt == Date(timeIntervalSince1970: 100), "fallback snapshots preserve log time")
        } catch {
            expect(false, "latest non-HTTP log entries are ignored")
        }
    }

    private static func runSQLite(databasePath: String, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databasePath, sql]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UsageProviderError.unreadableUsage
        }
    }

    private static func testSessionRateLimitsTakePriorityOverOlderHeaders() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageSessionTests-\(UUID().uuidString)")
        let databaseURL = directory.appendingPathComponent("logs.sqlite")
        let sessionsURL = directory.appendingPathComponent("sessions")
        let rolloutURL = sessionsURL.appendingPathComponent("rollout.jsonl")

        do {
            try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            try runSQLite(
                databasePath: databaseURL.path,
                sql: """
                create table logs (
                    id integer primary key,
                    ts integer not null,
                    ts_nanos integer not null,
                    level text not null,
                    target text not null,
                    feedback_log_body text,
                    estimated_bytes integer not null default 0
                );
                insert into logs (id, ts, ts_nanos, level, target, feedback_log_body)
                values (
                    1, 100, 0, 'INFO', 'codex_http_client::default_client',
                    '{"x-codex-primary-used-percent":"65","x-codex-primary-window-minutes":"10080","x-codex-primary-reset-at":"2000000000"}'
                );
                """
            )

            let sessionLine = """
            {"timestamp":"2026-07-21T08:07:45.246Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":74.0,"window_minutes":10080,"resets_at":1784957683},"secondary":null}}}
            """
            try sessionLine.write(to: rolloutURL, atomically: true, encoding: .utf8)

            let provider = CodexUsageProvider(
                databasePath: databaseURL.path,
                sessionsPath: sessionsURL.path
            )
            let snapshot = try await provider.fetchUsage()
            expect(snapshot.menuBarText == "W 26%", "session rate limits take priority over older headers")
            expect(snapshot.source == .sessionEvent, "realtime snapshots report the session-event source")

            let newerSessionLine = """
            {"timestamp":"2026-07-21T08:08:45.246Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":75.0,"window_minutes":10080,"resets_at":1784957683},"secondary":null}}}
            """
            let handle = try FileHandle(forWritingTo: rolloutURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n\(newerSessionLine)".utf8))
            try handle.close()

            let refreshedSnapshot = try await provider.fetchUsage()
            expect(refreshedSnapshot.menuBarText == "W 25%", "new session rate limits are picked up on refresh")
        } catch {
            expect(false, "session rate limits take priority over older headers")
        }
    }

    private static func testMalformedSessionReportsDiagnosticWhileUsingHeaderFallback() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageDriftTests-\(UUID().uuidString)")
        let databaseURL = directory.appendingPathComponent("logs.sqlite")
        let sessionsURL = directory.appendingPathComponent("sessions")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/session-malformed-rate-limits.jsonl")
        let rolloutURL = sessionsURL.appendingPathComponent("rollout.jsonl")

        do {
            try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.copyItem(at: fixtureURL, to: rolloutURL)
            try FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: rolloutURL.path
            )
            try runSQLite(
                databasePath: databaseURL.path,
                sql: """
                create table logs (
                    id integer primary key,
                    ts integer not null,
                    ts_nanos integer not null,
                    level text not null,
                    target text not null,
                    feedback_log_body text,
                    estimated_bytes integer not null default 0
                );
                insert into logs (id, ts, ts_nanos, level, target, feedback_log_body)
                values (
                    1, 100, 0, 'INFO', 'codex_http_client::default_client',
                    '{"x-codex-primary-used-percent":"65","x-codex-primary-window-minutes":"10080","x-codex-primary-reset-at":"2000000000"}'
                );
                """
            )

            let result = try await CodexUsageProvider(
                databasePath: databaseURL.path,
                sessionsPath: sessionsURL.path
            ).fetchUsageResult()
            expect(result.snapshot.menuBarText == "W 35%", "malformed sessions keep header fallback data")
            expect(result.diagnostic != nil, "malformed sessions report an independent diagnostic")
        } catch {
            expect(false, "malformed sessions report an independent diagnostic")
        }
    }

    private static func testStandardSessionFixture() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageFixtureTests-\(UUID().uuidString)")
        let sessionsURL = directory.appendingPathComponent("sessions")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/session-standard.jsonl")

        do {
            try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.copyItem(
                at: fixtureURL,
                to: sessionsURL.appendingPathComponent("rollout.jsonl")
            )

            let snapshot = try await CodexUsageProvider(
                databasePath: directory.appendingPathComponent("missing.sqlite").path,
                sessionsPath: sessionsURL.path
            ).fetchUsage()
            expect(snapshot.menuBarText == "H 60% W 30%", "standard session fixture parses both windows")
            expect(snapshot.planType == "plus", "standard session fixture parses the plan")
            expect(snapshot.credits?.displayBalance == "2500", "standard session fixture parses credits")
        } catch {
            expect(false, "standard session fixture parses")
        }
    }

    private static func testNewestSessionEventWinsAcrossFiles() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageMultiSessionTests-\(UUID().uuidString)")
        let sessionsURL = directory.appendingPathComponent("sessions")
        let newerFileURL = sessionsURL.appendingPathComponent("newer-file.jsonl")
        let newerEventURL = sessionsURL.appendingPathComponent("newer-event.jsonl")

        do {
            try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let olderEvent = """
            {"timestamp":"2026-07-22T05:00:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":70,"window_minutes":10080}}}}
            """
            let newerEvent = """
            {"timestamp":"2026-07-22T05:05:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":80,"window_minutes":10080}}}}
            """
            try olderEvent.write(to: newerFileURL, atomically: true, encoding: .utf8)
            try newerEvent.write(to: newerEventURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: newerFileURL.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-60)],
                ofItemAtPath: newerEventURL.path
            )

            let snapshot = try await CodexUsageProvider(
                databasePath: directory.appendingPathComponent("missing.sqlite").path,
                sessionsPath: sessionsURL.path
            ).fetchUsage()
            expect(snapshot.menuBarText == "W 20%", "newest event wins across session files")
        } catch {
            expect(false, "newest event wins across session files")
        }
    }

    @MainActor
    private static func testSchemaDriftRequiresTwoDistinctEvents() async {
        let snapshot = UsageSnapshot(
            shortWindow: nil,
            weekWindow: UsageWindow(minutes: 10_080, remainingPercent: 35, resetAt: nil),
            updatedAt: Date(timeIntervalSince1970: 100),
            source: .responseHeader,
            planType: nil,
            credits: nil
        )
        let firstEvidence = Date(timeIntervalSince1970: 200)
        let secondEvidence = Date(timeIntervalSince1970: 201)
        let provider = SequencedDiagnosticProvider(results: [
            UsageFetchResult(snapshot: snapshot, diagnostic: .sessionSchemaDrift(evidenceAt: firstEvidence)),
            UsageFetchResult(snapshot: snapshot, diagnostic: .sessionSchemaDrift(evidenceAt: firstEvidence)),
            UsageFetchResult(snapshot: snapshot, diagnostic: .sessionSchemaDrift(evidenceAt: secondEvidence))
        ])
        let store = UsageStore(provider: provider)

        await store.refresh()
        expect(store.providerError == nil, "one schema drift event stays provisional")
        await store.refresh()
        expect(store.providerError == nil, "re-reading the same drift event does not escalate")
        await store.refresh()
        expect(store.providerError == .schemaDrift, "two distinct schema drift events show a warning")
    }

    @MainActor
    private static func testSingleMalformedSessionWithoutFallbackStaysProvisional() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageNoFallbackDriftTests-\(UUID().uuidString)")
        let sessionsURL = directory.appendingPathComponent("sessions")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/session-malformed-rate-limits.jsonl")
        let rolloutURL = sessionsURL.appendingPathComponent("rollout.jsonl")

        do {
            try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.copyItem(at: fixtureURL, to: rolloutURL)
            try FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: rolloutURL.path
            )

            let store = UsageStore(provider: CodexUsageProvider(
                databasePath: directory.appendingPathComponent("missing.sqlite").path,
                sessionsPath: sessionsURL.path
            ))
            await store.refresh()
            expect(store.providerError == .unreadableUsage, "one drift event without fallback stays provisional")
        } catch {
            expect(false, "one drift event without fallback stays provisional")
        }
    }

    private static func testFileMonitorDetectsAppend() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageMonitorTests-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("rollout.jsonl")
        let signal = DispatchSemaphore(value: 0)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try "initial\n".write(to: fileURL, atomically: true, encoding: .utf8)

            let monitor = UsageFileMonitor(paths: [directory.path], latency: 0.05) {
                signal.signal()
            }
            expect(monitor.start(), "file monitor starts")
            defer { monitor.stop() }

            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("update\n".utf8))
            try handle.close()

            expect(
                signal.wait(timeout: .now() + 3) == .success,
                "file monitor detects session appends"
            )
        } catch {
            expect(false, "file monitor detects session appends")
        }
    }

    @MainActor
    private static func testMenuBarModeDefaultsToDual() {
        let suiteName = "CodexUsageSettingsTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            expect(false, "menu bar mode defaults to dual")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        expect(settings.menuBarMode == .dual, "menu bar mode defaults to dual")
    }

    @MainActor
    private static func testHistoryDoesNotRepeatSameEvent() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageHistoryTests-\(UUID().uuidString)")
        var now = Date(timeIntervalSince1970: 1_000)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = UsageHistoryStore(directory: directory, now: { now })
            let snapshot = UsageSnapshot(
                shortWindow: nil,
                weekWindow: UsageWindow(minutes: 10_080, remainingPercent: 42, resetAt: nil),
                updatedAt: Date(timeIntervalSince1970: 900),
                source: .sessionEvent,
                planType: "plus",
                credits: nil
            )

            store.record(snapshot: snapshot)
            now = now.addingTimeInterval(61)
            store.record(snapshot: snapshot)

            expect(store.records.count == 1, "history stores the same event only once")
        } catch {
            expect(false, "history stores the same event only once")
        }
    }

    @MainActor
    private static func testRunwayUsesRecentConsumptionRate() {
        let base = Date(timeIntervalSince1970: 10_000)
        let records = [
            UsageHistoryStore.Record(
                timestamp: base,
                shortRemaining: 60,
                weekRemaining: nil,
                planType: nil,
                creditsBalance: nil
            ),
            UsageHistoryStore.Record(
                timestamp: base.addingTimeInterval(5 * 60),
                shortRemaining: 50,
                weekRemaining: nil,
                planType: nil,
                creditsBalance: nil
            ),
            UsageHistoryStore.Record(
                timestamp: base.addingTimeInterval(10 * 60),
                shortRemaining: 40,
                weekRemaining: nil,
                planType: nil,
                creditsBalance: nil
            )
        ]

        let runway = DepletionEstimator.runwayMinutes(
            records: records,
            windowType: .short,
            currentRemaining: 40,
            now: base.addingTimeInterval(10 * 60)
        )
        expect(runway == 20, "runway follows the recent consumption rate")
    }

    @MainActor
    private static func testRunwayRequiresDistinctEventTimes() {
        let base = Date(timeIntervalSince1970: 20_000)
        let repeated = UsageHistoryStore.Record(
            timestamp: base,
            shortRemaining: 60,
            weekRemaining: nil,
            planType: nil,
            creditsBalance: nil
        )
        let records = [
            repeated,
            repeated,
            repeated,
            UsageHistoryStore.Record(
                timestamp: base.addingTimeInterval(10 * 60),
                shortRemaining: 40,
                weekRemaining: nil,
                planType: nil,
                creditsBalance: nil
            )
        ]

        let runway = DepletionEstimator.runwayMinutes(
            records: records,
            windowType: .short,
            currentRemaining: 40,
            now: base.addingTimeInterval(10 * 60)
        )
        expect(runway == nil, "runway requires three distinct event times")
    }

    @MainActor
    private static func testDepletionEstimateIgnoresPreviousResetCycle() {
        let base = Date(timeIntervalSince1970: 30_000)
        let values: [(minutes: Double, remaining: Int)] = [
            (0, 5),
            (1, 100),
            (6, 90),
            (11, 80)
        ]
        let records = values.map { value in
            UsageHistoryStore.Record(
                timestamp: base.addingTimeInterval(value.minutes * 60),
                shortRemaining: value.remaining,
                weekRemaining: nil,
                planType: nil,
                creditsBalance: nil
            )
        }
        let now = base.addingTimeInterval(11 * 60)

        let estimate = DepletionEstimator.estimate(
            records: records,
            windowType: .short,
            currentRemaining: 80,
            now: now
        )
        expect(
            abs(estimate.ratePerHour - 120) < 0.001,
            "depletion estimate ignores the previous reset cycle"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            fputs("Test failed: \(name)\n", stderr)
            exit(1)
        }
    }
}

private final class SequencedDiagnosticProvider: UsageProvider {
    private let results: [UsageFetchResult]
    private var index = 0

    init(results: [UsageFetchResult]) {
        self.results = results
    }

    func fetchUsage() async throws -> UsageSnapshot {
        try await fetchUsageResult().snapshot
    }

    func fetchUsageResult() async throws -> UsageFetchResult {
        let result = results[min(index, results.count - 1)]
        index += 1
        return result
    }
}
