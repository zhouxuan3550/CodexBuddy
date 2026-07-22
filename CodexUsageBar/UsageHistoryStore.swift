import Foundation

/// Persists usage snapshots locally as JSON for trend analysis.
/// Retains 7 days of history, sampling at most once per 60 seconds.
@MainActor
final class UsageHistoryStore {
    struct Record: Codable {
        let timestamp: Date
        let shortRemaining: Int?
        let weekRemaining: Int?
        let planType: String?
        let creditsBalance: String?
    }

    private static let minSampleInterval: TimeInterval = 60
    private static let retentionDays = 7

    private let fileURL: URL
    private let now: () -> Date
    private(set) var records: [Record] = []
    private var lastSampleTime: Date?

    init(directory: URL? = nil, now: @escaping () -> Date = Date.init) {
        let dir = directory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex-usage-history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        self.now = now
        load()
    }

    func record(reading: UsageReading) {
        let record = Record(
            timestamp: reading.updatedAt,
            shortRemaining: reading.shortWindow?.remainingPercent,
            weekRemaining: reading.weekWindow?.remainingPercent,
            planType: reading.planName,
            creditsBalance: reading.credits?.finiteBalance
        )
        if let last = records.last,
           last.timestamp == record.timestamp,
           last.shortRemaining == record.shortRemaining,
           last.weekRemaining == record.weekRemaining,
           last.planType == record.planType,
           last.creditsBalance == record.creditsBalance {
            return
        }

        let sampleTime = now()
        if let last = lastSampleTime, sampleTime.timeIntervalSince(last) < Self.minSampleInterval {
            return
        }
        lastSampleTime = sampleTime
        records.append(record)
        prune()
        save()
    }

    func records(since date: Date) -> [Record] {
        records.filter { $0.timestamp >= date }
    }

    func records24h(now: Date = Date()) -> [Record] {
        records(since: now.addingTimeInterval(-86_400))
    }

    func records7d(now: Date = Date()) -> [Record] {
        records(since: now.addingTimeInterval(-7 * 86_400))
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-TimeInterval(Self.retentionDays * 86_400))
        records.removeAll { $0.timestamp < cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([Record].self, from: data)) ?? []
        prune()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
