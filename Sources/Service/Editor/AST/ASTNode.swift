//
//  ASTNode.swift
//  MiNoteMac
//
//  小米笔记 XML 与 NSAttributedString 转换的抽象语法树节点定义
//  参考 ProseMirror 的 Node + Mark 分离设计
//

import Foundation

// MARK: - AST 节点类型枚举

/// AST 节点类型枚举
/// 包含所有块级元素和行内格式元素的类型标识
public enum ASTNodeType: String, Equatable, Hashable, Sendable {
    // 块级元素
    case document       // 文档根节点
    case titleBlock     // 标题块 <title> (特殊的第一个段落)
    case textBlock      // 文本块 <text>
    case bulletList     // 无序列表 <bullet>
    case orderedList    // 有序列表 <order>
    case checkbox       // 复选框 <input type="checkbox">
    case horizontalRule // 分割线 <hr>
    case image          // 图片 <img>
    case audio          // 音频 <sound>
    case quote          // 引用块 <quote>
    
    // 行内格式元素
    case text           // 纯文本节点
    case bold           // 粗体 <b>
    case italic         // 斜体 <i>
    case underline      // 下划线 <u>
    case strikethrough  // 删除线 <delete>
    case highlight      // 高亮/背景色 <background>
    case heading1       // 大标题 <size>
    case heading2       // 二级标题 <mid-size>
    case heading3       // 三级标题 <h3-size>
    case centerAlign    // 居中对齐 <center>
    case rightAlign     // 右对齐 <right>
    
    /// 是否为块级元素
    public var isBlockLevel: Bool {
        switch self {
        case .document, .titleBlock, .textBlock, .bulletList, .orderedList,
             .checkbox, .horizontalRule, .image, .audio, .quote:
            return true
        default:
            return false
        }
    }
    
    /// 是否为行内格式元素
    public var isInlineFormat: Bool {
        switch self {
        case .bold, .italic, .underline, .strikethrough,
             .highlight, .heading1, .heading2, .heading3,
             .centerAlign, .rightAlign:
            return true
        default:
            return false
        }
    }
    
    /// 对应的 XML 标签名
    public var xmlTagName: String? {
        switch self {
        case .document:
            return nil
        case .titleBlock:
            return "title"
        case .textBlock:
            return "text"
        case .bulletList:
            return "bullet"
        case .orderedList:
            return "order"
        case .checkbox:
            return "input"
        case .horizontalRule:
            return "hr"
        case .image:
            return "img"
        case .audio:
            return "sound"
        case .quote:
            return "quote"
        case .text:
            return nil
        case .bold:
            return "b"
        case .italic:
            return "i"
        case .underline:
            return "u"
        case .strikethrough:
            return "delete"
        case .highlight:
            return "background"
        case .heading1:
            return "size"
        case .heading2:
            return "mid-size"
        case .heading3:
            return "h3-size"
        case .centerAlign:
            return "center"
        case .rightAlign:
            return "right"
        }
    }
}

// MARK: - AST 节点协议

/// AST 节点基础协议
/// 所有 AST 节点都必须实现此协议
public protocol ASTNode: Sendable {
    /// 节点类型标识
    var nodeType: ASTNodeType { get }
    
    /// 子节点（用于遍历）
    var children: [any ASTNode] { get }
}

// MARK: - 块级节点协议

/// 块级节点协议
/// 代表一行内容的节点（如 text、bullet、order、checkbox 等）
public protocol BlockNode: ASTNode {
    /// 缩进级别
    var indent: Int { get }
}

// MARK: - 行内节点协议

/// 行内节点协议
/// 代表文本格式的节点（如 bold、italic、text 等）
public protocol InlineNode: ASTNode {}

// MARK: - 节点相等性比较

/// 用于比较两个 AST 节点是否语义等价
public func areNodesEqual(_ lhs: any ASTNode, _ rhs: any ASTNode) -> Bool {
    // 首先比较节点类型
    guard lhs.nodeType == rhs.nodeType else { return false }
    
    // 比较子节点数量
    guard lhs.children.count == rhs.children.count else { return false }
    
    // 递归比较子节点
    for (leftChild, rightChild) in zip(lhs.children, rhs.children) {
        if !areNodesEqual(leftChild, rightChild) {
            return false
        }
    }
    
    return true
}
