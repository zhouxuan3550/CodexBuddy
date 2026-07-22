import Foundation

/// Persists daily token-consumption totals to power the activity heatmap.
/// Backfills history by incrementally scanning Codex session .jsonl files:
/// each file is only re-read from the byte offset processed last time, so
/// repeated scans are cheap. Results are cached on disk.
@MainActor
final class UsageActivityStore: ObservableObject {
    /// Maps a local calendar day ("yyyy-MM-dd") to total tokens consumed.
    @Published private(set) var dailyTokens: [String: Int64] = [:]

    private let cacheURL: URL
    private let sessionsRoot: URL
    private var fileOffsets: [String: UInt64] = [:]
    private var isScanning = false

    init(directory: URL? = nil) {
        let dir = directory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex-usage-history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("activity.json")
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

        Task.detached(priority: .utility) { [weak self] in
            var (delta, newOffsets, truncated) = Self.scan(root: root, offsets: offsets)
            if truncated {
                // A file shrank (rotation/truncation): rebuild everything from scratch.
                let (full, allOffsets, _) = Self.scan(root: root, offsets: [:])
                delta = full
                newOffsets = allOffsets
            }
            let finalDelta = delta
            let finalOffsets = newOffsets
            let replace = truncated
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isScanning = false
                self.apply(delta: finalDelta, offsets: finalOffsets, replace: replace)
            }
        }
    }

    // MARK: - Private

    private func apply(delta: [String: Int64], offsets: [String: UInt64], replace: Bool) {
        if replace {
            dailyTokens = delta
        } else {
            for (day, tokens) in delta {
                dailyTokens[day, default: 0] += tokens
            }
        }
        fileOffsets = offsets
        save()
    }

    private nonisolated static func scan(
        root: URL,
        offsets: [String: UInt64]
    ) -> (delta: [String: Int64], offsets: [String: UInt64], truncated: Bool) {
        var delta: [String: Int64] = [:]
        var newOffsets = offsets
        var truncated = false

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return (delta, newOffsets, truncated)
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
                truncated = true
                continue
            }
            if size == stored {
                continue
            }

            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { continue }
            defer { try? handle.close() }

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
                            processLine(buffer[cursor..<newline], into: &delta, dayFormatter: dayFormatter)
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
                newOffsets[path] = consumed
            } catch {
                continue
            }
        }

        return (delta, newOffsets, truncated)
    }

    private nonisolated static func processLine(
        _ line: Data,
        into delta: inout [String: Int64],
        dayFormatter: DateFormatter
    ) {
        guard line.range(of: Data("token_count".utf8)) != nil else { return }
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let payload = object["payload"] as? [String: Any],
            payload["type"] as? String == "token_count",
            let timestamp = object["timestamp"] as? String,
            let date = isoDate(timestamp)
        else { return }

        let info = payload["info"] as? [String: Any]
        let lastUsage = info?["last_token_usage"] as? [String: Any]
        let tokens = (lastUsage?["total_tokens"] as? NSNumber)?.int64Value ?? 0
        let day = dayFormatter.string(from: date)
        delta[day, default: 0] += tokens
    }

    private nonisolated static func isoDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private struct Cache: Codable {
        var dailyTokens: [String: Int64]
        var fileOffsets: [String: UInt64]
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        guard let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        dailyTokens = cache.dailyTokens
        fileOffsets = cache.fileOffsets
    }

    private func save() {
        let cache = Cache(dailyTokens: dailyTokens, fileOffsets: fileOffsets)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
