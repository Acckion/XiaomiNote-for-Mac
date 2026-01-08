//
//  FormatApplicationPerformanceOptimizer.swift
//  MiNoteMac
//
//  格式应用性能优化器 - 优化格式应用的响应时间
//  需求: 3.1 - 确保50ms内开始格式应用
//

import Foundation
import AppKit
import Combine

// MARK: - 格式应用性能优化器

/// 格式应用性能优化器
/// 
/// 负责监控和优化格式应用的响应时间，确保在50ms内开始格式应用。
/// 提供性能测量、优化建议和性能报告功能。
@MainActor
final class FormatApplicationPerformanceOptimizer {
    
    // MARK: - Singleton
    
    static let shared = FormatApplicationPerformanceOptimizer()
    
    // MARK: - 性能阈值常量
    
    /// 格式应用响应时间阈值（毫秒）- 需求 3.1
    static let formatApplicationThresholdMs: Double = 50.0
    
    /// 状态同步响应时间阈值（毫秒）- 需求 3.2
    static let stateSyncThresholdMs: Double = 100.0
    
    // MARK: - Properties
    
    /// 是否启用性能监控
    var isEnabled: Bool = true
    
    /// 是否启用详细日志
    var verboseLogging: Bool = false
    
    /// 格式应用性能记录
    private var formatApplicationRecords: [FormatApplicationPerformanceRecord] = []
    
    /// 最大记录数量
    private let maxRecordCount: Int = 1000
    
    /// 性能统计
    private(set) var statistics: FormatApplicationStatistics = FormatApplicationStatistics()
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - 性能测量方法
    
    /// 测量格式应用性能
    /// - Parameters:
    ///   - format: 格式类型
    ///   - selectedRange: 选择范围
    ///   - block: 要测量的代码块
    /// - Returns: 代码块的返回值
    func measureFormatApplication<T>(
        format: TextFormat,
        selectedRange: NSRange,
        block: () throws -> T
    ) rethrows -> T {
        guard isEnabled else {
            return try block()
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        var success = true
        var errorMessage: String?
        
        defer {
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            // 记录性能数据
            recordFormatApplication(
                format: format,
                selectedRange: selectedRange,
                durationMs: durationMs,
                success: success,
                errorMessage: errorMessage
            )
            
            // 检查是否超过阈值
            if durationMs > Self.formatApplicationThresholdMs {
                logPerformanceWarning(
                    operation: "格式应用",
                    format: format,
                    durationMs: durationMs,
                    thresholdMs: Self.formatApplicationThresholdMs
                )
            } else if verboseLogging {
                print("[FormatPerformance] ✅ 格式应用完成: \(format.displayName), 耗时: \(String(format: "%.2f", durationMs))ms")
            }
        }
        
        do {
            let result = try block()
            return result
        } catch {
            success = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    /// 测量格式应用性能（异步版本）
    /// - Parameters:
    ///   - format: 格式类型
    ///   - selectedRange: 选择范围
    ///   - block: 要测量的异步代码块
    /// - Returns: 代码块的返回值
    func measureFormatApplicationAsync<T>(
        format: TextFormat,
        selectedRange: NSRange,
        block: () async throws -> T
    ) async rethrows -> T {
        guard isEnabled else {
            return try await block()
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        var success = true
        var errorMessage: String?
        
        defer {
            let endTime = CFAbsoluteTimeGetCurrent()
            let durationMs = (endTime - startTime) * 1000
            
            // 记录性能数据
            recordFormatApplication(
                format: format,
                selectedRange: selectedRange,
                durationMs: durationMs,
                success: success,
                errorMessage: errorMessage
            )
            
            // 检查是否超过阈值
            if durationMs > Self.formatApplicationThresholdMs {
                logPerformanceWarning(
                    operation: "格式应用",
                    format: format,
                    durationMs: durationMs,
                    thresholdMs: Self.formatApplicationThresholdMs
                )
            }
        }
        
        do {
            let result = try await block()
            return result
        } catch {
            success = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    /// 开始格式应用测量
    /// - Parameters:
    ///   - format: 格式类型
    ///   - selectedRange: 选择范围
    /// - Returns: 测量上下文
    func beginMeasurement(format: TextFormat, selectedRange: NSRange) -> FormatApplicationMeasurementContext {
        return FormatApplicationMeasurementContext(
            format: format,
            selectedRange: selectedRange,
            startTime: CFAbsoluteTimeGetCurrent()
        )
    }
    
    /// 结束格式应用测量
    /// - Parameters:
    ///   - context: 测量上下文
    ///   - success: 是否成功
    ///   - errorMessage: 错误信息（可选）
    func endMeasurement(
        _ context: FormatApplicationMeasurementContext,
        success: Bool = true,
        errorMessage: String? = nil
    ) {
        guard isEnabled else { return }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let durationMs = (endTime - context.startTime) * 1000
        
        // 记录性能数据
        recordFormatApplication(
            format: context.format,
            selectedRange: context.selectedRange,
            durationMs: durationMs,
            success: success,
            errorMessage: errorMessage
        )
        
        // 检查是否超过阈值
        if durationMs > Self.formatApplicationThresholdMs {
            logPerformanceWarning(
                operation: "格式应用",
                format: context.format,
                durationMs: durationMs,
                thresholdMs: Self.formatApplicationThresholdMs
            )
        } else if verboseLogging {
            print("[FormatPerformance] ✅ 格式应用完成: \(context.format.displayName), 耗时: \(String(format: "%.2f", durationMs))ms")
        }
    }
    
    // MARK: - 记录方法
    
    /// 记录格式应用性能
    private func recordFormatApplication(
        format: TextFormat,
        selectedRange: NSRange,
        durationMs: Double,
        success: Bool,
        errorMessage: String?
    ) {
        let record = FormatApplicationPerformanceRecord(
            timestamp: Date(),
            format: format,
            selectedRange: selectedRange,
            durationMs: durationMs,
            success: success,
            errorMessage: errorMessage,
            exceededThreshold: durationMs > Self.formatApplicationThresholdMs
        )
        
        // 添加记录
        formatApplicationRecords.append(record)
        
        // 限制记录数量
        if formatApplicationRecords.count > maxRecordCount {
            formatApplicationRecords.removeFirst(formatApplicationRecords.count - maxRecordCount)
        }
        
        // 更新统计信息
        updateStatistics(with: record)
    }
    
    /// 更新统计信息
    private func updateStatistics(with record: FormatApplicationPerformanceRecord) {
        statistics.totalApplications += 1
        statistics.totalDurationMs += record.durationMs
        
        if record.exceededThreshold {
            statistics.slowApplications += 1
        }
        
        if !record.success {
            statistics.failedApplications += 1
        }
        
        // 更新最大/最小值
        statistics.maxDurationMs = max(statistics.maxDurationMs, record.durationMs)
        if statistics.minDurationMs == 0 {
            statistics.minDurationMs = record.durationMs
        } else {
            statistics.minDurationMs = min(statistics.minDurationMs, record.durationMs)
        }
        
        // 按格式类型统计
        statistics.applicationsByFormat[record.format, default: 0] += 1
        statistics.durationByFormat[record.format, default: 0] += record.durationMs
    }
    
    // MARK: - 日志方法
    
    /// 记录性能警告
    private func logPerformanceWarning(
        operation: String,
        format: TextFormat,
        durationMs: Double,
        thresholdMs: Double
    ) {
        print("[FormatPerformance] ⚠️ \(operation)性能警告: \(format.displayName)")
        print("  - 耗时: \(String(format: "%.2f", durationMs))ms")
        print("  - 阈值: \(String(format: "%.2f", thresholdMs))ms")
        print("  - 超出: \(String(format: "%.2f", durationMs - thresholdMs))ms")
    }
    
    // MARK: - 查询方法
    
    /// 获取最近的性能记录
    /// - Parameter count: 记录数量
    /// - Returns: 性能记录数组
    func getRecentRecords(count: Int = 100) -> [FormatApplicationPerformanceRecord] {
        let startIndex = max(0, formatApplicationRecords.count - count)
        return Array(formatApplicationRecords[startIndex...])
    }
    
    /// 获取慢速格式应用记录
    /// - Returns: 超过阈值的记录数组
    func getSlowApplicationRecords() -> [FormatApplicationPerformanceRecord] {
        return formatApplicationRecords.filter { $0.exceededThreshold }
    }
    
    /// 获取失败的格式应用记录
    /// - Returns: 失败的记录数组
    func getFailedApplicationRecords() -> [FormatApplicationPerformanceRecord] {
        return formatApplicationRecords.filter { !$0.success }
    }
    
    /// 获取指定格式的性能记录
    /// - Parameter format: 格式类型
    /// - Returns: 该格式的记录数组
    func getRecords(for format: TextFormat) -> [FormatApplicationPerformanceRecord] {
        return formatApplicationRecords.filter { $0.format == format }
    }
    
    // MARK: - 统计方法
    
    /// 获取平均格式应用时间
    /// - Returns: 平均时间（毫秒）
    func getAverageApplicationTime() -> Double {
        guard statistics.totalApplications > 0 else { return 0 }
        return statistics.totalDurationMs / Double(statistics.totalApplications)
    }
    
    /// 获取指定格式的平均应用时间
    /// - Parameter format: 格式类型
    /// - Returns: 平均时间（毫秒）
    func getAverageApplicationTime(for format: TextFormat) -> Double {
        let count = statistics.applicationsByFormat[format] ?? 0
        let duration = statistics.durationByFormat[format] ?? 0
        guard count > 0 else { return 0 }
        return duration / Double(count)
    }
    
    /// 获取慢速应用比例
    /// - Returns: 慢速应用比例（0-1）
    func getSlowApplicationRatio() -> Double {
        guard statistics.totalApplications > 0 else { return 0 }
        return Double(statistics.slowApplications) / Double(statistics.totalApplications)
    }
    
    /// 检查性能是否达标
    /// - Returns: (是否达标, 问题列表)
    func checkPerformanceCompliance() -> (passed: Bool, issues: [String]) {
        var issues: [String] = []
        
        // 检查平均格式应用时间
        let avgTime = getAverageApplicationTime()
        if avgTime > Self.formatApplicationThresholdMs {
            issues.append("平均格式应用时间 (\(String(format: "%.2f", avgTime))ms) 超过阈值 (\(Self.formatApplicationThresholdMs)ms)")
        }
        
        // 检查慢速应用比例
        let slowRatio = getSlowApplicationRatio()
        if slowRatio > 0.1 {  // 超过 10% 的操作慢速
            issues.append("慢速格式应用比例过高: \(String(format: "%.1f", slowRatio * 100))%")
        }
        
        // 检查失败比例
        if statistics.totalApplications > 0 {
            let failRatio = Double(statistics.failedApplications) / Double(statistics.totalApplications)
            if failRatio > 0.01 {  // 超过 1% 的操作失败
                issues.append("格式应用失败比例过高: \(String(format: "%.1f", failRatio * 100))%")
            }
        }
        
        return (issues.isEmpty, issues)
    }
    
    // MARK: - 报告方法
    
    /// 生成性能报告
    /// - Returns: 性能报告字符串
    func generatePerformanceReport() -> String {
        var report = """
        ========================================
        格式应用性能报告
        ========================================
        
        ## 总体统计
        - 总应用次数: \(statistics.totalApplications)
        - 成功次数: \(statistics.totalApplications - statistics.failedApplications)
        - 失败次数: \(statistics.failedApplications)
        - 慢速次数: \(statistics.slowApplications)
        
        ## 性能指标
        - 平均耗时: \(String(format: "%.2f", getAverageApplicationTime()))ms
        - 最大耗时: \(String(format: "%.2f", statistics.maxDurationMs))ms
        - 最小耗时: \(String(format: "%.2f", statistics.minDurationMs))ms
        - 总耗时: \(String(format: "%.2f", statistics.totalDurationMs))ms
        
        ## 性能阈值
        - 格式应用阈值: \(Self.formatApplicationThresholdMs)ms
        - 慢速应用比例: \(String(format: "%.1f", getSlowApplicationRatio() * 100))%
        
        """
        
        // 按格式类型统计
        if !statistics.applicationsByFormat.isEmpty {
            report += """
            
            ## 按格式类型统计
            
            """
            
            for (format, count) in statistics.applicationsByFormat.sorted(by: { $0.value > $1.value }) {
                let avgTime = getAverageApplicationTime(for: format)
                report += "- \(format.displayName): \(count) 次, 平均 \(String(format: "%.2f", avgTime))ms\n"
            }
        }
        
        // 性能合规性检查
        let (passed, issues) = checkPerformanceCompliance()
        report += """
        
        ## 性能合规性检查
        状态: \(passed ? "✅ 通过" : "❌ 未通过")
        
        """
        
        if !issues.isEmpty {
            report += "问题:\n"
            for issue in issues {
                report += "- \(issue)\n"
            }
        }
        
        report += """
        
        ========================================
        """
        
        return report
    }
    
    // MARK: - 重置方法
    
    /// 重置所有记录和统计
    func reset() {
        formatApplicationRecords.removeAll()
        statistics = FormatApplicationStatistics()
    }
}

// MARK: - 支持类型

/// 格式应用性能记录
struct FormatApplicationPerformanceRecord {
    let timestamp: Date
    let format: TextFormat
    let selectedRange: NSRange
    let durationMs: Double
    let success: Bool
    let errorMessage: String?
    let exceededThreshold: Bool
}

/// 格式应用测量上下文
struct FormatApplicationMeasurementContext {
    let format: TextFormat
    let selectedRange: NSRange
    let startTime: CFAbsoluteTime
}

/// 格式应用统计信息
struct FormatApplicationStatistics {
    var totalApplications: Int = 0
    var slowApplications: Int = 0
    var failedApplications: Int = 0
    var totalDurationMs: Double = 0
    var maxDurationMs: Double = 0
    var minDurationMs: Double = 0
    var applicationsByFormat: [TextFormat: Int] = [:]
    var durationByFormat: [TextFormat: Double] = [:]
}
