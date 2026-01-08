//
//  FormatMenuPerformanceMonitor.swift
//  MiNoteMac
//
//  格式菜单性能监控器 - 专门监控格式菜单操作的性能
//  需求: 8.3
//

import Foundation
import AppKit

// MARK: - 性能测量器

/// 格式菜单性能测量器
/// 用于测量格式菜单操作的执行时间
struct FormatMenuPerformanceMeasurer {
    let operation: String
    let format: TextFormat?
    let startTime: CFAbsoluteTime
    
    init(operation: String, format: TextFormat? = nil) {
        self.operation = operation
        self.format = format
        self.startTime = CFAbsoluteTimeGetCurrent()
    }
    
    /// 结束测量并记录
    @MainActor
    func finish(success: Bool = true, errorMessage: String? = nil, additionalInfo: [String: Any]? = nil) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        // 记录到调试器
        if operation.contains("格式应用") || operation.contains("applyFormat") {
            if let format = format {
                FormatMenuDebugger.shared.recordFormatApplication(
                    format: format,
                    selectedRange: NSRange(location: 0, length: 0),
                    cursorPosition: 0,
                    duration: duration,
                    success: success,
                    errorMessage: errorMessage
                )
            }
        } else if operation.contains("状态同步") || operation.contains("updateCurrentFormats") {
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
final class FormatMenuPerformanceMonitor {
    
    // MARK: - Singleton
    
    static let shared = FormatMenuPerformanceMonitor()
    
    // MARK: - Properties
    
    /// 是否启用性能监控
    var isEnabled: Bool = false
    
    /// 性能阈值（毫秒）
    struct PerformanceThresholds {
        var formatApplication: TimeInterval = 0.05  // 50ms
        var stateDetection: TimeInterval = 0.1      // 100ms
        var stateSynchronization: TimeInterval = 0.1 // 100ms
        var userInteraction: TimeInterval = 0.016    // 16ms (60fps)
    }
    
    var thresholds = PerformanceThresholds()
    
    /// 日志记录器
    private let logger = NativeEditorLogger.shared
    
    /// 调试器
    private let debugger = FormatMenuDebugger.shared
    
    // MARK: - Initialization
    
    private init() {}
    
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
        
        do {
            let result = try block()
            return result
        } catch {
            success = false
            errorMessage = error.localizedDescription
            throw error
        } finally {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            
            // 记录性能数据
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
                    category: "FormatMenuPerformance"
                )
            }
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
        
        do {
            detectedFormats = try block()
            return detectedFormats
        } catch {
            success = false
            throw error
        } finally {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            
            // 记录性能数据
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
                    category: "FormatMenuPerformance"
                )
            }
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
        
        // 检查是否超过阈值
        if duration > thresholds.stateDetection {
            logger.logWarning(
                "状态检测性能警告: \(format.displayName) 耗时 \(String(format: "%.2f", duration * 1000))ms (阈值: \(String(format: "%.2f", thresholds.stateDetection * 1000))ms)",
                category: "FormatMenuPerformance"
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
        
        // 检查是否超过阈值
        if duration > thresholds.userInteraction {
            logger.logWarning(
                "用户交互性能警告: \(action) 耗时 \(String(format: "%.2f", duration * 1000))ms (阈值: \(String(format: "%.2f", thresholds.userInteraction * 1000))ms)",
                category: "FormatMenuPerformance"
            )
        }
        
        return result
    }
    
    // MARK: - Performance Analysis
    
    /// 获取性能摘要
    func getPerformanceSummary() -> String {
        let stats = debugger.statistics
        
        var summary = """
        ========================================
        格式菜单性能摘要
        ========================================
        
        ## 总体统计
        - 总操作次数: \(stats.totalApplications + stats.totalSynchronizations)
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
        
        // 添加慢速操作详情
        let slowApplications = debugger.getSlowApplicationRecords()
        if !slowApplications.isEmpty {
            summary += """
            
            ## 慢速格式应用详情
            
            """
            
            for record in slowApplications.prefix(10) {
                summary += "- \(record.format.displayName): \(String(format: "%.2f", record.durationMs))ms\n"
            }
        }
        
        let slowSynchronizations = debugger.getSlowSynchronizationRecords()
        if !slowSynchronizations.isEmpty {
            summary += """
            
            ## 慢速状态同步详情
            
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
            issues.append("格式应用平均时间 (\(String(format: "%.2f", stats.avgApplicationTimeMs))ms) 超过阈值 (\(String(format: "%.2f", thresholds.formatApplication * 1000))ms)")
        }
        
        // 检查平均状态同步时间
        if stats.avgSynchronizationTimeMs > thresholds.stateSynchronization * 1000 {
            issues.append("状态同步平均时间 (\(String(format: "%.2f", stats.avgSynchronizationTimeMs))ms) 超过阈值 (\(String(format: "%.2f", thresholds.stateSynchronization * 1000))ms)")
        }
        
        // 检查慢速操作比例
        if stats.totalApplications > 0 {
            let slowRatio = Double(stats.slowApplications) / Double(stats.totalApplications)
            if slowRatio > 0.1 {  // 超过 10% 的操作慢速
                issues.append("慢速格式应用比例过高: \(String(format: "%.1f", slowRatio * 100))%")
            }
        }
        
        if stats.totalSynchronizations > 0 {
            let slowRatio = Double(stats.slowSynchronizations) / Double(stats.totalSynchronizations)
            if slowRatio > 0.1 {  // 超过 10% 的操作慢速
                issues.append("慢速状态同步比例过高: \(String(format: "%.1f", slowRatio * 100))%")
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
}

// MARK: - 便捷扩展

extension FormatMenuPerformanceMonitor {
    
    /// 创建性能测量器
    func createMeasurer(operation: String, format: TextFormat? = nil) -> FormatMenuPerformanceMeasurer {
        return FormatMenuPerformanceMeasurer(operation: operation, format: format)
    }
}
