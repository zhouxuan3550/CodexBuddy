import AppKit
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let provider: UsageProvider
    private let timeFormatter: DateFormatter

    init(provider: UsageProvider) {
        self.provider = provider
        self.timeFormatter = DateFormatter()
        self.timeFormatter.locale = Locale(identifier: "zh_CN")
        self.timeFormatter.dateFormat = "HH:mm"
    }

    var statusText: String {
        if isLoading, snapshot == nil {
            return "h-- w--"
        }

        if let snapshot {
            return snapshot.menuBarText
        }

        return "h-- w--"
    }

    var updatedAtText: String {
        guard let updatedAt = snapshot?.updatedAt else {
            return "尚未成功更新"
        }

        return "上次更新：\(timeFormatter.string(from: updatedAt))"
    }

    var detailMessage: String {
        if let errorMessage, snapshot == nil {
            return errorMessage
        }

        if snapshot == nil {
            return "正在读取 Usage..."
        }

        if let errorMessage {
            return errorMessage
        }

        return ""
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            snapshot = try await provider.fetchUsage()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "无法读取 Usage"
        }
    }

    func openOfficialUsage() {
        guard let url = URL(string: "https://chatgpt.com/codex/usage") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
