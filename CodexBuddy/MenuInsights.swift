import Cocoa

// Usage insights, exports, and update actions
extension MenuBarCoordinator {
    // MARK: - Updates and menu insights

    func observeUpdateChecker() {
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

    func handleUpdateState(_ state: AutoUpdater.UpdateState) {
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

    func makePlanCreditsView(reading: UsageReading) -> NSView {
        var parts: [String] = []
        if let plan = reading.planName {
            parts.append("\(L10n.text(.planType, language: language)): \(plan.capitalized)")
        }
        if let credits = reading.credits {
            if credits.isUnlimited {
                parts.append("\(L10n.text(.creditsBalance, language: language)): ∞")
            } else if let balance = credits.finiteBalance {
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

    func makeEstimateView(text: String) -> NSView {
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

    func makeSectionHeaderView(title: String) -> NSView {
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

    func depletionEstimateText() -> String? {
        guard let reading = model.reading, let window = reading.tightestWindow else { return nil }
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

    func updateMenuItemTitle() -> String {
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

    @objc func exportDiagnostic() {
        DiagnosticExporter.export(
            reading: model.reading,
            settings: settings,
            historyStore: historyStore,
            language: language
        )
    }

    @objc func checkForUpdates() {
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

    func observeActivityStore() {
        activityStore.$dailyTokens
            .sink { [weak self] tokens in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.heatmapView?.update(dailyTokens: tokens, language: self.language)
                }
            }
            .store(in: &cancellables)
    }

    @objc func exportCSV() {
        CSVExporter.export(historyStore: historyStore, language: language)
    }
}
