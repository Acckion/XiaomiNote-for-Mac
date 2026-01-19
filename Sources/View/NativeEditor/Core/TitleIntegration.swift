//
//  TitleIntegration.swift
//  MiNoteMac
//
//  标题集成管理器
//  负责在编辑器和 XML 格式之间处理标题的提取、插入和转换
//
//  Created by Paper-inspired Editor Refactor
//

import Foundation
import AppKit

/// 标题集成管理器
///
/// 核心职责：
/// 1. 从 XML 提取标题文本
/// 2. 将标题作为第一个段落插入编辑器
/// 3. 从编辑器提取标题文本
/// 4. 在 XML 转换时处理标题段落
///
/// 设计原则：
/// - 标题始终是编辑器中的第一个段落（type=title）
/// - 标题在 XML 中表示为 `<title>` 标签
/// - 保持与现有 XML 格式的完全兼容性
///
/// _Requirements: 3.1, 3.3, 3.4, 3.5, 3.6_
@MainActor
public final class TitleIntegration {
    
    // MARK: - Singleton
    
    /// 共享实例
    public static let shared = TitleIntegration()
    
    private init() {}
    
    // MARK: - XML 标题提取
    
    /// 从 XML 提取标题
    ///
    /// 解析 XML 字符串，查找 `<title>` 标签并提取其内容
    ///
    /// - Parameter xml: XML 字符串
    /// - Returns: 标题文本，如果没有找到标题则返回空字符串
    ///
    /// _Requirements: 3.1_ - 从 XML 提取标题文本
    ///
    /// 示例：
    /// ```xml
    /// <title>我的笔记标题</title>
    /// ```
    /// 返回: "我的笔记标题"
    public func extractTitle(from xml: String) -> String {
        // 查找 <title> 标签
        guard let titleRange = xml.range(of: "<title>") else {
            return ""
        }
        
        // 查找 </title> 结束标签
        guard let endTitleRange = xml.range(of: "</title>", range: titleRange.upperBound..<xml.endIndex) else {
            return ""
        }
        
        // 提取标题内容
        let titleContent = String(xml[titleRange.upperBound..<endTitleRange.lowerBound])
        
        // 解码 XML 实体
        return decodeXMLEntities(titleContent)
    }
    
    // MARK: - 编辑器标题插入
    
    /// 将标题插入编辑器
    ///
    /// 将标题作为第一个段落插入到 NSTextStorage 中
    /// 标题段落使用特殊的格式标记（通过自定义属性）
    ///
    /// - Parameters:
    ///   - title: 标题文本
    ///   - textStorage: 文本存储对象
    ///
    /// _Requirements: 3.1_ - 将标题作为第一个段落插入编辑器
    ///
    /// 注意：
    /// - 如果 textStorage 已有内容，标题会插入到最前面
    /// - 标题后会自动添加换行符
    /// - 标题使用自定义属性 `paragraphType` 标记为 `.title`
    public func insertTitle(_ title: String, into textStorage: NSTextStorage) {
        // 如果标题为空，不插入
        guard !title.isEmpty else { return }
        
        // 创建标题的 NSAttributedString
        let titleString = NSMutableAttributedString(string: title + "\n")
        
        // 设置标题的自定义属性
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .paragraphType: ParagraphType.title,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]
        
        titleString.addAttributes(
            titleAttributes,
            range: NSRange(location: 0, length: titleString.length)
        )
        
        // 插入到文本存储的开头
        textStorage.beginEditing()
        textStorage.insert(titleString, at: 0)
        textStorage.endEditing()
    }
    
    // MARK: - 编辑器标题提取
    
    /// 从编辑器提取标题
    ///
    /// 从 NSTextStorage 中提取第一个段落作为标题
    /// 如果第一个段落标记为 `.title` 类型，则提取其文本内容
    ///
    /// - Parameter textStorage: 文本存储对象
    /// - Returns: 标题文本，如果没有标题段落则返回空字符串
    ///
    /// _Requirements: 3.3_ - 从编辑器提取标题文本
    ///
    /// 注意：
    /// - 只提取第一个段落的文本
    /// - 会移除末尾的换行符
    /// - 如果第一个段落不是标题类型，返回空字符串
    public func extractTitle(from textStorage: NSTextStorage) -> String {
        // 如果文本存储为空，返回空字符串
        guard textStorage.length > 0 else {
            return ""
        }
        
        // 查找第一个换行符的位置
        let fullText = textStorage.string
        let firstLineEnd: Int
        
        if let newlineRange = fullText.range(of: "\n") {
            firstLineEnd = fullText.distance(from: fullText.startIndex, to: newlineRange.lowerBound)
        } else {
            // 如果没有换行符，整个文本就是标题
            firstLineEnd = fullText.count
        }
        
        // 提取第一行文本
        let firstLineRange = NSRange(location: 0, length: firstLineEnd)
        
        // 检查第一行是否标记为标题类型
        var isTitle = false
        if firstLineEnd > 0 {
            let attributes = textStorage.attributes(at: 0, effectiveRange: nil)
            if let paragraphType = attributes[.paragraphType] as? ParagraphType,
               paragraphType == .title {
                isTitle = true
            }
        }
        
        // 如果不是标题类型，返回空字符串
        guard isTitle else {
            return ""
        }
        
        // 提取标题文本
        let titleText = (fullText as NSString).substring(with: firstLineRange)
        return titleText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - XML 转换支持
    
    /// 转换为 XML 时处理标题
    ///
    /// 从 NSTextStorage 提取标题并生成 XML 的 `<title>` 标签
    ///
    /// - Parameter textStorage: 文本存储对象
    /// - Returns: XML 标题标签字符串，如果没有标题则返回空字符串
    ///
    /// _Requirements: 3.4_ - 将第一个段落（type=title）转换为 XML 的 `<title>` 标签
    ///
    /// 示例输出：
    /// ```xml
    /// <title>我的笔记标题</title>
    /// ```
    public func convertTitleToXML(from textStorage: NSTextStorage) -> String {
        let title = extractTitle(from: textStorage)
        
        // 如果没有标题，返回空字符串
        guard !title.isEmpty else {
            return ""
        }
        
        // 编码 XML 实体
        let encodedTitle = encodeXMLEntities(title)
        
        return "<title>\(encodedTitle)</title>"
    }
    
    /// 从 XML 加载时处理标题
    ///
    /// 从 XML 提取标题并插入到 NSTextStorage 的开头
    ///
    /// - Parameters:
    ///   - xml: XML 字符串
    ///   - textStorage: 文本存储对象
    ///
    /// _Requirements: 3.5_ - 从 XML 的 `<title>` 标签加载为第一个段落
    ///
    /// 注意：
    /// - 如果 XML 中没有标题，不会插入任何内容
    /// - 如果 textStorage 已有内容，标题会插入到最前面
    public func loadTitleFromXML(_ xml: String, into textStorage: NSTextStorage) {
        let title = extractTitle(from: xml)
        
        // 如果没有标题，不插入
        guard !title.isEmpty else {
            return
        }
        
        // 插入标题到编辑器
        insertTitle(title, into: textStorage)
    }
    
    /// 从 XML 内容中移除标题标签
    ///
    /// 用于在加载 XML 时，先提取标题，然后移除标题标签，
    /// 以便后续处理其他内容时不会重复处理标题
    ///
    /// - Parameter xml: XML 字符串
    /// - Returns: 移除标题标签后的 XML 字符串
    ///
    /// _Requirements: 3.6_ - 保持与现有 XML 格式的兼容性
    public func removeTitleTag(from xml: String) -> String {
        // 查找 <title> 标签
        guard let titleRange = xml.range(of: "<title>") else {
            return xml
        }
        
        // 查找 </title> 结束标签
        guard let endTitleRange = xml.range(of: "</title>", range: titleRange.upperBound..<xml.endIndex) else {
            return xml
        }
        
        // 移除整个标题标签（包括开始和结束标签）
        var result = xml
        result.removeSubrange(titleRange.lowerBound...endTitleRange.upperBound)
        
        // 移除标题后可能留下的空行
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return result
    }
    
    // MARK: - 辅助方法
    
    /// 解码 XML 实体
    ///
    /// 将 XML 实体（如 `&lt;`, `&gt;`, `&amp;` 等）转换为对应的字符
    ///
    /// - Parameter text: 包含 XML 实体的文本
    /// - Returns: 解码后的文本
    private func decodeXMLEntities(_ text: String) -> String {
        var result = text
        
        // 标准 XML 实体
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&amp;", with: "&")  // 必须最后处理
        
        return result
    }
    
    /// 编码 XML 实体
    ///
    /// 将特殊字符转换为 XML 实体，以便安全地嵌入 XML 中
    ///
    /// - Parameter text: 原始文本
    /// - Returns: 编码后的文本
    private func encodeXMLEntities(_ text: String) -> String {
        var result = text
        
        // 必须首先处理 &，避免重复编码
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        
        return result
    }
}

// MARK: - NSAttributedString.Key Extension

extension NSAttributedString.Key {
    /// 段落类型属性键
    ///
    /// 用于标记段落的类型（如标题、普通段落、列表等）
    /// 值类型为 `ParagraphType` 枚举
    static let paragraphType = NSAttributedString.Key("ParagraphType")
}
