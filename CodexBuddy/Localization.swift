import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

enum L10nKey {
    case usage
    case updatedAt
    case neverUpdated
    case loadingUsage
    case refreshing
    case refresh
    case openOfficialUsage
    case settings
    case launchAtLogin
    case refreshInterval
    case notifications
    case enableNotifications
    case notifyBelow
    case language
    case systemLanguage
    case simplifiedChinese
    case english
    case quit
    case seconds
    case percentRemaining
    case shortWindowNotificationTitle
    case weekWindowNotificationTitle
    case dataSourceUnavailable
    case notLoggedIn
    case unreadableUsage
    case schemaDrift
    case dataSource
    case sessionEvent
    case responseHeaderFallback
    case dataMayBeStale
    case justNow
    case minutesAgo
    case about
    case used
    case resetExpired
    case otherWindow
    case settingsTooltip
    case depletionEstimate
    case planType
    case creditsBalance
    case exportDiagnostic
    case checkForUpdates
    case updateAvailable
    case upToDate
    case exportCSV
    case menuBarDisplay
    case displayMode
    case dualWindowMode
    case worstWindowMode
    case showShortWindow
    case showWeekWindow
    case resetCountdownTitle
    case resetCountdownBody
    case tokenActivity
    case noActivityData
    case less
    case more
}

enum L10n {
    static func launchAtLoginTitle(isEnabled: Bool, language: AppLanguage) -> String {
        let state: String
        switch language.resolved {
        case .simplifiedChinese:
            state = isEnabled ? "已开启" : "已关闭"
        case .english, .system:
            state = isEnabled ? "On" : "Off"
        }
        return "\(text(.launchAtLogin, language: language)) · \(state)"
    }

    static func text(_ key: L10nKey, language: AppLanguage) -> String {
        switch language.resolved {
        case .simplifiedChinese:
            return chinese(key)
        case .english, .system:
            return english(key)
        }
    }

    private static func chinese(_ key: L10nKey) -> String {
        switch key {
        case .usage: return "用量"
        case .updatedAt: return "上次更新"
        case .neverUpdated: return "尚未成功更新"
        case .loadingUsage: return "正在读取用量..."
        case .refreshing: return "刷新中..."
        case .refresh: return "刷新用量"
        case .openOfficialUsage: return "打开官方 Usage"
        case .settings: return "设置"
        case .launchAtLogin: return "登录时启动"
        case .refreshInterval: return "刷新频率"
        case .notifications: return "低用量提醒"
        case .enableNotifications: return "启用提醒"
        case .notifyBelow: return "提醒阈值"
        case .language: return "语言"
        case .systemLanguage: return "跟随系统"
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        case .quit: return "退出"
        case .seconds: return "秒"
        case .percentRemaining: return "剩余"
        case .shortWindowNotificationTitle: return "短时用量即将耗尽"
        case .weekWindowNotificationTitle: return "每周用量即将耗尽"
        case .dataSourceUnavailable: return "当前没有可用的官方 Usage 数据源。"
        case .notLoggedIn: return "未检测到 Codex 登录状态。请先登录 Codex 后重试。"
        case .unreadableUsage: return "无法自动读取官方 Usage。请打开官方 Usage 页面查看。"
        case .schemaDrift: return "会话日志格式可能已变化，当前显示的是备用数据。请检查 App 更新。"
        case .dataSource: return "数据来源"
        case .sessionEvent: return "实时事件"
        case .responseHeaderFallback: return "响应头备用"
        case .dataMayBeStale: return "数据可能已过期"
        case .justNow: return "刚刚更新"
        case .minutesAgo: return "分钟前"
        case .about: return "关于"
        case .used: return "已使用"
        case .resetExpired: return "等待新周期"
        case .otherWindow: return "其他窗口"
        case .settingsTooltip: return "打开设置"
        case .depletionEstimate: return "耗尽预估"
        case .planType: return "套餐"
        case .creditsBalance: return "Credits 余额"
        case .exportDiagnostic: return "导出诊断报告"
        case .checkForUpdates: return "检查更新"
        case .updateAvailable: return "发现新版本"
        case .upToDate: return "已是最新版本"
        case .exportCSV: return "导出 CSV"
        case .menuBarDisplay: return "菜单栏显示"
        case .displayMode: return "显示模式"
        case .dualWindowMode: return "双窗口"
        case .worstWindowMode: return "单值（最紧张）"
        case .showShortWindow: return "短时窗口"
        case .showWeekWindow: return "每周窗口"
        case .resetCountdownTitle: return "用量即将重置"
        case .resetCountdownBody: return "用量将在 5 分钟内重置，可放心使用"
        case .tokenActivity: return "Token 活动"
        case .noActivityData: return "暂无 Token 活动数据，使用一段时间后自动生成"
        case .less: return "少"
        case .more: return "多"
        }
    }

    private static func english(_ key: L10nKey) -> String {
        switch key {
        case .usage: return "Usage"
        case .updatedAt: return "Last updated"
        case .neverUpdated: return "Not updated yet"
        case .loadingUsage: return "Reading usage..."
        case .refreshing: return "Refreshing..."
        case .refresh: return "Refresh Usage"
        case .openOfficialUsage: return "Open Official Usage"
        case .settings: return "Settings"
        case .launchAtLogin: return "Launch at Login"
        case .refreshInterval: return "Refresh Interval"
        case .notifications: return "Low-Usage Alerts"
        case .enableNotifications: return "Enable Alerts"
        case .notifyBelow: return "Alert Threshold"
        case .language: return "Language"
        case .systemLanguage: return "System Default"
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        case .quit: return "Quit"
        case .seconds: return "sec"
        case .percentRemaining: return "remaining"
        case .shortWindowNotificationTitle: return "Short-window usage is running low"
        case .weekWindowNotificationTitle: return "Weekly usage is running low"
        case .dataSourceUnavailable: return "No official Usage data source is currently available."
        case .notLoggedIn: return "Codex login was not detected. Sign in to Codex and try again."
        case .unreadableUsage: return "Official Usage could not be read automatically. Open the official Usage page to check."
        case .schemaDrift: return "The session log format may have changed. Fallback data is shown; check for app updates."
        case .dataSource: return "Source"
        case .sessionEvent: return "Live event"
        case .responseHeaderFallback: return "Response-header fallback"
        case .dataMayBeStale: return "Data may be stale"
        case .justNow: return "Updated just now"
        case .minutesAgo: return "min ago"
        case .about: return "About"
        case .used: return "used"
        case .resetExpired: return "Awaiting new period"
        case .otherWindow: return "Other window"
        case .settingsTooltip: return "Open Settings"
        case .depletionEstimate: return "Depletion Estimate"
        case .planType: return "Plan"
        case .creditsBalance: return "Credits Balance"
        case .exportDiagnostic: return "Export Diagnostic Report"
        case .checkForUpdates: return "Check for Updates"
        case .updateAvailable: return "Update Available"
        case .upToDate: return "Up to Date"
        case .exportCSV: return "Export CSV"
        case .menuBarDisplay: return "Menu Bar Display"
        case .displayMode: return "Display Mode"
        case .dualWindowMode: return "Two Windows"
        case .worstWindowMode: return "Single Value (Most Urgent)"
        case .showShortWindow: return "Short Window"
        case .showWeekWindow: return "Weekly Window"
        case .resetCountdownTitle: return "Usage Reset Imminent"
        case .resetCountdownBody: return "Usage will reset within 5 minutes"
        case .tokenActivity: return "Token Activity"
        case .noActivityData: return "No token activity yet — will populate after some usage"
        case .less: return "Less"
        case .more: return "More"
        }
    }
}
