//
//  XMLGenerator.swift
//  MiNoteMac
//
//  XML 生成器
//  将 AST 转换为小米笔记 XML 字符串
//

import Foundation

// MARK: - XMLGenerator

/// 小米笔记 XML 生成器
/// 将 AST 转换为小米笔记 XML 字符串
public final class XMLGenerator: @unchecked Sendable {
    
    // MARK: - 格式标签嵌套顺序
    
    /// 格式标签的嵌套顺序（从外到内）
    /// 生成 XML 时按此顺序嵌套标签
    /// 顺序：标题 → 对齐 → 背景色 → 删除线 → 下划线 → 斜体 → 粗体
    private let formatOrder: [ASTNodeType] = [
        .heading1, .heading2, .heading3,  // 标题最外层
        .centerAlign, .rightAlign,         // 对齐
        .highlight,                         // 背景色
        .strikethrough,                     // 删除线
        .underline,                         // 下划线
        .italic,                            // 斜体
        .bold                               // 粗体最内层
    ]
    
    // MARK: - 初始化
    
    public init() {}
    
    // MARK: - 公共方法
    
    /// 将文档 AST 转换为 XML 字符串
    /// - Parameter document: 文档 AST 节点
    /// - Returns: XML 字符串
    public func generate(_ document: DocumentNode) -> String {
        var lines: [String] = []
        
        for block in document.blocks {
            let line = generateBlock(block)
            lines.append(line)
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - 块级元素生成
    
    /// 将块级节点转换为 XML 行
    /// - Parameter block: 块级节点
    /// - Returns: XML 行字符串
    private func generateBlock(_ block: any BlockNode) -> String {
        switch block.nodeType {
        case .textBlock:
            return generateTextBlock(block as! TextBlockNode)
            
        case .bulletList:
            return generateBulletList(block as! BulletListNode)
            
        case .orderedList:
            return generateOrderedList(block as! OrderedListNode)
            
        case .checkbox:
            return generateCheckbox(block as! CheckboxNode)
            
        case .horizontalRule:
            return generateHorizontalRule()
            
        case .image:
            return generateImage(block as! ImageNode)
            
        case .audio:
            return generateAudio(block as! AudioNode)
            
        case .quote:
            return generateQuote(block as! QuoteNode)
            
        default:
            // 不应该到达这里
            return ""
        }
    }
    
    /// 生成文本块 XML
    /// 格式：`<text indent="N">内容</text>`
    private func generateTextBlock(_ node: TextBlockNode) -> String {
        let content = generateInlineContent(node.content)
        return "<text indent=\"\(node.indent)\">\(content)</text>"
    }
    
    /// 生成无序列表 XML
    /// 格式：`<bullet indent="N" />内容`
    /// 注意：内容在标签外部
    private func generateBulletList(_ node: BulletListNode) -> String {
        let content = generateInlineContent(node.content)
        return "<bullet indent=\"\(node.indent)\" />\(content)"
    }
    
    /// 生成有序列表 XML
    /// 格式：`<order indent="N" inputNumber="M" />内容`
    /// 注意：内容在标签外部
    private func generateOrderedList(_ node: OrderedListNode) -> String {
        let content = generateInlineContent(node.content)
        return "<order indent=\"\(node.indent)\" inputNumber=\"\(node.inputNumber)\" />\(content)"
    }
    
    /// 生成复选框 XML
    /// 格式：`<input type="checkbox" indent="N" level="M" />内容`
    /// 或带 `checked="true"` 的复选框
    private func generateCheckbox(_ node: CheckboxNode) -> String {
        let content = generateInlineContent(node.content)
        var attributes = "type=\"checkbox\" indent=\"\(node.indent)\" level=\"\(node.level)\""
        
        if node.isChecked {
            attributes += " checked=\"true\""
        }
        
        return "<input \(attributes) />\(content)"
    }
    
    /// 生成分割线 XML
    /// 格式：`<hr />`
    private func generateHorizontalRule() -> String {
        return "<hr />"
    }
    
    /// 生成图片 XML
    /// 格式：新格式 `<img fileid="ID" imgshow="0/1" imgdes="描述" />` 或旧格式 `<img src="URL" />`
    private func generateImage(_ node: ImageNode) -> String {
        var attributes: [String] = []
        
        // 优先使用 fileId（小米笔记格式）
        if let fileId = node.fileId {
            attributes.append("fileid=\"\(encodeXMLEntities(fileId))\"")
            
            // 添加描述（只在有值时添加，避免生成空属性）
            if let description = node.description, !description.isEmpty {
                attributes.append("imgdes=\"\(encodeXMLEntities(description))\"")
            }
            
            // 使用实际的 imgshow 值，如果没有则默认为 "0"
            // 注意：必须保持原值，不能随意修改
            let imgshowValue = node.imgshow ?? "0"
            attributes.append("imgshow=\"\(imgshowValue)\"")
        }
        // 如果没有 fileId，使用 src（兼容其他格式）
        else if let src = node.src {
            attributes.append("src=\"\(encodeXMLEntities(src))\"")
        }
        
        // 添加尺寸信息（如果有）
        if let width = node.width {
            attributes.append("width=\"\(width)\"")
        }
        
        if let height = node.height {
            attributes.append("height=\"\(height)\"")
        }
        
        if attributes.isEmpty {
            return "<img />"
        }
        
        return "<img \(attributes.joined(separator: " ")) />"
    }
    
    /// 生成音频 XML
    /// 格式：`<sound fileid="ID" />`
    private func generateAudio(_ node: AudioNode) -> String {
        var attributes = "fileid=\"\(encodeXMLEntities(node.fileId))\""
        
        if node.isTemporary {
            attributes += " temporary=\"true\""
        }
        
        return "<sound \(attributes) />"
    }
    
    /// 生成引用块 XML
    /// 格式：`<quote>多行内容</quote>`
    private func generateQuote(_ node: QuoteNode) -> String {
        if node.textBlocks.isEmpty {
            return "<quote></quote>"
        }
        
        var innerLines: [String] = []
        for textBlock in node.textBlocks {
            innerLines.append(generateTextBlock(textBlock))
        }
        
        return "<quote>\(innerLines.joined(separator: "\n"))</quote>"
    }

    
    // MARK: - 行内内容生成
    
    /// 将行内节点数组转换为 XML 内容
    /// - Parameter nodes: 行内节点数组
    /// - Returns: XML 内容字符串
    private func generateInlineContent(_ nodes: [any InlineNode]) -> String {
        var result = ""
        
        for node in nodes {
            result += generateInlineNode(node)
        }
        
        return result
    }
    
    /// 生成单个行内节点的 XML
    /// - Parameter node: 行内节点
    /// - Returns: XML 字符串
    private func generateInlineNode(_ node: any InlineNode) -> String {
        if let textNode = node as? TextNode {
            return encodeXMLEntities(textNode.text)
        }
        
        if let formattedNode = node as? FormattedNode {
            return generateFormattedNode(formattedNode)
        }
        
        return ""
    }
    
    /// 生成格式化节点的 XML
    /// - Parameter node: 格式化节点
    /// - Returns: XML 字符串
    private func generateFormattedNode(_ node: FormattedNode) -> String {
        guard let tagName = node.nodeType.xmlTagName else {
            // 如果没有对应的标签名，直接生成内容
            return generateInlineContent(node.content)
        }
        
        // 生成内容
        let content = generateInlineContent(node.content)
        
        // 生成开始标签
        var startTag = "<\(tagName)"
        
        // 添加属性（目前只有 highlight 有 color 属性）
        if node.nodeType == .highlight, let color = node.color {
            startTag += " color=\"\(encodeXMLEntities(color))\""
        }
        
        startTag += ">"
        
        // 生成结束标签
        let endTag = "</\(tagName)>"
        
        return startTag + content + endTag
    }
    
    // MARK: - XML 实体编码
    
    /// 编码 XML 特殊字符
    /// - Parameter text: 原始文本
    /// - Returns: 编码后的文本
    private func encodeXMLEntities(_ text: String) -> String {
        var result = text
        
        // 必须先替换 & 符号，否则会影响其他替换
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        
        return result
    }
}

// MARK: - 便捷扩展

extension XMLGenerator {
    
    /// 从文档节点生成 XML 字符串（静态方法）
    /// - Parameter document: 文档 AST 节点
    /// - Returns: XML 字符串
    public static func generate(_ document: DocumentNode) -> String {
        let generator = XMLGenerator()
        return generator.generate(document)
    }
}
