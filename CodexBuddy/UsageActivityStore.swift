import Foundation

/// Per-day token totals broken down by project, model and source, plus the
/// cached/uncached input split. Powers the dashboard insight cards.
struct UsageDayBreakdown: Codable, Equatable {
    var totalTokens: Int64 = 0
    var inputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var byProject: [String: Int64] = [:]
    var byModel: [String: Int64] = [:]
    var bySource: [String: Int64] = [:]

    mutating func merge(_ other: UsageDayBreakdown) {
        totalTokens += other.totalTokens
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        for (key, value) in other.byProject { byProject[key, default: 0] += value }
        for (key, value) in other.byModel { byModel[key, default: 0] += value }
        for (key, value) in other.bySource { bySource[key, default: 0] += value }
    }
}

/// Aggregates the trailing 7 days for the weekly recap notification: total
/// tokens, the hottest project, and the change versus the 7 days before.
struct UsageWeeklyReportStats: Equatable {
    let totalTokens: Int64
    let topProject: String?
    let deltaPercent: Int?

    static func build(
        dailyBreakdown: [String: UsageDayBreakdown],
        now: Date = Date()
    ) -> UsageWeeklyReportStats {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current

        var current = UsageDayBreakdown()
        var previousTotal: Int64 = 0
        for offset in 0..<14 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now),
                  let day = dailyBreakdown[formatter.string(from: date)] else { continue }
            if offset < 7 {
                current.merge(day)
            } else {
                previousTotal += day.totalTokens
            }
        }

        let topEntry = current.byProject
            .filter { !$0.key.isEmpty }
            .max { $0.value < $1.value }
        let delta: Int?
        if previousTotal > 0 {
            delta = Int((Double(current.totalTokens - previousTotal) / Double(previousTotal) * 100).rounded())
        } else {
            delta = nil
        }
        return UsageWeeklyReportStats(
            totalTokens: current.totalTokens,
            topProject: topEntry.map { ($0.key as NSString).lastPathComponent },
            deltaPercent: delta
        )
    }
}

/// Persists daily token-consumption totals to power the activity heatmap and
/// insight cards. Backfills history by incrementally scanning Codex session
/// .jsonl files: each file is only re-read from the byte offset processed last
/// time, so repeated scans are cheap. Results are cached on disk.
@MainActor
final class UsageActivityStore: ObservableObject {
    /// Maps a local calendar day ("yyyy-MM-dd") to total tokens consumed.
    @Published private(set) var dailyTokens: [String: Int64] = [:]
    /// Maps a local calendar day to its dimensional breakdown.
    @Published private(set) var dailyBreakdown: [String: UsageDayBreakdown] = [:]

    private let cacheURL: URL
    private let sessionsRoot: URL
    private var fileOffsets: [String: UInt64] = [:]
    private var fileContexts: [String: FileContext] = [:]
    private var isScanning = false

    init(directory: URL? = nil) {
        let dir = directory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex-buddy-history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // v2 adds breakdowns; the v1 cache lacks them, so a fresh file forces
        // one full rescan that backfills every dimension.
        cacheURL = dir.appendingPathComponent("activity-v2.json")
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("activity.json"))
        sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        load()
    }

    /// Scans session files for new token events. Safe to call often; concurrent
    /// calls are coalesced and only appended bytes are parsed.
    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        let root = sessionsRoot
        let offsets = fileOffsets
        let contexts = fileContexts

        Task.detached(priority: .utility) { [weak self] in
            var result = Self.scan(root: root, offsets: offsets, contexts: contexts)
            if result.truncated {
                // A file shrank (rotation/truncation): rebuild everything from scratch.
                result = Self.scan(root: root, offsets: [:], contexts: [:])
            }
            let finalResult = result
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isScanning = false
                self.apply(result: finalResult)
            }
        }
    }

    // MARK: - Private

    /// The most recent session metadata seen in a file; carried across scans
    /// because incremental reads resume past the lines that declared it.
    private struct FileContext: Codable {
        var project: String?
        var model: String?
        var source: String?
    }

    private struct ScanResult {
        var delta: [String: UsageDayBreakdown] = [:]
        var offsets: [String: UInt64] = [:]
        var contexts: [String: FileContext] = [:]
        var truncated = false
        var isFullScan = false
    }

    private func apply(result: ScanResult) {
        if result.isFullScan {
            dailyBreakdown = result.delta
        } else {
            for (day, breakdown) in result.delta {
                dailyBreakdown[day, default: UsageDayBreakdown()].merge(breakdown)
            }
        }
        dailyTokens = dailyBreakdown.mapValues(\.totalTokens)
        fileOffsets = result.offsets
        fileContexts = result.contexts
        save()
    }

    private nonisolated static func scan(
        root: URL,
        offsets: [String: UInt64],
        contexts: [String: FileContext]
    ) -> ScanResult {
        var result = ScanResult()
        result.offsets = offsets
        result.contexts = contexts
        result.isFullScan = offsets.isEmpty

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return result
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let chunkSize = 4 * 1024 * 1024
        let lineCap = 64 * 1024 * 1024

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            let path = fileURL.path
            guard
                let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                let size = (attrs[.size] as? NSNumber)?.uint64Value
            else { continue }

            let stored = offsets[path] ?? 0
            if size < stored {
                result.truncated = true
                continue
            }
            if size == stored {
                continue
            }

            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { continue }
            defer { try? handle.close() }

            var context = contexts[path] ?? FileContext()

            do {
                try handle.seek(toOffset: stored)
                var consumed = stored
                var buffer = Data()
                var finished = false

                // Stream the file in chunks; only complete (newline-terminated)
                // lines are consumed, so `consumed` always lands on a line
                // boundary and no event is ever lost between scans. Each chunk
                // is wrapped in an autoreleasepool — inside a detached task
                // there is no surrounding pool, so without this the read
                // buffers accumulate until the whole scan finishes.
                while !finished {
                    try autoreleasepool {
                        let chunk = try handle.read(upToCount: chunkSize) ?? Data()
                        if chunk.isEmpty {
                            finished = true
                            return
                        }
                        buffer.append(chunk)

                        var cursor = buffer.startIndex
                        while let newline = buffer[cursor...].firstIndex(of: 0x0A) {
                            processLine(
                                buffer[cursor..<newline],
                                into: &result.delta,
                                context: &context,
                                dayFormatter: dayFormatter
                            )
                            cursor = buffer.index(after: newline)
                        }
                        consumed += UInt64(buffer.distance(from: buffer.startIndex, to: cursor))
                        buffer.removeSubrange(buffer.startIndex..<cursor)

                        // Pathological unterminated line: skip it to keep progress.
                        if buffer.count > lineCap {
                            consumed += UInt64(buffer.count)
                            buffer.removeAll(keepingCapacity: false)
                        }
                    }
                }
                result.offsets[path] = consumed
                result.contexts[path] = context
            } catch {
                continue
            }
        }

        return result
    }

    private nonisolated static func processLine(
        _ line: Data,
        into delta: inout [String: UsageDayBreakdown],
        context: inout FileContext,
        dayFormatter: DateFormatter
    ) {
        // Cheap byte-level filter before paying for JSON parsing.
        let isTokenCount = line.range(of: Data("token_count".utf8)) != nil
        let isSessionMeta = line.range(of: Data("\"session_meta\"".utf8)) != nil
        let isTurnContext = line.range(of: Data("\"turn_context\"".utf8)) != nil
        guard isTokenCount || isSessionMeta || isTurnContext else { return }

        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let payload = object["payload"] as? [String: Any]
        else { return }

        switch object["type"] as? String {
        case "session_meta":
            if let cwd = payload["cwd"] as? String { context.project = cwd }
            if let source = payload["source"] as? String { context.source = source }
            return
        case "turn_context":
            if let cwd = payload["cwd"] as? String { context.project = cwd }
            if let model = payload["model"] as? String { context.model = model }
            return
        default:
            break
        }

        guard
            payload["type"] as? String == "token_count",
            let timestamp = object["timestamp"] as? String,
            let date = isoDate(timestamp)
        else { return }

        let info = payload["info"] as? [String: Any]
        let lastUsage = info?["last_token_usage"] as? [String: Any]
        let tokens = (lastUsage?["total_tokens"] as? NSNumber)?.int64Value ?? 0
        let input = (lastUsage?["input_tokens"] as? NSNumber)?.int64Value ?? 0
        let cached = (lastUsage?["cached_input_tokens"] as? NSNumber)?.int64Value ?? 0

        let day = dayFormatter.string(from: date)
        var breakdown = delta[day] ?? UsageDayBreakdown()
        breakdown.totalTokens += tokens
        breakdown.inputTokens += input
        breakdown.cachedInputTokens += cached
        if tokens > 0 {
            breakdown.byProject[context.project ?? "", default: 0] += tokens
            breakdown.byModel[context.model ?? "", default: 0] += tokens
            breakdown.bySource[context.source ?? "", default: 0] += tokens
        }
        delta[day] = breakdown
    }

    // ISO8601DateFormatter is thread-safe; cache instances because creation is
    // expensive and isoDate runs once per token_count line during full scans.
    private nonisolated(unsafe) static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let plainISOFormatter = ISO8601DateFormatter()

    private nonisolated static func isoDate(_ value: String) -> Date? {
        fractionalISOFormatter.date(from: value) ?? plainISOFormatter.date(from: value)
    }

    private struct Cache: Codable {
        var dailyBreakdown: [String: UsageDayBreakdown]
        var fileOffsets: [String: UInt64]
        var fileContexts: [String: FileContext]
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        guard let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        dailyBreakdown = cache.dailyBreakdown
        dailyTokens = cache.dailyBreakdown.mapValues(\.totalTokens)
        fileOffsets = cache.fileOffsets
        fileContexts = cache.fileContexts
    }

    private func save() {
        let cache = Cache(
            dailyBreakdown: dailyBreakdown,
            fileOffsets: fileOffsets,
            fileContexts: fileContexts
        )
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
