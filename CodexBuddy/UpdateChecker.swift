import Foundation

/// Checks GitHub Releases for new versions silently at launch.
@MainActor
final class UpdateChecker {
    nonisolated static let defaultRepoOwner = ProductIdentity.repositoryOwner
    nonisolated static let defaultRepoName = ProductIdentity.repositoryName
    nonisolated static var defaultRepository: String { "\(defaultRepoOwner)/\(defaultRepoName)" }

    struct ReleaseInfo {
        let tagName: String
        let htmlURL: String
        let publishedAt: Date?

        var version: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }
    }

    @Published private(set) var availableUpdate: ReleaseInfo?
    @Published private(set) var isChecking = false
    @Published private(set) var latestAssetURL: URL?
    @Published private(set) var latestSHA256URL: URL?

    private let repoOwner: String
    private let repoName: String
    private let currentVersion: String
    private let defaults: UserDefaults
    private static let lastCheckKey = "updateChecker.lastCheckDate"
    private static let checkInterval: TimeInterval = 86_400  // 24 hours

    init(
        repoOwner: String = UpdateChecker.defaultRepoOwner,
        repoName: String = UpdateChecker.defaultRepoName,
        currentVersion: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.currentVersion = currentVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
        self.defaults = defaults
    }

    /// Checks if enough time has passed since last check, then fetches latest release.
    func checkIfNeeded() async {
        let lastCheck = Date(timeIntervalSince1970: defaults.double(forKey: Self.lastCheckKey))
        guard Date().timeIntervalSince(lastCheck) >= Self.checkInterval else { return }
        await checkNow()
    }

    /// Forces an immediate update check.
    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer {
            isChecking = false
            defaults.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String
            else { return }

            let publishedAt = (json["published_at"] as? String).flatMap { isoDate($0) }
            let release = ReleaseInfo(tagName: tagName, htmlURL: htmlURL, publishedAt: publishedAt)

            // Parse asset URLs
            if let assets = json["assets"] as? [[String: Any]] {
                let zipAsset = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
                let shaAsset = assets.first { ($0["name"] as? String)?.hasSuffix(".sha256") == true }
                latestAssetURL = (zipAsset?["browser_download_url"] as? String).flatMap { URL(string: $0) }
                latestSHA256URL = (shaAsset?["browser_download_url"] as? String).flatMap { URL(string: $0) }
            }

            if isNewer(release.version, than: currentVersion) {
                availableUpdate = release
            } else {
                availableUpdate = nil
            }
        } catch {
            // Silent failure — update check is best-effort
        }
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let parse: (String) -> [Int] = { version in
            version.split(separator: ".").compactMap { Int($0) }
        }
        let c = parse(candidate)
        let cur = parse(current)

        for i in 0..<max(c.count, cur.count) {
            let cv = i < c.count ? c[i] : 0
            let curv = i < cur.count ? cur[i] : 0
            if cv > curv { return true }
            if cv < curv { return false }
        }
        return false
    }

    private func isoDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
