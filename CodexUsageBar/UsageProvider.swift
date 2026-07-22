import Foundation

enum UsageProviderError: Error, Equatable {
    case dataSourceUnavailable
    case notLoggedIn
    case unreadableUsage
    case schemaDrift
    case schemaDriftEvidence(Date)
}

enum UsageProviderDiagnostic: Equatable {
    case sessionSchemaDrift(evidenceAt: Date)
}

struct UsageFetchResult {
    let snapshot: UsageSnapshot
    let diagnostic: UsageProviderDiagnostic?
}

protocol UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot

    func fetchUsageResult() async throws -> UsageFetchResult
}

extension UsageProvider {
    func fetchUsageResult() async throws -> UsageFetchResult {
        UsageFetchResult(snapshot: try await fetchUsage(), diagnostic: nil)
    }
}
