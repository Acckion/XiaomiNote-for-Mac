//
//  NativeEditorLogger.swift
//  MiNoteMac
//
//  原生编辑器日志记录器 - 提供详细的日志记录功能
//

import Foundation
import os.log

// MARK: - 日志级别

/// 日志级别
enum LogLevel: Int, Comparable, CaseIterable {
    case trace = -1 // 最详细的跟踪日志
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4

    var prefix: String {
        switch self {
        case .trace: "🔬 TRACE"
        case .debug: "🔍 DEBUG"
        case .info: "ℹ️ INFO"
        case .warning: "⚠️ WARNING"
        case .error: "❌ ERROR"
        case .critical: "🚨 CRITICAL"
        }
    }

    var displayName: String {
        switch self {
        case .trace: "跟踪"
        case .debug: "调试"
        case .info: "信息"
        case .warning: "警告"
        case .error: "错误"
        case .critical: "严重"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .trace: .debug
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        case .critical: .fault
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - 日志类别

/// 日志类别 - 用于分类和过滤日志
/// 需求: 8.1 - 启用调试模式时输出格式状态变化的详细日志
enum LogCategory: String, CaseIterable {
    case general = "General"
    case formatMenu = "FormatMenu"
    case formatState = "FormatState"
    case formatApplication = "FormatApplication"
    case stateSynchronization = "StateSynchronization"
    case stateDetection = "StateDetection"
    case performance = "Performance"
    case formatConversion = "FormatConversion"
    case rendering = "Rendering"
    case error = "Error"
    case system = "System"
    case userInteraction = "UserInteraction"
    case diagnostics = "Diagnostics"

    var displayName: String {
        switch self {
        case .general: "通用"
        case .formatMenu: "格式菜单"
        case .formatState: "格式状态"
        case .formatApplication: "格式应用"
        case .stateSynchronization: "状态同步"
        case .stateDetection: "状态检测"
        case .performance: "性能"
        case .formatConversion: "格式转换"
        case .rendering: "渲染"
        case .error: "错误"
        case .system: "系统"
        case .userInteraction: "用户交互"
        case .diagnostics: "诊断"
        }
    }
}

// MARK: - 日志条目

/// 日志条目
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
    let file: String
    let function: String
    let line: Int
    let additionalInfo: [String: Any]?

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var shortTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var formattedMessage: String {
        var result = "[\(formattedTimestamp)] \(level.prefix) [\(category)] \(message)"
        if let info = additionalInfo, !info.isEmpty {
            result += " | \(info)"
        }
        return result
    }

    var compactMessage: String {
        "[\(shortTimestamp)] [\(category)] \(message)"
    }

    var shortLocation: String {
        let fileName = (file as NSString).lastPathComponent
        return "\(fileName):\(line)"
    }
}

// MARK: - 格式状态变化记录

/// 格式状态变化记录
/// 需求: 8.1 - 格式状态变化的详细日志
struct FormatStateChangeRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let format: TextFormat
    let previousState: Bool
    let newState: Bool
    let cursorPosition: Int
    let selectedRange: NSRange
    let trigger: FormatStateChangeTrigger

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var summary: String {
        let stateChange = previousState == newState ? "保持" : (newState ? "激活" : "取消")
        return "[\(formattedTimestamp)] \(format.displayName): \(stateChange) (触发: \(trigger.displayName))"
    }
}

/// 格式状态变化触发器
enum FormatStateChangeTrigger: String {
    case cursorMove = "光标移动"
    case selectionChange = "选择变化"
    case formatApplication = "格式应用"
    case undoRedo = "撤销/重做"
    case contentLoad = "内容加载"
    case keyboardShortcut = "快捷键"
    case menuClick = "菜单点击"
    case external = "外部触发"

    var displayName: String {
        rawValue
    }
}

// MARK: - 原生编辑器日志记录器

/// 原生编辑器日志记录器
/// 提供详细的日志记录、格式转换日志和性能日志
/// 需求: 8.1 - 启用调试模式时输出格式状态变化的详细日志
@MainActor
final class NativeEditorLogger: ObservableObject {

    // MARK: - Singleton

    static let shared = NativeEditorLogger()

    // MARK: - Published Properties

    /// 是否启用调试模式
    /// 需求: 8.1 - 创建调试模式的开关
    @Published var isDebugModeEnabled = false {
        didSet {
            if isDebugModeEnabled != oldValue {
                if isDebugModeEnabled {
                    enableDebugModeInternal()
                } else {
                    disableDebugModeInternal()
                }
            }
        }
    }

    /// 当前日志级别
    /// 需求: 8.1 - 实现可配置的日志级别
    @Published var currentLogLevel: LogLevel = .info

    /// 启用的日志类别
    @Published var enabledCategories: Set<LogCategory> = Set(LogCategory.allCases)

    // MARK: - Properties

    /// 系统日志
    private let osLog = OSLog(subsystem: "com.minote.mac", category: "NativeEditor")

    /// 日志条目缓存
    private var logEntries: [LogEntry] = []

    /// 格式状态变化记录
    /// 需求: 8.1 - 添加格式状态变化的日志记录
    private var formatStateChanges: [FormatStateChangeRecord] = []

    /// 最大日志条目数
    private let maxLogEntries = 2000

    /// 最大格式状态变化记录数
    private let maxFormatStateChanges = 500

    /// 当前日志级别（低于此级别的日志不记录）
    var minimumLogLevel: LogLevel = .debug

    /// 是否启用控制台输出
    var enableConsoleOutput = true

    /// 是否启用文件日志
    var enableFileLogging = false

    /// 日志文件 URL
    private var logFileURL: URL?

    /// 日志文件句柄
    private var logFileHandle: FileHandle?

    /// 格式转换日志是否启用
    var enableFormatConversionLogging = true

    /// 渲染日志是否启用
    var enableRenderingLogging = true

    /// 性能日志是否启用
    var enablePerformanceLogging = true

    /// 格式状态变化日志是否启用
    /// 需求: 8.1 - 添加格式状态变化的日志记录
    var enableFormatStateLogging = true

    /// 详细跟踪日志是否启用
    var enableTraceLogging = false

    // MARK: - Initialization

    private init() {
        setupFileLogging()
    }

    deinit {
        logFileHandle?.closeFile()
    }

    // MARK: - File Logging Setup

    private func setupFileLogging() {
        guard enableFileLogging else { return }

        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let logDirectory = appSupport.appendingPathComponent("MiNoteMac/Logs", isDirectory: true)

        do {
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())

            logFileURL = logDirectory.appendingPathComponent("native-editor-\(dateString).log")

            if let url = logFileURL {
                if !fileManager.fileExists(atPath: url.path) {
                    fileManager.createFile(atPath: url.path, contents: nil)
                }
                logFileHandle = try FileHandle(forWritingTo: url)
                logFileHandle?.seekToEndOfFile()
            }
        } catch {
            print("[NativeEditorLogger] 无法设置文件日志: \(error)")
        }
    }

    // MARK: - Logging Methods

    /// 记录调试日志
    func logDebug(
        _ message: String,
        category: String = "General",
        additionalInfo: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message, category: category, additionalInfo: additionalInfo, file: file, function: function, line: line)
    }

    /// 记录信息日志
    func logInfo(
        _ message: String,
        category: String = "General",
        additionalInfo: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message, category: category, additionalInfo: additionalInfo, file: file, function: function, line: line)
    }

    /// 记录警告日志
    func logWarning(
        _ message: String,
        category: String = "General",
        additionalInfo: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message, category: category, additionalInfo: additionalInfo, file: file, function: function, line: line)
    }

    /// 记录错误日志
    func logError(
        _ error: Error,
        context: String = "",
        category: String = "Error",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var info: [String: Any] = ["error": error.localizedDescription]
        if !context.isEmpty {
            info["context"] = context
        }

        if let editorError = error as? NativeEditorError {
            info["errorCode"] = editorError.errorCode
            info["isRecoverable"] = editorError.isRecoverable
        }

        log(level: .error, message: error.localizedDescription, category: category, additionalInfo: info, file: file, function: function, line: line)
    }

    /// 记录严重错误日志
    func logCritical(
        _ message: String,
        category: String = "Critical",
        additionalInfo: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .critical, message: message, category: category, additionalInfo: additionalInfo, file: file, function: function, line: line)
    }

    // MARK: - Specialized Logging

    /// 记录格式状态变化
    /// 需求: 8.1 - 添加格式状态变化的日志记录
    func logFormatStateChange(
        format: TextFormat,
        previousState: Bool,
        newState: Bool,
        cursorPosition: Int,
        selectedRange: NSRange,
        trigger: FormatStateChangeTrigger,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard enableFormatStateLogging else { return }

        // 创建格式状态变化记录
        let record = FormatStateChangeRecord(
            timestamp: Date(),
            format: format,
            previousState: previousState,
            newState: newState,
            cursorPosition: cursorPosition,
            selectedRange: selectedRange,
            trigger: trigger
        )

        formatStateChanges.append(record)
        if formatStateChanges.count > maxFormatStateChanges {
            formatStateChanges.removeFirst(formatStateChanges.count - maxFormatStateChanges)
        }

        // 记录日志
        let stateChange = previousState == newState ? "保持" : (newState ? "激活" : "取消")
        let info: [String: Any] = [
            "format": format.displayName,
            "previousState": previousState,
            "newState": newState,
            "cursorPosition": cursorPosition,
            "selectedRange": NSStringFromRange(selectedRange),
            "trigger": trigger.rawValue,
        ]

        let message = "格式状态变化: \(format.displayName) \(stateChange) (触发: \(trigger.displayName))"

        log(
            level: .debug,
            message: message,
            category: LogCategory.formatState.rawValue,
            additionalInfo: info,
            file: file,
            function: function,
            line: line
        )
    }

    /// 记录格式应用操作
    /// 需求: 8.1 - 添加格式状态变化的日志记录
    func logFormatApplication(
        format: TextFormat,
        range: NSRange,
        success: Bool,
        duration: TimeInterval,
        errorMessage: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var info: [String: Any] = [
            "format": format.displayName,
            "range": NSStringFromRange(range),
            "success": success,
            "duration_ms": String(format: "%.2f", duration * 1000),
        ]

        if let error = errorMessage {
            info["error"] = error
        }

        let level: LogLevel = success ? .debug : .warning
        let message = "格式应用: \(format.displayName) - \(success ? "成功" : "失败") (\(String(format: "%.2f", duration * 1000))ms)"

        log(
            level: level,
            message: message,
            category: LogCategory.formatApplication.rawValue,
            additionalInfo: info,
            file: file,
            function: function,
            line: line
        )
    }

    /// 记录状态同步操作
    /// 需求: 8.1 - 添加格式状态变化的日志记录
    func logStateSynchronization(
        cursorPosition: Int,
        detectedFormats: Set<TextFormat>,
        duration: TimeInterval,
        success: Bool,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let formatNames = detectedFormats.map(\.displayName).joined(separator: ", ")
        let info: [String: Any] = [
            "cursorPosition": cursorPosition,
            "detectedFormats": formatNames,
            "formatCount": detectedFormats.count,
            "duration_ms": String(format: "%.2f", duration * 1000),
            "success": success,
        ]

        let level: LogLevel = success ? .debug : .warning
        let message = "状态同步: 位置 \(cursorPosition), 检测到 \(detectedFormats.count) 个格式 (\(String(format: "%.2f", duration * 1000))ms)"

        log(
            level: level,
            message: message,
            category: LogCategory.stateSynchronization.rawValue,
            additionalInfo: info,
            file: file,
            function: function,
            line: line
        )
    }

    /// 记录状态检测操作
    /// 需求: 8.1 - 添加格式状态变化的日志记录
    func logStateDetection(
        format: TextFormat,
        detected: Bool,
        position: Int,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard enableTraceLogging else { return }

        let info: [String: Any] = [
            "format": format.displayName,
            "detected": detected,
            "position": position,
        ]

        let message = "状态检测: \(format.displayName) - \(detected ? "激活" : "未激活") (位置: \(position))"

        log(
            level: .trace,
            message: message,
            category: LogCategory.stateDetection.rawValue,
            additionalInfo: info,
            file: file,
            function: function,
            line: line
        )
    }

    /// 记录用户交互
    func logUserInteraction(
        action: String,
        format: TextFormat? = nil,
        details: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var info = details ?? [:]
        if let format {
            info["format"] = format.displayName
        }

        let message = "用户交互: \(action)"

        log(
            level: .debug,
            message: message,
            category: LogCategory.userInteraction.rawValue,
            additionalInfo: info,
            file: file,
            function: function,
            line: line
        )
    }

    /// 记录跟踪日志（最详细级别）
    func logTrace(
        _ message: String,
        category: String = "General",
        additionalInfo: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard enableTraceLogging else { return }
        log(level: .trace, message: message, category: category, additionalInfo: additionalInfo, file: file, function: function, line: line)
    }

    /// 记录格式转换日志
    func logFormatConversion(
        direction: String,
        inputPreview: String,
        outputPreview: String,
        duration: TimeInterval,
        success: Bool,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard enableFormatConversionLogging else { return }

        let info: [String: Any] = [
            "direction": direction,
            "inputPreview": String(inputPreview.prefix(100)),
            "outputPreview": String(outputPreview.prefix(100)),
            "duration_ms": String(format: "%.2f", duration * 1000),
            "success": success,
        ]

        let level: LogLevel = success ? .debug : .warning
        let message = "格式转换 [\(direction)] - \(success ? "成功" : "失败") (\(String(format: "%.2f", duration * 1000))ms)"

        log(level: level, message: message, category: "FormatConversion", additionalInfo: info, file: file, function: function, line: line)
    }

    /// 记录渲染日志
    func logRendering(
        element: String,
        duration: TimeInterval,
        cached: Bool,
        success: Bool,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard enableRenderingLogging else { return }

        let info: [String: Any] = [
            "element": element,
            "duration_ms": String(format: "%.2f", duration * 1000),
            "cached": cached,
            "success": success,
        ]

        let level: LogLevel = success ? .debug : .warning
        let message = "渲染 [\(element)] - \(cached ? "缓存命中" : "新渲染") (\(String(format: "%.2f", duration * 1000))ms)"

        log(level: level, message: message, category: "Rendering", additionalInfo: info, file: file, function: function, line: line)
    }

    /// 记录性能日志
    func logPerformance(
        operation: String,
        duration: TimeInterval,
        threshold: TimeInterval? = nil,
        additionalInfo: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard enablePerformanceLogging else { return }

        var info = additionalInfo ?? [:]
        info["operation"] = operation
        info["duration_ms"] = String(format: "%.2f", duration * 1000)

        let exceededThreshold = threshold != nil && duration > threshold!
        if let threshold {
            info["threshold_ms"] = String(format: "%.2f", threshold * 1000)
            info["exceeded"] = exceededThreshold
        }

        let level: LogLevel = exceededThreshold ? .warning : .debug
        let message = "性能 [\(operation)] - \(String(format: "%.2f", duration * 1000))ms\(exceededThreshold ? " (超过阈值)" : "")"

        log(level: level, message: message, category: "Performance", additionalInfo: info, file: file, function: function, line: line)

        // 记录到性能指标
        NativeEditorMetrics.shared.recordOperation(operation, duration: duration)
    }

    // MARK: - Core Logging

    /// 核心日志方法
    private func log(
        level: LogLevel,
        message: String,
        category: String,
        additionalInfo: [String: Any]?,
        file: String,
        function: String,
        line: Int
    ) {
        // 检查日志级别
        guard level >= minimumLogLevel else { return }

        // 检查类别是否启用
        guard isCategoryEnabled(category) else { return }

        // 创建日志条目
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line,
            additionalInfo: additionalInfo
        )

        // 添加到缓存
        logEntries.append(entry)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }

        // 控制台输出
        if enableConsoleOutput {
            print(entry.formattedMessage)
        }

        // 系统日志
        os_log("%{public}@", log: osLog, type: level.osLogType, entry.formattedMessage)

        // 文件日志
        writeToFile(entry)
    }

    /// 写入文件
    private func writeToFile(_ entry: LogEntry) {
        guard enableFileLogging, let handle = logFileHandle else { return }

        let logLine = entry.formattedMessage + "\n"
        if let data = logLine.data(using: .utf8) {
            handle.write(data)
        }
    }

    // MARK: - Log Access

    /// 获取所有日志条目
    func getAllLogs() -> [LogEntry] {
        logEntries
    }

    /// 获取指定级别的日志
    func getLogs(level: LogLevel) -> [LogEntry] {
        logEntries.filter { $0.level >= level }
    }

    /// 获取指定类别的日志
    func getLogs(category: String) -> [LogEntry] {
        logEntries.filter { $0.category == category }
    }

    /// 获取指定类别的日志（使用枚举）
    func getLogs(category: LogCategory) -> [LogEntry] {
        logEntries.filter { $0.category == category.rawValue }
    }

    /// 获取最近的日志
    func getRecentLogs(count: Int = 50) -> [LogEntry] {
        Array(logEntries.suffix(count))
    }

    /// 获取格式状态变化记录
    /// 需求: 8.1 - 添加格式状态变化的日志记录
    func getFormatStateChanges() -> [FormatStateChangeRecord] {
        formatStateChanges
    }

    /// 获取指定格式的状态变化记录
    func getFormatStateChanges(for format: TextFormat) -> [FormatStateChangeRecord] {
        formatStateChanges.filter { $0.format == format }
    }

    /// 获取最近的格式状态变化记录
    func getRecentFormatStateChanges(count: Int = 20) -> [FormatStateChangeRecord] {
        Array(formatStateChanges.suffix(count))
    }

    /// 清除所有日志
    func clearLogs() {
        logEntries.removeAll()
    }

    /// 清除格式状态变化记录
    func clearFormatStateChanges() {
        formatStateChanges.removeAll()
    }

    /// 清除所有记录
    func clearAllRecords() {
        logEntries.removeAll()
        formatStateChanges.removeAll()
    }

    /// 导出日志到字符串
    func exportLogs() -> String {
        logEntries.map(\.formattedMessage).joined(separator: "\n")
    }

    /// 导出日志到文件
    func exportLogs(to url: URL) throws {
        let content = exportLogs()
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 导出格式状态变化记录
    func exportFormatStateChanges() -> String {
        formatStateChanges.map(\.summary).joined(separator: "\n")
    }

    /// 生成调试报告
    /// 需求: 8.1 - 启用调试模式时输出格式状态变化的详细日志
    func generateDebugReport() -> String {
        var report = """
        ========================================
        原生编辑器调试报告
        生成时间: \(ISO8601DateFormatter().string(from: Date()))
        ========================================

        ## 调试模式状态
        - 调试模式: \(isDebugModeEnabled ? "启用" : "禁用")
        - 当前日志级别: \(currentLogLevel.displayName)
        - 控制台输出: \(enableConsoleOutput ? "启用" : "禁用")
        - 文件日志: \(enableFileLogging ? "启用" : "禁用")
        - 格式状态日志: \(enableFormatStateLogging ? "启用" : "禁用")
        - 跟踪日志: \(enableTraceLogging ? "启用" : "禁用")

        ## 日志统计
        - 总日志条目: \(logEntries.count)
        - 格式状态变化记录: \(formatStateChanges.count)

        """

        // 按级别统计
        report += "\n## 按级别统计\n"
        for level in LogLevel.allCases {
            let count = logEntries.count(where: { $0.level == level })
            report += "- \(level.displayName): \(count)\n"
        }

        // 按类别统计
        report += "\n## 按类别统计\n"
        for category in LogCategory.allCases {
            let count = logEntries.count(where: { $0.category == category.rawValue })
            if count > 0 {
                report += "- \(category.displayName): \(count)\n"
            }
        }

        // 最近的格式状态变化
        let recentChanges = getRecentFormatStateChanges(count: 20)
        if !recentChanges.isEmpty {
            report += "\n## 最近的格式状态变化\n"
            for change in recentChanges.reversed() {
                report += "\(change.summary)\n"
            }
        }

        // 最近的错误日志
        let errorLogs = logEntries.filter { $0.level >= .error }.suffix(10)
        if !errorLogs.isEmpty {
            report += "\n## 最近的错误日志\n"
            for log in errorLogs.reversed() {
                report += "\(log.compactMessage)\n"
            }
        }

        report += "\n========================================\n"

        return report
    }

    // MARK: - Debug Mode

    /// 启用调试模式
    /// 需求: 8.1 - 创建调试模式的开关
    func enableDebugMode() {
        isDebugModeEnabled = true
    }

    /// 禁用调试模式
    /// 需求: 8.1 - 创建调试模式的开关
    func disableDebugMode() {
        isDebugModeEnabled = false
    }

    /// 内部启用调试模式
    private func enableDebugModeInternal() {
        minimumLogLevel = .debug
        currentLogLevel = .debug
        enableConsoleOutput = true
        enableFormatConversionLogging = true
        enableRenderingLogging = true
        enablePerformanceLogging = true
        enableFormatStateLogging = true
        enableTraceLogging = false // 跟踪日志默认关闭，太详细
        enabledCategories = Set(LogCategory.allCases)
        logInfo("调试模式已启用", category: LogCategory.system.rawValue)
    }

    /// 内部禁用调试模式
    private func disableDebugModeInternal() {
        minimumLogLevel = .warning
        currentLogLevel = .warning
        enableConsoleOutput = false
        enableFormatConversionLogging = false
        enableRenderingLogging = false
        enablePerformanceLogging = false
        enableFormatStateLogging = false
        enableTraceLogging = false
        logInfo("调试模式已禁用", category: LogCategory.system.rawValue)
    }

    /// 启用详细跟踪模式（最详细的日志）
    func enableTraceMode() {
        enableDebugMode()
        enableTraceLogging = true
        minimumLogLevel = .trace
        currentLogLevel = .trace
        logInfo("跟踪模式已启用", category: LogCategory.system.rawValue)
    }

    /// 设置日志级别
    /// 需求: 8.1 - 实现可配置的日志级别
    func setLogLevel(_ level: LogLevel) {
        minimumLogLevel = level
        currentLogLevel = level
        logInfo("日志级别已设置为: \(level.displayName)", category: LogCategory.system.rawValue)
    }

    /// 启用指定类别的日志
    func enableCategory(_ category: LogCategory) {
        enabledCategories.insert(category)
    }

    /// 禁用指定类别的日志
    func disableCategory(_ category: LogCategory) {
        enabledCategories.remove(category)
    }

    /// 检查类别是否启用
    func isCategoryEnabled(_ category: LogCategory) -> Bool {
        enabledCategories.contains(category)
    }

    /// 检查类别是否启用（字符串版本）
    func isCategoryEnabled(_ categoryString: String) -> Bool {
        guard let category = LogCategory(rawValue: categoryString) else {
            return true // 未知类别默认启用
        }
        return enabledCategories.contains(category)
    }
}
