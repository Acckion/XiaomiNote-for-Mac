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
public struct MiNoteXMLParser: Sendable {

    // MARK: - 解析上下文

    /// 封装解析过程中的可变状态
    private struct ParsingContext {
        /// Token 数组
        var tokens: [XMLToken] = []

        /// 当前位置
        var currentIndex = 0

        /// 解析警告
        var warnings: [ParseWarning] = []

        /// 是否启用错误恢复
        var enableErrorRecovery = true

        /// 是否已到达末尾
        var isAtEnd: Bool {
            currentIndex >= tokens.count
        }

        /// 当前 Token
        var currentToken: XMLToken? {
            guard !isAtEnd else { return nil }
            return tokens[currentIndex]
        }

        /// 前进一个 Token
        mutating func advance() {
            if currentIndex < tokens.count {
                currentIndex += 1
            }
        }
    }

    // MARK: - 属性

    /// 错误日志记录器
    private let errorLogger: ErrorLogger

    /// 错误恢复处理器
    private let errorRecoveryHandler: ErrorRecoveryHandler

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
        var ctx = ParsingContext()

        LogService.shared.debug(.editor, "开始解析 XML，长度: \(xml.count)")

        do {
            let tokenizer = XMLTokenizer()
            ctx.tokens = try tokenizer.tokenize(xml)
        } catch {
            if ctx.enableErrorRecovery {
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

        while !ctx.isAtEnd {
            if case .newline = ctx.currentToken {
                ctx.advance()
                continue
            }

            if case let .startTag(name, _, selfClosing) = ctx.currentToken, name == "title" {
                ctx.advance()

                if !selfClosing {
                    if case let .text(titleText) = ctx.currentToken {
                        title = titleText
                        ctx.advance()
                    }

                    if case let .endTag(endName) = ctx.currentToken, endName == "title" {
                        ctx.advance()
                    }
                }

                continue
            }

            do {
                if let block = try parseBlock(ctx: &ctx) {
                    blocks.append(block)
                }
            } catch let error as ParseError {
                if ctx.enableErrorRecovery {
                    let context = ErrorContext(
                        elementName: extractElementName(from: ctx.currentToken),
                        content: extractContent(from: ctx.currentToken),
                        position: ctx.currentIndex
                    )

                    let strategy = errorRecoveryHandler.handleError(error, context: context)

                    switch strategy {
                    case .skipElement:
                        let warning = ParseWarning(
                            message: "跳过错误元素: \(error.localizedDescription)",
                            location: "位置 \(ctx.currentIndex)",
                            type: .unsupportedElement
                        )
                        ctx.warnings.append(warning)
                        errorLogger.logWarning(warning)
                        skipToNextBlock(ctx: &ctx)

                    case .fallbackToPlainText:
                        if let content = context.content {
                            let textBlock = TextBlockNode(indent: 1, content: [TextNode(text: content)])
                            blocks.append(textBlock)
                        }
                        ctx.advance()

                    case .useDefaultValue:
                        ctx.advance()

                    case .abort:
                        throw error
                    }
                } else {
                    throw error
                }
            }
        }

        return ParseResult(value: DocumentNode(title: title, blocks: blocks), warnings: ctx.warnings)
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
    private func skipToNextBlock(ctx: inout ParsingContext) {
        while !ctx.isAtEnd {
            guard let token = ctx.currentToken else { break }

            switch token {
            case .newline:
                ctx.advance()
                return

            case let .startTag(name, _, _):
                if isBlockLevelTag(name) {
                    return
                }
                ctx.advance()

            default:
                ctx.advance()
            }
        }
    }

    // MARK: - 块级元素解析

    /// 解析块级元素
    private func parseBlock(ctx: inout ParsingContext) throws -> (any BlockNode)? {
        guard let token = ctx.currentToken else { return nil }

        switch token {
        case let .startTag(name, attributes, selfClosing):
            return try parseBlockElement(name: name, attributes: attributes, selfClosing: selfClosing, ctx: &ctx)

        case let .text(text):
            ctx.advance()
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                return TextBlockNode(indent: 1, content: [TextNode(text: text)])
            }
            return nil

        case .endTag:
            ctx.advance()
            return nil

        case .newline:
            ctx.advance()
            return nil
        }
    }

    /// 解析块级元素
    private func parseBlockElement(
        name: String,
        attributes: [String: String],
        selfClosing: Bool,
        ctx: inout ParsingContext
    ) throws -> (any BlockNode)? {
        // <new-format/> 是元数据标记，不影响文本渲染
        if name == "new-format" {
            ctx.advance()
            return nil
        }

        switch name {
        case "text":
            return try parseTextBlock(attributes: attributes, selfClosing: selfClosing, ctx: &ctx)

        case "bullet":
            return try parseBulletList(attributes: attributes, selfClosing: selfClosing, ctx: &ctx)

        case "order":
            return try parseOrderedList(attributes: attributes, selfClosing: selfClosing, ctx: &ctx)

        case "input":
            return try parseCheckbox(attributes: attributes, selfClosing: selfClosing, ctx: &ctx)

        case "hr":
            ctx.advance()
            return HorizontalRuleNode()

        case "img":
            return try parseImage(attributes: attributes, ctx: &ctx)

        case "sound":
            return try parseAudio(attributes: attributes, ctx: &ctx)

        case "quote":
            return try parseQuote(selfClosing: selfClosing, ctx: &ctx)

        default:
            let warning = ParseWarning(
                message: "跳过不支持的元素: <\(name)>",
                location: "位置 \(ctx.currentIndex)",
                type: .unsupportedElement
            )
            ctx.warnings.append(warning)
            errorLogger.logWarning(warning)

            ctx.advance()
            if !selfClosing {
                try skipUntilEndTag(name, ctx: &ctx)
            }
            return nil
        }
    }

    // MARK: - 具体块级元素解析

    /// 解析文本块 `<text indent="N">内容</text>`
    private func parseTextBlock(attributes: [String: String], selfClosing: Bool, ctx: inout ParsingContext) throws -> TextBlockNode {
        let indent = Int(attributes["indent"] ?? "1") ?? 1

        ctx.advance()

        if selfClosing {
            return TextBlockNode(indent: indent, content: [])
        }

        let content = try parseInlineContent(until: "text", ctx: &ctx)

        return TextBlockNode(indent: indent, content: content)
    }

    /// 解析无序列表 `<bullet indent="N" />内容`
    private func parseBulletList(attributes: [String: String], selfClosing: Bool, ctx: inout ParsingContext) throws -> BulletListNode {
        let indent = Int(attributes["indent"] ?? "1") ?? 1

        ctx.advance()

        if !selfClosing {
            if case let .endTag(name) = ctx.currentToken, name == "bullet" {
                ctx.advance()
            }
        }

        let content = try parseContentAfterTag(ctx: &ctx)

        return BulletListNode(indent: indent, content: content)
    }

    /// 解析有序列表 `<order indent="N" inputNumber="M" />内容`
    private func parseOrderedList(attributes: [String: String], selfClosing: Bool, ctx: inout ParsingContext) throws -> OrderedListNode {
        let indent = Int(attributes["indent"] ?? "1") ?? 1
        let inputNumber = Int(attributes["inputNumber"] ?? "0") ?? 0

        ctx.advance()

        if !selfClosing {
            if case let .endTag(name) = ctx.currentToken, name == "order" {
                ctx.advance()
            }
        }

        let content = try parseContentAfterTag(ctx: &ctx)

        return OrderedListNode(indent: indent, inputNumber: inputNumber, content: content)
    }

    /// 解析复选框 `<input type="checkbox" indent="N" level="M" />内容`
    private func parseCheckbox(attributes: [String: String], selfClosing: Bool, ctx: inout ParsingContext) throws -> CheckboxNode {
        guard attributes["type"] == "checkbox" else {
            throw ParseError.unsupportedElement("input type=\"\(attributes["type"] ?? "unknown")\"")
        }

        let indent = Int(attributes["indent"] ?? "1") ?? 1
        let level = Int(attributes["level"] ?? "1") ?? 1
        let isChecked = attributes["checked"] == "true"

        ctx.advance()

        if !selfClosing {
            if case let .endTag(name) = ctx.currentToken, name == "input" {
                ctx.advance()
            }
        }

        let content = try parseContentAfterTag(ctx: &ctx)

        return CheckboxNode(indent: indent, level: level, isChecked: isChecked, content: content)
    }

    /// 解析图片 `<img fileid="ID" />` 或 `<img src="URL" />`
    private func parseImage(attributes: [String: String], ctx: inout ParsingContext) throws -> ImageNode {
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

        ctx.advance()

        return ImageNode(fileId: fileId, src: src, width: width, height: height, description: description, imgshow: imgshow)
    }

    /// 解析音频 `<sound fileid="ID" />`
    private func parseAudio(attributes: [String: String], ctx: inout ParsingContext) throws -> AudioNode {
        guard let fileId = attributes["fileid"] else {
            throw ParseError.missingAttribute(tag: "sound", attribute: "fileid")
        }

        let isTemporary = attributes["temporary"] == "true"

        ctx.advance()

        return AudioNode(fileId: fileId, isTemporary: isTemporary)
    }

    /// 解析引用块 `<quote>多行内容</quote>`
    private func parseQuote(selfClosing: Bool, ctx: inout ParsingContext) throws -> QuoteNode {
        ctx.advance()

        if selfClosing {
            return QuoteNode(textBlocks: [])
        }

        var textBlocks: [TextBlockNode] = []

        while !ctx.isAtEnd {
            if case .newline = ctx.currentToken {
                ctx.advance()
                continue
            }

            if case let .endTag(name) = ctx.currentToken {
                if name == "quote" {
                    ctx.advance()
                    break
                }
            }

            if case let .startTag(name, attributes, selfClosing) = ctx.currentToken {
                if name == "text" {
                    let textBlock = try parseTextBlock(attributes: attributes, selfClosing: selfClosing, ctx: &ctx)
                    textBlocks.append(textBlock)
                } else {
                    let warning = ParseWarning(
                        message: "引用块内跳过不支持的元素: <\(name)>",
                        location: "位置 \(ctx.currentIndex)",
                        type: .unsupportedElement
                    )
                    ctx.warnings.append(warning)
                    errorLogger.logWarning(warning)

                    ctx.advance()
                    if !selfClosing {
                        try skipUntilEndTag(name, ctx: &ctx)
                    }
                }
            } else {
                ctx.advance()
            }
        }

        return QuoteNode(textBlocks: textBlocks)
    }

    // MARK: - 行内内容解析

    /// 解析行内内容直到指定的结束标签
    private func parseInlineContent(until endTagName: String, ctx: inout ParsingContext) throws -> [any InlineNode] {
        var nodes: [any InlineNode] = []

        while !ctx.isAtEnd {
            guard let token = ctx.currentToken else { break }

            switch token {
            case let .endTag(name):
                if name == endTagName {
                    ctx.advance()
                    return nodes
                } else {
                    throw ParseError.unmatchedTag(expected: endTagName, found: name)
                }

            case let .text(text):
                ctx.advance()
                if !text.isEmpty {
                    nodes.append(TextNode(text: text))
                }

            case let .startTag(name, attributes, selfClosing):
                if let inlineNode = try parseInlineElement(name: name, attributes: attributes, selfClosing: selfClosing, ctx: &ctx) {
                    nodes.append(inlineNode)
                }

            case .newline:
                ctx.advance()
                nodes.append(TextNode(text: "\n"))
            }
        }

        throw ParseError.unexpectedEndOfInput
    }

    /// 解析标签后的内容（用于 bullet/order/checkbox）
    private func parseContentAfterTag(ctx: inout ParsingContext) throws -> [any InlineNode] {
        var nodes: [any InlineNode] = []

        while !ctx.isAtEnd {
            guard let token = ctx.currentToken else { break }

            switch token {
            case .newline:
                ctx.advance()
                return nodes

            case let .text(text):
                ctx.advance()
                if !text.isEmpty {
                    nodes.append(TextNode(text: text))
                }

            case let .startTag(name, attributes, selfClosing):
                if isBlockLevelTag(name) {
                    return nodes
                }

                if let inlineNode = try parseInlineElement(name: name, attributes: attributes, selfClosing: selfClosing, ctx: &ctx) {
                    nodes.append(inlineNode)
                }

            case .endTag:
                return nodes
            }
        }

        return nodes
    }

    /// 解析行内元素
    private func parseInlineElement(
        name: String,
        attributes: [String: String],
        selfClosing: Bool,
        ctx: inout ParsingContext
    ) throws -> (any InlineNode)? {
        // <new-format/> 是元数据标记，不影响文本渲染
        if name == "new-format" {
            ctx.advance()
            return nil
        }

        guard let nodeType = inlineTagToNodeType(name) else {
            let warning = ParseWarning(
                message: "跳过不支持的行内元素: <\(name)>",
                location: "位置 \(ctx.currentIndex)",
                type: .unsupportedElement
            )
            ctx.warnings.append(warning)
            errorLogger.logWarning(warning)

            ctx.advance()
            if !selfClosing {
                try skipUntilEndTag(name, ctx: &ctx)
            }
            return nil
        }

        ctx.advance()

        if selfClosing {
            return FormattedNode(type: nodeType, content: [], color: attributes["color"])
        }

        let content = try parseInlineContent(until: name, ctx: &ctx)

        let color = (nodeType == .highlight) ? attributes["color"] : nil
        return FormattedNode(type: nodeType, content: content, color: color)
    }

    // MARK: - 辅助方法

    /// 跳过直到指定的结束标签
    private func skipUntilEndTag(_ tagName: String, ctx: inout ParsingContext) throws {
        var depth = 1

        while !ctx.isAtEnd, depth > 0 {
            guard let token = ctx.currentToken else { break }

            switch token {
            case let .startTag(name, _, selfClosing):
                if name == tagName, !selfClosing {
                    depth += 1
                }
                ctx.advance()

            case let .endTag(name):
                if name == tagName {
                    depth -= 1
                }
                ctx.advance()

            default:
                ctx.advance()
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
            nil
        default:
            nil
        }
    }
}
