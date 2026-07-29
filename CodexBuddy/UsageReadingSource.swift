import Foundation

enum UsageReadError: Error, Equatable {
    case unavailable
    case unreadable
    case formatChanged(Date)
}

enum UsageHealthSignal: Equatable {
    case sessionFormatChanged(evidenceAt: Date)
    /// A newer event claimed a large quota recovery before the previous
    /// window's reset. The reader keeps the last internally consistent value
    /// instead of presenting an optimistic, likely cross-session value.
    case suspiciousQuotaRecovery(evidenceAt: Date)
}

struct UsageReadOutcome {
    let reading: UsageReading
    let healthSignal: UsageHealthSignal?

    init(reading: UsageReading, healthSignal: UsageHealthSignal? = nil) {
        self.reading = reading
        self.healthSignal = healthSignal
    }
}

protocol UsageReadingSource {
    func read() async throws -> UsageReadOutcome
}

extension UsageReadingSource {
    func readReading() async throws -> UsageReading {
        try await read().reading
    }
}
