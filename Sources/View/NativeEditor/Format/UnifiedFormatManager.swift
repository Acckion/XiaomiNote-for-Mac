//
//  UnifiedFormatManager.swift
//  MiNoteMac
//
//  统一格式管理器 - 整合所有格式处理逻辑
//  负责格式应用、换行继承和 typingAttributes 同步的统一处理
//
//

import AppKit
import Combine
import Foundation

// MARK: - 格式分类枚举

/// 格式分类枚举
/// 用于区分不同类型的格式，决定换行继承规则
public enum FormatCategory: Equatable, Sendable {
    /// 内联格式：加粗、斜体、下划线、删除线、高亮
    case inline

    /// 块级标题：大标题、二级标题、三级标题
    case blockTitle

    /// 块级列表：有序列表、无序列表、Checkbox
    case blockList

    /// 块级引用
    case blockQuote

    /// 对齐属性：左对齐、居中、右对齐
    case alignment
}

// MARK: - TextFormat 扩展

public extension TextFormat {

    /// 获取格式的分类
    var category: FormatCategory {
        switch self {
        case .bold, .italic, .underline, .strikethrough, .highlight:
            .inline
        case .heading1, .heading2, .heading3:
            .blockTitle
        case .bulletList, .numberedList, .checkbox:
            .blockList
        case .quote:
            .blockQuote
        case .alignCenter, .alignRight:
            .alignment
        case .horizontalRule:
            // 分割线是插入操作，归类为内联
            .inline
        }
    }

    /// 是否应该在换行时继承
    ///
    /// 换行继承规则：
    /// - 内联格式（加粗、斜体等）：不继承
    /// - 标题格式：不继承
    /// - 列表格式：继承（非空列表项）
    /// - 引用格式：继承
    /// - 对齐属性：继承
    ///
    var shouldInheritOnNewLine: Bool {
        switch category {
        case .inline, .blockTitle:
            false
        case .blockList, .blockQuote, .alignment:
            true
        }
    }
}

// MARK: - 换行上下文结构体

/// 换行上下文
/// 包含换行时需要的所有信息
public struct NewLineContext: Equatable, Sendable {

    /// 当前行的范围
    public let currentLineRange: NSRange

    /// 当前行的块级格式（如果有）
    public let currentBlockFormat: TextFormat?

    /// 当前行的对齐方式
    public let currentAlignment: NSTextAlignment

    /// 列表项是否为空（仅对列表格式有效）
    public let isListItemEmpty: Bool

    /// 是否应该继承格式
    public var shouldInheritFormat: Bool {
        guard let format = currentBlockFormat else {
            // 没有块级格式，不需要继承
            return false
        }

        // 列表格式：空列表项不继承
        if format.category == .blockList, isListItemEmpty {
            return false
        }

        // 其他情况根据格式类型决定
        return format.shouldInheritOnNewLine
    }

    /// 初始化
    public init(
        currentLineRange: NSRange,
        currentBlockFormat: TextFormat?,
        currentAlignment: NSTextAlignment,
        isListItemEmpty: Bool
    ) {
        self.currentLineRange = currentLineRange
        self.currentBlockFormat = currentBlockFormat
        self.currentAlignment = currentAlignment
        self.isListItemEmpty = isListItemEmpty
    }

    /// 默认上下文（用于空文档或无法检测的情况）
    public static let `default` = NewLineContext(
        currentLineRange: NSRange(location: 0, length: 0),
        currentBlockFormat: nil,
        currentAlignment: .left,
        isListItemEmpty: false
    )
}

// MARK: - 统一格式管理器

/// 统一格式管理器
/// 整合所有格式处理逻辑，提供统一的 API
@MainActor
public final class UnifiedFormatManager {

    // MARK: - 单例

    /// 共享实例
    public static let shared = UnifiedFormatManager()

    // MARK: - 属性

    /// 当前关联的 NSTextView（弱引用）
    private weak var textView: NSTextView?

    /// 当前关联的 NativeEditorContext（弱引用）
    private weak var editorContext: NativeEditorContext?

    /// 是否已注册
    public private(set) var isRegistered = false

    // MARK: - 初始化

    private init() {}

    // MARK: - 注册/注销

    /// 注册编辑器组件
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - context: NativeEditorContext 实例
    public func register(textView: NSTextView, context: NativeEditorContext) {
        self.textView = textView
        editorContext = context
        isRegistered = true
    }

    /// 取消注册
    public func unregister() {
        textView = nil
        editorContext = nil
        isRegistered = false
    }

    // MARK: - 公共方法 - 内联格式应用

    /// 应用内联格式到选中文本
    ///
    /// 使用 InlineFormatHandler 统一处理所有内联格式
    ///
    /// - Parameters:
    ///   - format: 要应用的内联格式
    ///   - range: 应用范围
    ///   - toggle: 是否切换模式（默认 true）
    public func applyInlineFormat(_ format: TextFormat, to range: NSRange, toggle: Bool = true) {
        guard let textStorage = currentTextStorage else {
            return
        }

        guard format.category == .inline else {
            return
        }

        InlineFormatHandler.apply(format, to: range, in: textStorage, toggle: toggle)
    }

    /// 应用多个内联格式到选中文本
    ///
    /// 确保多个内联格式可以同时生效
    ///
    /// - Parameters:
    ///   - formats: 要应用的内联格式集合
    ///   - range: 应用范围
    ///   - toggle: 是否切换模式（默认 true）
    public func applyMultipleInlineFormats(_ formats: Set<TextFormat>, to range: NSRange, toggle: Bool = true) {
        guard let textStorage = currentTextStorage else {
            return
        }

        InlineFormatHandler.applyMultiple(formats, to: range, in: textStorage, toggle: toggle)
    }

    /// 检测指定位置的内联格式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 当前位置激活的内联格式集合
    public func detectInlineFormats(at position: Int) -> Set<TextFormat> {
        guard let textStorage = currentTextStorage else {
            return []
        }

        return InlineFormatHandler.detect(at: position, in: textStorage)
    }

    /// 构建不包含内联格式的 typingAttributes
    ///
    /// 用于换行后清除内联格式
    ///
    /// - Parameter baseAttributes: 基础属性（可选）
    /// - Returns: 清除内联格式后的属性字典
    public func buildCleanTypingAttributes(from baseAttributes: [NSAttributedString.Key: Any]? = nil) -> [NSAttributedString.Key: Any] {
        InlineFormatHandler.buildCleanTypingAttributes(from: baseAttributes)
    }

    // MARK: - 公共方法 - 块级格式应用

    /// 应用块级格式到选中文本
    ///
    /// 使用 BlockFormatHandler 统一处理所有块级格式
    ///
    /// - Parameters:
    ///   - format: 要应用的块级格式
    ///   - range: 应用范围
    ///   - toggle: 是否切换模式（默认 true）
    public func applyBlockFormat(_ format: TextFormat, to range: NSRange, toggle: Bool = true) {
        guard let textStorage = currentTextStorage else {
            return
        }

        guard BlockFormatHandler.isBlockFormat(format) else {
            return
        }

        BlockFormatHandler.apply(format, to: range, in: textStorage, toggle: toggle)
    }

    /// 检测指定位置的块级格式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 当前位置的块级格式（如果有）
    public func detectBlockFormat(at position: Int) -> TextFormat? {
        guard let textStorage = currentTextStorage else {
            return nil
        }

        return BlockFormatHandler.detect(at: position, in: textStorage)
    }

    /// 检测指定位置的对齐方式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 当前位置的对齐方式
    public func detectAlignment(at position: Int) -> NSTextAlignment {
        guard let textStorage = currentTextStorage else {
            return .left
        }

        return BlockFormatHandler.detectAlignment(at: position, in: textStorage)
    }

    /// 移除块级格式
    ///
    /// - Parameters:
    ///   - range: 移除范围
    public func removeBlockFormat(from range: NSRange) {
        guard let textStorage = currentTextStorage else {
            return
        }

        BlockFormatHandler.removeBlockFormat(from: range, in: textStorage)
    }

    /// 检测列表项是否为空
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 是否为空列表项
    public func isListItemEmpty(at position: Int) -> Bool {
        guard let textStorage = currentTextStorage else {
            return false
        }

        return BlockFormatHandler.isListItemEmpty(at: position, in: textStorage)
    }

    /// 获取指定位置的列表类型
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 列表类型（bulletList、numberedList、checkbox 或 nil）
    public func getListType(at position: Int) -> TextFormat? {
        guard let textStorage = currentTextStorage else {
            return nil
        }

        return BlockFormatHandler.getListType(at: position, in: textStorage)
    }

    /// 检测是否是列表格式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 是否是列表格式
    public func isList(at position: Int) -> Bool {
        guard let textStorage = currentTextStorage else {
            return false
        }

        return BlockFormatHandler.isList(at: position, in: textStorage)
    }

    /// 构建换行上下文
    ///
    /// - Parameters:
    ///   - position: 当前光标位置
    /// - Returns: 换行上下文
    public func buildNewLineContext(at position: Int) -> NewLineContext {
        guard let textStorage = currentTextStorage else {
            return .default
        }

        let string = textStorage.string as NSString

        // 计算安全位置，用于获取当前行范围
        // 当光标在换行符位置时，使用前一个位置来获取当前行
        let safePositionForLineRange: Int
        if position > 0, position < textStorage.length {
            let charAtPosition = string.character(at: position)
            if charAtPosition == 0x0A { // 换行符 \n
                safePositionForLineRange = position - 1
            } else {
                safePositionForLineRange = position
            }
        } else if position >= textStorage.length, textStorage.length > 0 {
            safePositionForLineRange = textStorage.length - 1
        } else {
            safePositionForLineRange = position
        }

        let lineRange = string.lineRange(for: NSRange(location: safePositionForLineRange, length: 0))

        // 使用安全位置来检测格式
        let blockFormat: TextFormat? = if safePositionForLineRange < textStorage.length {
            BlockFormatHandler.detect(at: safePositionForLineRange, in: textStorage)
        } else if safePositionForLineRange > 0 {
            BlockFormatHandler.detect(at: safePositionForLineRange - 1, in: textStorage)
        } else {
            nil
        }

        let alignment: NSTextAlignment = if safePositionForLineRange < textStorage.length {
            BlockFormatHandler.detectAlignment(at: safePositionForLineRange, in: textStorage)
        } else if safePositionForLineRange > 0 {
            BlockFormatHandler.detectAlignment(at: safePositionForLineRange - 1, in: textStorage)
        } else {
            .left
        }

        let isListEmpty = BlockFormatHandler.isListItemEmpty(at: position, in: textStorage)

        return NewLineContext(
            currentLineRange: lineRange,
            currentBlockFormat: blockFormat,
            currentAlignment: alignment,
            isListItemEmpty: isListEmpty
        )
    }

    // MARK: - 公共方法 - 格式应用（统一入口）

    /// 应用格式到选中文本（统一入口）
    ///
    /// 根据格式类型调用对应的处理器：
    /// - 内联格式：调用 InlineFormatHandler
    /// - 块级格式：调用 BlockFormatHandler
    ///
    /// - Parameters:
    ///   - format: 要应用的格式
    ///   - range: 应用范围
    public func applyFormat(_ format: TextFormat, to range: NSRange) {
        switch format.category {
        case .inline:
            applyInlineFormat(format, to: range)
        case .blockTitle, .blockList, .blockQuote, .alignment:
            applyBlockFormat(format, to: range)
        }
    }

    // MARK: - 公共方法 - 换行处理

    /// 处理换行
    ///
    /// 根据当前行的格式类型决定换行行为：
    /// - 内联格式：清除，不继承
    /// - 标题格式：清除，新行变为普通正文
    /// - 列表格式：非空时继承，空时取消格式
    /// - 引用格式：继承
    /// - 对齐属性：继承
    ///
    /// - Returns: 是否已处理换行（true 表示已处理，调用方不需要执行默认行为）
    public func handleNewLine() -> Bool {
        guard let textView = currentTextView else {
            return false
        }

        // 构建换行上下文
        let context = NewLineContext.build(from: textView)

        // 调用 NewLineHandler 处理换行
        return NewLineHandler.handleNewLine(context: context, textView: textView)
    }

    // MARK: - 公共方法 - 格式检测

    /// 检测光标位置的格式状态
    ///
    /// 检测指定位置的完整格式状态，包括：
    /// - 内联格式（加粗、斜体、下划线、删除线、高亮）
    /// - 块级格式（标题、列表、引用）
    /// - 对齐属性
    ///
    /// - Parameter position: 光标位置
    /// - Returns: 完整的格式状态
    public func detectFormatState(at position: Int) -> FormatState {
        guard let textStorage = currentTextStorage else {
            return FormatState.default
        }

        guard let textView = currentTextView else {
            return FormatState.default
        }

        // 获取选择信息
        let selectedRange = textView.selectedRange()
        let hasSelection = selectedRange.length > 0
        let selectionLength = selectedRange.length

        // 确定检测位置
        let detectPosition: Int
        if hasSelection {
            // 有选择时，使用选择起始位置
            detectPosition = selectedRange.location
        } else if position > 0, position <= textStorage.length {
            // 无选择时，使用前一个字符的位置（更符合用户预期）
            detectPosition = position - 1
        } else if position < textStorage.length {
            detectPosition = position
        } else {
            // 空文档或文档末尾
            return FormatState(hasSelection: hasSelection, selectionLength: selectionLength)
        }

        // 确保位置有效
        guard detectPosition >= 0, detectPosition < textStorage.length else {
            return FormatState(hasSelection: hasSelection, selectionLength: selectionLength)
        }

        // 获取属性
        let attributes = textStorage.attributes(at: detectPosition, effectiveRange: nil)

        // 构建格式状态
        var state = FormatState()
        state.hasSelection = hasSelection
        state.selectionLength = selectionLength

        // 检测内联格式
        state.isBold = InlineFormatHandler.isFormatActive(.bold, in: attributes)
        state.isItalic = InlineFormatHandler.isFormatActive(.italic, in: attributes)
        state.isUnderline = InlineFormatHandler.isFormatActive(.underline, in: attributes)
        state.isStrikethrough = InlineFormatHandler.isFormatActive(.strikethrough, in: attributes)
        state.isHighlight = InlineFormatHandler.isFormatActive(.highlight, in: attributes)

        // 检测块级格式
        if let blockFormat = BlockFormatHandler.detect(at: detectPosition, in: textStorage) {
            switch blockFormat {
            case .heading1:
                state.paragraphFormat = .heading1
            case .heading2:
                state.paragraphFormat = .heading2
            case .heading3:
                state.paragraphFormat = .heading3
            case .bulletList:
                state.paragraphFormat = .bulletList
            case .numberedList:
                state.paragraphFormat = .numberedList
            case .checkbox:
                state.paragraphFormat = .checkbox
            case .quote:
                state.isQuote = true
            default:
                break
            }
        }

        // 检测列表属性（缩进级别和编号）
        if state.paragraphFormat.isList {
            // 获取列表缩进级别
            if let listIndent = attributes[.listIndent] as? Int {
                state.listIndent = listIndent
            } else {
                // 尝试从 ListFormatHandler 获取
                state.listIndent = ListFormatHandler.getListIndent(in: textStorage, at: detectPosition)
            }

            // 获取列表编号（仅有序列表）
            if state.paragraphFormat == .numberedList {
                if let listNumber = attributes[.listNumber] as? Int {
                    state.listNumber = listNumber
                } else {
                    // 尝试从 ListFormatHandler 获取
                    state.listNumber = ListFormatHandler.getListNumber(in: textStorage, at: detectPosition)
                }
            }
        }

        // 检测对齐属性
        let alignment = BlockFormatHandler.detectAlignment(at: detectPosition, in: textStorage)
        switch alignment {
        case .center:
            state.alignment = .center
        case .right:
            state.alignment = .right
        default:
            state.alignment = .left
        }

        return state
    }

    /// 检测选择范围的格式状态
    ///
    /// 对于选择范围，检测所有字符共有的格式
    ///
    /// - Parameter range: 选择范围
    /// - Returns: 完整的格式状态
    public func detectFormatState(in range: NSRange) -> FormatState {
        guard let textStorage = currentTextStorage else {
            return FormatState.default
        }

        guard range.length > 0 else {
            return detectFormatState(at: range.location)
        }

        // 初始化状态（假设所有格式都激活）
        var state = FormatState()
        state.hasSelection = true
        state.selectionLength = range.length
        state.isBold = true
        state.isItalic = true
        state.isUnderline = true
        state.isStrikethrough = true
        state.isHighlight = true

        // 遍历范围内的所有字符，检测共有格式
        var isFirstChar = true
        textStorage.enumerateAttributes(in: range, options: []) { attributes, _, _ in
            if isFirstChar {
                // 第一个字符，设置初始状态
                state.isBold = InlineFormatHandler.isFormatActive(.bold, in: attributes)
                state.isItalic = InlineFormatHandler.isFormatActive(.italic, in: attributes)
                state.isUnderline = InlineFormatHandler.isFormatActive(.underline, in: attributes)
                state.isStrikethrough = InlineFormatHandler.isFormatActive(.strikethrough, in: attributes)
                state.isHighlight = InlineFormatHandler.isFormatActive(.highlight, in: attributes)
                isFirstChar = false
            } else {
                // 后续字符，只保留共有格式
                if state.isBold, !InlineFormatHandler.isFormatActive(.bold, in: attributes) {
                    state.isBold = false
                }
                if state.isItalic, !InlineFormatHandler.isFormatActive(.italic, in: attributes) {
                    state.isItalic = false
                }
                if state.isUnderline, !InlineFormatHandler.isFormatActive(.underline, in: attributes) {
                    state.isUnderline = false
                }
                if state.isStrikethrough, !InlineFormatHandler.isFormatActive(.strikethrough, in: attributes) {
                    state.isStrikethrough = false
                }
                if state.isHighlight, !InlineFormatHandler.isFormatActive(.highlight, in: attributes) {
                    state.isHighlight = false
                }
            }
        }

        // 块级格式使用范围起始位置检测
        if let blockFormat = BlockFormatHandler.detect(at: range.location, in: textStorage) {
            switch blockFormat {
            case .heading1:
                state.paragraphFormat = .heading1
            case .heading2:
                state.paragraphFormat = .heading2
            case .heading3:
                state.paragraphFormat = .heading3
            case .bulletList:
                state.paragraphFormat = .bulletList
            case .numberedList:
                state.paragraphFormat = .numberedList
            case .checkbox:
                state.paragraphFormat = .checkbox
            case .quote:
                state.isQuote = true
            default:
                break
            }
        }

        // 对齐属性使用范围起始位置检测
        let alignment = BlockFormatHandler.detectAlignment(at: range.location, in: textStorage)
        switch alignment {
        case .center:
            state.alignment = .center
        case .right:
            state.alignment = .right
        default:
            state.alignment = .left
        }

        return state
    }

    // MARK: - 公共方法 - typingAttributes 同步

    /// 同步 typingAttributes
    ///
    /// 根据上下文设置 typingAttributes：
    /// - 换行后：清除内联格式，保留需要继承的格式
    /// - 光标移动后：根据当前位置的格式状态同步
    /// - 格式应用后：更新 typingAttributes 以反映新格式
    ///
    /// - Parameter newLineContext: 换行上下文（可选，用于换行后的同步）
    public func syncTypingAttributes(for newLineContext: NewLineContext? = nil) {
        guard let textView = currentTextView else {
            return
        }

        if let context = newLineContext {
            // 换行后的同步：根据继承规则设置 typingAttributes
            syncTypingAttributesAfterNewLine(context: context, textView: textView)
        } else {
            // 光标移动或格式应用后的同步
            syncTypingAttributesAtCursor(textView: textView)
        }
    }

    /// 换行后同步 typingAttributes
    ///
    /// 根据换行上下文设置新行的 typingAttributes：
    /// - 清除所有内联格式
    /// - 保留需要继承的块级格式
    /// - 保留对齐属性
    ///
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    private func syncTypingAttributesAfterNewLine(context: NewLineContext, textView: NSTextView) {
        // 构建清除内联格式后的基础属性
        var attrs = InlineFormatHandler.buildCleanTypingAttributes()

        // 设置对齐属性
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = context.currentAlignment
        attrs[.paragraphStyle] = paragraphStyle

        // 根据块级格式设置继承属性
        if context.shouldInheritFormat, let blockFormat = context.currentBlockFormat {
            switch blockFormat {
            case .bulletList:
                attrs[.listType] = ListType.bullet
                attrs[.listIndent] = 1

            case .numberedList:
                attrs[.listType] = ListType.ordered
                attrs[.listIndent] = 1

            case .checkbox:
                attrs[.listType] = ListType.checkbox
                attrs[.listIndent] = 1
                attrs[.checkboxLevel] = 3

            case .quote:
                attrs[.quoteBlock] = true
                attrs[.quoteIndent] = 1
                // 设置引用块背景色
                let quoteBackgroundColor = NSColor.systemBlue.withAlphaComponent(0.05)
                attrs[.backgroundColor] = quoteBackgroundColor

            default:
                break
            }
        }

        textView.typingAttributes = attrs
    }

    /// 光标位置同步 typingAttributes
    ///
    /// 根据当前光标位置的格式状态同步 typingAttributes
    ///
    /// - Parameter textView: NSTextView 实例
    private func syncTypingAttributesAtCursor(textView: NSTextView) {
        guard let textStorage = textView.textStorage else {
            return
        }

        let selectedRange = textView.selectedRange()
        let position = selectedRange.location

        // 如果有选中文本，不需要同步 typingAttributes
        if selectedRange.length > 0 {
            return
        }

        // 获取当前位置的属性
        var attrs: [NSAttributedString.Key: Any] = if position > 0, position <= textStorage.length {
            // 使用前一个字符的属性
            textStorage.attributes(at: position - 1, effectiveRange: nil)
        } else if position < textStorage.length {
            // 使用当前位置的属性
            textStorage.attributes(at: position, effectiveRange: nil)
        } else {
            // 空文档或文档末尾，使用默认属性
            InlineFormatHandler.buildCleanTypingAttributes()
        }

        textView.typingAttributes = attrs
    }

    // MARK: - 辅助方法

    /// 获取当前 textView
    /// - Returns: NSTextView 实例，如果未注册则返回 nil
    public var currentTextView: NSTextView? {
        textView
    }

    /// 获取当前 editorContext
    /// - Returns: NativeEditorContext 实例，如果未注册则返回 nil
    public var currentEditorContext: NativeEditorContext? {
        editorContext
    }

    /// 获取当前 textStorage
    /// - Returns: NSTextStorage 实例，如果未注册则返回 nil
    public var currentTextStorage: NSTextStorage? {
        textView?.textStorage
    }
}
