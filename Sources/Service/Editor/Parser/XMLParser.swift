//
//  XMLParser.swift
//  MiNoteMac
//
//  XML 语法分析器
//  将 Token 流解析为 AST（抽象语法树）
//

import Foundation

// MARK: - MiNoteXMLParser

/// 小米笔记 XML 解析器
/// 将小米笔记 XML 字符串解析为 AST
public final class MiNoteXMLParser: @unchecked Sendable {

    // MARK: - 属性

    /// Token 数组
    private var tokens: [XMLToken] = []

    /// 当前位置
    private var currentIndex = 0

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
    public private(set) var warnings: [ParseWarning] = []

    /// 错误日志记录器
    private let errorLogger: ErrorLogger

    /// 错误恢复处理器
    private let errorRecoveryHandler: ErrorRecoveryHandler

    /// 是否启用错误恢复（默认启用）
    public var enableErrorRecovery = true

    // MARK: - 初始化

    public init(
        errorLogger: ErrorLogger = ConsoleErrorLogger(),
        errorRecoveryHandler: ErrorRecoveryHandler = DefaultErrorRecoveryHandler()
    ) {
        self.errorLogger = errorLogger
        self.errorRecoveryHandler = errorRecoveryHandler
    }

    // MARK: - 公共方法

    /// 解析 XML 字符串为文档 AST
    /// - Parameter xml: 小米笔记 XML 字符串
    /// - Returns: 解析结果（包含文档 AST 和警告）
    /// - Throws: ParseError（仅在无法恢复时抛出）
    ///
    public func parse(_ xml: String) throws -> ParseResult<DocumentNode> {
        warnings = []
        currentIndex = 0

        LogService.shared.debug(.editor, "开始解析 XML，长度: \(xml.count)")

        do {
            let tokenizer = XMLTokenizer(input: xml)
            tokens = try tokenizer.tokenize()
        } catch {
            if enableErrorRecovery {
                errorLogger.logError(error, context: ["phase": "tokenization"])
                let fallbackNode = createFallbackDocument(xml)
                let warning = ParseWarning(
                    message: "词法分析失败，使用纯文本回退: \(error.localizedDescription)",
                    type: .other
                )
                return ParseResult(value: fallbackNode, warnings: [warning])
            } else {
                throw error
            }
        }

        var title: String?
        var blocks: [any BlockNode] = []

        while !isAtEnd {
            if case .newline = currentToken {
                advance()
                continue
            }

            if case let .startTag(name, _, selfClosing) = currentToken, name == "title" {
                advance()

                if !selfClosing {
                    if case let .text(titleText) = currentToken {
                        title = titleText
                        advance()
                    }

                    if case let .endTag(endName) = currentToken, endName == "title" {
                        advance()
                    }
                }

                continue
            }

            do {
                if let block = try parseBlock() {
                    blocks.append(block)
                }
            } catch let error as ParseError {
                if enableErrorRecovery {
                    let context = ErrorContext(
                        elementName: extractElementName(from: currentToken),
                        content: extractContent(from: currentToken),
                        position: currentIndex
                    )

                    let strategy = errorRecoveryHandler.handleError(error, context: context)

                    switch strategy {
                    case .skipElement:
                        let warning = ParseWarning(
                            message: "跳过错误元素: \(error.localizedDescription)",
                            location: "位置 \(currentIndex)",
                            type: .unsupportedElement
                        )
                        warnings.append(warning)
                        errorLogger.logWarning(warning)
                        skipToNextBlock()

                    case .fallbackToPlainText:
                        if let content = context.content {
                            let textBlock = TextBlockNode(indent: 1, content: [TextNode(text: content)])
                            blocks.append(textBlock)
                        }
                        advance()

                    case .useDefaultValue:
                        advance()

                    case .abort:
                        throw error
                    }
                } else {
                    throw error
                }
            }
        }

        return ParseResult(value: DocumentNode(title: title, blocks: blocks), warnings: warnings)
    }

    /// 创建纯文本回退文档
    private func createFallbackDocument(_ text: String) -> DocumentNode {
        let lines = text.components(separatedBy: .newlines)
        let blocks: [any BlockNode] = lines.map { line in
            TextBlockNode(indent: 1, content: [TextNode(text: line)])
        }
        return DocumentNode(blocks: blocks)
    }

    /// 从 Token 中提取元素名称
    private func extractElementName(from token: XMLToken?) -> String? {
        guard let token else { return nil }
        switch token {
        case let .startTag(name, _, _):
            return name
        case let .endTag(name):
            return name
        default:
            return nil
        }
    }

    /// 从 Token 中提取内容
    private func extractContent(from token: XMLToken?) -> String? {
        guard let token else { return nil }
        switch token {
        case let .text(text):
            return text
        default:
            return nil
        }
    }

    /// 跳到下一个块级元素
    private func skipToNextBlock() {
        while !isAtEnd {
            guard let token = currentToken else { break }

            switch token {
            case .newline:
                advance()
                return

            case let .startTag(name, _, _):
                if isBlockLevelTag(name) {
                    return
                }
                advance()

            default:
                advance()
            }
        }
    }

    // MARK: - 块级元素解析

    /// 解析块级元素
    private func parseBlock() throws -> (any BlockNode)? {
        guard let token = currentToken else { return nil }

        switch token {
        case let .startTag(name, attributes, selfClosing):
            return try parseBlockElement(name: name, attributes: attributes, selfClosing: selfClosing)

        case let .text(text):
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
        // 特殊处理：<new-format/> 标签
        // 这是一个元数据标记，不影响文本渲染，直接跳过
        if name == "new-format" {
            advance()
            return nil
        }

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
            let warning = ParseWarning(
                message: "跳过不支持的元素: <\(name)>",
                location: "位置 \(currentIndex)",
                type: .unsupportedElement
            )
            warnings.append(warning)
            errorLogger.logWarning(warning)

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
            if case let .endTag(name) = currentToken, name == "bullet" {
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
            if case let .endTag(name) = currentToken, name == "order" {
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
            if case let .endTag(name) = currentToken, name == "input" {
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

        let description: String? = {
            guard let rawDesc = attributes["imgdes"] else { return nil }
            var cleaned = rawDesc
            while cleaned.hasPrefix("\""), cleaned.hasSuffix("\""), cleaned.count > 1 {
                cleaned = String(cleaned.dropFirst().dropLast())
            }
            return cleaned
        }()

        let imgshow = attributes["imgshow"]

        advance()

        return ImageNode(fileId: fileId, src: src, width: width, height: height, description: description, imgshow: imgshow)
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
            if case let .endTag(name) = currentToken {
                if name == "quote" {
                    advance()
                    break
                }
            }

            // 解析内部的 text 元素
            if case let .startTag(name, attributes, selfClosing) = currentToken {
                if name == "text" {
                    let textBlock = try parseTextBlock(attributes: attributes, selfClosing: selfClosing)
                    textBlocks.append(textBlock)
                } else {
                    // 跳过其他元素
                    let warning = ParseWarning(
                        message: "引用块内跳过不支持的元素: <\(name)>",
                        location: "位置 \(currentIndex)",
                        type: .unsupportedElement
                    )
                    warnings.append(warning)
                    errorLogger.logWarning(warning)

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
            case let .endTag(name):
                if name == endTagName {
                    advance()
                    return nodes
                } else {
                    throw ParseError.unmatchedTag(expected: endTagName, found: name)
                }

            case let .text(text):
                advance()
                if !text.isEmpty {
                    nodes.append(TextNode(text: text))
                }

            case let .startTag(name, attributes, selfClosing):
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

            case let .text(text):
                advance()
                if !text.isEmpty {
                    nodes.append(TextNode(text: text))
                }

            case let .startTag(name, attributes, selfClosing):
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
        // 特殊处理：<new-format/> 标签
        // 这是一个元数据标记，不影响文本渲染，直接跳过
        if name == "new-format" {
            advance()
            return nil
        }

        // 获取对应的节点类型
        guard let nodeType = inlineTagToNodeType(name) else {
            // 不支持的行内元素，记录警告并跳过
            let warning = ParseWarning(
                message: "跳过不支持的行内元素: <\(name)>",
                location: "位置 \(currentIndex)",
                type: .unsupportedElement
            )
            warnings.append(warning)
            errorLogger.logWarning(warning)

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

        while !isAtEnd, depth > 0 {
            guard let token = currentToken else { break }

            switch token {
            case let .startTag(name, _, selfClosing):
                if name == tagName, !selfClosing {
                    depth += 1
                }
                advance()

            case let .endTag(name):
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
            true
        default:
            false
        }
    }

    /// 将行内标签名转换为节点类型
    private func inlineTagToNodeType(_ name: String) -> ASTNodeType? {
        switch name {
        case "b":
            .bold
        case "i":
            .italic
        case "u":
            .underline
        case "delete":
            .strikethrough
        case "background":
            .highlight
        case "size":
            .heading1
        case "mid-size":
            .heading2
        case "h3-size":
            .heading3
        case "center":
            .centerAlign
        case "right":
            .rightAlign
        case "new-format":
            // <new-format/> 标签是一个标记标签，表示使用新版格式
            // 它不影响文本渲染，只是一个元数据标记
            // 返回 nil 表示跳过这个标签，但不记录警告
            nil
        default:
            nil
        }
    }
}
