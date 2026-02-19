//
//  TitleExtractionService.swift
//  MiNoteMac
//
//  标题提取服务
//  负责从不同来源（XML、原生编辑器）提取标题文本，并提供标题验证功能
//
//  Created by Title Content Integration Fix
//

import AppKit
import Foundation

/// 标题提取服务
///
/// 核心职责：
/// 1. 从 XML 内容提取标题文本
/// 2. 从原生编辑器（NSTextStorage）提取标题文本
/// 3. 提供标题验证和清理功能
/// 4. 处理特殊字符和 XML 实体编码
///
/// 设计原则：
/// - 提供统一的标题提取接口
/// - 确保提取结果的一致性和可靠性
/// - 支持多种数据源（XML、NSTextStorage）
/// - 包含完善的错误处理和验证逻辑
///
@MainActor
public final class TitleExtractionService {

    // MARK: - Singleton

    /// 共享实例
    public static let shared = TitleExtractionService()

    private init() {}

    // MARK: - 公共接口

    /// 从 XML 内容提取标题
    ///
    /// 解析 XML 字符串，查找 `<title>` 标签并提取其内容
    /// 自动处理 XML 实体编码和解码
    ///
    /// - Parameter xmlContent: XML 字符串内容
    /// - Returns: TitleExtractionResult 包含提取结果和元数据
    ///
    ///
    /// 示例：
    /// ```xml
    /// <title>我的笔记标题 &amp; 特殊字符</title>
    /// ```
    /// 返回: TitleExtractionResult(title: "我的笔记标题 & 特殊字符", source: .xml, isValid: true)
    public func extractTitleFromXML(_ xmlContent: String) -> TitleExtractionResult {
        LogService.shared.debug(.editor, "开始从 XML 提取标题")

        // 验证输入
        guard !xmlContent.isEmpty else {
            LogService.shared.debug(.editor, "XML 内容为空")
            return TitleExtractionResult(
                title: "",
                source: .xml,
                isValid: true,
                extractionTime: Date(),
                originalLength: 0,
                processedLength: 0
            )
        }

        let originalLength = xmlContent.count

        // 查找 <title> 标签
        guard let titleRange = xmlContent.range(of: "<title>") else {
            LogService.shared.debug(.editor, "未找到 title 标签")
            return TitleExtractionResult(
                title: "",
                source: .xml,
                isValid: true,
                extractionTime: Date(),
                originalLength: originalLength,
                processedLength: 0
            )
        }

        // 查找 </title> 结束标签
        guard let endTitleRange = xmlContent.range(of: "</title>", range: titleRange.upperBound ..< xmlContent.endIndex) else {
            LogService.shared.debug(.editor, "未找到 title 结束标签")
            return TitleExtractionResult(
                title: "",
                source: .xml,
                isValid: false,
                extractionTime: Date(),
                originalLength: originalLength,
                processedLength: 0,
                error: "XML 格式错误：缺少 </title> 结束标签"
            )
        }

        // 提取标题内容
        let rawTitleContent = String(xmlContent[titleRange.upperBound ..< endTitleRange.lowerBound])

        // 解码 XML 实体
        let decodedTitle = decodeXMLEntities(rawTitleContent)

        // 验证和清理标题
        let cleanedTitle = validateAndCleanTitle(decodedTitle)

        let result = TitleExtractionResult(
            title: cleanedTitle,
            source: .xml,
            isValid: true,
            extractionTime: Date(),
            originalLength: originalLength,
            processedLength: cleanedTitle.count
        )

        LogService.shared.info(.editor, "从 XML 提取标题成功: '\(cleanedTitle)'")
        return result
    }

    /// 从原生编辑器提取标题
    ///
    /// 从 NSTextStorage 中提取第一个标记为标题的段落
    /// 支持通过 `.isTitle` 属性或 `.paragraphType` 属性识别标题段落
    ///
    /// - Parameter textStorage: NSTextStorage 对象
    /// - Returns: TitleExtractionResult 包含提取结果和元数据
    ///
    ///
    /// 注意：
    /// - 只提取第一个段落的文本
    /// - 会移除末尾的换行符和空白字符
    /// - 如果第一个段落不是标题类型，返回空字符串
    public func extractTitleFromEditor(_ textStorage: NSTextStorage) -> TitleExtractionResult {
        LogService.shared.debug(.editor, "开始从编辑器提取标题")

        // 验证输入
        guard textStorage.length > 0 else {
            LogService.shared.debug(.editor, "编辑器内容为空")
            return TitleExtractionResult(
                title: "",
                source: .nativeEditor,
                isValid: true,
                extractionTime: Date(),
                originalLength: 0,
                processedLength: 0
            )
        }

        let originalLength = textStorage.length
        let fullText = textStorage.string

        // 查找第一个换行符的位置
        let firstLineEnd: Int = if let newlineRange = fullText.range(of: "\n") {
            fullText.distance(from: fullText.startIndex, to: newlineRange.lowerBound)
        } else {
            // 如果没有换行符，整个文本就是第一行
            fullText.count
        }

        // 提取第一行文本
        let firstLineRange = NSRange(location: 0, length: firstLineEnd)

        // 检查第一行是否标记为标题类型
        var isTitle = false
        var titleCheckMethod = ""

        if firstLineEnd > 0 {
            let attributes = textStorage.attributes(at: 0, effectiveRange: nil)

            // 方法1：检查 .isTitle 属性
            if let isTitleAttr = attributes[.isTitle] as? Bool, isTitleAttr {
                isTitle = true
                titleCheckMethod = ".isTitle 属性"
            }
            // 方法2：检查 .paragraphType 属性
            else if let paragraphType = attributes[.paragraphType] as? ParagraphType,
                    paragraphType == .title
            {
                isTitle = true
                titleCheckMethod = ".paragraphType 属性"
            }
        }

        // 如果不是标题类型，返回空字符串
        guard isTitle else {
            LogService.shared.debug(.editor, "第一行不是标题段落")
            return TitleExtractionResult(
                title: "",
                source: .nativeEditor,
                isValid: true,
                extractionTime: Date(),
                originalLength: originalLength,
                processedLength: 0
            )
        }

        // 提取标题文本
        let rawTitleText = (fullText as NSString).substring(with: firstLineRange)

        // 验证和清理标题
        let cleanedTitle = validateAndCleanTitle(rawTitleText)

        let result = TitleExtractionResult(
            title: cleanedTitle,
            source: .nativeEditor,
            isValid: true,
            extractionTime: Date(),
            originalLength: originalLength,
            processedLength: cleanedTitle.count
        )

        LogService.shared.info(.editor, "从编辑器提取标题成功: '\(cleanedTitle)'")
        return result
    }

    /// 验证标题内容
    ///
    /// 检查标题是否符合基本要求：
    /// - 长度限制（最大 200 字符）
    /// - 不包含换行符
    /// - 不包含控制字符
    ///
    /// - Parameter title: 待验证的标题文本
    /// - Returns: 验证结果，包含是否有效和错误信息
    ///
    public func validateTitle(_ title: String) -> (isValid: Bool, error: String?) {
        // 检查长度限制
        if title.count > 200 {
            return (false, "标题长度超过限制（最大 200 字符）")
        }

        // 检查是否包含换行符
        if title.contains("\n") || title.contains("\r") {
            return (false, "标题不能包含换行符")
        }

        // 检查是否包含控制字符
        let controlCharacters = CharacterSet.controlCharacters
        if title.rangeOfCharacter(from: controlCharacters) != nil {
            return (false, "标题不能包含控制字符")
        }

        return (true, nil)
    }

    // MARK: - 私有辅助方法

    /// 验证和清理标题文本
    ///
    /// 执行以下操作：
    /// 1. 移除首尾空白字符和换行符
    /// 2. 将内部的多个空白字符合并为单个空格
    /// 3. 验证标题有效性
    ///
    /// - Parameter rawTitle: 原始标题文本
    /// - Returns: 清理后的标题文本
    private func validateAndCleanTitle(_ rawTitle: String) -> String {
        // 移除首尾空白字符和换行符
        var cleanedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // 将内部的多个空白字符合并为单个空格
        cleanedTitle = cleanedTitle.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        // 验证标题
        let validation = validateTitle(cleanedTitle)
        if !validation.isValid {
            LogService.shared.warning(.editor, "标题验证失败: \(validation.error ?? "未知错误")")
            if cleanedTitle.count > 200 {
                cleanedTitle = String(cleanedTitle.prefix(200))
                LogService.shared.debug(.editor, "标题已截断到 200 字符")
            }
        }

        return cleanedTitle
    }

    /// 解码 XML 实体
    ///
    /// 将 XML 实体（如 `&lt;`, `&gt;`, `&amp;` 等）转换为对应的字符
    /// 支持标准 XML 实体和数字字符引用
    ///
    /// - Parameter text: 包含 XML 实体的文本
    /// - Returns: 解码后的文本
    ///
    private func decodeXMLEntities(_ text: String) -> String {
        var result = text

        // 标准 XML 实体（注意顺序：&amp; 必须最后处理）
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&amp;", with: "&")

        // 处理数字字符引用（如 &#39; &#x27;）
        result = decodeNumericCharacterReferences(result)

        return result
    }

    /// 解码数字字符引用
    ///
    /// 处理形如 `&#39;` (十进制) 和 `&#x27;` (十六进制) 的字符引用
    ///
    /// - Parameter text: 包含数字字符引用的文本
    /// - Returns: 解码后的文本
    private func decodeNumericCharacterReferences(_ text: String) -> String {
        var result = text

        // 处理十进制字符引用 &#数字;
        let decimalPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: decimalPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))

            // 从后往前替换，避免索引变化问题
            for match in matches.reversed() {
                if let numberRange = Range(match.range(at: 1), in: result),
                   let number = Int(result[numberRange]),
                   let scalar = UnicodeScalar(number)
                {
                    let character = String(Character(scalar))
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: character)
                }
            }
        }

        // 处理十六进制字符引用 &#x十六进制;
        let hexPattern = "&#x([0-9a-fA-F]+);"
        if let regex = try? NSRegularExpression(pattern: hexPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))

            // 从后往前替换，避免索引变化问题
            for match in matches.reversed() {
                if let hexRange = Range(match.range(at: 1), in: result),
                   let number = Int(result[hexRange], radix: 16),
                   let scalar = UnicodeScalar(number)
                {
                    let character = String(Character(scalar))
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: character)
                }
            }
        }

        return result
    }
}
