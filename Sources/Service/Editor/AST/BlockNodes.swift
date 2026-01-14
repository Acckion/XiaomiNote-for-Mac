//
//  BlockNodes.swift
//  MiNoteMac
//
//  块级 AST 节点实现
//  包含文档、文本块、列表、复选框、分割线、图片、音频、引用等节点
//

import Foundation

// MARK: - 文档根节点

/// 文档根节点
/// 包含所有块级节点的容器
public struct DocumentNode: ASTNode, Equatable, Sendable {
    public var nodeType: ASTNodeType { .document }
    
    /// 文档包含的块级节点
    public var blocks: [any BlockNode]
    
    public var children: [any ASTNode] {
        blocks.map { $0 as any ASTNode }
    }
    
    public init(blocks: [any BlockNode] = []) {
        self.blocks = blocks
    }
    
    public static func == (lhs: DocumentNode, rhs: DocumentNode) -> Bool {
        guard lhs.blocks.count == rhs.blocks.count else { return false }
        for (left, right) in zip(lhs.blocks, rhs.blocks) {
            if !areNodesEqual(left, right) {
                return false
            }
        }
        return true
    }
}

// MARK: - 文本块节点

/// 文本块节点
/// 对应 XML 中的 `<text indent="N">内容</text>`
public struct TextBlockNode: BlockNode, Equatable, Sendable {
    public var nodeType: ASTNodeType { .textBlock }
    
    /// 缩进级别
    public var indent: Int
    
    /// 行内内容
    public var content: [any InlineNode]
    
    public var children: [any ASTNode] {
        content.map { $0 as any ASTNode }
    }
    
    public init(indent: Int = 1, content: [any InlineNode] = []) {
        self.indent = indent
        self.content = content
    }
    
    public static func == (lhs: TextBlockNode, rhs: TextBlockNode) -> Bool {
        guard lhs.indent == rhs.indent else { return false }
        guard lhs.content.count == rhs.content.count else { return false }
        for (left, right) in zip(lhs.content, rhs.content) {
            if !areNodesEqual(left, right) {
                return false
            }
        }
        return true
    }
}

// MARK: - 无序列表节点

/// 无序列表节点
/// 对应 XML 中的 `<bullet indent="N" />内容`
/// 注意：内容在标签外部
public struct BulletListNode: BlockNode, Equatable, Sendable {
    public var nodeType: ASTNodeType { .bulletList }
    
    /// 缩进级别
    public var indent: Int
    
    /// 行内内容
    public var content: [any InlineNode]
    
    public var children: [any ASTNode] {
        content.map { $0 as any ASTNode }
    }
    
    public init(indent: Int = 1, content: [any InlineNode] = []) {
        self.indent = indent
        self.content = content
    }
    
    public static func == (lhs: BulletListNode, rhs: BulletListNode) -> Bool {
        guard lhs.indent == rhs.indent else { return false }
        guard lhs.content.count == rhs.content.count else { return false }
        for (left, right) in zip(lhs.content, rhs.content) {
            if !areNodesEqual(left, right) {
                return false
            }
        }
        return true
    }
}

// MARK: - 有序列表节点

/// 有序列表节点
/// 对应 XML 中的 `<order indent="N" inputNumber="M" />内容`
/// 注意：内容在标签外部
/// inputNumber 规则：首项为实际值-1，后续项为0
public struct OrderedListNode: BlockNode, Equatable, Sendable {
    public var nodeType: ASTNodeType { .orderedList }
    
    /// 缩进级别
    public var indent: Int
    
    /// 输入编号
    /// 0 表示连续编号，非0 表示新列表起始值-1
    public var inputNumber: Int
    
    /// 行内内容
    public var content: [any InlineNode]
    
    public var children: [any ASTNode] {
        content.map { $0 as any ASTNode }
    }
    
    public init(indent: Int = 1, inputNumber: Int = 0, content: [any InlineNode] = []) {
        self.indent = indent
        self.inputNumber = inputNumber
        self.content = content
    }
    
    public static func == (lhs: OrderedListNode, rhs: OrderedListNode) -> Bool {
        guard lhs.indent == rhs.indent else { return false }
        guard lhs.inputNumber == rhs.inputNumber else { return false }
        guard lhs.content.count == rhs.content.count else { return false }
        for (left, right) in zip(lhs.content, rhs.content) {
            if !areNodesEqual(left, right) {
                return false
            }
        }
        return true
    }
}

// MARK: - 复选框节点

/// 复选框节点
/// 对应 XML 中的 `<input type="checkbox" indent="N" level="M" />内容`
/// 或带 `checked="true"` 的复选框
public struct CheckboxNode: BlockNode, Equatable, Sendable {
    public var nodeType: ASTNodeType { .checkbox }
    
    /// 缩进级别
    public var indent: Int
    
    /// 层级
    public var level: Int
    
    /// 是否已勾选
    public var isChecked: Bool
    
    /// 行内内容
    public var content: [any InlineNode]
    
    public var children: [any ASTNode] {
        content.map { $0 as any ASTNode }
    }
    
    public init(indent: Int = 1, level: Int = 1, isChecked: Bool = false, content: [any InlineNode] = []) {
        self.indent = indent
        self.level = level
        self.isChecked = isChecked
        self.content = content
    }
    
    public static func == (lhs: CheckboxNode, rhs: CheckboxNode) -> Bool {
        guard lhs.indent == rhs.indent else { return false }
        guard lhs.level == rhs.level else { return false }
        guard lhs.isChecked == rhs.isChecked else { return false }
        guard lhs.content.count == rhs.content.count else { return false }
        for (left, right) in zip(lhs.content, rhs.content) {
            if !areNodesEqual(left, right) {
                return false
            }
        }
        return true
    }
}

// MARK: - 分割线节点

/// 分割线节点
/// 对应 XML 中的 `<hr />`
public struct HorizontalRuleNode: BlockNode, Equatable, Sendable {
    public var nodeType: ASTNodeType { .horizontalRule }
    
    /// 分割线的缩进固定为 1
    public var indent: Int { 1 }
    
    /// 分割线没有子节点
    public var children: [any ASTNode] { [] }
    
    public init() {}
}

// MARK: - 图片节点

/// 图片节点
/// 对应 XML 中的 `<img fileid="ID" />` 或 `<img src="URL" />`
public struct ImageNode: BlockNode, Equatable, Sendable {
    public var nodeType: ASTNodeType { .image }
    
    /// 图片的缩进固定为 1
    public var indent: Int { 1 }
    
    /// 文件 ID（云端图片）
    public var fileId: String?
    
    /// 图片 URL（本地或外部图片）
    public var src: String?
    
    /// 图片宽度
    public var width: Int?
    
    /// 图片高度
    public var height: Int?
    
    /// 图片没有子节点
    public var children: [any ASTNode] { [] }
    
    public init(fileId: String? = nil, src: String? = nil, width: Int? = nil, height: Int? = nil) {
        self.fileId = fileId
        self.src = src
        self.width = width
        self.height = height
    }
}

// MARK: - 音频节点

/// 音频节点
/// 对应 XML 中的 `<sound fileid="ID" />`
public struct AudioNode: BlockNode, Equatable, Sendable {
    public var nodeType: ASTNodeType { .audio }
    
    /// 音频的缩进固定为 1
    public var indent: Int { 1 }
    
    /// 文件 ID
    public var fileId: String
    
    /// 是否为临时文件（本地录音未上传）
    public var isTemporary: Bool
    
    /// 音频没有子节点
    public var children: [any ASTNode] { [] }
    
    public init(fileId: String, isTemporary: Bool = false) {
        self.fileId = fileId
        self.isTemporary = isTemporary
    }
}

// MARK: - 引用块节点

/// 引用块节点
/// 对应 XML 中的 `<quote>多行内容</quote>`
/// 内部可以包含多个 text 元素
public struct QuoteNode: BlockNode, Equatable, Sendable {
    public var nodeType: ASTNodeType { .quote }
    
    /// 引用块的缩进固定为 1
    public var indent: Int { 1 }
    
    /// 引用块内的文本块
    public var textBlocks: [TextBlockNode]
    
    public var children: [any ASTNode] {
        textBlocks.map { $0 as any ASTNode }
    }
    
    public init(textBlocks: [TextBlockNode] = []) {
        self.textBlocks = textBlocks
    }
    
    public static func == (lhs: QuoteNode, rhs: QuoteNode) -> Bool {
        guard lhs.textBlocks.count == rhs.textBlocks.count else { return false }
        for (left, right) in zip(lhs.textBlocks, rhs.textBlocks) {
            if left != right {
                return false
            }
        }
        return true
    }
}
