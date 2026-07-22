import AppKit

/// GitHub-style activity heatmap: columns = weeks (oldest → newest, left → right),
/// rows = weekdays (Sun–Sat, top → bottom). Cell intensity encodes daily token
/// consumption on a log scale. Supports hover tooltip and a Less→More legend.
@MainActor
final class UsageHeatmapView: NSView {
    private var dailyTokens: [String: Int64] = [:]
    private var language: AppLanguage = .system

    private let cellSize: CGFloat = 9
    private let cellGap: CGFloat = 2
    private let leftInset: CGFloat = 26
    private let topInset: CGFloat = 14
    private let bottomInset: CGFloat = 18

    private var trackingArea: NSTrackingArea?
    private var cellFrames: [(rect: CGRect, date: Date, tokens: Int64)] = []
    private var hoveredIndex: Int?

    private let dayKeyFormatter: DateFormatter
    private let tooltipDateFormatter: DateFormatter
    private let monthFormatter: DateFormatter

    init() {
        dayKeyFormatter = DateFormatter()
        dayKeyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"

        tooltipDateFormatter = DateFormatter()
        monthFormatter = DateFormatter()

        let width = UsageSummaryMenuView.preferredWidth - 40
        let height: CGFloat = 108
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        setupTracking()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    private var step: CGFloat { cellSize + cellGap }

    func update(dailyTokens: [String: Int64], language: AppLanguage) {
        self.dailyTokens = dailyTokens
        self.language = language
        let isChinese = language.resolved == .simplifiedChinese
        let locale = Locale(identifier: isChinese ? "zh_CN" : "en_US")
        tooltipDateFormatter.locale = locale
        tooltipDateFormatter.dateFormat = isChinese ? "M月d日" : "MMM d"
        monthFormatter.locale = locale
        monthFormatter.dateFormat = isChinese ? "M月" : "MMM"
        needsDisplay = true
    }

    // MARK: - Tooltip tracking

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        setupTracking()
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let index = cellFrames.firstIndex { $0.rect.insetBy(dx: -1.5, dy: -1.5).contains(location) }
        if index != hoveredIndex {
            hoveredIndex = index
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredIndex != nil {
            hoveredIndex = nil
            needsDisplay = true
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1 // Sunday-stable grid, like GitHub
        let today = calendar.startOfDay(for: Date())

        let weeks = max(1, Int((bounds.width - leftInset - 2) / step))
        let weekday = calendar.component(.weekday, from: today)
        guard let currentWeekStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) else { return }

        // Resolve tokens per visible day.
        var dayValues: [Date: Int64] = [:]
        var maxTokens: Int64 = 0
        var totalTokens: Int64 = 0
        for c in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * (weeks - 1 - c), to: currentWeekStart) else { continue }
            for r in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: r, to: weekStart) else { continue }
                guard date <= today else { continue }
                let key = dayKeyFormatter.string(from: date)
                let tokens = dailyTokens[key] ?? 0
                dayValues[date] = tokens
                if tokens > maxTokens { maxTokens = tokens }
                totalTokens += tokens
            }
        }

        cellFrames = []

        if maxTokens <= 0 {
            drawNoData(ctx: ctx)
            return
        }

        drawMonthLabels(ctx: ctx, calendar: calendar, weeks: weeks, currentWeekStart: currentWeekStart, today: today)
        drawWeekdayLabels(ctx: ctx)

        let maxLog = log(Double(maxTokens) + 1)
        for c in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * (weeks - 1 - c), to: currentWeekStart) else { continue }
            for r in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: r, to: weekStart) else { continue }
                guard date <= today else { continue }
                let tokens = dayValues[date] ?? 0
                let rect = CGRect(
                    x: leftInset + CGFloat(c) * step,
                    y: topInset + CGFloat(r) * step,
                    width: cellSize,
                    height: cellSize
                )
                let level = colorLevel(tokens: tokens, maxLog: maxLog)
                let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
                ctx.saveGState()
                ctx.setFillColor(color(for: level).cgColor)
                ctx.addPath(path)
                ctx.fillPath()
                ctx.restoreGState()
                cellFrames.append((rect, date, tokens))
            }
        }

        if let hoveredIndex, cellFrames.indices.contains(hoveredIndex) {
            let cell = cellFrames[hoveredIndex]
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(1)
            let path = CGPath(roundedRect: cell.rect.insetBy(dx: -0.5, dy: -0.5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }

        drawLegend(ctx: ctx, totalTokens: totalTokens)

        if let hoveredIndex, cellFrames.indices.contains(hoveredIndex) {
            let cell = cellFrames[hoveredIndex]
            let text = "\(tooltipDateFormatter.string(from: cell.date)) · \(formatTokens(cell.tokens)) tokens"
            drawTooltip(ctx: ctx, text: text, near: cell.rect)
        }
    }

    private func drawNoData(ctx: CGContext) {
        let text = L10n.text(.noActivityData, language: language) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private func drawMonthLabels(
        ctx: CGContext,
        calendar: Calendar,
        weeks: Int,
        currentWeekStart: Date,
        today: Date
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        var lastLabelMaxX: CGFloat = -.infinity
        var lastMonth = -1
        for c in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * (weeks - 1 - c), to: currentWeekStart) else { continue }
            let month = calendar.component(.month, from: weekStart)
            guard month != lastMonth else { continue }
            lastMonth = month
            let label = monthFormatter.string(from: weekStart) as NSString
            let size = label.size(withAttributes: attrs)
            let x = leftInset + CGFloat(c) * step
            guard x - lastLabelMaxX >= size.width + 8 else { continue }
            guard x + size.width <= bounds.width else { continue }
            label.draw(at: CGPoint(x: x, y: 1), withAttributes: attrs)
            lastLabelMaxX = x + size.width
        }
    }

    private func drawWeekdayLabels(ctx: CGContext) {
        let isChinese = language.resolved == .simplifiedChinese
        let labels: [(row: Int, zh: String, en: String)] = [
            (1, "一", "Mon"),
            (3, "三", "Wed"),
            (5, "五", "Fri")
        ]
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        for entry in labels {
            let label = (isChinese ? entry.zh : entry.en) as NSString
            let size = label.size(withAttributes: attrs)
            let y = topInset + CGFloat(entry.row) * step + (cellSize - size.height) / 2
            label.draw(at: CGPoint(x: leftInset - size.width - 5, y: y), withAttributes: attrs)
        }
    }

    private func drawLegend(ctx: CGContext, totalTokens: Int64) {
        let y = topInset + 7 * step + 4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let isChinese = language.resolved == .simplifiedChinese

        var x = leftInset
        let less = L10n.text(.less, language: language) as NSString
        less.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
        x += less.size(withAttributes: attrs).width + 4

        for level in 0...4 {
            let rect = CGRect(x: x, y: y + 1, width: 8, height: 8)
            let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
            ctx.saveGState()
            ctx.setFillColor(color(for: level).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
            x += 10
        }

        let more = L10n.text(.more, language: language) as NSString
        more.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)

        let total = "\(isChinese ? "共" : "Σ") \(formatTokens(totalTokens)) tokens" as NSString
        let totalSize = total.size(withAttributes: attrs)
        total.draw(at: CGPoint(x: bounds.width - totalSize.width - 2, y: y), withAttributes: attrs)
    }

    private func drawTooltip(ctx: CGContext, text: String, near cell: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let nsText = text as NSString
        let textSize = nsText.size(withAttributes: attrs)
        let padding: CGFloat = 6
        let boxWidth = textSize.width + padding * 2
        let boxHeight = textSize.height + padding * 2

        var boxX = cell.midX - boxWidth / 2
        boxX = max(2, min(boxX, bounds.width - boxWidth - 2))
        var boxY = cell.minY - boxHeight - 5
        if boxY < 0 {
            boxY = cell.maxY + 5
        }

        let boxRect = CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)
        ctx.saveGState()
        ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor)
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.5)
        let path = CGPath(roundedRect: boxRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()

        nsText.draw(at: CGPoint(x: boxX + padding, y: boxY + padding), withAttributes: attrs)
    }

    // MARK: - Color scale

    private func colorLevel(tokens: Int64, maxLog: Double) -> Int {
        guard tokens > 0 else { return 0 }
        let ratio = log(Double(tokens) + 1) / maxLog
        return max(1, min(4, Int(ceil(ratio * 4))))
    }

    private func color(for level: Int) -> NSColor {
        switch level {
        case 0:
            return NSColor.tertiaryLabelColor.withAlphaComponent(0.3)
        case 1:
            return NSColor.systemBlue.withAlphaComponent(0.3)
        case 2:
            return NSColor.systemBlue.withAlphaComponent(0.5)
        case 3:
            return NSColor.systemBlue.withAlphaComponent(0.75)
        default:
            return NSColor.systemBlue
        }
    }

    private func formatTokens(_ value: Int64) -> String {
        let isChinese = language.resolved == .simplifiedChinese
        if isChinese {
            if value >= 100_000_000 { return String(format: "%.1f 亿", Double(value) / 1e8) }
            if value >= 10_000 { return String(format: "%.1f 万", Double(value) / 1e4) }
            return "\(value)"
        }
        if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1e9) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1e6) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1e3) }
        return "\(value)"
    }
}
