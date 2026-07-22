import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let refreshIntervals: [TimeInterval] = [5, 15, 30, 60]
    static let notificationThresholds = [10, 20, 30]

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

    @Published var menuBarMode: MenuBarMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: Keys.menuBarMode) }
    }

    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var settingsError: String?

    private let defaults: UserDefaults

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
        menuBarMode = defaults.string(forKey: Keys.menuBarMode)
            .flatMap(MenuBarMode.init(rawValue:)) ?? .dual

        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled || status == .requiresApproval
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if enabled {
                if service.status == .notRegistered {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }

            launchAtLoginEnabled = service.status == .enabled || service.status == .requiresApproval
            settingsError = nil
        } catch {
            launchAtLoginEnabled = service.status == .enabled || service.status == .requiresApproval
            settingsError = error.localizedDescription
        }
    }

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationThreshold = "notificationThreshold"
        static let language = "language"
        static let showShortWindow = "showShortWindow"
        static let showWeekWindow = "showWeekWindow"
        static let menuBarMode = "menuBarMode"
    }
}
