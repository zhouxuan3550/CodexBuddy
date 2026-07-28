import AppKit
import Combine
import SwiftUI

/// Applies one predetermined content height for each settings pane. Keeping
/// the dimensions deterministic avoids SwiftUI/AppKit feedback loops while
/// the user is switching pages.
@MainActor
final class SettingsPaneSizer {
    // The hosting view lays out (and reports preferences) before the window
    // exists; remember the request so it can be applied once attached.
    private(set) var pendingHeight: CGFloat?

    weak var window: NSWindow? {
        didSet {
            guard window != nil, let pendingHeight else { return }
            drive(height: pendingHeight)
        }
    }

    /// Applies a pane height synchronously. There is intentionally no frame
    /// animation: the page and its window size change together in one step.
    func drive(height: CGFloat) {
        pendingHeight = height
        guard let window else { return }
        let contentRect = NSRect(x: 0, y: 0, width: SettingsWindowController.contentWidth, height: height)
        let targetSize = window.frameRect(forContentRect: contentRect).size
        guard abs(window.frame.height - targetSize.height) > 0.1 else { return }
        var frame = window.frame
        let topY = frame.maxY
        frame.size = targetSize
        frame.origin.y = topY - targetSize.height
        window.setFrame(frame, display: false)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    // A new autosave key lets existing installs recover from older oversized frames.
    static let frameAutosaveName = "CodexBuddySettingsWindowGlassCompactV2"
    static let contentWidth: CGFloat = 540

    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    init(
        model: UsageViewModel,
        settings: AppSettings,
        historyStore: UsageHistoryStore,
        activityStore: UsageActivityStore,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.settings = settings
        let initialPane = SettingsPane.previewPane
        let sizer = SettingsPaneSizer()
        let contentView = SettingsWindowView(
            model: model,
            settings: settings,
            historyStore: historyStore,
            activityStore: activityStore,
            onCheckForUpdates: onCheckForUpdates,
            sizer: sizer,
            initialPane: initialPane
        )
        let hostingController = NSHostingController(rootView: contentView)
        // The pane sizer is the only thing allowed to drive the window size.
        hostingController.sizingOptions = []
        let window = NSWindow(contentViewController: hostingController)
        window.title = SettingsCopy.settingsTitle(settings.language)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(Self.frameAutosaveName)
        window.setContentSize(
            NSSize(width: Self.contentWidth, height: initialPane.contentHeight)
        )
        // Center only on first launch; afterwards restore the user's saved frame.
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        sizer.window = window
        // A saved frame may belong to a different pane; normalize it before
        // the first draw so opening Settings never visibly jumps.
        sizer.drive(height: initialPane.contentHeight)

        super.init(window: window)
        shouldCascadeWindows = false

        // Keep the window title in sync with the app language.
        settings.$language
            .removeDuplicates()
            .sink { [weak self] language in
                self?.window?.title = SettingsCopy.settingsTitle(language)
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        settings.refreshLaunchAtLoginState()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case display
    case refresh
    case data

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .display: return "menubar.rectangle"
        case .refresh: return "bell"
        case .data: return "externaldrive"
        }
    }

    /// Fixed, tested pane sizes. Do not derive these from GeometryReader:
    /// measurement changes during a transition were the source of the long
    /// standing settings-window jitter.
    var contentHeight: CGFloat {
        switch self {
        case .general: return 356
        case .display: return 470
        case .refresh: return 370
        case .data: return 400
        }
    }

    static var previewPane: SettingsPane {
        guard let value = ProcessInfo.processInfo.environment["CODEX_BUDDY_SETTINGS_PANE"],
              let pane = SettingsPane(rawValue: value) else {
            return .general
        }
        return pane
    }
}

@MainActor
private struct SettingsWindowView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject var settings: AppSettings

    let historyStore: UsageHistoryStore
    @ObservedObject var activityStore: UsageActivityStore
    let onCheckForUpdates: () -> Void
    let sizer: SettingsPaneSizer

    @State private var selectedPane: SettingsPane

    init(
        model: UsageViewModel,
        settings: AppSettings,
        historyStore: UsageHistoryStore,
        activityStore: UsageActivityStore,
        onCheckForUpdates: @escaping () -> Void,
        sizer: SettingsPaneSizer,
        initialPane: SettingsPane = .general
    ) {
        self.model = model
        self.settings = settings
        self.historyStore = historyStore
        self.activityStore = activityStore
        self.onCheckForUpdates = onCheckForUpdates
        self.sizer = sizer
        _selectedPane = State(initialValue: initialPane)
    }

    private var copy: SettingsCopy {
        SettingsCopy(locale: settings.language)
    }

    var body: some View {
        ZStack {
            SettingsGlassBackground()

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    SettingsTabBar(
                        selection: $selectedPane,
                        copy: copy,
                        isLoading: model.isReloading,
                        onSelect: selectPane
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                }
                ZStack(alignment: .topLeading) {
                    selectedSection
                        .id(selectedPane)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .padding(18)
            }
        }
        .frame(
            width: SettingsWindowController.contentWidth,
            height: selectedPane.contentHeight
        )
        .preferredColorScheme(.dark)
    }

    private func selectPane(_ pane: SettingsPane) {
        guard pane != selectedPane else { return }
        // Resize first, then replace content without an animation. This is a
        // single AppKit transaction instead of a sequence of layout passes.
        sizer.drive(height: pane.contentHeight)
        selectedPane = pane
    }

    @ViewBuilder
    private func paneSection(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            generalSection
        case .display:
            displaySection
        case .refresh:
            refreshSection
        case .data:
            dataSection
        }
    }

    private var selectedSection: some View {
        paneSection(selectedPane)
    }

    private var launchAtLoginDetail: String {
        if let error = settings.settingsError {
            return error
        }
        if settings.launchAtLoginIsUpdating {
            return copy.launchAtLoginUpdating
        }
        if settings.launchAtLoginRequiresApproval {
            return copy.launchAtLoginApproval
        }
        if settings.launchAtLoginEnabled {
            return copy.launchAtLoginOn
        }
        return copy.launchAtLoginDetail
    }

    private var generalSection: some View {
        SettingsPage(
            title: copy.general,
            detail: copy.generalDescription
        ) {
            SettingsGlassCard {
                SettingsRow(title: copy.language, detail: copy.languageDetail) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(copy.languageName(language)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                SettingsDivider()

                SettingsRow(title: copy.launchAtLogin, detail: launchAtLoginDetail) {
                    HStack(spacing: 8) {
                        if settings.launchAtLoginRequiresApproval {
                            Button(copy.reviewLoginItems) {
                                settings.openLoginItemsSettings()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.medium))
                        }

                        if settings.launchAtLoginIsUpdating {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Toggle("", isOn: Binding(
                            get: { settings.launchAtLoginEnabled },
                            set: { settings.setLaunchAtLoginEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(settings.launchAtLoginIsUpdating)
                    }
                }
            }

            SettingsAboutCard(copy: copy, onCheckForUpdates: onCheckForUpdates)
        }
    }

    private var displaySection: some View {
        SettingsPage(
            title: copy.display,
            detail: copy.displayDescription
        ) {
            SettingsGlassCard {
                SettingsRow(title: copy.floatingWidget, detail: copy.floatingWidgetDetail) {
                    Toggle("", isOn: $settings.floatingWidgetEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(title: copy.menuBarStyle, detail: copy.menuBarStyleDetail) {
                    Picker("", selection: $settings.menuBarMode) {
                        ForEach(StatusDisplayMode.allCases, id: \.self) { mode in
                            Text(copy.menuBarModeName(mode)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                if settings.menuBarMode == .allWindows {
                    SettingsDivider()

                    HStack(spacing: 18) {
                        Toggle(copy.shortWindow, isOn: $settings.showShortWindow)
                        Toggle(copy.weekWindow, isOn: $settings.showWeekWindow)
                        Spacer()
                    }
                    .toggleStyle(.checkbox)
                    .font(.caption.weight(.medium))
                }

                SettingsDivider()

                SettingsRow(title: copy.sparkline, detail: copy.sparklineDetail) {
                    Toggle("", isOn: $settings.menuBarSparkline)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(title: copy.globalHotkey, detail: copy.globalHotkeyDetail) {
                    Toggle("", isOn: $settings.globalHotkeyEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                MenuBarSettingsPreview(
                    reading: model.reading,
                    settings: settings,
                    activityStore: activityStore,
                    copy: copy
                )
            }
        }
    }

    private var refreshSection: some View {
        SettingsPage(
            title: copy.refreshAndAlerts,
            detail: copy.refreshDescription
        ) {
            SettingsGlassCard {
                SettingsRow(title: copy.refreshInterval, detail: copy.refreshIntervalDetail) {
                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(AppSettings.refreshIntervals, id: \.self) { interval in
                            Text(copy.intervalName(interval)).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                SettingsDivider()

                SettingsRow(title: copy.lowUsageAlert, detail: copy.lowUsageAlertDetail) {
                    Toggle("", isOn: $settings.notificationsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if settings.notificationsEnabled {
                    SettingsDivider()

                    SettingsRow(title: copy.alertThreshold, detail: copy.alertThresholdDetail) {
                        Picker("", selection: $settings.notificationThreshold) {
                            ForEach(AppSettings.notificationThresholds, id: \.self) { threshold in
                                Text("\(Int(threshold))%").tag(threshold)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                }

                SettingsDivider()

                SettingsRow(title: copy.weeklyReserve, detail: copy.weeklyReserveDetail) {
                    Picker("", selection: $settings.weeklyReservePercent) {
                        ForEach(AppSettings.weeklyReserveOptions, id: \.self) { reserve in
                            Text(copy.reserveName(reserve)).tag(reserve)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
        }
    }

    private var dataSection: some View {
        SettingsPage(
            title: copy.dataAndMaintenance,
            detail: copy.dataDescription
        ) {
            SettingsGlassCard {
                DataHealthSummary(
                    health: UsageDataHealth.snapshot(
                        reading: model.reading,
                        issue: model.issue,
                        historySamples: historyStore.records7d().count
                    ),
                    copy: copy
                )

                SettingsDivider()

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.dataSource)
                            .font(.subheadline.weight(.semibold))
                        Text(
                            model.confidenceText(language: settings.language)
                                ?? model.detailText(language: settings.language)
                        )
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(2)
                        Text(model.updatedText(language: settings.language))
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.38))
                    }

                    Spacer()

                    StatusPill(
                        text: model.reading == nil ? copy.unavailable : copy.available,
                        isAvailable: model.reading != nil
                    )
                }

                SettingsDivider()

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    SettingsActionButton(copy.refreshNow, systemImage: "arrow.clockwise") {
                        Task { await model.reload() }
                    }
                    SettingsActionButton(copy.officialUsage, systemImage: "arrow.up.right.square") {
                        model.openOfficialUsagePage()
                    }
                    SettingsActionButton(copy.exportCSV, systemImage: "tablecells") {
                        CSVExporter.export(historyStore: historyStore, language: settings.language)
                    }
                    SettingsActionButton(
                        copy.diagnosticReport,
                        systemImage: "doc.text.magnifyingglass"
                    ) {
                        DiagnosticExporter.export(
                            reading: model.reading,
                            settings: settings,
                            historyStore: historyStore,
                            language: settings.language
                        )
                    }
                }
            }
        }
    }
}

private struct DataHealthSummary: View {
    let health: UsageDataHealth.Snapshot
    let copy: SettingsCopy

    private var tint: Color {
        switch health.state {
        case .current: return Color(red: 0.18, green: 0.83, blue: 0.60)
        case .stale: return .orange
        case .attention: return Color(red: 1, green: 0.56, blue: 0.18)
        case .unavailable: return Color.white.opacity(0.45)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: copy.dataHealthSymbol(health.state))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(copy.dataHealthTitle(health.state))
                    .font(.subheadline.weight(.semibold))
                Text(copy.dataHealthDetail(health))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.50))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(copy.dataHealthPill(health.state))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.12), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsGlassBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Color(red: 0.055, green: 0.060, blue: 0.070)
                .opacity(0.80)
        }
        .ignoresSafeArea()
    }
}

private struct SettingsTabBar: View {
    @Binding var selection: SettingsPane
    let copy: SettingsCopy
    let isLoading: Bool
    let onSelect: (SettingsPane) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SettingsPane.allCases) { pane in
                Button {
                    onSelect(pane)
                } label: {
                    Label(copy.paneTitle(pane), systemImage: pane.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    selection == pane
                        ? Color.white
                        : Color.white.opacity(0.54)
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            selection == pane
                                ? Color.white.opacity(0.13)
                                : Color.clear
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            selection == pane
                                ? Color.white.opacity(0.12)
                                : Color.clear,
                            lineWidth: 1
                        )
                )
            }

            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .padding(.leading, 4)
            }
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    init(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SettingsGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String
    let control: Control

    init(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.50))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 18)
            control
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
    }
}

private struct SettingsActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

private struct StatusPill: View {
    let text: String
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isAvailable ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill((isAvailable ? Color.green : Color.secondary).opacity(0.12))
        )
    }
}

private struct MenuBarSettingsPreview: View {
    let reading: UsageReading?
    @ObservedObject var settings: AppSettings
    @ObservedObject var activityStore: UsageActivityStore
    let copy: SettingsCopy

    private var remaining: Double {
        Double(reading?.tightestWindow?.remainingPercent ?? 50)
    }

    private var tint: Color {
        if settings.menuBarMode == .todayTokens { return .primary }
        if remaining < 20 { return .red }
        if remaining > 80 { return .green }
        return .primary
    }

    private var title: String {
        if settings.menuBarMode == .todayTokens {
            let formatter = UIDateFormatters.formatter(
                dateFormat: "yyyy-MM-dd",
                localeIdentifier: "en_US_POSIX"
            )
            let tokens = activityStore.dailyTokens[formatter.string(from: Date())] ?? 0
            return "T \(TokenFormat.compact(tokens, language: settings.language))"
        }
        guard let reading else {
            return settings.menuBarMode == .tightest ? "--%" : "H --% W --%"
        }
        let segments = reading.menuBarSegments(
            mode: settings.menuBarMode,
            showShortWindow: settings.showShortWindow,
            showWeekWindow: settings.showWeekWindow
        )
        return segments.isEmpty
            ? (settings.menuBarMode == .tightest ? "--%" : "H --% W --%")
            : segments.map(\.text).joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(copy.preview)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.48))

            Spacer()

            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if settings.menuBarSparkline {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.20))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }
}

private struct SettingsAboutCard: View {
    let copy: SettingsCopy
    let onCheckForUpdates: () -> Void

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let version else { return "—" }
        return build.map { "v\(version) (\($0))" } ?? "v\(version)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(ProductIdentity.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text(versionText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(
                    URL(string: "https://github.com/\(ProductIdentity.repository)")!
                )
            } label: {
                Label(copy.viewOnGitHub, systemImage: "link")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderless)

            Button {
                onCheckForUpdates()
            } label: {
                Label(copy.checkForUpdates, systemImage: "sparkles")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SettingsCopy {
    let locale: AppLanguage

    static func settingsTitle(_ language: AppLanguage) -> String {
        language.resolved == .english ? "CodexBuddy Settings" : "CodexBuddy 设置"
    }

    private var isEnglish: Bool {
        locale.resolved == .english
    }

    var subtitle: String {
        isEnglish ? "Make usage monitoring work the way you do." : "让用量监控更符合你的使用习惯"
    }

    var general: String { isEnglish ? "General" : "常规" }
    var generalDescription: String {
        isEnglish ? "Language and startup behavior." : "语言与启动方式"
    }
    var language: String { isEnglish ? "Display language" : "显示语言" }
    var languageDetail: String {
        isEnglish ? "Changes menus and this window immediately." : "菜单和设置窗口会立即切换语言"
    }
    var launchAtLogin: String { isEnglish ? "Launch at login" : "登录时启动" }
    var launchAtLoginDetail: String {
        isEnglish ? "Keep usage available after you sign in to your Mac." : "登录 Mac 后自动运行 CodexBuddy"
    }
    var launchAtLoginUpdating: String {
        isEnglish ? "Updating the macOS login item…" : "正在更新 macOS 登录项…"
    }
    var launchAtLoginApproval: String {
        isEnglish ? "Registered. Allow it in System Settings to finish." : "已注册，需要在系统设置中允许"
    }
    var launchAtLoginOn: String {
        isEnglish ? "On. CodexBuddy will run after you sign in." : "已开启，登录 Mac 后会自动运行"
    }
    var reviewLoginItems: String { isEnglish ? "Review" : "去允许" }

    var display: String { isEnglish ? "Display" : "显示" }
    var displayDescription: String {
        isEnglish ? "Control the menu bar and floating widget." : "控制菜单栏与桌面悬浮组件"
    }
    var floatingWidget: String { isEnglish ? "Floating usage widget" : "桌面悬浮用量" }
    var floatingWidgetDetail: String {
        isEnglish ? "Show a compact widget. Click it to view details." : "显示精简悬浮窗，单击后展开详情"
    }
    var menuBarStyle: String { isEnglish ? "Menu bar style" : "菜单栏样式" }
    var menuBarStyleDetail: String {
        isEnglish ? "Choose how remaining usage appears in the menu bar." : "选择菜单栏中剩余用量的显示方式"
    }
    var shortWindow: String { isEnglish ? "5-hour usage" : "5 小时用量" }
    var weekWindow: String { isEnglish ? "Weekly usage" : "每周用量" }
    var sparkline: String { isEnglish ? "Mini trend line" : "迷你趋势线" }
    var sparklineDetail: String {
        isEnglish
            ? "Draw a tiny sparkline next to the menu bar value."
            : "在菜单栏数值旁绘制一条迷你趋势线"
    }
    var globalHotkey: String { isEnglish ? "Global shortcut ⌥⌘U" : "全局快捷键 ⌥⌘U" }
    var globalHotkeyDetail: String {
        isEnglish
            ? "Toggle the usage dashboard from anywhere."
            : "在任意应用中按下即可打开 / 收起用量详情"
    }
    var preview: String { isEnglish ? "Live preview" : "实时预览" }

    var refreshAndAlerts: String { isEnglish ? "Refresh & Alerts" : "刷新与提醒" }
    var refreshDescription: String {
        isEnglish ? "Choose update frequency and warning level." : "设置更新频率和预警阈值"
    }
    var refreshInterval: String { isEnglish ? "Refresh interval" : "刷新频率" }
    var refreshIntervalDetail: String {
        isEnglish ? "How often CodexBuddy checks for new usage." : "CodexBuddy 自动检查最新用量的频率"
    }
    var lowUsageAlert: String { isEnglish ? "Low usage alert" : "低用量提醒" }
    var lowUsageAlertDetail: String {
        isEnglish ? "Notify you when remaining weekly usage is low." : "每周剩余用量偏低时发送系统通知"
    }
    var alertThreshold: String { isEnglish ? "Alert threshold" : "提醒阈值" }
    var alertThresholdDetail: String {
        isEnglish ? "Send the alert once usage falls below this level." : "剩余用量首次低于此数值时提醒"
    }
    var weeklyReserve: String { isEnglish ? "Weekly safety reserve" : "每周安全余量" }
    var weeklyReserveDetail: String {
        isEnglish
            ? "Keeps this amount as a planning buffer; it never limits Codex."
            : "为本周后续任务预留缓冲，不会限制 Codex 使用"
    }

    func reserveName(_ value: Int) -> String {
        value == 0 ? (isEnglish ? "None" : "不预留") : "\(value)%"
    }

    var dataAndMaintenance: String { isEnglish ? "Data & Maintenance" : "数据与维护" }
    var dataDescription: String {
        isEnglish ? "Inspect the source, export data, and update the app." : "查看数据来源、导出记录与维护应用"
    }
    var dataSource: String { isEnglish ? "Current data source" : "当前数据来源" }
    var available: String { isEnglish ? "Available" : "可用" }
    var unavailable: String { isEnglish ? "Waiting" : "等待数据" }
    var refreshNow: String { isEnglish ? "Refresh now" : "立即刷新" }
    var officialUsage: String { isEnglish ? "Official Usage" : "官方 Usage" }
    var checkForUpdates: String { isEnglish ? "Check updates" : "检查更新" }
    var viewOnGitHub: String { isEnglish ? "GitHub" : "GitHub 仓库" }
    var exportCSV: String { isEnglish ? "Export CSV" : "导出 CSV" }
    var diagnosticReport: String { isEnglish ? "Diagnostics" : "诊断报告" }

    func dataHealthTitle(_ state: UsageDataHealth.State) -> String {
        switch state {
        case .current: return isEnglish ? "Usage data is current" : "用量数据可信"
        case .stale: return isEnglish ? "Usage data may be stale" : "用量数据可能过期"
        case .attention: return isEnglish ? "Usage data needs attention" : "用量数据需要关注"
        case .unavailable: return isEnglish ? "Usage data is unavailable" : "暂未获取用量数据"
        }
    }

    func dataHealthPill(_ state: UsageDataHealth.State) -> String {
        switch state {
        case .current: return isEnglish ? "Current" : "可信"
        case .stale: return isEnglish ? "Stale" : "过期"
        case .attention: return isEnglish ? "Check" : "检查"
        case .unavailable: return isEnglish ? "Waiting" : "等待"
        }
    }

    func dataHealthSymbol(_ state: UsageDataHealth.State) -> String {
        switch state {
        case .current: return "checkmark.shield.fill"
        case .stale: return "clock.badge.exclamationmark"
        case .attention: return "exclamationmark.triangle.fill"
        case .unavailable: return "arrow.clockwise.circle"
        }
    }

    func dataHealthDetail(_ health: UsageDataHealth.Snapshot) -> String {
        let source = health.source.map { $0.displayName(language: locale) }
            ?? (isEnglish ? "No source yet" : "尚无数据来源")
        let samples = isEnglish
            ? "\(health.historySamples) local samples (7d)"
            : "近 7 天 \(health.historySamples) 条本地样本"
        return "\(source) · \(samples)"
    }

    func paneTitle(_ pane: SettingsPane) -> String {
        switch pane {
        case .general:
            return general
        case .display:
            return display
        case .refresh:
            return isEnglish ? "Alerts" : "提醒"
        case .data:
            return isEnglish ? "Data" : "数据"
        }
    }

    func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .system:
            return isEnglish ? "System" : "跟随系统"
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    func menuBarModeName(_ mode: StatusDisplayMode) -> String {
        switch mode {
        case .allWindows:
            return isEnglish ? "H / W" : "H / W"
        case .tightest:
            return isEnglish ? "Tightest" : "最紧张额度"
        case .todayTokens:
            return isEnglish ? "Today" : "今日 Tokens"
        }
    }

    func intervalName(_ interval: TimeInterval) -> String {
        switch interval {
        case 5:
            return isEnglish ? "5 seconds" : "5 秒"
        case 15:
            return isEnglish ? "15 seconds" : "15 秒"
        case 30:
            return isEnglish ? "30 seconds" : "30 秒"
        case 60:
            return isEnglish ? "1 minute" : "1 分钟"
        default:
            return "\(Int(interval))s"
        }
    }
}
