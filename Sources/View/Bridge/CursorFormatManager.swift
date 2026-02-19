//
//  CursorFormatManager.swift
//  MiNoteMac
//
//  光标格式管理器 - 统一管理光标位置的格式检测、工具栏同步和输入格式继承
//  负责协调格式检测、工具栏同步和 typingAttributes 同步
//
//  _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_
//

import AppKit
import Combine
import Foundation

// MARK: - 光标格式检测错误

/// 光标格式检测错误
/// _Requirements: 5.5_
public enum CursorFormatDetectionError: Error, CustomStringConvertible {
    case textViewUnavailable
    case textStorageEmpty
    case invalidPosition
    case attributeExtractionFailed

    public var description: String {
        switch self {
        case .textViewUnavailable:
            "NSTextView 不可用"
        case .textStorageEmpty:
            "文本存储为空"
        case .invalidPosition:
            "无效的光标位置"
        case .attributeExtractionFailed:
            "属性提取失败"
        }
    }
}

// MARK: - 格式检测结果

/// 格式检测结果
/// _Requirements: 1.1-1.6_
public struct FormatDetectionResult {
    /// 检测到的格式状态
    public let state: FormatState

    /// 检测位置
    public let position: Int

    /// 是否为光标模式（无选择）
    public let isCursorMode: Bool

    /// 检测时间戳
    public let timestamp: Date

    public init(state: FormatState, position: Int, isCursorMode: Bool, timestamp: Date = Date()) {
        self.state = state
        self.position = position
        self.isCursorMode = isCursorMode
        self.timestamp = timestamp
    }
}

// MARK: - 光标格式管理器

/// 光标格式管理器
/// 统一管理光标位置的格式检测、工具栏同步和输入格式继承
/// _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_
@MainActor
public final class CursorFormatManager {

    // MARK: - Singleton

    /// 共享实例
    public static let shared = CursorFormatManager()

    // MARK: - Properties

    /// 当前关联的 NSTextView（弱引用）
    private weak var textView: NSTextView?

    /// 当前关联的 NativeEditorContext（弱引用）
    private weak var editorContext: NativeEditorContext?

    /// 防抖定时器
    private var debounceTimer: Timer?

    /// 防抖间隔（毫秒）
    /// _Requirements: 6.5_
    private let debounceInterval: TimeInterval = 0.05 // 50ms

    /// 当前检测到的格式状态
    /// _Requirements: 1.1-1.6_
    public private(set) var currentFormatState = FormatState()

    /// 待处理的选择范围（用于防抖）
    private var pendingRange: NSRange?

    /// 是否已注册
    public private(set) var isRegistered = false

    // MARK: - Initialization

    private init() {}

    public func register(textView: NSTextView, context: NativeEditorContext) {
        self.textView = textView
        editorContext = context
        isRegistered = true

        let selectedRange = textView.selectedRange()
        handleSelectionChange(selectedRange)
    }

    public func unregister() {
        debounceTimer?.invalidate()
        debounceTimer = nil

        textView = nil
        editorContext = nil
        isRegistered = false

        currentFormatState = FormatState()
        pendingRange = nil
    }

    // MARK: - Public Methods - 选择变化处理

    /// 处理光标位置变化
    ///
    /// 此方法是 CursorFormatManager 的主要入口点，当光标位置或选择范围变化时调用。
    /// 它使用防抖机制来合并快速连续的变化，避免频繁的状态更新影响性能。
    ///
    /// 处理流程：
    /// 1. 保存待处理的选择范围
    /// 2. 使用防抖机制调度更新（50ms 延迟）
    /// 3. 在 performUpdate() 中执行实际的格式检测和状态同步
    ///
    /// - Parameter range: 新的选择范围
    ///   - 当 range.length == 0 时，表示光标模式（无选择）
    ///   - 当 range.length > 0 时，表示选择模式（有选中文字）
    ///
    /// _Requirements: 3.1, 6.2_
    public func handleSelectionChange(_ range: NSRange) {
        // 保存待处理的范围
        pendingRange = range

        // 使用防抖机制
        // _Requirements: 6.5 - 支持防抖机制以避免频繁的状态更新影响性能
        scheduleUpdate()
    }

    /// 处理工具栏格式切换
    ///
    /// 当用户通过工具栏点击格式按钮时调用此方法。
    /// 该方法负责：
    /// 1. 更新 currentFormatState 中对应格式的状态
    /// 2. 同步 typingAttributes 以确保后续输入应用新格式
    /// 3. 更新工具栏按钮状态以反映当前格式
    /// 4. 通知 FormatStateManager 以同步菜单栏状态
    ///
    /// - Parameter format: 要切换的格式
    /// _Requirements: 4.1-4.6, 6.3_
    public func handleToolbarFormatToggle(_ format: TextFormat) {
        // 更新当前格式状态
        var newState = currentFormatState

        // 切换格式状态
        switch format {
        case .bold:
            newState.isBold.toggle()
        case .italic:
            newState.isItalic.toggle()
        case .underline:
            newState.isUnderline.toggle()
        case .strikethrough:
            newState.isStrikethrough.toggle()
        case .highlight:
            newState.isHighlight.toggle()
        case .quote:
            newState.isQuote.toggle()
        case .heading1:
            newState.paragraphFormat = (newState.paragraphFormat == .heading1) ? .body : .heading1
        case .heading2:
            newState.paragraphFormat = (newState.paragraphFormat == .heading2) ? .body : .heading2
        case .heading3:
            newState.paragraphFormat = (newState.paragraphFormat == .heading3) ? .body : .heading3
        case .bulletList:
            newState.paragraphFormat = (newState.paragraphFormat == .bulletList) ? .body : .bulletList
        case .numberedList:
            newState.paragraphFormat = (newState.paragraphFormat == .numberedList) ? .body : .numberedList
        case .checkbox:
            newState.paragraphFormat = (newState.paragraphFormat == .checkbox) ? .body : .checkbox
        case .alignCenter:
            newState.alignment = (newState.alignment == .center) ? .left : .center
        case .alignRight:
            newState.alignment = (newState.alignment == .right) ? .left : .right
        case .horizontalRule:
            return
        }

        currentFormatState = newState

        syncTypingAttributes(with: newState)
        updateToolbarState(with: newState)
        notifyFormatStateManager(with: newState)
    }

    /// 强制刷新格式状态
    public func forceRefresh() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        performUpdate()
    }
}

// MARK: - Private Methods - 格式检测

extension CursorFormatManager {

    /// 检测光标位置的格式状态
    /// - Parameter position: 光标位置
    /// - Returns: 格式状态
    private func detectFormatState(at position: Int) -> FormatState {
        guard let textView else { return FormatState.default }
        guard let textStorage = textView.textStorage else { return FormatState.default }
        guard textStorage.length > 0 else { return FormatState.default }
        guard position > 0 else { return FormatState.default }

        let attributePosition = min(position - 1, textStorage.length - 1)
        guard attributePosition >= 0 else { return FormatState.default }

        let attributes = textStorage.attributes(at: attributePosition, effectiveRange: nil)
        var state = FormatState()

        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            let fontName = font.fontName.lowercased()

            if traits.contains(.bold) || fontName.contains("bold") {
                state.isBold = true
            }
            if traits.contains(.italic) || fontName.contains("italic") || fontName.contains("oblique") {
                state.isItalic = true
            }

            let detectedFormat = FontSizeManager.shared.detectParagraphFormat(fontSize: font.pointSize)
            if detectedFormat != .body {
                state.paragraphFormat = detectedFormat
            }
        }

        if let obliqueness = attributes[.obliqueness] as? Double, obliqueness > 0 {
            state.isItalic = true
        }
        if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
            state.isUnderline = true
        }
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
            state.isStrikethrough = true
        }
        if let backgroundColor = attributes[.backgroundColor] as? NSColor {
            if backgroundColor.alphaComponent > 0.1, backgroundColor != .clear, backgroundColor != .white {
                state.isHighlight = true
            }
        }
        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            switch paragraphStyle.alignment {
            case .center: state.alignment = .center
            case .right: state.alignment = .right
            default: state.alignment = .left
            }
        }
        if let isQuote = attributes[.quoteBlock] as? Bool, isQuote {
            state.isQuote = true
        }
        if let listType = attributes[.listType] {
            if let listTypeEnum = listType as? ListType {
                switch listTypeEnum {
                case .bullet: state.paragraphFormat = .bulletList
                case .ordered: state.paragraphFormat = .numberedList
                case .checkbox: state.paragraphFormat = .checkbox
                case .none: break
                }
            } else if let listTypeString = listType as? String {
                switch listTypeString {
                case "bullet": state.paragraphFormat = .bulletList
                case "ordered", "order": state.paragraphFormat = .numberedList
                case "checkbox": state.paragraphFormat = .checkbox
                default: break
                }
            }
        }
        if state.paragraphFormat.isList {
            if let listIndent = attributes[.listIndent] as? Int {
                state.listIndent = listIndent
            }
            if state.paragraphFormat == .numberedList, let listNumber = attributes[.listNumber] as? Int {
                state.listNumber = listNumber
            }
        }

        return state
    }

    private func handleDetectionError(_ error: CursorFormatDetectionError) {
        let defaultState = FormatState.default
        currentFormatState = defaultState
        syncTypingAttributes(with: defaultState)
        updateToolbarState(with: defaultState)
        notifyFormatStateManager(with: defaultState)
    }
}

// MARK: - Private Methods - 防抖机制

extension CursorFormatManager {

    /// 调度更新（使用防抖）
    /// _Requirements: 6.5_
    private func scheduleUpdate() {
        // 取消之前的定时器
        debounceTimer?.invalidate()

        // 设置新的定时器
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performUpdate()
            }
        }
    }

    /// 执行更新
    ///
    /// 此方法是光标位置变化处理的核心，负责：
    /// 1. 检测是否为光标模式（无选择）或选择模式
    /// 2. 在光标模式下：检测光标前一个字符的格式，同步 typingAttributes
    /// 3. 在选择模式下：检测选中文字的格式（使用选择起始位置的格式）
    /// 4. 更新工具栏状态和通知 FormatStateManager
    ///
    /// _Requirements: 3.1, 6.2_
    private func performUpdate() {
        guard let range = pendingRange else { return }

        let isCursorMode = range.length == 0

        if isCursorMode {
            let position = range.location
            let state: FormatState
            if UnifiedFormatManager.shared.isRegistered {
                state = UnifiedFormatManager.shared.detectFormatState(at: position)
            } else {
                state = detectFormatState(at: position)
            }

            currentFormatState = state
            currentFormatState.hasSelection = false
            currentFormatState.selectionLength = 0

            syncTypingAttributes(with: state)
            updateToolbarState(with: state)
            notifyFormatStateManager(with: state)
        } else {
            let position = range.location
            var state: FormatState
            if UnifiedFormatManager.shared.isRegistered {
                state = UnifiedFormatManager.shared.detectFormatState(in: range)
            } else {
                state = detectFormatState(at: position)
            }

            state.hasSelection = true
            state.selectionLength = range.length
            currentFormatState = state

            updateToolbarState(with: state)
            notifyFormatStateManager(with: state)
        }

        pendingRange = nil
    }
}

// MARK: - Private Methods - 状态同步

extension CursorFormatManager {

    /// 同步 typingAttributes
    /// - Parameter state: 格式状态
    /// _Requirements: 3.1, 3.4, 10.3_
    private func syncTypingAttributes(with state: FormatState) {
        guard let textView else { return }

        let isInTitleParagraph = checkIfInTitleParagraph()

        if isInTitleParagraph {
            var titleAttributes = textView.typingAttributes
            titleAttributes[.font] = NSFont.systemFont(ofSize: 40, weight: .semibold)
            titleAttributes[.foregroundColor] = NSColor.labelColor
            textView.typingAttributes = titleAttributes
        } else {
            let attributes = FormatAttributesBuilder.build(from: state)
            textView.typingAttributes = attributes
        }
    }

    /// 检查当前光标是否在标题段落中
    /// - Returns: 是否在标题段落中
    private func checkIfInTitleParagraph() -> Bool {
        guard let textView,
              let textStorage = textView.textStorage
        else {
            return false
        }

        let selectedRange = textView.selectedRange()
        let cursorPosition = selectedRange.location

        // 检查光标位置是否在标题段落中
        if cursorPosition < textStorage.length {
            // 获取光标所在行的范围
            let string = textStorage.string as NSString
            let lineRange = string.lineRange(for: NSRange(location: cursorPosition, length: 0))

            // 检查该行是否有 .isTitle 属性
            if lineRange.location < textStorage.length {
                let attributes = textStorage.attributes(at: lineRange.location, effectiveRange: nil)
                if let isTitle = attributes[.isTitle] as? Bool, isTitle {
                    return true
                }
            }
        }

        return false
    }

    /// 更新工具栏状态
    /// - Parameter state: 格式状态
    /// _Requirements: 1.1-1.6, 4.6_
    private func updateToolbarState(with state: FormatState) {
        guard let editorContext else { return }

        let formats = state.toTextFormats()
        editorContext.currentFormats = formats

        for format in TextFormat.allCases {
            editorContext.toolbarButtonStates[format] = state.isFormatActive(format)
        }
    }

    private func notifyFormatStateManager(with state: FormatState) {
        NotificationCenter.default.post(
            name: .formatStateDidChange,
            object: self,
            userInfo: ["state": state]
        )

        if let editorContext {
            editorContext.formatProvider.forceStateUpdate()
        }
    }
}

// MARK: - FormatAttributesBuilder

// FormatAttributesBuilder 已移至单独的文件: FormatAttributesBuilder.swift
// _Requirements: 2.1-2.6, 3.1_
