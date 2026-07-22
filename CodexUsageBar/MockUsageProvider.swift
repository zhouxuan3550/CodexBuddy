import Foundation

struct MockUsageProvider: UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot {
        return UsageSnapshot(
            shortWindow: nil,
            weekWindow: UsageWindow(
                minutes: 10_080,
                remainingPercent: 17,
                resetAt: Date().addingTimeInterval(3.4 * 86_400)
            ),
            updatedAt: Date(),
            source: .sessionEvent,
            planType: "plus",
            credits: CreditsInfo(hasCredits: true, unlimited: false, balance: "2500")
        )
    }
}
