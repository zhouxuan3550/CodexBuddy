import Foundation

@main
struct CoreTests {
    @MainActor
    static func main() async {
        testCodexBuddyIdentity()
        testOfficialUsageMenu()
        testArchitectureSpecificUpdateAssets()
        testLaunchAtLoginStatusIsExplicit()
        testDomainFormattingAndThresholds()
        testSettingsMigrationAndDefaults()
        await testSessionFixture()
        await testResponseHeaderFallback()
        await testNewestSessionEventWins()
        await testMalformedSessionReportsHealthSignal()
        await testViewModelDebouncesFormatWarnings()
        testHistoryDeduplicatesEvents()
        testDepletionEstimate()
        testSessionMonitorDetectsAppend()
        print("Core tests passed")
    }

    private static func testCodexBuddyIdentity() {
        expect(ProductIdentity.name == "CodexBuddy", "product name is CodexBuddy")
        expect(ProductIdentity.repository == "zhouxuan3550/CodexBuddy", "updates use the CodexBuddy repository")
        expect(ProductIdentity.bundleIdentifier == "com.zhouxuan3550.codexbuddy", "bundle identifier uses CodexBuddy")
    }

    private static func testOfficialUsageMenu() {
        expect(
            L10n.text(.openOfficialUsage, language: .simplifiedChinese) == "官方 Usage",
            "Chinese official Usage menu title is concise"
        )
        expect(
            L10n.text(.openOfficialUsage, language: .english) == "Official Usage",
            "English official Usage menu title is concise"
        )
        expect(
            ProductIdentity.officialUsageURL.absoluteString == "https://chatgpt.com/codex/settings/usage",
            "official Usage menu opens the current OpenAI Usage page"
        )
    }

    private static func testArchitectureSpecificUpdateAssets() {
        let names = [
            "CodexBuddy-v0.7.2-arm64.dmg",
            "CodexBuddy-v0.7.2-arm64.zip",
            "CodexBuddy-v0.7.2-arm64.zip.sha256",
            "CodexBuddy-v0.7.2-x86_64.dmg",
            "CodexBuddy-v0.7.2-x86_64.zip",
            "CodexBuddy-v0.7.2-x86_64.zip.sha256"
        ]
        expect(
            UpdateChecker.preferredAssetName(in: names, architecture: "arm64", suffix: ".zip")
                == "CodexBuddy-v0.7.2-arm64.zip",
            "Apple Silicon updates select the arm64 ZIP"
        )
        expect(
            UpdateChecker.preferredAssetName(in: names, architecture: "x86_64", suffix: ".zip")
                == "CodexBuddy-v0.7.2-x86_64.zip",
            "Intel updates select the x86_64 ZIP"
        )
        expect(
            UpdateChecker.preferredAssetName(in: names, architecture: "x86_64", suffix: ".zip.sha256")
                == "CodexBuddy-v0.7.2-x86_64.zip.sha256",
            "update checksum matches the selected architecture"
        )
    }

    private static func testLaunchAtLoginStatusIsExplicit() {
        expect(
            L10n.launchAtLoginTitle(isEnabled: true, language: .simplifiedChinese) == "登录时启动 · 已开启",
            "Chinese launch-at-login title shows enabled state"
        )
        expect(
            L10n.launchAtLoginTitle(isEnabled: false, language: .simplifiedChinese) == "登录时启动 · 已关闭",
            "Chinese launch-at-login title shows disabled state"
        )
        expect(
            L10n.launchAtLoginTitle(isEnabled: true, language: .english) == "Launch at Login · On",
            "English launch-at-login title shows enabled state"
        )
        expect(
            L10n.launchAtLoginTitle(isEnabled: false, language: .english) == "Launch at Login · Off",
            "English launch-at-login title shows disabled state"
        )
    }

    private static func testDomainFormattingAndThresholds() {
        let reading = UsageReading(
            shortWindow: QuotaWindow(minutes: 300, remainingPercent: 72, resetAt: nil),
            weekWindow: QuotaWindow(minutes: 10_080, remainingPercent: 21, resetAt: nil),
            updatedAt: Date(timeIntervalSince1970: 0),
            source: .sessionLog,
            planName: "plus",
            credits: CreditState(isAvailable: true, isUnlimited: false, balance: "2500")
        )
        expect(reading.completeStatusText == "H 72% W 21%", "status text includes both windows")
        expect(
            reading.menuBarSegments(mode: .tightest, showShortWindow: true, showWeekWindow: true)
                == [StatusSegment(text: "W 21%", percent: 21)],
            "compact status highlights the tightest window"
        )
        expect(reading.tightestWindow == reading.weekWindow, "summary highlights the tightest window")
        expect(reading.weekWindow?.consumedPercent == 79, "consumed percentage is derived")
        expect(reading.credits?.finiteBalance == "2500", "finite credits are displayed")
        expect(QuotaLevel.forRemaining(19) == .critical, "below 20 percent is critical")
        expect(QuotaLevel.forRemaining(20) == .standard, "20 percent remains standard")
        expect(QuotaLevel.forRemaining(60) == .standard, "60 percent remains standard")
        expect(QuotaLevel.forRemaining(61) == .healthy, "above 60 percent is healthy")
        expect(reading.source.displayName(language: .english) == "Live event", "source name is localized")
        expect(UpdateChecker.defaultRepository == ProductIdentity.repository, "updates use the public repository")
        expect(
            reading.isOutdated(at: Date(timeIntervalSince1970: 1_801), maximumAge: 1_800),
            "old readings without reset dates are marked outdated"
        )
        expect(
            SingleInstanceCoordinator.otherProcessIDs(currentPID: 7, runningPIDs: [4, 7, 4, 9]) == [4, 9],
            "single-instance filtering excludes the current process"
        )
    }

    @MainActor
    private static func testSettingsMigrationAndDefaults() {
        let suite = "CodexBuddyV07Settings-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            expect(false, "settings suite is available")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(AppSettings(defaults: defaults).menuBarMode == .allWindows, "display defaults to both windows")
        defaults.set("worst", forKey: "menuBarMode")
        expect(AppSettings(defaults: defaults).menuBarMode == .tightest, "legacy compact setting migrates")
    }

    private static func testSessionFixture() async {
        let sandbox = temporaryDirectory("Session")
        let sessions = sandbox.appendingPathComponent("sessions")
        do {
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sandbox) }
            try FileManager.default.copyItem(
                at: fixture("session-standard.jsonl"),
                to: sessions.appendingPathComponent("rollout.jsonl")
            )
            let reading = try await LocalUsageReader(
                databaseURL: sandbox.appendingPathComponent("missing.sqlite"),
                sessionsURL: sessions
            ).readReading()
            expect(reading.completeStatusText == "H 60% W 30%", "session fixture parses both windows")
            expect(reading.planName == "plus", "session fixture parses the plan")
            expect(reading.credits?.finiteBalance == "2500", "session fixture parses credits")
        } catch {
            expect(false, "session fixture parses")
        }
    }

    private static func testResponseHeaderFallback() async {
        let sandbox = temporaryDirectory("Headers")
        let database = sandbox.appendingPathComponent("logs.sqlite")
        do {
            try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sandbox) }
            try makeLogDatabase(
                at: database,
                timestamp: 100,
                body: #"{"x-codex-primary-used-percent":"74","x-codex-primary-window-minutes":"10080","x-codex-primary-reset-at":"2000000000"}"#
            )
            let reading = try await LocalUsageReader(
                databaseURL: database,
                sessionsURL: sandbox.appendingPathComponent("empty")
            ).readReading()
            expect(reading.completeStatusText == "W 26%", "response headers provide fallback usage")
            expect(reading.source == .responseHeaders, "fallback source is recorded")
            expect(reading.updatedAt == Date(timeIntervalSince1970: 100), "fallback keeps its event time")
        } catch {
            expect(false, "response header fallback parses")
        }
    }

    private static func testNewestSessionEventWins() async {
        let sandbox = temporaryDirectory("Newest")
        let sessions = sandbox.appendingPathComponent("sessions")
        do {
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sandbox) }
            let older = #"{"timestamp":"2026-07-22T05:00:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":70,"window_minutes":10080}}}}"#
            let newer = #"{"timestamp":"2026-07-22T05:05:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":80,"window_minutes":10080}}}}"#
            let first = sessions.appendingPathComponent("recent-file.jsonl")
            let second = sessions.appendingPathComponent("recent-event.jsonl")
            try older.write(to: first, atomically: true, encoding: .utf8)
            try newer.write(to: second, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: first.path)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-60)],
                ofItemAtPath: second.path
            )
            let reading = try await LocalUsageReader(
                databaseURL: sandbox.appendingPathComponent("missing.sqlite"),
                sessionsURL: sessions
            ).readReading()
            expect(reading.completeStatusText == "W 20%", "newest event wins across session files")
        } catch {
            expect(false, "newest session event is selected")
        }
    }

    private static func testMalformedSessionReportsHealthSignal() async {
        let sandbox = temporaryDirectory("Format")
        let sessions = sandbox.appendingPathComponent("sessions")
        let database = sandbox.appendingPathComponent("logs.sqlite")
        do {
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sandbox) }
            let rollout = sessions.appendingPathComponent("rollout.jsonl")
            try FileManager.default.copyItem(at: fixture("session-malformed-rate-limits.jsonl"), to: rollout)
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: rollout.path)
            try makeLogDatabase(
                at: database,
                timestamp: 100,
                body: #"{"x-codex-primary-used-percent":"65","x-codex-primary-window-minutes":"10080"}"#
            )
            let outcome = try await LocalUsageReader(databaseURL: database, sessionsURL: sessions).read()
            expect(outcome.reading.completeStatusText == "W 35%", "malformed session keeps fallback data")
            expect(outcome.healthSignal != nil, "malformed session reports a health signal")
        } catch {
            expect(false, "malformed session is diagnosed independently")
        }
    }

    @MainActor
    private static func testViewModelDebouncesFormatWarnings() async {
        let reading = UsageReading(
            shortWindow: nil,
            weekWindow: QuotaWindow(minutes: 10_080, remainingPercent: 35, resetAt: nil),
            updatedAt: Date(timeIntervalSince1970: 100),
            source: .responseHeaders,
            planName: nil,
            credits: nil
        )
        let first = Date(timeIntervalSince1970: 200)
        let second = Date(timeIntervalSince1970: 201)
        let source = SequenceSource([
            UsageReadOutcome(reading: reading, healthSignal: .sessionFormatChanged(evidenceAt: first)),
            UsageReadOutcome(reading: reading, healthSignal: .sessionFormatChanged(evidenceAt: first)),
            UsageReadOutcome(reading: reading, healthSignal: .sessionFormatChanged(evidenceAt: second))
        ])
        let model = UsageViewModel(source: source)
        await model.reload()
        expect(model.issue == nil, "one format signal remains provisional")
        await model.reload()
        expect(model.issue == nil, "the same signal is not counted twice")
        await model.reload()
        expect(model.issue == .formatChanged, "two distinct signals show a warning")
    }

    @MainActor
    private static func testHistoryDeduplicatesEvents() {
        let sandbox = temporaryDirectory("History")
        var now = Date(timeIntervalSince1970: 1_000)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let history = UsageHistoryStore(directory: sandbox, now: { now })
        let reading = UsageReading(
            shortWindow: nil,
            weekWindow: QuotaWindow(minutes: 10_080, remainingPercent: 42, resetAt: nil),
            updatedAt: Date(timeIntervalSince1970: 900),
            source: .sessionLog,
            planName: "plus",
            credits: nil
        )
        history.record(reading: reading)
        now = now.addingTimeInterval(61)
        history.record(reading: reading)
        expect(history.records.count == 1, "history stores a source event once")
    }

    @MainActor
    private static func testDepletionEstimate() {
        let start = Date(timeIntervalSince1970: 10_000)
        let records = [60, 50, 40].enumerated().map { index, remaining in
            UsageHistoryStore.Record(
                timestamp: start.addingTimeInterval(TimeInterval(index * 300)),
                shortRemaining: remaining,
                weekRemaining: nil,
                planType: nil,
                creditsBalance: nil
            )
        }
        expect(
            DepletionEstimator.runwayMinutes(
                records: records,
                windowType: .short,
                currentRemaining: 40,
                now: start.addingTimeInterval(600)
            ) == 20,
            "depletion estimate follows recent consumption"
        )
    }

    private static func testSessionMonitorDetectsAppend() {
        let sandbox = temporaryDirectory("Monitor")
        let file = sandbox.appendingPathComponent("rollout.jsonl")
        let signal = DispatchSemaphore(value: 0)
        do {
            try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sandbox) }
            try "initial\n".write(to: file, atomically: true, encoding: .utf8)
            let monitor = UsageFileMonitor(paths: [sandbox.path], latency: 0.05) { signal.signal() }
            expect(monitor.start(), "session monitor starts")
            defer { monitor.stop() }
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("update\n".utf8))
            try handle.close()
            expect(signal.wait(timeout: .now() + 3) == .success, "session monitor detects appends")
        } catch {
            expect(false, "session monitor detects appends")
        }
    }

    private static func makeLogDatabase(at url: URL, timestamp: Int, body: String) throws {
        let escapedBody = body.replacingOccurrences(of: "'", with: "''")
        try runSQLite(url, sql: """
        create table logs (
            id integer primary key,
            ts integer not null,
            ts_nanos integer not null,
            level text not null,
            target text not null,
            feedback_log_body text
        );
        insert into logs (id, ts, ts_nanos, level, target, feedback_log_body)
        values (1, \(timestamp), 0, 'INFO', 'codex_http_client::default_client', '\(escapedBody)');
        """)
    }

    private static func runSQLite(_ url: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, sql]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UsageReadError.unreadable }
    }

    private static func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    private static func temporaryDirectory(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBuddyV07\(label)-\(UUID().uuidString)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            fputs("Test failed: \(name)\n", stderr)
            exit(1)
        }
    }
}

private final class SequenceSource: UsageReadingSource {
    private let outcomes: [UsageReadOutcome]
    private var index = 0

    init(_ outcomes: [UsageReadOutcome]) {
        self.outcomes = outcomes
    }

    func read() async throws -> UsageReadOutcome {
        let outcome = outcomes[min(index, outcomes.count - 1)]
        index += 1
        return outcome
    }
}
