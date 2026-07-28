import AppKit
import Combine

@main
@MainActor
final class CodexBuddyApplication: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarCoordinator?
    private var usageModel: UsageViewModel?
    private var settings: AppSettings?
    private var notifications: UsageNotificationManager?
    private var history: UsageHistoryStore?
    private var activity: UsageActivityStore?
    private var updateChecker: UpdateChecker?
    private var subscriptions = Set<AnyCancellable>()
    private var reloadTimer: Timer?
    private var sessionMonitor: UsageFileMonitor?
    private var activityToken: NSObjectProtocol?

    static func main() {
        let application = NSApplication.shared
        let delegate = CodexBuddyApplication()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        SingleInstanceCoordinator.terminateOtherInstances()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Keep Codex usage monitoring responsive"
        )

        let preview = ProcessInfo.processInfo.environment["CODEX_BUDDY_PREVIEW"] == "1"
        let source: UsageReadingSource = preview ? PreviewUsageReader() : LocalUsageReader()
        let model = UsageViewModel(source: source)
        let preferences = AppSettings()
        let notificationManager = UsageNotificationManager()
        let historyStore = UsageHistoryStore()
        let activityStore = UsageActivityStore()
        let checker = UpdateChecker()
        let updater = AutoUpdater(checker: checker)
        let coordinator = MenuBarCoordinator(
            model: model,
            settings: preferences,
            historyStore: historyStore,
            activityStore: activityStore,
            updateChecker: checker,
            autoUpdater: updater
        )

        usageModel = model
        settings = preferences
        notifications = notificationManager
        history = historyStore
        activity = activityStore
        updateChecker = checker
        menuBar = coordinator

        activityStore.rescan()
        observe(model: model, settings: preferences, coordinator: coordinator)
        if !preview {
            watchSessionChanges(model: model, activityStore: activityStore)
            preferences.$refreshInterval
                .removeDuplicates()
                .sink { [weak self] interval in self?.scheduleReload(every: interval) }
                .store(in: &subscriptions)
            Task { await checker.checkIfNeeded() }
        }
        Task { await model.reload() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        reloadTimer?.invalidate()
        sessionMonitor?.stop()
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
        }
    }

    /// Deep links for Raycast/Alfred/scripts: codexbuddy://dashboard,
    /// codexbuddy://preflight, codexbuddy://settings and codexbuddy://refresh.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host?.lowercased() {
            case "dashboard":
                menuBar?.openUsageDashboard()
            case "preflight":
                let copyResult = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .contains(where: { $0.name == "copy" && $0.value == "1" }) ?? false
                menuBar?.showTaskReadiness(copyResult: copyResult)
            case "settings":
                menuBar?.openSettings()
            case "refresh":
                if let usageModel {
                    Task { await usageModel.reload() }
                }
                activity?.rescan()
            default:
                break
            }
        }
    }

    private func observe(
        model: UsageViewModel,
        settings: AppSettings,
        coordinator: MenuBarCoordinator
    ) {
        Publishers.CombineLatest3(model.$reading, model.$isReloading, model.$issue)
            .sink { [weak coordinator] _, _, _ in
                DispatchQueue.main.async { coordinator?.refreshTitle() }
            }
            .store(in: &subscriptions)

        model.$reading
            .compactMap { $0 }
            .sink { [weak settings, weak notifications, weak history, weak activity] reading in
                guard let settings else { return }
                notifications?.evaluate(
                    reading: reading,
                    threshold: settings.notificationThreshold,
                    language: settings.language,
                    enabled: settings.notificationsEnabled
                )
                notifications?.evaluateResetCountdown(
                    reading: reading,
                    language: settings.language,
                    enabled: settings.notificationsEnabled
                )
                history?.record(reading: reading)
                // Record first so the freshest point feeds the burn-rate model.
                notifications?.evaluateDepletionForecast(
                    reading: reading,
                    records: history?.records24h() ?? [],
                    language: settings.language,
                    enabled: settings.notificationsEnabled
                )
                notifications?.evaluateSurplusReminder(
                    reading: reading,
                    language: settings.language,
                    enabled: settings.notificationsEnabled
                )
                notifications?.evaluateWeeklyReport(
                    reading: reading,
                    dailyBreakdown: activity?.dailyBreakdown ?? [:],
                    language: settings.language,
                    enabled: settings.notificationsEnabled
                )
            }
            .store(in: &subscriptions)

        settings.$notificationsEnabled
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak notifications] _ in notifications?.requestAuthorization() }
            .store(in: &subscriptions)
    }

    private func scheduleReload(every interval: TimeInterval) {
        reloadTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak usageModel] _ in
            guard let usageModel else { return }
            Task { @MainActor in await usageModel.reload() }
        }
        RunLoop.main.add(timer, forMode: .common)
        reloadTimer = timer
    }

    private func watchSessionChanges(model: UsageViewModel, activityStore: UsageActivityStore) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        let monitor = UsageFileMonitor(paths: [directory.path]) { [weak model, weak activityStore] in
            DispatchQueue.main.async {
                guard let model else { return }
                Task { @MainActor in await model.reload() }
                activityStore?.rescan()
            }
        }
        if monitor.start() { sessionMonitor = monitor }
    }
}
