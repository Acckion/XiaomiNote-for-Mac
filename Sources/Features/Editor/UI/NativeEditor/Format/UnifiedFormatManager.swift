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

    // MARK: - 属性

    /// 当前关联的 NSTextView（弱引用）
    private weak var textView: NSTextView?

    /// 当前关联的 NativeEditorContext（弱引用）
    private weak var editorContext: NativeEditorContext?

    /// 是否已注册
    public private(set) var isRegistered = false

    // MARK: - 初始化

    init() {}

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

    // MARK: - 统一入口

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

    // MARK: - 辅助属性

    /// 缩进单位（像素）
    var indentUnit: CGFloat {
        20
    }

    /// 设置缩进级别
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - level: 缩进级别
    func setIndentLevel(to textStorage: NSTextStorage, range: NSRange, level: Int) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        textStorage.beginEditing()

        let paragraphStyle = NSMutableParagraphStyle()
        let indentValue = CGFloat(max(0, level - 1)) * indentUnit
        paragraphStyle.firstLineHeadIndent = indentValue
        paragraphStyle.headIndent = indentValue

        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)

        textStorage.endEditing()
    }

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

    // MARK: - 错误处理

    /// 记录格式操作错误
    /// - Parameters:
    ///   - error: 格式错误
    ///   - context: 错误上下文描述
    func logFormatError(_ error: FormatError, context: String) {
        LogService.shared.error(.editor, "格式操作错误: \(error.errorDescription ?? "未知"), 上下文: \(context)")
    }
}
