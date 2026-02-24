import Combine
import Foundation

/// 性能监控器
///
/// 用于监控原生编辑器的性能指标，包括：
/// - 输入法状态检测
/// - 保存操作触发
/// - 视图更新频率
///
/// 使用单例模式，确保全局只有一个监控实例
@MainActor
class PerformanceMonitor: ObservableObject {

    // MARK: - 单例

    // 共享实例

    // MARK: - 输入法状态监控

    /// 输入法检测次数
    @Published var inputMethodDetectionCount = 0

    /// 输入法组合状态总持续时间（秒）
    @Published var inputMethodCompositionDuration: TimeInterval = 0

    // MARK: - 保存触发监控

    /// 保存请求总次数
    @Published var saveRequestCount = 0

    /// 实际执行保存的次数
    @Published var actualSaveCount = 0

    /// 因输入法状态而跳过的保存次数
    @Published var skippedSaveCountInputMethod = 0

    /// 因内容未变化而跳过的保存次数
    @Published var skippedSaveCountNoChange = 0

    // MARK: - 视图更新监控

    /// 视图重绘次数
    @Published var viewRedrawCount = 0

    /// 内容重新加载次数
    @Published var contentReloadCount = 0

    /// 状态更新次数
    @Published var stateUpdateCount = 0

    // MARK: - 私有属性

    /// 输入法组合开始时间（用于计算持续时间）
    private var compositionStartTime: Date?

    // MARK: - 初始化

    /// 初始化方法
    init() {}

    // MARK: - 输入法状态监控方法

    /// 记录输入法检测
    func recordInputMethodDetection() {
        inputMethodDetectionCount += 1
    }

    /// 记录输入法组合开始
    func recordCompositionStart() {
        compositionStartTime = Date()
    }

    /// 记录输入法组合结束
    func recordCompositionEnd() {
        if let startTime = compositionStartTime {
            inputMethodCompositionDuration += Date().timeIntervalSince(startTime)
            compositionStartTime = nil
        }
    }

    // MARK: - 保存触发监控方法

    /// 记录保存请求
    func recordSaveRequest() {
        saveRequestCount += 1
    }

    /// 记录实际保存
    func recordActualSave() {
        actualSaveCount += 1
    }

    /// 记录跳过保存（输入法状态）
    func recordSkippedSaveInputMethod() {
        skippedSaveCountInputMethod += 1
    }

    /// 记录跳过保存（内容未变化）
    func recordSkippedSaveNoChange() {
        skippedSaveCountNoChange += 1
    }

    // MARK: - 视图更新监控方法

    /// 记录视图重绘
    func recordViewRedraw() {
        viewRedrawCount += 1
    }

    /// 记录内容重新加载
    func recordContentReload() {
        contentReloadCount += 1
    }

    /// 记录状态更新
    func recordStateUpdate() {
        stateUpdateCount += 1
    }

    // MARK: - 工具方法

    /// 重置所有计数器
    func reset() {
        inputMethodDetectionCount = 0
        inputMethodCompositionDuration = 0
        saveRequestCount = 0
        actualSaveCount = 0
        skippedSaveCountInputMethod = 0
        skippedSaveCountNoChange = 0
        viewRedrawCount = 0
        contentReloadCount = 0
        stateUpdateCount = 0
        compositionStartTime = nil
    }

    /// 输出性能报告到日志
    func printReport() {
        var report = "性能监控报告 - "
        report += "输入法检测:\(inputMethodDetectionCount) "
        report += "保存请求:\(saveRequestCount) 实际保存:\(actualSaveCount) "
        report += "跳过(输入法):\(skippedSaveCountInputMethod) 跳过(无变化):\(skippedSaveCountNoChange)"
        if saveRequestCount > 0 {
            let efficiency = Double(actualSaveCount) / Double(saveRequestCount) * 100
            report += " 效率:\(String(format: "%.1f", efficiency))%"
        }
        LogService.shared.debug(.editor, report)
    }
}
