//
//  XiaoMiFormatConverter.swift
//  MiNoteMac
//
//  小米笔记格式转换器 - 负责 AttributedString 与小米笔记 XML 格式之间的转换
//

import Foundation
import SwiftUI
import AppKit

// MARK: - Extensions

extension NSColor {
    /// 从十六进制字符串创建颜色
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
    
    /// 转换为十六进制字符串
    func toHexString() -> String {
        let red = Int(round(redComponent * 255))
        let green = Int(round(greenComponent * 255))
        let blue = Int(round(blueComponent * 255))
        let alpha = Int(round(alphaComponent * 255))
        
        if alpha < 255 {
            return String(format: "#%02x%02x%02x%02x", alpha, red, green, blue)
        } else {
            return String(format: "#%02x%02x%02x", red, green, blue)
        }
    }
}

extension NSFont {
    /// 获取斜体版本
    func italic() -> NSFont {
        let fontDescriptor = self.fontDescriptor
        let italicDescriptor = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: italicDescriptor, size: self.pointSize) ?? self
    }
}

extension Color {
    /// 转换为 NSColor
    var nsColor: NSColor {
        return NSColor(self)
    }
    
    /// 转换为十六进制字符串
    func toHexString() -> String {
        return nsColor.toHexString()
    }
}

// MARK: - 导入自定义附件类型
// 注意：InteractiveCheckboxAttachment, HorizontalRuleAttachment, BulletAttachment, OrderAttachment
// 已在 Sources/View/NativeEditor/CustomAttachments.swift 中定义

/// 转换错误类型
enum ConversionError: Error, LocalizedError {
    case invalidXML(String)
    case conversionFailed(Error)
    case conversionInconsistent
    case unsupportedElement(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidXML(let message):
            return "无效的 XML 格式: \(message)"
        case .conversionFailed(let error):
            return "转换失败: \(error.localizedDescription)"
        case .conversionInconsistent:
            return "转换结果不一致"
        case .unsupportedElement(let element):
            return "不支持的元素: \(element)"
        }
    }
}

/// 小米笔记格式转换器
@MainActor
class XiaoMiFormatConverter {
    
    // MARK: - Singleton
    
    @MainActor
    static let shared = XiaoMiFormatConverter()
    
    private init() {}
    
    // MARK: - Properties
    
    /// 当前有序列表编号（用于跟踪连续列表）
    private var currentOrderedListNumber: Int = 1
    
    // MARK: - Public Methods
    
    /// 将 AttributedString 转换为小米笔记 XML 格式
    /// - Parameter attributedString: 要转换的 AttributedString
    /// - Returns: 小米笔记 XML 格式字符串
    /// - Throws: ConversionError
    func attributedStringToXML(_ attributedString: AttributedString) throws -> String {
        var xmlElements: [String] = []
        
        // 将 AttributedString 按换行符分割成行
        let fullText = String(attributedString.characters)
        let lines = fullText.components(separatedBy: "\n")
        
        var currentIndex = attributedString.startIndex
        
        for (lineIndex, lineText) in lines.enumerated() {
            guard !lineText.isEmpty else {
                // 空行，跳过但更新索引
                if lineIndex < lines.count - 1 {
                    // 跳过换行符
                    if currentIndex < attributedString.endIndex {
                        currentIndex = attributedString.characters.index(after: currentIndex)
                    }
                }
                continue
            }
            
            // 计算当前行在 AttributedString 中的范围
            let lineEndIndex = attributedString.characters.index(currentIndex, offsetBy: lineText.count, limitedBy: attributedString.endIndex) ?? attributedString.endIndex
            let lineRange = currentIndex..<lineEndIndex
            
            // 获取该行的子 AttributedString
            let lineAttributedString = AttributedString(attributedString[lineRange])
            
            // 转换该行
            let xmlElement = try convertLineToXML(lineAttributedString)
            xmlElements.append(xmlElement)
            
            // 更新索引，跳过当前行和换行符
            currentIndex = lineEndIndex
            if lineIndex < lines.count - 1 && currentIndex < attributedString.endIndex {
                currentIndex = attributedString.characters.index(after: currentIndex)
            }
        }
        
        return xmlElements.joined(separator: "\n")
    }
    
    /// 将单行 AttributedString 转换为 XML
    /// - Parameter lineAttributedString: 单行 AttributedString
    /// - Returns: XML 字符串
    /// - Throws: ConversionError
    private func convertLineToXML(_ lineAttributedString: AttributedString) throws -> String {
        var content = ""
        var indent = 1
        var alignment: NSTextAlignment = .left
        
        // 遍历该行的所有运行段
        for run in lineAttributedString.runs {
            if let attachment = run.attachment {
                // 如果是附件，直接返回附件的 XML
                return try convertAttachmentToXML(attachment)
            }
            
            // 获取文本内容
            let text = String(lineAttributedString.characters[run.range])
            
            // 处理富文本属性
            let taggedText = processAttributesToXMLTags(text, run: run)
            content += taggedText
            
            // 提取缩进级别（使用第一个运行段的缩进）
            if let paragraphStyle = run.paragraphStyle {
                indent = Int(paragraphStyle.firstLineHeadIndent / 20) + 1
                alignment = paragraphStyle.alignment
            }
        }
        
        // 处理对齐方式
        switch alignment {
        case .center:
            content = "<center>\(content)</center>"
        case .right:
            content = "<right>\(content)</right>"
        default:
            break
        }
        
        return "<text indent=\"\(indent)\">\(content)</text>"
    }
    
    /// 将小米笔记 XML 转换为 AttributedString
    /// - Parameter xml: 小米笔记 XML 格式字符串
    /// - Returns: 转换后的 AttributedString
    /// - Throws: ConversionError
    func xmlToAttributedString(_ xml: String) throws -> AttributedString {
        guard !xml.isEmpty else {
            return AttributedString()
        }
        
        // 重置列表状态
        resetListState()
        
        var result = AttributedString()
        let lines = xml.components(separatedBy: .newlines)
        var isFirstLine = true
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            
            // 在非第一行之前添加换行符
            if !isFirstLine {
                result.append(AttributedString("\n"))
            }
            isFirstLine = false
            
            let attributedFragment = try processXMLLine(trimmedLine)
            result.append(attributedFragment)
        }
        
        return result
    }
    
    /// 验证转换的一致性（往返转换测试）
    /// - Parameter xml: 原始 XML
    /// - Returns: 是否一致
    func validateConversion(_ xml: String) -> Bool {
        do {
            let attributedString = try xmlToAttributedString(xml)
            let backConverted = try attributedStringToXML(attributedString)
            return isEquivalent(original: xml, converted: backConverted)
        } catch {
            return false
        }
    }
    
    // MARK: - Private Methods - XML to AttributedString
    
    /// 处理单行 XML
    /// - Parameter line: XML 行
    /// - Returns: 对应的 AttributedString 片段
    /// - Throws: ConversionError
    private func processXMLLine(_ line: String) throws -> AttributedString {
        if line.hasPrefix("<text") {
            return try processTextElement(line)
        } else if line.hasPrefix("<bullet") {
            return try processBulletElement(line)
        } else if line.hasPrefix("<order") {
            return try processOrderElement(line)
        } else if line.hasPrefix("<input type=\"checkbox\"") {
            return try processCheckboxElement(line)
        } else if line.hasPrefix("<hr") {
            return try processHRElement(line)
        } else if line.hasPrefix("<quote>") {
            return try processQuoteElement(line)
        } else if line.hasPrefix("<img") {
            return try processImageElement(line)
        } else {
            throw ConversionError.unsupportedElement(line)
        }
    }
    
    /// 处理 <text> 元素
    /// - Parameter line: XML 行
    /// - Returns: AttributedString 片段
    /// - Throws: ConversionError
    private func processTextElement(_ line: String) throws -> AttributedString {
        // 提取 indent 属性
        let indent = extractAttribute("indent", from: line) ?? "1"
        
        // 提取文本内容（会验证 XML 格式）
        guard let content = try extractTextContent(from: line) else {
            return AttributedString()
        }
        
        // 处理富文本标签并获取属性化的文本
        let (processedText, nsAttributes) = try processRichTextTags(content)
        
        // 创建 AttributedString
        var attributedString = AttributedString(processedText)
        
        // 应用富文本属性 - 使用 AppKit 属性
        for (range, attrs) in nsAttributes {
            // 确保范围有效
            guard range.location >= 0 && range.location + range.length <= processedText.count else {
                continue
            }
            
            let startIndex = attributedString.characters.index(attributedString.startIndex, offsetBy: range.location)
            let endIndex = attributedString.characters.index(startIndex, offsetBy: range.length)
            let attributedRange = startIndex..<endIndex
            
            // 使用 AttributeContainer 来设置属性
            var container = AttributeContainer()
            
            for (key, value) in attrs {
                switch key {
                case .font:
                    if let font = value as? NSFont {
                        container.appKit.font = font
                    }
                case .foregroundColor:
                    if let color = value as? NSColor {
                        container.appKit.foregroundColor = color
                    }
                case .backgroundColor:
                    if let color = value as? NSColor {
                        container.appKit.backgroundColor = color
                    }
                case .underlineStyle:
                    if let style = value as? Int {
                        container.appKit.underlineStyle = NSUnderlineStyle(rawValue: style)
                    }
                case .strikethroughStyle:
                    if let style = value as? Int {
                        container.appKit.strikethroughStyle = NSUnderlineStyle(rawValue: style)
                    }
                case .paragraphStyle:
                    if let style = value as? NSParagraphStyle {
                        container.appKit.paragraphStyle = style
                    }
                default:
                    break
                }
            }
            
            attributedString[attributedRange].mergeAttributes(container)
        }
        
        // 设置段落样式
        var paragraphContainer = AttributeContainer()
        paragraphContainer.appKit.paragraphStyle = createParagraphStyle(indent: Int(indent) ?? 1)
        attributedString.mergeAttributes(paragraphContainer)
        
        return attributedString
    }
    
    /// 处理 <bullet> 元素
    /// - Parameter line: XML 行
    /// - Returns: AttributedString 片段
    /// - Throws: ConversionError
    private func processBulletElement(_ line: String) throws -> AttributedString {
        let indent = extractAttribute("indent", from: line) ?? "1"
        
        // 提取内容（bullet 元素后面的文本）
        let content = extractContentAfterElement(from: line, elementName: "bullet")
        
        // 创建项目符号 + 内容
        var result = AttributedString("• \(content)")
        result.paragraphStyle = createParagraphStyle(indent: Int(indent) ?? 1)
        
        return result
    }
    
    /// 处理 <order> 元素
    /// - Parameter line: XML 行
    /// - Returns: AttributedString 片段
    /// - Throws: ConversionError
    private func processOrderElement(_ line: String) throws -> AttributedString {
        let indent = extractAttribute("indent", from: line) ?? "1"
        let inputNumber = extractAttribute("inputNumber", from: line) ?? "0"
        
        // 提取内容
        let content = extractContentAfterElement(from: line, elementName: "order")
        
        // 根据 inputNumber 规则处理编号
        // inputNumber 为 0 表示连续列表项（自动编号）
        // inputNumber 非 0 表示新列表开始，值为起始编号 - 1
        let inputNum = Int(inputNumber) ?? 0
        let displayNumber: Int
        
        if inputNum == 0 {
            // 连续列表项，使用跟踪的编号
            displayNumber = currentOrderedListNumber
            currentOrderedListNumber += 1
        } else {
            // 新列表开始
            displayNumber = inputNum + 1
            currentOrderedListNumber = displayNumber + 1
        }
        
        var result = AttributedString("\(displayNumber). \(content)")
        
        // 设置列表属性
        var container = AttributeContainer()
        container.appKit.paragraphStyle = createParagraphStyle(indent: Int(indent) ?? 1)
        result.mergeAttributes(container)
        
        return result
    }
    
    /// 重置列表状态（在开始新的转换时调用）
    func resetListState() {
        currentOrderedListNumber = 1
    }
    
    /// 处理 <input type="checkbox"> 元素
    /// - Parameter line: XML 行
    /// - Returns: AttributedString 片段
    /// - Throws: ConversionError
    private func processCheckboxElement(_ line: String) throws -> AttributedString {
        let indent = extractAttribute("indent", from: line) ?? "1"
        let level = extractAttribute("level", from: line) ?? "3"
        
        // 提取内容
        let content = extractContentAfterElement(from: line, elementName: "input")
        
        // 创建复选框符号 + 内容（未选中状态）
        var result = AttributedString("☐ \(content)")
        result.paragraphStyle = createParagraphStyle(indent: Int(indent) ?? 1)
        
        return result
    }
    
    /// 处理 <hr> 元素
    /// - Parameter line: XML 行
    /// - Returns: AttributedString 片段
    /// - Throws: ConversionError
    private func processHRElement(_ line: String) throws -> AttributedString {
        // 创建分割线的文本表示
        var result = AttributedString("───────────────────────────────────────\n")
        
        // 设置分割线的样式
        result.foregroundColor = .secondary
        
        return result
    }
    
    /// 处理 <quote> 元素
    /// - Parameter line: XML 行
    /// - Returns: AttributedString 片段
    /// - Throws: ConversionError
    private func processQuoteElement(_ line: String) throws -> AttributedString {
        // 提取 quote 标签内的内容
        guard let quoteContent = extractQuoteContent(from: line) else {
            return AttributedString()
        }
        
        var result = AttributedString()
        
        // 处理引用块内的每个 text 元素
        let textElements = extractTextElementsFromQuote(quoteContent)
        for textElement in textElements {
            let textFragment = try processTextElement(textElement)
            result.append(textFragment)
            result.append(AttributedString("\n"))
        }
        
        // 为整个引用块设置样式
        result.backgroundColor = .quaternarySystemFill
        
        return result
    }
    
    /// 处理 <img> 元素
    /// - Parameter line: XML 行
    /// - Returns: AttributedString 片段
    /// - Throws: ConversionError
    private func processImageElement(_ line: String) throws -> AttributedString {
        // 提取图片属性
        let src = extractAttribute("src", from: line) ?? ""
        let width = extractAttribute("width", from: line) ?? "100"
        let height = extractAttribute("height", from: line) ?? "100"
        
        // 创建图片占位符文本
        var result = AttributedString("[图片: \(src)]")
        result.foregroundColor = .secondary
        
        return result
    }
    
    // MARK: - Private Methods - AttributedString to XML
    
    /// 将文本运行段转换为 XML
    /// - Parameters:
    ///   - run: AttributedString 运行段
    ///   - attributedString: 原始 AttributedString（用于获取文本内容）
    /// - Returns: XML 字符串
    /// - Throws: ConversionError
    private func convertTextRunToXML(_ run: AttributedString.Runs.Run, in attributedString: AttributedString) throws -> String {
        // 从运行段中提取文本内容 - 使用 characters[run.range] 获取对应的文本
        let text = String(attributedString.characters[run.range])
        
        // 提取缩进级别
        let indent = extractIndentFromParagraphStyle(run.paragraphStyle) ?? 1
        
        // 处理富文本属性
        var content = processAttributesToXMLTags(text, run: run)
        
        // 处理对齐方式
        if let paragraphStyle = run.paragraphStyle {
            switch paragraphStyle.alignment {
            case .center:
                content = "<center>\(content)</center>"
            case .right:
                content = "<right>\(content)</right>"
            default:
                break
            }
        }
        
        return "<text indent=\"\(indent)\">\(content)</text>"
    }
    
    /// 将 NSTextAttachment 转换为 XML
    /// - Parameter attachment: NSTextAttachment
    /// - Returns: XML 字符串
    /// - Throws: ConversionError
    private func convertAttachmentToXML(_ attachment: NSTextAttachment) throws -> String {
        // 根据 attachment 的类型生成对应的 XML
        // 这里需要识别不同类型的自定义 attachment
        
        // 检查是否是复选框 attachment
        if let checkboxAttachment = attachment as? InteractiveCheckboxAttachment {
            return "<input type=\"checkbox\" indent=\"1\" level=\"\(checkboxAttachment.level)\" />"
        }
        
        // 检查是否是分割线 attachment
        if attachment is HorizontalRuleAttachment {
            return "<hr />"
        }
        
        // 检查是否是项目符号 attachment
        if attachment is BulletAttachment {
            return "<bullet indent=\"1\" />"
        }
        
        // 检查是否是有序列表 attachment
        if let orderAttachment = attachment as? OrderAttachment {
            return "<order indent=\"1\" inputNumber=\"\(orderAttachment.inputNumber)\" />"
        }
        
        // 默认情况，可能是图片或其他类型
        return "<hr />" // 临时实现
    }
    
    // MARK: - Helper Methods
    
    /// 提取 XML 属性值
    /// - Parameters:
    ///   - attribute: 属性名
    ///   - line: XML 行
    /// - Returns: 属性值
    private func extractAttribute(_ attribute: String, from line: String) -> String? {
        let pattern = "\(attribute)=\"([^\"]*)\""
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: line.utf16.count)
        
        if let match = regex?.firstMatch(in: line, range: range),
           let matchRange = Range(match.range(at: 1), in: line) {
            return String(line[matchRange])
        }
        
        return nil
    }
    
    /// 提取文本内容
    /// - Parameter line: XML 行
    /// - Returns: 文本内容
    /// - Throws: ConversionError 如果 XML 格式不正确
    private func extractTextContent(from line: String) throws -> String? {
        // 验证 XML 格式 - 检查是否有闭合标签
        if line.hasPrefix("<text") && !line.contains("</text>") {
            throw ConversionError.invalidXML("缺少闭合标签 </text>")
        }
        
        let pattern = "<text[^>]*>(.*?)</text>"
        let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let range = NSRange(location: 0, length: line.utf16.count)
        
        if let match = regex?.firstMatch(in: line, range: range),
           let matchRange = Range(match.range(at: 1), in: line) {
            return String(line[matchRange])
        }
        
        return nil
    }
    
    /// 处理富文本标签
    /// - Parameter content: 包含富文本标签的内容
    /// - Returns: 处理后的纯文本和属性映射
    /// - Throws: ConversionError
    private func processRichTextTags(_ content: String) throws -> (String, [(NSRange, [NSAttributedString.Key: Any])]) {
        var processedText = content
        var attributes: [(NSRange, [NSAttributedString.Key: Any])] = []
        
        // 处理各种富文本标签
        processedText = try processTag(processedText, tag: "size", attribute: .font, value: NSFont.systemFont(ofSize: 24, weight: .bold), attributes: &attributes)
        processedText = try processTag(processedText, tag: "mid-size", attribute: .font, value: NSFont.systemFont(ofSize: 20, weight: .semibold), attributes: &attributes)
        processedText = try processTag(processedText, tag: "h3-size", attribute: .font, value: NSFont.systemFont(ofSize: 16, weight: .medium), attributes: &attributes)
        processedText = try processTag(processedText, tag: "b", attribute: .font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize), attributes: &attributes)
        processedText = try processTag(processedText, tag: "i", attribute: .font, value: NSFont.systemFont(ofSize: NSFont.systemFontSize).italic(), attributes: &attributes)
        processedText = try processTag(processedText, tag: "u", attribute: .underlineStyle, value: NSUnderlineStyle.single.rawValue, attributes: &attributes)
        processedText = try processTag(processedText, tag: "delete", attribute: .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, attributes: &attributes)
        
        // 处理背景色标签
        processedText = try processBackgroundTag(processedText, attributes: &attributes)
        
        // 处理对齐标签
        processedText = try processAlignmentTags(processedText, attributes: &attributes)
        
        return (processedText, attributes)
    }
    
    /// 处理单个标签
    /// - Parameters:
    ///   - text: 文本内容
    ///   - tag: 标签名
    ///   - attribute: 属性键
    ///   - value: 属性值
    ///   - attributes: 属性数组（引用传递）
    /// - Returns: 处理后的文本
    /// - Throws: ConversionError
    private func processTag(_ text: String, tag: String, attribute: NSAttributedString.Key, value: Any, attributes: inout [(NSRange, [NSAttributedString.Key: Any])]) throws -> String {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let range = NSRange(location: 0, length: text.utf16.count)
        
        var processedText = text
        var offset = 0
        let openTagLength = tag.count + 2  // "<tag>" 的长度
        let closeTagLength = tag.count + 3 // "</tag>" 的长度
        
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            
            let contentRange = match.range(at: 1)
            
            // 计算在处理后文本中的位置
            // 原始位置 - 已移除的字符数 - 开始标签长度
            let adjustedLocation = match.range.location - offset
            let adjustedRange = NSRange(location: adjustedLocation, length: contentRange.length)
            
            attributes.append((adjustedRange, [attribute: value]))
            
            // 移除标签，保留内容
            let fullMatchRange = NSRange(location: match.range.location - offset, length: match.range.length)
            if let swiftRange = Range(fullMatchRange, in: processedText),
               let contentSwiftRange = Range(contentRange, in: text) {
                let content = String(text[contentSwiftRange])
                processedText.replaceSubrange(swiftRange, with: content)
                offset += openTagLength + closeTagLength
            }
        }
        
        return processedText
    }
    
    /// 处理背景色标签
    /// - Parameters:
    ///   - text: 文本内容
    ///   - attributes: 属性数组（引用传递）
    /// - Returns: 处理后的文本
    /// - Throws: ConversionError
    private func processBackgroundTag(_ text: String, attributes: inout [(NSRange, [NSAttributedString.Key: Any])]) throws -> String {
        let pattern = "<background color=\"([^\"]*?)\">(.*?)</background>"
        let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let range = NSRange(location: 0, length: text.utf16.count)
        
        var processedText = text
        var offset = 0
        
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            
            let colorRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            
            if let colorSwiftRange = Range(colorRange, in: text),
               let contentSwiftRange = Range(contentRange, in: text) {
                let colorString = String(text[colorSwiftRange])
                let backgroundColor = NSColor(hex: colorString) ?? NSColor.systemYellow
                
                let adjustedRange = NSRange(location: contentRange.location - offset, length: contentRange.length)
                attributes.append((adjustedRange, [.backgroundColor: backgroundColor]))
                
                // 移除标签，保留内容
                let fullMatchRange = NSRange(location: match.range.location - offset, length: match.range.length)
                if let swiftRange = Range(fullMatchRange, in: processedText) {
                    let content = String(text[contentSwiftRange])
                    processedText.replaceSubrange(swiftRange, with: content)
                    offset += match.range.length - content.count
                }
            }
        }
        
        return processedText
    }
    
    /// 处理对齐标签
    /// - Parameters:
    ///   - text: 文本内容
    ///   - attributes: 属性数组（引用传递）
    /// - Returns: 处理后的文本
    /// - Throws: ConversionError
    private func processAlignmentTags(_ text: String, attributes: inout [(NSRange, [NSAttributedString.Key: Any])]) throws -> String {
        var processedText = text
        
        // 处理居中对齐
        processedText = try processAlignmentTag(processedText, tag: "center", alignment: .center, attributes: &attributes)
        
        // 处理右对齐
        processedText = try processAlignmentTag(processedText, tag: "right", alignment: .right, attributes: &attributes)
        
        return processedText
    }
    
    /// 处理单个对齐标签
    /// - Parameters:
    ///   - text: 文本内容
    ///   - tag: 标签名
    ///   - alignment: 对齐方式
    ///   - attributes: 属性数组（引用传递）
    /// - Returns: 处理后的文本
    /// - Throws: ConversionError
    private func processAlignmentTag(_ text: String, tag: String, alignment: NSTextAlignment, attributes: inout [(NSRange, [NSAttributedString.Key: Any])]) throws -> String {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let range = NSRange(location: 0, length: text.utf16.count)
        
        var processedText = text
        var offset = 0
        
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            
            let contentRange = match.range(at: 1)
            let adjustedRange = NSRange(location: contentRange.location - offset, length: contentRange.length)
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            attributes.append((adjustedRange, [.paragraphStyle: paragraphStyle]))
            
            // 移除标签，保留内容
            let fullMatchRange = NSRange(location: match.range.location - offset, length: match.range.length)
            if let swiftRange = Range(fullMatchRange, in: processedText),
               let contentSwiftRange = Range(contentRange, in: text) {
                let content = String(text[contentSwiftRange])
                processedText.replaceSubrange(swiftRange, with: content)
                offset += match.range.length - content.count
            }
        }
        
        return processedText
    }
    
    /// 创建段落样式
    /// - Parameter indent: 缩进级别
    /// - Returns: NSParagraphStyle
    private func createParagraphStyle(indent: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = CGFloat((indent - 1) * 20)
        style.headIndent = CGFloat((indent - 1) * 20)
        return style
    }
    
    /// 从段落样式提取缩进级别
    /// - Parameter style: 段落样式
    /// - Returns: 缩进级别
    private func extractIndentFromParagraphStyle(_ style: NSParagraphStyle?) -> Int? {
        guard let style = style else { return nil }
        return Int(style.firstLineHeadIndent / 20) + 1
    }
    
    /// 从段落样式提取对齐方式
    /// - Parameter style: 段落样式
    /// - Returns: 对齐方式
    private func extractAlignmentFromParagraphStyle(_ style: NSParagraphStyle?) -> NSTextAlignment {
        return style?.alignment ?? .left
    }
    
    /// 处理富文本属性到 XML 标签的转换
    /// - Parameters:
    ///   - text: 文本内容
    ///   - run: AttributedString 运行段
    /// - Returns: 包含 XML 标签的文本
    private func processAttributesToXMLTags(_ text: String, run: AttributedString.Runs.Run) -> String {
        var result = text
        
        // 处理字体样式 - 检查 AppKit 字体属性
        if let font = run.appKit.font {
            let traits = font.fontDescriptor.symbolicTraits
            
            // 检查是否是粗体
            if traits.contains(.bold) {
                result = "<b>\(result)</b>"
            }
            
            // 检查是否是斜体
            if traits.contains(.italic) {
                result = "<i>\(result)</i>"
            }
            
            // 检查字体大小来确定标题级别
            let fontSize = font.pointSize
            if fontSize >= 24 {
                result = "<size>\(result)</size>"
            } else if fontSize >= 20 {
                result = "<mid-size>\(result)</mid-size>"
            } else if fontSize >= 16 && fontSize < 20 {
                result = "<h3-size>\(result)</h3-size>"
            }
        }
        
        // 处理下划线 - 检查是否存在下划线样式
        if run.underlineStyle != nil {
            result = "<u>\(result)</u>"
        }
        
        // 处理删除线 - 检查是否存在删除线样式
        if run.strikethroughStyle != nil {
            result = "<delete>\(result)</delete>"
        }
        
        // 处理背景色
        if let backgroundColor = run.backgroundColor {
            let hexColor = backgroundColor.toHexString()
            result = "<background color=\"\(hexColor)\">\(result)</background>"
        }
        
        return result
    }
    
    /// 处理富文本属性
    /// - Parameters:
    ///   - text: 文本内容
    ///   - attributes: 属性容器
    /// - Returns: 处理后的 XML 内容
    private func processRichTextAttributes(_ text: String, attributes: AttributeContainer) -> String {
        var result = text
        
        // 处理字体样式 - 简化处理
        // SwiftUI 的 Font 和 AttributedString 的属性系统比较复杂
        // 这里先实现基本功能，后续可以完善
        
        // 处理下划线
        if attributes.underlineStyle != nil {
            result = "<u>\(result)</u>"
        }
        
        // 处理删除线
        if attributes.strikethroughStyle != nil {
            result = "<delete>\(result)</delete>"
        }
        
        // 处理背景色
        if let backgroundColor = attributes.backgroundColor {
            let hexColor = backgroundColor.toHexString()
            result = "<background color=\"\(hexColor)\">\(result)</background>"
        }
        
        return result
    }
    
    /// 提取元素后的内容
    /// - Parameters:
    ///   - line: XML 行
    ///   - elementName: 元素名
    /// - Returns: 元素后的内容
    private func extractContentAfterElement(from line: String, elementName: String) -> String {
        let pattern = "<\(elementName)[^>]*\\s*/?>\\s*(.*?)$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: line.utf16.count)
        
        if let match = regex?.firstMatch(in: line, range: range),
           let matchRange = Range(match.range(at: 1), in: line) {
            return String(line[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return ""
    }
    
    /// 提取引用块内容
    /// - Parameter line: XML 行
    /// - Returns: 引用块内容
    private func extractQuoteContent(from line: String) -> String? {
        let pattern = "<quote>(.*?)</quote>"
        let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let range = NSRange(location: 0, length: line.utf16.count)
        
        if let match = regex?.firstMatch(in: line, range: range),
           let matchRange = Range(match.range(at: 1), in: line) {
            return String(line[matchRange])
        }
        
        return nil
    }
    
    /// 从引用块内容中提取文本元素
    /// - Parameter quoteContent: 引用块内容
    /// - Returns: 文本元素数组
    private func extractTextElementsFromQuote(_ quoteContent: String) -> [String] {
        let pattern = "<text[^>]*>.*?</text>"
        let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let range = NSRange(location: 0, length: quoteContent.utf16.count)
        
        var textElements: [String] = []
        regex?.enumerateMatches(in: quoteContent, range: range) { match, _, _ in
            guard let match = match,
                  let matchRange = Range(match.range, in: quoteContent) else { return }
            textElements.append(String(quoteContent[matchRange]))
        }
        
        return textElements
    }
    
    /// 检查两个 XML 是否等价
    /// - Parameters:
    ///   - original: 原始 XML
    ///   - converted: 转换后的 XML
    /// - Returns: 是否等价
    private func isEquivalent(original: String, converted: String) -> Bool {
        // 规范化两个 XML 字符串进行比较
        let normalizedOriginal = normalizeXML(original)
        let normalizedConverted = normalizeXML(converted)
        
        return normalizedOriginal == normalizedConverted
    }
    
    /// 规范化 XML 字符串用于比较
    /// - Parameter xml: XML 字符串
    /// - Returns: 规范化后的字符串
    private func normalizeXML(_ xml: String) -> String {
        var result = xml
        
        // 移除多余的空白字符
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 将多个连续空白字符替换为单个空格
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        
        // 移除标签之间的空白
        result = result.replacingOccurrences(of: "> <", with: "><")
        result = result.replacingOccurrences(of: ">\n<", with: "><")
        result = result.replacingOccurrences(of: ">\r\n<", with: "><")
        
        return result
    }
}