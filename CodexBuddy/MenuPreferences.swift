import Cocoa

// Preferences, commands, and menu lifecycle
extension MenuBarCoordinator {
    func settingsMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: L10n.text(.settings, language: language), action: nil, keyEquivalent: "")
        rootItem.image = menuImage(named: "gearshape")
        let menu = NSMenu()

        let launchItem = NSMenuItem(
            title: L10n.launchAtLoginTitle(
                isEnabled: settings.launchAtLoginEnabled,
                language: language
            ),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = settings.launchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)

        if let settingsError = settings.settingsError {
            menu.addItem(disabledItem("⚠︎ \(settingsError)"))
        }

        menu.addItem(submenuItem(
            title: L10n.text(.refreshInterval, language: language),
            menu: refreshIntervalMenu()
        ))
        menu.addItem(submenuItem(
            title: L10n.text(.notifications, language: language),
            menu: notificationMenu()
        ))
        menu.addItem(submenuItem(
            title: L10n.text(.language, language: language),
            menu: languageMenu()
        ))
        menu.addItem(submenuItem(
            title: L10n.text(.menuBarDisplay, language: language),
            menu: menuBarDisplayMenu()
        ))

        menu.addItem(.separator())

        let diagnosticItem = NSMenuItem(
            title: L10n.text(.exportDiagnostic, language: language),
            action: #selector(exportDiagnostic),
            keyEquivalent: ""
        )
        diagnosticItem.target = self
        diagnosticItem.image = menuImage(named: "doc.text")
        menu.addItem(diagnosticItem)

        let csvItem = NSMenuItem(
            title: L10n.text(.exportCSV, language: language),
            action: #selector(exportCSV),
            keyEquivalent: ""
        )
        csvItem.target = self
        csvItem.image = menuImage(named: "tablecells")
        menu.addItem(csvItem)

        rootItem.submenu = menu
        return rootItem
    }

    func refreshIntervalMenu() -> NSMenu {
        let menu = NSMenu()
        for interval in AppSettings.refreshIntervals {
            let item = NSMenuItem(
                title: "\(Int(interval)) \(L10n.text(.seconds, language: language))",
                action: #selector(selectRefreshInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: interval)
            item.state = settings.refreshInterval == interval ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    func notificationMenu() -> NSMenu {
        let menu = NSMenu()
        let enabledItem = NSMenuItem(
            title: L10n.text(.enableNotifications, language: language),
            action: #selector(toggleNotifications),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = settings.notificationsEnabled ? .on : .off
        menu.addItem(enabledItem)
        menu.addItem(.separator())
        menu.addItem(disabledItem(L10n.text(.notifyBelow, language: language)))

        for threshold in AppSettings.notificationThresholds {
            let item = NSMenuItem(
                title: "≤ \(threshold)%",
                action: #selector(selectNotificationThreshold(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: threshold)
            item.state = settings.notificationThreshold == threshold ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    func languageMenu() -> NSMenu {
        let menu = NSMenu()
        let options: [(AppLanguage, L10nKey)] = [
            (.system, .systemLanguage),
            (.simplifiedChinese, .simplifiedChinese),
            (.english, .english)
        ]

        for (appLanguage, titleKey) in options {
            let item = NSMenuItem(
                title: L10n.text(titleKey, language: language),
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = appLanguage.rawValue
            item.state = settings.language == appLanguage ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    func menuBarDisplayMenu() -> NSMenu {
        let menu = NSMenu()

        let modeMenu = NSMenu()
        for mode in StatusDisplayMode.allCases {
            let titleKey: L10nKey = mode == .allWindows ? .dualWindowMode : .worstWindowMode
            let item = NSMenuItem(
                title: L10n.text(titleKey, language: language),
                action: #selector(selectStatusDisplayMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.menuBarMode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        menu.addItem(submenuItem(
            title: L10n.text(.displayMode, language: language),
            menu: modeMenu
        ))
        menu.addItem(.separator())

        let shortItem = NSMenuItem(
            title: L10n.text(.showShortWindow, language: language),
            action: #selector(toggleShowShortWindow),
            keyEquivalent: ""
        )
        shortItem.target = self
        shortItem.state = settings.showShortWindow ? .on : .off
        shortItem.isEnabled = settings.menuBarMode == .allWindows
        menu.addItem(shortItem)

        let weekItem = NSMenuItem(
            title: L10n.text(.showWeekWindow, language: language),
            action: #selector(toggleShowWeekWindow),
            keyEquivalent: ""
        )
        weekItem.target = self
        weekItem.state = settings.showWeekWindow ? .on : .off
        weekItem.isEnabled = settings.menuBarMode == .allWindows
        menu.addItem(weekItem)

        return menu
    }

    func submenuItem(title: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
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

    @objc func toggleLaunchAtLogin() {
        settings.setLaunchAtLoginEnabled(!settings.launchAtLoginEnabled)
    }

    @objc func selectRefreshInterval(_ sender: NSMenuItem) {
        guard let interval = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        settings.refreshInterval = interval
    }

    @objc func toggleNotifications() {
        settings.notificationsEnabled.toggle()
    }

    @objc func selectNotificationThreshold(_ sender: NSMenuItem) {
        guard let threshold = (sender.representedObject as? NSNumber)?.intValue else { return }
        settings.notificationThreshold = threshold
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let selectedLanguage = AppLanguage(rawValue: rawValue)
        else { return }
        settings.language = selectedLanguage
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
