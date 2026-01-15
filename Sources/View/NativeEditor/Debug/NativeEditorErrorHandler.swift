//
//  NativeEditorErrorHandler.swift
//  MiNoteMac
//
//  原生编辑器错误处理器 - 统一处理编辑器相关的错误

import Foundation
import AppKit
import os.log

// MARK: - 编辑器错误类型

/// 原生编辑器错误类型
enum NativeEditorError: Error, LocalizedError {
    // 初始化错误
    case initializationFailed(reason: String)
    case systemVersionNotSupported(required: String, current: String)
    case frameworkNotAvailable(framework: String)
    
    // 渲染错误
    case renderingFailed(element: String, reason: String)
    case attachmentCreationFailed(type: String)
    case layoutManagerError(reason: String)
    
    // 格式转换错误
    case xmlParsingFailed(xml: String, reason: String)
    case attributedStringConversionFailed(reason: String)
    case unsupportedXMLElement(element: String)
    case invalidXMLStructure(details: String)
    
    // 内容错误
    case contentLoadFailed(reason: String)
    case contentSaveFailed(reason: String)
    case imageLoadFailed(fileId: String?, reason: String)
    
    // 状态错误
    case invalidEditorState(state: String)
    case contextSyncFailed(reason: String)
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed(let reason):
            return "编辑器初始化失败: \(reason)"
        case .systemVersionNotSupported(let required, let current):
            return "系统版本不支持: 需要 \(required)，当前 \(current)"
        case .frameworkNotAvailable(let framework):
            return "框架不可用: \(framework)"
        case .renderingFailed(let element, let reason):
            return "渲染失败 [\(element)]: \(reason)"
        case .attachmentCreationFailed(let type):
            return "附件创建失败: \(type)"
        case .layoutManagerError(let reason):
            return "布局管理器错误: \(reason)"
        case .xmlParsingFailed(_, let reason):
            return "XML 解析失败: \(reason)"
        case .attributedStringConversionFailed(let reason):
            return "AttributedString 转换失败: \(reason)"
        case .unsupportedXMLElement(let element):
            return "不支持的 XML 元素: \(element)"
        case .invalidXMLStructure(let details):
            return "无效的 XML 结构: \(details)"
        case .contentLoadFailed(let reason):
            return "内容加载失败: \(reason)"
        case .contentSaveFailed(let reason):
            return "内容保存失败: \(reason)"
        case .imageLoadFailed(let fileId, let reason):
            return "图片加载失败 [\(fileId ?? "unknown")]: \(reason)"
        case .invalidEditorState(let state):
            return "无效的编辑器状态: \(state)"
        case .contextSyncFailed(let reason):
            return "上下文同步失败: \(reason)"
        }
    }
    
    /// 错误代码
    var errorCode: Int {
        switch self {
        case .initializationFailed: return 1001
        case .systemVersionNotSupported: return 1002
        case .frameworkNotAvailable: return 1003
        case .renderingFailed: return 2001
        case .attachmentCreationFailed: return 2002
        case .layoutManagerError: return 2003
        case .xmlParsingFailed: return 3001
        case .attributedStringConversionFailed: return 3002
        case .unsupportedXMLElement: return 3003
        case .invalidXMLStructure: return 3004
        case .contentLoadFailed: return 4001
        case .contentSaveFailed: return 4002
        case .imageLoadFailed: return 4003
        case .invalidEditorState: return 5001
        case .contextSyncFailed: return 5002
        }
    }
    
    /// 是否可恢复
    var isRecoverable: Bool {
        switch self {
        case .initializationFailed, .systemVersionNotSupported, .frameworkNotAvailable:
            return false
        case .renderingFailed, .attachmentCreationFailed, .layoutManagerError:
            return true
        case .xmlParsingFailed, .attributedStringConversionFailed, .unsupportedXMLElement, .invalidXMLStructure:
            return true
        case .contentLoadFailed, .contentSaveFailed, .imageLoadFailed:
            return true
        case .invalidEditorState, .contextSyncFailed:
            return true
        }
    }
    
    /// 建议的恢复操作
    var suggestedRecovery: ErrorRecoveryAction {
        switch self {
        case .initializationFailed, .systemVersionNotSupported, .frameworkNotAvailable:
            return .switchToWebEditor
        case .renderingFailed, .attachmentCreationFailed:
            return .useFallbackRendering
        case .layoutManagerError:
            return .refreshEditor
        case .xmlParsingFailed, .attributedStringConversionFailed, .unsupportedXMLElement, .invalidXMLStructure:
            return .preserveOriginalContent
        case .contentLoadFailed:
            return .retryLoad
        case .contentSaveFailed:
            return .retrySave
        case .imageLoadFailed:
            return .showPlaceholder
        case .invalidEditorState, .contextSyncFailed:
            return .refreshEditor
        }
    }
}

/// 错误恢复操作
enum ErrorRecoveryAction {
    case switchToWebEditor      // 切换到 Web 编辑器
    case useFallbackRendering   // 使用回退渲染
    case refreshEditor          // 刷新编辑器
    case preserveOriginalContent // 保留原始内容
    case retryLoad              // 重试加载
    case retrySave              // 重试保存
    case showPlaceholder        // 显示占位符
    case none                   // 无操作
    
    var description: String {
        switch self {
        case .switchToWebEditor:
            return "切换到 Web 编辑器"
        case .useFallbackRendering:
            return "使用基础文本显示"
        case .refreshEditor:
            return "刷新编辑器"
        case .preserveOriginalContent:
            return "保留原始内容"
        case .retryLoad:
            return "重试加载"
        case .retrySave:
            return "重试保存"
        case .showPlaceholder:
            return "显示占位符"
        case .none:
            return "无操作"
        }
    }
}

// MARK: - 错误处理结果

/// 错误处理结果
struct ErrorHandlingResult {
    let error: NativeEditorError
    let handled: Bool
    let recoveryAction: ErrorRecoveryAction
    let userMessage: String?
    let shouldNotifyUser: Bool
    
    static func handled(error: NativeEditorError, action: ErrorRecoveryAction, message: String? = nil, notify: Bool = false) -> ErrorHandlingResult {
        return ErrorHandlingResult(
            error: error,
            handled: true,
            recoveryAction: action,
            userMessage: message,
            shouldNotifyUser: notify
        )
    }
    
    static func unhandled(error: NativeEditorError, message: String) -> ErrorHandlingResult {
        return ErrorHandlingResult(
            error: error,
            handled: false,
            recoveryAction: .none,
            userMessage: message,
            shouldNotifyUser: true
        )
    }
}

// MARK: - 原生编辑器错误处理器

/// 原生编辑器错误处理器
/// 统一处理编辑器相关的错误，提供错误恢复和用户通知
@MainActor
final class NativeEditorErrorHandler {
    
    // MARK: - Singleton
    
    static let shared = NativeEditorErrorHandler()
    
    // MARK: - Properties
    
    /// 错误日志记录器
    private let logger = NativeEditorLogger.shared
    
    /// 错误历史记录
    private var errorHistory: [ErrorRecord] = []
    
    /// 最大错误历史记录数
    private let maxErrorHistoryCount = 100
    
    /// 错误回调
    var onError: ((NativeEditorError, ErrorHandlingResult) -> Void)?
    
    /// 是否启用自动恢复
    var enableAutoRecovery: Bool = true
    
    /// 连续错误计数（用于检测重复错误）
    private var consecutiveErrorCount: [Int: Int] = [:]
    
    /// 连续错误阈值（超过此值触发特殊处理）
    private let consecutiveErrorThreshold = 3
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Error Handling
    
    /// 处理错误
    /// - Parameters:
    ///   - error: 错误
    ///   - context: 错误上下文
    /// - Returns: 错误处理结果
    @discardableResult
    func handleError(_ error: NativeEditorError, context: String = "") -> ErrorHandlingResult {
        // 记录错误
        let record = ErrorRecord(
            error: error,
            context: context,
            timestamp: Date()
        )
        recordError(record)
        
        // 记录日志
        logger.logError(error, context: context)
        
        // 检查连续错误
        let errorCode = error.errorCode
        consecutiveErrorCount[errorCode, default: 0] += 1
        
        if consecutiveErrorCount[errorCode]! >= consecutiveErrorThreshold {
            // 连续错误过多，触发特殊处理
            return handleRepeatedError(error, context: context)
        }
        
        // 根据错误类型处理
        let result: ErrorHandlingResult
        
        if enableAutoRecovery && error.isRecoverable {
            result = performAutoRecovery(for: error, context: context)
        } else {
            result = ErrorHandlingResult.unhandled(
                error: error,
                message: error.localizedDescription
            )
        }
        
        // 触发回调
        onError?(error, result)
        
        return result
    }
    
    /// 处理重复错误
    private func handleRepeatedError(_ error: NativeEditorError, context: String) -> ErrorHandlingResult {
        logger.logWarning("检测到重复错误 [\(error.errorCode)]，已发生 \(consecutiveErrorCount[error.errorCode] ?? 0) 次")
        
        // 重置计数
        consecutiveErrorCount[error.errorCode] = 0
        
        // 对于重复错误，建议切换到 Web 编辑器
        return ErrorHandlingResult.handled(
            error: error,
            action: .switchToWebEditor,
            message: "检测到重复错误，建议切换到 Web 编辑器",
            notify: true
        )
    }
    
    /// 执行自动恢复
    private func performAutoRecovery(for error: NativeEditorError, context: String) -> ErrorHandlingResult {
        let action = error.suggestedRecovery
        
        switch action {
        case .useFallbackRendering:
            logger.logInfo("执行回退渲染恢复")
            return ErrorHandlingResult.handled(
                error: error,
                action: action,
                message: nil,
                notify: false
            )
            
        case .refreshEditor:
            logger.logInfo("执行编辑器刷新恢复")
            NotificationCenter.default.post(name: .nativeEditorNeedsRefresh, object: nil)
            return ErrorHandlingResult.handled(
                error: error,
                action: action,
                message: nil,
                notify: false
            )
            
        case .preserveOriginalContent:
            logger.logInfo("保留原始内容")
            return ErrorHandlingResult.handled(
                error: error,
                action: action,
                message: "格式转换出现问题，已保留原始内容",
                notify: true
            )
            
        case .showPlaceholder:
            logger.logInfo("显示占位符")
            return ErrorHandlingResult.handled(
                error: error,
                action: action,
                message: nil,
                notify: false
            )
            
        case .switchToWebEditor:
            logger.logWarning("建议切换到 Web 编辑器")
            return ErrorHandlingResult.handled(
                error: error,
                action: action,
                message: "原生编辑器遇到问题，建议切换到 Web 编辑器",
                notify: true
            )
            
        default:
            return ErrorHandlingResult.handled(
                error: error,
                action: action,
                message: nil,
                notify: false
            )
        }
    }
    
    /// 重置错误计数
    func resetErrorCount(for errorCode: Int? = nil) {
        if let code = errorCode {
            consecutiveErrorCount[code] = 0
        } else {
            consecutiveErrorCount.removeAll()
        }
    }
    
    // MARK: - Error Recording
    
    /// 记录错误
    private func recordError(_ record: ErrorRecord) {
        errorHistory.append(record)
        
        // 限制历史记录数量
        if errorHistory.count > maxErrorHistoryCount {
            errorHistory.removeFirst(errorHistory.count - maxErrorHistoryCount)
        }
    }
    
    /// 获取错误历史
    func getErrorHistory() -> [ErrorRecord] {
        return errorHistory
    }
    
    /// 清除错误历史
    func clearErrorHistory() {
        errorHistory.removeAll()
        consecutiveErrorCount.removeAll()
    }
    
    /// 获取最近的错误
    func getRecentErrors(count: Int = 10) -> [ErrorRecord] {
        return Array(errorHistory.suffix(count))
    }
    
    // MARK: - Error Report Generation
    
    /// 生成错误报告
    /// - Returns: 错误报告字符串
    func generateErrorReport() -> String {
        var report = """
        ========================================
        原生编辑器错误报告
        生成时间: \(ISO8601DateFormatter().string(from: Date()))
        ========================================
        
        """
        
        // 系统信息
        report += """
        
        ## 系统信息
        - macOS 版本: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - 应用版本: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")
        - 构建版本: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知")
        
        """
        
        // 错误统计
        let errorCounts = Dictionary(grouping: errorHistory) { $0.error.errorCode }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        report += """
        
        ## 错误统计
        总错误数: \(errorHistory.count)
        
        """
        
        for (code, count) in errorCounts.prefix(10) {
            report += "- 错误代码 \(code): \(count) 次\n"
        }
        
        // 最近错误详情
        report += """
        
        ## 最近错误详情
        
        """
        
        for record in errorHistory.suffix(20).reversed() {
            report += """
            ---
            时间: \(ISO8601DateFormatter().string(from: record.timestamp))
            错误: \(record.error.localizedDescription ?? "未知错误")
            代码: \(record.error.errorCode)
            上下文: \(record.context.isEmpty ? "无" : record.context)
            
            """
        }
        
        // 性能指标
        let metrics = NativeEditorMetrics.shared.getMetricsSummary()
        report += """
        
        ## 性能指标
        \(metrics)
        
        """
        
        report += """
        
        ========================================
        报告结束
        ========================================
        """
        
        return report
    }
    
    /// 导出错误报告到文件
    /// - Parameter url: 文件 URL
    /// - Throws: 写入错误
    func exportErrorReport(to url: URL) throws {
        let report = generateErrorReport()
        try report.write(to: url, atomically: true, encoding: .utf8)
        logger.logInfo("错误报告已导出到: \(url.path)")
    }
}

// MARK: - 错误记录

/// 错误记录
struct ErrorRecord {
    let error: NativeEditorError
    let context: String
    let timestamp: Date
    
    var description: String {
        return "[\(timestamp)] \(error.localizedDescription ?? "未知错误") - \(context)"
    }
}

// MARK: - 通知名称扩展

extension Notification.Name {
    /// 编辑器需要刷新
    static let nativeEditorNeedsRefresh = Notification.Name("nativeEditorNeedsRefresh")
    
    /// 编辑器错误发生
    static let nativeEditorErrorOccurred = Notification.Name("nativeEditorErrorOccurred")
    
    /// 建议切换编辑器
    static let suggestSwitchEditor = Notification.Name("suggestSwitchEditor")
}
