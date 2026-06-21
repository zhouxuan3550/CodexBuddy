import Foundation

struct CodexUsageProvider: UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot {
        throw UsageProviderError.dataSourceUnavailable
    }
}
