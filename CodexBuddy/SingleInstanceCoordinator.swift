import AppKit
import Foundation

enum SingleInstanceCoordinator {
    static func otherProcessIDs(currentPID: Int32, runningPIDs: [Int32]) -> [Int32] {
        Array(Set(runningPIDs.filter { $0 != currentPID })).sorted()
    }

    @MainActor
    static func terminateOtherInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        let otherPIDs = Set(otherProcessIDs(
            currentPID: currentPID,
            runningPIDs: applications.map(\.processIdentifier)
        ))

        for application in applications where otherPIDs.contains(application.processIdentifier) {
            if !application.terminate() {
                application.forceTerminate()
            }
        }
    }
}
