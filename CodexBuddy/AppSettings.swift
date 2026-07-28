import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let refreshIntervals: [TimeInterval] = [5, 15, 30, 60]
    static let notificationThresholds = [10, 20, 30]
    static let weeklyReserveOptions = [0, 10, 20, 30]

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    @Published var notificationThreshold: Int {
        didSet { defaults.set(notificationThreshold, forKey: Keys.notificationThreshold) }
    }

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var showShortWindow: Bool {
        didSet { defaults.set(showShortWindow, forKey: Keys.showShortWindow) }
    }

    @Published var showWeekWindow: Bool {
        didSet { defaults.set(showWeekWindow, forKey: Keys.showWeekWindow) }
    }

    @Published var menuBarMode: StatusDisplayMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: Keys.menuBarMode) }
    }

    @Published var floatingWidgetEnabled: Bool {
        didSet { defaults.set(floatingWidgetEnabled, forKey: Keys.floatingWidgetEnabled) }
    }

    @Published var menuBarSparkline: Bool {
        didSet { defaults.set(menuBarSparkline, forKey: Keys.menuBarSparkline) }
    }

    @Published var globalHotkeyEnabled: Bool {
        didSet { defaults.set(globalHotkeyEnabled, forKey: Keys.globalHotkeyEnabled) }
    }

    /// A soft buffer used by the weekly pacing plan. It only informs the UI;
    /// CodexBuddy never blocks or changes Codex usage.
    @Published var weeklyReservePercent: Int {
        didSet { defaults.set(weeklyReservePercent, forKey: Keys.weeklyReservePercent) }
    }

    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var launchAtLoginRequiresApproval: Bool
    @Published private(set) var launchAtLoginIsUpdating = false
    @Published private(set) var settingsError: String?

    private let defaults: UserDefaults
    private var launchAtLoginRefreshTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedInterval = defaults.object(forKey: Keys.refreshInterval) as? Double ?? 15
        refreshInterval = Self.refreshIntervals.contains(savedInterval) ? savedInterval : 15

        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)

        let savedThreshold = defaults.object(forKey: Keys.notificationThreshold) as? Int ?? 20
        notificationThreshold = Self.notificationThresholds.contains(savedThreshold) ? savedThreshold : 20

        let languageValue = defaults.string(forKey: Keys.language) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: languageValue) ?? .system

        showShortWindow = defaults.object(forKey: Keys.showShortWindow) as? Bool ?? true
        showWeekWindow = defaults.object(forKey: Keys.showWeekWindow) as? Bool ?? true
        let savedMode = defaults.string(forKey: Keys.menuBarMode)
        menuBarMode = savedMode.flatMap(StatusDisplayMode.init(rawValue:))
            ?? (savedMode == "worst" ? .tightest : .allWindows)
        floatingWidgetEnabled = defaults.object(forKey: Keys.floatingWidgetEnabled) as? Bool ?? false
        menuBarSparkline = defaults.object(forKey: Keys.menuBarSparkline) as? Bool ?? false
        globalHotkeyEnabled = defaults.object(forKey: Keys.globalHotkeyEnabled) as? Bool ?? true
        let savedReserve = defaults.object(forKey: Keys.weeklyReservePercent) as? Int ?? 0
        weeklyReservePercent = Self.weeklyReserveOptions.contains(savedReserve) ? savedReserve : 0

        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = Self.isLaunchAtLoginRegistered(status)
        launchAtLoginRequiresApproval = status == .requiresApproval
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard !launchAtLoginIsUpdating else {
            return
        }

        launchAtLoginRefreshTask?.cancel()

        let service = SMAppService.mainApp
        settingsError = nil
        launchAtLoginEnabled = enabled
        launchAtLoginRequiresApproval = false
        launchAtLoginIsUpdating = true

        do {
            if enabled {
                if !Self.isLaunchAtLoginRegistered(service.status) {
                    try service.register()
                }
            } else if Self.isLaunchAtLoginRegistered(service.status) {
                try service.unregister()
            }
        } catch {
            applyLaunchAtLoginStatus(service.status)
            settingsError = error.localizedDescription
            return
        }

        launchAtLoginRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            for attempt in 0..<6 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }

                guard !Task.isCancelled else {
                    return
                }

                let status = SMAppService.mainApp.status
                if Self.status(status, matchesEnabledState: enabled) {
                    applyLaunchAtLoginStatus(status)
                    return
                }
            }

            let status = SMAppService.mainApp.status
            applyLaunchAtLoginStatus(status)

            if launchAtLoginEnabled != enabled {
                settingsError = launchAtLoginSyncError(expectedEnabled: enabled)
            }
        }
    }

    func refreshLaunchAtLoginState() {
        guard !launchAtLoginIsUpdating else {
            return
        }

        applyLaunchAtLoginStatus(SMAppService.mainApp.status)
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func isLaunchAtLoginRegistered(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    private static func status(
        _ status: SMAppService.Status,
        matchesEnabledState enabled: Bool
    ) -> Bool {
        if enabled {
            return status == .enabled || status == .requiresApproval
        }

        return status == .notRegistered || status == .notFound
    }

    private func applyLaunchAtLoginStatus(_ status: SMAppService.Status) {
        launchAtLoginEnabled = Self.isLaunchAtLoginRegistered(status)
        launchAtLoginRequiresApproval = status == .requiresApproval
        launchAtLoginIsUpdating = false
    }

    private func launchAtLoginSyncError(expectedEnabled: Bool) -> String {
        if language.resolved == .english {
            return expectedEnabled
                ? "macOS did not enable the login item. Try again or allow it in System Settings."
                : "macOS did not disable the login item. Try again in System Settings."
        }

        return expectedEnabled
            ? "macOS 未能启用登录项，请重试或前往系统设置允许。"
            : "macOS 未能关闭登录项，请前往系统设置重试。"
    }

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationThreshold = "notificationThreshold"
        static let language = "language"
        static let showShortWindow = "showShortWindow"
        static let showWeekWindow = "showWeekWindow"
        static let menuBarMode = "menuBarMode"
        static let floatingWidgetEnabled = "floatingWidgetEnabled"
        static let menuBarSparkline = "menuBarSparkline"
        static let globalHotkeyEnabled = "globalHotkeyEnabled"
        static let weeklyReservePercent = "weeklyReservePercent"
    }
}
