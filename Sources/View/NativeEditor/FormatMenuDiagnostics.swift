//
//  FormatMenuDiagnostics.swift
//  MiNoteMac
//
//  格式菜单诊断工具 - 收集和分析格式菜单问题的诊断信息
//  需求: 8.4
//

import Foundation
import AppKit

// MARK: - 诊断信息类型

/// 诊断信息类型
enum DiagnosticInfoType: String {
    case editorState = "编辑器状态"
    case textStorage = "文本存储"
    case formatState = "格式状态"
    case cursorPosition = "光标位置"
    case selectedRange = "选择范围"
    case attributes = "文本属性"
    case performance = "性能数据"
    case errorHistory = "错误历史"
}

// MARK: - 诊断快照

/// 格式菜单诊断快照
/// 捕获特定时刻的完整状态信息
struct FormatMenuDiagnosticSnapshot {
    let timestamp: Date
    let editorState: EditorStateInfo
    let textStorageInfo: TextStorageInfo
    let formatState: FormatStateInfo
    let cursorInfo: CursorInfo
    let performanceInfo: PerformanceInfo
    let errorHistory: [String]
    
    /// 编辑器状态信息
    struct EditorStateInfo {
        let isEditorFocused: Bool
        let hasUnsavedChanges: Bool
        let textLength: Int
        let isEmpty: Bool
    }
    
    /// 文本存储信息
    struct TextStorageInfo {
        let length: Int
        let string: String
        let attributeCount: Int
        let hasAttachments: Bool
    }
    
    /// 格式状态信息
    struct FormatStateInfo {
        let currentFormats: Set<TextFormat>
        let toolbarButtonStates: [TextFormat: Bool]
        let specialElement: String?
    }
    
    /// 光标信息
    struct CursorInfo {
        let position: Int
        let selectedRange: NSRange
        let hasSelection: Bool
        let attributesAtCursor: [String: Any]
    }
    
    /// 性能信息
    struct PerformanceInfo {
        let avgApplicationTimeMs: Double
        let avgSynchronizationTimeMs: Double
        let slowOperationsCount: Int
        let totalOperations: Int
    }
    
    /// 生成摘要
    func generateSummary() -> String {
        var summary = """
        ========================================
        格式菜单诊断快照
        时间: \(ISO8601DateFormatter().string(from: timestamp))
        ========================================
        
        ## 编辑器状态
        - 焦点状态: \(editorState.isEditorFocused ? "已获得" : "未获得")
        - 未保存更改: \(editorState.hasUnsavedChanges ? "是" : "否")
        - 文本长度: \(editorState.textLength)
        - 是否为空: \(editorState.isEmpty ? "是" : "否")
        
        ## 文本存储
        - 长度: \(textStorageInfo.length)
        - 属性数量: \(textStorageInfo.attributeCount)
        - 包含附件: \(textStorageInfo.hasAttachments ? "是" : "否")
        - 文本预览: \(String(textStorageInfo.string.prefix(100)))
        
        ## 格式状态
        - 当前激活格式: \(formatState.currentFormats.map { $0.displayName }.joined(separator: ", "))
        - 特殊元素: \(formatState.specialElement ?? "无")
        
        ## 光标信息
        - 位置: \(cursorInfo.position)
        - 选择范围: \(NSStringFromRange(cursorInfo.selectedRange))
        - 有选择: \(cursorInfo.hasSelection ? "是" : "否")
        - 光标处属性数量: \(cursorInfo.attributesAtCursor.count)
        
        ## 性能信息
        - 平均应用时间: \(String(format: "%.2f", performanceInfo.avgApplicationTimeMs))ms
        - 平均同步时间: \(String(format: "%.2f", performanceInfo.avgSynchronizationTimeMs))ms
        - 慢速操作: \(performanceInfo.slowOperationsCount) / \(performanceInfo.totalOperations)
        
        """
        
        if !errorHistory.isEmpty {
            summary += """
            
            ## 最近错误
            
            """
            for error in errorHistory.prefix(5) {
                summary += "- \(error)\n"
            }
        }
        
        summary += """
        
        ========================================
        """
        
        return summary
    }
}

// MARK: - 格式菜单诊断工具

/// 格式菜单诊断工具
/// 收集和分析格式菜单问题的诊断信息
@MainActor
final class FormatMenuDiagnostics {
    
    // MARK: - Singleton
    
    static let shared = FormatMenuDiagnostics()
    
    // MARK: - Properties
    
    /// 日志记录器
    private let logger = NativeEditorLogger.shared
    
    /// 调试器
    private let debugger = FormatMenuDebugger.shared
    
    /// 性能监控器
    private let performanceMonitor = FormatMenuPerformanceMonitor.shared
    
    /// 诊断快照历史
    private var snapshots: [FormatMenuDiagnosticSnapshot] = []
    
    /// 最大快照数
    private let maxSnapshots = 50
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Snapshot Capture
    
    /// 捕获当前状态的诊断快照
    /// - Parameters:
    ///   - context: 编辑器上下文
    ///   - textView: 文本视图（可选）
    /// - Returns: 诊断快照
    func captureSnapshot(
        context: NativeEditorContext,
        textView: NSTextView? = nil
    ) -> FormatMenuDiagnosticSnapshot {
        // 编辑器状态
        let editorState = FormatMenuDiagnosticSnapshot.EditorStateInfo(
            isEditorFocused: context.isEditorFocused,
            hasUnsavedChanges: context.hasUnsavedChanges,
            textLength: context.nsAttributedText.length,
            isEmpty: context.nsAttributedText.string.isEmpty
        )
        
        // 文本存储信息
        let textStorage = textView?.textStorage ?? context.nsAttributedText.mutableCopy() as? NSMutableAttributedString ?? NSMutableAttributedString()
        var attributeCount = 0
        var hasAttachments = false
        
        textStorage.enumerateAttributes(in: NSRange(location: 0, length: textStorage.length), options: []) { attrs, _, _ in
            attributeCount += attrs.count
            if attrs[.attachment] != nil {
                hasAttachments = true
            }
        }
        
        let textStorageInfo = FormatMenuDiagnosticSnapshot.TextStorageInfo(
            length: textStorage.length,
            string: textStorage.string,
            attributeCount: attributeCount,
            hasAttachments: hasAttachments
        )
        
        // 格式状态
        let formatState = FormatMenuDiagnosticSnapshot.FormatStateInfo(
            currentFormats: context.currentFormats,
            toolbarButtonStates: context.toolbarButtonStates,
            specialElement: context.currentSpecialElement?.displayName
        )
        
        // 光标信息
        let position = context.cursorPosition
        let selectedRange = context.selectedRange
        var attributesAtCursor: [String: Any] = [:]
        
        if position < textStorage.length {
            let attrs = textStorage.attributes(at: position, effectiveRange: nil)
            for (key, value) in attrs {
                attributesAtCursor[key.rawValue] = value
            }
        }
        
        let cursorInfo = FormatMenuDiagnosticSnapshot.CursorInfo(
            position: position,
            selectedRange: selectedRange,
            hasSelection: selectedRange.length > 0,
            attributesAtCursor: attributesAtCursor
        )
        
        // 性能信息
        let stats = debugger.statistics
        let performanceInfo = FormatMenuDiagnosticSnapshot.PerformanceInfo(
            avgApplicationTimeMs: stats.avgApplicationTimeMs,
            avgSynchronizationTimeMs: stats.avgSynchronizationTimeMs,
            slowOperationsCount: stats.slowApplications + stats.slowSynchronizations,
            totalOperations: stats.totalApplications + stats.totalSynchronizations
        )
        
        // 错误历史
        let errorHistory = debugger.getEvents(type: .error)
            .suffix(10)
            .map { $0.message }
        
        // 创建快照
        let snapshot = FormatMenuDiagnosticSnapshot(
            timestamp: Date(),
            editorState: editorState,
            textStorageInfo: textStorageInfo,
            formatState: formatState,
            cursorInfo: cursorInfo,
            performanceInfo: performanceInfo,
            errorHistory: errorHistory
        )
        
        // 保存快照
        snapshots.append(snapshot)
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst(snapshots.count - maxSnapshots)
        }
        
        logger.logDebug("已捕获格式菜单诊断快照", category: "FormatMenuDiagnostics")
        
        return snapshot
    }
    
    // MARK: - Diagnostic Analysis
    
    /// 分析格式应用问题
    /// - Parameters:
    ///   - format: 格式类型
    ///   - context: 编辑器上下文
    ///   - textView: 文本视图
    /// - Returns: 诊断结果
    func diagnoseFormatApplication(
        format: TextFormat,
        context: NativeEditorContext,
        textView: NSTextView
    ) -> DiagnosticResult {
        var issues: [String] = []
        var suggestions: [String] = []
        
        // 检查编辑器状态
        if !context.isEditorFocused {
            issues.append("编辑器未获得焦点")
            suggestions.append("确保编辑器已获得焦点")
        }
        
        // 检查文本存储
        guard let textStorage = textView.textStorage else {
            issues.append("文本存储不可用")
            suggestions.append("检查 NSTextView 的 textStorage 是否正确初始化")
            return DiagnosticResult(
                type: .formatApplication,
                format: format,
                issues: issues,
                suggestions: suggestions,
                severity: .critical
            )
        }
        
        // 检查选择范围
        let selectedRange = textView.selectedRange()
        if selectedRange.length == 0 && !format.isBlockFormat {
            issues.append("没有选中文本，且格式不是块级格式")
            suggestions.append("选中要应用格式的文本")
        }
        
        if selectedRange.location + selectedRange.length > textStorage.length {
            issues.append("选择范围超出文本长度")
            suggestions.append("检查选择范围的有效性")
        }
        
        // 检查格式管理器
        let formatManager = FormatManager.shared
        if selectedRange.length > 0 {
            let isActive = formatManager.isFormatActive(format, in: textStorage, at: selectedRange.location)
            if isActive {
                suggestions.append("格式已激活，点击将移除格式")
            } else {
                suggestions.append("格式未激活，点击将应用格式")
            }
        }
        
        // 检查性能
        let recentRecords = debugger.getApplicationRecords(for: format)
        if !recentRecords.isEmpty {
            let failedCount = recentRecords.filter { !$0.success }.count
            if failedCount > 0 {
                issues.append("最近 \(recentRecords.count) 次应用中有 \(failedCount) 次失败")
                suggestions.append("查看错误日志了解失败原因")
            }
            
            let avgDuration = recentRecords.map { $0.duration }.reduce(0, +) / Double(recentRecords.count)
            if avgDuration > performanceMonitor.thresholds.formatApplication {
                issues.append("平均应用时间 (\(String(format: "%.2f", avgDuration * 1000))ms) 超过阈值")
                suggestions.append("优化格式应用逻辑")
            }
        }
        
        let severity: DiagnosticSeverity = issues.isEmpty ? .info : (issues.count > 2 ? .error : .warning)
        
        return DiagnosticResult(
            type: .formatApplication,
            format: format,
            issues: issues,
            suggestions: suggestions,
            severity: severity
        )
    }
    
    /// 分析状态同步问题
    /// - Parameters:
    ///   - context: 编辑器上下文
    ///   - textView: 文本视图
    /// - Returns: 诊断结果
    func diagnoseStateSynchronization(
        context: NativeEditorContext,
        textView: NSTextView
    ) -> DiagnosticResult {
        var issues: [String] = []
        var suggestions: [String] = []
        
        // 检查文本存储
        guard let textStorage = textView.textStorage else {
            issues.append("文本存储不可用")
            suggestions.append("检查 NSTextView 的 textStorage 是否正确初始化")
            return DiagnosticResult(
                type: .stateSynchronization,
                format: nil,
                issues: issues,
                suggestions: suggestions,
                severity: .critical
            )
        }
        
        // 检查光标位置
        let cursorPosition = context.cursorPosition
        if cursorPosition > textStorage.length {
            issues.append("光标位置超出文本长度")
            suggestions.append("更新光标位置到有效范围")
        }
        
        // 检查格式状态一致性
        if cursorPosition < textStorage.length {
            let formatManager = FormatManager.shared
            var inconsistencies: [TextFormat] = []
            
            for format in TextFormat.allCases {
                let isActiveInContext = context.currentFormats.contains(format)
                let isActiveInStorage = formatManager.isFormatActive(format, in: textStorage, at: cursorPosition)
                
                if isActiveInContext != isActiveInStorage {
                    inconsistencies.append(format)
                }
            }
            
            if !inconsistencies.isEmpty {
                issues.append("检测到 \(inconsistencies.count) 个格式状态不一致")
                suggestions.append("不一致的格式: \(inconsistencies.map { $0.displayName }.joined(separator: ", "))")
                suggestions.append("调用 updateCurrentFormats() 重新同步状态")
            }
        }
        
        // 检查性能
        let recentRecords = debugger.getRecentSynchronizationRecords(count: 10)
        if !recentRecords.isEmpty {
            let avgDuration = recentRecords.map { $0.duration }.reduce(0, +) / Double(recentRecords.count)
            if avgDuration > performanceMonitor.thresholds.stateSynchronization {
                issues.append("平均同步时间 (\(String(format: "%.2f", avgDuration * 1000))ms) 超过阈值")
                suggestions.append("优化状态检测算法")
            }
        }
        
        let severity: DiagnosticSeverity = issues.isEmpty ? .info : (issues.count > 2 ? .error : .warning)
        
        return DiagnosticResult(
            type: .stateSynchronization,
            format: nil,
            issues: issues,
            suggestions: suggestions,
            severity: severity
        )
    }
    
    /// 生成完整诊断报告
    /// - Parameters:
    ///   - context: 编辑器上下文
    ///   - textView: 文本视图
    /// - Returns: 诊断报告
    func generateFullDiagnosticReport(
        context: NativeEditorContext,
        textView: NSTextView
    ) -> String {
        // 捕获快照
        let snapshot = captureSnapshot(context: context, textView: textView)
        
        var report = snapshot.generateSummary()
        
        // 添加状态同步诊断
        let syncDiagnostic = diagnoseStateSynchronization(context: context, textView: textView)
        report += """
        
        ## 状态同步诊断
        严重程度: \(syncDiagnostic.severity.rawValue)
        
        """
        
        if !syncDiagnostic.issues.isEmpty {
            report += "问题:\n"
            for issue in syncDiagnostic.issues {
                report += "- \(issue)\n"
            }
        }
        
        if !syncDiagnostic.suggestions.isEmpty {
            report += "\n建议:\n"
            for suggestion in syncDiagnostic.suggestions {
                report += "- \(suggestion)\n"
            }
        }
        
        // 添加性能分析
        report += """
        
        ## 性能分析
        \(performanceMonitor.getPerformanceSummary())
        
        """
        
        return report
    }
    
    // MARK: - Snapshot Management
    
    /// 获取所有快照
    func getAllSnapshots() -> [FormatMenuDiagnosticSnapshot] {
        return snapshots
    }
    
    /// 获取最近的快照
    func getRecentSnapshots(count: Int = 10) -> [FormatMenuDiagnosticSnapshot] {
        return Array(snapshots.suffix(count))
    }
    
    /// 清除所有快照
    func clearSnapshots() {
        snapshots.removeAll()
        logger.logInfo("已清除所有诊断快照", category: "FormatMenuDiagnostics")
    }
    
    // MARK: - Export
    
    /// 导出诊断报告
    func exportDiagnosticReport(
        context: NativeEditorContext,
        textView: NSTextView,
        to url: URL
    ) throws {
        let report = generateFullDiagnosticReport(context: context, textView: textView)
        try report.write(to: url, atomically: true, encoding: .utf8)
        logger.logInfo("诊断报告已导出到: \(url.path)", category: "FormatMenuDiagnostics")
    }
}

// MARK: - 诊断结果

/// 诊断结果
struct DiagnosticResult {
    let type: DiagnosticInfoType
    let format: TextFormat?
    let issues: [String]
    let suggestions: [String]
    let severity: DiagnosticSeverity
    
    var summary: String {
        var result = """
        诊断类型: \(type.rawValue)
        严重程度: \(severity.rawValue)
        
        """
        
        if let format = format {
            result += "格式: \(format.displayName)\n\n"
        }
        
        if !issues.isEmpty {
            result += "问题:\n"
            for issue in issues {
                result += "- \(issue)\n"
            }
            result += "\n"
        }
        
        if !suggestions.isEmpty {
            result += "建议:\n"
            for suggestion in suggestions {
                result += "- \(suggestion)\n"
            }
        }
        
        return result
    }
}

/// 诊断严重程度
enum DiagnosticSeverity: String {
    case info = "信息"
    case warning = "警告"
    case error = "错误"
    case critical = "严重"
}
