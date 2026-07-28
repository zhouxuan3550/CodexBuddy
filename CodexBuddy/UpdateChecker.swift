import Foundation

/// Checks GitHub Releases for new versions silently at launch.
@MainActor
final class UpdateChecker {
    nonisolated static let defaultRepoOwner = ProductIdentity.repositoryOwner
    nonisolated static let defaultRepoName = ProductIdentity.repositoryName
    nonisolated static var defaultRepository: String { "\(defaultRepoOwner)/\(defaultRepoName)" }
    #if arch(arm64)
    nonisolated static let currentArchitecture = "arm64"
    #elseif arch(x86_64)
    nonisolated static let currentArchitecture = "x86_64"
    #endif

    nonisolated static func preferredAssetName(
        in names: [String],
        architecture: String = currentArchitecture,
        suffix: String
    ) -> String? {
        names.first { $0.hasSuffix("-\(architecture)\(suffix)") }
    }

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
                let names = assets.compactMap { $0["name"] as? String }
                let zipName = Self.preferredAssetName(in: names, suffix: ".zip")
                let shaName = Self.preferredAssetName(in: names, suffix: ".zip.sha256")
                let zipAsset = assets.first { ($0["name"] as? String) == zipName }
                let shaAsset = assets.first { ($0["name"] as? String) == shaName }
                latestAssetURL = (zipAsset?["browser_download_url"] as? String).flatMap { URL(string: $0) }
                latestSHA256URL = (shaAsset?["browser_download_url"] as? String).flatMap { URL(string: $0) }
            }

            if Self.isNewer(release.version, than: currentVersion) {
                availableUpdate = release
            } else {
                availableUpdate = nil
            }
        } catch {
            // Silent failure — update check is best-effort
        }
    }

    /// SemVer-style comparison: numeric core first, then pre-release rules
    /// (a pre-release precedes its release: 0.8.0-beta.1 < 0.8.0).
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let split: (String) -> (core: [Int], prerelease: String?) = { version in
            let parts = version.split(separator: "-", maxSplits: 1)
            let core = parts[0].split(separator: ".").compactMap { Int($0) }
            let prerelease = parts.count > 1 ? String(parts[1]) : nil
            return (core, prerelease)
        }
        let c = split(candidate)
        let cur = split(current)

        for i in 0..<max(c.core.count, cur.core.count) {
            let cv = i < c.core.count ? c.core[i] : 0
            let curv = i < cur.core.count ? cur.core[i] : 0
            if cv > curv { return true }
            if cv < curv { return false }
        }

        // Same numeric core: release > pre-release; two pre-releases compare
        // lexically (sufficient for beta.1/beta.2-style tags).
        switch (c.prerelease, cur.prerelease) {
        case (nil, nil): return false
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(lhs), .some(rhs)): return lhs > rhs
        }
    }

    // ISO8601DateFormatter is documented thread-safe, hence nonisolated(unsafe).
    private nonisolated(unsafe) static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let plainISOFormatter = ISO8601DateFormatter()

    private func isoDate(_ string: String) -> Date? {
        Self.fractionalISOFormatter.date(from: string) ?? Self.plainISOFormatter.date(from: string)
    }
}
