//
//  FormatState.swift
//  MiNoteMac
//
//  格式状态结构体 - 表示当前光标或选择处的完整格式状态
//  用于统一格式菜单系统，确保工具栏和菜单栏显示一致的格式状态
//
//

import Foundation

// MARK: - 段落格式枚举

/// 段落格式枚举
/// 定义所有互斥的段落级格式类型
public enum ParagraphFormat: String, CaseIterable, Equatable, Hashable, Sendable {
    case heading1 // 大标题
    case heading2 // 二级标题
    case heading3 // 三级标题
    case body // 正文
    case bulletList // 无序列表
    case numberedList // 有序列表
    case checkbox // 复选框

    /// 格式的显示名称
    public var displayName: String {
        switch self {
        case .heading1: "大标题"
        case .heading2: "二级标题"
        case .heading3: "三级标题"
        case .body: "正文"
        case .bulletList: "无序列表"
        case .numberedList: "有序列表"
        case .checkbox: "复选框"
        }
    }

    /// 是否是标题格式
    public var isHeading: Bool {
        switch self {
        case .heading1, .heading2, .heading3:
            true
        default:
            false
        }
    }

    /// 是否是列表格式
    public var isList: Bool {
        switch self {
        case .bulletList, .numberedList, .checkbox:
            true
        default:
            false
        }
    }

    /// 转换为 TextFormat（用于与现有系统兼容）
    public var textFormat: TextFormat? {
        switch self {
        case .heading1: .heading1
        case .heading2: .heading2
        case .heading3: .heading3
        case .body: nil // 正文是默认状态，没有对应的 TextFormat
        case .bulletList: .bulletList
        case .numberedList: .numberedList
        case .checkbox: .checkbox
        }
    }

    /// 从 TextFormat 创建 ParagraphFormat
    public static func from(_ textFormat: TextFormat) -> ParagraphFormat? {
        switch textFormat {
        case .heading1: .heading1
        case .heading2: .heading2
        case .heading3: .heading3
        case .bulletList: .bulletList
        case .numberedList: .numberedList
        case .checkbox: .checkbox
        default: nil
        }
    }
}

// MARK: - 对齐格式枚举

/// 对齐格式枚举
/// 定义所有互斥的对齐方式
public enum AlignmentFormat: String, CaseIterable, Equatable, Hashable, Sendable {
    case left // 左对齐（默认）
    case center // 居中对齐
    case right // 右对齐

    /// 格式的显示名称
    public var displayName: String {
        switch self {
        case .left: "左对齐"
        case .center: "居中"
        case .right: "右对齐"
        }
    }

    /// 转换为 TextFormat（用于与现有系统兼容）
    public var textFormat: TextFormat? {
        switch self {
        case .left: nil // 左对齐是默认状态
        case .center: .alignCenter
        case .right: .alignRight
        }
    }

    /// 从 TextFormat 创建 AlignmentFormat
    public static func from(_ textFormat: TextFormat) -> AlignmentFormat? {
        switch textFormat {
        case .alignCenter: .center
        case .alignRight: .right
        default: nil
        }
    }
}

// MARK: - 格式状态结构体

/// 格式状态结构体
/// 表示当前光标或选择处的完整格式状态
public struct FormatState: Equatable, Sendable {

    // MARK: - 段落级格式

    /// 当前段落格式（互斥）
    public var paragraphFormat: ParagraphFormat = .body

    // MARK: - 对齐格式

    /// 当前对齐方式（互斥）
    public var alignment: AlignmentFormat = .left

    // MARK: - 字符级格式（可叠加）

    /// 是否加粗
    public var isBold = false

    /// 是否斜体
    public var isItalic = false

    /// 是否下划线
    public var isUnderline = false

    /// 是否删除线
    public var isStrikethrough = false

    /// 是否高亮
    public var isHighlight = false

    // MARK: - 独立格式

    /// 是否引用块
    public var isQuote = false

    // MARK: - 列表属性

    /// 列表缩进级别（仅当 paragraphFormat 为列表类型时有效）
    /// 默认为 1，表示第一级缩进
    public var listIndent = 1

    /// 列表编号（仅当 paragraphFormat 为 .numberedList 时有效）
    /// 默认为 1
    public var listNumber = 1

    // MARK: - 选择模式信息

    /// 是否有选中文本
    public var hasSelection = false

    /// 选择范围长度
    public var selectionLength = 0

    // MARK: - 初始化

    /// 默认初始化
    public init() {}

    /// 完整初始化
    public init(
        paragraphFormat: ParagraphFormat = .body,
        alignment: AlignmentFormat = .left,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        isStrikethrough: Bool = false,
        isHighlight: Bool = false,
        isQuote: Bool = false,
        listIndent: Int = 1,
        listNumber: Int = 1,
        hasSelection: Bool = false,
        selectionLength: Int = 0
    ) {
        self.paragraphFormat = paragraphFormat
        self.alignment = alignment
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.isStrikethrough = isStrikethrough
        self.isHighlight = isHighlight
        self.isQuote = isQuote
        self.listIndent = listIndent
        self.listNumber = listNumber
        self.hasSelection = hasSelection
        self.selectionLength = selectionLength
    }

    // MARK: - 便捷方法

    /// 从 TextFormat 集合创建 FormatState
    /// 用于与现有系统兼容
    public static func from(formats: Set<TextFormat>, hasSelection: Bool = false, selectionLength: Int = 0) -> FormatState {
        var state = FormatState()
        state.hasSelection = hasSelection
        state.selectionLength = selectionLength

        // 检测段落格式
        if formats.contains(.heading1) {
            state.paragraphFormat = .heading1
        } else if formats.contains(.heading2) {
            state.paragraphFormat = .heading2
        } else if formats.contains(.heading3) {
            state.paragraphFormat = .heading3
        } else if formats.contains(.bulletList) {
            state.paragraphFormat = .bulletList
        } else if formats.contains(.numberedList) {
            state.paragraphFormat = .numberedList
        } else if formats.contains(.checkbox) {
            state.paragraphFormat = .checkbox
        } else {
            state.paragraphFormat = .body
        }

        // 检测对齐格式
        if formats.contains(.alignCenter) {
            state.alignment = .center
        } else if formats.contains(.alignRight) {
            state.alignment = .right
        } else {
            state.alignment = .left
        }

        // 检测字符格式
        state.isBold = formats.contains(.bold)
        state.isItalic = formats.contains(.italic)
        state.isUnderline = formats.contains(.underline)
        state.isStrikethrough = formats.contains(.strikethrough)
        state.isHighlight = formats.contains(.highlight)

        // 检测引用块
        state.isQuote = formats.contains(.quote)

        return state
    }

    /// 转换为 TextFormat 集合
    /// 用于与现有系统兼容
    public func toTextFormats() -> Set<TextFormat> {
        var formats: Set<TextFormat> = []

        // 添加段落格式
        if let textFormat = paragraphFormat.textFormat {
            formats.insert(textFormat)
        }

        // 添加对齐格式
        if let textFormat = alignment.textFormat {
            formats.insert(textFormat)
        }

        // 添加字符格式
        if isBold { formats.insert(.bold) }
        if isItalic { formats.insert(.italic) }
        if isUnderline { formats.insert(.underline) }
        if isStrikethrough { formats.insert(.strikethrough) }
        if isHighlight { formats.insert(.highlight) }

        // 添加引用块
        if isQuote { formats.insert(.quote) }

        return formats
    }

    /// 检查指定格式是否激活
    public func isFormatActive(_ format: TextFormat) -> Bool {
        switch format {
        case .bold: isBold
        case .italic: isItalic
        case .underline: isUnderline
        case .strikethrough: isStrikethrough
        case .highlight: isHighlight
        case .heading1: paragraphFormat == .heading1
        case .heading2: paragraphFormat == .heading2
        case .heading3: paragraphFormat == .heading3
        case .alignCenter: alignment == .center
        case .alignRight: alignment == .right
        case .bulletList: paragraphFormat == .bulletList
        case .numberedList: paragraphFormat == .numberedList
        case .checkbox: paragraphFormat == .checkbox
        case .quote: isQuote
        case .horizontalRule: false // 分割线不是状态格式
        }
    }

    /// 默认格式状态（用于空文档或光标在文档开头）
    public static let `default` = FormatState()
}

// MARK: - CustomStringConvertible

extension FormatState: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []

        // 段落格式
        parts.append("段落: \(paragraphFormat.displayName)")

        // 对齐格式
        parts.append("对齐: \(alignment.displayName)")

        // 字符格式
        var charFormats: [String] = []
        if isBold { charFormats.append("加粗") }
        if isItalic { charFormats.append("斜体") }
        if isUnderline { charFormats.append("下划线") }
        if isStrikethrough { charFormats.append("删除线") }
        if isHighlight { charFormats.append("高亮") }
        if !charFormats.isEmpty {
            parts.append("字符: \(charFormats.joined(separator: ", "))")
        }

        // 引用块
        if isQuote {
            parts.append("引用块")
        }

        // 选择信息
        if hasSelection {
            parts.append("选择: \(selectionLength)字符")
        }

        return "FormatState(\(parts.joined(separator: ", ")))"
    }
}

// MARK: - ParagraphFormat 与 MenuItemTag 映射

extension ParagraphFormat {

    /// 对应的菜单项标签
    var menuItemTag: MenuItemTag {
        switch self {
        case .heading1: .heading
        case .heading2: .subheading
        case .heading3: .subtitle
        case .body: .bodyText
        case .bulletList: .unorderedList
        case .numberedList: .orderedList
        case .checkbox: .checklist
        }
    }

    /// 从菜单项标签创建段落格式
    static func from(tag: MenuItemTag) -> ParagraphFormat? {
        switch tag {
        case .heading: .heading1
        case .subheading: .heading2
        case .subtitle: .heading3
        case .bodyText: .body
        case .unorderedList: .bulletList
        case .orderedList: .numberedList
        case .checklist: .checkbox
        default: nil
        }
    }
}

// MARK: - AlignmentFormat 与 MenuItemTag 映射

extension AlignmentFormat {

    /// 对应的菜单项标签
    var menuItemTag: MenuItemTag {
        switch self {
        case .left: .alignLeft
        case .center: .alignCenter
        case .right: .alignRight
        }
    }

    /// 从菜单项标签创建对齐格式
    static func from(tag: MenuItemTag) -> AlignmentFormat? {
        switch tag {
        case .alignLeft: .left
        case .alignCenter: .center
        case .alignRight: .right
        default: nil
        }
    }
}
