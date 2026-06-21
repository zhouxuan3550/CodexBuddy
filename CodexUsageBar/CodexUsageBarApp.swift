import AppKit
import Combine

@main
@MainActor
final class CodexUsageBarApp: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var store: UsageStore?
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = CodexUsageBarApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore(provider: MockUsageProvider())
        let controller = StatusBarController(store: store)
        self.store = store
        self.statusBarController = controller

        Publishers.CombineLatest3(store.$snapshot, store.$isLoading, store.$errorMessage)
            .sink { [weak controller] _, _, _ in
                Task { @MainActor in
                    controller?.refreshTitle()
                }
            }
            .store(in: &cancellables)

        Task { await store.refresh() }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak store] _ in
            guard let store else { return }
            Task { @MainActor in
                await store.refresh()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }
}
