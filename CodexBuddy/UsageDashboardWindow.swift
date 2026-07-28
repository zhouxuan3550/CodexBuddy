import AppKit
import Charts
import Combine
import SwiftUI

@MainActor
final class UsageDashboardWindowController: NSWindowController {
    private let model: UsageViewModel
    private let activityStore: UsageActivityStore
    private var cancellables = Set<AnyCancellable>()

    init(
        model: UsageViewModel,
        settings: AppSettings,
        historyStore: UsageHistoryStore,
        activityStore: UsageActivityStore
    ) {
        self.model = model
        self.activityStore = activityStore

        let contentView = UsageDashboardView(
            model: model,
            settings: settings,
            historyStore: historyStore,
            activityStore: activityStore
        )
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = UsageDashboardCopy.windowTitle(settings.language)
        window.setContentSize(NSSize(width: 860, height: 600))
        window.minSize = NSSize(width: 760, height: 500)
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

        // Keep the window title in sync with the app language.
        settings.$language
            .removeDuplicates()
            .sink { [weak self] language in
                self?.window?.title = UsageDashboardCopy.windowTitle(language)
            }
            .store(in: &cancellables)
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

private struct HeatmapDay: Identifiable {
    let date: Date
    let tokens: Int64
    let isFuture: Bool

    var id: Date { date }
}

private struct HeatmapMonthMarker: Identifiable {
    let weekIndex: Int
    let monthStart: Date

    var id: Int { weekIndex }
}

@MainActor
private struct UsageDashboardView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject var settings: AppSettings
    let historyStore: UsageHistoryStore
    @ObservedObject var activityStore: UsageActivityStore

    @State private var range: DashboardRange = .month
    @State private var snapshot = DashboardSnapshot.empty
    @State private var insights = DashboardInsights.empty
    @State private var hoveredPoint: DailyTokenPoint?
    @State private var showsSecondaryInsights = false

    private var copy: UsageDashboardCopy {
        UsageDashboardCopy(language: settings.language)
    }

    private var chartPoints: [DailyTokenPoint] {
        snapshot.points(forLastDays: range.rawValue)
    }

    var body: some View {
        ZStack {
            DashboardGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    metricGrid

                    HStack(alignment: .top, spacing: 16) {
                        tokenChart
                            .frame(maxWidth: .infinity)
                        quotaOverview
                            .frame(width: 270)
                    }

                    insightsRow
                    secondaryInsights
                }
                .padding(18)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .preferredColorScheme(.dark)
        .onAppear {
            snapshot = DashboardSnapshot.build(from: activityStore.dailyTokens)
            insights = DashboardInsights.build(
                from: activityStore.dailyBreakdown,
                lastDays: range.rawValue
            )
        }
        .onChange(of: activityStore.dailyTokens) { dailyTokens in
            snapshot = DashboardSnapshot.build(from: dailyTokens)
        }
        .onChange(of: activityStore.dailyBreakdown) { breakdown in
            insights = DashboardInsights.build(from: breakdown, lastDays: range.rawValue)
        }
        .onChange(of: range) { newRange in
            insights = DashboardInsights.build(
                from: activityStore.dailyBreakdown,
                lastDays: newRange.rawValue
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(copy.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.52))
            }

            Spacer()

            Button {
                CSVExporter.exportDailyTokens(activityStore.dailyTokens)
            } label: {
                Label(copy.exportCSV, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(snapshot.total == 0)

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
                Label(copy.refresh, systemImage: "arrow.clockwise")
                    .opacity(model.isReloading ? 0 : 1)
                    .overlay {
                        if model.isReloading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isReloading)
        }
    }

    /// "This week" prefers the official rolling 7-day cycle when its reset date
    /// is known, so the card lines up with the weekly quota next to it.
    private var weekCard: (value: Int64, detail: String) {
        if let resetAt = model.reading?.weekWindow?.resetAt {
            let cycleStart = resetAt.addingTimeInterval(-7 * 86_400)
            return (snapshot.tokens(since: cycleStart), copy.officialCycleDetail(end: resetAt))
        }
        return (snapshot.naturalWeek, copy.naturalWeek)
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
            spacing: 12
        ) {
            DashboardMetricCard(
                title: copy.totalRecorded,
                value: copy.formatTokens(snapshot.total),
                detail: copy.localHistory,
                color: Color(red: 0.12, green: 0.48, blue: 0.95)
            )
            DashboardMetricCard(
                title: copy.today,
                value: copy.formatTokens(snapshot.today),
                detail: copy.naturalDay,
                color: Color(red: 0.12, green: 0.48, blue: 0.95)
            )
            DashboardMetricCard(
                title: copy.thisWeek,
                value: copy.formatTokens(weekCard.value),
                detail: weekCard.detail,
                color: Color(red: 0.12, green: 0.48, blue: 0.95)
            )
            DashboardMetricCard(
                title: copy.thisMonth,
                value: copy.formatTokens(snapshot.thisMonth),
                detail: copy.naturalMonth,
                color: Color(red: 0.12, green: 0.48, blue: 0.95)
            )
        }
    }

    private var tokenChart: some View {
        let points = chartPoints
        let todayStart = Calendar.current.startOfDay(for: Date())
        let total = points.reduce(Int64(0)) { $0 + $1.tokens }

        return DashboardGlassCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.tokenTrend)
                            .font(.headline)
                        Text(hoveredPoint.map { copy.hoverSummary($0.date, tokens: $0.tokens) }
                            ?? copy.rangeSummary(range, total: total))
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.46))
                            .monospacedDigit()
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

                if points.allSatisfy({ $0.tokens == 0 }) {
                    DashboardEmptyState(text: copy.noActivity)
                        .frame(height: 144)
                } else {
                    Chart {
                        ForEach(points) { point in
                            BarMark(
                                x: .value(copy.dateAxis, point.date, unit: .day),
                                y: .value(copy.tokenAxis, point.tokens)
                            )
                            .foregroundStyle(
                                point.date == todayStart
                                    ? Color(red: 0.32, green: 0.65, blue: 1)
                                    : Color(red: 0.12, green: 0.48, blue: 0.95)
                            )
                            .cornerRadius(3)
                        }

                        if let hovered = hoveredPoint {
                            RuleMark(x: .value(copy.dateAxis, hovered.date, unit: .day))
                                .foregroundStyle(Color.white.opacity(0.22))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                        }
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
                    .chartOverlay { proxy in
                        // The overlay covers exactly the plot area, so local
                        // hover coordinates map straight into chart values.
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let date: Date = proxy.value(atX: location.x) {
                                        let day = Calendar.current.startOfDay(for: date)
                                        hoveredPoint = points.first { $0.date == day }
                                    } else {
                                        hoveredPoint = nil
                                    }
                                case .ended:
                                    hoveredPoint = nil
                                }
                            }
                    }
                    .frame(height: 144)
                }
            }
        }
    }

    private enum QuotaFeedState {
        case waiting
        case live
        case stale
    }

    private var feedState: QuotaFeedState {
        guard let reading = model.reading else { return .waiting }
        return reading.isOutdated() ? .stale : .live
    }

    private var updatedValue: String {
        let absolute = model.updatedText(language: settings.language)
        guard let updatedAt = model.reading?.updatedAt else { return absolute }
        return "\(absolute) · \(copy.relativeAge(since: updatedAt))"
    }

    private func depletionText(
        _ type: DepletionEstimator.WindowType,
        window: QuotaWindow?
    ) -> String? {
        guard let window else { return nil }
        let estimate = DepletionEstimator.estimate(
            records: historyStore.records7d(),
            windowType: type,
            currentRemaining: window.remainingPercent
        )
        return DepletionEstimator.formatEstimate(estimate, language: settings.language)
    }

    private var quotaOverview: some View {
        DashboardGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(copy.currentQuota)
                        .font(.headline)
                    Spacer()
                    switch feedState {
                    case .waiting:
                        DashboardStatusPill(text: copy.waiting, color: .secondary)
                    case .live:
                        DashboardStatusPill(text: copy.live, color: .green)
                    case .stale:
                        DashboardStatusPill(text: copy.stale, color: .orange)
                    }
                }

                DashboardQuotaRow(
                    title: copy.shortWindow,
                    prefix: "H",
                    window: model.reading?.shortWindow,
                    estimateText: depletionText(.short, window: model.reading?.shortWindow),
                    copy: copy
                )

                DashboardQuotaRow(
                    title: copy.weekWindow,
                    prefix: "W",
                    window: model.reading?.weekWindow,
                    estimateText: depletionText(.week, window: model.reading?.weekWindow),
                    copy: copy
                )

                Divider()
                    .overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 3) {
                    if let planName = model.reading?.planName {
                        DashboardInfoLine(label: copy.plan, value: planName.uppercased())
                    }
                    DashboardInfoLine(
                        label: copy.lastUpdated,
                        value: updatedValue,
                        valueColor: feedState == .stale
                            ? Color.orange.opacity(0.90)
                            : Color.white.opacity(0.74)
                    )
                }
            }
        }
    }

    // MARK: - Insights

    private func insightHeader(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            Text(copy.insightRange(range))
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.38))
        }
    }

    private var insightsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            projectRankCard
                .frame(maxWidth: .infinity)
            modelSplitCard
                .frame(maxWidth: .infinity)
        }
    }

    private var secondaryInsights: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsSecondaryInsights.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: showsSecondaryInsights ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                    Text(showsSecondaryInsights ? copy.hideSecondaryInsights : copy.showSecondaryInsights)
                        .font(.caption.weight(.semibold))
                    Text(copy.secondaryInsightsDetail)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.38))
                }
                .foregroundStyle(Color.white.opacity(0.62))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsSecondaryInsights {
                cacheCard
                activityHeatmap
            }
        }
    }

    private var projectRankCard: some View {
        DashboardGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                insightHeader(copy.topProjects)

                if insights.topProjects.isEmpty {
                    insightEmptyState
                } else {
                    VStack(spacing: 9) {
                        ForEach(insights.topProjects) { item in
                            DashboardShareRow(
                                name: item.name.isEmpty ? copy.unknownName : item.name,
                                valueText: copy.formatTokens(item.tokens),
                                share: item.share,
                                tint: Color(red: 0.12, green: 0.48, blue: 0.95)
                            )
                            .help(item.fullName.isEmpty ? copy.unknownName : item.fullName)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modelSplitCard: some View {
        DashboardGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                insightHeader(copy.modelsAndSources)

                if insights.models.isEmpty && insights.sources.isEmpty {
                    insightEmptyState
                } else {
                    VStack(spacing: 9) {
                        ForEach(insights.models) { item in
                            DashboardShareRow(
                                name: item.name.isEmpty ? copy.unknownName : item.name,
                                valueText: copy.formatTokens(item.tokens),
                                share: item.share,
                                tint: Color(red: 0.62, green: 0.44, blue: 0.98)
                            )
                        }
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    VStack(spacing: 9) {
                        ForEach(insights.sources) { item in
                            DashboardShareRow(
                                name: copy.sourceName(item.name),
                                valueText: copy.formatTokens(item.tokens),
                                share: item.share,
                                tint: Color(red: 0.16, green: 0.72, blue: 0.65)
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cacheCard: some View {
        DashboardGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                insightHeader(copy.cacheHitRate)

                if let rate = insights.hitRate {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f%%", rate * 100))
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        if let delta = insights.hitRateDelta {
                            Text(copy.deltaText(delta))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    delta >= 0
                                        ? Color(red: 0.18, green: 0.83, blue: 0.60)
                                        : Color(red: 1, green: 0.45, blue: 0.35)
                                )
                        }
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(Color(red: 0.18, green: 0.83, blue: 0.60))
                                .frame(width: max(2, proxy.size.width * rate))
                        }
                    }
                    .frame(height: 5)

                    Text(copy.cacheDetail(
                        cached: insights.cachedInputTokens,
                        input: insights.inputTokens
                    ))
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.42))

                    Text(copy.cacheHint)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.34))
                } else {
                    insightEmptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var insightEmptyState: some View {
        Text(copy.noInsightData)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.38))
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
    }

    private var activityHeatmap: some View {
        DashboardGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.tokenActivity)
                            .font(.headline)
                        Text(copy.heatmapDetail(
                            firstActiveDay: snapshot.firstActiveDay,
                            weeks: snapshot.heatmapWeeks,
                            activeDays: snapshot.activeDays
                        ))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.46))
                    }
                    Spacer()
                    HeatmapLegend(copy: copy)
                }

                YearActivityHeatmap(
                    days: snapshot.heatmapDays,
                    maxTokens: snapshot.heatmapMaxTokens,
                    monthMarkers: snapshot.monthMarkers,
                    minWeeks: snapshot.heatmapWeeks,
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DashboardQuotaRow: View {
    let title: String
    let prefix: String
    let window: QuotaWindow?
    let estimateText: String?
    let copy: UsageDashboardCopy

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
                Text(window.map { "\($0.remainingPercent)%" } ?? "--")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            if window == nil {
                // No data yet: show an inert track so the empty state cannot be
                // mistaken for a depleted (0%) quota.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 4)
                Text(copy.noQuotaData)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.42))
            } else {
                ProgressView(value: Double(percent), total: 100)
                    .progressViewStyle(.linear)
                    .tint(tint)
                Text(footerText)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
        .opacity(window == nil ? 0.55 : 1)
    }

    private var footerText: String {
        var parts: [String] = []
        if let resetAt = window?.resetAt {
            let formatter = UIDateFormatters.formatter(
                dateFormat: window?.isWeekly == true
                    ? (copy.chinese ? "M月d日 HH:mm" : "MMM d, HH:mm")
                    : "HH:mm",
                localeIdentifier: copy.chinese ? "zh_CN" : "en_US"
            )
            let prefix = copy.chinese ? "重置" : "Resets"
            parts.append("\(prefix) · \(formatter.string(from: resetAt))")
        }
        if let estimateText {
            parts.append(estimateText)
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

private struct DashboardStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

private struct DashboardInfoLine: View {
    let label: String
    let value: String
    var valueColor: Color = Color.white.opacity(0.74)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.42))
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .font(.caption2)
    }
}

/// A labelled proportion bar used by the insight cards (projects, models,
/// sources): name on the left, formatted tokens on the right, share below.
private struct DashboardShareRow: View {
    let name: String
    let valueText: String
    let share: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(valueText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.60))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, proxy.size.width * share))
                }
            }
            .frame(height: 4)
        }
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

private struct HeatmapWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct YearActivityHeatmap: View {
    let days: [HeatmapDay]
    let maxTokens: Int64
    let monthMarkers: [HeatmapMonthMarker]
    let minWeeks: Int
    let language: AppLanguage

    private static let cellSpacing: CGFloat = 3
    private static let baseCellSize: CGFloat = 10
    private static let maxCellSize: CGFloat = 16
    private static let weekdayLabelWidth: CGFloat = 22
    private static let labelSpacing: CGFloat = 8

    /// Card width measured at runtime; drives how many trailing weeks are
    /// shown and how large each cell grows, so the grid fills the row.
    @State private var availableWidth: CGFloat = 0

    private var totalWeeks: Int { max(1, days.count / 7) }

    private var gridWidth: CGFloat {
        availableWidth - Self.weekdayLabelWidth - Self.labelSpacing
    }

    /// Trailing weeks to render: as many base-size columns as fit, but never
    /// fewer than the data span and never more than the available year.
    private var visibleWeeks: Int {
        guard gridWidth > 0 else { return min(totalWeeks, max(1, minWeeks)) }
        let fit = Int((gridWidth + Self.cellSpacing) / (Self.baseCellSize + Self.cellSpacing))
        return max(1, min(totalWeeks, max(minWeeks, fit)))
    }

    /// Cells scale up (capped) to absorb any width left over after fitting.
    private var cellSize: CGFloat {
        guard gridWidth > 0 else { return Self.baseCellSize }
        let column = (gridWidth + Self.cellSpacing) / CGFloat(visibleWeeks)
        return min(Self.maxCellSize, max(4, column - Self.cellSpacing))
    }

    private var columnWidth: CGFloat { cellSize + Self.cellSpacing }

    private var hiddenWeeks: Int { totalWeeks - visibleWeeks }

    private var visibleDays: ArraySlice<HeatmapDay> { days.suffix(visibleWeeks * 7) }

    var body: some View {
        HStack(alignment: .bottom, spacing: Self.labelSpacing) {
            weekdayLabels
            VStack(alignment: .leading, spacing: 4) {
                monthLabels
                grid
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HeatmapWidthKey.self,
                    value: proxy.size.width
                )
            }
        )
        .onPreferenceChange(HeatmapWidthKey.self) { availableWidth = $0 }
    }

    private var monthLabels: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: CGFloat(visibleWeeks) * columnWidth, height: 12)
            ForEach(monthMarkers.filter { $0.weekIndex >= hiddenWeeks }) { marker in
                Text(monthText(marker.monthStart))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.40))
                    .fixedSize()
                    .offset(x: CGFloat(marker.weekIndex - hiddenWeeks) * columnWidth)
            }
        }
        .clipped()
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: Self.cellSpacing) {
            ForEach(0..<7, id: \.self) { row in
                Text(weekdayText(row))
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.36))
                    .frame(
                        width: Self.weekdayLabelWidth,
                        height: cellSize,
                        alignment: .trailing
                    )
            }
        }
    }

    private var grid: some View {
        LazyHGrid(
            rows: Array(
                repeating: GridItem(.fixed(cellSize), spacing: Self.cellSpacing),
                count: 7
            ),
            spacing: Self.cellSpacing
        ) {
            ForEach(visibleDays) { day in
                if day.isFuture {
                    Color.clear
                        .frame(width: cellSize, height: cellSize)
                } else {
                    RoundedRectangle(cornerRadius: cellSize * 0.25, style: .continuous)
                        .fill(Self.color(level: level(for: day.tokens)))
                        .frame(width: cellSize, height: cellSize)
                        .help(tooltip(for: day))
                }
            }
        }
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
        let normalized = log(Double(tokens) + 1) / log(Double(max(1, maxTokens)) + 1)
        return min(4, max(1, Int(ceil(normalized * 4))))
    }

    private func monthText(_ date: Date) -> String {
        if language.resolved == .simplifiedChinese {
            return "\(Calendar.current.component(.month, from: date))月"
        }
        let formatter = UIDateFormatters.formatter(
            dateFormat: "MMM",
            localeIdentifier: "en_US"
        )
        return formatter.string(from: date)
    }

    private func weekdayText(_ row: Int) -> String {
        // Rows run Sunday through Saturday; label Mon / Wed / Fri.
        let chinese = language.resolved == .simplifiedChinese
        switch row {
        case 1: return chinese ? "一" : "Mon"
        case 3: return chinese ? "三" : "Wed"
        case 5: return chinese ? "五" : "Fri"
        default: return ""
        }
    }

    private func tooltip(for day: HeatmapDay) -> String {
        let formatter = UIDateFormatters.mediumDate(
            localeIdentifier: language.resolved == .simplifiedChinese ? "zh_CN" : "en_US"
        )
        let tokens = UsageDashboardCopy(language: language).formatTokens(day.tokens)
        return "\(formatter.string(from: day.date)) · \(tokens) tokens"
    }
}

/// Precomputed dashboard metrics. Built once per `dailyTokens` change instead
/// of being re-derived on every SwiftUI render pass.
private struct DashboardSnapshot {
    let dayTotals: [Date: Int64]
    let total: Int64
    let today: Int64
    let naturalWeek: Int64
    let thisMonth: Int64
    let firstActiveDay: Date?
    let heatmapWeeks: Int
    let heatmapDays: [HeatmapDay]
    let heatmapMaxTokens: Int64
    let monthMarkers: [HeatmapMonthMarker]
    let activeDays: Int

    static let empty = DashboardSnapshot(
        dayTotals: [:],
        total: 0,
        today: 0,
        naturalWeek: 0,
        thisMonth: 0,
        firstActiveDay: nil,
        heatmapWeeks: 52,
        heatmapDays: [],
        heatmapMaxTokens: 1,
        monthMarkers: [],
        activeDays: 0
    )

    static func build(from dailyTokens: [String: Int64], now: Date = Date()) -> DashboardSnapshot {
        let calendar = Calendar.current

        // Parse day keys exactly once.
        var dayTotals: [Date: Int64] = Dictionary(minimumCapacity: dailyTokens.count)
        var total: Int64 = 0
        for (key, value) in dailyTokens {
            guard let date = dayFormatter.date(from: key) else { continue }
            dayTotals[calendar.startOfDay(for: date), default: 0] += value
            total += value
        }

        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start

        var naturalWeek: Int64 = 0
        var thisMonth: Int64 = 0
        var firstActiveDay: Date?
        for (date, value) in dayTotals {
            if value > 0, firstActiveDay.map({ date < $0 }) ?? true {
                firstActiveDay = date
            }
            if let weekStart, date >= weekStart { naturalWeek += value }
            if let monthStart, date >= monthStart { thisMonth += value }
        }

        // The header reports the data span, while the grid always has a full
        // 52-week year available; the view shows as many trailing weeks as it
        // needs to fill the card's width (at least the data span).
        let weekday = calendar.component(.weekday, from: todayStart)
        guard let currentWeekStart = calendar.date(
            byAdding: .day,
            value: -(weekday - 1),
            to: todayStart
        ) else {
            return .empty
        }
        var dataWeeks = 52
        if let firstActiveDay {
            let firstWeekday = calendar.component(.weekday, from: firstActiveDay)
            if let firstWeekStart = calendar.date(
                byAdding: .day,
                value: -(firstWeekday - 1),
                to: firstActiveDay
            ) {
                let dayDiff = calendar.dateComponents(
                    [.day],
                    from: firstWeekStart,
                    to: currentWeekStart
                ).day ?? 0
                dataWeeks = min(52, max(12, dayDiff / 7 + 1))
            }
        }
        let weeks = 52

        guard let start = calendar.date(
            byAdding: .day,
            value: -(weeks - 1) * 7,
            to: currentWeekStart
        ) else {
            return .empty
        }

        var heatmapDays: [HeatmapDay] = []
        heatmapDays.reserveCapacity(weeks * 7)
        var maxTokens: Int64 = 1
        var activeDays = 0
        var monthMarkers: [HeatmapMonthMarker] = []
        var lastMonth = -1
        for offset in 0..<(weeks * 7) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                continue
            }
            let isFuture = date > todayStart
            let tokens = isFuture ? 0 : (dayTotals[date] ?? 0)
            if tokens > 0 { activeDays += 1 }
            maxTokens = max(maxTokens, tokens)
            heatmapDays.append(HeatmapDay(date: date, tokens: tokens, isFuture: isFuture))

            if offset % 7 == 0 {
                let month = calendar.component(.month, from: date)
                if month != lastMonth {
                    monthMarkers.append(
                        HeatmapMonthMarker(weekIndex: offset / 7, monthStart: date)
                    )
                    lastMonth = month
                }
            }
        }

        return DashboardSnapshot(
            dayTotals: dayTotals,
            total: total,
            today: dayTotals[todayStart] ?? 0,
            naturalWeek: naturalWeek,
            thisMonth: thisMonth,
            firstActiveDay: firstActiveDay,
            heatmapWeeks: dataWeeks,
            heatmapDays: heatmapDays,
            heatmapMaxTokens: maxTokens,
            monthMarkers: monthMarkers,
            activeDays: activeDays
        )
    }

    /// Day-granularity sum from `start` onwards (partial first day included).
    func tokens(since start: Date) -> Int64 {
        let startDay = Calendar.current.startOfDay(for: start)
        return dayTotals.reduce(into: Int64(0)) { result, pair in
            if pair.key >= startDay { result += pair.value }
        }
    }

    func points(forLastDays count: Int, now: Date = Date()) -> [DailyTokenPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(
                byAdding: .day,
                value: -(count - 1 - offset),
                to: today
            ) else {
                return nil
            }
            return DailyTokenPoint(date: date, tokens: dayTotals[date] ?? 0)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// Dimensional insight metrics for the selected range, derived from the
/// per-day breakdowns collected by UsageActivityStore.
private struct DashboardInsights {
    struct Share: Identifiable {
        let name: String
        let fullName: String
        let tokens: Int64
        let share: Double
        var id: String { fullName }
    }

    let topProjects: [Share]
    let models: [Share]
    let sources: [Share]
    let inputTokens: Int64
    let cachedInputTokens: Int64
    /// Hit-rate change vs the previous period of equal length, in percentage
    /// points; nil when either period lacks input data.
    let hitRateDelta: Double?

    var hitRate: Double? {
        inputTokens > 0 ? Double(cachedInputTokens) / Double(inputTokens) : nil
    }

    static let empty = DashboardInsights(
        topProjects: [],
        models: [],
        sources: [],
        inputTokens: 0,
        cachedInputTokens: 0,
        hitRateDelta: nil
    )

    static func build(
        from dailyBreakdown: [String: UsageDayBreakdown],
        lastDays: Int,
        now: Date = Date()
    ) -> DashboardInsights {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        guard
            let currentStart = calendar.date(byAdding: .day, value: -(lastDays - 1), to: todayStart),
            let previousStart = calendar.date(byAdding: .day, value: -lastDays, to: currentStart)
        else { return .empty }

        var current = UsageDayBreakdown()
        var previous = UsageDayBreakdown()
        for (key, value) in dailyBreakdown {
            guard let date = dayFormatter.date(from: key) else { continue }
            let day = calendar.startOfDay(for: date)
            if day >= currentStart, day <= todayStart {
                current.merge(value)
            } else if day >= previousStart {
                previous.merge(value)
            }
        }

        let delta: Double?
        if current.inputTokens > 0, previous.inputTokens > 0 {
            let currentRate = Double(current.cachedInputTokens) / Double(current.inputTokens)
            let previousRate = Double(previous.cachedInputTokens) / Double(previous.inputTokens)
            delta = (currentRate - previousRate) * 100
        } else {
            delta = nil
        }

        return DashboardInsights(
            topProjects: shares(from: current.byProject, limit: 5) {
                ($0 as NSString).lastPathComponent
            },
            models: shares(from: current.byModel, limit: 3) { $0 },
            sources: shares(from: current.bySource, limit: 3) { $0 },
            inputTokens: current.inputTokens,
            cachedInputTokens: current.cachedInputTokens,
            hitRateDelta: delta
        )
    }

    private static func shares(
        from dict: [String: Int64],
        limit: Int,
        displayName: (String) -> String
    ) -> [Share] {
        let total = dict.values.reduce(0, +)
        guard total > 0 else { return [] }
        return dict
            .filter { UsageDetailFilter.shouldDisplay(tokens: $0.value) }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { key, value in
                Share(
                    name: displayName(key),
                    fullName: key,
                    tokens: value,
                    share: Double(value) / Double(total)
                )
            }
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

    var chinese: Bool {
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
    var exportCSV: String { chinese ? "导出 CSV" : "Export CSV" }
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
    var lastUpdated: String { chinese ? "上次更新" : "Updated" }
    var live: String { chinese ? "实时" : "Live" }
    var waiting: String { chinese ? "等待数据" : "Waiting" }
    var stale: String { chinese ? "可能过期" : "Stale" }
    var noQuotaData: String {
        chinese
            ? "暂无数据 · 使用 Codex 后自动获取"
            : "No data yet · appears after Codex activity"
    }
    var tokenActivity: String { chinese ? "Token 活动" : "Token Activity" }
    var less: String { chinese ? "较少" : "Less" }
    var more: String { chinese ? "较多" : "More" }
    var topProjects: String { chinese ? "项目用量排行" : "Top Projects" }
    var modelsAndSources: String { chinese ? "模型与来源" : "Models & Sources" }
    var cacheHitRate: String { chinese ? "缓存命中率" : "Cache Hit Rate" }
    var unknownName: String { chinese ? "未知" : "Unknown" }
    var noInsightData: String {
        chinese
            ? "暂无数据 · 使用 Codex 后自动统计"
            : "No data yet · appears after Codex activity"
    }
    var cacheHint: String {
        chinese
            ? "命中率越高，同样额度能跑更多任务"
            : "A higher hit rate stretches the same quota further"
    }
    var showSecondaryInsights: String { chinese ? "更多洞察" : "More insights" }
    var hideSecondaryInsights: String { chinese ? "收起洞察" : "Hide insights" }
    var secondaryInsightsDetail: String {
        chinese ? "缓存命中率与 Token 活动" : "Cache hit rate and token activity"
    }
    var weeklyPace: String { chinese ? "本周节奏" : "Weekly pace" }

    func dailyAllowance(_ plan: QuotaPacing.Plan) -> String {
        chinese
            ? "今天可用约 \(plan.dailyAllowancePercent)%"
            : "~\(plan.dailyAllowancePercent)% today"
    }

    func paceState(_ state: QuotaPacing.State) -> String {
        switch state {
        case .relaxed: return chinese ? "节奏宽松" : "Relaxed"
        case .onTrack: return chinese ? "节奏正常" : "On track"
        case .tight: return chinese ? "需要放缓" : "Pace down"
        case .protected: return chinese ? "已到余量" : "At reserve"
        }
    }

    func paceDetail(_ plan: QuotaPacing.Plan) -> String {
        let reserve = plan.isReserveEnabled
            ? (chinese ? "，含 \(plan.reservePercent)% 安全余量" : ", incl. \(plan.reservePercent)% reserve")
            : ""
        return chinese
            ? "距重置约 \(plan.daysRemaining) 天，按当前节奏分配\(reserve)"
            : "About \(plan.daysRemaining) day(s) to reset; paced from remaining quota\(reserve)"
    }

    func pacingAccessibility(_ plan: QuotaPacing.Plan) -> String {
        "\(weeklyPace), \(dailyAllowance(plan)), \(paceState(plan.state)), \(paceDetail(plan))"
    }

    func insightRange(_ range: DashboardRange) -> String {
        chinese ? "最近 \(range.rawValue) 天" : "Last \(range.rawValue) days"
    }

    func sourceName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "vscode": return "VS Code"
        case "cli": return "CLI"
        case "exec": return "Exec"
        case "": return unknownName
        default: return raw
        }
    }

    func deltaText(_ delta: Double) -> String {
        let sign = delta >= 0 ? "+" : ""
        let value = String(format: "%@%.1fpp", sign, delta)
        return chinese ? "\(value) 较上期" : "\(value) vs prev"
    }

    func cacheDetail(cached: Int64, input: Int64) -> String {
        chinese
            ? "缓存输入 \(formatTokens(cached)) / 输入总量 \(formatTokens(input))"
            : "Cached \(formatTokens(cached)) of \(formatTokens(input)) input"
    }

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

    func officialCycleDetail(end: Date) -> String {
        let formatter = UIDateFormatters.formatter(
            dateFormat: chinese ? "M月d日" : "MMM d",
            localeIdentifier: chinese ? "zh_CN" : "en_US"
        )
        let day = formatter.string(from: end)
        return chinese
            ? "官方 7 天周期 · 至 \(day)"
            : "Official 7-day cycle · ends \(day)"
    }

    func heatmapDetail(firstActiveDay: Date?, weeks: Int, activeDays: Int) -> String {
        if weeks < 52, let firstActiveDay {
            let formatter = UIDateFormatters.formatter(
                dateFormat: chinese ? "M月d日" : "MMM d",
                localeIdentifier: chinese ? "zh_CN" : "en_US"
            )
            let day = formatter.string(from: firstActiveDay)
            return chinese
                ? "自 \(day) 起 · 共 \(activeDays) 个活跃日"
                : "Since \(day) · \(activeDays) active days"
        }
        return chinese
            ? "过去 \(weeks) 周 · 共 \(activeDays) 个活跃日"
            : "Last \(weeks) weeks · \(activeDays) active days"
    }

    func hoverSummary(_ date: Date, tokens: Int64) -> String {
        let formatter = UIDateFormatters.formatter(
            dateFormat: chinese ? "M月d日" : "MMM d",
            localeIdentifier: chinese ? "zh_CN" : "en_US"
        )
        return "\(formatter.string(from: date)) · \(formatTokens(tokens)) tokens"
    }

    func relativeAge(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return chinese ? "刚刚" : "just now"
        }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return chinese ? "\(minutes) 分钟前" : "\(minutes)m ago"
        }
        let hours = Int(seconds / 3600)
        return chinese ? "\(hours) 小时前" : "\(hours)h ago"
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
