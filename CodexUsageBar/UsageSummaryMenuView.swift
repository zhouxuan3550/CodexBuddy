import AppKit
import Foundation

@MainActor
final class UsageSummaryMenuView: NSView {
    static let preferredWidth: CGFloat = 380
    private static let compactHeight: CGFloat = 240
    private static let expandedHeight: CGFloat = 264

    private let sectionTitleLabel = NSTextField(labelWithString: "")
    private let remainingLabel = NSTextField(labelWithString: "")
    private let nowLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")
    private let resetRelativeLabel = NSTextField(labelWithString: "")
    private let adviceLabel = NSTextField(labelWithString: "")
    private let secondaryWindowLabel = NSTextField(labelWithString: "")
    private let startDot = NSImageView()
    private let endDot = NSImageView()
    private let sourceIcon = NSImageView()
    private let sourceLabel = NSTextField(labelWithString: "")

    init(
        reading: UsageReading?,
        isLoading: Bool,
        detailMessage: String,
        confidenceStatus: String?,
        language: AppLanguage
    ) {
        let hasMultipleWindows = reading?.shortWindow != nil && reading?.weekWindow != nil
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: Self.preferredWidth,
            height: hasMultipleWindows ? Self.expandedHeight : Self.compactHeight
        ))
        buildInterface()
        update(
            reading: reading,
            isLoading: isLoading,
            detailMessage: detailMessage,
            confidenceStatus: confidenceStatus,
            language: language
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        reading: UsageReading?,
        isLoading: Bool,
        detailMessage: String,
        confidenceStatus: String?,
        language: AppLanguage,
        now: Date = Date()
    ) {
        guard let reading, let window = reading.tightestWindow else {
            sectionTitleLabel.stringValue = L10n.text(.usage, language: language)
            remainingLabel.stringValue = "--%"
            remainingLabel.textColor = .labelColor
            nowLabel.stringValue = currentDateText(language: language, now: now)
            resetLabel.stringValue = "--"
            resetRelativeLabel.stringValue = L10n.text(.neverUpdated, language: language)
            adviceLabel.stringValue = detailMessage
            secondaryWindowLabel.isHidden = true
            updateSource(
                text: isLoading ? L10n.text(.refreshing, language: language) : detailMessage,
                color: .secondaryLabelColor,
                symbolName: isLoading ? "arrow.triangle.2.circlepath" : "exclamationmark.circle.fill"
            )
            updateTimelineColor(.tertiaryLabelColor)
            setAccessibilityLabel("\(sectionTitleLabel.stringValue), \(detailMessage)")
            return
        }

        let isWeekly = window.minutes >= 10_080
        sectionTitleLabel.stringValue = isWeekly
            ? (language.resolved == .simplifiedChinese ? "每周用量" : "Weekly usage")
            : (language.resolved == .simplifiedChinese ? "短时用量" : "Short-window usage")
        remainingLabel.stringValue = language.resolved == .simplifiedChinese
            ? "剩余 \(window.remainingPercent)%"
            : "\(window.remainingPercent)% remaining"

        let semanticColor = color(for: window.remainingPercent)
        remainingLabel.textColor = semanticColor
        nowLabel.stringValue = currentDateText(language: language, now: now)
        resetLabel.stringValue = resetDateText(for: window, language: language)
        resetRelativeLabel.stringValue = resetRelativeText(for: window, language: language, now: now)
        adviceLabel.stringValue = adviceText(percent: window.remainingPercent, language: language)
        updateTimelineColor(semanticColor)

        if let otherWindow = otherWindow(in: reading, featured: window) {
            secondaryWindowLabel.stringValue = "\(L10n.text(.otherWindow, language: language)): \(reading.detailLine(for: otherWindow, language: language))"
            secondaryWindowLabel.isHidden = false
        } else {
            secondaryWindowLabel.isHidden = true
        }

        let sourceColor: NSColor = reading.isOutdated(at: now) ? .systemOrange : .systemGreen
        updateSource(
            text: isLoading
                ? "\(confidenceStatus ?? reading.source.displayName(language: language)) · \(L10n.text(.refreshing, language: language))"
                : (confidenceStatus ?? reading.source.displayName(language: language)),
            color: sourceColor,
            symbolName: reading.isOutdated(at: now) ? "exclamationmark.circle.fill" : "circle.fill"
        )

        setAccessibilityLabel(
            "\(sectionTitleLabel.stringValue), \(remainingLabel.stringValue), \(nowLabel.stringValue), \(resetLabel.stringValue), \(adviceLabel.stringValue), \(sourceLabel.stringValue)"
        )
    }

    private func buildInterface() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        // Frosted glass background
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        configureLabel(sectionTitleLabel, size: 18, weight: .medium, color: .labelColor)
        configureLabel(remainingLabel, size: 22, weight: .semibold, color: .labelColor, monospacedDigits: true)
        configureLabel(nowLabel, size: 14, weight: .medium, color: .labelColor)
        configureLabel(resetLabel, size: 14, weight: .medium, color: .labelColor)
        configureLabel(resetRelativeLabel, size: 12, weight: .regular, color: .secondaryLabelColor)
        configureLabel(adviceLabel, size: 13, weight: .regular, color: .secondaryLabelColor)
        configureLabel(secondaryWindowLabel, size: 12, weight: .regular, color: .secondaryLabelColor)
        configureLabel(sourceLabel, size: 13, weight: .medium, color: .secondaryLabelColor)

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 10
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        let header = makeHeader()
        let summaryRow = makeEdgeAlignedRow(leading: sectionTitleLabel, trailing: remainingLabel)
        let datesRow = makeEdgeAlignedRow(leading: nowLabel, trailing: resetLabel)
        let timeline = makeTimeline()
        let relativeRow = makeTrailingRow(resetRelativeLabel)

        let sourceRow = NSStackView(views: [sourceIcon, sourceLabel])
        sourceRow.orientation = .horizontal
        sourceRow.alignment = .centerY
        sourceRow.spacing = 8

        rootStack.addArrangedSubview(header)
        rootStack.addArrangedSubview(makeSeparator())
        rootStack.addArrangedSubview(summaryRow)
        rootStack.addArrangedSubview(datesRow)
        rootStack.addArrangedSubview(timeline)
        rootStack.addArrangedSubview(relativeRow)
        rootStack.addArrangedSubview(adviceLabel)
        rootStack.addArrangedSubview(secondaryWindowLabel)
        rootStack.addArrangedSubview(makeSeparator())
        rootStack.addArrangedSubview(sourceRow)

        rootStack.setCustomSpacing(13, after: header)
        rootStack.setCustomSpacing(13, after: rootStack.arrangedSubviews[1])
        rootStack.setCustomSpacing(14, after: summaryRow)
        rootStack.setCustomSpacing(2, after: datesRow)
        rootStack.setCustomSpacing(0, after: timeline)
        rootStack.setCustomSpacing(12, after: relativeRow)
        rootStack.setCustomSpacing(12, after: adviceLabel)

        for view in [header, summaryRow, datesRow, timeline, relativeRow] {
            view.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -13),
            timeline.heightAnchor.constraint(equalToConstant: 16),
            sourceIcon.widthAnchor.constraint(equalToConstant: 12),
            sourceIcon.heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    private func makeHeader() -> NSStackView {
        let versionLabel = NSTextField(labelWithString: "CodexUsage \(displayVersion())")
        configureLabel(versionLabel, size: 12, weight: .regular, color: .tertiaryLabelColor)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [spacer, versionLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func makeEdgeAlignedRow(leading: NSView, trailing: NSView) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [leading, spacer, trailing])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }

    private func makeTrailingRow(_ view: NSView) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [spacer, view])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    private func makeTimeline() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let track = NSBox()
        track.boxType = .separator
        track.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(track)

        startDot.translatesAutoresizingMaskIntoConstraints = false
        endDot.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(startDot)
        container.addSubview(endDot)

        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            track.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            track.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            startDot.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            startDot.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            startDot.widthAnchor.constraint(equalToConstant: 11),
            startDot.heightAnchor.constraint(equalToConstant: 11),
            endDot.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            endDot.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            endDot.widthAnchor.constraint(equalToConstant: 11),
            endDot.heightAnchor.constraint(equalToConstant: 11)
        ])
        return container
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func configureLabel(
        _ label: NSTextField,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        monospacedDigits: Bool = false
    ) {
        label.font = monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
    }

    private func color(for percent: Int) -> NSColor {
        switch QuotaLevel.forRemaining(percent) {
        case .critical: return .systemRed
        case .standard: return .labelColor
        case .healthy: return .systemGreen
        }
    }

    private func updateTimelineColor(_ color: NSColor) {
        startDot.image = symbol(named: "circle.fill", pointSize: 10)
        startDot.contentTintColor = color
        endDot.image = symbol(named: "circle.fill", pointSize: 10)
        endDot.contentTintColor = .tertiaryLabelColor
    }

    private func otherWindow(in reading: UsageReading, featured: QuotaWindow) -> QuotaWindow? {
        [reading.shortWindow, reading.weekWindow]
            .compactMap { $0 }
            .first { $0 != featured }
    }

    private func currentDateText(language: AppLanguage, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.resolved == .simplifiedChinese ? "zh_CN" : "en_US")
        formatter.dateFormat = language.resolved == .simplifiedChinese ? "M月d日" : "MMM d"
        let date = formatter.string(from: now)
        return language.resolved == .simplifiedChinese ? "现在 · \(date)" : "Now · \(date)"
    }

    private func resetDateText(for window: QuotaWindow, language: AppLanguage) -> String {
        guard let resetAt = window.resetAt else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.resolved == .simplifiedChinese ? "zh_CN" : "en_US")
        formatter.dateFormat = language.resolved == .simplifiedChinese ? "M月d日" : "MMM d"
        let date = formatter.string(from: resetAt)
        return language.resolved == .simplifiedChinese ? "恢复 · \(date)" : "Reset · \(date)"
    }

    private func resetRelativeText(for window: QuotaWindow, language: AppLanguage, now: Date) -> String {
        guard let resetAt = window.resetAt else { return "--" }
        let seconds = resetAt.timeIntervalSince(now)
        guard seconds > 0 else { return L10n.text(.resetExpired, language: language) }

        if seconds >= 86_400 {
            let days = max(1, Int((seconds / 86_400).rounded()))
            return language.resolved == .simplifiedChinese ? "约 \(days) 天后" : "In about \(days) days"
        }
        let hours = max(1, Int(ceil(seconds / 3_600)))
        return language.resolved == .simplifiedChinese ? "约 \(hours) 小时后" : "In about \(hours) hours"
    }

    private func adviceText(percent: Int, language: AppLanguage) -> String {
        switch QuotaLevel.forRemaining(percent) {
        case .critical:
            return language.resolved == .simplifiedChinese
                ? "低于 20%，建议控制使用"
                : "Below 20% — consider limiting usage"
        case .standard:
            return language.resolved == .simplifiedChinese
                ? "当前用量正常"
                : "Usage is within the normal range"
        case .healthy:
            return language.resolved == .simplifiedChinese
                ? "用量充足，可以放心使用"
                : "Plenty of usage remains"
        }
    }

    private func updateSource(text: String, color: NSColor, symbolName: String) {
        sourceIcon.image = symbol(named: symbolName, pointSize: 10)
        sourceIcon.contentTintColor = color
        sourceLabel.stringValue = text
        sourceLabel.textColor = color == .systemOrange ? .systemOrange : .secondaryLabelColor
    }

    private func symbol(named name: String, pointSize: CGFloat) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
    }

    private func displayVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.3.0"
        let parts = version.split(separator: ".")
        if parts.count == 3, parts.last == "0" {
            return "v\(parts.dropLast().joined(separator: "."))"
        }
        return "v\(version)"
    }
}
