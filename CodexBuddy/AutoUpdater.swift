import AppKit
import CryptoKit
import Foundation

/// Downloads, verifies, and installs updates from GitHub Releases.
@MainActor
final class AutoUpdater: ObservableObject {
    enum UpdateState {
        case idle
        case checking
        case available(UpdateChecker.ReleaseInfo)
        case downloading(progress: Double)
        case readyToInstall
        case installing
        case upToDate
        case failed(String)
    }

    @Published private(set) var state: UpdateState = .idle

    private let checker: UpdateChecker
    private var downloadTask: Task<Void, Never>?

    init(checker: UpdateChecker) {
        self.checker = checker
    }

    func checkForUpdate() async {
        state = .checking
        await checker.checkNow()
        if let release = checker.availableUpdate {
            state = .available(release)
        } else {
            state = .upToDate
        }
    }

    func downloadAndInstall() {
        guard case .available = state else { return }
        guard let assetURL = checker.latestAssetURL else {
            state = .failed("No download asset found")
            return
        }

        downloadTask = Task {
            do {
                state = .downloading(progress: 0)

                // Download ZIP
                let zipURL = try await downloadFile(from: assetURL)

                state = .downloading(progress: 0.7)

                // SHA-256 checksum is mandatory: refuse to install unverifiable payloads.
                guard let shaURL = checker.latestSHA256URL else {
                    state = .failed("Missing SHA-256 checksum for update asset")
                    try? FileManager.default.removeItem(at: zipURL)
                    return
                }
                let valid = try await verifySHA256(fileURL: zipURL, shaURL: shaURL)
                if !valid {
                    state = .failed("SHA-256 verification failed")
                    try? FileManager.default.removeItem(at: zipURL)
                    return
                }

                state = .downloading(progress: 0.9)

                // Unzip and install
                try installUpdate(zipURL: zipURL)

                state = .installing
                relaunchApp()
            } catch {
                if !Task.isCancelled {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }

    // MARK: - Private

    private func downloadFile(from url: URL) async throws -> URL {
        let request = URLRequest(url: url, timeoutInterval: 120)
        // Delegate-based download avoids per-byte async iteration for multi-MB assets.
        let delegate = DownloadProgressDelegate { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.state else { return }
                self.state = .downloading(progress: fraction * 0.7)
            }
        }
        let (tempURL, response) = try await URLSession.shared.download(for: request, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw UpdateError.downloadFailed
        }

        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent("\(ProductIdentity.name)-update-\(UUID().uuidString).zip")
        try FileManager.default.moveItem(at: tempURL, to: zipURL)
        return zipURL
    }

    private func verifySHA256(fileURL: URL, shaURL: URL) async throws -> Bool {
        let (data, _) = try await URLSession.shared.data(from: shaURL)
        guard let shaContent = String(data: data, encoding: .utf8) else { return false }

        // Format: "<hash>  <filename>"
        let expectedHash = shaContent.split(separator: " ").first.map(String.init)?.lowercased()
        guard let expected = expectedHash else { return false }

        let fileData = try Data(contentsOf: fileURL)
        let actual = sha256Hex(fileData)
        return actual == expected
    }

    private func installUpdate(zipURL: URL) throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("\(ProductIdentity.name)-install-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, tempDir.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.unzipFailed
        }

        // Find the .app in extracted contents
        let contents = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.appNotFoundInArchive
        }

        // Current app location
        let currentAppURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let parentDir = currentAppURL.deletingLastPathComponent()
        let backupURL = parentDir.appendingPathComponent(".\(ProductIdentity.name)-backup.app")

        // Replace: move current to backup, move new into place
        try? fm.removeItem(at: backupURL)
        try fm.moveItem(at: currentAppURL, to: backupURL)

        do {
            try fm.moveItem(at: newApp, to: currentAppURL)
        } catch {
            // Rollback
            try? fm.moveItem(at: backupURL, to: currentAppURL)
            throw error
        }

        // Cleanup
        try? fm.removeItem(at: backupURL)
        try? fm.removeItem(at: tempDir)
        try? fm.removeItem(at: zipURL)
    }

    private func relaunchApp() {
        let appPath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [appPath]
        try? process.run()

        // Give open a moment, then terminate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    enum UpdateError: LocalizedError {
        case downloadFailed
        case unzipFailed
        case appNotFoundInArchive

        var errorDescription: String? {
            switch self {
            case .downloadFailed: return "Download failed"
            case .unzipFailed: return "Failed to extract update"
            case .appNotFoundInArchive: return "App not found in archive"
            }
        }
    }
}

/// Reports download progress for the async `URLSession.download(for:delegate:)` API.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The async download(for:) API surfaces the file URL directly.
    }
}
