import Foundation

struct MockUsageProvider: UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot {
        try await Task.sleep(nanoseconds: 250_000_000)
        return UsageSnapshot(
            shortWindowLabel: "5 小时",
            shortWindowPercent: 89,
            shortWindowResetText: "23:31",
            weekWindowLabel: "1 周",
            weekWindowPercent: 32,
            weekWindowResetText: "6月26日",
            updatedAt: Date()
        )
    }
}
