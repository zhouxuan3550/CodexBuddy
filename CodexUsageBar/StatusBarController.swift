import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: UsageStore

    init(store: UsageStore) {
        self.store = store
        super.init()
        configureStatusItem()
        rebuildMenu()
    }

    func refreshTitle() {
        statusItem.length = NSStatusItem.variableLength
        statusItem.button?.image = nil
        statusItem.button?.title = store.statusText
        rebuildMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = nil
        button.imagePosition = .noImage
        button.title = store.statusText
        button.toolTip = "Codex Usage"
        writeDebugLog("status button created: \(button)")
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let titleItem = NSMenuItem(title: "Usage", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        if let snapshot = store.snapshot {
            menu.addItem(disabledItem(snapshot.shortWindowLine))
            menu.addItem(disabledItem(snapshot.weekWindowLine))
            menu.addItem(disabledItem(store.updatedAtText))

            if !store.detailMessage.isEmpty {
                menu.addItem(disabledItem(store.detailMessage))
            }
        } else {
            menu.addItem(disabledItem(store.detailMessage))
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: store.isLoading ? "刷新中..." : "刷新",
            action: #selector(refreshUsage),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = !store.isLoading
        menu.addItem(refreshItem)

        let openItem = NSMenuItem(
            title: "打开官方 Usage",
            action: #selector(openOfficialUsage),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        Task { await store.refresh() }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func refreshUsage() {
        Task { await store.refresh() }
    }

    @objc private func openOfficialUsage() {
        store.openOfficialUsage()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func writeDebugLog(_ message: String) {
        let url = URL(fileURLWithPath: "/tmp/CodexUsageBar.log")
        let line = "\(Date()) \(message)\n"

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
