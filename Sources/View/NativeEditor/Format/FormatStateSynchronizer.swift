//
//  FormatStateSynchronizer.swift
//  MiNoteMac
//
//  格式状态同步器 - 管理格式菜单按钮状态与编辑器实际状态的同步
//

import AppKit
import Foundation

/// 状态同步性能记录
struct StateSyncPerformanceRecord {
    let timestamp: Date
    let durationMs: Double
    let success: Bool
    let errorMessage: String?
    let exceededThreshold: Bool
}

/// 格式状态同步器
///
/// 负责管理格式菜单按钮状态与编辑器实际状态的同步，
/// 使用防抖机制避免频繁更新，并提供性能监控功能。
@MainActor
class FormatStateSynchronizer {

    // MARK: - 性能阈值常量

    static let stateSyncThresholdMs = 100.0

    // MARK: - Properties

    /// 防抖定时器
    private var debounceTimer: Timer?

    /// 防抖间隔（秒）
    private let debounceInterval: TimeInterval

    /// 性能监控是否启用
    private let performanceMonitoringEnabled: Bool

    /// 性能阈值（毫秒）- 超过此值会记录警告
    private let performanceThreshold: Double

    /// 更新回调
    private var updateCallback: (() -> Void)?

    /// 统计信息
    private var updateCount = 0
    private var totalUpdateTime: Double = 0
    private var maxUpdateTime: Double = 0
    private var minUpdateTime = Double.infinity

    /// 慢速更新次数
    private var slowUpdateCount = 0

    /// 失败更新次数
    private var failedUpdateCount = 0

    /// 性能记录
    private var performanceRecords: [StateSyncPerformanceRecord] = []

    /// 最大记录数量
    private let maxRecordCount = 500

    // MARK: - Initialization

    /// 初始化格式状态同步器
    /// - Parameters:
    ///   - debounceInterval: 防抖间隔（默认 0.1 秒）
    ///   - performanceMonitoringEnabled: 是否启用性能监控（默认 true）
    init(
        debounceInterval: TimeInterval = 0.1,
        performanceMonitoringEnabled: Bool = true,
        performanceThreshold: Double = 100.0
    ) {
        self.debounceInterval = debounceInterval
        self.performanceMonitoringEnabled = performanceMonitoringEnabled
        self.performanceThreshold = performanceThreshold
    }

    // MARK: - Public Methods

    /// 设置更新回调
    /// - Parameter callback: 更新回调函数
    func setUpdateCallback(_ callback: @escaping () -> Void) {
        updateCallback = callback
    }

    /// 调度状态更新（使用防抖）
    ///
    /// 此方法会取消之前的更新请求，并在防抖间隔后执行新的更新。
    /// 这样可以避免在快速移动光标时频繁更新状态。
    func scheduleStateUpdate() {
        // 取消之前的定时器
        debounceTimer?.invalidate()

        // 创建新的定时器
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.performStateUpdate()
        }
    }

    /// 立即执行状态更新（不使用防抖）
    ///
    /// 在某些情况下（如用户点击格式按钮），我们需要立即更新状态，
    /// 而不是等待防抖间隔。
    func performImmediateUpdate() {
        // 取消防抖定时器
        debounceTimer?.invalidate()

        // 立即执行更新
        performStateUpdate()
    }

    /// 取消待处理的更新
    func cancelPendingUpdate() {
        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    /// 获取性能统计信息
    /// - Returns: 性能统计信息字典
    func getPerformanceStats() -> [String: Any] {
        guard updateCount > 0 else {
            return [
                "updateCount": 0,
                "averageTime": 0.0,
                "maxTime": 0.0,
                "minTime": 0.0,
                "slowUpdateCount": 0,
                "failedUpdateCount": 0,
                "slowUpdateRatio": 0.0,
            ]
        }

        let averageTime = totalUpdateTime / Double(updateCount)
        let slowRatio = Double(slowUpdateCount) / Double(updateCount)

        return [
            "updateCount": updateCount,
            "averageTime": averageTime,
            "maxTime": maxUpdateTime,
            "minTime": minUpdateTime,
            "totalTime": totalUpdateTime,
            "slowUpdateCount": slowUpdateCount,
            "failedUpdateCount": failedUpdateCount,
            "slowUpdateRatio": slowRatio,
            "thresholdMs": performanceThreshold,
        ]
    }

    /// 重置性能统计信息
    func resetPerformanceStats() {
        updateCount = 0
        totalUpdateTime = 0
        maxUpdateTime = 0
        minUpdateTime = Double.infinity
        slowUpdateCount = 0
        failedUpdateCount = 0
        performanceRecords.removeAll()
    }

    /// 打印性能统计信息
    func printPerformanceStats() {
        // 调试方法，保留但不自动输出
    }

    /// 获取最近的性能记录
    /// - Parameter count: 记录数量
    /// - Returns: 性能记录数组
    func getRecentRecords(count: Int = 100) -> [StateSyncPerformanceRecord] {
        let startIndex = max(0, performanceRecords.count - count)
        return Array(performanceRecords[startIndex...])
    }

    /// 获取慢速更新记录
    /// - Returns: 超过阈值的记录数组
    func getSlowUpdateRecords() -> [StateSyncPerformanceRecord] {
        performanceRecords.filter(\.exceededThreshold)
    }

    /// 检查性能是否达标
    /// - Returns: (是否达标, 问题列表)
    func checkPerformanceCompliance() -> (passed: Bool, issues: [String]) {
        var issues: [String] = []

        guard updateCount > 0 else {
            return (true, [])
        }

        // 检查平均状态同步时间
        let avgTime = totalUpdateTime / Double(updateCount)
        if avgTime > performanceThreshold {
            issues.append("平均状态同步时间 (\(String(format: "%.2f", avgTime))ms) 超过阈值 (\(performanceThreshold)ms)")
        }

        // 检查慢速更新比例
        let slowRatio = Double(slowUpdateCount) / Double(updateCount)
        if slowRatio > 0.1 { // 超过 10% 的操作慢速
            issues.append("慢速状态同步比例过高: \(String(format: "%.1f", slowRatio * 100))%")
        }

        // 检查最大耗时
        if maxUpdateTime > performanceThreshold * 2 {
            issues.append("最大状态同步时间 (\(String(format: "%.2f", maxUpdateTime))ms) 严重超过阈值")
        }

        return (issues.isEmpty, issues)
    }

    /// 生成性能报告
    /// - Returns: 性能报告字符串
    func generatePerformanceReport() -> String {
        let stats = getPerformanceStats()
        let (passed, issues) = checkPerformanceCompliance()

        var report = """
        ========================================
        状态同步性能报告
        ========================================

        ## 总体统计
        - 更新次数: \(stats["updateCount"] ?? 0)
        - 慢速更新次数: \(stats["slowUpdateCount"] ?? 0)
        - 失败更新次数: \(stats["failedUpdateCount"] ?? 0)

        ## 性能指标
        - 平均耗时: \(String(format: "%.2f", stats["averageTime"] as? Double ?? 0))ms
        - 最大耗时: \(String(format: "%.2f", stats["maxTime"] as? Double ?? 0))ms
        - 最小耗时: \(String(format: "%.2f", stats["minTime"] as? Double ?? 0))ms
        - 总耗时: \(String(format: "%.2f", stats["totalTime"] as? Double ?? 0))ms

        ## 性能阈值
        - 状态同步阈值: \(performanceThreshold)ms
        - 慢速更新比例: \(String(format: "%.1f", (stats["slowUpdateRatio"] as? Double ?? 0) * 100))%

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

    // MARK: - Private Methods

    /// 执行状态更新
    private func performStateUpdate() {
        guard let callback = updateCallback else {
            return
        }

        if performanceMonitoringEnabled {
            // 记录开始时间
            let startTime = CFAbsoluteTimeGetCurrent()
            var success = true
            var errorMessage: String?

            // 执行更新
            do {
                callback()
            } catch {
                success = false
                errorMessage = error.localizedDescription
                failedUpdateCount += 1
            }

            // 计算耗时
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            let exceededThreshold = duration > performanceThreshold

            // 更新统计信息
            updateStatistics(duration: duration)

            // 记录性能数据
            recordPerformance(
                durationMs: duration,
                success: success,
                errorMessage: errorMessage,
                exceededThreshold: exceededThreshold
            )

            // 检查性能
            if exceededThreshold {
                slowUpdateCount += 1
            }
        } else {
            // 不监控性能，直接执行更新
            callback()
        }
    }

    /// 记录性能数据
    private func recordPerformance(
        durationMs: Double,
        success: Bool,
        errorMessage: String?,
        exceededThreshold: Bool
    ) {
        let record = StateSyncPerformanceRecord(
            timestamp: Date(),
            durationMs: durationMs,
            success: success,
            errorMessage: errorMessage,
            exceededThreshold: exceededThreshold
        )

        performanceRecords.append(record)

        // 限制记录数量
        if performanceRecords.count > maxRecordCount {
            performanceRecords.removeFirst(performanceRecords.count - maxRecordCount)
        }
    }

    /// 更新统计信息
    /// - Parameter duration: 更新耗时（毫秒）
    private func updateStatistics(duration: Double) {
        updateCount += 1
        totalUpdateTime += duration
        maxUpdateTime = max(maxUpdateTime, duration)
        minUpdateTime = min(minUpdateTime, duration)
    }

    // MARK: - Deinit

    // 注意：由于 @MainActor 的限制，我们不能在 deinit 中访问 debounceTimer
    // Timer 会在对象销毁时自动失效
}

// MARK: - FormatStateSynchronizer Extension

extension FormatStateSynchronizer {

    /// 创建默认的格式状态同步器
    /// - Returns: 默认配置的格式状态同步器
    static func createDefault() -> FormatStateSynchronizer {
        FormatStateSynchronizer(
            debounceInterval: 0.1,
            performanceMonitoringEnabled: true,
            performanceThreshold: 100.0
        )
    }

    /// 创建快速响应的格式状态同步器
    /// - Returns: 快速响应配置的格式状态同步器
    static func createFastResponse() -> FormatStateSynchronizer {
        FormatStateSynchronizer(
            debounceInterval: 0.05,
            performanceMonitoringEnabled: true,
            performanceThreshold: 50.0
        )
    }

    /// 创建节能模式的格式状态同步器
    /// - Returns: 节能模式配置的格式状态同步器
    static func createPowerSaving() -> FormatStateSynchronizer {
        FormatStateSynchronizer(
            debounceInterval: 0.2,
            performanceMonitoringEnabled: false,
            performanceThreshold: 150.0
        )
    }

    /// 创建用于测试的格式状态同步器
    /// - Returns: 测试配置的格式状态同步器
    static func createForTesting() -> FormatStateSynchronizer {
        FormatStateSynchronizer(
            debounceInterval: 0.01, // 更短的防抖间隔用于测试
            performanceMonitoringEnabled: true,
            performanceThreshold: 100.0
        )
    }
}
