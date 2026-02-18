//
//  FormatOperationQueue.swift
//  MiNoteMac
//
//  格式操作队列管理器 - 管理连续格式操作，防止操作丢失和冲突
//

import AppKit
import Combine
import Foundation

// MARK: - 格式操作类型

/// 格式操作
struct FormatOperation: Identifiable, Equatable {
    let id: UUID
    let format: TextFormat
    let range: NSRange
    let timestamp: Date
    let priority: OperationPriority

    /// 操作优先级
    enum OperationPriority: Int, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case immediate = 3

        static func < (lhs: OperationPriority, rhs: OperationPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    init(
        format: TextFormat,
        range: NSRange,
        priority: OperationPriority = .normal
    ) {
        id = UUID()
        self.format = format
        self.range = range
        timestamp = Date()
        self.priority = priority
    }

    static func == (lhs: FormatOperation, rhs: FormatOperation) -> Bool {
        lhs.id == rhs.id
    }
}

/// 操作执行结果
struct OperationResult {
    let operation: FormatOperation
    let success: Bool
    let durationMs: Double
    let errorMessage: String?
}

// MARK: - 格式操作队列管理器

/// 格式操作队列管理器
///
/// 负责管理连续的格式操作，确保操作按顺序执行，
/// 防止操作丢失和冲突，并提供性能监控功能。
@MainActor
final class FormatOperationQueue {

    // MARK: - Singleton

    static let shared = FormatOperationQueue()

    // MARK: - Properties

    /// 操作队列
    private var operationQueue: [FormatOperation] = []

    /// 是否正在处理操作
    private var isProcessing = false

    /// 操作执行回调
    private var executeCallback: ((FormatOperation) async -> Bool)?

    /// 操作完成回调
    private var completionCallback: ((OperationResult) -> Void)?

    /// 最大队列长度
    private let maxQueueLength = 100

    /// 操作超时时间（秒）
    private let operationTimeout: TimeInterval = 5.0

    /// 合并相同操作的时间窗口（秒）
    private let mergeWindow: TimeInterval = 0.1

    /// 是否启用操作合并
    var enableOperationMerging = true

    /// 是否启用性能监控
    var enablePerformanceMonitoring = true

    /// 统计信息
    private var totalOperations = 0
    private var successfulOperations = 0
    private var failedOperations = 0
    private var droppedOperations = 0
    private var mergedOperations = 0
    private var totalProcessingTime: Double = 0
    private var maxProcessingTime: Double = 0

    /// 操作历史记录
    private var operationHistory: [OperationResult] = []
    private let maxHistoryCount = 200

    // MARK: - Initialization

    private init() {}

    // MARK: - 配置方法

    /// 设置操作执行回调
    /// - Parameter callback: 执行回调函数
    func setExecuteCallback(_ callback: @escaping (FormatOperation) async -> Bool) {
        executeCallback = callback
    }

    /// 设置操作完成回调
    /// - Parameter callback: 完成回调函数
    func setCompletionCallback(_ callback: @escaping (OperationResult) -> Void) {
        completionCallback = callback
    }

    // MARK: - 队列操作方法

    /// 添加格式操作到队列
    /// - Parameter operation: 格式操作
    /// - Returns: 是否成功添加
    @discardableResult
    func enqueue(_ operation: FormatOperation) -> Bool {
        // 检查队列是否已满
        if operationQueue.count >= maxQueueLength {
            print("[FormatOperationQueue] ⚠️ 队列已满，丢弃操作: \(operation.format.displayName)")
            droppedOperations += 1
            return false
        }

        // 尝试合并相同操作
        if enableOperationMerging {
            if let mergedIndex = findMergeableOperation(for: operation) {
                // 替换为新操作（保留最新的范围）
                operationQueue[mergedIndex] = operation
                mergedOperations += 1
                print("[FormatOperationQueue] 合并操作: \(operation.format.displayName)")
                return true
            }
        }

        // 根据优先级插入队列
        insertByPriority(operation)

        print("[FormatOperationQueue] 添加操作: \(operation.format.displayName), 队列长度: \(operationQueue.count)")

        // 开始处理队列
        processQueue()

        return true
    }

    /// 添加格式操作（便捷方法）
    /// - Parameters:
    ///   - format: 格式类型
    ///   - range: 选择范围
    ///   - priority: 优先级
    /// - Returns: 是否成功添加
    @discardableResult
    func enqueue(
        format: TextFormat,
        range: NSRange,
        priority: FormatOperation.OperationPriority = .normal
    ) -> Bool {
        let operation = FormatOperation(format: format, range: range, priority: priority)
        return enqueue(operation)
    }

    /// 取消所有待处理的操作
    func cancelAll() {
        let cancelledCount = operationQueue.count
        operationQueue.removeAll()
        droppedOperations += cancelledCount
        print("[FormatOperationQueue] 取消所有操作，共 \(cancelledCount) 个")
    }

    /// 取消指定格式的操作
    /// - Parameter format: 格式类型
    func cancel(format: TextFormat) {
        let beforeCount = operationQueue.count
        operationQueue.removeAll { $0.format == format }
        let cancelledCount = beforeCount - operationQueue.count
        droppedOperations += cancelledCount
        print("[FormatOperationQueue] 取消 \(format.displayName) 操作，共 \(cancelledCount) 个")
    }

    // MARK: - 队列处理方法

    /// 处理队列中的操作
    private func processQueue() {
        guard !isProcessing else { return }
        guard !operationQueue.isEmpty else { return }
        guard executeCallback != nil else {
            print("[FormatOperationQueue] ⚠️ 未设置执行回调")
            return
        }

        isProcessing = true

        Task {
            await processNextOperation()
        }
    }

    /// 处理下一个操作
    private func processNextOperation() async {
        guard let operation = operationQueue.first else {
            isProcessing = false
            return
        }

        // 从队列中移除
        operationQueue.removeFirst()

        // 执行操作
        let startTime = CFAbsoluteTimeGetCurrent()
        var success = false
        var errorMessage: String?

        do {
            if let callback = executeCallback {
                success = await callback(operation)
            }
        } catch {
            success = false
            errorMessage = error.localizedDescription
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let durationMs = (endTime - startTime) * 1000

        // 更新统计信息
        updateStatistics(success: success, durationMs: durationMs)

        // 记录结果
        let result = OperationResult(
            operation: operation,
            success: success,
            durationMs: durationMs,
            errorMessage: errorMessage
        )
        recordResult(result)

        // 调用完成回调
        completionCallback?(result)

        // 处理下一个操作
        if !operationQueue.isEmpty {
            await processNextOperation()
        } else {
            isProcessing = false
        }
    }

    // MARK: - 辅助方法

    /// 查找可合并的操作
    private func findMergeableOperation(for operation: FormatOperation) -> Int? {
        let now = Date()

        for (index, existingOp) in operationQueue.enumerated() {
            // 检查是否是相同格式
            guard existingOp.format == operation.format else { continue }

            // 检查时间窗口
            let timeDiff = now.timeIntervalSince(existingOp.timestamp)
            guard timeDiff < mergeWindow else { continue }

            // 检查范围是否重叠或相邻
            if rangesOverlapOrAdjacent(existingOp.range, operation.range) {
                return index
            }
        }

        return nil
    }

    /// 检查两个范围是否重叠或相邻
    private func rangesOverlapOrAdjacent(_ range1: NSRange, _ range2: NSRange) -> Bool {
        let end1 = range1.location + range1.length
        let end2 = range2.location + range2.length

        // 检查重叠
        if range1.location < end2 && range2.location < end1 {
            return true
        }

        // 检查相邻
        if end1 == range2.location || end2 == range1.location {
            return true
        }

        return false
    }

    /// 根据优先级插入操作
    private func insertByPriority(_ operation: FormatOperation) {
        // 找到第一个优先级低于新操作的位置
        if let insertIndex = operationQueue.firstIndex(where: { $0.priority < operation.priority }) {
            operationQueue.insert(operation, at: insertIndex)
        } else {
            operationQueue.append(operation)
        }
    }

    /// 更新统计信息
    private func updateStatistics(success: Bool, durationMs: Double) {
        totalOperations += 1

        if success {
            successfulOperations += 1
        } else {
            failedOperations += 1
        }

        totalProcessingTime += durationMs
        maxProcessingTime = max(maxProcessingTime, durationMs)
    }

    /// 记录操作结果
    private func recordResult(_ result: OperationResult) {
        operationHistory.append(result)

        // 限制历史记录数量
        if operationHistory.count > maxHistoryCount {
            operationHistory.removeFirst(operationHistory.count - maxHistoryCount)
        }
    }

    // MARK: - 查询方法

    /// 获取当前队列长度
    var queueLength: Int {
        operationQueue.count
    }

    /// 检查队列是否为空
    var isEmpty: Bool {
        operationQueue.isEmpty
    }

    /// 检查是否正在处理
    var processing: Bool {
        isProcessing
    }

    /// 获取待处理的操作
    func getPendingOperations() -> [FormatOperation] {
        operationQueue
    }

    /// 获取操作历史
    func getOperationHistory(count: Int = 50) -> [OperationResult] {
        let startIndex = max(0, operationHistory.count - count)
        return Array(operationHistory[startIndex...])
    }

    // MARK: - 统计方法

    /// 获取统计信息
    func getStatistics() -> [String: Any] {
        let avgTime = totalOperations > 0 ? totalProcessingTime / Double(totalOperations) : 0
        let successRate = totalOperations > 0 ? Double(successfulOperations) / Double(totalOperations) : 0

        return [
            "totalOperations": totalOperations,
            "successfulOperations": successfulOperations,
            "failedOperations": failedOperations,
            "droppedOperations": droppedOperations,
            "mergedOperations": mergedOperations,
            "averageProcessingTime": avgTime,
            "maxProcessingTime": maxProcessingTime,
            "totalProcessingTime": totalProcessingTime,
            "successRate": successRate,
            "currentQueueLength": operationQueue.count,
            "isProcessing": isProcessing,
        ]
    }

    /// 打印统计信息
    func printStatistics() {
        let stats = getStatistics()

        print("[FormatOperationQueue] 统计信息:")
        print("  - 总操作数: \(stats["totalOperations"] ?? 0)")
        print("  - 成功操作数: \(stats["successfulOperations"] ?? 0)")
        print("  - 失败操作数: \(stats["failedOperations"] ?? 0)")
        print("  - 丢弃操作数: \(stats["droppedOperations"] ?? 0)")
        print("  - 合并操作数: \(stats["mergedOperations"] ?? 0)")
        print("  - 平均处理时间: \(String(format: "%.2f", stats["averageProcessingTime"] as? Double ?? 0))ms")
        print("  - 最大处理时间: \(String(format: "%.2f", stats["maxProcessingTime"] as? Double ?? 0))ms")
        print("  - 成功率: \(String(format: "%.1f", (stats["successRate"] as? Double ?? 0) * 100))%")
        print("  - 当前队列长度: \(stats["currentQueueLength"] ?? 0)")
    }

    /// 生成性能报告
    func generatePerformanceReport() -> String {
        let stats = getStatistics()

        return """
        ========================================
        格式操作队列性能报告
        ========================================

        ## 操作统计
        - 总操作数: \(stats["totalOperations"] ?? 0)
        - 成功操作数: \(stats["successfulOperations"] ?? 0)
        - 失败操作数: \(stats["failedOperations"] ?? 0)
        - 丢弃操作数: \(stats["droppedOperations"] ?? 0)
        - 合并操作数: \(stats["mergedOperations"] ?? 0)

        ## 性能指标
        - 平均处理时间: \(String(format: "%.2f", stats["averageProcessingTime"] as? Double ?? 0))ms
        - 最大处理时间: \(String(format: "%.2f", stats["maxProcessingTime"] as? Double ?? 0))ms
        - 总处理时间: \(String(format: "%.2f", stats["totalProcessingTime"] as? Double ?? 0))ms
        - 成功率: \(String(format: "%.1f", (stats["successRate"] as? Double ?? 0) * 100))%

        ## 当前状态
        - 队列长度: \(stats["currentQueueLength"] ?? 0)
        - 正在处理: \(stats["isProcessing"] as? Bool ?? false ? "是" : "否")

        ========================================
        """
    }

    /// 重置统计信息
    func resetStatistics() {
        totalOperations = 0
        successfulOperations = 0
        failedOperations = 0
        droppedOperations = 0
        mergedOperations = 0
        totalProcessingTime = 0
        maxProcessingTime = 0
        operationHistory.removeAll()
    }
}
