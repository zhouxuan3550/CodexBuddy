import Foundation

@main
struct CoreTests {
    @MainActor
    static func main() async {
        testCodexBuddyIdentity()
        testOfficialUsageMenu()
        testArchitectureSpecificUpdateAssets()
        testVersionComparison()
        testLaunchAtLoginStatusIsExplicit()
        testDomainFormattingAndThresholds()
        testUsageDataHealth()
        testSettingsMigrationAndDefaults()
        await testSessionFixture()
        await testResponseHeaderFallback()
        await testNewestSessionEventWins()
        await testSuspiciousSessionRecoveryIsRejected()
        await testMalformedSessionReportsHealthSignal()
        await testViewModelDebouncesFormatWarnings()
        testHistoryDeduplicatesEvents()
        testDepletionEstimate()
        testDepletionForecastGate()
        testWeeklyPacingPlan()
        testTaskReadiness()
        testSurplusGate()
        testWeeklyReportStats()
        testCompactTokenFormat()
        testDayBreakdownMerge()
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
            "CodexBuddy-v0.7.3-arm64.dmg",
            "CodexBuddy-v0.7.3-arm64.zip",
            "CodexBuddy-v0.7.3-arm64.zip.sha256",
            "CodexBuddy-v0.7.3-x86_64.dmg",
            "CodexBuddy-v0.7.3-x86_64.zip",
            "CodexBuddy-v0.7.3-x86_64.zip.sha256"
        ]
        expect(
            UpdateChecker.preferredAssetName(in: names, architecture: "arm64", suffix: ".zip")
                == "CodexBuddy-v0.7.3-arm64.zip",
            "Apple Silicon updates select the arm64 ZIP"
        )
        expect(
            UpdateChecker.preferredAssetName(in: names, architecture: "x86_64", suffix: ".zip")
                == "CodexBuddy-v0.7.3-x86_64.zip",
            "Intel updates select the x86_64 ZIP"
        )
        expect(
            UpdateChecker.preferredAssetName(in: names, architecture: "x86_64", suffix: ".zip.sha256")
                == "CodexBuddy-v0.7.3-x86_64.zip.sha256",
            "update checksum matches the selected architecture"
        )
    }

    private static func testVersionComparison() {
        expect(UpdateChecker.isNewer("0.8.0", than: "0.7.3"), "newer patch release is detected")
        expect(!UpdateChecker.isNewer("0.7.3", than: "0.7.3"), "identical versions are not upgrades")
        expect(!UpdateChecker.isNewer("0.7.2", than: "0.7.3"), "older versions are not upgrades")
        expect(UpdateChecker.isNewer("1.0", than: "0.9.9"), "shorter version strings compare by zero-padding")
        expect(!UpdateChecker.isNewer("0.8.0-beta.1", than: "0.8.0"), "a pre-release does not replace its release")
        expect(UpdateChecker.isNewer("0.8.0", than: "0.8.0-beta.1"), "a release upgrades from its pre-release")
        expect(UpdateChecker.isNewer("0.8.0-beta.2", than: "0.8.0-beta.1"), "newer pre-releases are detected")
        expect(UpdateChecker.isNewer("0.8.1-beta.1", than: "0.8.0"), "a pre-release of a later version is an upgrade")
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
        let weeklyOnlyReading = UsageReading(
            shortWindow: nil,
            weekWindow: QuotaWindow(minutes: 10_080, remainingPercent: 21, resetAt: nil),
            updatedAt: Date(timeIntervalSince1970: 0),
            source: .sessionLog,
            planName: "plus",
            credits: nil
        )
        expect(
            weeklyOnlyReading.menuBarSegments(
                mode: .allWindows,
                showShortWindow: true,
                showWeekWindow: true
            ) == [
                StatusSegment(text: "H --%", percent: nil),
                StatusSegment(text: "W 21%", percent: 21)
            ],
            "dual status preserves a missing short window as an explicit placeholder"
        )
        expect(reading.tightestWindow == reading.weekWindow, "summary highlights the tightest window")
        expect(reading.weekWindow?.consumedPercent == 79, "consumed percentage is derived")
        expect(reading.credits?.finiteBalance == "2500", "finite credits are displayed")
        expect(QuotaLevel.forRemaining(19) == .critical, "below 20 percent is critical")
        expect(QuotaLevel.forRemaining(20) == .standard, "20 percent remains standard")
        expect(QuotaLevel.forRemaining(60) == .standard, "60 percent remains standard")
        expect(QuotaLevel.forRemaining(61) == .healthy, "above 60 percent is healthy")
        expect(
            !UsageDetailFilter.shouldDisplay(tokens: 9_999_999),
            "detail cards hide incidental usage below ten million tokens"
        )
        expect(
            UsageDetailFilter.shouldDisplay(tokens: 10_000_000),
            "detail cards retain usage at ten million tokens"
        )
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

    private static func testUsageDataHealth() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let reading = UsageReading(
            shortWindow: nil,
            weekWindow: QuotaWindow(minutes: 10_080, remainingPercent: 55, resetAt: now.addingTimeInterval(86_400)),
            updatedAt: now,
            source: .sessionLog,
            planName: nil,
            credits: nil
        )
        expect(
            UsageDataHealth.snapshot(
                reading: reading,
                issue: nil,
                historySamples: 12,
                now: now
            ).state == .current,
            "fresh data is marked current"
        )
        expect(
            UsageDataHealth.snapshot(
                reading: reading,
                issue: .formatChanged,
                historySamples: 12,
                now: now
            ).state == .attention,
            "format warnings are surfaced as attention"
        )
        expect(
            UsageDataHealth.snapshot(
                reading: nil,
                issue: .unreadable,
                historySamples: 0,
                now: now
            ).state == .unavailable,
            "missing data stays unavailable instead of guessing"
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
        expect(!AppSettings(defaults: defaults).floatingWidgetEnabled, "floating widget defaults to off")
        expect(AppSettings(defaults: defaults).weeklyReservePercent == 0, "weekly reserve defaults to off")
        defaults.set("worst", forKey: "menuBarMode")
        expect(AppSettings(defaults: defaults).menuBarMode == .tightest, "legacy compact setting migrates")
        defaults.set(true, forKey: "floatingWidgetEnabled")
        expect(AppSettings(defaults: defaults).floatingWidgetEnabled, "floating widget preference persists")
        defaults.set(20, forKey: "weeklyReservePercent")
        expect(AppSettings(defaults: defaults).weeklyReservePercent == 20, "weekly reserve preference persists")
        defaults.set(15, forKey: "weeklyReservePercent")
        expect(AppSettings(defaults: defaults).weeklyReservePercent == 0, "invalid weekly reserve falls back safely")
        expect(
            L10n.floatingWidgetTitle(isEnabled: true, language: .simplifiedChinese) == "桌面悬浮窗 · 已开启",
            "floating widget setting has an explicit Chinese state"
        )
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
                body: #"{"x-codex-primary-used-percent":"74.5","x-codex-primary-window-minutes":"10080","x-codex-primary-reset-at":"2000000000"}"#,
                target: "codex_http_client::client"
            )
            let reading = try await LocalUsageReader(
                databaseURL: database,
                sessionsURL: sandbox.appendingPathComponent("empty")
            ).readReading()
            expect(reading.completeStatusText == "W 25%", "response headers provide fallback usage from the current client target")
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

    private static func testSuspiciousSessionRecoveryIsRejected() async {
        let sandbox = temporaryDirectory("Recovery")
        let sessions = sandbox.appendingPathComponent("sessions")
        do {
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sandbox) }
            let previous = #"{"timestamp":"2026-07-29T03:20:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":41,"window_minutes":10080,"resets_at":1785813194}}}}"#
            let inconsistent = #"{"timestamp":"2026-07-29T05:25:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":0,"window_minutes":10080,"resets_at":1785907474}}}}"#
            let rollout = sessions.appendingPathComponent("rollout.jsonl")
            try "\(previous)\n\(inconsistent)\n".write(to: rollout, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: rollout.path)
            let outcome = try await LocalUsageReader(
                databaseURL: sandbox.appendingPathComponent("missing.sqlite"),
                sessionsURL: sessions
            ).read()
            expect(outcome.reading.completeStatusText == "W 59%", "an early quota recovery retains the last consistent weekly value")
            if case .suspiciousQuotaRecovery = outcome.healthSignal {
                expect(true, "an early quota recovery is reported")
            } else {
                expect(false, "an early quota recovery is reported")
            }
        } catch {
            expect(false, "suspicious session recovery is rejected")
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

    @MainActor
    private static func testDepletionForecastGate() {
        let now = Date(timeIntervalSince1970: 20_000)
        let estimate = DepletionEstimator.Estimate(
            depletedAt: now.addingTimeInterval(30 * 60),
            ratePerHour: 12
        )
        expect(
            DepletionEstimator.forecastShouldFire(
                estimate: estimate,
                resetAt: now.addingTimeInterval(120 * 60),
                leadMinutes: 90,
                now: now
            ),
            "forecast fires when depletion lands before reset within lead"
        )
        expect(
            !DepletionEstimator.forecastShouldFire(
                estimate: estimate,
                resetAt: now.addingTimeInterval(10 * 60),
                leadMinutes: 90,
                now: now
            ),
            "forecast stays quiet when the reset arrives first"
        )
        expect(
            !DepletionEstimator.forecastShouldFire(
                estimate: estimate,
                resetAt: now.addingTimeInterval(120 * 60),
                leadMinutes: 15,
                now: now
            ),
            "forecast stays quiet outside the lead window"
        )
        expect(
            !DepletionEstimator.forecastShouldFire(
                estimate: DepletionEstimator.Estimate(depletedAt: nil, ratePerHour: 0),
                resetAt: now.addingTimeInterval(120 * 60),
                leadMinutes: 90,
                now: now
            ),
            "forecast requires an active depletion estimate"
        )
    }

    private static func testWeeklyPacingPlan() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetAt = now.addingTimeInterval(3.2 * 86_400)
        let weeklyWindow = QuotaWindow(
            minutes: 10_080,
            remainingPercent: 42,
            resetAt: resetAt
        )
        let plan = QuotaPacing.weeklyPlan(
            window: weeklyWindow,
            reservePercent: 20,
            now: now
        )
        expect(plan?.daysRemaining == 4, "weekly pace counts today as a planning day")
        expect(plan?.dailyAllowancePercent == 5, "weekly pace spreads non-reserved quota across days")
        expect(plan?.state == .tight, "weekly pace flags a plan below its expected line")

        let protected = QuotaPacing.weeklyPlan(
            window: QuotaWindow(minutes: 10_080, remainingPercent: 20, resetAt: resetAt),
            reservePercent: 20,
            now: now
        )
        expect(protected?.state == .protected, "weekly pace protects the selected safety reserve")
        expect(
            QuotaPacing.weeklyPlan(
                window: QuotaWindow(minutes: 300, remainingPercent: 80, resetAt: resetAt),
                reservePercent: 20,
                now: now
            ) == nil,
            "weekly pace ignores non-weekly quota windows"
        )
    }

    @MainActor
    private static func testTaskReadiness() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let resetAt = now.addingTimeInterval(4 * 86_400)
        let regularReading = UsageReading(
            shortWindow: nil,
            weekWindow: QuotaWindow(minutes: 10_080, remainingPercent: 76, resetAt: resetAt),
            updatedAt: now,
            source: .sessionLog,
            planName: nil,
            credits: nil
        )
        expect(
            TaskReadiness.report(
                reading: regularReading,
                reservePercent: 20,
                records: [],
                now: now
            ).verdict == .ready,
            "task check allows a healthy weekly quota"
        )

        let forecastRecords = [70, 55, 40].enumerated().map { index, remaining in
            UsageHistoryStore.Record(
                timestamp: now.addingTimeInterval(TimeInterval((index - 2) * 300)),
                shortRemaining: nil,
                weekRemaining: remaining,
                planType: nil,
                creditsBalance: nil
            )
        }
        let riskyReading = UsageReading(
            shortWindow: nil,
            weekWindow: QuotaWindow(minutes: 10_080, remainingPercent: 40, resetAt: resetAt),
            updatedAt: now,
            source: .sessionLog,
            planName: nil,
            credits: nil
        )
        let risky = TaskReadiness.report(
            reading: riskyReading,
            reservePercent: 0,
            records: forecastRecords,
            now: now
        )
        expect(risky.verdict == .conserve, "task check protects quota forecast to expire before reset")
        expect(risky.forecastDepletesBeforeReset, "task check exposes forecast risk")

        expect(
            TaskReadiness.report(
                reading: nil,
                reservePercent: 0,
                records: [],
                now: now
            ).verdict == .unavailable,
            "task check asks for data instead of guessing"
        )
    }

        @MainActor
        private static func testSurplusGate() {
            let now = Date(timeIntervalSince1970: 40_000)
            expect(
                DepletionEstimator.surplusShouldFire(
                    remainingPercent: 60,
                    resetAt: now.addingTimeInterval(6 * 3600),
                    leadMinutes: 12 * 60,
                    minimumRemainingPercent: 50,
                    now: now
                ),
                "surplus reminder fires with plenty left shortly before reset"
            )
            expect(
                !DepletionEstimator.surplusShouldFire(
                    remainingPercent: 40,
                    resetAt: now.addingTimeInterval(6 * 3600),
                    leadMinutes: 12 * 60,
                    minimumRemainingPercent: 50,
                    now: now
                ),
                "surplus reminder stays quiet when the quota is mostly used"
            )
            expect(
                !DepletionEstimator.surplusShouldFire(
                    remainingPercent: 60,
                    resetAt: now.addingTimeInterval(48 * 3600),
                    leadMinutes: 12 * 60,
                    minimumRemainingPercent: 50,
                    now: now
                ),
                "surplus reminder stays quiet far away from the reset"
            )
            expect(
                !DepletionEstimator.surplusShouldFire(
                    remainingPercent: 60,
                    resetAt: now.addingTimeInterval(-60),
                    leadMinutes: 12 * 60,
                    minimumRemainingPercent: 50,
                    now: now
                ),
                "surplus reminder ignores resets already in the past"
            )
        }

        private static func testWeeklyReportStats() {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let calendar = Calendar.current
            let now = Date(timeIntervalSince1970: 1_700_000_000)

            var breakdown: [String: UsageDayBreakdown] = [:]
            for offset in 0..<14 {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
                var day = UsageDayBreakdown()
                day.totalTokens = offset < 7 ? 200 : 100
                day.byProject = offset < 7 ? ["/Users/dev/alpha": 150, "": 50] : ["/Users/dev/beta": 100]
                breakdown[formatter.string(from: date)] = day
            }

            let stats = UsageWeeklyReportStats.build(dailyBreakdown: breakdown, now: now)
            expect(stats.totalTokens == 1_400, "weekly recap sums the trailing 7 days")
            expect(stats.topProject == "alpha", "weekly recap names the hottest project by folder name")
            expect(stats.deltaPercent == 100, "weekly recap compares against the previous 7 days")

            let empty = UsageWeeklyReportStats.build(dailyBreakdown: [:], now: now)
            expect(empty.totalTokens == 0, "empty history yields zero tokens")
            expect(empty.topProject == nil, "empty history has no top project")
            expect(empty.deltaPercent == nil, "delta needs a non-zero previous week")
        }

        private static func testCompactTokenFormat() {
            expect(TokenFormat.compact(410_000_000, language: .simplifiedChinese) == "4.1亿", "Chinese formatting uses 亿")
            expect(TokenFormat.compact(25_000, language: .simplifiedChinese) == "2.5万", "Chinese formatting uses 万")
            expect(TokenFormat.compact(999, language: .simplifiedChinese) == "999", "small values stay literal")
            expect(TokenFormat.compact(410_000_000, language: .english) == "410M", "English formatting trims the .0 tail")
            expect(TokenFormat.compact(1_500_000_000, language: .english) == "1.5B", "English formatting uses B")
            expect(TokenFormat.compact(3_200, language: .english) == "3.2K", "English formatting uses K")
        }

    private static func testDayBreakdownMerge() {
        var day = UsageDayBreakdown()
        day.totalTokens = 100
        day.inputTokens = 80
        day.cachedInputTokens = 60
        day.byProject = ["/tmp/a": 100]
        day.byModel = ["gpt-5": 100]
        day.bySource = ["vscode": 100]

        var other = UsageDayBreakdown()
        other.totalTokens = 50
        other.inputTokens = 40
        other.cachedInputTokens = 10
        other.byProject = ["/tmp/a": 20, "/tmp/b": 30]
        other.byModel = ["gpt-5": 50]
        other.bySource = ["cli": 50]

        day.merge(other)
        expect(day.totalTokens == 150, "breakdown merge sums totals")
        expect(day.inputTokens == 120 && day.cachedInputTokens == 70, "breakdown merge sums cache split")
        expect(day.byProject == ["/tmp/a": 120, "/tmp/b": 30], "breakdown merge sums per-project")
        expect(day.byModel == ["gpt-5": 150], "breakdown merge sums per-model")
        expect(day.bySource == ["vscode": 100, "cli": 50], "breakdown merge sums per-source")
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

    private static func makeLogDatabase(
        at url: URL,
        timestamp: Int,
        body: String,
        target: String = "codex_http_client::default_client"
    ) throws {
        let escapedBody = body.replacingOccurrences(of: "'", with: "''")
        let escapedTarget = target.replacingOccurrences(of: "'", with: "''")
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
        values (1, \(timestamp), 0, 'INFO', '\(escapedTarget)', '\(escapedBody)');
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
