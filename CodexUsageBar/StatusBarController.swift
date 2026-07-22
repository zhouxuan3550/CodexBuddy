import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: UsageStore
    private let settings: AppSettings
    private let historyStore: UsageHistoryStore
    private let updateChecker: UpdateChecker
    private let autoUpdater: AutoUpdater
    private var cancellables = Set<AnyCancellable>()
    private var isMenuOpen = false
    private var needsMenuRebuild = false
    private weak var summaryView: UsageSummaryMenuView?
    private weak var refreshMenuItem: NSMenuItem?
    private let activityStore: UsageActivityStore
    private weak var heatmapView: UsageHeatmapView?
    private var updateWindow: UpdateWindowController?

    init(store: UsageStore, settings: AppSettings, historyStore: UsageHistoryStore, activityStore: UsageActivityStore, updateChecker: UpdateChecker, autoUpdater: AutoUpdater) {
        self.store = store
        self.settings = settings
        self.historyStore = historyStore
        self.activityStore = activityStore
        self.updateChecker = updateChecker
        self.autoUpdater = autoUpdater
        super.init()
        configureStatusItem()
        observeSettings()
        observeUpdateChecker()
        observeActivityStore()
        rebuildMenu()
    }

    func refreshTitle() {
        statusItem.length = NSStatusItem.variableLength
        updateStatusButton()
        summaryView?.update(
            snapshot: store.snapshot,
            isLoading: store.isLoading,
            detailMessage: store.detailMessage(language: language),
            confidenceStatus: store.confidenceStatusText(language: language),
            language: language
        )
        refreshMenuItem?.title = store.isLoading
            ? L10n.text(.refreshing, language: language)
            : L10n.text(.refresh, language: language)
        refreshMenuItem?.isEnabled = !store.isLoading
        if isMenuOpen {
            needsMenuRebuild = true
        } else {
            rebuildMenu()
        }
    }

    private var language: AppLanguage { settings.language }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.imagePosition = .noImage
        button.toolTip = "CodexUsage"
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let segments: [(text: String, percent: Int?)]
        if let snapshot = store.snapshot {
            let availableSegments = snapshot.menuBarSegments(
                mode: settings.menuBarMode,
                showShortWindow: settings.showShortWindow,
                showWeekWindow: settings.showWeekWindow
            )
            segments = availableSegments.isEmpty
                ? [(settings.menuBarMode == .worst ? "--%" : "H --% W --%", nil)]
                : availableSegments.map { ($0.text, $0.percent) }
        } else {
            segments = [(settings.menuBarMode == .worst ? "--%" : "H --% W --%", nil)]
        }

        let title = NSMutableAttributedString(string: "")
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        for (index, segment) in segments.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: " ", attributes: [.font: font]))
            }

            let color: NSColor
            if let percent = segment.percent {
                switch UsageColorLevel.classify(percent: percent) {
                case .low: color = .systemRed
                case .normal: color = .labelColor
                case .high: color = .systemGreen
                }
            } else {
                color = .labelColor
            }

            title.append(NSAttributedString(
                string: segment.text,
                attributes: [.font: font, .foregroundColor: color]
            ))
        }

        if store.snapshot?.isStale() == true {
            title.append(NSAttributedString(
                string: " ⚠︎",
                attributes: [.font: font, .foregroundColor: NSColor.systemOrange]
            ))
        }

        button.title = ""
        button.attributedTitle = title
        button.setAccessibilityLabel(store.statusText)
        if let snapshot = store.snapshot {
            button.toolTip = "\(snapshot.menuBarText) · \(store.updatedAtText(language: language))"
        } else {
            button.toolTip = "CodexUsage"
        }
    }

    private func observeSettings() {
        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshTitle()
                }
            }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let summary = UsageSummaryMenuView(
            snapshot: store.snapshot,
            isLoading: store.isLoading,
            detailMessage: store.detailMessage(language: language),
            confidenceStatus: store.confidenceStatusText(language: language),
            language: language
        )
        let summaryItem = NSMenuItem()
        summaryItem.view = summary
        menu.addItem(summaryItem)
        summaryView = summary

        // Plan & Credits info row
        if let snapshot = store.snapshot, snapshot.planType != nil || snapshot.credits != nil {
            let infoItem = NSMenuItem()
            infoItem.view = makePlanCreditsView(snapshot: snapshot)
            menu.addItem(infoItem)
        }

        // Depletion estimate
        if let estimateText = depletionEstimateText() {
            let estimateItem = NSMenuItem()
            estimateItem.view = makeEstimateView(text: estimateText)
            menu.addItem(estimateItem)
        }

        menu.addItem(.separator())

        // Token activity heatmap
        let heatmapHeaderItem = NSMenuItem()
        heatmapHeaderItem.view = makeSectionHeaderView(title: L10n.text(.tokenActivity, language: language))
        menu.addItem(heatmapHeaderItem)

        let heatmap = UsageHeatmapView()
        heatmap.update(dailyTokens: activityStore.dailyTokens, language: language)

        // Wrap heatmap in frosted glass container
        let heatmapContainer = NSView(frame: NSRect(
            x: 0, y: 0,
            width: UsageSummaryMenuView.preferredWidth - 40,
            height: heatmap.frame.height
        ))
        let heatmapEffect = NSVisualEffectView(frame: heatmapContainer.bounds)
        heatmapEffect.material = .popover
        heatmapEffect.blendingMode = .behindWindow
        heatmapEffect.state = .active
        heatmapEffect.autoresizingMask = [.width, .height]
        heatmapContainer.addSubview(heatmapEffect)
        heatmap.frame = heatmapContainer.bounds
        heatmap.autoresizingMask = [.width, .height]
        heatmapContainer.addSubview(heatmap)

        let heatmapItem = NSMenuItem()
        heatmapItem.view = heatmapContainer
        menu.addItem(heatmapItem)
        heatmapView = heatmap

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: store.isLoading ? L10n.text(.refreshing, language: language) : L10n.text(.refresh, language: language),
            action: #selector(refreshUsage),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = !store.isLoading
        refreshItem.image = menuImage(named: "arrow.triangle.2.circlepath")
        menu.addItem(refreshItem)
        refreshMenuItem = refreshItem

        let openItem = NSMenuItem(
            title: L10n.text(.openOfficialUsage, language: language),
            action: #selector(openOfficialUsage),
            keyEquivalent: "o"
        )
        openItem.target = self
        openItem.image = menuImage(named: "arrow.up.right.square")
        menu.addItem(openItem)

        menu.addItem(settingsMenuItem())
        menu.addItem(.separator())

        // Update check item
        let updateItem = NSMenuItem(
            title: updateMenuItemTitle(),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.image = menuImage(named: updateChecker.availableUpdate != nil ? "arrow.down.circle.fill" : "arrow.down.circle")
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(
            title: L10n.text(.about, language: language),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = menuImage(named: "info.circle")
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: L10n.text(.quit, language: language),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = menuImage(named: "power")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func settingsMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: L10n.text(.settings, language: language), action: nil, keyEquivalent: "")
        rootItem.image = menuImage(named: "gearshape")
        let menu = NSMenu()

        let launchItem = NSMenuItem(
            title: L10n.text(.launchAtLogin, language: language),
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

    private func refreshIntervalMenu() -> NSMenu {
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

    private func notificationMenu() -> NSMenu {
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

    private func languageMenu() -> NSMenu {
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

    private func menuBarDisplayMenu() -> NSMenu {
        let menu = NSMenu()

        let modeMenu = NSMenu()
        for mode in MenuBarMode.allCases {
            let titleKey: L10nKey = mode == .dual ? .dualWindowMode : .worstWindowMode
            let item = NSMenuItem(
                title: L10n.text(titleKey, language: language),
                action: #selector(selectMenuBarMode(_:)),
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
        shortItem.isEnabled = settings.menuBarMode == .dual
        menu.addItem(shortItem)

        let weekItem = NSMenuItem(
            title: L10n.text(.showWeekWindow, language: language),
            action: #selector(toggleShowWeekWindow),
            keyEquivalent: ""
        )
        weekItem.target = self
        weekItem.state = settings.showWeekWindow ? .on : .off
        weekItem.isEnabled = settings.menuBarMode == .dual
        menu.addItem(weekItem)

        return menu
    }

    private func submenuItem(title: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func menuImage(named symbolName: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        // Always fetch fresh data when the user opens the menu, so the value
        // they see is current even if background refreshes were delayed.
        Task { await store.refresh() }
        activityStore.rescan()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        guard needsMenuRebuild else { return }
        needsMenuRebuild = false
        rebuildMenu()
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func refreshUsage() {
        Task { await store.refresh() }
    }

    @objc private func openOfficialUsage() {
        store.openOfficialUsage()
    }

    @objc private func toggleLaunchAtLogin() {
        settings.setLaunchAtLoginEnabled(!settings.launchAtLoginEnabled)
    }

    @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
        guard let interval = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        settings.refreshInterval = interval
    }

    @objc private func toggleNotifications() {
        settings.notificationsEnabled.toggle()
    }

    @objc private func selectNotificationThreshold(_ sender: NSMenuItem) {
        guard let threshold = (sender.representedObject as? NSNumber)?.intValue else { return }
        settings.notificationThreshold = threshold
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let selectedLanguage = AppLanguage(rawValue: rawValue)
        else { return }
        settings.language = selectedLanguage
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "CodexUsage",
            .applicationVersion: version,
            .version: "Build \(build)"
        ])
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - v0.4 Features

    private func observeUpdateChecker() {
        updateChecker.$availableUpdate
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshTitle()
                }
            }
            .store(in: &cancellables)

        autoUpdater.$state
            .sink { [weak self] state in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.refreshTitle()
                    self.handleUpdateState(state)
                }
            }
            .store(in: &cancellables)
    }

    private func handleUpdateState(_ state: AutoUpdater.UpdateState) {
        switch state {
        case .available(let release):
            if updateWindow == nil {
                updateWindow = UpdateWindowController.show(
                    version: release.version,
                    releaseNotesURL: release.htmlURL,
                    language: language,
                    onCancel: { [weak self] in
                        self?.autoUpdater.cancelDownload()
                    }
                )
            }
        case .downloading(let progress):
            updateWindow?.updateProgress(progress)
        case .installing:
            updateWindow?.setInstalling()
        case .failed:
            updateWindow?.window?.close()
            updateWindow = nil
        case .idle, .upToDate:
            updateWindow?.window?.close()
            updateWindow = nil
        default:
            break
        }
    }

    private func makePlanCreditsView(snapshot: UsageSnapshot) -> NSView {
        var parts: [String] = []
        if let plan = snapshot.planType {
            parts.append("\(L10n.text(.planType, language: language)): \(plan.capitalized)")
        }
        if let credits = snapshot.credits {
            if credits.unlimited {
                parts.append("\(L10n.text(.creditsBalance, language: language)): ∞")
            } else if let balance = credits.displayBalance {
                parts.append("\(L10n.text(.creditsBalance, language: language)): \(balance)")
            }
        }

        let label = NSTextField(labelWithString: parts.joined(separator: "  ·  "))
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    private func makeEstimateView(text: String) -> NSView {
        let label = NSTextField(labelWithString: "⏳ \(text)")
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = .systemOrange
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    private func makeSectionHeaderView(title: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            titleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])
        return container
    }

    private func depletionEstimateText() -> String? {
        guard let snapshot = store.snapshot, let window = snapshot.featuredWindow else { return nil }
        let windowType: DepletionEstimator.WindowType = window.minutes >= 10_080 ? .week : .short
        let records = historyStore.records24h()
        let estimate = DepletionEstimator.estimate(
            records: records,
            windowType: windowType,
            currentRemaining: window.remainingPercent
        )
        guard let estimateText = DepletionEstimator.formatEstimate(estimate, language: language) else { return nil }
        if let rate = DepletionEstimator.formatRate(estimate) {
            return "\(estimateText)  ·  \(rate)"
        }
        return estimateText
    }

    private func updateMenuItemTitle() -> String {
        switch autoUpdater.state {
        case .downloading(let progress):
            return "\(L10n.text(.checkForUpdates, language: language))... \(Int(progress * 100))%"
        case .readyToInstall, .installing:
            return language.resolved == .simplifiedChinese ? "安装更新并重启" : "Install Update & Restart"
        case .available(let release):
            return "\(L10n.text(.updateAvailable, language: language)) v\(release.version)"
        case .checking:
            return L10n.text(.refreshing, language: language)
        case .failed:
            return language.resolved == .simplifiedChinese ? "更新失败，点击重试" : "Update failed, retry"
        default:
            if updateChecker.availableUpdate != nil {
                return L10n.text(.updateAvailable, language: language)
            }
            return L10n.text(.checkForUpdates, language: language)
        }
    }

    @objc private func exportDiagnostic() {
        DiagnosticExporter.export(
            snapshot: store.snapshot,
            settings: settings,
            historyStore: historyStore,
            language: language
        )
    }

    @objc private func checkForUpdates() {
        switch autoUpdater.state {
        case .readyToInstall, .available:
            autoUpdater.downloadAndInstall()
        case .downloading:
            break
        default:
            Task {
                await autoUpdater.checkForUpdate()
                if case .available = autoUpdater.state {
                    autoUpdater.downloadAndInstall()
                }
            }
        }
    }

    private func observeActivityStore() {
        activityStore.$dailyTokens
            .sink { [weak self] tokens in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.heatmapView?.update(dailyTokens: tokens, language: self.language)
                }
            }
            .store(in: &cancellables)
    }

    @objc private func toggleShowShortWindow() {
        settings.showShortWindow.toggle()
    }

    @objc private func selectMenuBarMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = MenuBarMode(rawValue: rawValue)
        else { return }
        settings.menuBarMode = mode
    }

    @objc private func toggleShowWeekWindow() {
        settings.showWeekWindow.toggle()
    }

    @objc private func exportCSV() {
        CSVExporter.export(historyStore: historyStore, language: language)
    }
}
