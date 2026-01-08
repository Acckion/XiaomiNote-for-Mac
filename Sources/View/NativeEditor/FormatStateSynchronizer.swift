//
//  FormatStateSynchronizer.swift
//  MiNoteMac
//
//  格式状态同步器 - 管理格式菜单按钮状态与编辑器实际状态的同步
//  需求: 3.2, 3.3
//

import Foundation
import AppKit

/// 格式状态同步器
/// 
/// 负责管理格式菜单按钮状态与编辑器实际状态的同步，
/// 使用防抖机制避免频繁更新，并提供性能监控功能。
@MainActor
class FormatStateSynchronizer {
    
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
    private var updateCount: Int = 0
    private var totalUpdateTime: Double = 0
    private var maxUpdateTime: Double = 0
    private var minUpdateTime: Double = Double.infinity
    
    // MARK: - Initialization
    
    /// 初始化格式状态同步器
    /// - Parameters:
    ///   - debounceInterval: 防抖间隔（默认 0.1 秒）
    ///   - performanceMonitoringEnabled: 是否启用性能监控（默认 true）
    ///   - performanceThreshold: 性能阈值（默认 50 毫秒）
    init(
        debounceInterval: TimeInterval = 0.1,
        performanceMonitoringEnabled: Bool = true,
        performanceThreshold: Double = 50.0
    ) {
        self.debounceInterval = debounceInterval
        self.performanceMonitoringEnabled = performanceMonitoringEnabled
        self.performanceThreshold = performanceThreshold
    }
    
    // MARK: - Public Methods
    
    /// 设置更新回调
    /// - Parameter callback: 更新回调函数
    func setUpdateCallback(_ callback: @escaping () -> Void) {
        self.updateCallback = callback
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
                "minTime": 0.0
            ]
        }
        
        let averageTime = totalUpdateTime / Double(updateCount)
        
        return [
            "updateCount": updateCount,
            "averageTime": averageTime,
            "maxTime": maxUpdateTime,
            "minTime": minUpdateTime,
            "totalTime": totalUpdateTime
        ]
    }
    
    /// 重置性能统计信息
    func resetPerformanceStats() {
        updateCount = 0
        totalUpdateTime = 0
        maxUpdateTime = 0
        minUpdateTime = Double.infinity
    }
    
    /// 打印性能统计信息
    func printPerformanceStats() {
        let stats = getPerformanceStats()
        
        print("[FormatStateSynchronizer] 性能统计:")
        print("  - 更新次数: \(stats["updateCount"] ?? 0)")
        print("  - 平均耗时: \(String(format: "%.2f", stats["averageTime"] as? Double ?? 0))ms")
        print("  - 最大耗时: \(String(format: "%.2f", stats["maxTime"] as? Double ?? 0))ms")
        print("  - 最小耗时: \(String(format: "%.2f", stats["minTime"] as? Double ?? 0))ms")
        print("  - 总耗时: \(String(format: "%.2f", stats["totalTime"] as? Double ?? 0))ms")
    }
    
    // MARK: - Private Methods
    
    /// 执行状态更新
    private func performStateUpdate() {
        guard let callback = updateCallback else {
            print("[FormatStateSynchronizer] 警告: 未设置更新回调")
            return
        }
        
        if performanceMonitoringEnabled {
            // 记录开始时间
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // 执行更新
            callback()
            
            // 计算耗时
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            
            // 更新统计信息
            updateStatistics(duration: duration)
            
            // 检查性能
            if duration > performanceThreshold {
                print("[FormatStateSynchronizer] ⚠️ 警告: 状态更新耗时 \(String(format: "%.2f", duration))ms，超过阈值 \(performanceThreshold)ms")
            }
            
            #if DEBUG
            print("[FormatStateSynchronizer] 状态更新完成，耗时: \(String(format: "%.2f", duration))ms")
            #endif
        } else {
            // 不监控性能，直接执行更新
            callback()
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
        return FormatStateSynchronizer(
            debounceInterval: 0.1,
            performanceMonitoringEnabled: true,
            performanceThreshold: 50.0
        )
    }
    
    /// 创建快速响应的格式状态同步器
    /// - Returns: 快速响应配置的格式状态同步器
    static func createFastResponse() -> FormatStateSynchronizer {
        return FormatStateSynchronizer(
            debounceInterval: 0.05,
            performanceMonitoringEnabled: true,
            performanceThreshold: 30.0
        )
    }
    
    /// 创建节能模式的格式状态同步器
    /// - Returns: 节能模式配置的格式状态同步器
    static func createPowerSaving() -> FormatStateSynchronizer {
        return FormatStateSynchronizer(
            debounceInterval: 0.2,
            performanceMonitoringEnabled: false,
            performanceThreshold: 100.0
        )
    }
}
