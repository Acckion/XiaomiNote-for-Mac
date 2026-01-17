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
public final class XMLTokenizer: @unchecked Sendable {
    
    // MARK: - 属性
    
    /// 输入字符串
    private let input: String
    
    /// 当前位置
    private var currentIndex: String.Index
    
    /// 是否已到达输入末尾
    private var isAtEnd: Bool {
        currentIndex >= input.endIndex
    }
    
    // MARK: - 初始化
    
    /// 创建词法分析器
    /// - Parameter input: XML 字符串
    public init(input: String) {
        self.input = input
        self.currentIndex = input.startIndex
    }
    
    // MARK: - 公共方法
    
    /// 获取所有 Token
    /// - Returns: Token 数组
    /// - Throws: TokenizerError
    public func tokenize() throws -> [XMLToken] {
        var tokens: [XMLToken] = []
        
        while !isAtEnd {
            if let token = try nextToken() {
                tokens.append(token)
            }
        }
        
        return tokens
    }
    
    /// 获取下一个 Token
    /// - Returns: Token 或 nil（如果已到达末尾）
    /// - Throws: TokenizerError
    public func nextToken() throws -> XMLToken? {
        guard !isAtEnd else { return nil }
        
        let char = currentChar
        
        // 检查换行符
        if char == "\n" {
            advance()
            return .newline
        }
        
        // 检查标签开始
        if char == "<" {
            return try parseTag()
        }
        
        // 解析文本内容
        return try parseText()
    }
    
    // MARK: - 私有方法 - 标签解析
    
    /// 解析标签（开始标签、结束标签或自闭合标签）
    private func parseTag() throws -> XMLToken {
        // 跳过 '<'
        advance()
        
        guard !isAtEnd else {
            throw TokenizerError.unexpectedEndOfInput
        }
        
        // 检查是否为结束标签
        if currentChar == "/" {
            return try parseEndTag()
        }
        
        // 解析开始标签
        return try parseStartTag()
    }
    
    /// 解析开始标签
    private func parseStartTag() throws -> XMLToken {
        // 解析标签名
        let tagName = parseTagName()
        
        guard !tagName.isEmpty else {
            throw TokenizerError.invalidTagName
        }
        
        // 跳过空白
        skipWhitespace()
        
        // 解析属性
        var attributes: [String: String] = [:]
        while !isAtEnd && currentChar != ">" && currentChar != "/" {
            let (name, value) = try parseAttribute()
            attributes[name] = value
            skipWhitespace()
        }
        
        // 检查自闭合标签
        var selfClosing = false
        if !isAtEnd && currentChar == "/" {
            selfClosing = true
            advance()
        }
        
        // 跳过 '>'
        guard !isAtEnd && currentChar == ">" else {
            throw TokenizerError.expectedClosingBracket
        }
        advance()
        
        return .startTag(name: tagName, attributes: attributes, selfClosing: selfClosing)
    }
    
    /// 解析结束标签
    private func parseEndTag() throws -> XMLToken {
        // 跳过 '/'
        advance()
        
        // 解析标签名
        let tagName = parseTagName()
        
        guard !tagName.isEmpty else {
            throw TokenizerError.invalidTagName
        }
        
        // 跳过空白
        skipWhitespace()
        
        // 跳过 '>'
        guard !isAtEnd && currentChar == ">" else {
            throw TokenizerError.expectedClosingBracket
        }
        advance()
        
        return .endTag(name: tagName)
    }
    
    /// 解析标签名
    private func parseTagName() -> String {
        var name = ""
        
        while !isAtEnd {
            let char = currentChar
            // 标签名可以包含字母、数字、连字符
            if char.isLetter || char.isNumber || char == "-" || char == "_" {
                name.append(char)
                advance()
            } else {
                break
            }
        }
        
        return name
    }
    
    /// 解析属性
    private func parseAttribute() throws -> (String, String) {
        // 解析属性名
        let name = parseAttributeName()
        
        guard !name.isEmpty else {
            throw TokenizerError.invalidAttributeName
        }
        
        // 跳过空白
        skipWhitespace()
        
        // 检查是否有值
        guard !isAtEnd && currentChar == "=" else {
            // 没有值的属性，返回空字符串
            return (name, "")
        }
        
        // 跳过 '='
        advance()
        skipWhitespace()
        
        // 解析属性值
        let value = try parseAttributeValue()
        
        return (name, value)
    }
    
    /// 解析属性名
    private func parseAttributeName() -> String {
        var name = ""
        
        while !isAtEnd {
            let char = currentChar
            if char.isLetter || char.isNumber || char == "-" || char == "_" {
                name.append(char)
                advance()
            } else {
                break
            }
        }
        
        return name
    }
    
    /// 解析属性值
    private func parseAttributeValue() throws -> String {
        guard !isAtEnd else {
            throw TokenizerError.unexpectedEndOfInput
        }
        
        let quote = currentChar
        
        // 检查引号
        guard quote == "\"" || quote == "'" else {
            // 无引号的属性值
            return parseUnquotedAttributeValue()
        }
        
        // 跳过开始引号
        advance()
        
        var value = ""
        
        while !isAtEnd && currentChar != quote {
            value.append(currentChar)
            advance()
        }
        
        // 跳过结束引号
        guard !isAtEnd && currentChar == quote else {
            throw TokenizerError.unterminatedString
        }
        advance()
        
        // 解码 XML 实体
        return XMLEntityCodec.decode(value)
    }
    
    /// 解析无引号的属性值
    private func parseUnquotedAttributeValue() -> String {
        var value = ""
        
        while !isAtEnd {
            let char = currentChar
            if char.isWhitespace || char == ">" || char == "/" {
                break
            }
            value.append(char)
            advance()
        }
        
        return XMLEntityCodec.decode(value)
    }
    
    // MARK: - 私有方法 - 文本解析
    
    /// 解析文本内容
    private func parseText() throws -> XMLToken {
        var text = ""
        
        while !isAtEnd {
            let char = currentChar
            
            // 检查旧格式图片标记 ☺
            if char == "☺" {
                // 如果已经累积了文本，先返回文本 Token
                if !text.isEmpty {
                    let decodedText = XMLEntityCodec.decode(text)
                    return .text(decodedText)
                }
                // 解析旧格式图片
                return try parseLegacyImage()
            }
            
            // 遇到标签开始或换行符时停止
            if char == "<" || char == "\n" {
                break
            }
            
            text.append(char)
            advance()
        }
        
        // 解码 XML 实体
        let decodedText = XMLEntityCodec.decode(text)
        
        return .text(decodedText)
    }
    
    /// 解析旧格式图片
    /// 格式：☺ {fileId}<0/><[{description}]/> 或 ☺ {fileId}<0/></>
    private func parseLegacyImage() throws -> XMLToken {
        // 跳过 ☺ 字符
        advance()
        
        // 跳过空白
        skipWhitespace()
        
        // 提取 fileId（直到 <0/> 标记）
        var fileId = ""
        while !isAtEnd {
            let char = currentChar
            
            // 检查是否到达 <0/> 标记
            if char == "<" {
                // 检查后续是否为 "0/>"
                let savedIndex = currentIndex
                advance()
                
                if !isAtEnd && currentChar == "0" {
                    advance()
                    if !isAtEnd && currentChar == "/" {
                        advance()
                        if !isAtEnd && currentChar == ">" {
                            advance()
                            // 找到 <0/> 标记
                            break
                        }
                    }
                }
                
                // 不是 <0/> 标记，恢复位置并继续
                currentIndex = savedIndex
                fileId.append(char)
                advance()
            } else {
                fileId.append(char)
                advance()
            }
        }
        
        // 验证 fileId 不为空
        let trimmedFileId = fileId.trimmingCharacters(in: .whitespaces)
        guard !trimmedFileId.isEmpty else {
            throw TokenizerError.invalidLegacyImageFormat("缺少 fileId")
        }
        
        // 提取 description（从 <[ 到 ]/> 之间的文本，或者 </> 表示无描述）
        var description = ""
        
        // 查找描述标记
        if !isAtEnd && currentChar == "<" {
            let savedIndex = currentIndex
            advance()
            
            // 检查是否是空描述标记 </>
            if !isAtEnd && currentChar == "/" {
                advance()
                if !isAtEnd && currentChar == ">" {
                    advance()
                    // 找到 </> 标记，表示无描述
                    description = ""
                }
            } else if !isAtEnd && currentChar == "[" {
                // 有描述的情况：<[description]/>
                advance()
                
                // 提取描述内容（直到 ]/> 标记）
                while !isAtEnd {
                    let char = currentChar
                    
                    // 检查是否到达 ]/> 标记
                    if char == "]" {
                        let savedDescIndex = currentIndex
                        advance()
                        
                        if !isAtEnd && currentChar == "/" {
                            advance()
                            if !isAtEnd && currentChar == ">" {
                                advance()
                                // 找到 ]/> 标记
                                break
                            }
                        }
                        
                        // 不是 ]/> 标记，恢复位置并继续
                        currentIndex = savedDescIndex
                        description.append(char)
                        advance()
                    } else {
                        description.append(char)
                        advance()
                    }
                }
            } else {
                // 不是预期的描述标记，恢复位置
                currentIndex = savedIndex
            }
        }
        
        // 生成等效的 <img> 标签 Token
        let attributes: [String: String] = [
            "fileid": trimmedFileId,
            "imgshow": "0",
            "imgdes": description
        ]
        
        return .startTag(name: "img", attributes: attributes, selfClosing: true)
    }
    
    // MARK: - 辅助方法
    
    /// 当前字符
    private var currentChar: Character {
        input[currentIndex]
    }
    
    /// 前进一个字符
    private func advance() {
        if currentIndex < input.endIndex {
            currentIndex = input.index(after: currentIndex)
        }
    }
    
    /// 跳过空白字符（不包括换行符）
    private func skipWhitespace() {
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
            return "意外的输入结束"
        case .invalidTagName:
            return "无效的标签名"
        case .invalidAttributeName:
            return "无效的属性名"
        case .expectedClosingBracket:
            return "期望 '>'"
        case .unterminatedString:
            return "未终止的字符串"
        case .invalidEntity(let entity):
            return "无效的 XML 实体: \(entity)"
        case .invalidLegacyImageFormat(let reason):
            return "无效的旧格式图片: \(reason)"
        }
    }
}


