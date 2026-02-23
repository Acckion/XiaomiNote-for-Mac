//
//  XMLTokenizer.swift
//  MiNoteMac
//
//  XML 词法分析器
//  将 XML 字符串分解为 Token 流，支持标签识别、属性提取和 XML 实体解码
//

import Foundation

// MARK: - Token 类型

/// XML Token 类型
public enum XMLToken: Equatable, Sendable {
    /// 开始标签，如 `<text indent="1">`
    case startTag(name: String, attributes: [String: String], selfClosing: Bool)

    /// 结束标签，如 `</text>`
    case endTag(name: String)

    /// 文本内容
    case text(String)

    /// 换行符
    case newline
}

// MARK: - XMLTokenizer

/// XML 词法分析器
/// 将小米笔记 XML 字符串分解为 Token 流
public struct XMLTokenizer: Sendable {

    // MARK: - 解析上下文

    /// 封装解析过程中的可变状态
    private struct ParsingContext {
        let input: String
        var currentIndex: String.Index

        /// 是否已到达输入末尾
        var isAtEnd: Bool {
            currentIndex >= input.endIndex
        }

        /// 当前字符
        var currentChar: Character {
            input[currentIndex]
        }

        /// 前进一个字符
        mutating func advance() {
            if currentIndex < input.endIndex {
                currentIndex = input.index(after: currentIndex)
            }
        }

        /// 跳过空白字符（不包括换行符）
        mutating func skipWhitespace() {
            while !isAtEnd {
                let char = currentChar
                if char == " " || char == "\t" || char == "\r" {
                    advance()
                } else {
                    break
                }
            }
        }
    }

    // MARK: - 初始化

    public init() {}

    // MARK: - 公共方法

    /// 获取所有 Token
    /// - Parameter input: XML 字符串
    /// - Returns: Token 数组
    /// - Throws: TokenizerError
    public func tokenize(_ input: String) throws -> [XMLToken] {
        var context = ParsingContext(input: input, currentIndex: input.startIndex)
        var tokens: [XMLToken] = []

        while !context.isAtEnd {
            if let token = try nextToken(&context) {
                tokens.append(token)
            }
        }

        return tokens
    }

    // MARK: - 私有方法 - Token 解析

    /// 获取下一个 Token
    private func nextToken(_ context: inout ParsingContext) throws -> XMLToken? {
        guard !context.isAtEnd else { return nil }

        let char = context.currentChar

        // 检查换行符
        if char == "\n" {
            context.advance()
            return .newline
        }

        // 检查标签开始
        if char == "<" {
            return try parseTag(&context)
        }

        // 解析文本内容
        return try parseText(&context)
    }

    // MARK: - 私有方法 - 标签解析

    /// 解析标签（开始标签、结束标签或自闭合标签）
    private func parseTag(_ context: inout ParsingContext) throws -> XMLToken {
        // 跳过 '<'
        context.advance()

        guard !context.isAtEnd else {
            throw TokenizerError.unexpectedEndOfInput
        }

        // 检查是否为结束标签
        if context.currentChar == "/" {
            return try parseEndTag(&context)
        }

        // 解析开始标签
        return try parseStartTag(&context)
    }

    /// 解析开始标签
    private func parseStartTag(_ context: inout ParsingContext) throws -> XMLToken {
        // 解析标签名
        let tagName = parseTagName(&context)

        guard !tagName.isEmpty else {
            throw TokenizerError.invalidTagName
        }

        // 跳过空白
        context.skipWhitespace()

        // 解析属性
        var attributes: [String: String] = [:]
        while !context.isAtEnd, context.currentChar != ">", context.currentChar != "/" {
            let (name, value) = try parseAttribute(&context)
            attributes[name] = value
            context.skipWhitespace()
        }

        // 检查自闭合标签
        var selfClosing = false
        if !context.isAtEnd, context.currentChar == "/" {
            selfClosing = true
            context.advance()
        }

        // 跳过 '>'
        guard !context.isAtEnd, context.currentChar == ">" else {
            throw TokenizerError.expectedClosingBracket
        }
        context.advance()

        return .startTag(name: tagName, attributes: attributes, selfClosing: selfClosing)
    }

    /// 解析结束标签
    private func parseEndTag(_ context: inout ParsingContext) throws -> XMLToken {
        // 跳过 '/'
        context.advance()

        // 解析标签名
        let tagName = parseTagName(&context)

        guard !tagName.isEmpty else {
            throw TokenizerError.invalidTagName
        }

        // 跳过空白
        context.skipWhitespace()

        // 跳过 '>'
        guard !context.isAtEnd, context.currentChar == ">" else {
            throw TokenizerError.expectedClosingBracket
        }
        context.advance()

        return .endTag(name: tagName)
    }

    /// 解析标签名
    private func parseTagName(_ context: inout ParsingContext) -> String {
        var name = ""

        while !context.isAtEnd {
            let char = context.currentChar
            // 标签名可以包含字母、数字、连字符
            if char.isLetter || char.isNumber || char == "-" || char == "_" {
                name.append(char)
                context.advance()
            } else {
                break
            }
        }

        return name
    }

    /// 解析属性
    private func parseAttribute(_ context: inout ParsingContext) throws -> (String, String) {
        // 解析属性名
        let name = parseAttributeName(&context)

        guard !name.isEmpty else {
            throw TokenizerError.invalidAttributeName
        }

        // 跳过空白
        context.skipWhitespace()

        // 检查是否有值
        guard !context.isAtEnd, context.currentChar == "=" else {
            // 没有值的属性，返回空字符串
            return (name, "")
        }

        // 跳过 '='
        context.advance()
        context.skipWhitespace()

        // 解析属性值
        let value = try parseAttributeValue(&context)

        return (name, value)
    }

    /// 解析属性名
    private func parseAttributeName(_ context: inout ParsingContext) -> String {
        var name = ""

        while !context.isAtEnd {
            let char = context.currentChar
            if char.isLetter || char.isNumber || char == "-" || char == "_" {
                name.append(char)
                context.advance()
            } else {
                break
            }
        }

        return name
    }

    /// 解析属性值
    private func parseAttributeValue(_ context: inout ParsingContext) throws -> String {
        guard !context.isAtEnd else {
            throw TokenizerError.unexpectedEndOfInput
        }

        let quote = context.currentChar

        // 检查引号
        guard quote == "\"" || quote == "'" else {
            // 无引号的属性值
            return parseUnquotedAttributeValue(&context)
        }

        // 跳过开始引号
        context.advance()

        var value = ""

        while !context.isAtEnd, context.currentChar != quote {
            value.append(context.currentChar)
            context.advance()
        }

        // 跳过结束引号
        guard !context.isAtEnd, context.currentChar == quote else {
            throw TokenizerError.unterminatedString
        }
        context.advance()

        // 解码 XML 实体
        return XMLEntityCodec.decode(value)
    }

    /// 解析无引号的属性值
    private func parseUnquotedAttributeValue(_ context: inout ParsingContext) -> String {
        var value = ""

        while !context.isAtEnd {
            let char = context.currentChar
            if char.isWhitespace || char == ">" || char == "/" {
                break
            }
            value.append(char)
            context.advance()
        }

        return XMLEntityCodec.decode(value)
    }

    // MARK: - 私有方法 - 文本解析

    /// 解析文本内容
    private func parseText(_ context: inout ParsingContext) throws -> XMLToken {
        var text = ""

        while !context.isAtEnd {
            let char = context.currentChar

            // 检查旧格式图片标记
            if char == "\u{263A}" {
                // 如果已经累积了文本，先返回文本 Token
                if !text.isEmpty {
                    let decodedText = XMLEntityCodec.decode(text)
                    return .text(decodedText)
                }
                // 解析旧格式图片
                return try parseLegacyImage(&context)
            }

            // 遇到标签开始或换行符时停止
            if char == "<" || char == "\n" {
                break
            }

            text.append(char)
            context.advance()
        }

        // 解码 XML 实体
        let decodedText = XMLEntityCodec.decode(text)

        return .text(decodedText)
    }

    /// 解析旧格式图片
    /// 格式：\u{263A} {fileId}<0/><[{description}]/> 或 \u{263A} {fileId}<0/></>
    private func parseLegacyImage(_ context: inout ParsingContext) throws -> XMLToken {
        // 跳过特殊字符
        context.advance()

        // 跳过空白
        context.skipWhitespace()

        // 提取 fileId（直到 <0/> 标记）
        var fileId = ""
        while !context.isAtEnd {
            let char = context.currentChar

            // 检查是否到达 <0/> 标记
            if char == "<" {
                let savedIndex = context.currentIndex
                context.advance()

                if !context.isAtEnd, context.currentChar == "0" {
                    context.advance()
                    if !context.isAtEnd, context.currentChar == "/" {
                        context.advance()
                        if !context.isAtEnd, context.currentChar == ">" {
                            context.advance()
                            // 找到 <0/> 标记
                            break
                        }
                    }
                }

                // 不是 <0/> 标记，恢复位置并继续
                context.currentIndex = savedIndex
                fileId.append(char)
                context.advance()
            } else {
                fileId.append(char)
                context.advance()
            }
        }

        // 验证 fileId 不为空
        let trimmedFileId = fileId.trimmingCharacters(in: .whitespaces)
        guard !trimmedFileId.isEmpty else {
            throw TokenizerError.invalidLegacyImageFormat("缺少 fileId")
        }

        // 提取 description（支持三种格式）
        // 1. </>：空描述
        // 2. <[description]/>：方括号包裹的描述
        // 3. <description/>：标签名就是描述内容
        var description = ""

        // 查找描述标记
        if !context.isAtEnd, context.currentChar == "<" {
            context.advance()

            // 检查是否是空描述标记 </>
            if !context.isAtEnd, context.currentChar == "/" {
                context.advance()
                if !context.isAtEnd, context.currentChar == ">" {
                    context.advance()
                    // 找到 </> 标记，表示无描述
                    description = ""
                }
            } else if !context.isAtEnd, context.currentChar == "[" {
                // 格式 2：有描述的情况 <[description]/>
                context.advance()

                // 提取描述内容（直到 ]/> 标记）
                while !context.isAtEnd {
                    let char = context.currentChar

                    // 检查是否到达 ]/> 标记
                    if char == "]" {
                        let savedDescIndex = context.currentIndex
                        context.advance()

                        if !context.isAtEnd, context.currentChar == "/" {
                            context.advance()
                            if !context.isAtEnd, context.currentChar == ">" {
                                context.advance()
                                // 找到 ]/> 标记
                                break
                            }
                        }

                        // 不是 ]/> 标记，恢复位置并继续
                        context.currentIndex = savedDescIndex
                        description.append(char)
                        context.advance()
                    } else {
                        description.append(char)
                        context.advance()
                    }
                }
            } else {
                // 格式 3：<tagname/> 格式，标签名就是描述内容
                // 提取标签名（直到 /> 标记）
                while !context.isAtEnd {
                    let char = context.currentChar

                    // 检查是否到达 /> 标记
                    if char == "/" {
                        let savedDescIndex = context.currentIndex
                        context.advance()

                        if !context.isAtEnd, context.currentChar == ">" {
                            context.advance()
                            // 找到 /> 标记
                            break
                        }

                        // 不是 /> 标记，恢复位置并继续
                        context.currentIndex = savedDescIndex
                        description.append(char)
                        context.advance()
                    } else {
                        description.append(char)
                        context.advance()
                    }
                }
            }
        }

        // 生成等效的 <img> 标签 Token
        let attributes: [String: String] = [
            "fileid": trimmedFileId,
            "imgshow": "0",
            "imgdes": description,
        ]

        return .startTag(name: "img", attributes: attributes, selfClosing: true)
    }
}

// MARK: - TokenizerError

/// 词法分析错误
public enum TokenizerError: Error, LocalizedError, Sendable {
    case unexpectedEndOfInput
    case invalidTagName
    case invalidAttributeName
    case expectedClosingBracket
    case unterminatedString
    case invalidEntity(String)
    case invalidLegacyImageFormat(String)

    public var errorDescription: String? {
        switch self {
        case .unexpectedEndOfInput:
            "意外的输入结束"
        case .invalidTagName:
            "无效的标签名"
        case .invalidAttributeName:
            "无效的属性名"
        case .expectedClosingBracket:
            "期望 '>'"
        case .unterminatedString:
            "未终止的字符串"
        case let .invalidEntity(entity):
            "无效的 XML 实体: \(entity)"
        case let .invalidLegacyImageFormat(reason):
            "无效的旧格式图片: \(reason)"
        }
    }
}
