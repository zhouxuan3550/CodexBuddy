import Foundation

struct UsageSnapshot: Equatable {
    let shortWindowLabel: String
    let shortWindowPercent: Int
    let shortWindowResetText: String
    let weekWindowLabel: String
    let weekWindowPercent: Int
    let weekWindowResetText: String
    let updatedAt: Date

    var menuBarText: String {
        "h\(shortWindowPercent) w\(weekWindowPercent)"
    }

    var fullMenuBarText: String {
        "\(compactShortLabel) \(shortWindowPercent)% · \(shortWindowResetText) | \(compactWeekLabel) \(weekWindowPercent)% · \(weekWindowResetText)"
    }

    var shortWindowLine: String {
        "\(shortWindowLabel) \(shortWindowPercent)% · \(shortWindowResetText)"
    }

    var weekWindowLine: String {
        "\(weekWindowLabel) \(weekWindowPercent)% · \(weekWindowResetText)"
    }

    private var compactShortLabel: String {
        shortWindowLabel.replacingOccurrences(of: " 小时", with: "h")
    }

    private var compactWeekLabel: String {
        weekWindowLabel.replacingOccurrences(of: " 周", with: "w")
    }
}
