import Cocoa

// Preferences, commands, and menu lifecycle
extension MenuBarCoordinator {
    func settingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(L10n.text(.settings, language: language))…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        item.target = self
        item.image = menuImage(named: "gearshape")
        return item
    }

    func menuImage(named symbolName: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        // Always fetch fresh data when the user opens the menu, so the value
        // they see is current even if background refreshes were delayed.
        Task { await model.reload() }
        activityStore.rescan()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        guard needsMenuRebuild else { return }
        needsMenuRebuild = false
        rebuildMenu()
    }

    func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc func refreshUsage() {
        Task { await model.reload() }
    }

    @objc func openOfficialUsagePage() {
        model.openOfficialUsagePage()
    }

    @objc func openUsageDashboard() {
        if dashboardWindow == nil {
            dashboardWindow = UsageDashboardWindowController(
                model: model,
                settings: settings,
                historyStore: historyStore,
                activityStore: activityStore
            )
        }
        dashboardWindow?.show()
    }

    /// Global-hotkey and URL-scheme entry: hides the dashboard when it is
    /// already frontmost, otherwise brings it up.
    func toggleUsageDashboard() {
        if let window = dashboardWindow?.window, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
            return
        }
        openUsageDashboard()
    }

    @objc func openTaskReadiness() {
        showTaskReadiness(copyResult: false)
    }

    func showTaskReadiness(copyResult: Bool) {
        if taskReadinessWindow == nil {
            taskReadinessWindow = TaskReadinessWindowController(
                model: model,
                settings: settings,
                historyStore: historyStore
            )
        }
        taskReadinessWindow?.show(copyResult: copyResult)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                model: model,
                settings: settings,
                historyStore: historyStore,
                activityStore: activityStore,
                onCheckForUpdates: { [weak self] in
                    self?.checkForUpdates()
                }
            )
        }
        settingsWindow?.show()
    }

    @objc func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: ProductIdentity.name,
            .applicationVersion: version,
            .version: "Build \(build)"
        ])
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
