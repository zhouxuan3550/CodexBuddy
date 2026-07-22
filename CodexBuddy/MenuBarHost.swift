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

    init(model: UsageViewModel, settings: AppSettings, historyStore: UsageHistoryStore, activityStore: UsageActivityStore, updateChecker: UpdateChecker, autoUpdater: AutoUpdater) {
        self.model = model
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
        if let reading = model.reading {
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
        button.setAccessibilityLabel(model.statusText)
        if let reading = model.reading {
            button.toolTip = "\(reading.completeStatusText) · \(model.updatedText(language: language))"
        } else {
            button.toolTip = ProductIdentity.name
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
