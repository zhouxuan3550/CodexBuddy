import Cocoa
import Combine

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let model: UsageViewModel
    let settings: AppSettings
    let historyStore: UsageHistoryStore
    let updateChecker: UpdateChecker
    let autoUpdater: AutoUpdater
    var cancellables = Set<AnyCancellable>()
    var isMenuOpen = false
    var needsMenuRebuild = false
    weak var summaryView: UsageSummaryMenuView?
    weak var refreshMenuItem: NSMenuItem?
    let activityStore: UsageActivityStore
    weak var heatmapView: UsageHeatmapView?
    var updateWindow: UpdateWindowController?
    var floatingPanel: FloatingUsagePanelController?
    var settingsWindow: SettingsWindowController?
    var dashboardWindow: UsageDashboardWindowController?
    var taskReadinessWindow: TaskReadinessWindowController?
    private var hotKey: GlobalHotKey?

    init(model: UsageViewModel, settings: AppSettings, historyStore: UsageHistoryStore, activityStore: UsageActivityStore, updateChecker: UpdateChecker, autoUpdater: AutoUpdater) {
        self.model = model
        self.settings = settings
        self.historyStore = historyStore
        self.activityStore = activityStore
        self.updateChecker = updateChecker
        self.autoUpdater = autoUpdater
        super.init()
        configureStatusItem()
        configureFloatingPanel()
        configureHotKey()
        observeSettings()
        observeUpdateChecker()
        observeActivityStore()
        rebuildMenu()
        if ProcessInfo.processInfo.environment["CODEX_BUDDY_SETTINGS"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
        }
        if ProcessInfo.processInfo.environment["CODEX_BUDDY_DASHBOARD"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.openUsageDashboard()
            }
        }
    }

    private func configureFloatingPanel() {
        let controller = FloatingUsagePanelController(
            model: model,
            settings: settings,
            onOpenDetails: { [weak self] in
                self?.openUsageDashboard()
            }
        )
        floatingPanel = controller
        let forcePreview = ProcessInfo.processInfo.environment["CODEX_BUDDY_FLOATING_WIDGET"] == "1"

        settings.$floatingWidgetEnabled
            .removeDuplicates()
            .sink { [weak controller] enabled in
                if enabled || forcePreview {
                    controller?.show()
                } else {
                    controller?.hide()
                }
            }
            .store(in: &cancellables)
    }

    /// Registers ⌥⌘U while the setting is on; dropping the instance
    /// unregisters it, so toggling the switch takes effect immediately.
    private func configureHotKey() {
        settings.$globalHotkeyEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    guard self.hotKey == nil else { return }
                    self.hotKey = GlobalHotKey.optionCommandU { [weak self] in
                        self?.toggleUsageDashboard()
                    }
                } else {
                    self.hotKey = nil
                }
            }
            .store(in: &cancellables)
    }

    func refreshTitle() {
        statusItem.length = NSStatusItem.variableLength
        updateStatusButton()
        summaryView?.update(
            reading: model.reading,
            isLoading: model.isReloading,
            detailMessage: model.detailText(language: language),
            confidenceStatus: model.confidenceText(language: language),
            language: language
        )
        refreshMenuItem?.title = model.isReloading
            ? L10n.text(.refreshing, language: language)
            : L10n.text(.refresh, language: language)
        refreshMenuItem?.isEnabled = !model.isReloading
        if isMenuOpen {
            needsMenuRebuild = true
        } else {
            rebuildMenu()
        }
    }

    var language: AppLanguage { settings.language }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.imagePosition = .noImage
        button.toolTip = ProductIdentity.name
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let segments: [(text: String, percent: Int?)]
        if settings.menuBarMode == .todayTokens {
            // Fed by the activity store: show today's total token consumption.
            let todayKey = UIDateFormatters.formatter(
                dateFormat: "yyyy-MM-dd",
                localeIdentifier: "en_US_POSIX"
            ).string(from: Date())
            let tokens = activityStore.dailyTokens[todayKey] ?? 0
            segments = [("T \(TokenFormat.compact(tokens, language: language))", nil)]
        } else if let reading = model.reading {
            let availableSegments = reading.menuBarSegments(
                mode: settings.menuBarMode,
                showShortWindow: settings.showShortWindow,
                showWeekWindow: settings.showWeekWindow
            )
            segments = availableSegments.isEmpty
                ? [(settings.menuBarMode == .tightest ? "--%" : "H --% W --%", nil)]
                : availableSegments.map { ($0.text, $0.percent) }
        } else {
            segments = [(settings.menuBarMode == .tightest ? "--%" : "H --% W --%", nil)]
        }

        let title = NSMutableAttributedString(string: "")
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        for (index, segment) in segments.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: " ", attributes: [.font: font]))
            }

            let color: NSColor
            if let percent = segment.percent {
                switch QuotaLevel.forRemaining(percent) {
                case .critical: color = .systemRed
                case .standard: color = .labelColor
                case .healthy: color = .systemGreen
                }
            } else {
                color = .labelColor
            }

            title.append(NSAttributedString(
                string: segment.text,
                attributes: [.font: font, .foregroundColor: color]
            ))
        }

        if model.reading?.isOutdated() == true {
            title.append(NSAttributedString(
                string: " ⚠︎",
                attributes: [.font: font, .foregroundColor: NSColor.systemOrange]
            ))
        }

        button.title = ""
        button.attributedTitle = title
        updateSparkline(on: button)
        button.setAccessibilityLabel(model.statusText)
        if let reading = model.reading {
            button.toolTip = "\(reading.completeStatusText) · \(model.updatedText(language: language))"
        } else {
            button.toolTip = ProductIdentity.name
        }
    }

    /// Appends a tiny trend line after the text when the user opts in:
    /// percent modes plot the last 24h of remaining quota, today mode plots
    /// the last 7 days of token consumption.
    private func updateSparkline(on button: NSStatusBarButton) {
        guard settings.menuBarSparkline else {
            button.image = nil
            button.imagePosition = .noImage
            return
        }

        let values: [Double]
        if settings.menuBarMode == .todayTokens {
            let formatter = UIDateFormatters.formatter(
                dateFormat: "yyyy-MM-dd",
                localeIdentifier: "en_US_POSIX"
            )
            let calendar = Calendar.current
            let now = Date()
            values = (0..<7).reversed().compactMap { offset -> Double? in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
                return Double(activityStore.dailyTokens[formatter.string(from: date)] ?? 0)
            }
        } else {
            values = historyStore.records24h().compactMap { record in
                record.shortRemaining.map(Double.init)
            }
        }

        if let image = MenuBarSparkline.image(values: values) {
            button.image = image
            button.imagePosition = .imageTrailing
        } else {
            button.image = nil
            button.imagePosition = .noImage
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

    func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let summary = UsageSummaryMenuView(
            reading: model.reading,
            isLoading: model.isReloading,
            detailMessage: model.detailText(language: language),
            confidenceStatus: model.confidenceText(language: language),
            language: language
        )
        let summaryItem = NSMenuItem()
        summaryItem.view = summary
        menu.addItem(summaryItem)
        summaryView = summary

        // Plan & Credits info row
        if let reading = model.reading, reading.planName != nil || reading.credits != nil {
            let infoItem = NSMenuItem()
            infoItem.view = makePlanCreditsView(reading: reading)
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

        let dashboardItem = NSMenuItem(
            title: UsageDashboardCopy(language: language).menuTitle,
            action: #selector(openUsageDashboard),
            keyEquivalent: "d"
        )
        dashboardItem.target = self
        dashboardItem.image = menuImage(named: "chart.bar.xaxis")
        menu.addItem(dashboardItem)

        let taskCheckItem = NSMenuItem(
            title: TaskReadinessCopy(language: language).title + "…",
            action: #selector(openTaskReadiness),
            keyEquivalent: ""
        )
        taskCheckItem.target = self
        taskCheckItem.image = menuImage(named: "checkmark.seal")
        menu.addItem(taskCheckItem)

        let refreshItem = NSMenuItem(
            title: model.isReloading ? L10n.text(.refreshing, language: language) : L10n.text(.refresh, language: language),
            action: #selector(refreshUsage),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = !model.isReloading
        refreshItem.image = menuImage(named: "arrow.triangle.2.circlepath")
        menu.addItem(refreshItem)
        refreshMenuItem = refreshItem

        let openItem = NSMenuItem(
            title: L10n.text(.openOfficialUsage, language: language),
            action: #selector(openOfficialUsagePage),
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
}

/// Renders the tiny menu-bar trend line as a template image so it adapts to
/// the menu bar's light/dark appearance automatically.
@MainActor
enum MenuBarSparkline {
    nonisolated static let size = NSSize(width: 30, height: 12)

    static func image(values: [Double], size: NSSize = size) -> NSImage? {
        // Cap the point count so a dense 24h history stays smooth at 30pt.
        let points = downsample(values, to: 24)
        guard points.count >= 2 else { return nil }

        let minValue = points.min() ?? 0
        let maxValue = points.max() ?? 0
        let range = maxValue - minValue

        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let insetY: CGFloat = 1.5
            let drawableHeight = rect.height - insetY * 2
            let stepX = rect.width / CGFloat(points.count - 1)

            for (index, value) in points.enumerated() {
                let normalized = range > 0 ? (value - minValue) / range : 0.5
                let point = NSPoint(
                    x: CGFloat(index) * stepX,
                    y: insetY + CGFloat(normalized) * drawableHeight
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.line(to: point)
                }
            }

            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func downsample(_ values: [Double], to limit: Int) -> [Double] {
        guard values.count > limit else { return values }
        return (0..<limit).map { index in
            values[index * (values.count - 1) / (limit - 1)]
        }
    }
}
