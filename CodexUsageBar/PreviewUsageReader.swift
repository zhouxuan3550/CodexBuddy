import Foundation

struct PreviewUsageReader: UsageReadingSource {
    func read() async throws -> UsageReadOutcome {
        UsageReadOutcome(reading: UsageReading(
            shortWindow: QuotaWindow(minutes: 300, remainingPercent: 72, resetAt: Date().addingTimeInterval(7_200)),
            weekWindow: QuotaWindow(minutes: 10_080, remainingPercent: 38, resetAt: Date().addingTimeInterval(4 * 86_400)),
            updatedAt: Date(),
            source: .sessionLog,
            planName: "plus",
            credits: CreditState(isAvailable: true, isUnlimited: false, balance: "2500")
        ))
    }
}
