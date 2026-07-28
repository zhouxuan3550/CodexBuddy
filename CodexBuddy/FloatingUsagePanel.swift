import AppKit
import Combine
import SwiftUI

private enum FloatingUsageMetrics {
    static let compactSize = CGSize(width: 84, height: 52)
    static let expandedSize = CGSize(width: 326, height: 236)
    static let savedTopLeftKey = "floatingWidgetTopLeft"
}

@MainActor
private final class FloatingUsagePresentation: ObservableObject {
    @Published var isExpanded = false
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

@MainActor
final class FloatingUsagePanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    private let defaults: UserDefaults
    private var hasPositionedPanel = false
    private var anchorTopLeft: NSPoint?
    private var isProgrammaticResize = false
    private let presentation = FloatingUsagePresentation()
    private var expansionCancellable: AnyCancellable?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    init(
        model: UsageViewModel,
        settings: AppSettings,
        onOpenDetails: @escaping () -> Void,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: FloatingUsageMetrics.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let rootView = FloatingUsageView(
            model: model,
            settings: settings,
            presentation: presentation,
            onOpenDetails: onOpenDetails
        )
        let hostingView = DraggableHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: FloatingUsageMetrics.compactSize)
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView = hostingView
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.title = "\(ProductIdentity.name) \(L10n.text(.usage, language: settings.language))"
        panel.setAccessibilityLabel(panel.title)

        expansionCancellable = presentation.$isExpanded
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isExpanded in
                self?.setExpanded(isExpanded, animated: true)
                self?.updateOutsideClickMonitors(isExpanded: isExpanded)
            }
    }

    func show() {
        if !hasPositionedPanel {
            restoreOrPlacePanel()
            hasPositionedPanel = true
        }
        presentation.isExpanded = false
        setExpanded(false, animated: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        presentation.isExpanded = false
        updateOutsideClickMonitors(isExpanded: false)
        panel.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticResize else { return }
        anchorTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        saveTopLeft()
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        let targetSize = expanded
            ? FloatingUsageMetrics.expandedSize
            : FloatingUsageMetrics.compactSize
        let topLeft = anchorTopLeft
            ?? NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let frame = clampedFrame(size: targetSize, topLeft: topLeft)

        guard animated else {
            isProgrammaticResize = true
            panel.setFrame(frame, display: true)
            isProgrammaticResize = false
            return
        }

        isProgrammaticResize = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.22 : 0.18
            context.timingFunction = CAMediaTimingFunction(
                name: expanded ? .easeOut : .easeInEaseOut
            )
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isProgrammaticResize = false
            }
        }
    }

    private func restoreOrPlacePanel() {
        let size = FloatingUsageMetrics.compactSize
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)

        let topLeft: NSPoint
        if let saved = defaults.string(forKey: FloatingUsageMetrics.savedTopLeftKey) {
            topLeft = NSPointFromString(saved)
        } else {
            topLeft = NSPoint(
                x: visibleFrame.maxX - size.width - 28,
                y: visibleFrame.maxY - 28
            )
        }
        anchorTopLeft = topLeft
        panel.setFrame(clampedFrame(size: size, topLeft: topLeft), display: false)
    }

    private func clampedFrame(size: CGSize, topLeft: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first {
            $0.frame.contains(topLeft)
        } ?? panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)

        let x = min(max(topLeft.x, visible.minX + 12), visible.maxX - size.width - 12)
        let maxTop = visible.maxY - 12
        let minTop = visible.minY + size.height + 12
        let y = min(max(topLeft.y, minTop), maxTop) - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func saveTopLeft() {
        let topLeft = anchorTopLeft
            ?? NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        defaults.set(NSStringFromPoint(topLeft), forKey: FloatingUsageMetrics.savedTopLeftKey)
    }

    private func updateOutsideClickMonitors(isExpanded: Bool) {
        removeOutsideClickMonitors()
        guard isExpanded else { return }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.collapseIfClickIsOutside()
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.collapseIfClickIsOutside()
            }
        }
    }

    private func collapseIfClickIsOutside() {
        guard presentation.isExpanded,
              !panel.frame.contains(NSEvent.mouseLocation) else {
            return
        }
        presentation.isExpanded = false
    }

    private func removeOutsideClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }
}

private struct FloatingUsageView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var presentation: FloatingUsagePresentation
    let onOpenDetails: () -> Void

    private var language: AppLanguage { settings.language }
    private var reading: UsageReading? { model.reading }
    private var featuredWindow: QuotaWindow? { reading?.tightestWindow }
    private var isExpanded: Bool { presentation.isExpanded }
    private var semanticColor: Color {
        guard let featuredWindow else { return .secondary }
        return color(for: featuredWindow.remainingPercent)
    }

    var body: some View {
        ZStack {
            background

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
            } else {
                compactContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(
            width: isExpanded
                ? FloatingUsageMetrics.expandedSize.width
                : FloatingUsageMetrics.compactSize.width,
            height: isExpanded
                ? FloatingUsageMetrics.expandedSize.height
                : FloatingUsageMetrics.compactSize.height
        )
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 22 : 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isExpanded ? 22 : 17, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: isExpanded ? 20 : 12, y: isExpanded ? 10 : 6)
        .contentShape(RoundedRectangle(cornerRadius: isExpanded ? 22 : 17, style: .continuous))
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isExpanded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var background: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(red: 0.055, green: 0.063, blue: 0.078).opacity(0.88)
        }
    }

    private var compactContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(featuredPrefix)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(featuredPercent)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(semanticColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            presentation.isExpanded = true
        }
        .help(copy.clickForDetails)
        .accessibilityAction {
            presentation.isExpanded = true
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ProductIdentity.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(planText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(featuredPercent)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(semanticColor)
                    Text(copy.remaining)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Button {
                    presentation.isExpanded = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.09), in: Circle())
                }
                .buttonStyle(.plain)
                .help(copy.collapse)
            }

            Divider().overlay(Color.white.opacity(0.08))

            VStack(spacing: 11) {
                QuotaRow(
                    title: copy.shortWindow,
                    prefix: "H",
                    window: reading?.shortWindow,
                    language: language
                )
                QuotaRow(
                    title: copy.weekWindow,
                    prefix: "W",
                    window: reading?.weekWindow,
                    language: language
                )
            }

            HStack(spacing: 12) {
                if let credits = reading?.credits?.finiteBalance {
                    Label("\(copy.credits) \(credits)", systemImage: "bolt.fill")
                        .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1))
                }

                Spacer(minLength: 6)

                if let reading {
                    Label(
                        reading.source.displayName(language: language),
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)

            HStack {
                Text(model.updatedText(language: language))
                    .lineLimit(1)

                Spacer()

                Button {
                    presentation.isExpanded = false
                    onOpenDetails()
                } label: {
                    Label(copy.details, systemImage: "chart.bar.xaxis")
                }
                .buttonStyle(.plain)

                Button {
                    Task { await model.reload() }
                } label: {
                    HStack(spacing: 5) {
                        if model.isReloading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(model.isReloading ? copy.refreshing : copy.refresh)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isReloading)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .foregroundStyle(Color.white.opacity(0.95))
    }

    private var featuredPrefix: String {
        guard let window = featuredWindow else { return "—" }
        return reading?.prefix(for: window) ?? "—"
    }

    private var featuredPercent: String {
        featuredWindow.map { "\($0.remainingPercent)%" } ?? "--%"
    }

    private var planText: String {
        guard let name = reading?.planName, !name.isEmpty else { return copy.usageMonitor }
        return "\(copy.plan) · \(name.uppercased())"
    }

    private var copy: FloatingUsageCopy {
        FloatingUsageCopy(language: language)
    }

    private var accessibilityText: String {
        "\(ProductIdentity.name), \(featuredPrefix) \(featuredPercent), \(copy.remaining)"
    }

    private func color(for percent: Int) -> Color {
        switch QuotaLevel.forRemaining(percent) {
        case .critical:
            return Color(red: 1, green: 0.28, blue: 0.28)
        case .standard:
            return Color.white.opacity(0.92)
        case .healthy:
            return Color(red: 0.18, green: 0.83, blue: 0.60)
        }
    }
}

private struct QuotaRow: View {
    let title: String
    let prefix: String
    let window: QuotaWindow?
    let language: AppLanguage

    private var percent: Int { window?.remainingPercent ?? 0 }
    private var tint: Color {
        guard window != nil else { return .secondary }
        switch QuotaLevel.forRemaining(percent) {
        case .critical:
            return Color(red: 1, green: 0.28, blue: 0.28)
        case .standard:
            return Color(red: 0.35, green: 0.65, blue: 1)
        case .healthy:
            return Color(red: 0.18, green: 0.83, blue: 0.60)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 7) {
                    Text(prefix)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(width: 20, height: 20)
                        .background(tint.opacity(0.16), in: Circle())
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }

                Spacer()

                Text(window.map { "\($0.remainingPercent)%" } ?? "--%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(resetText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(percent), total: 100)
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }

    private var resetText: String {
        guard let resetAt = window?.resetAt else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: language.resolved == .simplifiedChinese ? "zh_CN" : "en_US"
        )
        formatter.dateFormat = window?.isWeekly == true
            ? (language.resolved == .simplifiedChinese ? "M月d日" : "MMM d")
            : "HH:mm"
        let prefix = language.resolved == .simplifiedChinese ? "重置" : "resets"
        return "\(prefix) \(formatter.string(from: resetAt))"
    }
}

private struct FloatingUsageCopy {
    let language: AppLanguage

    private var chinese: Bool { language.resolved == .simplifiedChinese }

    var remaining: String { chinese ? "剩余" : "remaining" }
    var shortWindow: String { chinese ? "短时用量" : "Short window" }
    var weekWindow: String { chinese ? "每周用量" : "Weekly window" }
    var credits: String { chinese ? "Credits" : "Credits" }
    var plan: String { chinese ? "套餐" : "Plan" }
    var usageMonitor: String { chinese ? "用量监控" : "Usage monitor" }
    var refresh: String { chinese ? "刷新" : "Refresh" }
    var refreshing: String { chinese ? "刷新中" : "Refreshing" }
    var details: String { chinese ? "详情" : "Details" }
    var clickForDetails: String { chinese ? "单击查看详情" : "Click for details" }
    var collapse: String { chinese ? "收起" : "Collapse" }
}
