//
//  NativeFormatProvider.swift
//  MiNoteMac
//
//  原生编辑器格式提供者 - 实现 FormatMenuProvider 协议
//  为原生编辑器提供统一的格式状态获取和应用接口
//
//

import AppKit
import Combine
import Foundation

// MARK: - 性能监控记录

/// 格式检测性能记录
public struct FormatDetectionPerformanceRecord: Sendable {
    public let timestamp: Date
    public let durationMs: Double
    public let detectionType: DetectionType
    public let rangeLength: Int
    public let success: Bool
    public let errorMessage: String?

    public enum DetectionType: String, Sendable {
        case cursor
        case selection
    }
}

// MARK: - NativeFormatProvider

/// 原生编辑器格式提供者
/// 实现 FormatMenuProvider 协议，为原生编辑器提供格式操作接口
@MainActor
public final class NativeFormatProvider: FormatMenuProvider {

    // MARK: - Properties

    /// 编辑器上下文（弱引用，避免循环引用）
    private weak var editorContext: NativeEditorContext?

    /// 格式状态变化主题
    private let formatStateSubject = PassthroughSubject<FormatState, Never>()

    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 格式管理器
    private let formatManager = FormatManager.shared

    /// 防抖定时器
    private var debounceTimer: Timer?

    private let debounceInterval: TimeInterval = 0.05 // 50ms

    // MARK: - 性能监控属性


    /// 性能监控是否启用
    private var performanceMonitoringEnabled = true

    /// 性能记录
    private var performanceRecords: [FormatDetectionPerformanceRecord] = []

    /// 最大记录数量
    private let maxRecordCount = 200

    /// 检测计数
    private var detectionCount = 0

    /// 总检测时间（毫秒）
    private var totalDetectionTime: Double = 0

    /// 最大检测时间（毫秒）
    private var maxDetectionTime: Double = 0

    /// 最小检测时间（毫秒）
    private var minDetectionTime = Double.infinity

    /// 错误计数
    private var errorCount = 0

    /// 上次状态（用于增量更新）
    private var lastState: FormatState?

    // MARK: - FormatMenuProvider Protocol Properties

    /// 编辑器类型
    public var editorType: EditorType {
        .native
    }

    /// 编辑器是否可用
    public var isEditorAvailable: Bool {
        guard let context = editorContext else { return false }
        return context.isEditorFocused
    }

    /// 格式状态变化发布者
    public var formatStatePublisher: AnyPublisher<FormatState, Never> {
        formatStateSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    /// 初始化格式提供者
    /// - Parameter editorContext: 编辑器上下文
    public init(editorContext: NativeEditorContext) {
        self.editorContext = editorContext
        setupObservers()
    }

    // MARK: - FormatMenuProvider Protocol Methods - 状态获取

    /// 获取当前格式状态
    /// - Returns: 当前格式状态
    public func getCurrentFormatState() -> FormatState {
        let startTime = CFAbsoluteTimeGetCurrent()
        var detectionType: FormatDetectionPerformanceRecord.DetectionType = .cursor
        var rangeLength = 0
        var success = true
        var errorMessage: String?

        defer {
            if performanceMonitoringEnabled {
                let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                recordPerformance(
                    duration: duration,
                    detectionType: detectionType,
                    rangeLength: rangeLength,
                    success: success,
                    errorMessage: errorMessage
                )
            }
        }

        // 边界条件：编辑器上下文不可用
        guard let context = editorContext else {
            errorMessage = "编辑器上下文不可用"
            success = false
            errorCount += 1
            return FormatState.default
        }

        let hasSelection = context.selectedRange.length > 0
        rangeLength = hasSelection ? context.selectedRange.length : 0
        detectionType = hasSelection ? .selection : .cursor

        do {
            if hasSelection {
                // 选择模式：检测选择范围内的格式状态
                return try detectFormatStateInSelectionSafe(range: context.selectedRange)
            } else {
                // 光标模式：检测光标位置的格式状态
                return try detectFormatStateAtCursorSafe(position: context.cursorPosition)
            }
        } catch {
            errorMessage = error.localizedDescription
            success = false
            errorCount += 1
            return FormatState.default
        }
    }

    /// 检查指定格式是否激活
    /// - Parameter format: 格式类型
    /// - Returns: 是否激活
    public func isFormatActive(_ format: TextFormat) -> Bool {
        let state = getCurrentFormatState()
        return state.isFormatActive(format)
    }

    // MARK: - 性能监控方法


    /// 启用或禁用性能监控
    /// - Parameter enabled: 是否启用
    public func setPerformanceMonitoring(enabled: Bool) {
        performanceMonitoringEnabled = enabled
    }

    /// 获取性能统计信息
    /// - Returns: 性能统计信息字典
    public func getPerformanceStats() -> [String: Any] {
        guard detectionCount > 0 else {
            return [
                "detectionCount": 0,
                "errorCount": errorCount,
                "averageTime": 0.0,
                "maxTime": 0.0,
                "minTime": 0.0,
                "totalTime": 0.0,
            ]
        }

        return [
            "detectionCount": detectionCount,
            "errorCount": errorCount,
            "averageTime": totalDetectionTime / Double(detectionCount),
            "maxTime": maxDetectionTime,
            "minTime": minDetectionTime == Double.infinity ? 0.0 : minDetectionTime,
            "totalTime": totalDetectionTime,
            "errorRate": Double(errorCount) / Double(detectionCount),
        ]
    }

    /// 重置性能统计信息
    public func resetPerformanceStats() {
        detectionCount = 0
        errorCount = 0
        totalDetectionTime = 0
        maxDetectionTime = 0
        minDetectionTime = Double.infinity
        performanceRecords.removeAll()
    }

    /// 记录性能数据
    private func recordPerformance(
        duration: Double,
        detectionType: FormatDetectionPerformanceRecord.DetectionType,
        rangeLength: Int,
        success: Bool,
        errorMessage: String?
    ) {
        // 更新统计信息
        detectionCount += 1
        totalDetectionTime += duration
        maxDetectionTime = max(maxDetectionTime, duration)
        minDetectionTime = min(minDetectionTime, duration)

        // 创建性能记录
        let record = FormatDetectionPerformanceRecord(
            timestamp: Date(),
            durationMs: duration,
            detectionType: detectionType,
            rangeLength: rangeLength,
            success: success,
            errorMessage: errorMessage
        )

        performanceRecords.append(record)

        // 限制记录数量
        if performanceRecords.count > maxRecordCount {
            performanceRecords.removeFirst(performanceRecords.count - maxRecordCount)
        }
    }

    // MARK: - FormatMenuProvider Protocol Methods - 格式应用

    /// 应用格式
    /// - Parameter format: 要应用的格式
    /// - Note: 自动处理互斥规则
    public func applyFormat(_ format: TextFormat) {
        guard let context = editorContext else {
            return
        }

        let hasSelection = context.selectedRange.length > 0

        if hasSelection {
            // 选择模式：应用格式到选择范围
            applyFormatToSelection(format, range: context.selectedRange)
        } else {
            // 光标模式：设置 typingAttributes
            applyFormatAtCursor(format)
        }

        // 更新格式状态并发送通知
        scheduleStateUpdate()
    }

    /// 切换格式
    /// - Parameter format: 要切换的格式
    /// - Note: 如果格式已激活则移除，否则应用
    public func toggleFormat(_ format: TextFormat) {
        guard let context = editorContext else {
            return
        }

        // 使用 NativeEditorContext 的 applyFormat 方法，它会处理切换逻辑
        context.applyFormat(format, method: .toolbar)

        // 更新格式状态并发送通知
        scheduleStateUpdate()
    }

    /// 清除段落格式（恢复为正文）
    public func clearParagraphFormat() {
        guard let context = editorContext else {
            return
        }

        context.clearHeadingFormat()

        // 更新格式状态并发送通知
        scheduleStateUpdate()
    }

    /// 清除对齐格式（恢复为左对齐）
    public func clearAlignmentFormat() {
        guard let context = editorContext else {
            return
        }

        context.clearAlignmentFormat()

        // 更新格式状态并发送通知
        scheduleStateUpdate()
    }

    // MARK: - 光标模式格式检测

    /// 光标模式下的格式状态检测（安全版本，带边界条件处理）
    /// - Parameter position: 光标位置
    /// - Returns: 格式状态
    /// - Throws: 检测过程中的错误
    private func detectFormatStateAtCursorSafe(position: Int) throws -> FormatState {
        guard let context = editorContext else {
            throw FormatDetectionError.editorNotAvailable
        }

        var state = FormatState()
        state.hasSelection = false
        state.selectionLength = 0

        let textStorage = context.nsAttributedText

        // 边界条件：文档为空
        guard textStorage.length > 0 else {
            return state
        }

        // 边界条件：光标在文档开头
        guard position > 0 else {
            return state
        }

        // 边界条件：光标位置超出文档长度
        guard position <= textStorage.length else {
            let safePosition = textStorage.length - 1
            if safePosition >= 0 {
                let attributes = textStorage.attributes(at: safePosition, effectiveRange: nil)
                state = detectFormatsFromAttributes(attributes, textStorage: textStorage, position: safePosition)
            }
            state.hasSelection = false
            state.selectionLength = 0
            return state
        }

        // 获取光标前一个字符的属性
        let attributePosition = min(position - 1, textStorage.length - 1)
        let attributes = textStorage.attributes(at: attributePosition, effectiveRange: nil)

        // 检测所有格式
        state = detectFormatsFromAttributes(attributes, textStorage: textStorage, position: attributePosition)
        state.hasSelection = false
        state.selectionLength = 0

        return state
    }

    /// 光标模式下的格式状态检测（原始版本，保持向后兼容）
    /// - Parameter position: 光标位置
    /// - Returns: 格式状态
    public func detectFormatStateAtCursor(position: Int) -> FormatState {
        do {
            return try detectFormatStateAtCursorSafe(position: position)
        } catch {
            return FormatState.default
        }
    }

    // MARK: - 选择模式格式检测

    /// 选择模式下的格式状态检测（安全版本，带边界条件处理）
    /// - Parameter range: 选择范围
    /// - Returns: 格式状态
    /// - Throws: 检测过程中的错误
    private func detectFormatStateInSelectionSafe(range: NSRange) throws -> FormatState {
        guard let context = editorContext else {
            throw FormatDetectionError.editorNotAvailable
        }

        var state = FormatState()
        state.hasSelection = true
        state.selectionLength = range.length

        let textStorage = context.nsAttributedText

        // 边界条件：文档为空
        guard textStorage.length > 0 else {
            state.hasSelection = false
            state.selectionLength = 0
            return state
        }

        // 边界条件：选择范围起始位置超出文档长度
        guard range.location < textStorage.length else {
            state.hasSelection = false
            state.selectionLength = 0
            return state
        }

        // 调整范围以确保不超出文本长度
        let validRange = NSRange(
            location: range.location,
            length: min(range.length, textStorage.length - range.location)
        )

        // 边界条件：有效范围长度为 0
        guard validRange.length > 0 else {
            state.hasSelection = false
            state.selectionLength = 0
            return state
        }

        state.selectionLength = validRange.length

        // 使用优化的遍历方法检测格式
        state = detectFormatsInRangeOptimized(textStorage: textStorage, range: validRange)
        state.hasSelection = true
        state.selectionLength = validRange.length

        return state
    }

    /// 选择模式下的格式状态检测（原始版本，保持向后兼容）
    /// - Parameter range: 选择范围
    /// - Returns: 格式状态
    public func detectFormatStateInSelection(range: NSRange) -> FormatState {
        do {
            return try detectFormatStateInSelectionSafe(range: range)
        } catch {
            return FormatState.default
        }
    }

    /// 优化的范围内格式检测
    /// 使用批量遍历减少性能开销
    private func detectFormatsInRangeOptimized(textStorage: NSAttributedString, range: NSRange) -> FormatState {
        var state = FormatState()

        // 初始化为全部激活（用于"全选检测"逻辑）
        var allBold = true
        var allItalic = true
        var allUnderline = true
        var allStrikethrough = true
        var allHighlight = true

        // 优化：对于大范围选择，使用采样检测
        let shouldSample = range.length > 1000
        let sampleInterval = shouldSample ? max(1, range.length / 100) : 1

        // 遍历选择范围内的属性
        var currentPosition = range.location
        while currentPosition < range.location + range.length {
            var effectiveRange = NSRange()
            let attributes = textStorage.attributes(at: currentPosition, effectiveRange: &effectiveRange)

            // 检测加粗
            if allBold, !isBoldInAttributes(attributes) {
                allBold = false
            }
            // 检测斜体
            if allItalic, !isItalicInAttributes(attributes) {
                allItalic = false
            }
            // 检测下划线
            if allUnderline, !isUnderlineInAttributes(attributes) {
                allUnderline = false
            }
            // 检测删除线
            if allStrikethrough, !isStrikethroughInAttributes(attributes) {
                allStrikethrough = false
            }
            // 检测高亮
            if allHighlight, !isHighlightInAttributes(attributes) {
                allHighlight = false
            }

            // 如果所有格式都已确定为 false，可以提前退出
            if !allBold, !allItalic, !allUnderline, !allStrikethrough, !allHighlight {
                break
            }

            // 移动到下一个位置
            if shouldSample {
                currentPosition += sampleInterval
            } else {
                // 跳到有效范围的末尾
                currentPosition = effectiveRange.location + effectiveRange.length
            }
        }

        // 设置字符级格式状态
        state.isBold = allBold
        state.isItalic = allItalic
        state.isUnderline = allUnderline
        state.isStrikethrough = allStrikethrough
        state.isHighlight = allHighlight

        // 段落级格式：取第一个字符的段落格式
        let firstCharAttributes = textStorage.attributes(at: range.location, effectiveRange: nil)
        state.paragraphFormat = detectParagraphFormat(from: firstCharAttributes, textStorage: textStorage, position: range.location)

        // 对齐格式：取第一个字符的对齐格式
        state.alignment = detectAlignmentFormat(from: firstCharAttributes)

        // 引用块格式：取第一个字符的引用块状态
        state.isQuote = isQuoteInAttributes(firstCharAttributes)

        return state
    }

    // MARK: - 格式应用逻辑

    /// 选择模式下应用格式
    /// - Parameters:
    ///   - format: 要应用的格式
    ///   - range: 选择范围
    private func applyFormatToSelection(_ format: TextFormat, range _: NSRange) {
        guard let context = editorContext else { return }

        // 使用 NativeEditorContext 的 applyFormat 方法
        // 它会根据当前状态决定是应用还是移除格式
        context.applyFormat(format, method: .toolbar)
    }

    /// 光标模式下应用格式
    /// - Parameter format: 要应用的格式
    private func applyFormatAtCursor(_ format: TextFormat) {
        guard let context = editorContext else { return }

        // 使用 NativeEditorContext 的 applyFormat 方法
        // 它会设置 typingAttributes
        context.applyFormat(format, method: .toolbar)
    }

    // MARK: - 私有方法 - 格式检测辅助

    /// 从属性中检测所有格式
    /// - Parameters:
    ///   - attributes: 属性字典
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 格式状态
    private func detectFormatsFromAttributes(
        _ attributes: [NSAttributedString.Key: Any],
        textStorage: NSAttributedString,
        position: Int
    ) -> FormatState {
        var state = FormatState()

        // 检测字符级格式
        state.isBold = isBoldInAttributes(attributes)
        state.isItalic = isItalicInAttributes(attributes)
        state.isUnderline = isUnderlineInAttributes(attributes)
        state.isStrikethrough = isStrikethroughInAttributes(attributes)
        state.isHighlight = isHighlightInAttributes(attributes)

        // 检测段落级格式
        state.paragraphFormat = detectParagraphFormat(from: attributes, textStorage: textStorage, position: position)

        // 检测对齐格式
        state.alignment = detectAlignmentFormat(from: attributes)

        // 检测引用块格式
        state.isQuote = isQuoteInAttributes(attributes)

        return state
    }

    /// 检测加粗格式
    private func isBoldInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let font = attributes[.font] as? NSFont else { return false }

        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) {
            return true
        }

        // 备用检测：检查字体名称
        let fontName = font.fontName.lowercased()
        if fontName.contains("bold") || fontName.contains("-bold") {
            return true
        }

        // 备用检测：检查字体 weight
        if let weightTrait = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any],
           let weight = weightTrait[.weight] as? CGFloat
        {
            return weight >= 0.4
        }

        return false
    }

    /// 检测斜体格式
    private func isItalicInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        // 方法 1: 检查 obliqueness 属性（用于中文斜体）
        if let obliqueness = attributes[.obliqueness] as? Double, obliqueness > 0 {
            return true
        }

        // 方法 2: 检查字体特性
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.italic) {
                return true
            }

            // 备用检测：检查字体名称
            let fontName = font.fontName.lowercased()
            if fontName.contains("italic") || fontName.contains("oblique") {
                return true
            }
        }

        return false
    }

    /// 检测下划线格式
    private func isUnderlineInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
            return true
        }
        return false
    }

    /// 检测删除线格式
    private func isStrikethroughInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
            return true
        }
        return false
    }

    /// 检测高亮格式
    private func isHighlightInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let backgroundColor = attributes[.backgroundColor] as? NSColor {
            // 排除透明或白色背景
            if backgroundColor.alphaComponent > 0.1, backgroundColor != .clear, backgroundColor != .white {
                return true
            }
        }
        return false
    }

    /// 检测引用块格式
    private func isQuoteInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let isQuote = attributes[.quoteBlock] as? Bool {
            return isQuote
        }
        return false
    }

    /// 检测段落格式
    /// - Parameters:
    ///   - attributes: 属性字典
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 段落格式
    ///
    /// 标题检测完全基于字体大小，因为在小米笔记中字体大小和标题类型是一一对应的
    ///
    private func detectParagraphFormat(
        from attributes: [NSAttributedString.Key: Any],
        textStorage: NSAttributedString,
        position: Int
    ) -> ParagraphFormat {
        // 使用 FontSizeManager 检查字体大小来检测标题格式
        // 在小米笔记中，字体大小和标题类型是一一对应的
        if let font = attributes[.font] as? NSFont {
            let fontSize = font.pointSize
            let detectedFormat = FontSizeManager.shared.detectParagraphFormat(fontSize: fontSize)
            if detectedFormat != .body {
                return detectedFormat
            }
        }

        // 检查列表类型
        // 获取当前行的范围
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))

        if lineRange.location < textStorage.length {
            let lineAttributes = textStorage.attributes(at: lineRange.location, effectiveRange: nil)

            // 检查 listType 属性
            if let listType = lineAttributes[.listType] {
                if let listTypeEnum = listType as? ListType {
                    switch listTypeEnum {
                    case .bullet: return .bulletList
                    case .ordered: return .numberedList
                    case .checkbox: return .checkbox
                    case .none: break
                    }
                } else if let listTypeString = listType as? String {
                    switch listTypeString {
                    case "bullet": return .bulletList
                    case "ordered", "order": return .numberedList
                    case "checkbox": return .checkbox
                    default: break
                    }
                }
            }

            // 检查附件类型
            if let attachment = lineAttributes[.attachment] as? NSTextAttachment {
                if attachment is InteractiveCheckboxAttachment {
                    return .checkbox
                } else if attachment is BulletAttachment {
                    return .bulletList
                } else if attachment is OrderAttachment {
                    return .numberedList
                }
            }
        }

        return .body
    }

    /// 检测对齐格式
    /// - Parameter attributes: 属性字典
    /// - Returns: 对齐格式
    private func detectAlignmentFormat(from attributes: [NSAttributedString.Key: Any]) -> AlignmentFormat {
        guard let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle else {
            return .left
        }

        switch paragraphStyle.alignment {
        case .center: return .center
        case .right: return .right
        default: return .left
        }
    }

    // MARK: - 私有方法 - 状态更新

    /// 调度状态更新（带防抖）
    private func scheduleStateUpdate() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performStateUpdate()
            }
        }
    }

    /// 执行状态更新
    private func performStateUpdate() {
        let state = getCurrentFormatState()

        // 增量更新：只有状态变化时才发送
        if let lastState, state == lastState {
            return
        }

        lastState = state
        formatStateSubject.send(state)
    }

    /// 立即执行状态更新（不使用防抖）
    public func forceStateUpdate() {
        debounceTimer?.invalidate()
        lastState = nil // 清除上次状态，强制发送
        performStateUpdate()
    }

    // MARK: - 私有方法 - 观察者设置

    /// 设置观察者
    private func setupObservers() {
        guard let context = editorContext else { return }

        // 监听选择范围变化
        context.$selectedRange
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)

        // 监听光标位置变化
        context.$cursorPosition
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)

        // 监听当前格式变化
        context.$currentFormats
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)

        // 监听内容变化
        context.$nsAttributedText
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &cancellables)
    }

    // MARK: - Deinit

    nonisolated deinit {
        // 注意：在 nonisolated deinit 中不能访问 MainActor 隔离的属性
        // debounceTimer 会在对象销毁时自动失效
    }
}

// MARK: - NativeFormatProvider 扩展 - 调试方法

public extension NativeFormatProvider {

    /// 打印当前格式状态（调试用）
    func printCurrentState() {
        let state = getCurrentFormatState()
        LogService.shared.debug(.editor, "[NativeFormatProvider] 当前格式状态:")
        LogService.shared.debug(.editor, "  - 段落格式: \(state.paragraphFormat.displayName)")
        LogService.shared.debug(.editor, "  - 对齐方式: \(state.alignment.displayName)")
        LogService.shared.debug(.editor, "  - 加粗: \(state.isBold)")
        LogService.shared.debug(.editor, "  - 斜体: \(state.isItalic)")
        LogService.shared.debug(.editor, "  - 下划线: \(state.isUnderline)")
        LogService.shared.debug(.editor, "  - 删除线: \(state.isStrikethrough)")
        LogService.shared.debug(.editor, "  - 高亮: \(state.isHighlight)")
        LogService.shared.debug(.editor, "  - 引用块: \(state.isQuote)")
        LogService.shared.debug(.editor, "  - 有选择: \(state.hasSelection)")
        LogService.shared.debug(.editor, "  - 选择长度: \(state.selectionLength)")
    }
}

// MARK: - 格式检测错误枚举

/// 格式检测错误
public enum FormatDetectionError: Error, LocalizedError {
    case editorNotAvailable
    case invalidRange(location: Int, length: Int, textLength: Int)
    case emptyDocument
    case cursorOutOfBounds(position: Int, textLength: Int)
    case unknownError(String)

    public var errorDescription: String? {
        switch self {
        case .editorNotAvailable:
            "编辑器不可用"
        case let .invalidRange(location, length, textLength):
            "无效的选择范围: location=\(location), length=\(length), textLength=\(textLength)"
        case .emptyDocument:
            "文档为空"
        case let .cursorOutOfBounds(position, textLength):
            "光标位置超出范围: position=\(position), textLength=\(textLength)"
        case let .unknownError(message):
            "未知错误: \(message)"
        }
    }
}
