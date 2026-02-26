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

    /// 防抖定时器
    private var debounceTimer: Timer?

    private let debounceInterval: TimeInterval = 0.05 // 50ms

    /// 上次状态（用于增量更新）
    private var lastState: FormatState?

    // MARK: - FormatMenuProvider Protocol Properties

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
        guard let context = editorContext else {
            return FormatState.default
        }

        let hasSelection = context.selectedRange.length > 0

        do {
            if hasSelection {
                return try detectFormatStateInSelectionSafe(range: context.selectedRange)
            } else {
                return try detectFormatStateAtCursorSafe(position: context.cursorPosition)
            }
        } catch {
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

    // MARK: - FormatMenuProvider Protocol Methods - 格式应用

    /// 应用格式
    /// - Parameter format: 要应用的格式
    /// - Note: 自动处理互斥规则
    public func applyFormat(_ format: TextFormat) {
        guard let context = editorContext else {
            return
        }

        // 通过 NativeEditorContext 调用（内部通过 formatApplyHandler 直连 Coordinator）
        context.applyFormat(format, method: .toolbar)

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

    /// 增加缩进
    public func increaseIndent() {
        guard let context = editorContext else {
            return
        }

        context.increaseIndent()
    }

    /// 减少缩进
    public func decreaseIndent() {
        guard let context = editorContext else {
            return
        }

        context.decreaseIndent()
    }

    /// 增大字体
    public func increaseFontSize() {
        guard editorContext != nil else {
            return
        }

        // TODO(spec-121): FontSizeManager 暂无 increase/decrease API
        LogService.shared.debug(.editor, "increaseFontSize 待实现")
    }

    /// 减小字体
    public func decreaseFontSize() {
        guard editorContext != nil else {
            return
        }

        // TODO(spec-121): FontSizeManager 暂无 increase/decrease API
        LogService.shared.debug(.editor, "decreaseFontSize 待实现")
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

        // 遍历选择范围内的属性（委托 InlineFormatHandler 检测）
        var currentPosition = range.location
        while currentPosition < range.location + range.length {
            var effectiveRange = NSRange()
            let attributes = textStorage.attributes(at: currentPosition, effectiveRange: &effectiveRange)

            if allBold, !InlineFormatHandler.isFormatActive(.bold, in: attributes) {
                allBold = false
            }
            if allItalic, !InlineFormatHandler.isFormatActive(.italic, in: attributes) {
                allItalic = false
            }
            if allUnderline, !InlineFormatHandler.isFormatActive(.underline, in: attributes) {
                allUnderline = false
            }
            if allStrikethrough, !InlineFormatHandler.isFormatActive(.strikethrough, in: attributes) {
                allStrikethrough = false
            }
            if allHighlight, !InlineFormatHandler.isFormatActive(.highlight, in: attributes) {
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

        // 段落级格式（委托 ParagraphManager）
        let storage = asTextStorage(textStorage)
        state.paragraphFormat = ParagraphManager.detectParagraphFormat(at: range.location, in: storage)

        // 对齐格式（委托 ParagraphManager）
        state.alignment = ParagraphManager.detectAlignment(at: range.location, in: storage)

        // 引用块格式（委托 ParagraphManager）
        state.isQuote = ParagraphManager.isQuoteFormat(at: range.location, in: storage)

        return state
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

        // 检测字符级格式（委托 InlineFormatHandler）
        state.isBold = InlineFormatHandler.isFormatActive(.bold, in: attributes)
        state.isItalic = InlineFormatHandler.isFormatActive(.italic, in: attributes)
        state.isUnderline = InlineFormatHandler.isFormatActive(.underline, in: attributes)
        state.isStrikethrough = InlineFormatHandler.isFormatActive(.strikethrough, in: attributes)
        state.isHighlight = InlineFormatHandler.isFormatActive(.highlight, in: attributes)

        // 检测段落级格式（委托 ParagraphManager）
        let storage = asTextStorage(textStorage)
        state.paragraphFormat = ParagraphManager.detectParagraphFormat(at: position, in: storage)

        // 检测对齐格式（委托 ParagraphManager）
        state.alignment = ParagraphManager.detectAlignment(at: position, in: storage)

        // 检测引用块格式（委托 ParagraphManager）
        state.isQuote = ParagraphManager.isQuoteFormat(at: position, in: storage)

        return state
    }

    /// 将 NSAttributedString 转为 NSTextStorage（供 ParagraphManager 调用）
    private func asTextStorage(_ text: NSAttributedString) -> NSTextStorage {
        if let storage = text as? NSTextStorage {
            return storage
        }
        return NSTextStorage(attributedString: text)
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
