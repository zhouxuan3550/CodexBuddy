import CoreServices
import Foundation

final class UsageFileMonitor {
    private let paths: [String]
    private let latency: TimeInterval
    private let onChange: () -> Void
    private let callbackQueue = DispatchQueue(label: "local.codex.usage.file-monitor")
    private var stream: FSEventStreamRef?

    init(
        paths: [String],
        latency: TimeInterval = 0.25,
        onChange: @escaping () -> Void
    ) {
        self.paths = paths
        self.latency = latency
        self.onChange = onChange
    }

    @discardableResult
    func start() -> Bool {
        if stream != nil {
            return true
        }
        guard !paths.isEmpty else {
            return false
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, contextInfo, _, _, _, _ in
            guard let contextInfo else { return }
            let monitor = Unmanaged<UsageFileMonitor>
                .fromOpaque(contextInfo)
                .takeUnretainedValue()
            monitor.onChange()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        )

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return false
        }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, callbackQueue)
        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            stream = nil
            return false
        }
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
