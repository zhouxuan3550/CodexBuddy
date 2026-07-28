import AppKit
import Charts
import SwiftUI

@MainActor
final class UsageDashboardWindowController: NSWindowController {
    private let model: UsageViewModel
    private let activityStore: UsageActivityStore

    init(
        model: UsageViewModel,
        settings: AppSettings,
        activityStore: UsageActivityStore
    ) {
        self.model = model
        self.activityStore = activityStore

        let contentView = UsageDashboardView(
            model: model,
            settings: settings,
            activityStore: activityStore
        )
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = UsageDashboardCopy.windowTitle(settings.language)
        window.setContentSize(NSSize(width: 1_040, height: 720))
        window.minSize = NSSize(width: 820, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CodexBuddyUsageDashboard")

        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        activityStore.rescan()
        Task { await model.reload() }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum DashboardRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
}

private struct DailyTokenPoint: Identifiable {
    let date: Date
    let tokens: Int64

    var id: Date { date }
}

@MainActor
private struct UsageDashboardView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var activityStore: UsageActivityStore

    @State private var range: DashboardRange = .month

    private var copy: UsageDashboardCopy {
        UsageDashboardCopy(language: settings.language)
    }

    private var metrics: DashboardMetrics {
        DashboardMetrics(dailyTokens: activityStore.dailyTokens)
    }

    private var chartPoints: [DailyTokenPoint] {
        metrics.points(forLastDays: range.rawValue)
    }

    var body: some View {
        ZStack {
            DashboardGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    metricGrid

                    HStack(alignment: .top, spacing: 16) {
                        tokenChart
                            .frame(maxWidth: .infinity)
                        quotaOverview
                            .frame(width: 310)
                    }

                    activityHeatmap
                }
                .padding(24)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .preferredColorScheme(.dark)
        .onChange(of: settings.language) { language in
            NSApplication.shared.windows
                .first(where: { $0.frameAutosaveName == "CodexBuddyUsageDashboard" })?
                .title = UsageDashboardCopy.windowTitle(language)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(copy.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.52))
            }

            Spacer()

            Button {
                model.openOfficialUsagePage()
            } label: {
                Label(copy.officialUsage, systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)

            Button {
                activityStore.rescan()
                Task { await model.reload() }
            } label: {
                if model.isReloading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(copy.refresh, systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isReloading)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
            spacing: 12
        ) {
            DashboardMetricCard(
                title: copy.totalRecorded,
                value: copy.formatTokens(metrics.total),
                detail: copy.localHistory,
                color: Color(red: 0.12, green: 0.48, blue: 0.95)
            )
            DashboardMetricCard(
                title: copy.today,
                value: copy.formatTokens(metrics.today),
                detail: copy.naturalDay,
                color: Color(red: 0.12, green: 0.48, blue: 0.95)
            )
            DashboardMetricCard(
                title: copy.thisWeek,
                value: copy.formatTokens(metrics.thisWeek),
                detail: copy.naturalWeek,
                color: Color(red: 0.12, green: 0.48, blue: 0.95)
            )
            DashboardMetricCard(
                title: copy.thisMonth,
                value: copy.formatTokens(metrics.thisMonth),
                detail: copy.naturalMonth,
                color: Color(red: 0.12, green: 0.48, blue: 0.95)
            )
        }
    }

    private var tokenChart: some View {
        DashboardGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.tokenTrend)
                            .font(.headline)
                        Text(copy.rangeSummary(range, total: chartPoints.reduce(0) { $0 + $1.tokens }))
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.46))
                    }

                    Spacer()

                    Picker("", selection: $range) {
                        ForEach(DashboardRange.allCases) { item in
                            Text(copy.rangeName(item)).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                if chartPoints.allSatisfy({ $0.tokens == 0 }) {
                    DashboardEmptyState(text: copy.noActivity)
                        .frame(height: 174)
                } else {
                    Chart(chartPoints) { point in
                        BarMark(
                            x: .value(copy.dateAxis, point.date, unit: .day),
                            y: .value(copy.tokenAxis, point.tokens)
                        )
                        .foregroundStyle(Color(red: 0.12, green: 0.48, blue: 0.95))
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 6)) {
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                            AxisValueLabel(format: .dateTime.month().day())
                                .foregroundStyle(Color.white.opacity(0.42))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                            AxisValueLabel {
                                if let tokens = value.as(Int64.self) {
                                    Text(copy.formatAxisTokens(tokens))
                                }
                            }
                            .foregroundStyle(Color.white.opacity(0.42))
                        }
                    }
                    .frame(height: 174)
                }
            }
        }
    }

    private var quotaOverview: some View {
        DashboardGlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(copy.currentQuota)
                        .font(.headline)
                    Spacer()
                    DashboardStatusPill(
                        text: model.reading == nil ? copy.waiting : copy.live,
                        isAvailable: model.reading != nil
                    )
                }

                DashboardQuotaRow(
                    title: copy.shortWindow,
                    prefix: "H",
                    window: model.reading?.shortWindow,
                    language: settings.language
                )

                DashboardQuotaRow(
                    title: copy.weekWindow,
                    prefix: "W",
                    window: model.reading?.weekWindow,
                    language: settings.language
                )

                Divider()
                    .overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 4) {
                    if let planName = model.reading?.planName {
                        DashboardInfoLine(label: copy.plan, value: planName.uppercased())
                    }
                    if let source = model.reading?.source {
                        DashboardInfoLine(
                            label: copy.source,
                            value: source.displayName(language: settings.language)
                        )
                    }
                    DashboardInfoLine(
                        label: copy.updated,
                        value: model.updatedText(language: settings.language)
                    )
                }
            }
        }
    }

    private var activityHeatmap: some View {
        DashboardGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.tokenActivity)
                            .font(.headline)
                        Text(copy.heatmapDetail(activeDays: metrics.activeDays(weeks: 52)))
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.46))
                    }
                    Spacer()
                    HeatmapLegend(copy: copy)
                }

                YearActivityHeatmap(
                    dailyTokens: activityStore.dailyTokens,
                    language: settings.language
                )
            }
        }
    }
}

private struct DashboardGlassBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(red: 0.055, green: 0.060, blue: 0.070).opacity(0.82)
        }
        .ignoresSafeArea()
    }
}

private struct DashboardGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(17)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.052))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 18, y: 9)
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        DashboardGlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
                Text(value)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.38))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DashboardQuotaRow: View {
    let title: String
    let prefix: String
    let window: QuotaWindow?
    let language: AppLanguage

    private var percent: Int { window?.remainingPercent ?? 0 }

    private var tint: Color {
        guard window != nil else { return .secondary }
        switch QuotaLevel.forRemaining(percent) {
        case .critical: return Color(red: 1, green: 0.28, blue: 0.28)
        case .standard: return Color.white.opacity(0.90)
        case .healthy: return Color(red: 0.18, green: 0.83, blue: 0.60)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(prefix)
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.14), in: Circle())
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(window.map { "\($0.remainingPercent)%" } ?? "--%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            ProgressView(value: Double(percent), total: 100)
                .progressViewStyle(.linear)
                .tint(tint)

            Text(resetText)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.42))
        }
    }

    private var resetText: String {
        guard let resetAt = window?.resetAt else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: language.resolved == .simplifiedChinese ? "zh_CN" : "en_US"
        )
        formatter.dateFormat = window?.isWeekly == true
            ? (language.resolved == .simplifiedChinese ? "M月d日 HH:mm" : "MMM d, HH:mm")
            : "HH:mm"
        let prefix = language.resolved == .simplifiedChinese ? "重置" : "Resets"
        return "\(prefix) · \(formatter.string(from: resetAt))"
    }
}

private struct DashboardStatusPill: View {
    let text: String
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isAvailable ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill((isAvailable ? Color.green : Color.secondary).opacity(0.12))
        )
    }
}

private struct DashboardInfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.42))
            Spacer()
            Text(value)
                .foregroundStyle(Color.white.opacity(0.74))
                .lineLimit(1)
        }
        .font(.caption2)
    }
}

private struct DashboardEmptyState: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 24))
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(Color.white.opacity(0.36))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HeatmapLegend: View {
    let copy: UsageDashboardCopy

    var body: some View {
        HStack(spacing: 5) {
            Text(copy.less)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(YearActivityHeatmap.color(level: level))
                    .frame(width: 9, height: 9)
            }
            Text(copy.more)
        }
        .font(.caption2)
        .foregroundStyle(Color.white.opacity(0.40))
    }
}

private struct YearActivityHeatmap: View {
    let dailyTokens: [String: Int64]
    let language: AppLanguage

    private let rows = Array(
        repeating: GridItem(.fixed(10), spacing: 3),
        count: 7
    )

    private var days: [DailyTokenPoint] {
        DashboardMetrics(dailyTokens: dailyTokens).heatmapPoints(weeks: 52)
    }

    private var maxTokens: Int64 {
        max(1, days.map(\.tokens).max() ?? 1)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 3) {
                ForEach(days) { point in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Self.color(level: level(for: point.tokens)))
                        .frame(width: 10, height: 10)
                        .help(tooltip(for: point))
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 90)
    }

    static func color(level: Int) -> Color {
        switch level {
        case 0: return Color.white.opacity(0.055)
        case 1: return Color(red: 0.09, green: 0.22, blue: 0.39)
        case 2: return Color(red: 0.08, green: 0.34, blue: 0.61)
        case 3: return Color(red: 0.05, green: 0.44, blue: 0.82)
        default: return Color(red: 0.04, green: 0.52, blue: 1)
        }
    }

    private func level(for tokens: Int64) -> Int {
        guard tokens > 0 else { return 0 }
        let normalized = log(Double(tokens) + 1) / log(Double(maxTokens) + 1)
        return min(4, max(1, Int(ceil(normalized * 4))))
    }

    private func tooltip(for point: DailyTokenPoint) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: language.resolved == .simplifiedChinese ? "zh_CN" : "en_US"
        )
        formatter.dateStyle = .medium
        let tokens = UsageDashboardCopy(language: language).formatTokens(point.tokens)
        return "\(formatter.string(from: point.date)) · \(tokens) tokens"
    }
}

private struct DashboardMetrics {
    let dailyTokens: [String: Int64]

    private let calendar = Calendar.current

    var total: Int64 {
        dailyTokens.values.reduce(0, +)
    }

    var today: Int64 {
        tokens(on: Date())
    }

    var thisWeek: Int64 {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return 0
        }
        return tokens(since: start)
    }

    var thisMonth: Int64 {
        guard let start = calendar.dateInterval(of: .month, for: Date())?.start else {
            return 0
        }
        return tokens(since: start)
    }

    func points(forLastDays count: Int) -> [DailyTokenPoint] {
        let today = calendar.startOfDay(for: Date())
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(
                byAdding: .day,
                value: -(count - 1 - offset),
                to: today
            ) else {
                return nil
            }
            return DailyTokenPoint(date: date, tokens: tokens(on: date))
        }
    }

    func heatmapPoints(weeks: Int) -> [DailyTokenPoint] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        guard let currentWeekStart = calendar.date(
            byAdding: .day,
            value: -(weekday - 1),
            to: today
        ), let start = calendar.date(
            byAdding: .weekOfYear,
            value: -(weeks - 1),
            to: currentWeekStart
        ) else {
            return []
        }

        return (0..<(weeks * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            let value = date > today ? 0 : tokens(on: date)
            return DailyTokenPoint(date: date, tokens: value)
        }
    }

    func activeDays(weeks: Int) -> Int {
        heatmapPoints(weeks: weeks).filter { $0.tokens > 0 }.count
    }

    private func tokens(since start: Date) -> Int64 {
        dailyTokens.reduce(into: Int64(0)) { result, pair in
            guard let date = Self.dayFormatter.date(from: pair.key), date >= start else {
                return
            }
            result += pair.value
        }
    }

    private func tokens(on date: Date) -> Int64 {
        dailyTokens[Self.dayFormatter.string(from: date)] ?? 0
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct UsageDashboardCopy {
    let language: AppLanguage

    private var chinese: Bool {
        language.resolved == .simplifiedChinese
    }

    static func windowTitle(_ language: AppLanguage) -> String {
        language.resolved == .simplifiedChinese
            ? "CodexBuddy 用量详情"
            : "CodexBuddy Usage Details"
    }

    var menuTitle: String { chinese ? "用量详情…" : "Usage Details…" }
    var title: String { chinese ? "用量详情" : "Usage Details" }
    var subtitle: String {
        chinese
            ? "本机 Codex Token 活动与官方额度概览"
            : "Local Codex token activity and official quota overview"
    }
    var officialUsage: String { chinese ? "官方 Usage" : "Official Usage" }
    var refresh: String { chinese ? "刷新" : "Refresh" }
    var totalRecorded: String { chinese ? "本机记录累计" : "Total recorded" }
    var today: String { chinese ? "今日消耗" : "Today" }
    var thisWeek: String { chinese ? "本周" : "This week" }
    var thisMonth: String { chinese ? "本月" : "This month" }
    var localHistory: String { chinese ? "来自本机 Codex 会话记录" : "From local Codex sessions" }
    var naturalDay: String { chinese ? "按本地自然日统计" : "Local calendar day" }
    var naturalWeek: String { chinese ? "按当前自然周统计" : "Current calendar week" }
    var naturalMonth: String { chinese ? "按当前自然月统计" : "Current calendar month" }
    var tokenTrend: String { chinese ? "Token 趋势" : "Token Trend" }
    var noActivity: String { chinese ? "此范围内暂无 Token 活动" : "No token activity in this range" }
    var dateAxis: String { chinese ? "日期" : "Date" }
    var tokenAxis: String { "Tokens" }
    var currentQuota: String { chinese ? "当前额度" : "Current Quota" }
    var shortWindow: String { chinese ? "5 小时额度" : "5-hour quota" }
    var weekWindow: String { chinese ? "每周额度" : "Weekly quota" }
    var plan: String { chinese ? "套餐" : "Plan" }
    var source: String { chinese ? "来源" : "Source" }
    var updated: String { chinese ? "状态" : "Status" }
    var live: String { chinese ? "实时" : "Live" }
    var waiting: String { chinese ? "等待数据" : "Waiting" }
    var tokenActivity: String { chinese ? "Token 活动" : "Token Activity" }
    var less: String { chinese ? "较少" : "Less" }
    var more: String { chinese ? "较多" : "More" }

    func rangeName(_ range: DashboardRange) -> String {
        switch range {
        case .week: return chinese ? "7 天" : "7 days"
        case .month: return chinese ? "30 天" : "30 days"
        case .quarter: return chinese ? "90 天" : "90 days"
        }
    }

    func rangeSummary(_ range: DashboardRange, total: Int64) -> String {
        let formatted = formatTokens(total)
        return chinese
            ? "最近 \(range.rawValue) 天共 \(formatted) tokens"
            : "\(formatted) tokens over the last \(range.rawValue) days"
    }

    func heatmapDetail(activeDays: Int) -> String {
        chinese
            ? "过去 52 周 · 共 \(activeDays) 个活跃日"
            : "Last 52 weeks · \(activeDays) active days"
    }

    func formatTokens(_ value: Int64) -> String {
        if chinese {
            if value >= 100_000_000 {
                return String(format: "%.2f 亿", Double(value) / 100_000_000)
            }
            if value >= 10_000 {
                return String(format: "%.1f 万", Double(value) / 10_000)
            }
            return value.formatted()
        }

        if value >= 1_000_000_000 {
            return String(format: "%.2fB", Double(value) / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return value.formatted()
    }

    func formatAxisTokens(_ value: Int64) -> String {
        if chinese {
            if value >= 100_000_000 {
                return String(format: "%.1f亿", Double(value) / 100_000_000)
            }
            if value >= 10_000 {
                return String(format: "%.0f万", Double(value) / 10_000)
            }
        } else {
            if value >= 1_000_000_000 {
                return String(format: "%.1fB", Double(value) / 1_000_000_000)
            }
            if value >= 1_000_000 {
                return String(format: "%.0fM", Double(value) / 1_000_000)
            }
            if value >= 1_000 {
                return String(format: "%.0fK", Double(value) / 1_000)
            }
        }
        return value.formatted()
    }
}
