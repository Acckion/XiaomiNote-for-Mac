//
//  FormatMenuPerformanceMonitor.swift
//  MiNoteMac
//
//  格式菜单性能监控器 - 专门监控格式菜单操作的性能
//

import AppKit
import Foundation

// MARK: - 性能指标类型

/// 格式菜单性能指标类型
enum FormatMenuMetricType: String, CaseIterable {
    case formatApplication = "格式应用"
    case stateDetection = "状态检测"
    case stateSynchronization = "状态同步"
    case userInteraction = "用户交互"
    case menuUpdate = "菜单更新"
    case toolbarUpdate = "工具栏更新"

    var displayName: String {
        rawValue
    }
}

// MARK: - 性能指标记录

/// 格式菜单性能指标记录
struct FormatMenuMetricRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: FormatMenuMetricType
    let format: TextFormat?
    let duration: TimeInterval
    let success: Bool
    let additionalInfo: [String: Any]?

    var durationMs: Double {
        duration * 1000
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var summary: String {
        var result = "[\(formattedTimestamp)] \(type.displayName)"
        if let format {
            result += " [\(format.displayName)]"
        }
        result += " - \(String(format: "%.2f", durationMs))ms"
        result += success ? " ✅" : " ❌"
        return result
    }
}

// MARK: - 性能统计

/// 格式菜单性能统计
struct FormatMenuPerformanceStatistics {
    let type: FormatMenuMetricType
    let totalCount: Int
    let successCount: Int
    let failureCount: Int
    let totalDuration: TimeInterval
    let averageDuration: TimeInterval
    let minDuration: TimeInterval
    let maxDuration: TimeInterval
    let p50Duration: TimeInterval
    let p95Duration: TimeInterval
    let p99Duration: TimeInterval
    let thresholdExceededCount: Int

    var successRate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(successCount) / Double(totalCount) * 100
    }

    var averageMs: Double {
        averageDuration * 1000
    }

    var minMs: Double {
        minDuration * 1000
    }

    var maxMs: Double {
        maxDuration * 1000
    }

    var p50Ms: Double {
        p50Duration * 1000
    }

    var p95Ms: Double {
        p95Duration * 1000
    }

    var p99Ms: Double {
        p99Duration * 1000
    }

    var summary: String {
        """
        \(type.displayName):
          - 总次数: \(totalCount) (成功: \(successCount), 失败: \(failureCount))
          - 成功率: \(String(format: "%.1f", successRate))%
          - 平均时间: \(String(format: "%.2f", averageMs))ms
          - 最小时间: \(String(format: "%.2f", minMs))ms
          - 最大时间: \(String(format: "%.2f", maxMs))ms
          - P50: \(String(format: "%.2f", p50Ms))ms
          - P95: \(String(format: "%.2f", p95Ms))ms
          - P99: \(String(format: "%.2f", p99Ms))ms
          - 超过阈值: \(thresholdExceededCount) 次
        """
    }
}

// MARK: - 性能测量器

/// 格式菜单性能测量器
/// 用于测量格式菜单操作的执行时间
struct FormatMenuPerformanceMeasurer {
    let operation: String
    let format: TextFormat?
    let type: FormatMenuMetricType
    let startTime: CFAbsoluteTime

    init(operation: String, format: TextFormat? = nil, type: FormatMenuMetricType = .formatApplication) {
        self.operation = operation
        self.format = format
        self.type = type
        startTime = CFAbsoluteTimeGetCurrent()
    }

    /// 结束测量并记录
    @MainActor
    func finish(success: Bool = true, errorMessage: String? = nil, additionalInfo: [String: Any]? = nil) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // 记录到性能监控器
        FormatMenuPerformanceMonitor.shared.recordMetric(
            type: type,
            format: format,
            duration: duration,
            success: success,
            additionalInfo: additionalInfo
        )

        // 记录到调试器
        if type == .formatApplication {
            if let format {
                FormatMenuDebugger.shared.recordFormatApplication(
                    format: format,
                    selectedRange: NSRange(location: 0, length: 0),
                    cursorPosition: 0,
                    duration: duration,
                    success: success,
                    errorMessage: errorMessage
                )
            }
        } else if type == .stateSynchronization {
            FormatMenuDebugger.shared.recordStateSynchronization(
                cursorPosition: 0,
                detectedFormats: [],
                duration: duration,
                success: success
            )
        }

        // 记录到性能指标
        NativeEditorMetrics.shared.recordOperation(
            operation,
            duration: duration,
            type: .userInput,
            additionalData: additionalInfo
        )
    }
}

// MARK: - 格式菜单性能监控器

/// 格式菜单性能监控器
/// 提供性能监控和分析功能
@MainActor
final class FormatMenuPerformanceMonitor: ObservableObject {

    // MARK: - Singleton

    static let shared = FormatMenuPerformanceMonitor()

    // MARK: - Published Properties

    /// 是否启用性能监控
    @Published var isEnabled = false

    /// 实时性能统计
    @Published var realtimeStatistics: [FormatMenuMetricType: FormatMenuPerformanceStatistics] = [:]

    // MARK: - Properties

    /// 性能阈值（毫秒）
    struct PerformanceThresholds {
        var formatApplication: TimeInterval = 0.05 // 50ms
        var stateDetection: TimeInterval = 0.1 // 100ms
        var stateSynchronization: TimeInterval = 0.1 // 100ms
        var userInteraction: TimeInterval = 0.016 // 16ms (60fps)
        var menuUpdate: TimeInterval = 0.016 // 16ms
        var toolbarUpdate: TimeInterval = 0.016 // 16ms
    }

    var thresholds = PerformanceThresholds()

    /// 性能指标记录
    private var metricRecords: [FormatMenuMetricRecord] = []

    /// 最大记录数
    private let maxRecords = 5000

    /// 日志记录器
    private let logger = NativeEditorLogger.shared

    /// 调试器
    private let debugger = FormatMenuDebugger.shared

    /// 阈值超出回调
    var onThresholdExceeded: ((FormatMenuMetricRecord, TimeInterval) -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Metric Recording

    /// 记录性能指标
    func recordMetric(
        type: FormatMenuMetricType,
        format: TextFormat? = nil,
        duration: TimeInterval,
        success: Bool = true,
        additionalInfo: [String: Any]? = nil
    ) {
        guard isEnabled else { return }

        let record = FormatMenuMetricRecord(
            timestamp: Date(),
            type: type,
            format: format,
            duration: duration,
            success: success,
            additionalInfo: additionalInfo
        )

        metricRecords.append(record)
        if metricRecords.count > maxRecords {
            metricRecords.removeFirst(metricRecords.count - maxRecords)
        }

        // 检查阈值
        let threshold = getThreshold(for: type)
        if duration > threshold {
            // 记录警告日志
            logger.logWarning(
                "性能警告: \(type.displayName) 耗时 \(String(format: "%.2f", duration * 1000))ms (阈值: \(String(format: "%.2f", threshold * 1000))ms)",
                category: LogCategory.performance.rawValue,
                additionalInfo: [
                    "type": type.rawValue,
                    "format": format?.displayName ?? "无",
                    "duration_ms": String(format: "%.2f", duration * 1000),
                    "threshold_ms": String(format: "%.2f", threshold * 1000),
                ]
            )

            // 触发回调
            onThresholdExceeded?(record, threshold)
        }

        // 更新实时统计
        updateRealtimeStatistics()
    }

    /// 获取指定类型的阈值
    private func getThreshold(for type: FormatMenuMetricType) -> TimeInterval {
        switch type {
        case .formatApplication:
            thresholds.formatApplication
        case .stateDetection:
            thresholds.stateDetection
        case .stateSynchronization:
            thresholds.stateSynchronization
        case .userInteraction:
            thresholds.userInteraction
        case .menuUpdate:
            thresholds.menuUpdate
        case .toolbarUpdate:
            thresholds.toolbarUpdate
        }
    }

    /// 更新实时统计
    private func updateRealtimeStatistics() {
        var newStats: [FormatMenuMetricType: FormatMenuPerformanceStatistics] = [:]

        for type in FormatMenuMetricType.allCases {
            if let stats = calculateStatistics(for: type) {
                newStats[type] = stats
            }
        }

        realtimeStatistics = newStats
    }

    /// 计算指定类型的统计信息
    private func calculateStatistics(for type: FormatMenuMetricType) -> FormatMenuPerformanceStatistics? {
        let typeRecords = metricRecords.filter { $0.type == type }
        guard !typeRecords.isEmpty else { return nil }

        let durations = typeRecords.map(\.duration).sorted()
        let count = durations.count
        let total = durations.reduce(0, +)
        let successCount = typeRecords.count(where: { $0.success })
        let threshold = getThreshold(for: type)
        let exceededCount = typeRecords.count(where: { $0.duration > threshold })

        return FormatMenuPerformanceStatistics(
            type: type,
            totalCount: count,
            successCount: successCount,
            failureCount: count - successCount,
            totalDuration: total,
            averageDuration: total / Double(count),
            minDuration: durations.first ?? 0,
            maxDuration: durations.last ?? 0,
            p50Duration: percentile(durations, 0.50),
            p95Duration: percentile(durations, 0.95),
            p99Duration: percentile(durations, 0.99),
            thresholdExceededCount: exceededCount
        )
    }

    /// 计算百分位数
    private func percentile(_ sortedValues: [TimeInterval], _ p: Double) -> TimeInterval {
        guard !sortedValues.isEmpty else { return 0 }
        let index = Int(Double(sortedValues.count - 1) * p)
        return sortedValues[index]
    }

    // MARK: - Measurement Methods

    /// 测量格式应用性能
    /// - Parameters:
    ///   - format: 格式类型
    ///   - block: 要测量的代码块
    /// - Returns: 代码块的返回值
    func measureFormatApplication<T>(
        _ format: TextFormat,
        block: () throws -> T
    ) rethrows -> T {
        guard isEnabled else {
            return try block()
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        var success = true
        var errorMessage: String?

        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime

            // 记录性能数据
            recordMetric(
                type: .formatApplication,
                format: format,
                duration: duration,
                success: success
            )

            debugger.recordFormatApplication(
                format: format,
                selectedRange: NSRange(location: 0, length: 0),
                cursorPosition: 0,
                duration: duration,
                success: success,
                errorMessage: errorMessage
            )

            // 检查是否超过阈值
            if duration > thresholds.formatApplication {
                logger.logWarning(
                    "格式应用性能警告: \(format.displayName) 耗时 \(String(format: "%.2f", duration * 1000))ms (阈值: \(String(format: "%.2f", thresholds.formatApplication * 1000))ms)",
                    category: LogCategory.performance.rawValue
                )
            }
        }

        do {
            return try block()
        } catch {
            success = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// 测量状态同步性能
    /// - Parameters:
    ///   - cursorPosition: 光标位置
    ///   - block: 要测量的代码块，返回检测到的格式集合
    /// - Returns: 检测到的格式集合
    func measureStateSynchronization(
        cursorPosition: Int,
        block: () throws -> Set<TextFormat>
    ) rethrows -> Set<TextFormat> {
        guard isEnabled else {
            return try block()
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        var success = true
        var detectedFormats: Set<TextFormat> = []

        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime

            // 记录性能数据
            recordMetric(
                type: .stateSynchronization,
                format: nil,
                duration: duration,
                success: success,
                additionalInfo: [
                    "cursorPosition": cursorPosition,
                    "formatCount": detectedFormats.count,
                ]
            )

            debugger.recordStateSynchronization(
                cursorPosition: cursorPosition,
                detectedFormats: detectedFormats,
                duration: duration,
                success: success
            )

            // 检查是否超过阈值
            if duration > thresholds.stateSynchronization {
                logger.logWarning(
                    "状态同步性能警告: 耗时 \(String(format: "%.2f", duration * 1000))ms (阈值: \(String(format: "%.2f", thresholds.stateSynchronization * 1000))ms)",
                    category: LogCategory.performance.rawValue
                )
            }
        }

        do {
            detectedFormats = try block()
            return detectedFormats
        } catch {
            success = false
            throw error
        }
    }

    /// 测量状态检测性能
    /// - Parameters:
    ///   - format: 格式类型
    ///   - block: 要测量的代码块，返回是否检测到格式
    /// - Returns: 是否检测到格式
    func measureStateDetection(
        _ format: TextFormat,
        block: () throws -> Bool
    ) rethrows -> Bool {
        guard isEnabled else {
            return try block()
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let detected = try block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // 记录性能数据
        recordMetric(
            type: .stateDetection,
            format: format,
            duration: duration,
            success: true
        )

        // 检查是否超过阈值
        if duration > thresholds.stateDetection {
            logger.logWarning(
                "状态检测性能警告: \(format.displayName) 耗时 \(String(format: "%.2f", duration * 1000))ms (阈值: \(String(format: "%.2f", thresholds.stateDetection * 1000))ms)",
                category: LogCategory.performance.rawValue
            )
        }

        return detected
    }

    /// 测量用户交互响应性能
    /// - Parameters:
    ///   - action: 交互动作描述
    ///   - block: 要测量的代码块
    /// - Returns: 代码块的返回值
    func measureUserInteraction<T>(
        _ action: String,
        block: () throws -> T
    ) rethrows -> T {
        guard isEnabled else {
            return try block()
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // 记录性能数据
        recordMetric(
            type: .userInteraction,
            format: nil,
            duration: duration,
            success: true,
            additionalInfo: ["action": action]
        )

        // 检查是否超过阈值
        if duration > thresholds.userInteraction {
            logger.logWarning(
                "用户交互性能警告: \(action) 耗时 \(String(format: "%.2f", duration * 1000))ms (阈值: \(String(format: "%.2f", thresholds.userInteraction * 1000))ms)",
                category: LogCategory.performance.rawValue
            )
        }

        return result
    }

    // MARK: - Query Methods

    /// 获取所有指标记录
    func getAllRecords() -> [FormatMenuMetricRecord] {
        metricRecords
    }

    /// 获取指定类型的记录
    func getRecords(for type: FormatMenuMetricType) -> [FormatMenuMetricRecord] {
        metricRecords.filter { $0.type == type }
    }

    /// 获取指定格式的记录
    func getRecords(for format: TextFormat) -> [FormatMenuMetricRecord] {
        metricRecords.filter { $0.format == format }
    }

    /// 获取最近的记录
    func getRecentRecords(count: Int = 50) -> [FormatMenuMetricRecord] {
        Array(metricRecords.suffix(count))
    }

    /// 获取超过阈值的记录
    func getThresholdExceededRecords() -> [FormatMenuMetricRecord] {
        metricRecords.filter { record in
            let threshold = getThreshold(for: record.type)
            return record.duration > threshold
        }
    }

    /// 获取失败的记录
    func getFailedRecords() -> [FormatMenuMetricRecord] {
        metricRecords.filter { !$0.success }
    }

    // MARK: - Performance Analysis

    /// 获取性能摘要
    func getPerformanceSummary() -> String {
        let stats = debugger.statistics

        var summary = """
        ========================================
        格式菜单性能摘要
        生成时间: \(ISO8601DateFormatter().string(from: Date()))
        ========================================

        ## 总体统计
        - 总记录数: \(metricRecords.count)
        - 格式应用次数: \(stats.totalApplications)
        - 状态同步次数: \(stats.totalSynchronizations)

        ## 平均性能
        - 格式应用平均时间: \(String(format: "%.2f", stats.avgApplicationTimeMs))ms
        - 状态同步平均时间: \(String(format: "%.2f", stats.avgSynchronizationTimeMs))ms

        ## 性能警告
        - 慢速格式应用: \(stats.slowApplications) 次
        - 慢速状态同步: \(stats.slowSynchronizations) 次

        ## 性能阈值
        - 格式应用阈值: \(String(format: "%.2f", thresholds.formatApplication * 1000))ms
        - 状态同步阈值: \(String(format: "%.2f", thresholds.stateSynchronization * 1000))ms
        - 状态检测阈值: \(String(format: "%.2f", thresholds.stateDetection * 1000))ms
        - 用户交互阈值: \(String(format: "%.2f", thresholds.userInteraction * 1000))ms

        """

        // 添加各类型的详细统计
        summary += "\n## 各类型详细统计\n"
        for type in FormatMenuMetricType.allCases {
            if let typeStats = realtimeStatistics[type] {
                summary += "\n" + typeStats.summary + "\n"
            }
        }

        // 添加慢速操作详情
        let slowApplications = debugger.getSlowApplicationRecords()
        if !slowApplications.isEmpty {
            summary += """

            ## 慢速格式应用详情 (最近 10 条)

            """

            for record in slowApplications.prefix(10) {
                summary += "- \(record.format.displayName): \(String(format: "%.2f", record.durationMs))ms\n"
            }
        }

        let slowSynchronizations = debugger.getSlowSynchronizationRecords()
        if !slowSynchronizations.isEmpty {
            summary += """

            ## 慢速状态同步详情 (最近 10 条)

            """

            for record in slowSynchronizations.prefix(10) {
                summary += "- 位置 \(record.cursorPosition): \(String(format: "%.2f", record.durationMs))ms\n"
            }
        }

        summary += """

        ========================================
        """

        return summary
    }

    /// 检查性能是否达标
    func checkPerformanceCompliance() -> (passed: Bool, issues: [String]) {
        let stats = debugger.statistics
        var issues: [String] = []

        // 检查平均格式应用时间
        if stats.avgApplicationTimeMs > thresholds.formatApplication * 1000 {
            issues
                .append(
                    "格式应用平均时间 (\(String(format: "%.2f", stats.avgApplicationTimeMs))ms) 超过阈值 (\(String(format: "%.2f", thresholds.formatApplication * 1000))ms)"
                )
        }

        // 检查平均状态同步时间
        if stats.avgSynchronizationTimeMs > thresholds.stateSynchronization * 1000 {
            issues
                .append(
                    "状态同步平均时间 (\(String(format: "%.2f", stats.avgSynchronizationTimeMs))ms) 超过阈值 (\(String(format: "%.2f", thresholds.stateSynchronization * 1000))ms)"
                )
        }

        // 检查慢速操作比例
        if stats.totalApplications > 0 {
            let slowRatio = Double(stats.slowApplications) / Double(stats.totalApplications)
            if slowRatio > 0.1 { // 超过 10% 的操作慢速
                issues.append("慢速格式应用比例过高: \(String(format: "%.1f", slowRatio * 100))%")
            }
        }

        if stats.totalSynchronizations > 0 {
            let slowRatio = Double(stats.slowSynchronizations) / Double(stats.totalSynchronizations)
            if slowRatio > 0.1 { // 超过 10% 的操作慢速
                issues.append("慢速状态同步比例过高: \(String(format: "%.1f", slowRatio * 100))%")
            }
        }

        // 检查失败率
        let failedRecords = getFailedRecords()
        if !metricRecords.isEmpty {
            let failureRate = Double(failedRecords.count) / Double(metricRecords.count)
            if failureRate > 0.05 { // 超过 5% 的操作失败
                issues.append("操作失败率过高: \(String(format: "%.1f", failureRate * 100))%")
            }
        }

        return (issues.isEmpty, issues)
    }

    /// 生成性能报告
    func generatePerformanceReport() -> String {
        var report = getPerformanceSummary()

        let (passed, issues) = checkPerformanceCompliance()

        report += """

        ## 性能合规性检查
        状态: \(passed ? "✅ 通过" : "❌ 未通过")

        """

        if !issues.isEmpty {
            report += """
            问题:

            """
            for issue in issues {
                report += "- \(issue)\n"
            }
        }

        return report
    }

    /// 导出性能报告
    func exportPerformanceReport(to url: URL) throws {
        let report = generatePerformanceReport()
        try report.write(to: url, atomically: true, encoding: .utf8)
        logger.logInfo("性能报告已导出到: \(url.path)", category: LogCategory.performance.rawValue)
    }

    // MARK: - Management

    /// 清除所有记录
    func clearAllRecords() {
        metricRecords.removeAll()
        realtimeStatistics.removeAll()
        logger.logInfo("已清除所有性能记录", category: LogCategory.performance.rawValue)
    }

    /// 清除指定类型的记录
    func clearRecords(for type: FormatMenuMetricType) {
        metricRecords.removeAll { $0.type == type }
        updateRealtimeStatistics()
    }

    /// 清除指定时间之前的记录
    func clearRecords(before date: Date) {
        metricRecords.removeAll { $0.timestamp < date }
        updateRealtimeStatistics()
    }
}

// MARK: - 便捷扩展

extension FormatMenuPerformanceMonitor {

    /// 创建性能测量器
    func createMeasurer(
        operation: String,
        format: TextFormat? = nil,
        type: FormatMenuMetricType = .formatApplication
    ) -> FormatMenuPerformanceMeasurer {
        FormatMenuPerformanceMeasurer(operation: operation, format: format, type: type)
    }

    /// 启用性能监控
    func enable() {
        isEnabled = true
        logger.logInfo("格式菜单性能监控已启用", category: LogCategory.performance.rawValue)
    }

    /// 禁用性能监控
    func disable() {
        isEnabled = false
        logger.logInfo("格式菜单性能监控已禁用", category: LogCategory.performance.rawValue)
    }

    /// 设置阈值
    func setThreshold(_ threshold: TimeInterval, for type: FormatMenuMetricType) {
        switch type {
        case .formatApplication:
            thresholds.formatApplication = threshold
        case .stateDetection:
            thresholds.stateDetection = threshold
        case .stateSynchronization:
            thresholds.stateSynchronization = threshold
        case .userInteraction:
            thresholds.userInteraction = threshold
        case .menuUpdate:
            thresholds.menuUpdate = threshold
        case .toolbarUpdate:
            thresholds.toolbarUpdate = threshold
        }
    }

    /// 获取指定类型的统计信息
    func getStatistics(for type: FormatMenuMetricType) -> FormatMenuPerformanceStatistics? {
        realtimeStatistics[type]
    }
}
