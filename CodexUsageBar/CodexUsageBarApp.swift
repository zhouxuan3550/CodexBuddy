import AppKit
import Combine

@main
@MainActor
final class CodexUsageApp: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var store: UsageStore?
    private var settings: AppSettings?
    private var notificationManager: UsageNotificationManager?
    private var historyStore: UsageHistoryStore?
    private var activityStore: UsageActivityStore?
    private var updateChecker: UpdateChecker?
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var usageFileMonitor: UsageFileMonitor?
    private var activityToken: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = CodexUsageApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        SingleInstanceCoordinator.terminateOtherInstances()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the process active so App Nap doesn't freeze the usage monitor.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "CodexUsage continuously monitors Codex usage for the menu bar"
        )

        let settings = AppSettings()
        let isPreviewMode = ProcessInfo.processInfo.environment["CODEX_USAGE_PREVIEW"] == "1"
        let provider: UsageProvider = isPreviewMode ? MockUsageProvider() : CodexUsageProvider()
        let store = UsageStore(provider: provider)
        let notificationManager = UsageNotificationManager()
        let historyStore = UsageHistoryStore()
        let activityStore = UsageActivityStore()
        let updateChecker = UpdateChecker()
        let autoUpdater = AutoUpdater(checker: updateChecker)
        let controller = StatusBarController(
            store: store,
            settings: settings,
            historyStore: historyStore,
            activityStore: activityStore,
            updateChecker: updateChecker,
            autoUpdater: autoUpdater
        )

        self.settings = settings
        self.store = store
        self.notificationManager = notificationManager
        self.historyStore = historyStore
        self.activityStore = activityStore
        self.updateChecker = updateChecker
        self.statusBarController = controller
        activityStore.rescan()
        if !isPreviewMode {
            startUsageFileMonitor(store: store, activityStore: activityStore)
        }

        Publishers.CombineLatest3(store.$snapshot, store.$isLoading, store.$providerError)
            .sink { [weak controller] _, _, _ in
                DispatchQueue.main.async {
                    controller?.refreshTitle()
                }
            }
            .store(in: &cancellables)

        store.$snapshot
            .compactMap { $0 }
            .sink { [weak settings, weak notificationManager, weak historyStore] snapshot in
                guard let settings else { return }
                notificationManager?.evaluate(
                    snapshot: snapshot,
                    threshold: settings.notificationThreshold,
                    language: settings.language,
                    enabled: settings.notificationsEnabled
                )
                notificationManager?.evaluateResetCountdown(
                    snapshot: snapshot,
                    language: settings.language,
                    enabled: settings.notificationsEnabled
                )
                historyStore?.record(snapshot: snapshot)
            }
            .store(in: &cancellables)

        if !isPreviewMode {
            settings.$refreshInterval
                .removeDuplicates()
                .sink { [weak self] interval in
                    self?.scheduleRefreshTimer(interval: interval)
                }
                .store(in: &cancellables)
        }

        settings.$notificationsEnabled
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak notificationManager] _ in
                notificationManager?.requestAuthorization()
            }
            .store(in: &cancellables)

        Task { await store.refresh() }

        // Silent update check at launch (respects 24h cooldown)
        if !isPreviewMode {
            Task { await updateChecker.checkIfNeeded() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        usageFileMonitor?.stop()
    }

    private func scheduleRefreshTimer(interval: TimeInterval) {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak store] _ in
            guard let store else { return }
            Task { @MainActor in
                await store.refresh()
            }
        }
        // .common mode keeps the timer firing while menus are open (tracking mode).
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func startUsageFileMonitor(store: UsageStore, activityStore: UsageActivityStore) {
        let sessionsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
            .path
        guard FileManager.default.fileExists(atPath: sessionsPath) else { return }

        let monitor = UsageFileMonitor(paths: [sessionsPath]) { [weak store, weak activityStore] in
            DispatchQueue.main.async { [weak store, weak activityStore] in
                guard let store else { return }
                Task { @MainActor in
                    await store.refresh()
                }
                activityStore?.rescan()
            }
        }
        if monitor.start() {
            usageFileMonitor = monitor
        }
    }
}
