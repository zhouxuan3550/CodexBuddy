import Foundation

/// Shared cache for UI-facing date formatters. `DateFormatter` creation is
/// expensive and several SwiftUI/AppKit render paths need one per render;
/// caching by locale + format eliminates that cost. `DateFormatter` itself is
/// thread-safe on modern macOS, so instances can be shared; the cache
/// dictionary is guarded by a lock.
enum UIDateFormatters {
    private static let lock = NSLock()
    private static var cache: [String: DateFormatter] = [:]

    static func formatter(dateFormat: String, localeIdentifier: String) -> DateFormatter {
        cached(key: "\(localeIdentifier)|\(dateFormat)") { formatter in
            formatter.locale = Locale(identifier: localeIdentifier)
            formatter.dateFormat = dateFormat
        }
    }

    static func mediumDate(localeIdentifier: String) -> DateFormatter {
        cached(key: "\(localeIdentifier)|<mediumDate>") { formatter in
            formatter.locale = Locale(identifier: localeIdentifier)
            formatter.dateStyle = .medium
        }
    }

    private static func cached(key: String, configure: (DateFormatter) -> Void) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[key] { return existing }
        let formatter = DateFormatter()
        configure(formatter)
        cache[key] = formatter
        return formatter
    }
}
