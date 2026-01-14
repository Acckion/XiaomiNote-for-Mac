//
//  XMLParser.swift
//  MiNoteMac
//
//  XML 语法分析器
//  将 Token 流解析为 AST（抽象语法树）
//

import Foundation

// MARK: - ParseError

/// 解析错误类型
public enum ParseError: Error, LocalizedError, Sendable {
    /// XML 格式无效
    case invalidXML(String)
    
    /// 意外的输入结束
    case unexpectedEndOfInput
    
    /// 标签不匹配
    case unmatchedTag(expected: String, found: String)
    
    /// 不支持的元素
    case unsupportedElement(String)
    
    /// 意外的 Token
    case unexpectedToken(XMLToken)
    
    /// 缺少必需的属性
    case missingAttribute(tag: String, attribute: String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidXML(let message):
            return "无效的 XML 格式: \(message)"
        case .unexpectedEndOfInput:
            return "意外的输入结束"
        case .unmatchedTag(let expected, let found):
            return "标签不匹配: 期望 </\(expected)>，找到 </\(found)>"
        case .unsupportedElement(let element):
            return "不支持的元素: \(element)"
        case .unexpectedToken(let token):
            return "意外的 Token: \(token)"
        case .missingAttribute(let tag, let attribute):
            return "标签 <\(tag)> 缺少必需的属性: \(attribute)"
        }
    }
}

// MARK: - MiNoteXMLParser

/// 小米笔记 XML 解析器
/// 将小米笔记 XML 字符串解析为 AST
public final class MiNoteXMLParser: @unchecked Sendable {
    
    // MARK: - 属性
    
    /// Token 数组
    private var tokens: [XMLToken] = []
    
    /// 当前位置
    private var currentIndex: Int = 0
    
    /// 是否已到达末尾
    private var isAtEnd: Bool {
        currentIndex >= tokens.count
    }
    
    /// 当前 Token
    private var currentToken: XMLToken? {
        guard !isAtEnd else { return nil }
        return tokens[currentIndex]
    }
    
    /// 解析警告（用于记录跳过的不支持元素）
    public private(set) var warnings: [String] = []
    
    // MARK: - 初始化
    
    public init() {}
    
    // MARK: - 公共方法
    
    /// 解析 XML 字符串为文档 AST
    /// - Parameter xml: 小米笔记 XML 字符串
    /// - Returns: 文档 AST 节点
    /// - Throws: ParseError
    public func parse(_ xml: String) throws -> DocumentNode {
        // 重置状态
        warnings = []
        currentIndex = 0
        
        // 词法分析
        let tokenizer = XMLTokenizer(input: xml)
        tokens = try tokenizer.tokenize()
        
        // 语法分析
        var blocks: [any BlockNode] = []
        
        while !isAtEnd {
            // 跳过换行符
            if case .newline = currentToken {
                advance()
                continue
            }
            
            // 解析块级元素
            if let block = try parseBlock() {
                blocks.append(block)
            }
        }
        
        return DocumentNode(blocks: blocks)
    }
    
    // MARK: - 块级元素解析
    
    /// 解析块级元素
    private func parseBlock() throws -> (any BlockNode)? {
        guard let token = currentToken else { return nil }
        
        switch token {
        case .startTag(let name, let attributes, let selfClosing):
            return try parseBlockElement(name: name, attributes: attributes, selfClosing: selfClosing)
            
        case .text(let text):
            // 独立的文本（可能是 bullet/order/checkbox 后的内容）
            // 这种情况不应该在这里出现，因为我们在解析特殊块级元素时会处理
            advance()
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                return TextBlockNode(indent: 1, content: [TextNode(text: text)])
            }
            return nil
            
        case .endTag:
            // 结束标签不应该在块级解析中出现
            advance()
            return nil
            
        case .newline:
            advance()
            return nil
        }
    }
    
    /// 解析块级元素
    private func parseBlockElement(name: String, attributes: [String: String], selfClosing: Bool) throws -> (any BlockNode)? {
        switch name {
        case "text":
            return try parseTextBlock(attributes: attributes, selfClosing: selfClosing)
            
        case "bullet":
            return try parseBulletList(attributes: attributes, selfClosing: selfClosing)
            
        case "order":
            return try parseOrderedList(attributes: attributes, selfClosing: selfClosing)
            
        case "input":
            return try parseCheckbox(attributes: attributes, selfClosing: selfClosing)
            
        case "hr":
            advance()
            return HorizontalRuleNode()
            
        case "img":
            return try parseImage(attributes: attributes)
            
        case "sound":
            return try parseAudio(attributes: attributes)
            
        case "quote":
            return try parseQuote(selfClosing: selfClosing)
            
        default:
            // 不支持的元素，记录警告并跳过
            warnings.append("跳过不支持的元素: <\(name)>")
            advance()
            if !selfClosing {
                try skipUntilEndTag(name)
            }
            return nil
        }
    }
    
    // MARK: - 具体块级元素解析
    
    /// 解析文本块 `<text indent="N">内容</text>`
    private func parseTextBlock(attributes: [String: String], selfClosing: Bool) throws -> TextBlockNode {
        let indent = Int(attributes["indent"] ?? "1") ?? 1
        
        // 跳过开始标签
        advance()
        
        if selfClosing {
            return TextBlockNode(indent: indent, content: [])
        }
        
        // 解析行内内容
        let content = try parseInlineContent(until: "text")
        
        return TextBlockNode(indent: indent, content: content)
    }
    
    /// 解析无序列表 `<bullet indent="N" />内容`
    /// 注意：内容在标签外部
    private func parseBulletList(attributes: [String: String], selfClosing: Bool) throws -> BulletListNode {
        let indent = Int(attributes["indent"] ?? "1") ?? 1
        
        // 跳过开始标签
        advance()
        
        // 如果不是自闭合标签，需要跳过结束标签
        if !selfClosing {
            if case .endTag(let name) = currentToken, name == "bullet" {
                advance()
            }
        }
        
        // 解析标签后的文本内容（直到换行符）
        let content = try parseContentAfterTag()
        
        return BulletListNode(indent: indent, content: content)
    }
    
    /// 解析有序列表 `<order indent="N" inputNumber="M" />内容`
    /// 注意：内容在标签外部
    private func parseOrderedList(attributes: [String: String], selfClosing: Bool) throws -> OrderedListNode {
        let indent = Int(attributes["indent"] ?? "1") ?? 1
        let inputNumber = Int(attributes["inputNumber"] ?? "0") ?? 0
        
        // 跳过开始标签
        advance()
        
        // 如果不是自闭合标签，需要跳过结束标签
        if !selfClosing {
            if case .endTag(let name) = currentToken, name == "order" {
                advance()
            }
        }
        
        // 解析标签后的文本内容（直到换行符）
        let content = try parseContentAfterTag()
        
        return OrderedListNode(indent: indent, inputNumber: inputNumber, content: content)
    }
    
    /// 解析复选框 `<input type="checkbox" indent="N" level="M" />内容`
    /// 注意：内容在标签外部
    private func parseCheckbox(attributes: [String: String], selfClosing: Bool) throws -> CheckboxNode {
        // 验证是 checkbox 类型
        guard attributes["type"] == "checkbox" else {
            throw ParseError.unsupportedElement("input type=\"\(attributes["type"] ?? "unknown")\"")
        }
        
        let indent = Int(attributes["indent"] ?? "1") ?? 1
        let level = Int(attributes["level"] ?? "1") ?? 1
        let isChecked = attributes["checked"] == "true"
        
        // 跳过开始标签
        advance()
        
        // 如果不是自闭合标签，需要跳过结束标签
        if !selfClosing {
            if case .endTag(let name) = currentToken, name == "input" {
                advance()
            }
        }
        
        // 解析标签后的文本内容（直到换行符）
        let content = try parseContentAfterTag()
        
        return CheckboxNode(indent: indent, level: level, isChecked: isChecked, content: content)
    }
    
    /// 解析图片 `<img fileid="ID" />` 或 `<img src="URL" />`
    private func parseImage(attributes: [String: String]) throws -> ImageNode {
        let fileId = attributes["fileid"]
        let src = attributes["src"]
        let width = attributes["width"].flatMap { Int($0) }
        let height = attributes["height"].flatMap { Int($0) }
        
        // 跳过标签
        advance()
        
        return ImageNode(fileId: fileId, src: src, width: width, height: height)
    }
    
    /// 解析音频 `<sound fileid="ID" />`
    private func parseAudio(attributes: [String: String]) throws -> AudioNode {
        guard let fileId = attributes["fileid"] else {
            throw ParseError.missingAttribute(tag: "sound", attribute: "fileid")
        }
        
        let isTemporary = attributes["temporary"] == "true"
        
        // 跳过标签
        advance()
        
        return AudioNode(fileId: fileId, isTemporary: isTemporary)
    }
    
    /// 解析引用块 `<quote>多行内容</quote>`
    private func parseQuote(selfClosing: Bool) throws -> QuoteNode {
        // 跳过开始标签
        advance()
        
        if selfClosing {
            return QuoteNode(textBlocks: [])
        }
        
        var textBlocks: [TextBlockNode] = []
        
        // 解析引用块内的内容
        while !isAtEnd {
            // 跳过换行符
            if case .newline = currentToken {
                advance()
                continue
            }
            
            // 检查结束标签
            if case .endTag(let name) = currentToken {
                if name == "quote" {
                    advance()
                    break
                }
            }
            
            // 解析内部的 text 元素
            if case .startTag(let name, let attributes, let selfClosing) = currentToken {
                if name == "text" {
                    let textBlock = try parseTextBlock(attributes: attributes, selfClosing: selfClosing)
                    textBlocks.append(textBlock)
                } else {
                    // 跳过其他元素
                    warnings.append("引用块内跳过不支持的元素: <\(name)>")
                    advance()
                    if !selfClosing {
                        try skipUntilEndTag(name)
                    }
                }
            } else {
                // 跳过其他 Token
                advance()
            }
        }
        
        return QuoteNode(textBlocks: textBlocks)
    }
    
    // MARK: - 行内内容解析
    
    /// 解析行内内容直到指定的结束标签
    private func parseInlineContent(until endTagName: String) throws -> [any InlineNode] {
        var nodes: [any InlineNode] = []
        
        while !isAtEnd {
            guard let token = currentToken else { break }
            
            switch token {
            case .endTag(let name):
                if name == endTagName {
                    advance()
                    return nodes
                } else {
                    throw ParseError.unmatchedTag(expected: endTagName, found: name)
                }
                
            case .text(let text):
                advance()
                if !text.isEmpty {
                    nodes.append(TextNode(text: text))
                }
                
            case .startTag(let name, let attributes, let selfClosing):
                if let inlineNode = try parseInlineElement(name: name, attributes: attributes, selfClosing: selfClosing) {
                    nodes.append(inlineNode)
                }
                
            case .newline:
                // 行内内容中的换行符作为文本处理
                advance()
                nodes.append(TextNode(text: "\n"))
            }
        }
        
        throw ParseError.unexpectedEndOfInput
    }
    
    /// 解析标签后的内容（用于 bullet/order/checkbox）
    /// 直到换行符或下一个块级标签
    private func parseContentAfterTag() throws -> [any InlineNode] {
        var nodes: [any InlineNode] = []
        
        while !isAtEnd {
            guard let token = currentToken else { break }
            
            switch token {
            case .newline:
                // 遇到换行符，结束解析
                advance()
                return nodes
                
            case .text(let text):
                advance()
                if !text.isEmpty {
                    nodes.append(TextNode(text: text))
                }
                
            case .startTag(let name, let attributes, let selfClosing):
                // 检查是否为块级元素
                if isBlockLevelTag(name) {
                    // 遇到块级元素，结束解析（不消费这个 Token）
                    return nodes
                }
                
                // 解析行内元素
                if let inlineNode = try parseInlineElement(name: name, attributes: attributes, selfClosing: selfClosing) {
                    nodes.append(inlineNode)
                }
                
            case .endTag:
                // 结束标签不应该在这里出现
                return nodes
            }
        }
        
        return nodes
    }
    
    /// 解析行内元素
    private func parseInlineElement(name: String, attributes: [String: String], selfClosing: Bool) throws -> (any InlineNode)? {
        // 获取对应的节点类型
        guard let nodeType = inlineTagToNodeType(name) else {
            // 不支持的行内元素，记录警告并跳过
            warnings.append("跳过不支持的行内元素: <\(name)>")
            advance()
            if !selfClosing {
                try skipUntilEndTag(name)
            }
            return nil
        }
        
        // 跳过开始标签
        advance()
        
        if selfClosing {
            return FormattedNode(type: nodeType, content: [], color: attributes["color"])
        }
        
        // 递归解析内容
        let content = try parseInlineContent(until: name)
        
        // 创建格式化节点
        let color = (nodeType == .highlight) ? attributes["color"] : nil
        return FormattedNode(type: nodeType, content: content, color: color)
    }
    
    // MARK: - 辅助方法
    
    /// 前进一个 Token
    private func advance() {
        if currentIndex < tokens.count {
            currentIndex += 1
        }
    }
    
    /// 跳过直到指定的结束标签
    private func skipUntilEndTag(_ tagName: String) throws {
        var depth = 1
        
        while !isAtEnd && depth > 0 {
            guard let token = currentToken else { break }
            
            switch token {
            case .startTag(let name, _, let selfClosing):
                if name == tagName && !selfClosing {
                    depth += 1
                }
                advance()
                
            case .endTag(let name):
                if name == tagName {
                    depth -= 1
                }
                advance()
                
            default:
                advance()
            }
        }
    }
    
    /// 检查是否为块级标签
    private func isBlockLevelTag(_ name: String) -> Bool {
        switch name {
        case "text", "bullet", "order", "input", "hr", "img", "sound", "quote":
            return true
        default:
            return false
        }
    }
    
    /// 将行内标签名转换为节点类型
    private func inlineTagToNodeType(_ name: String) -> ASTNodeType? {
        switch name {
        case "b":
            return .bold
        case "i":
            return .italic
        case "u":
            return .underline
        case "delete":
            return .strikethrough
        case "background":
            return .highlight
        case "size":
            return .heading1
        case "mid-size":
            return .heading2
        case "h3-size":
            return .heading3
        case "center":
            return .centerAlign
        case "right":
            return .rightAlign
        default:
            return nil
        }
    }
}
