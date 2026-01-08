//
//  NativeEditorLogger.swift
//  MiNoteMac
//
//  原生编辑器日志记录器 - 提供详细的日志记录功能
//  需求: 13.1, 13.2, 13.3, 13.4, 13.5
//

import Foundation
import os.log

// MARK: - 日志级别

/// 日志级别
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4
    
    var prefix: String {
        switch self {
        case .debug: return "🔍 DEBUG"
        case .info: return "ℹ️ INFO"
        case .warning: return "⚠️ WARNING"
        case .error: return "❌ ERROR"
        case .critical: return "🚨 CRITICAL"
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
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
    
    var formattedMessage: String {
        var result = "[\(formattedTimestamp)] \(level.prefix) [\(category)] \(message)"
        if let info = additionalInfo, !info.isEmpty {
            result += " | \(info)"
        }
        return result
    }
    
    var shortLocation: String {
        let fileName = (file as NSString).lastPathComponent
        return "\(fileName):\(line)"
    }
}

// MARK: - 原生编辑器日志记录器

/// 原生编辑器日志记录器
/// 提供详细的日志记录、格式转换日志和性能日志
@MainActor
final class NativeEditorLogger {
    
    // MARK: - Singleton
    
    static let shared = NativeEditorLogger()
    
    // MARK: - Properties
    
    /// 系统日志
    private let osLog = OSLog(subsystem: "com.minote.mac", category: "NativeEditor")
    
    /// 日志条目缓存
    private var logEntries: [LogEntry] = []
    
    /// 最大日志条目数
    private let maxLogEntries = 1000
    
    /// 当前日志级别（低于此级别的日志不记录）
    var minimumLogLevel: LogLevel = .debug
    
    /// 是否启用控制台输出
    var enableConsoleOutput: Bool = true
    
    /// 是否启用文件日志
    var enableFileLogging: Bool = false
    
    /// 日志文件 URL
    private var logFileURL: URL?
    
    /// 日志文件句柄
    private var logFileHandle: FileHandle?
    
    /// 格式转换日志是否启用
    var enableFormatConversionLogging: Bool = true
    
    /// 渲染日志是否启用
    var enableRenderingLogging: Bool = true
    
    /// 性能日志是否启用
    var enablePerformanceLogging: Bool = true
    
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
            "success": success
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
            "success": success
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
        if let threshold = threshold {
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
        return logEntries
    }
    
    /// 获取指定级别的日志
    func getLogs(level: LogLevel) -> [LogEntry] {
        return logEntries.filter { $0.level >= level }
    }
    
    /// 获取指定类别的日志
    func getLogs(category: String) -> [LogEntry] {
        return logEntries.filter { $0.category == category }
    }
    
    /// 获取最近的日志
    func getRecentLogs(count: Int = 50) -> [LogEntry] {
        return Array(logEntries.suffix(count))
    }
    
    /// 清除所有日志
    func clearLogs() {
        logEntries.removeAll()
    }
    
    /// 导出日志到字符串
    func exportLogs() -> String {
        return logEntries.map { $0.formattedMessage }.joined(separator: "\n")
    }
    
    /// 导出日志到文件
    func exportLogs(to url: URL) throws {
        let content = exportLogs()
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Debug Mode
    
    /// 启用调试模式
    func enableDebugMode() {
        minimumLogLevel = .debug
        enableConsoleOutput = true
        enableFormatConversionLogging = true
        enableRenderingLogging = true
        enablePerformanceLogging = true
        logInfo("调试模式已启用", category: "System")
    }
    
    /// 禁用调试模式
    func disableDebugMode() {
        minimumLogLevel = .warning
        enableConsoleOutput = false
        enableFormatConversionLogging = false
        enableRenderingLogging = false
        enablePerformanceLogging = false
        logInfo("调试模式已禁用", category: "System")
    }
}
