import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let frameAutosaveName = "CodexBuddySettingsWindowGlassCompact"

    private let settings: AppSettings

    init(
        model: UsageViewModel,
        settings: AppSettings,
        historyStore: UsageHistoryStore,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.settings = settings
        let initialPane = SettingsPane.previewPane
        let contentView = SettingsWindowView(
            model: model,
            settings: settings,
            historyStore: historyStore,
            onCheckForUpdates: onCheckForUpdates,
            initialPane: initialPane
        )
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = SettingsCopy.settingsTitle(settings.language)
        window.setContentSize(
            NSSize(width: 540, height: initialPane.contentHeight)
        )
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
            NSSize(width: 540, height: initialPane.contentHeight)
        )

        super.init(window: window)
        shouldCascadeWindows = false
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

    var contentHeight: CGFloat {
        340
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
    let onCheckForUpdates: () -> Void

    @State private var selectedPane: SettingsPane

    init(
        model: UsageViewModel,
        settings: AppSettings,
        historyStore: UsageHistoryStore,
        onCheckForUpdates: @escaping () -> Void,
        initialPane: SettingsPane = .general
    ) {
        self.model = model
        self.settings = settings
        self.historyStore = historyStore
        self.onCheckForUpdates = onCheckForUpdates
        _selectedPane = State(initialValue: initialPane)
    }

    private var copy: SettingsCopy {
        SettingsCopy(locale: settings.language)
    }

    var body: some View {
        ZStack {
            SettingsGlassBackground()

            VStack(spacing: 0) {
                SettingsTabBar(
                    selection: $selectedPane,
                    copy: copy,
                    isLoading: model.isReloading
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                ZStack(alignment: .topLeading) {
                    selectedSection
                        .id(selectedPane)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .padding(18)
            }
        }
        .frame(width: 540, height: selectedPane.contentHeight)
        .preferredColorScheme(.dark)
        .onChange(of: settings.language) { language in
            NSApplication.shared.windows
                .first(where: {
                    $0.frameAutosaveName == SettingsWindowController.frameAutosaveName
                })?
                .title = SettingsCopy.settingsTitle(language)
        }
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch selectedPane {
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
                    .frame(width: 240)
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

                MenuBarSettingsPreview(
                    reading: model.reading,
                    settings: settings,
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
            }
        }
    }

    private var dataSection: some View {
        SettingsPage(
            title: copy.dataAndMaintenance,
            detail: copy.dataDescription
        ) {
            SettingsGlassCard {
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
                    SettingsActionButton(copy.checkForUpdates, systemImage: "sparkles") {
                        onCheckForUpdates()
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

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SettingsPane.allCases) { pane in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selection = pane
                    }
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    let copy: SettingsCopy

    private var remaining: Double {
        Double(reading?.tightestWindow?.remainingPercent ?? 50)
    }

    private var tint: Color {
        if remaining < 20 { return .red }
        if remaining > 80 { return .green }
        return .primary
    }

    private var title: String {
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
    var exportCSV: String { isEnglish ? "Export CSV" : "导出 CSV" }
    var diagnosticReport: String { isEnglish ? "Diagnostics" : "诊断报告" }

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
