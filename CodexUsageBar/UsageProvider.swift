import Foundation

enum UsageProviderError: LocalizedError, Equatable {
    case dataSourceUnavailable
    case notLoggedIn
    case unreadableUsage

    var errorDescription: String? {
        switch self {
        case .dataSourceUnavailable:
            return "当前没有可用的官方 Usage 数据源。"
        case .notLoggedIn:
            return "未检测到 Codex 登录状态。请先登录 Codex 后重试。"
        case .unreadableUsage:
            return "无法自动读取官方 Usage。请打开官方 Usage 页面查看。"
        }
    }
}

protocol UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot
}
