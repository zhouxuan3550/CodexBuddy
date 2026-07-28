import Foundation

/// A compact explanation of whether the currently displayed quota can be
/// trusted. This is intentionally separate from the reader so UI, task
/// preflight and diagnostics can communicate the same confidence semantics.
enum UsageDataHealth {
    enum State: Equatable {
        case current
        case stale
        case attention
        case unavailable
    }

    struct Snapshot: Equatable {
        let state: State
        let source: UsageSource?
        let updatedAt: Date?
        let historySamples: Int
    }

    static func snapshot(
        reading: UsageReading?,
        issue: UsageViewModelIssue?,
        historySamples: Int,
        now: Date = Date()
    ) -> Snapshot {
        guard let reading else {
            return Snapshot(
                state: .unavailable,
                source: nil,
                updatedAt: nil,
                historySamples: historySamples
            )
        }

        let state: State
        if reading.isOutdated(at: now) {
            state = .stale
        } else if issue != nil {
            state = .attention
        } else {
            state = .current
        }
        return Snapshot(
            state: state,
            source: reading.source,
            updatedAt: reading.updatedAt,
            historySamples: historySamples
        )
    }
}
