//
//  FormatErrorHandler.swift
//  MiNoteMac
//
//  格式错误处理器 - 统一处理格式应用和状态同步相关的错误
//  需求: 4.1, 4.2
//

import Foundation
import AppKit
import Combine

// MARK: - 格式错误处理结果

/// 格式错误处理结果
struct FormatErrorHandlingResult {
    /// 错误
    let error: FormatError
    
    /// 是否已处理
    let handled: Bool
    
    /// 恢复操作
    let recoveryAction: FormatErrorRecoveryAction
    
    /// 用户消息
    let userMessage: String?
    
    /// 是否需要通知用户
    let shouldNotifyUser: Bool
    
    /// 创建已处理的结果
    static func handled(
        error: FormatError,
        action: FormatErrorRecoveryAction,
        message: String? = nil,
        notify: Bool = false
    ) -> FormatErrorHandlingResult {
        return FormatErrorHandlingResult(
            error: error,
            handled: true,
            recoveryAction: action,
            userMessage: message,
            shouldNotifyUser: notify
        )
    }
    
    /// 创建未处理的结果
    static func unhandled(
        error: FormatError,
        message: String
    ) -> FormatErrorHandlingResult {
        return FormatErrorHandlingResult(
            error: error,
            handled: false,
            recoveryAction: .none,
            userMessage: message,
            shouldNotifyUser: true
        )
    }
}

// MARK: - 格式错误处理器

/// 格式错误处理器
/// 
/// 统一处理格式应用和状态同步相关的错误，提供：
/// - 错误记录和历史管理
/// - 自动恢复机制
/// - 错误回调通知
/// - 性能监控
/// 
/// 需求: 4.1, 4.2
@MainActor
final class FormatErrorHandler {
    
    // MARK: - Singleton
    
    static let shared = FormatErrorHandler()
    
    // MARK: - Properties
    
    /// 错误日志记录器
    private let logger = NativeEditorLogger.shared
    
    /// 错误历史记录
    private var errorHistory: [FormatErrorRecord] = []
    
    /// 最大错误历史记录数
    private let maxErrorHistoryCount = 100
    
    /// 错误回调
    var onError: ((FormatError, FormatErrorHandlingResult) -> Void)?
    
    /// 是否启用自动恢复
    var enableAutoRecovery: Bool = true
    
    /// 连续错误计数（用于检测重复错误）
    private var consecutiveErrorCount: [Int: Int] = [:]
    
    /// 连续错误阈值（超过此值触发特殊处理）
    private let consecutiveErrorThreshold = 3
    
    /// 错误发布者
    private let errorSubject = PassthroughSubject<FormatErrorRecord, Never>()
    
    /// 错误发布者（公开）
    var errorPublisher: AnyPublisher<FormatErrorRecord, Never> {
        errorSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Error Handling
    
    /// 处理格式错误
    /// 
    /// - Parameters:
    ///   - error: 格式错误
    ///   - context: 错误上下文
    /// - Returns: 错误处理结果
    /// 
    /// 需求: 4.1 - 格式应用失败时记录错误日志并保持界面状态一致
    @discardableResult
    func handleError(_ error: FormatError, context: FormatErrorContext = .empty) -> FormatErrorHandlingResult {
        // 1. 记录错误
        let record = FormatErrorRecord(
            error: error,
            context: context,
            timestamp: Date(),
            handled: false,
            recoveryAction: nil
        )
        recordError(record)
        
        // 2. 记录日志
        logError(error, context: context)
        
        // 3. 检查连续错误
        let errorCode = error.errorCode
        consecutiveErrorCount[errorCode, default: 0] += 1
        
        // 4. 根据错误类型处理
        let result: FormatErrorHandlingResult
        
        if consecutiveErrorCount[errorCode]! >= consecutiveErrorThreshold {
            // 连续错误过多，触发特殊处理
            result = handleRepeatedError(error, context: context)
        } else if enableAutoRecovery && error.isRecoverable {
            result = performAutoRecovery(for: error, context: context)
        } else {
            result = FormatErrorHandlingResult.unhandled(
                error: error,
                message: error.localizedDescription ?? "未知错误"
            )
        }
        
        // 5. 更新记录
        updateErrorRecord(record, with: result)
        
        // 6. 触发回调
        onError?(error, result)
        
        // 7. 发布错误事件
        errorSubject.send(record)
        
        return result
    }
    
    /// 处理格式应用错误
    /// 
    /// - Parameters:
    ///   - format: 格式类型
    ///   - range: 应用范围
    ///   - textLength: 文本长度
    ///   - underlyingError: 底层错误
    /// - Returns: 错误处理结果
    /// 
    /// 需求: 4.1
    @discardableResult
    func handleFormatApplicationError(
        format: TextFormat,
        range: NSRange,
        textLength: Int,
        underlyingError: Error? = nil
    ) -> FormatErrorHandlingResult {
        let error = FormatError.formatApplicationFailed(
            format: format.displayName,
            reason: underlyingError?.localizedDescription ?? "未知原因"
        )
        
        let context = FormatErrorContext(
            operation: "applyFormat",
            format: format.displayName,
            selectedRange: range,
            textLength: textLength,
            cursorPosition: range.location,
            additionalInfo: underlyingError != nil ? ["underlyingError": underlyingError!] : nil
        )
        
        return handleError(error, context: context)
    }
    
    /// 处理状态同步错误
    /// 
    /// - Parameters:
    ///   - reason: 失败原因
    ///   - cursorPosition: 光标位置
    ///   - textLength: 文本长度
    /// - Returns: 错误处理结果
    /// 
    /// 需求: 4.2 - 状态同步失败时重新检测格式状态并更新界面
    @discardableResult
    func handleStateSyncError(
        reason: String,
        cursorPosition: Int,
        textLength: Int
    ) -> FormatErrorHandlingResult {
        let error = FormatError.stateSyncFailed(reason: reason)
        
        let context = FormatErrorContext(
            operation: "syncState",
            format: nil,
            selectedRange: nil,
            textLength: textLength,
            cursorPosition: cursorPosition,
            additionalInfo: nil
        )
        
        return handleError(error, context: context)
    }
    
    /// 处理范围错误
    /// 
    /// - Parameters:
    ///   - range: 无效范围
    ///   - textLength: 文本长度
    /// - Returns: 错误处理结果
    @discardableResult
    func handleRangeError(range: NSRange, textLength: Int) -> FormatErrorHandlingResult {
        let error: FormatError
        
        if range.location + range.length > textLength {
            error = .rangeOutOfBounds(range: range, textLength: textLength)
        } else {
            error = .invalidRange(range: range, textLength: textLength)
        }
        
        let context = FormatErrorContext(
            operation: "validateRange",
            format: nil,
            selectedRange: range,
            textLength: textLength,
            cursorPosition: range.location,
            additionalInfo: nil
        )
        
        return handleError(error, context: context)
    }
    
    // MARK: - Private Methods
    
    /// 处理重复错误
    private func handleRepeatedError(_ error: FormatError, context: FormatErrorContext) -> FormatErrorHandlingResult {
        logger.logWarning("[FormatErrorHandler] 检测到重复错误 [\(error.errorCode)]，已发生 \(consecutiveErrorCount[error.errorCode] ?? 0) 次")
        
        // 重置计数
        consecutiveErrorCount[error.errorCode] = 0
        
        // 对于重复错误，建议刷新编辑器
        return FormatErrorHandlingResult.handled(
            error: error,
            action: .refreshEditor,
            message: "检测到重复错误，建议刷新编辑器",
            notify: true
        )
    }
    
    /// 执行自动恢复
    /// 
    /// 需求: 4.1, 4.2
    private func performAutoRecovery(for error: FormatError, context: FormatErrorContext) -> FormatErrorHandlingResult {
        let action = error.suggestedRecovery
        
        switch action {
        case .adjustRange:
            logger.logInfo("[FormatErrorHandler] 执行范围调整恢复")
            return FormatErrorHandlingResult.handled(
                error: error,
                action: action,
                message: nil,
                notify: false
            )
            
        case .selectText:
            logger.logInfo("[FormatErrorHandler] 提示用户选择文本")
            return FormatErrorHandlingResult.handled(
                error: error,
                action: action,
                message: "请先选择要格式化的文本",
                notify: true
            )
            
        case .refreshEditor:
            logger.logInfo("[FormatErrorHandler] 执行编辑器刷新恢复")
            NotificationCenter.default.post(name: .nativeEditorNeedsRefresh, object: nil)
            return FormatErrorHandlingResult.handled(
                error: error,
                action: action,
                message: nil,
                notify: false
            )
            
        case .retryWithFallback:
            logger.logInfo("[FormatErrorHandler] 使用回退方案重试")
            return FormatErrorHandlingResult.handled(
                error: error,
                action: action,
                message: nil,
                notify: false
            )
            
        case .forceStateUpdate:
            logger.logInfo("[FormatErrorHandler] 强制更新格式状态")
            // 发送强制更新通知
            NotificationCenter.default.post(name: .formatStateNeedsForceUpdate, object: nil)
            return FormatErrorHandlingResult.handled(
                error: error,
                action: action,
                message: nil,
                notify: false
            )
            
        case .enableEditing:
            logger.logInfo("[FormatErrorHandler] 提示启用编辑模式")
            return FormatErrorHandlingResult.handled(
                error: error,
                action: action,
                message: "编辑器处于只读模式",
                notify: true
            )
            
        case .focusEditor:
            logger.logInfo("[FormatErrorHandler] 提示聚焦编辑器")
            return FormatErrorHandlingResult.handled(
                error: error,
                action: action,
                message: nil,
                notify: false
            )
            
        case .ignoreOperation, .none:
            return FormatErrorHandlingResult.handled(
                error: error,
                action: action,
                message: nil,
                notify: false
            )
        }
    }
    
    /// 记录错误日志
    private func logError(_ error: FormatError, context: FormatErrorContext) {
        // 使用 logError 方法记录 FormatError（它遵循 Error 协议）
        logger.logError(error, context: context.description, category: "FormatError")
    }
    
    // MARK: - Error Recording
    
    /// 记录错误
    private func recordError(_ record: FormatErrorRecord) {
        errorHistory.append(record)
        
        // 限制历史记录数量
        if errorHistory.count > maxErrorHistoryCount {
            errorHistory.removeFirst(errorHistory.count - maxErrorHistoryCount)
        }
    }
    
    /// 更新错误记录
    private func updateErrorRecord(_ record: FormatErrorRecord, with result: FormatErrorHandlingResult) {
        if let index = errorHistory.firstIndex(where: { $0.timestamp == record.timestamp }) {
            errorHistory[index].handled = result.handled
            errorHistory[index].recoveryAction = result.recoveryAction
        }
    }
    
    /// 获取错误历史
    func getErrorHistory() -> [FormatErrorRecord] {
        return errorHistory
    }
    
    /// 清除错误历史
    func clearErrorHistory() {
        errorHistory.removeAll()
        consecutiveErrorCount.removeAll()
    }
    
    /// 获取最近的错误
    func getRecentErrors(count: Int = 10) -> [FormatErrorRecord] {
        return Array(errorHistory.suffix(count))
    }
    
    /// 重置错误计数
    func resetErrorCount(for errorCode: Int? = nil) {
        if let code = errorCode {
            consecutiveErrorCount[code] = 0
        } else {
            consecutiveErrorCount.removeAll()
        }
    }
    
    // MARK: - Error Statistics
    
    /// 获取错误统计信息
    func getErrorStatistics() -> [String: Any] {
        let totalErrors = errorHistory.count
        let handledErrors = errorHistory.filter { $0.handled }.count
        let unhandledErrors = totalErrors - handledErrors
        
        // 按错误代码分组统计
        let errorCounts = Dictionary(grouping: errorHistory) { $0.error.errorCode }
            .mapValues { $0.count }
        
        // 按恢复操作分组统计
        let recoveryActionCounts = Dictionary(grouping: errorHistory.compactMap { $0.recoveryAction }) { $0 }
            .mapValues { $0.count }
        
        return [
            "totalErrors": totalErrors,
            "handledErrors": handledErrors,
            "unhandledErrors": unhandledErrors,
            "errorsByCode": errorCounts,
            "recoveryActions": recoveryActionCounts,
            "consecutiveErrorCounts": consecutiveErrorCount
        ]
    }
    
    /// 打印错误统计信息
    func printErrorStatistics() {
        let stats = getErrorStatistics()
        print("""
        [FormatErrorHandler] 错误统计
          - 总错误数: \(stats["totalErrors"] ?? 0)
          - 已处理: \(stats["handledErrors"] ?? 0)
          - 未处理: \(stats["unhandledErrors"] ?? 0)
          - 按错误代码: \(stats["errorsByCode"] ?? [:])
          - 恢复操作: \(stats["recoveryActions"] ?? [:])
        """)
    }
}

// MARK: - 通知名称扩展

extension Notification.Name {
    /// 格式状态需要强制更新
    static let formatStateNeedsForceUpdate = Notification.Name("formatStateNeedsForceUpdate")
    
    /// 格式错误发生
    static let formatErrorOccurred = Notification.Name("formatErrorOccurred")
}
