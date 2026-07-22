import AppKit
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

                // Verify SHA-256 if available
                if let shaURL = checker.latestSHA256URL {
                    let valid = try await verifySHA256(fileURL: zipURL, shaURL: shaURL)
                    if !valid {
                        state = .failed("SHA-256 verification failed")
                        try? FileManager.default.removeItem(at: zipURL)
                        return
                    }
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
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UpdateError.downloadFailed
        }

        let expectedLength = response.expectedContentLength
        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent("\(ProductIdentity.name)-update-\(UUID().uuidString).zip")

        var downloaded: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(expectedLength > 0 ? Int(min(expectedLength, 50 * 1024 * 1024)) : 1024 * 1024)

        for try await byte in asyncBytes {
            buffer.append(byte)
            downloaded += 1

            if expectedLength > 0, downloaded % 65536 == 0 {
                let progress = Double(downloaded) / Double(expectedLength) * 0.7
                state = .downloading(progress: progress)
            }
        }

        try buffer.write(to: zipURL)
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
        // Use CommonCrypto via Process for portability
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256_wrapper(ptr.baseAddress, Int(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
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

// CommonCrypto SHA-256 bridge
import CommonCrypto

private func CC_SHA256_wrapper(_ data: UnsafeRawPointer?, _ len: Int, _ md: UnsafeMutablePointer<UInt8>) -> Int32 {
    CC_SHA256(data, CC_LONG(len), md)
    return 0
}
