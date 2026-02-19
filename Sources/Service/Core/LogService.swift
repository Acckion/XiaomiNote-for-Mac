import OSLog

/// 日志模块标识
public enum LogModule: String, CaseIterable, Sendable {
    case storage
    case network
    case sync
    case core
    case editor
    case app
    case viewmodel
    case window
    case audio
}

/// 统一日志服务
public final class LogService: Sendable {
    public static let shared = LogService()

    private static let subsystem = "com.mi.note.mac"

    /// 每个模块对应一个 os.Logger 实例
    private let loggers: [LogModule: Logger]

    private init() {
        var map: [LogModule: Logger] = [:]
        for module in LogModule.allCases {
            map[module] = Logger(subsystem: LogService.subsystem, category: module.rawValue)
        }
        self.loggers = map
    }

    /// 获取指定模块的 Logger
    private func logger(for module: LogModule) -> Logger {
        loggers[module]!
    }

    // MARK: - 日志方法

    public func debug(_ module: LogModule, _ message: String) {
        logger(for: module).debug("[\(module.rawValue)] \(message)")
    }

    public func info(_ module: LogModule, _ message: String) {
        logger(for: module).info("[\(module.rawValue)] \(message)")
    }

    public func warning(_ module: LogModule, _ message: String) {
        logger(for: module).warning("[\(module.rawValue)] \(message)")
    }

    public func error(_ module: LogModule, _ message: String) {
        logger(for: module).error("[\(module.rawValue)] \(message)")
    }

    // MARK: - 敏感数据日志

    /// Debug 构建显示明文，Release 构建显示脱敏占位符
    public func debugSensitive(_ module: LogModule, _ message: String, sensitiveValue: String) {
        #if DEBUG
            logger(for: module).debug("[\(module.rawValue)] \(message): \(sensitiveValue)")
        #else
            logger(for: module).debug("[\(module.rawValue)] \(message): ***")
        #endif
    }

    public func infoSensitive(_ module: LogModule, _ message: String, sensitiveValue: String) {
        #if DEBUG
            logger(for: module).info("[\(module.rawValue)] \(message): \(sensitiveValue)")
        #else
            logger(for: module).info("[\(module.rawValue)] \(message): ***")
        #endif
    }

    // MARK: - 辅助方法

    /// 截断字符串至指定最大长度
    public static func truncate(_ string: String, maxLength: Int = 200) -> String {
        if string.count <= maxLength {
            return string
        }
        return String(string.prefix(maxLength)) + "..."
    }
}
