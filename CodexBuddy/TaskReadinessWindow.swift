import AppKit
import Combine
import SwiftUI

@MainActor
final class TaskReadinessWindowController: NSWindowController {
    private var cancellables = Set<AnyCancellable>()
    private let model: UsageViewModel
    private let settings: AppSettings
    private let historyStore: UsageHistoryStore

    init(model: UsageViewModel, settings: AppSettings, historyStore: UsageHistoryStore) {
        self.model = model
        self.settings = settings
        self.historyStore = historyStore
        let rootView = TaskReadinessView(
            model: model,
            settings: settings,
            historyStore: historyStore
        )
        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(contentViewController: hostingController)
        panel.title = TaskReadinessCopy(language: settings.language).windowTitle
        panel.setContentSize(NSSize(width: 420, height: 300))
        panel.styleMask = [.titled, .closable, .utilityWindow]
        panel.titlebarAppearsTransparent = false
        panel.titlebarSeparatorStyle = .line
        panel.toolbarStyle = .unifiedCompact
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("CodexBuddyTaskReadiness")

        super.init(window: panel)
        shouldCascadeWindows = false

        settings.$language
            .removeDuplicates()
            .sink { [weak panel] language in
                panel?.title = TaskReadinessCopy(language: language).windowTitle
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(copyResult: Bool = false) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        guard copyResult else { return }
        Task { [weak self] in
            guard let self else { return }
            await model.reload()
            copyCurrentResult()
        }
    }

    private func copyCurrentResult() {
        let report = TaskReadiness.report(
            reading: model.reading,
            reservePercent: settings.weeklyReservePercent,
            records: historyStore.records24h()
        )
        let copy = TaskReadinessCopy(language: settings.language)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copy.clipboardText(report), forType: .string)
    }
}

@MainActor
private struct TaskReadinessView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject var settings: AppSettings
    let historyStore: UsageHistoryStore

    private var copy: TaskReadinessCopy {
        TaskReadinessCopy(language: settings.language)
    }

    private var report: TaskReadiness.Report {
        TaskReadiness.report(
            reading: model.reading,
            reservePercent: settings.weeklyReservePercent,
            records: historyStore.records24h()
        )
    }

    private var tint: Color {
        switch report.verdict {
        case .ready: return Color(red: 0.18, green: 0.83, blue: 0.60)
        case .pace: return Color.white.opacity(0.9)
        case .conserve: return Color(red: 1, green: 0.32, blue: 0.28)
        case .unavailable: return Color.orange
        }
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(red: 0.055, green: 0.060, blue: 0.070).opacity(0.84)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.title)
                            .font(.headline)
                        Text(copy.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.48))
                    }
                    Spacer()
                    Image(systemName: copy.symbol(for: report.verdict))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(copy.verdictTitle(report.verdict))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                    Text(copy.verdictDetail(report))
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.22), lineWidth: 1)
                )

                HStack(spacing: 16) {
                    TaskReadinessFact(label: copy.weekRemaining, value: copy.remainingValue(report))
                    TaskReadinessFact(label: copy.todayBudget, value: copy.budgetValue(report))
                    TaskReadinessFact(label: copy.reset, value: copy.resetValue(report))
                }

                HStack {
                    Button(copy.refresh) {
                        Task { await model.reload() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isReloading)

                    Spacer()

                    Button(copy.copyResult) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copy.clipboardText(report), forType: .string)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 420, height: 300)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }
}

private struct TaskReadinessFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.42))
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TaskReadinessCopy {
    let language: AppLanguage

    private var chinese: Bool { language.resolved == .simplifiedChinese }
    var windowTitle: String { chinese ? "CodexBuddy 任务前检查" : "CodexBuddy Task Check" }
    var title: String { chinese ? "任务前检查" : "Task Check" }
    var subtitle: String { chinese ? "基于当前额度与本机趋势，不估算提示词成本" : "Quota and local trend, not prompt-cost guessing" }
    var weekRemaining: String { chinese ? "每周剩余" : "Weekly left" }
    var todayBudget: String { chinese ? "今日建议" : "Today" }
    var reset: String { chinese ? "重置" : "Reset" }
    var refresh: String { chinese ? "刷新" : "Refresh" }
    var copyResult: String { chinese ? "复制结论" : "Copy result" }

    func symbol(for verdict: TaskReadiness.Verdict) -> String {
        switch verdict {
        case .ready: return "checkmark.seal.fill"
        case .pace: return "arrow.right.circle.fill"
        case .conserve: return "exclamationmark.triangle.fill"
        case .unavailable: return "arrow.clockwise.circle.fill"
        }
    }

    func verdictTitle(_ verdict: TaskReadiness.Verdict) -> String {
        switch verdict {
        case .ready: return chinese ? "可以开始" : "Good to start"
        case .pace: return chinese ? "建议拆小任务" : "Split the task"
        case .conserve: return chinese ? "建议保留额度" : "Conserve quota"
        case .unavailable: return chinese ? "先刷新用量" : "Refresh usage first"
        }
    }

    func verdictDetail(_ report: TaskReadiness.Report) -> String {
        switch report.verdict {
        case .ready:
            return chinese ? "当前节奏可承受一项正常的专注任务。" : "Current quota and pace support a focused task."
        case .pace:
            return chinese ? "本周消耗略快，建议分阶段执行并在中间检查。" : "Weekly use is ahead of plan; work in phases and recheck."
        case .conserve:
            if report.forecastDepletesBeforeReset {
                return chinese ? "近期消耗趋势会在重置前耗尽额度，优先处理必要工作。" : "Recent pace reaches zero before reset; keep quota for essential work."
            }
            return chinese ? "剩余额度已接近安全线，建议等待重置或只处理必要任务。" : "Quota is near the safety line; wait for reset or handle only essentials."
        case .unavailable:
            return report.isStale
                ? (chinese ? "现有额度数据可能已过期，请刷新后再判断。" : "Current quota data may be stale. Refresh before deciding.")
                : (chinese ? "尚未获取每周额度，使用 Codex 后点击刷新。" : "Weekly quota is not available yet. Use Codex, then refresh.")
        }
    }

    func remainingValue(_ report: TaskReadiness.Report) -> String {
        report.weekRemainingPercent.map { "\($0)%" } ?? "—"
    }

    func budgetValue(_ report: TaskReadiness.Report) -> String {
        guard let plan = report.plan else { return "—" }
        return chinese ? "约 \(plan.dailyAllowancePercent)%" : "~\(plan.dailyAllowancePercent)%"
    }

    func resetValue(_ report: TaskReadiness.Report) -> String {
        guard let resetAt = report.resetAt else { return "—" }
        let formatter = UIDateFormatters.formatter(
            dateFormat: chinese ? "M月d日" : "MMM d",
            localeIdentifier: chinese ? "zh_CN" : "en_US"
        )
        return formatter.string(from: resetAt)
    }

    func clipboardText(_ report: TaskReadiness.Report) -> String {
        let items = [
            title,
            verdictTitle(report.verdict),
            verdictDetail(report),
            "\(weekRemaining): \(remainingValue(report))",
            "\(todayBudget): \(budgetValue(report))",
            "\(reset): \(resetValue(report))"
        ]
        return items.joined(separator: "\n")
    }
}
