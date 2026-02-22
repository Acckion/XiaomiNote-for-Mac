//
//  FormatMenuDiagnostics.swift
//  MiNoteMac
//
//  格式菜单诊断工具 - 收集和分析格式菜单问题的诊断信息
//

import AppKit
import Foundation

// MARK: - 诊断信息类型

/// 诊断信息类型
enum DiagnosticInfoType: String, CaseIterable {
    case editorState = "编辑器状态"
    case textStorage = "文本存储"
    case formatState = "格式状态"
    case cursorPosition = "光标位置"
    case selectedRange = "选择范围"
    case attributes = "文本属性"
    case performance = "性能数据"
    case errorHistory = "错误历史"
    case formatApplication = "格式应用"
    case stateSynchronization = "状态同步"
    case systemInfo = "系统信息"
    case memoryUsage = "内存使用"
    case undoHistory = "撤销历史"
}

// MARK: - 问题类型

/// 格式菜单问题类型
enum FormatMenuProblemType: String, CaseIterable {
    case formatNotApplied = "格式未应用"
    case stateNotSynchronized = "状态未同步"
    case performanceSlow = "性能缓慢"
    case unexpectedBehavior = "意外行为"
    case uiNotResponding = "界面无响应"
    case inconsistentState = "状态不一致"
    case undoRedoIssue = "撤销/重做问题"
    case keyboardShortcutIssue = "快捷键问题"
    case specialElementIssue = "特殊元素问题"
    case mixedFormatIssue = "混合格式问题"

    var displayName: String {
        rawValue
    }

    var description: String {
        switch self {
        case .formatNotApplied:
            "点击格式按钮后，格式没有正确应用到选中的文本"
        case .stateNotSynchronized:
            "格式菜单按钮状态与实际文本格式不一致"
        case .performanceSlow:
            "格式操作响应缓慢，超过预期时间"
        case .unexpectedBehavior:
            "格式操作产生了意外的结果"
        case .uiNotResponding:
            "格式菜单界面无响应或卡顿"
        case .inconsistentState:
            "编辑器内部状态不一致"
        case .undoRedoIssue:
            "撤销或重做操作后格式状态不正确"
        case .keyboardShortcutIssue:
            "快捷键操作与菜单操作结果不一致"
        case .specialElementIssue:
            "特殊元素（图片、复选框等）附近的格式问题"
        case .mixedFormatIssue:
            "混合格式选择时的状态或应用问题"
        }
    }
}

// MARK: - 问题报告

/// 格式菜单问题报告
struct FormatMenuProblemReport: Identifiable {
    let id = UUID()
    let timestamp: Date
    let problemType: FormatMenuProblemType
    let description: String
    let context: ProblemContext
    let diagnosticSnapshot: FormatMenuDiagnosticSnapshot?
    let suggestedActions: [String]
    let relatedLogs: [String]

    /// 问题上下文
    struct ProblemContext {
        let format: TextFormat?
        let cursorPosition: Int
        let selectedRange: NSRange
        let currentFormats: Set<TextFormat>
        let userAction: String
        let additionalInfo: [String: Any]
    }

    /// 生成报告摘要
    func generateSummary() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var summary = """
        ========================================
        格式菜单问题报告
        ========================================

        ## 基本信息
        - 报告 ID: \(id.uuidString.prefix(8))
        - 时间: \(formatter.string(from: timestamp))
        - 问题类型: \(problemType.displayName)

        ## 问题描述
        \(description)

        ## 问题上下文
        - 用户操作: \(context.userAction)
        - 光标位置: \(context.cursorPosition)
        - 选择范围: \(NSStringFromRange(context.selectedRange))
        - 当前格式: \(context.currentFormats.map(\.displayName).joined(separator: ", "))
        """

        if let format = context.format {
            summary += "\n- 相关格式: \(format.displayName)"
        }

        if !context.additionalInfo.isEmpty {
            summary += "\n- 附加信息: \(context.additionalInfo)"
        }

        if !suggestedActions.isEmpty {
            summary += "\n\n## 建议操作\n"
            for (index, action) in suggestedActions.enumerated() {
                summary += "\(index + 1). \(action)\n"
            }
        }

        if !relatedLogs.isEmpty {
            summary += "\n## 相关日志\n"
            for log in relatedLogs.prefix(10) {
                summary += "- \(log)\n"
            }
        }

        if let snapshot = diagnosticSnapshot {
            summary += "\n## 诊断快照摘要\n"
            summary += "- 编辑器焦点: \(snapshot.editorState.isEditorFocused ? "是" : "否")\n"
            summary += "- 文本长度: \(snapshot.textStorageInfo.length)\n"
            summary += "- 性能: 应用 \(String(format: "%.2f", snapshot.performanceInfo.avgApplicationTimeMs))ms, 同步 \(String(format: "%.2f", snapshot.performanceInfo.avgSynchronizationTimeMs))ms\n"
        }

        summary += "\n========================================"

        return summary
    }
}

// MARK: - 上下文收集器

/// 上下文信息收集器
enum DiagnosticContextCollector {

    /// 收集系统信息
    static func collectSystemInfo() -> [String: Any] {
        var info: [String: Any] = [:]

        // 操作系统版本
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        info["osVersion"] = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // 应用版本
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            info["appVersion"] = appVersion
        }

        // 构建版本
        if let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            info["buildVersion"] = buildVersion
        }

        // 处理器数量
        info["processorCount"] = ProcessInfo.processInfo.processorCount

        // 物理内存
        info["physicalMemory"] = ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)

        // 系统运行时间
        info["systemUptime"] = String(format: "%.2f 小时", ProcessInfo.processInfo.systemUptime / 3600)

        return info
    }

    /// 收集内存使用信息
    static func collectMemoryUsage() -> [String: Any] {
        var info: [String: Any] = [:]

        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedMemory = taskInfo.phys_footprint
            info["usedMemory"] = ByteCountFormatter.string(fromByteCount: Int64(usedMemory), countStyle: .memory)
            info["usedMemoryBytes"] = usedMemory
        }

        return info
    }

    /// 收集撤销历史信息
    @MainActor
    static func collectUndoHistory(from undoManager: UndoManager?) -> [String: Any] {
        var info: [String: Any] = [:]

        guard let undoManager else {
            info["available"] = false
            return info
        }

        info["available"] = true
        info["canUndo"] = undoManager.canUndo
        info["canRedo"] = undoManager.canRedo
        info["undoActionName"] = undoManager.undoActionName
        info["redoActionName"] = undoManager.redoActionName
        info["levelsOfUndo"] = undoManager.levelsOfUndo
        info["groupingLevel"] = undoManager.groupingLevel

        return info
    }

    /// 收集文本属性详情
    static func collectAttributeDetails(from textStorage: NSTextStorage, at range: NSRange) -> [[String: Any]] {
        var attributes: [[String: Any]] = []

        guard range.location < textStorage.length else { return attributes }

        let effectiveRange = NSRange(
            location: range.location,
            length: min(range.length, textStorage.length - range.location)
        )

        guard effectiveRange.length > 0 else { return attributes }

        textStorage.enumerateAttributes(in: effectiveRange, options: []) { attrs, attrRange, _ in
            var attrInfo: [String: Any] = [
                "range": NSStringFromRange(attrRange),
            ]

            for (key, value) in attrs {
                switch key {
                case .font:
                    if let font = value as? NSFont {
                        attrInfo["font"] = "\(font.fontName) \(font.pointSize)pt"
                        attrInfo["fontTraits"] = describeFontTraits(font)
                    }
                case .foregroundColor:
                    if let color = value as? NSColor {
                        attrInfo["foregroundColor"] = color.description
                    }
                case .backgroundColor:
                    if let color = value as? NSColor {
                        attrInfo["backgroundColor"] = color.description
                    }
                case .underlineStyle:
                    attrInfo["underlineStyle"] = value
                case .strikethroughStyle:
                    attrInfo["strikethroughStyle"] = value
                case .paragraphStyle:
                    if let style = value as? NSParagraphStyle {
                        attrInfo["alignment"] = describeAlignment(style.alignment)
                        attrInfo["headIndent"] = style.headIndent
                        attrInfo["firstLineHeadIndent"] = style.firstLineHeadIndent
                    }
                case .attachment:
                    attrInfo["hasAttachment"] = true
                default:
                    attrInfo[key.rawValue] = String(describing: value)
                }
            }

            attributes.append(attrInfo)
        }

        return attributes
    }

    /// 描述字体特性
    private static func describeFontTraits(_ font: NSFont) -> String {
        let fontManager = NSFontManager.shared
        let traits = fontManager.traits(of: font)
        var descriptions: [String] = []

        if traits.contains(.boldFontMask) {
            descriptions.append("加粗")
        }
        if traits.contains(.italicFontMask) {
            descriptions.append("斜体")
        }

        return descriptions.isEmpty ? "常规" : descriptions.joined(separator: ", ")
    }

    /// 描述对齐方式
    private static func describeAlignment(_ alignment: NSTextAlignment) -> String {
        switch alignment {
        case .left: return "左对齐"
        case .center: return "居中"
        case .right: return "右对齐"
        case .justified: return "两端对齐"
        case .natural: return "自然"
        @unknown default: return "未知"
        }
    }
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
        - 当前激活格式: \(formatState.currentFormats.map(\.displayName).joined(separator: ", "))
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

    /// 问题报告历史
    private var problemReports: [FormatMenuProblemReport] = []

    /// 最大快照数
    private let maxSnapshots = 50

    /// 最大问题报告数
    private let maxProblemReports = 100

    /// 是否启用自动诊断
    var isAutoDiagnosticsEnabled = false

    /// 问题检测回调
    var onProblemDetected: ((FormatMenuProblemReport) -> Void)?

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
            .map(\.message)

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
        if selectedRange.length == 0, !format.isBlockFormat {
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
            let failedCount = recentRecords.count(where: { !$0.success })
            if failedCount > 0 {
                issues.append("最近 \(recentRecords.count) 次应用中有 \(failedCount) 次失败")
                suggestions.append("查看错误日志了解失败原因")
            }

            let avgDuration = recentRecords.map(\.duration).reduce(0, +) / Double(recentRecords.count)
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
                suggestions.append("不一致的格式: \(inconsistencies.map(\.displayName).joined(separator: ", "))")
                suggestions.append("调用 updateCurrentFormats() 重新同步状态")
            }
        }

        // 检查性能
        let recentRecords = debugger.getRecentSynchronizationRecords(count: 10)
        if !recentRecords.isEmpty {
            let avgDuration = recentRecords.map(\.duration).reduce(0, +) / Double(recentRecords.count)
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
        snapshots
    }

    /// 获取最近的快照
    func getRecentSnapshots(count: Int = 10) -> [FormatMenuDiagnosticSnapshot] {
        Array(snapshots.suffix(count))
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

    // MARK: - Problem Report Generation

    /// 创建问题报告
    /// - Parameters:
    ///   - problemType: 问题类型
    ///   - description: 问题描述
    ///   - context: 编辑器上下文
    ///   - textView: 文本视图
    ///   - format: 相关格式（可选）
    ///   - userAction: 用户操作描述
    ///   - additionalInfo: 附加信息
    /// - Returns: 问题报告
    func createProblemReport(
        problemType: FormatMenuProblemType,
        description: String,
        context: NativeEditorContext,
        textView: NSTextView? = nil,
        format: TextFormat? = nil,
        userAction: String,
        additionalInfo: [String: Any] = [:]
    ) -> FormatMenuProblemReport {
        // 收集上下文信息
        let problemContext = FormatMenuProblemReport.ProblemContext(
            format: format,
            cursorPosition: context.cursorPosition,
            selectedRange: context.selectedRange,
            currentFormats: context.currentFormats,
            userAction: userAction,
            additionalInfo: additionalInfo
        )

        // 捕获诊断快照
        let snapshot: FormatMenuDiagnosticSnapshot? = if let textView {
            captureSnapshot(context: context, textView: textView)
        } else {
            nil
        }

        // 生成建议操作
        let suggestedActions = generateSuggestedActions(for: problemType, context: problemContext)

        // 收集相关日志
        let relatedLogs = collectRelatedLogs(for: problemType, format: format)

        // 创建报告
        let report = FormatMenuProblemReport(
            timestamp: Date(),
            problemType: problemType,
            description: description,
            context: problemContext,
            diagnosticSnapshot: snapshot,
            suggestedActions: suggestedActions,
            relatedLogs: relatedLogs
        )

        // 保存报告
        problemReports.append(report)
        if problemReports.count > maxProblemReports {
            problemReports.removeFirst(problemReports.count - maxProblemReports)
        }

        // 记录日志
        logger.logWarning(
            "检测到格式菜单问题: \(problemType.displayName)",
            category: LogCategory.diagnostics.rawValue,
            additionalInfo: [
                "reportId": report.id.uuidString,
                "problemType": problemType.rawValue,
                "description": description,
            ]
        )

        // 触发回调
        onProblemDetected?(report)

        return report
    }

    /// 生成建议操作
    private func generateSuggestedActions(
        for problemType: FormatMenuProblemType,
        context: FormatMenuProblemReport.ProblemContext
    ) -> [String] {
        var actions: [String] = []

        switch problemType {
        case .formatNotApplied:
            actions.append("确保已选中要格式化的文本")
            actions.append("检查编辑器是否获得焦点")
            actions.append("尝试使用快捷键应用格式")
            if context.format != nil {
                actions.append("检查该格式是否与当前内容兼容")
            }

        case .stateNotSynchronized:
            actions.append("移动光标到其他位置再移回")
            actions.append("点击编辑器区域重新获取焦点")
            actions.append("检查是否有未完成的格式操作")

        case .performanceSlow:
            actions.append("检查文档大小是否过大")
            actions.append("关闭不必要的调试功能")
            actions.append("重启应用程序")

        case .unexpectedBehavior:
            actions.append("尝试撤销操作恢复之前的状态")
            actions.append("保存文档后重新打开")
            actions.append("检查是否有冲突的格式")

        case .uiNotResponding:
            actions.append("等待当前操作完成")
            actions.append("检查系统资源使用情况")
            actions.append("如果持续无响应，考虑强制退出应用")

        case .inconsistentState:
            actions.append("保存当前文档")
            actions.append("关闭并重新打开文档")
            actions.append("检查撤销历史是否正常")

        case .undoRedoIssue:
            actions.append("尝试多次撤销/重做")
            actions.append("手动重新应用格式")
            actions.append("检查撤销历史记录")

        case .keyboardShortcutIssue:
            actions.append("确认快捷键没有被其他应用占用")
            actions.append("尝试使用菜单操作代替")
            actions.append("检查系统快捷键设置")

        case .specialElementIssue:
            actions.append("避免在特殊元素上直接应用格式")
            actions.append("选择特殊元素周围的文本进行格式化")
            actions.append("检查特殊元素是否正确渲染")

        case .mixedFormatIssue:
            actions.append("尝试先清除所有格式再重新应用")
            actions.append("分段选择并分别应用格式")
            actions.append("检查选中范围内的格式一致性")
        }

        return actions
    }

    /// 收集相关日志
    private func collectRelatedLogs(
        for problemType: FormatMenuProblemType,
        format _: TextFormat?
    ) -> [String] {
        var logs: [String] = []

        // 根据问题类型收集相关日志
        switch problemType {
        case .formatNotApplied, .unexpectedBehavior:
            let formatLogs = logger.getLogs(category: LogCategory.formatApplication)
            logs.append(contentsOf: formatLogs.suffix(5).map(\.compactMessage))

        case .stateNotSynchronized, .inconsistentState:
            let syncLogs = logger.getLogs(category: LogCategory.stateSynchronization)
            logs.append(contentsOf: syncLogs.suffix(5).map(\.compactMessage))

        case .performanceSlow, .uiNotResponding:
            let perfLogs = logger.getLogs(category: LogCategory.performance)
            logs.append(contentsOf: perfLogs.suffix(5).map(\.compactMessage))

        case .undoRedoIssue, .keyboardShortcutIssue:
            let userLogs = logger.getLogs(category: LogCategory.userInteraction)
            logs.append(contentsOf: userLogs.suffix(5).map(\.compactMessage))

        case .specialElementIssue, .mixedFormatIssue:
            let formatStateLogs = logger.getLogs(category: LogCategory.formatState)
            logs.append(contentsOf: formatStateLogs.suffix(5).map(\.compactMessage))
        }

        // 添加错误日志
        let errorLogs = logger.getLogs(category: LogCategory.error)
        logs.append(contentsOf: errorLogs.suffix(3).map(\.compactMessage))

        return logs
    }

    // MARK: - Problem Report Management

    /// 获取所有问题报告
    func getAllProblemReports() -> [FormatMenuProblemReport] {
        problemReports
    }

    /// 获取最近的问题报告
    func getRecentProblemReports(count: Int = 10) -> [FormatMenuProblemReport] {
        Array(problemReports.suffix(count))
    }

    /// 获取指定类型的问题报告
    func getProblemReports(for type: FormatMenuProblemType) -> [FormatMenuProblemReport] {
        problemReports.filter { $0.problemType == type }
    }

    /// 清除所有问题报告
    func clearProblemReports() {
        problemReports.removeAll()
        logger.logInfo("已清除所有问题报告", category: LogCategory.diagnostics.rawValue)
    }

    /// 导出问题报告
    func exportProblemReport(_ report: FormatMenuProblemReport, to url: URL) throws {
        let content = report.generateSummary()
        try content.write(to: url, atomically: true, encoding: .utf8)
        logger.logInfo("问题报告已导出到: \(url.path)", category: LogCategory.diagnostics.rawValue)
    }

    /// 导出所有问题报告
    func exportAllProblemReports(to url: URL) throws {
        var content = """
        ========================================
        格式菜单问题报告汇总
        导出时间: \(ISO8601DateFormatter().string(from: Date()))
        总报告数: \(problemReports.count)
        ========================================

        """

        for (index, report) in problemReports.enumerated() {
            content += "\n--- 报告 \(index + 1) ---\n"
            content += report.generateSummary()
            content += "\n"
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
        logger.logInfo("所有问题报告已导出到: \(url.path)", category: LogCategory.diagnostics.rawValue)
    }

    // MARK: - Auto Diagnostics

    /// 自动检测问题
    /// - Parameters:
    ///   - context: 编辑器上下文
    ///   - textView: 文本视图
    ///   - operation: 操作描述
    ///   - format: 相关格式
    ///   - duration: 操作持续时间
    ///   - success: 操作是否成功
    func autoDetectProblems(
        context: NativeEditorContext,
        textView: NSTextView,
        operation: String,
        format: TextFormat? = nil,
        duration: TimeInterval,
        success: Bool
    ) {
        guard isAutoDiagnosticsEnabled else { return }

        // 检测性能问题
        if duration > performanceMonitor.thresholds.formatApplication * 2 {
            _ = createProblemReport(
                problemType: .performanceSlow,
                description: "操作 '\(operation)' 耗时 \(String(format: "%.2f", duration * 1000))ms，超过预期",
                context: context,
                textView: textView,
                format: format,
                userAction: operation,
                additionalInfo: ["duration": duration]
            )
        }

        // 检测操作失败
        if !success {
            _ = createProblemReport(
                problemType: .formatNotApplied,
                description: "操作 '\(operation)' 执行失败",
                context: context,
                textView: textView,
                format: format,
                userAction: operation
            )
        }

        // 检测状态不一致
        if let format {
            let formatManager = FormatManager.shared
            if let textStorage = textView.textStorage,
               context.cursorPosition < textStorage.length
            {
                let isActiveInContext = context.currentFormats.contains(format)
                let isActiveInStorage = formatManager.isFormatActive(format, in: textStorage, at: context.cursorPosition)

                if isActiveInContext != isActiveInStorage {
                    _ = createProblemReport(
                        problemType: .inconsistentState,
                        description: "格式 '\(format.displayName)' 状态不一致：上下文=\(isActiveInContext)，存储=\(isActiveInStorage)",
                        context: context,
                        textView: textView,
                        format: format,
                        userAction: operation
                    )
                }
            }
        }
    }

    // MARK: - Comprehensive Context Collection

    /// 收集完整的上下文信息
    /// - Parameters:
    ///   - context: 编辑器上下文
    ///   - textView: 文本视图
    /// - Returns: 上下文信息字典
    func collectComprehensiveContext(
        context: NativeEditorContext,
        textView: NSTextView
    ) -> [String: Any] {
        var info: [String: Any] = [:]

        // 系统信息
        info["system"] = DiagnosticContextCollector.collectSystemInfo()

        // 内存使用
        info["memory"] = DiagnosticContextCollector.collectMemoryUsage()

        // 撤销历史
        info["undoHistory"] = DiagnosticContextCollector.collectUndoHistory(from: textView.undoManager)

        // 编辑器状态
        info["editorState"] = [
            "isEditorFocused": context.isEditorFocused,
            "hasUnsavedChanges": context.hasUnsavedChanges,
            "cursorPosition": context.cursorPosition,
            "selectedRange": NSStringFromRange(context.selectedRange),
            "currentFormats": context.currentFormats.map(\.displayName),
            "specialElement": context.currentSpecialElement?.displayName ?? "无",
        ]

        // 文本存储信息
        if let textStorage = textView.textStorage {
            info["textStorage"] = [
                "length": textStorage.length,
                "isEmpty": textStorage.string.isEmpty,
                "preview": String(textStorage.string.prefix(200)),
            ]

            // 选中范围的属性详情
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 {
                info["selectedAttributes"] = DiagnosticContextCollector.collectAttributeDetails(
                    from: textStorage,
                    at: selectedRange
                )
            }
        }

        // 性能统计
        let stats = debugger.statistics
        info["performance"] = [
            "totalApplications": stats.totalApplications,
            "totalSynchronizations": stats.totalSynchronizations,
            "avgApplicationTimeMs": stats.avgApplicationTimeMs,
            "avgSynchronizationTimeMs": stats.avgSynchronizationTimeMs,
            "slowApplications": stats.slowApplications,
            "slowSynchronizations": stats.slowSynchronizations,
        ]

        // 最近的错误
        let recentErrors = debugger.getEvents(type: .error).suffix(5)
        info["recentErrors"] = recentErrors.map(\.message)

        return info
    }

    /// 生成综合诊断报告
    /// - Parameters:
    ///   - context: 编辑器上下文
    ///   - textView: 文本视图
    ///   - includeSystemInfo: 是否包含系统信息
    ///   - includePerformanceDetails: 是否包含性能详情
    /// - Returns: 综合诊断报告
    func generateComprehensiveDiagnosticReport(
        context: NativeEditorContext,
        textView: NSTextView,
        includeSystemInfo: Bool = true,
        includePerformanceDetails: Bool = true
    ) -> String {
        var report = """
        ========================================
        格式菜单综合诊断报告
        生成时间: \(ISO8601DateFormatter().string(from: Date()))
        ========================================

        """

        // 基础诊断报告
        report += generateFullDiagnosticReport(context: context, textView: textView)

        // 系统信息
        if includeSystemInfo {
            let systemInfo = DiagnosticContextCollector.collectSystemInfo()
            report += """

            ## 系统信息
            - 操作系统版本: \(systemInfo["osVersion"] ?? "未知")
            - 应用版本: \(systemInfo["appVersion"] ?? "未知")
            - 构建版本: \(systemInfo["buildVersion"] ?? "未知")
            - 处理器数量: \(systemInfo["processorCount"] ?? "未知")
            - 物理内存: \(systemInfo["physicalMemory"] ?? "未知")
            - 系统运行时间: \(systemInfo["systemUptime"] ?? "未知")

            """

            let memoryInfo = DiagnosticContextCollector.collectMemoryUsage()
            report += """
            ## 内存使用
            - 当前使用: \(memoryInfo["usedMemory"] ?? "未知")

            """
        }

        // 性能详情
        if includePerformanceDetails {
            report += """

            ## 性能详情
            \(performanceMonitor.generatePerformanceReport())

            """
        }

        // 问题报告摘要
        if !problemReports.isEmpty {
            report += """

            ## 最近的问题报告

            """

            for problemReport in problemReports.suffix(5) {
                report += "- [\(problemReport.problemType.displayName)] \(problemReport.description)\n"
            }
        }

        report += "\n========================================"

        return report
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

        if let format {
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
