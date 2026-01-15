//
//  FormatMenuDebugger.swift
//  MiNoteMac
//
//  格式菜单调试器 - 专门用于调试和监控格式菜单功能
//

import Foundation
import AppKit
import Combine

// MARK: - 格式菜单事件类型

/// 格式菜单事件类型
enum FormatMenuEventType: String {
    case formatApplication = "格式应用"
    case stateDetection = "状态检测"
    case stateSynchronization = "状态同步"
    case userInteraction = "用户交互"
    case performanceWarning = "性能警告"
    case error = "错误"
}

// MARK: - 格式菜单事件

/// 格式菜单调试事件
struct FormatMenuEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: FormatMenuEventType
    let format: TextFormat?
    let message: String
    let details: [String: Any]?
    let duration: TimeInterval?
    let success: Bool
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    var summary: String {
        var result = "[\(formattedTimestamp)] [\(type.rawValue)]"
        if let format = format {
            result += " [\(format.displayName)]"
        }
        result += " \(message)"
        if let duration = duration {
            result += " (\(String(format: "%.2f", duration * 1000))ms)"
        }
        result += success ? " ✅" : " ❌"
        return result
    }
}

// MARK: - 格式应用记录

/// 格式应用记录
struct FormatApplicationRecord {
    let format: TextFormat
    let timestamp: Date
    let selectedRange: NSRange
    let cursorPosition: Int
    let duration: TimeInterval
    let success: Bool
    let errorMessage: String?
    
    var durationMs: Double {
        return duration * 1000
    }
}

// MARK: - 状态同步记录

/// 状态同步记录
struct StateSynchronizationRecord {
    let timestamp: Date
    let cursorPosition: Int
    let detectedFormats: Set<TextFormat>
    let duration: TimeInterval
    let success: Bool
    
    var durationMs: Double {
        return duration * 1000
    }
}

// MARK: - 格式菜单调试器

/// 格式菜单调试器
/// 专门用于调试和监控格式菜单的功能
@MainActor
final class FormatMenuDebugger: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = FormatMenuDebugger()
    
    // MARK: - Published Properties
    
    /// 是否启用调试模式
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                logger.logInfo("格式菜单调试模式已启用", category: "FormatMenu")
            } else {
                logger.logInfo("格式菜单调试模式已禁用", category: "FormatMenu")
            }
        }
    }
    
    /// 调试事件列表
    @Published var events: [FormatMenuEvent] = []
    
    /// 实时统计数据
    @Published var statistics: FormatMenuStatistics = FormatMenuStatistics()
    
    // MARK: - Properties
    
    /// 日志记录器
    private let logger = NativeEditorLogger.shared
    
    /// 性能指标收集器
    private let metrics = NativeEditorMetrics.shared
    
    /// 格式应用记录
    private var applicationRecords: [FormatApplicationRecord] = []
    
    /// 状态同步记录
    private var synchronizationRecords: [StateSynchronizationRecord] = []
    
    /// 最大事件数
    private let maxEvents = 1000
    
    /// 最大记录数
    private let maxRecords = 500
    
    /// 性能阈值（毫秒）
    private let formatApplicationThreshold: TimeInterval = 0.05  // 50ms
    private let stateSynchronizationThreshold: TimeInterval = 0.1  // 100ms
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Event Recording
    
    /// 记录格式应用事件
    func recordFormatApplication(
        format: TextFormat,
        selectedRange: NSRange,
        cursorPosition: Int,
        duration: TimeInterval,
        success: Bool,
        errorMessage: String? = nil
    ) {
        guard isEnabled else { return }
        
        // 创建应用记录
        let record = FormatApplicationRecord(
            format: format,
            timestamp: Date(),
            selectedRange: selectedRange,
            cursorPosition: cursorPosition,
            duration: duration,
            success: success,
            errorMessage: errorMessage
        )
        
        applicationRecords.append(record)
        if applicationRecords.count > maxRecords {
            applicationRecords.removeFirst(applicationRecords.count - maxRecords)
        }
        
        // 创建调试事件
        var details: [String: Any] = [
            "selectedRange": NSStringFromRange(selectedRange),
            "cursorPosition": cursorPosition,
            "duration_ms": String(format: "%.2f", duration * 1000)
        ]
        
        if let error = errorMessage {
            details["error"] = error
        }
        
        let event = FormatMenuEvent(
            timestamp: Date(),
            type: .formatApplication,
            format: format,
            message: success ? "格式应用成功" : "格式应用失败",
            details: details,
            duration: duration,
            success: success
        )
        
        recordEvent(event)
        
        // 记录性能指标
        metrics.recordOperation(
            "格式应用: \(format.displayName)",
            duration: duration,
            type: .userInput
        )
        
        // 检查性能阈值
        if duration > formatApplicationThreshold {
            recordPerformanceWarning(
                format: format,
                operation: "格式应用",
                duration: duration,
                threshold: formatApplicationThreshold
            )
        }
        
        // 记录日志
        if success {
            logger.logDebug(
                "格式应用成功: \(format.displayName) (\(String(format: "%.2f", duration * 1000))ms)",
                category: "FormatMenu",
                additionalInfo: details
            )
        } else {
            logger.logWarning(
                "格式应用失败: \(format.displayName) - \(errorMessage ?? "未知错误")",
                category: "FormatMenu",
                additionalInfo: details
            )
        }
        
        // 更新统计数据
        updateStatistics()
    }
    
    /// 记录状态同步事件
    func recordStateSynchronization(
        cursorPosition: Int,
        detectedFormats: Set<TextFormat>,
        duration: TimeInterval,
        success: Bool
    ) {
        guard isEnabled else { return }
        
        // 创建同步记录
        let record = StateSynchronizationRecord(
            timestamp: Date(),
            cursorPosition: cursorPosition,
            detectedFormats: detectedFormats,
            duration: duration,
            success: success
        )
        
        synchronizationRecords.append(record)
        if synchronizationRecords.count > maxRecords {
            synchronizationRecords.removeFirst(synchronizationRecords.count - maxRecords)
        }
        
        // 创建调试事件
        let formatNames = detectedFormats.map { $0.displayName }.joined(separator: ", ")
        let details: [String: Any] = [
            "cursorPosition": cursorPosition,
            "detectedFormats": formatNames,
            "formatCount": detectedFormats.count,
            "duration_ms": String(format: "%.2f", duration * 1000)
        ]
        
        let event = FormatMenuEvent(
            timestamp: Date(),
            type: .stateSynchronization,
            format: nil,
            message: "检测到 \(detectedFormats.count) 个格式",
            details: details,
            duration: duration,
            success: success
        )
        
        recordEvent(event)
        
        // 记录性能指标
        metrics.recordOperation(
            "状态同步",
            duration: duration,
            type: .userInput
        )
        
        // 检查性能阈值
        if duration > stateSynchronizationThreshold {
            recordPerformanceWarning(
                format: nil,
                operation: "状态同步",
                duration: duration,
                threshold: stateSynchronizationThreshold
            )
        }
        
        // 记录日志
        logger.logDebug(
            "状态同步完成: 位置 \(cursorPosition), 检测到 \(detectedFormats.count) 个格式 (\(String(format: "%.2f", duration * 1000))ms)",
            category: "FormatMenu",
            additionalInfo: details
        )
        
        // 更新统计数据
        updateStatistics()
    }
    
    /// 记录状态检测事件
    func recordStateDetection(
        format: TextFormat,
        detected: Bool,
        cursorPosition: Int
    ) {
        guard isEnabled else { return }
        
        let details: [String: Any] = [
            "cursorPosition": cursorPosition,
            "detected": detected
        ]
        
        let event = FormatMenuEvent(
            timestamp: Date(),
            type: .stateDetection,
            format: format,
            message: detected ? "格式已激活" : "格式未激活",
            details: details,
            duration: nil,
            success: true
        )
        
        recordEvent(event)
        
        logger.logDebug(
            "状态检测: \(format.displayName) - \(detected ? "激活" : "未激活")",
            category: "FormatMenu",
            additionalInfo: details
        )
    }
    
    /// 记录用户交互事件
    func recordUserInteraction(
        action: String,
        format: TextFormat? = nil,
        details: [String: Any]? = nil
    ) {
        guard isEnabled else { return }
        
        let event = FormatMenuEvent(
            timestamp: Date(),
            type: .userInteraction,
            format: format,
            message: action,
            details: details,
            duration: nil,
            success: true
        )
        
        recordEvent(event)
        
        logger.logDebug(
            "用户交互: \(action)",
            category: "FormatMenu",
            additionalInfo: details
        )
    }
    
    /// 记录性能警告
    private func recordPerformanceWarning(
        format: TextFormat?,
        operation: String,
        duration: TimeInterval,
        threshold: TimeInterval
    ) {
        let details: [String: Any] = [
            "operation": operation,
            "duration_ms": String(format: "%.2f", duration * 1000),
            "threshold_ms": String(format: "%.2f", threshold * 1000),
            "exceeded_by_ms": String(format: "%.2f", (duration - threshold) * 1000)
        ]
        
        let event = FormatMenuEvent(
            timestamp: Date(),
            type: .performanceWarning,
            format: format,
            message: "\(operation)超过性能阈值",
            details: details,
            duration: duration,
            success: false
        )
        
        recordEvent(event)
        
        logger.logWarning(
            "性能警告: \(operation) 耗时 \(String(format: "%.2f", duration * 1000))ms (阈值: \(String(format: "%.2f", threshold * 1000))ms)",
            category: "FormatMenu",
            additionalInfo: details
        )
    }
    
    /// 记录错误事件
    func recordError(
        format: TextFormat?,
        operation: String,
        error: Error,
        context: [String: Any]? = nil
    ) {
        guard isEnabled else { return }
        
        var details = context ?? [:]
        details["error"] = error.localizedDescription
        details["operation"] = operation
        
        let event = FormatMenuEvent(
            timestamp: Date(),
            type: .error,
            format: format,
            message: "错误: \(error.localizedDescription)",
            details: details,
            duration: nil,
            success: false
        )
        
        recordEvent(event)
        
        logger.logError(
            error,
            context: operation,
            category: "FormatMenu"
        )
    }
    
    /// 记录事件
    private func recordEvent(_ event: FormatMenuEvent) {
        events.append(event)
        
        // 限制事件数量
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
    
    // MARK: - Statistics
    
    /// 更新统计数据
    private func updateStatistics() {
        let totalApplications = applicationRecords.count
        let successfulApplications = applicationRecords.filter { $0.success }.count
        let failedApplications = totalApplications - successfulApplications
        
        let totalSynchronizations = synchronizationRecords.count
        
        // 计算平均时间
        let avgApplicationTime = applicationRecords.isEmpty ? 0 :
            applicationRecords.map { $0.duration }.reduce(0, +) / Double(applicationRecords.count)
        
        let avgSynchronizationTime = synchronizationRecords.isEmpty ? 0 :
            synchronizationRecords.map { $0.duration }.reduce(0, +) / Double(synchronizationRecords.count)
        
        // 计算超过阈值的次数
        let slowApplications = applicationRecords.filter { $0.duration > formatApplicationThreshold }.count
        let slowSynchronizations = synchronizationRecords.filter { $0.duration > stateSynchronizationThreshold }.count
        
        // 按格式统计
        let formatCounts = Dictionary(grouping: applicationRecords) { $0.format }
            .mapValues { $0.count }
        
        statistics = FormatMenuStatistics(
            totalApplications: totalApplications,
            successfulApplications: successfulApplications,
            failedApplications: failedApplications,
            totalSynchronizations: totalSynchronizations,
            avgApplicationTimeMs: avgApplicationTime * 1000,
            avgSynchronizationTimeMs: avgSynchronizationTime * 1000,
            slowApplications: slowApplications,
            slowSynchronizations: slowSynchronizations,
            formatCounts: formatCounts
        )
    }
    
    // MARK: - Query Methods
    
    /// 获取指定格式的应用记录
    func getApplicationRecords(for format: TextFormat) -> [FormatApplicationRecord] {
        return applicationRecords.filter { $0.format == format }
    }
    
    /// 获取最近的应用记录
    func getRecentApplicationRecords(count: Int = 20) -> [FormatApplicationRecord] {
        return Array(applicationRecords.suffix(count))
    }
    
    /// 获取最近的同步记录
    func getRecentSynchronizationRecords(count: Int = 20) -> [StateSynchronizationRecord] {
        return Array(synchronizationRecords.suffix(count))
    }
    
    /// 获取失败的应用记录
    func getFailedApplicationRecords() -> [FormatApplicationRecord] {
        return applicationRecords.filter { !$0.success }
    }
    
    /// 获取慢速应用记录
    func getSlowApplicationRecords() -> [FormatApplicationRecord] {
        return applicationRecords.filter { $0.duration > formatApplicationThreshold }
    }
    
    /// 获取慢速同步记录
    func getSlowSynchronizationRecords() -> [StateSynchronizationRecord] {
        return synchronizationRecords.filter { $0.duration > stateSynchronizationThreshold }
    }
    
    /// 获取指定类型的事件
    func getEvents(type: FormatMenuEventType) -> [FormatMenuEvent] {
        return events.filter { $0.type == type }
    }
    
    /// 获取指定格式的事件
    func getEvents(format: TextFormat) -> [FormatMenuEvent] {
        return events.filter { $0.format == format }
    }
    
    // MARK: - Report Generation
    
    /// 生成调试报告
    func generateDebugReport() -> String {
        var report = """
        ========================================
        格式菜单调试报告
        生成时间: \(ISO8601DateFormatter().string(from: Date()))
        ========================================
        
        """
        
        // 统计摘要
        report += """
        
        ## 统计摘要
        \(statistics.summary)
        
        """
        
        // 性能分析
        report += """
        
        ## 性能分析
        - 格式应用平均时间: \(String(format: "%.2f", statistics.avgApplicationTimeMs))ms
        - 状态同步平均时间: \(String(format: "%.2f", statistics.avgSynchronizationTimeMs))ms
        - 慢速格式应用: \(statistics.slowApplications) 次
        - 慢速状态同步: \(statistics.slowSynchronizations) 次
        
        """
        
        // 格式使用统计
        if !statistics.formatCounts.isEmpty {
            report += """
            
            ## 格式使用统计
            
            """
            
            let sortedFormats = statistics.formatCounts.sorted { $0.value > $1.value }
            for (format, count) in sortedFormats.prefix(10) {
                report += "- \(format.displayName): \(count) 次\n"
            }
        }
        
        // 失败记录
        let failedRecords = getFailedApplicationRecords()
        if !failedRecords.isEmpty {
            report += """
            
            ## 失败记录
            
            """
            
            for record in failedRecords.prefix(10) {
                report += """
                - [\(ISO8601DateFormatter().string(from: record.timestamp))] \(record.format.displayName)
                  错误: \(record.errorMessage ?? "未知")
                
                """
            }
        }
        
        // 最近事件
        report += """
        
        ## 最近事件
        
        """
        
        for event in events.suffix(30).reversed() {
            report += "\(event.summary)\n"
        }
        
        report += """
        
        ========================================
        报告结束
        ========================================
        """
        
        return report
    }
    
    /// 导出调试报告
    func exportDebugReport(to url: URL) throws {
        let report = generateDebugReport()
        try report.write(to: url, atomically: true, encoding: .utf8)
        logger.logInfo("格式菜单调试报告已导出到: \(url.path)", category: "FormatMenu")
    }
    
    // MARK: - Management
    
    /// 清除所有记录
    func clearAllRecords() {
        events.removeAll()
        applicationRecords.removeAll()
        synchronizationRecords.removeAll()
        updateStatistics()
        logger.logInfo("已清除所有格式菜单调试记录", category: "FormatMenu")
    }
    
    /// 清除旧记录
    func clearOldRecords(olderThan date: Date) {
        events.removeAll { $0.timestamp < date }
        applicationRecords.removeAll { $0.timestamp < date }
        synchronizationRecords.removeAll { $0.timestamp < date }
        updateStatistics()
        logger.logInfo("已清除旧的格式菜单调试记录", category: "FormatMenu")
    }
}

// MARK: - 格式菜单统计数据

/// 格式菜单统计数据
struct FormatMenuStatistics {
    var totalApplications: Int = 0
    var successfulApplications: Int = 0
    var failedApplications: Int = 0
    var totalSynchronizations: Int = 0
    var avgApplicationTimeMs: Double = 0
    var avgSynchronizationTimeMs: Double = 0
    var slowApplications: Int = 0
    var slowSynchronizations: Int = 0
    var formatCounts: [TextFormat: Int] = [:]
    
    var successRate: Double {
        guard totalApplications > 0 else { return 0 }
        return Double(successfulApplications) / Double(totalApplications) * 100
    }
    
    var summary: String {
        return """
        - 总格式应用次数: \(totalApplications)
        - 成功次数: \(successfulApplications)
        - 失败次数: \(failedApplications)
        - 成功率: \(String(format: "%.1f", successRate))%
        - 总状态同步次数: \(totalSynchronizations)
        - 平均应用时间: \(String(format: "%.2f", avgApplicationTimeMs))ms
        - 平均同步时间: \(String(format: "%.2f", avgSynchronizationTimeMs))ms
        """
    }
}
