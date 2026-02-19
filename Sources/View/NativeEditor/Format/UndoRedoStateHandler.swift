//
//  UndoRedoStateHandler.swift
//  MiNoteMac
//
//  撤销/重做操作状态处理器 - 确保撤销/重做操作后格式菜单状态正确更新
//

import AppKit
import Combine
import Foundation

/// 撤销/重做操作类型
enum UndoRedoOperationType: String {
    case undo = "撤销"
    case redo = "重做"
}

/// 撤销/重做操作记录
struct UndoRedoOperationRecord {
    let timestamp: Date
    let operationType: UndoRedoOperationType
    let formatsBefore: Set<TextFormat>
    let formatsAfter: Set<TextFormat>
    let cursorPositionBefore: Int
    let cursorPositionAfter: Int
    let success: Bool
    let errorMessage: String?

    /// 格式是否发生变化
    var formatsChanged: Bool {
        formatsBefore != formatsAfter
    }

    /// 光标位置是否发生变化
    var cursorPositionChanged: Bool {
        cursorPositionBefore != cursorPositionAfter
    }
}

/// 撤销/重做状态处理器
///
/// 负责监听撤销/重做操作，并确保格式菜单状态正确更新。
@MainActor
class UndoRedoStateHandler {

    // MARK: - Singleton

    static let shared = UndoRedoStateHandler()

    // MARK: - Properties

    /// 操作记录
    private var operationRecords: [UndoRedoOperationRecord] = []

    /// 最大记录数量
    private let maxRecordCount = 100

    /// 状态更新延迟（毫秒）
    private let stateUpdateDelayMs: UInt64 = 50

    /// 是否启用详细日志
    var verboseLogging = true

    /// 统计信息
    private var undoCount = 0
    private var redoCount = 0
    private var successCount = 0
    private var failureCount = 0

    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 状态更新回调
    private var stateUpdateCallback: (() -> Void)?

    /// 内容同步回调
    private var contentSyncCallback: (() -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 设置状态更新回调
    /// - Parameter callback: 状态更新回调函数
    func setStateUpdateCallback(_ callback: @escaping () -> Void) {
        stateUpdateCallback = callback
    }

    /// 设置内容同步回调
    /// - Parameter callback: 内容同步回调函数
    func setContentSyncCallback(_ callback: @escaping () -> Void) {
        contentSyncCallback = callback
    }

    /// 处理撤销操作
    /// - Parameters:
    ///   - formatsBefore: 撤销前的格式状态
    ///   - cursorPositionBefore: 撤销前的光标位置
    /// - Returns: 处理结果
    func handleUndoOperation(
        formatsBefore: Set<TextFormat>,
        cursorPositionBefore: Int
    ) async -> UndoRedoOperationRecord {
        undoCount += 1

        // 1. 同步内容
        contentSyncCallback?()

        // 2. 等待撤销操作完成
        try? await Task.sleep(nanoseconds: stateUpdateDelayMs * 1_000_000)

        // 3. 强制更新格式状态
        stateUpdateCallback?()

        // 4. 再次等待状态更新完成
        try? await Task.sleep(nanoseconds: stateUpdateDelayMs * 1_000_000)

        // 5. 获取撤销后的状态（这里需要从外部获取，暂时使用空集合）
        let formatsAfter: Set<TextFormat> = []
        let cursorPositionAfter = 0

        // 6. 记录操作
        let record = UndoRedoOperationRecord(
            timestamp: Date(),
            operationType: .undo,
            formatsBefore: formatsBefore,
            formatsAfter: formatsAfter,
            cursorPositionBefore: cursorPositionBefore,
            cursorPositionAfter: cursorPositionAfter,
            success: true,
            errorMessage: nil
        )

        addRecord(record)
        successCount += 1

        return record
    }

    /// 处理重做操作
    /// - Parameters:
    ///   - formatsBefore: 重做前的格式状态
    ///   - cursorPositionBefore: 重做前的光标位置
    /// - Returns: 处理结果
    func handleRedoOperation(
        formatsBefore: Set<TextFormat>,
        cursorPositionBefore: Int
    ) async -> UndoRedoOperationRecord {
        redoCount += 1

        // 1. 同步内容
        contentSyncCallback?()

        // 2. 等待重做操作完成
        try? await Task.sleep(nanoseconds: stateUpdateDelayMs * 1_000_000)

        // 3. 强制更新格式状态
        stateUpdateCallback?()

        // 4. 再次等待状态更新完成
        try? await Task.sleep(nanoseconds: stateUpdateDelayMs * 1_000_000)

        // 5. 获取重做后的状态（这里需要从外部获取，暂时使用空集合）
        let formatsAfter: Set<TextFormat> = []
        let cursorPositionAfter = 0

        // 6. 记录操作
        let record = UndoRedoOperationRecord(
            timestamp: Date(),
            operationType: .redo,
            formatsBefore: formatsBefore,
            formatsAfter: formatsAfter,
            cursorPositionBefore: cursorPositionBefore,
            cursorPositionAfter: cursorPositionAfter,
            success: true,
            errorMessage: nil
        )

        addRecord(record)
        successCount += 1

        return record
    }

    /// 处理撤销/重做操作（简化版本）
    /// - Parameter operationType: 操作类型
    func handleOperation(_ operationType: UndoRedoOperationType) {
        switch operationType {
        case .undo:
            undoCount += 1
        case .redo:
            redoCount += 1
        }

        // 1. 同步内容
        contentSyncCallback?()

        // 2. 延迟更新格式状态
        Task { @MainActor in
            // 等待操作完成
            try? await Task.sleep(nanoseconds: stateUpdateDelayMs * 1_000_000)

            // 强制更新格式状态
            self.stateUpdateCallback?()

            self.successCount += 1
        }
    }

    /// 获取统计信息
    /// - Returns: 统计信息字典
    func getStatistics() -> [String: Any] {
        [
            "undoCount": undoCount,
            "redoCount": redoCount,
            "totalCount": undoCount + redoCount,
            "successCount": successCount,
            "failureCount": failureCount,
            "recordCount": operationRecords.count,
        ]
    }

    /// 获取最近的操作记录
    /// - Parameter count: 记录数量
    /// - Returns: 操作记录数组
    func getRecentRecords(count: Int = 10) -> [UndoRedoOperationRecord] {
        let startIndex = max(0, operationRecords.count - count)
        return Array(operationRecords[startIndex...])
    }

    /// 重置统计信息
    func resetStatistics() {
        undoCount = 0
        redoCount = 0
        successCount = 0
        failureCount = 0
        operationRecords.removeAll()
    }

    /// 打印统计信息
    func printStatistics() {
        let stats = getStatistics()

        LogService.shared.debug(.editor, "[UndoRedoStateHandler] 统计信息:")
        LogService.shared.debug(.editor, "  - 撤销次数: \(stats["undoCount"] ?? 0)")
        LogService.shared.debug(.editor, "  - 重做次数: \(stats["redoCount"] ?? 0)")
        LogService.shared.debug(.editor, "  - 总操作次数: \(stats["totalCount"] ?? 0)")
        LogService.shared.debug(.editor, "  - 成功次数: \(stats["successCount"] ?? 0)")
        LogService.shared.debug(.editor, "  - 失败次数: \(stats["failureCount"] ?? 0)")
        LogService.shared.debug(.editor, "  - 记录数量: \(stats["recordCount"] ?? 0)")
    }

    // MARK: - Private Methods

    /// 添加操作记录
    private func addRecord(_ record: UndoRedoOperationRecord) {
        operationRecords.append(record)

        // 限制记录数量
        if operationRecords.count > maxRecordCount {
            operationRecords.removeFirst(operationRecords.count - maxRecordCount)
        }
    }
}

// MARK: - UndoRedoStateHandler Extension

extension UndoRedoStateHandler {

    /// 生成操作报告
    /// - Returns: 操作报告字符串
    func generateReport() -> String {
        let stats = getStatistics()
        let recentRecords = getRecentRecords(count: 5)

        var report = """
        ========================================
        撤销/重做操作报告
        ========================================

        ## 统计信息
        - 撤销次数: \(stats["undoCount"] ?? 0)
        - 重做次数: \(stats["redoCount"] ?? 0)
        - 总操作次数: \(stats["totalCount"] ?? 0)
        - 成功次数: \(stats["successCount"] ?? 0)
        - 失败次数: \(stats["failureCount"] ?? 0)

        ## 最近操作记录

        """

        if recentRecords.isEmpty {
            report += "暂无操作记录\n"
        } else {
            for (index, record) in recentRecords.enumerated() {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "HH:mm:ss"
                let timeString = dateFormatter.string(from: record.timestamp)

                report += """
                \(index + 1). [\(timeString)] \(record.operationType.rawValue)
                   - 格式变化: \(record.formatsChanged ? "是" : "否")
                   - 光标位置变化: \(record.cursorPositionChanged ? "是" : "否")
                   - 状态: \(record.success ? "成功" : "失败")

                """
            }
        }

        report += """

        ========================================
        """

        return report
    }
}
