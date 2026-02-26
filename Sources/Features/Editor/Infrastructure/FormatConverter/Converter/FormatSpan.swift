//
//  FormatSpan.swift
//  MiNoteMac
//
//  格式跨度数据结构
//  用于扁平化表示一段具有特定格式的文本
//  参考 ProseMirror 的 Mark 概念，将嵌套的格式树扁平化为格式集合
//

import Foundation

// MARK: - 格式跨度

/// 格式跨度 - 表示一段具有特定格式的文本（扁平化表示）
///
/// 这是解决格式边界问题的关键数据结构。
/// 参考 ProseMirror 的 Mark 概念，将嵌套的格式树扁平化为格式集合。
///
/// 例如：`<b><i>文本</i></b>` 表示为 FormatSpan(text: "文本", formats: [.bold, .italic])
///
/// 优势：
/// 1. 合并相邻相同格式变得简单（只需比较 formats 集合）
/// 2. 避免了嵌套树结构导致的边界处理复杂性
/// 3. 生成 XML 时可以按照固定顺序重建嵌套结构
public struct FormatSpan: Equatable, Sendable {
    /// 文本内容
    public var text: String

    /// 格式类型集合
    /// 包含应用于此文本的所有行内格式
    public var formats: Set<ASTNodeType>

    /// 高亮颜色值（仅当 formats 包含 .highlight 时有效）
    public var highlightColor: String?

    /// 创建格式跨度
    /// - Parameters:
    ///   - text: 文本内容
    ///   - formats: 格式类型集合
    ///   - highlightColor: 高亮颜色值（可选）
    public init(text: String, formats: Set<ASTNodeType> = [], highlightColor: String? = nil) {
        self.text = text
        self.formats = formats
        self.highlightColor = highlightColor
    }

    /// 检查两个跨度是否可以合并（格式完全相同）
    ///
    /// 合并条件：
    /// 1. 格式集合完全相同
    /// 2. 高亮颜色相同（如果有高亮格式）
    ///
    /// - Parameter other: 另一个格式跨度
    /// - Returns: 是否可以合并
    public func canMerge(with other: FormatSpan) -> Bool {
        formats == other.formats && highlightColor == other.highlightColor
    }

    /// 合并两个跨度
    ///
    /// 将两个格式相同的跨度合并为一个，文本内容拼接
    ///
    /// - Parameter other: 另一个格式跨度
    /// - Returns: 合并后的格式跨度
    /// - Note: 调用前应先使用 `canMerge(with:)` 检查是否可以合并
    public func merged(with other: FormatSpan) -> FormatSpan {
        FormatSpan(
            text: text + other.text,
            formats: formats,
            highlightColor: highlightColor
        )
    }

    /// 是否为空跨度（没有文本内容）
    public var isEmpty: Bool {
        text.isEmpty
    }

    /// 是否为纯文本（没有任何格式）
    public var isPlainText: Bool {
        formats.isEmpty
    }

    /// 是否包含粗体格式
    public var isBold: Bool {
        formats.contains(.bold)
    }

    /// 是否包含斜体格式
    public var isItalic: Bool {
        formats.contains(.italic)
    }

    /// 是否包含下划线格式
    public var isUnderline: Bool {
        formats.contains(.underline)
    }

    /// 是否包含删除线格式
    public var isStrikethrough: Bool {
        formats.contains(.strikethrough)
    }

    /// 是否包含高亮格式
    public var isHighlight: Bool {
        formats.contains(.highlight)
    }

    /// 是否包含标题格式（任意级别）
    public var isHeading: Bool {
        formats.contains(.heading1) || formats.contains(.heading2) || formats.contains(.heading3)
    }

    /// 是否包含对齐格式（居中或右对齐）
    public var isAligned: Bool {
        formats.contains(.centerAlign) || formats.contains(.rightAlign)
    }
}

// MARK: - 便捷构造方法

public extension FormatSpan {
    /// 创建纯文本跨度
    static func plain(_ text: String) -> FormatSpan {
        FormatSpan(text: text)
    }

    /// 创建粗体跨度
    static func bold(_ text: String) -> FormatSpan {
        FormatSpan(text: text, formats: [.bold])
    }

    /// 创建斜体跨度
    static func italic(_ text: String) -> FormatSpan {
        FormatSpan(text: text, formats: [.italic])
    }

    /// 创建下划线跨度
    static func underline(_ text: String) -> FormatSpan {
        FormatSpan(text: text, formats: [.underline])
    }

    /// 创建删除线跨度
    static func strikethrough(_ text: String) -> FormatSpan {
        FormatSpan(text: text, formats: [.strikethrough])
    }

    /// 创建高亮跨度
    static func highlight(_ text: String, color: String) -> FormatSpan {
        FormatSpan(text: text, formats: [.highlight], highlightColor: color)
    }

    /// 创建粗斜体跨度
    static func boldItalic(_ text: String) -> FormatSpan {
        FormatSpan(text: text, formats: [.bold, .italic])
    }
}

// MARK: - CustomStringConvertible

extension FormatSpan: CustomStringConvertible {
    public var description: String {
        let formatNames = formats.map(\.rawValue).sorted().joined(separator: ", ")
        let colorInfo = highlightColor.map { " color=\($0)" } ?? ""
        return "FormatSpan(\"\(text)\", formats: [\(formatNames)]\(colorInfo))"
    }
}

// MARK: - CustomDebugStringConvertible

extension FormatSpan: CustomDebugStringConvertible {
    public var debugDescription: String {
        description
    }
}
