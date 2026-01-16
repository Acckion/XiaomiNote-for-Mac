//
//  InlineNodes.swift
//  MiNoteMac
//
//  行内 AST 节点实现
//  包含纯文本节点和格式化节点
//

import Foundation

// MARK: - 纯文本节点

/// 纯文本节点
/// 表示没有任何格式的纯文本内容
public struct TextNode: InlineNode, Equatable, Sendable {
    public var nodeType: ASTNodeType { .text }
    
    /// 文本内容
    public var text: String
    
    /// 纯文本节点没有子节点
    public var children: [any ASTNode] { [] }
    
    public init(text: String) {
        self.text = text
    }
}

// MARK: - 格式化节点

/// 格式化节点
/// 表示带有特定格式的内容，可以包含子节点（支持嵌套格式）
/// 例如：`<b><i>文本</i></b>` 会生成嵌套的 FormattedNode
public struct FormattedNode: InlineNode, Equatable, Sendable {
    /// 格式类型
    public var nodeType: ASTNodeType
    
    /// 子节点（可以是 TextNode 或其他 FormattedNode）
    public var content: [any InlineNode]
    
    /// 颜色值（仅用于 highlight 类型）
    public var color: String?
    
    public var children: [any ASTNode] {
        content.map { $0 as any ASTNode }
    }
    
    /// 创建格式化节点
    /// - Parameters:
    ///   - type: 格式类型（必须是行内格式类型）
    ///   - content: 子节点
    ///   - color: 颜色值（仅用于 highlight）
    public init(type: ASTNodeType, content: [any InlineNode], color: String? = nil) {
        // 确保类型是行内格式类型
        assert(type.isInlineFormat, "FormattedNode 只能使用行内格式类型")
        self.nodeType = type
        self.content = content
        self.color = color
    }
    
    public static func == (lhs: FormattedNode, rhs: FormattedNode) -> Bool {
        guard lhs.nodeType == rhs.nodeType else { return false }
        guard lhs.color == rhs.color else { return false }
        guard lhs.content.count == rhs.content.count else { return false }
        for (left, right) in zip(lhs.content, rhs.content) {
            if !areNodesEqual(left, right) {
                return false
            }
        }
        return true
    }
}

// MARK: - 便捷构造方法

extension FormattedNode {
    /// 创建粗体节点
    public static func bold(_ content: [any InlineNode]) -> FormattedNode {
        FormattedNode(type: .bold, content: content)
    }
    
    /// 创建粗体节点（单个文本）
    public static func bold(_ text: String) -> FormattedNode {
        FormattedNode(type: .bold, content: [TextNode(text: text)])
    }
    
    /// 创建斜体节点
    public static func italic(_ content: [any InlineNode]) -> FormattedNode {
        FormattedNode(type: .italic, content: content)
    }
    
    /// 创建斜体节点（单个文本）
    public static func italic(_ text: String) -> FormattedNode {
        FormattedNode(type: .italic, content: [TextNode(text: text)])
    }
    
    /// 创建下划线节点
    public static func underline(_ content: [any InlineNode]) -> FormattedNode {
        FormattedNode(type: .underline, content: content)
    }
    
    /// 创建下划线节点（单个文本）
    public static func underline(_ text: String) -> FormattedNode {
        FormattedNode(type: .underline, content: [TextNode(text: text)])
    }
    
    /// 创建删除线节点
    public static func strikethrough(_ content: [any InlineNode]) -> FormattedNode {
        FormattedNode(type: .strikethrough, content: content)
    }
    
    /// 创建删除线节点（单个文本）
    public static func strikethrough(_ text: String) -> FormattedNode {
        FormattedNode(type: .strikethrough, content: [TextNode(text: text)])
    }
    
    /// 创建高亮节点
    public static func highlight(_ content: [any InlineNode], color: String) -> FormattedNode {
        FormattedNode(type: .highlight, content: content, color: color)
    }
    
    /// 创建高亮节点（单个文本）
    public static func highlight(_ text: String, color: String) -> FormattedNode {
        FormattedNode(type: .highlight, content: [TextNode(text: text)], color: color)
    }
    
    /// 创建大标题节点
    public static func heading1(_ content: [any InlineNode]) -> FormattedNode {
        FormattedNode(type: .heading1, content: content)
    }
    
    /// 创建大标题节点（单个文本）
    public static func heading1(_ text: String) -> FormattedNode {
        FormattedNode(type: .heading1, content: [TextNode(text: text)])
    }
    
    /// 创建二级标题节点
    public static func heading2(_ content: [any InlineNode]) -> FormattedNode {
        FormattedNode(type: .heading2, content: content)
    }
    
    /// 创建二级标题节点（单个文本）
    public static func heading2(_ text: String) -> FormattedNode {
        FormattedNode(type: .heading2, content: [TextNode(text: text)])
    }
    
    /// 创建三级标题节点
    public static func heading3(_ content: [any InlineNode]) -> FormattedNode {
        FormattedNode(type: .heading3, content: content)
    }
    
    /// 创建三级标题节点（单个文本）
    public static func heading3(_ text: String) -> FormattedNode {
        FormattedNode(type: .heading3, content: [TextNode(text: text)])
    }
    
    /// 创建居中对齐节点
    public static func centerAlign(_ content: [any InlineNode]) -> FormattedNode {
        FormattedNode(type: .centerAlign, content: content)
    }
    
    /// 创建居中对齐节点（单个文本）
    public static func centerAlign(_ text: String) -> FormattedNode {
        FormattedNode(type: .centerAlign, content: [TextNode(text: text)])
    }
    
    /// 创建右对齐节点
    public static func rightAlign(_ content: [any InlineNode]) -> FormattedNode {
        FormattedNode(type: .rightAlign, content: content)
    }
    
    /// 创建右对齐节点（单个文本）
    public static func rightAlign(_ text: String) -> FormattedNode {
        FormattedNode(type: .rightAlign, content: [TextNode(text: text)])
    }
}

// MARK: - 行内节点工具方法

/// 从行内节点数组中提取纯文本内容
/// - Parameter nodes: 行内节点数组
/// - Returns: 纯文本字符串
public func extractPlainText(from nodes: [any InlineNode]) -> String {
    var result = ""
    
    func traverse(_ node: any InlineNode) {
        if let textNode = node as? TextNode {
            result += textNode.text
        } else if let formattedNode = node as? FormattedNode {
            for child in formattedNode.content {
                traverse(child)
            }
        }
    }
    
    for node in nodes {
        traverse(node)
    }
    
    return result
}

/// 检查行内节点数组是否为空（没有实际文本内容）
/// - Parameter nodes: 行内节点数组
/// - Returns: 是否为空
public func isInlineContentEmpty(_ nodes: [any InlineNode]) -> Bool {
    extractPlainText(from: nodes).isEmpty
}
