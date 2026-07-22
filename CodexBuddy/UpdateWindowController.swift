import AppKit

/// Floating window showing update download progress and release notes.
@MainActor
final class UpdateWindowController: NSWindowController {
    private let progressView = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let notesView = NSTextView()
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    private var onCancel: (() -> Void)?

    static func show(
        version: String,
        releaseNotesURL: String?,
        language: AppLanguage,
        onCancel: @escaping () -> Void
    ) -> UpdateWindowController {
        let controller = UpdateWindowController(language: language, onCancel: onCancel)
        controller.window?.title = language.resolved == .simplifiedChinese
            ? "正在更新到 v\(version)"
            : "Updating to v\(version)"
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let urlString = releaseNotesURL, let url = URL(string: urlString) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let html = String(data: data, encoding: .utf8) {
                    controller.notesView.string = html
                }
            }
        }

        return controller
    }

    private init(language: AppLanguage, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating

        super.init(window: window)

        cancelButton.title = language.resolved == .simplifiedChinese ? "取消" : "Cancel"
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.bezelStyle = .rounded

        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.stringValue = language.resolved == .simplifiedChinese ? "正在下载..." : "Downloading..."

        progressView.style = .bar
        progressView.isIndeterminate = false
        progressView.minValue = 0
        progressView.maxValue = 1.0
        progressView.doubleValue = 0

        notesView.isEditable = false
        notesView.isSelectable = true
        notesView.font = NSFont.systemFont(ofSize: 11)
        notesView.string = ""

        let scrollView = NSScrollView()
        scrollView.documentView = notesView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let content = window.contentView!
        content.addSubview(statusLabel)
        content.addSubview(progressView)
        content.addSubview(scrollView)
        content.addSubview(cancelButton)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),

            progressView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),

            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -12),

            cancelButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cancelButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func updateProgress(_ fraction: Double) {
        progressView.doubleValue = fraction
        statusLabel.stringValue = "\(Int(fraction * 100))%"
    }

    func setInstalling() {
        progressView.isIndeterminate = true
        progressView.startAnimation(nil)
        statusLabel.stringValue = "Installing..."
        cancelButton.isEnabled = false
    }

    @objc private func cancelClicked() {
        onCancel?()
        window?.close()
    }
}
