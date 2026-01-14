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
    /// 使用 NSFontManager 来正确转换字体为斜体
    func italic() -> NSFont {
        let fontManager = NSFontManager.shared
        return fontManager.convert(self, toHaveTrait: .italicFontMask)
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
    
    /// 当前文件夹 ID（用于图片加载）
    private var currentFolderId: String?
    
    // MARK: - Public Methods
    
    /// 将 AttributedString 转换为小米笔记 XML 格式
    /// 
    /// 注意：此方法已弃用，建议使用 nsAttributedStringToXML 方法
    /// 因为 NSAttributedString 可以正确保留自定义附件类型
    /// 
    /// - Parameter attributedString: 要转换的 AttributedString
    /// - Returns: 小米笔记 XML 格式字符串
    /// - Throws: ConversionError
    @available(*, deprecated, message: "使用 nsAttributedStringToXML 代替，以正确保留自定义附件类型")
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
    
    /// 将 NSAttributedString 转换为小米笔记 XML 格式
    /// 
    /// 使用新的 AST 转换器实现：
    /// 1. NSAttributedString → AST（使用 AttributedStringToASTConverter）
    /// 2. AST → XML（使用 XMLGenerator）
    /// 
    /// 关键方法：此方法直接处理 NSAttributedString，避免了 AttributedString 中转导致的属性丢失问题
    /// 用于原生编辑器的内容导出保存
    /// 
    /// - Parameter nsAttributedString: 要转换的 NSAttributedString
    /// - Returns: 小米笔记 XML 格式字符串
    /// - Throws: ConversionError
    /// 
    /// _Requirements: 所有_ - 使用新的 AST 转换器实现完整的转换流程
    func nsAttributedStringToXML(_ nsAttributedString: NSAttributedString) throws -> String {
        // 使用新的 AST 转换器
        let astConverter = AttributedStringToASTConverter()
        let document = astConverter.convert(nsAttributedString)
        
        // 使用 XML 生成器
        let xmlGenerator = XMLGenerator()
        return xmlGenerator.generate(document)
    }
    
    /// 将 NSAttributedString 转换为小米笔记 XML 格式（旧实现，保留作为后备）
    /// 
    /// 关键方法：此方法直接处理 NSAttributedString，避免了 AttributedString 中转导致的属性丢失问题
    /// 用于原生编辑器的内容导出保存
    /// 
    /// - Parameter nsAttributedString: 要转换的 NSAttributedString
    /// - Returns: 小米笔记 XML 格式字符串
    /// - Throws: ConversionError
    /// 
    /// _Requirements: 9.3_ - 格式转换失败时记录日志并尝试使用原始内容
    @available(*, deprecated, message: "使用新的 AST 转换器实现")
    func nsAttributedStringToXMLLegacy(_ nsAttributedString: NSAttributedString) throws -> String {
        var xmlElements: [String] = []
        
        let fullText = nsAttributedString.string
        let lines = fullText.components(separatedBy: "\n")
        
        var currentLocation = 0
        var conversionErrors: [String] = []
        
        for (lineIndex, lineText) in lines.enumerated() {
            // 空行处理
            guard !lineText.isEmpty else {
                // 跳过换行符
                if lineIndex < lines.count - 1 {
                    currentLocation += 1
                }
                continue
            }
            
            // 计算当前行的范围
            let lineRange = NSRange(location: currentLocation, length: lineText.count)
            
            // 获取该行的子 NSAttributedString
            let lineAttributedString = nsAttributedString.attributedSubstring(from: lineRange)
            
            // 转换该行，带错误回退
            // _Requirements: 9.3_ - 转换失败时记录日志并尝试使用原始内容
            do {
                let xmlElement = try convertNSLineToXML(lineAttributedString)
                xmlElements.append(xmlElement)
            } catch {
                // 记录错误日志
                let errorMessage = "行 \(lineIndex + 1) 转换失败: \(error.localizedDescription)"
                conversionErrors.append(errorMessage)
                print("[XiaoMiFormatConverter] ⚠️ \(errorMessage)")
                
                // 回退逻辑：使用纯文本作为回退内容
                // _Requirements: 9.3_
                let fallbackText = escapeXMLCharacters(lineText)
                let fallbackXML = "<text indent=\"1\">\(fallbackText)</text>"
                xmlElements.append(fallbackXML)
                print("[XiaoMiFormatConverter] 📝 使用回退内容: \(fallbackXML.prefix(100))...")
            }
            
            // 更新位置，跳过当前行和换行符
            currentLocation += lineText.count
            if lineIndex < lines.count - 1 {
                currentLocation += 1 // 跳过换行符
            }
        }
        
        // 如果有转换错误，记录汇总日志
        if !conversionErrors.isEmpty {
            print("[XiaoMiFormatConverter] ⚠️ 转换完成，但有 \(conversionErrors.count) 个错误:")
            for error in conversionErrors {
                print("[XiaoMiFormatConverter]   - \(error)")
            }
        }
        
        return xmlElements.joined(separator: "\n")
    }
    
    /// 安全转换 NSAttributedString 到 XML（带完整错误处理）
    /// 
    /// 此方法提供更完善的错误处理，即使转换完全失败也会返回纯文本内容
    /// 
    /// - Parameter nsAttributedString: 要转换的 NSAttributedString
    /// - Returns: 小米笔记 XML 格式字符串（保证不为空，除非输入为空）
    /// 
    /// _Requirements: 9.3_ - 格式转换失败时记录日志并尝试使用原始内容
    func safeNSAttributedStringToXML(_ nsAttributedString: NSAttributedString) -> String {
        // 处理空内容
        guard nsAttributedString.length > 0 else {
            return ""
        }
        
        do {
            return try nsAttributedStringToXML(nsAttributedString)
        } catch {
            // 完全失败时的回退：返回纯文本内容
            print("[XiaoMiFormatConverter] ❌ 转换完全失败: \(error.localizedDescription)")
            print("[XiaoMiFormatConverter] 📝 使用纯文本回退")
            
            let plainText = nsAttributedString.string
            let lines = plainText.components(separatedBy: "\n")
            var xmlElements: [String] = []
            
            for line in lines {
                guard !line.isEmpty else { continue }
                let escapedText = escapeXMLCharacters(line)
                xmlElements.append("<text indent=\"1\">\(escapedText)</text>")
            }
            
            return xmlElements.joined(separator: "\n")
        }
    }
    
    /// 将单行 NSAttributedString 转换为 XML
    /// - Parameter lineAttributedString: 单行 NSAttributedString
    /// - Returns: XML 字符串
    /// - Throws: ConversionError
    private func convertNSLineToXML(_ lineAttributedString: NSAttributedString) throws -> String {
        var content = ""
        var indent = 1
        var alignment: NSTextAlignment = .left
        var isCheckboxLine = false
        var checkboxXML = ""
        var textAfterCheckbox = ""
        
        let fullRange = NSRange(location: 0, length: lineAttributedString.length)
        
        // 遍历该行的所有属性运行段
        lineAttributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            // 首先检查是否有 XMLContent 自定义属性
            // 这用于录音模板等需要直接输出 XML 的元素
            if let xmlContent = attributes[NSAttributedString.Key("XMLContent")] as? String {
                content += xmlContent
                return
            }
            
            // 检查是否是附件
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                // 检查是否是复选框附件
                // _Requirements: 5.8_ - 导出时保留 checked 属性
                if let checkboxAttachment = attachment as? InteractiveCheckboxAttachment {
                    isCheckboxLine = true
                    // 导出 checked 属性：选中时添加 checked="true"，未选中时不添加该属性
                    // 这与小米笔记 XML 格式保持一致
                    if checkboxAttachment.isChecked {
                        checkboxXML = "<input type=\"checkbox\" indent=\"\(checkboxAttachment.indent)\" level=\"\(checkboxAttachment.level)\" checked=\"true\" />"
                    } else {
                        checkboxXML = "<input type=\"checkbox\" indent=\"\(checkboxAttachment.indent)\" level=\"\(checkboxAttachment.level)\" />"
                    }
                    return
                }
                
                // 其他附件类型
                do {
                    content = try convertAttachmentToXML(attachment)
                } catch {
                    print("[XiaoMiFormatConverter] 附件转换失败: \(error)")
                }
                return
            }
            
            // 获取文本内容
            let text = (lineAttributedString.string as NSString).substring(with: range)
            
            // 处理富文本属性
            let taggedText = processNSAttributesToXMLTags(text, attributes: attributes)
            
            // 如果是复选框行，将文本追加到复选框后
            if isCheckboxLine {
                textAfterCheckbox += taggedText
            } else {
                content += taggedText
            }
            
            // 提取缩进级别和对齐方式（使用第一个运行段的值）
            if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
                indent = Int(paragraphStyle.firstLineHeadIndent / 20) + 1
                alignment = paragraphStyle.alignment
            }
        }
        
        // 如果是复选框行，返回复选框格式（不使用 <text> 包裹）
        if isCheckboxLine {
            return checkboxXML + textAfterCheckbox
        }
        
        // 检查是否整行是附件（如分割线、图片、语音等）
        if content.hasPrefix("<hr") || content.hasPrefix("<img") || 
           content.hasPrefix("<input") || content.hasPrefix("<bullet") || 
           content.hasPrefix("<order") || content.hasPrefix("<sound") {
            return content
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
    
    /// 处理 NSAttributedString 属性并生成 XML 标签
    /// 
    /// 格式标签的嵌套顺序（从外到内）：
    /// 1. 标题标签（size, mid-size, h3-size）
    /// 2. 背景色标签（background）
    /// 3. 删除线标签（delete）
    /// 4. 下划线标签（u）
    /// 5. 斜体标签（i）
    /// 6. 粗体标签（b）
    /// 
    /// - Parameters:
    ///   - text: 文本内容
    ///   - attributes: NSAttributedString 属性字典
    /// - Returns: 包含 XML 标签的文本
    /// - Requirements: 5.2, 5.3, 5.4, 5.5, 5.6, 7.1, 7.2, 7.3
    private func processNSAttributesToXMLTags(_ text: String, attributes: [NSAttributedString.Key: Any]) -> String {
        var result = escapeXMLCharacters(text)
        
        // 收集所有需要应用的格式
        var hasBold = false
        var hasItalic = false
        var hasUnderline = false
        var hasStrikethrough = false
        var backgroundColor: NSColor? = nil
        var headingTag: String? = nil
        
        // 处理字体样式
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            
            // 检查是否是粗体
            if traits.contains(.bold) {
                hasBold = true
            }
            
            // 检查是否是斜体
            if traits.contains(.italic) {
                hasItalic = true
            }
            
            // 使用 FontSizeManager 检测标题级别
            // _Requirements: 7.1, 7.2, 7.3_
            let fontSize = font.pointSize
            let detectedFormat = FontSizeManager.shared.detectParagraphFormat(fontSize: fontSize)
            switch detectedFormat {
            case .heading1:
                headingTag = "size"
            case .heading2:
                headingTag = "mid-size"
            case .heading3:
                headingTag = "h3-size"
            default:
                break
            }
        }
        
        // 检查 obliqueness 属性（用于中文斜体）
        // 中文字体通常没有真正的斜体变体，所以使用 obliqueness 来模拟
        if let obliqueness = attributes[.obliqueness] as? Double, obliqueness > 0 {
            hasItalic = true
        }
        
        // 处理下划线
        if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
            hasUnderline = true
        }
        
        // 处理删除线
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
            hasStrikethrough = true
        }
        
        // 处理背景色（高亮）
        if let bgColor = attributes[.backgroundColor] as? NSColor {
            backgroundColor = bgColor
        }
        
        // 按照正确的嵌套顺序应用标签（从内到外）
        // 最内层的标签最先应用
        
        // 6. 粗体标签（最内层）
        if hasBold {
            result = "<b>\(result)</b>"
        }
        
        // 5. 斜体标签
        if hasItalic {
            result = "<i>\(result)</i>"
        }
        
        // 4. 下划线标签
        if hasUnderline {
            result = "<u>\(result)</u>"
        }
        
        // 3. 删除线标签
        if hasStrikethrough {
            result = "<delete>\(result)</delete>"
        }
        
        // 2. 背景色标签
        if let bgColor = backgroundColor {
            let hexColor = bgColor.toHexString()
            result = "<background color=\"\(hexColor)\">\(result)</background>"
        }
        
        // 1. 标题标签（最外层）
        if let tag = headingTag {
            result = "<\(tag)>\(result)</\(tag)>"
        }
        
        return result
    }
    
    /// 转义 XML 特殊字符
    /// - Parameter text: 原始文本
    /// - Returns: 转义后的文本
    private func escapeXMLCharacters(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
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
    /// 
    /// 注意：此方法已弃用，建议使用 xmlToNSAttributedString 方法
    /// 因为 NSAttributedString 可以正确保留自定义附件类型
    /// 
    /// - Parameters:
    ///   - xml: 小米笔记 XML 格式字符串
    ///   - folderId: 文件夹 ID（用于图片加载）
    /// - Returns: 转换后的 AttributedString
    /// - Throws: ConversionError
    @available(*, deprecated, message: "使用 xmlToNSAttributedString 代替，以正确保留自定义附件类型")
    func xmlToAttributedString(_ xml: String, folderId: String? = nil) throws -> AttributedString {
        guard !xml.isEmpty else {
            return AttributedString()
        }
        
        // 设置当前文件夹 ID
        self.currentFolderId = folderId
        
        // 重置列表状态
        resetListState()
        
        var result = AttributedString()
        let lines = xml.components(separatedBy: .newlines)
        var isFirstLine = true
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            
            let attributedFragment = try processXMLLine(trimmedLine)
            
            // 跳过空的片段（如 <new-format/> 标签）
            guard !attributedFragment.characters.isEmpty else { continue }
            
            // 在非第一行之前添加换行符
            if !isFirstLine {
                result.append(AttributedString("\n"))
            }
            isFirstLine = false
            
            result.append(attributedFragment)
        }
        
        return result
    }
    
    /// 将小米笔记 XML 直接转换为 NSAttributedString
    /// 
    /// 使用新的 AST 转换器实现：
    /// 1. XML → AST（使用 MiNoteXMLParser）
    /// 2. AST → NSAttributedString（使用 ASTToAttributedStringConverter）
    /// 
    /// 此方法避免了 AttributedString 中转，可以正确保留自定义 NSTextAttachment 子类（如 ImageAttachment）
    /// - Parameters:
    ///   - xml: 小米笔记 XML 格式字符串
    ///   - folderId: 文件夹 ID（用于图片加载）
    /// - Returns: 转换后的 NSAttributedString
    /// - Throws: ConversionError
    /// 
    /// _Requirements: 所有_ - 使用新的 AST 转换器实现完整的转换流程
    func xmlToNSAttributedString(_ xml: String, folderId: String? = nil) throws -> NSAttributedString {
        guard !xml.isEmpty else {
            return NSAttributedString()
        }
        
        // 设置当前文件夹 ID
        self.currentFolderId = folderId
        
        // 重置列表状态
        resetListState()
        
        // 使用新的 XML 解析器
        let parser = MiNoteXMLParser()
        let parseResult = try parser.parse(xml)
        
        // 记录解析警告
        for warning in parseResult.warnings {
            print("[XiaoMiFormatConverter] ⚠️ 解析警告: \(warning.message)")
        }
        
        // 使用 AST 到 NSAttributedString 转换器
        let astConverter = ASTToAttributedStringConverter(folderId: folderId)
        return astConverter.convert(parseResult.value)
    }
    
    /// 将小米笔记 XML 直接转换为 NSAttributedString（旧实现，保留作为后备）
    /// 此方法避免了 AttributedString 中转，可以正确保留自定义 NSTextAttachment 子类（如 ImageAttachment）
    /// - Parameters:
    ///   - xml: 小米笔记 XML 格式字符串
    ///   - folderId: 文件夹 ID（用于图片加载）
    /// - Returns: 转换后的 NSAttributedString
    /// - Throws: ConversionError
    @available(*, deprecated, message: "使用新的 AST 转换器实现")
    func xmlToNSAttributedStringLegacy(_ xml: String, folderId: String? = nil) throws -> NSAttributedString {
        guard !xml.isEmpty else {
            return NSAttributedString()
        }
        
        // 设置当前文件夹 ID
        self.currentFolderId = folderId
        
        // 重置列表状态
        resetListState()
        
        let result = NSMutableAttributedString()
        let lines = xml.components(separatedBy: .newlines)
        var isFirstLine = true
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            
            let nsAttributedFragment = try processXMLLineToNSAttributedString(trimmedLine)
            
            // 跳过空的片段（如 <new-format/> 标签）
            guard nsAttributedFragment.length > 0 else { continue }
            
            // 在非第一行之前添加换行符
            if !isFirstLine {
                result.append(NSAttributedString(string: "\n"))
            }
            isFirstLine = false
            
            result.append(nsAttributedFragment)
        }
        
        return result
    }
    
    /// 处理单行 XML 并返回 NSAttributedString
    /// - Parameter line: XML 行
    /// - Returns: 对应的 NSAttributedString 片段
    /// - Throws: ConversionError
    private func processXMLLineToNSAttributedString(_ line: String) throws -> NSAttributedString {
        // 忽略 <new-format/> 标签 - 这是小米笔记的格式标记，不需要渲染
        if line.hasPrefix("<new-format") {
            return NSAttributedString()
        } else if line.hasPrefix("<text") {
            return try processTextElementToNSAttributedString(line)
        } else if line.hasPrefix("<bullet") {
            return try processBulletElementToNSAttributedString(line)
        } else if line.hasPrefix("<order") {
            return try processOrderElementToNSAttributedString(line)
        } else if line.hasPrefix("<input type=\"checkbox\"") {
            return try processCheckboxElementToNSAttributedString(line)
        } else if line.hasPrefix("<hr") {
            return try processHRElementToNSAttributedString(line)
        } else if line.hasPrefix("<quote>") {
            return try processQuoteElementToNSAttributedString(line)
        } else if line.hasPrefix("<img") {
            return try processImageElementToNSAttributedString(line)
        } else if line.hasPrefix("<sound") {
            return try processSoundElementToNSAttributedString(line)
        } else {
            throw ConversionError.unsupportedElement(line)
        }
    }
    
    /// 处理 <text> 元素并返回 NSAttributedString
    /// 
    /// 关键修复：直接创建 NSAttributedString，而不是通过 AttributedString 中转
    /// 这样可以正确保留字体特性（如粗体、斜体）
    private func processTextElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
        // 提取 indent 属性
        let indent = extractAttribute("indent", from: line) ?? "1"
        
        // 提取文本内容（会验证 XML 格式）
        guard let content = try extractTextContent(from: line) else {
            return NSAttributedString()
        }
        
        // 处理富文本标签并获取属性化的文本
        let (processedText, nsAttributes) = try processRichTextTags(content)
        
        // 直接创建 NSMutableAttributedString
        let result = NSMutableAttributedString(string: processedText)
        
        // 检测是否有对齐属性（从 <center> 或 <right> 标签）
        var detectedAlignment: NSTextAlignment = .left
        for (_, attrs) in nsAttributes {
            if let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
                if paragraphStyle.alignment != .left {
                    detectedAlignment = paragraphStyle.alignment
                    break
                }
            }
        }
        
        // 应用富文本属性（跳过段落样式，稍后统一处理）
        // 对于字体属性，需要合并字体特性而不是直接覆盖
        for (_, (range, attrs)) in nsAttributes.enumerated() {
            // 确保范围有效
            guard range.location >= 0 && range.location + range.length <= processedText.count else {
                continue
            }
            
            for (key, value) in attrs {
                switch key {
                case .paragraphStyle:
                    // 跳过段落样式，稍后统一处理以保留对齐方式
                    break
                case .font:
                    // 字体属性需要特殊处理：合并字体特性而不是直接覆盖
                    if let newFont = value as? NSFont {
                        // 检查当前范围是否已有字体
                        var existingFont: NSFont? = nil
                        result.enumerateAttribute(.font, in: range, options: []) { existingValue, _, stop in
                            if let font = existingValue as? NSFont {
                                existingFont = font
                                stop.pointee = true
                            }
                        }
                        
                        if let existing = existingFont {
                            // 合并字体特性
                            let mergedFont = mergeFontTraits(existing: existing, new: newFont)
                            result.addAttribute(key, value: mergedFont, range: range)
                        } else {
                            // 没有现有字体，直接应用
                            result.addAttribute(key, value: newFont, range: range)
                        }
                    }
                default:
                    // 直接应用属性到 NSAttributedString
                    result.addAttribute(key, value: value, range: range)
                }
            }
        }
        
        // 设置段落样式（包含缩进和对齐方式）
        let paragraphStyle = createParagraphStyle(indent: Int(indent) ?? 1, alignment: detectedAlignment)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        
        return result
    }
    
    /// 处理 <bullet> 元素并返回 NSAttributedString
    private func processBulletElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
        let attributedString = try processBulletElement(line)
        return try NSAttributedString(attributedString, including: \.appKit)
    }
    
    /// 处理 <order> 元素并返回 NSAttributedString
    private func processOrderElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
        let attributedString = try processOrderElement(line)
        return try NSAttributedString(attributedString, including: \.appKit)
    }
    
    /// 处理 <input type="checkbox"> 元素并返回 NSAttributedString
    /// 
    /// 关键修复：直接创建 NSAttributedString 并使用 InteractiveCheckboxAttachment
    /// 而不是使用 Unicode 字符，这样可以：
    /// 1. 正确显示可交互的复选框图标
    /// 2. 支持点击切换选中状态
    /// 3. 正确导出为小米笔记 XML 格式
    /// 4. 正确解析和保存 checked 属性（勾选状态）
    /// 
    /// _Requirements: 1.4, 5.8_
    private func processCheckboxElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
        // 1. 提取属性
        let indent = Int(extractAttribute("indent", from: line) ?? "1") ?? 1
        let level = Int(extractAttribute("level", from: line) ?? "3") ?? 3
        
        // 2. 提取 checked 属性（勾选状态）
        // 小米笔记 XML 格式：<input type="checkbox" indent="1" level="3" checked="true" />
        // _Requirements: 1.4_ - 正确渲染可交互的复选框并保留勾选状态
        let checkedStr = extractAttribute("checked", from: line)
        let isChecked = checkedStr?.lowercased() == "true"
        
        // 3. 提取复选框后的文本内容
        let content = extractContentAfterElement(from: line, elementName: "input")
        
        // 4. 创建复选框附件（传入勾选状态）
        // _Requirements: 5.8_ - 创建 InteractiveCheckboxAttachment 时传入正确的状态
        let checkboxAttachment = CustomRenderer.shared.createCheckboxAttachment(
            checked: isChecked,
            level: level,
            indent: indent
        )
        
        // 5. 创建包含附件的 NSAttributedString
        let result = NSMutableAttributedString(attachment: checkboxAttachment)
        
        // 6. 追加文本内容（如果有）
        if !content.isEmpty {
            // 处理文本内容中可能包含的富文本标签
            let (processedText, nsAttributes) = try processRichTextTags(content)
            
            // 创建文本属性字符串
            let textString = NSMutableAttributedString(string: processedText)
            
            // 应用富文本属性
            for (range, attrs) in nsAttributes {
                guard range.location >= 0 && range.location + range.length <= processedText.count else {
                    continue
                }
                for (key, value) in attrs {
                    textString.addAttribute(key, value: value, range: range)
                }
            }
            
            result.append(textString)
        }
        
        // 7. 设置段落样式
        let paragraphStyle = createParagraphStyle(indent: indent)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, 
                           range: NSRange(location: 0, length: result.length))
        
        return result
    }
    
    /// 处理 <hr> 元素并返回 NSAttributedString（直接创建，不经过 AttributedString）
    private func processHRElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
        // 创建分割线附件
        let attachment = CustomRenderer.shared.createHorizontalRuleAttachment()
        
        // 直接创建 NSAttributedString，不经过 AttributedString 转换
        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: "\n"))
        
        return result
    }
    
    /// 处理 <quote> 元素并返回 NSAttributedString
    private func processQuoteElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
        let attributedString = try processQuoteElement(line)
        return try NSAttributedString(attributedString, including: \.appKit)
    }
    
    /// 处理 <img> 元素并返回 NSAttributedString（直接创建，不经过 AttributedString）
    /// 这是关键方法 - 直接返回 NSAttributedString 以保留 ImageAttachment 类型
    private func processImageElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
        // 提取图片属性
        let src = extractAttribute("src", from: line) ?? ""
        let fileId = extractAttribute("fileid", from: line) ?? extractAttribute("fileId", from: line)
        let folderId = extractAttribute("folderId", from: line) ?? currentFolderId
        let width = extractAttribute("width", from: line)
        let height = extractAttribute("height", from: line)
        
        // 创建图片附件
        let attachment = CustomRenderer.shared.createImageAttachment(
            src: src.isEmpty ? nil : src,
            fileId: fileId,
            folderId: folderId
        )
        
        // 如果有宽度和高度属性，设置显示尺寸
        if let widthStr = width, let heightStr = height,
           let w = Double(widthStr), let h = Double(heightStr) {
            attachment.displaySize = NSSize(width: w, height: h)
        }
        
        // 直接创建 NSAttributedString，不经过 AttributedString 转换
        // 这样可以保留 ImageAttachment 的类型信息
        let result = NSMutableAttributedString(attachment: attachment)
        
        return result
    }
    
    /// 处理 <sound> 元素并返回 NSAttributedString
    /// 
    /// 解析语音文件标签 `<sound fileid="xxx" />` 并创建 AudioAttachment
    /// 如果包含 `des="temp"` 属性，则标记为临时占位符
    /// 
    /// - Parameter line: XML 行
    /// - Returns: 包含 AudioAttachment 的 NSAttributedString
    /// - Throws: ConversionError
    /// - Requirements: 1.1, 1.2
    private func processSoundElementToNSAttributedString(_ line: String) throws -> NSAttributedString {
        // 1. 提取 fileid 属性（小米笔记 XML 中使用全小写的 fileid）
        guard let fileId = extractAttribute("fileid", from: line), !fileId.isEmpty else {
            // 如果缺少 fileid 属性，跳过该元素
            return NSAttributedString()
        }
        
        // 2. 检查是否是临时占位符（des="temp"）
        let desAttribute = extractAttribute("des", from: line)
        let isTemporary = desAttribute?.lowercased() == "temp"
        
        // 3. 创建音频附件
        let attachment = CustomRenderer.shared.createAudioAttachment(
            fileId: fileId,
            digest: nil,
            mimeType: nil
        )
        
        // 4. 设置临时占位符标记
        attachment.isTemporaryPlaceholder = isTemporary
        
        // 5. 创建包含附件的 NSAttributedString
        let result = NSMutableAttributedString(attachment: attachment)
        
        return result
    }
    
    /// 验证转换的一致性（往返转换测试）
    /// 使用新的 AST 转换器进行往返测试
    /// - Parameter xml: 原始 XML
    /// - Returns: 是否一致
    func validateConversion(_ xml: String) -> Bool {
        do {
            // XML → NSAttributedString
            let nsAttributedString = try xmlToNSAttributedString(xml)
            
            // NSAttributedString → XML
            let backConverted = try nsAttributedStringToXML(nsAttributedString)
            
            return isEquivalent(original: xml, converted: backConverted)
        } catch {
            print("[XiaoMiFormatConverter] 验证转换失败: \(error)")
            return false
        }
    }
    
    // MARK: - Private Methods - XML to AttributedString
    
    /// 处理单行 XML
    /// - Parameter line: XML 行
    /// - Returns: 对应的 AttributedString 片段
    /// - Throws: ConversionError
    private func processXMLLine(_ line: String) throws -> AttributedString {
        // 忽略 <new-format/> 标签 - 这是小米笔记的格式标记，不需要渲染
        if line.hasPrefix("<new-format") {
            return AttributedString()
        } else if line.hasPrefix("<text") {
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
        } else if line.hasPrefix("<sound") {
            return try processSoundElement(line)
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
        
        // 检测是否有对齐属性（从 <center> 或 <right> 标签）
        var detectedAlignment: NSTextAlignment = .left
        for (_, attrs) in nsAttributes {
            if let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
                if paragraphStyle.alignment != .left {
                    detectedAlignment = paragraphStyle.alignment
                    break
                }
            }
        }
        
        // 应用富文本属性 - 使用 AppKit 属性（跳过段落样式，稍后统一处理）
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
                    // 跳过段落样式，稍后统一处理以保留对齐方式
                    break
                default:
                    break
                }
            }
            
            attributedString[attributedRange].mergeAttributes(container)
        }
        
        // 设置段落样式（包含缩进和对齐方式）
        var paragraphContainer = AttributeContainer()
        paragraphContainer.appKit.paragraphStyle = createParagraphStyle(indent: Int(indent) ?? 1, alignment: detectedAlignment)
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
        // 调用 NSAttributedString 版本并转换
        // 注意：AttributedString 转换可能会丢失自定义 NSTextAttachment 子类的类型信息
        // 建议直接使用 processCheckboxElementToNSAttributedString 方法
        let nsAttributedString = try processCheckboxElementToNSAttributedString(line)
        return AttributedString(nsAttributedString)
    }
    
    /// 处理 <hr> 元素
    /// - Parameter line: XML 行
    /// - Returns: AttributedString 片段
    /// - Throws: ConversionError
    private func processHRElement(_ line: String) throws -> AttributedString {
        // 创建分割线附件
        let attachment = CustomRenderer.shared.createHorizontalRuleAttachment()
        
        // 创建包含附件的 AttributedString
        let attachmentString = NSAttributedString(attachment: attachment)
        var result = AttributedString(attachmentString)
        
        // 添加换行符
        result.append(AttributedString("\n"))
        
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
        // 注意：小米笔记 XML 中使用 "fileid"（全小写），需要同时支持两种格式
        let src = extractAttribute("src", from: line) ?? ""
        let fileId = extractAttribute("fileid", from: line) ?? extractAttribute("fileId", from: line)
        let folderId = extractAttribute("folderId", from: line) ?? currentFolderId
        let width = extractAttribute("width", from: line)
        let height = extractAttribute("height", from: line)
        
        // 创建图片附件
        let attachment = CustomRenderer.shared.createImageAttachment(
            src: src.isEmpty ? nil : src,
            fileId: fileId,
            folderId: folderId
        )
        
        // 如果有宽度和高度属性，设置显示尺寸
        if let widthStr = width, let heightStr = height,
           let w = Double(widthStr), let h = Double(heightStr) {
            attachment.displaySize = NSSize(width: w, height: h)
        }
        
        // 创建包含附件的 AttributedString
        let attachmentString = NSAttributedString(attachment: attachment)
        let result = AttributedString(attachmentString)
        
        return result
    }
    
    /// 处理 <sound> 元素
    /// 
    /// 解析语音文件标签 `<sound fileid="xxx" />` 并创建 AudioAttachment
    /// 
    /// - Parameter line: XML 行
    /// - Returns: AttributedString 片段
    /// - Throws: ConversionError
    /// - Requirements: 1.1, 1.2
    private func processSoundElement(_ line: String) throws -> AttributedString {
        // 调用 NSAttributedString 版本并转换
        let nsAttributedString = try processSoundElementToNSAttributedString(line)
        return AttributedString(nsAttributedString)
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
    /// 
    /// 支持的附件类型：
    /// - InteractiveCheckboxAttachment: 转换为 <input type="checkbox" indent="x" level="y" checked="true/false" />
    /// - HorizontalRuleAttachment: 转换为 <hr />
    /// - BulletAttachment: 转换为 <bullet indent="x" />
    /// - OrderAttachment: 转换为 <order indent="x" inputNumber="y" />
    /// - AudioAttachment: 转换为 <sound fileid="xxx" />
    /// - ImageAttachment: 转换为 <img src="xxx" width="y" height="z" />
    /// 
    /// - Parameter attachment: NSTextAttachment
    /// - Returns: XML 字符串
    /// - Throws: ConversionError
    /// - Requirements: 5.8, 5.9, 5.10
    private func convertAttachmentToXML(_ attachment: NSTextAttachment) throws -> String {
        // 根据 attachment 的类型生成对应的 XML
        // 这里需要识别不同类型的自定义 attachment
        
        // 检查是否是复选框 attachment
        // Requirements: 5.8 - 保留 checked 属性
        if let checkboxAttachment = attachment as? InteractiveCheckboxAttachment {
            var xmlAttrs: [String] = [
                "type=\"checkbox\"",
                "indent=\"\(checkboxAttachment.indent)\"",
                "level=\"\(checkboxAttachment.level)\""
            ]
            
            // 只有当选中时才添加 checked 属性
            if checkboxAttachment.isChecked {
                xmlAttrs.append("checked=\"true\"")
            }
            
            return "<input \(xmlAttrs.joined(separator: " ")) />"
        }
        
        // 检查是否是分割线 attachment
        if attachment is HorizontalRuleAttachment {
            return "<hr />"
        }
        
        // 检查是否是项目符号 attachment
        if let bulletAttachment = attachment as? BulletAttachment {
            return "<bullet indent=\"\(bulletAttachment.indent)\" />"
        }
        
        // 检查是否是有序列表 attachment
        if let orderAttachment = attachment as? OrderAttachment {
            return "<order indent=\"\(orderAttachment.indent)\" inputNumber=\"\(orderAttachment.inputNumber)\" />"
        }
        
        // 检查是否是语音文件 attachment
        // Requirements: 5.10 - 将 AudioAttachment 转换为 <sound fileid="xxx" /> 格式
        if let audioAttachment = attachment as? AudioAttachment {
            if let fileId = audioAttachment.fileId, !fileId.isEmpty {
                // 如果是临时占位符，添加 des="temp" 属性
                if audioAttachment.isTemporaryPlaceholder {
                    return "<sound fileid=\"\(fileId)\" des=\"temp\"/>"
                } else {
                    return "<sound fileid=\"\(fileId)\"/>"
                }
            } else {
                return ""
            }
        }
        
        // 检查是否是图片 attachment
        // Requirements: 5.9 - 保留 fileId 属性
        if let imageAttachment = attachment as? ImageAttachment {
            var xmlAttrs: [String] = []
            
            if let src = imageAttachment.src, !src.isEmpty {
                xmlAttrs.append("src=\"\(escapeXMLAttributeValue(src))\"")
            } else if let fileId = imageAttachment.fileId {
                // 生成 minote:// URL（统一格式，不需要 folderId）
                let minoteURL = ImageStorageManager.shared.generateMinoteURL(fileId: fileId)
                xmlAttrs.append("src=\"\(escapeXMLAttributeValue(minoteURL))\"")
            }
            
            // 保留 fileId 属性（用于云端同步）
            if let fileId = imageAttachment.fileId, !fileId.isEmpty {
                xmlAttrs.append("fileid=\"\(escapeXMLAttributeValue(fileId))\"")
            }
            
            if imageAttachment.displaySize.width > 0 {
                xmlAttrs.append("width=\"\(Int(imageAttachment.displaySize.width))\"")
            }
            if imageAttachment.displaySize.height > 0 {
                xmlAttrs.append("height=\"\(Int(imageAttachment.displaySize.height))\"")
            }
            
            return "<img \(xmlAttrs.joined(separator: " ")) />"
        }
        
        // 默认情况，可能是普通图片或其他类型
        if let image = attachment.image {
            // 普通图片附件，尝试保存并生成 XML
            // 使用统一的 images/{imageId}.jpg 格式
            if let saveResult = ImageStorageManager.shared.saveImage(image) {
                let minoteURL = ImageStorageManager.shared.generateMinoteURL(fileId: saveResult.fileId)
                return "<img src=\"\(escapeXMLAttributeValue(minoteURL))\" fileid=\"\(escapeXMLAttributeValue(saveResult.fileId))\" width=\"\(Int(image.size.width))\" height=\"\(Int(image.size.height))\" />"
            }
        }
        
        return "<hr />" // 临时实现
    }
    
    /// 转义 XML 属性值中的特殊字符
    /// - Parameter value: 原始属性值
    /// - Returns: 转义后的属性值
    private func escapeXMLAttributeValue(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        return result
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
    /// 
    /// 修复：使用递归方式处理嵌套标签，确保属性范围正确计算
    private func processRichTextTags(_ content: String) throws -> (String, [(NSRange, [NSAttributedString.Key: Any])]) {
        var attributes: [(NSRange, [NSAttributedString.Key: Any])] = []
        
        // 使用递归方式处理所有标签
        let processedText = try processNestedTags(content, attributes: &attributes)
        
        return (processedText, attributes)
    }
    
    /// 递归处理嵌套标签
    /// - Parameters:
    ///   - text: 文本内容
    ///   - attributes: 属性数组（引用传递）
    /// - Returns: 处理后的纯文本
    /// - Throws: ConversionError
    /// 
    /// 修复：使用最外层优先的策略处理嵌套标签
    /// 对于 `<i><b>你好</b></i>`，先处理 `<i>` 标签，再递归处理内部的 `<b>` 标签
    /// 
    /// _Requirements: 7.4, 7.5, 7.6_ - 使用 FontSizeManager 统一字体大小，标题使用常规字重
    private func processNestedTags(_ text: String, attributes: inout [(NSRange, [NSAttributedString.Key: Any])]) throws -> String {
        // 定义所有支持的标签及其对应的属性
        // 使用 FontSizeManager 获取字体大小，标题使用常规字重（不加粗）
        // _Requirements: 7.4, 7.5, 7.6_
        let tagMappings: [(tag: String, attribute: NSAttributedString.Key, value: Any)] = [
            ("size", .font, FontSizeManager.shared.createFont(for: .heading1)),      // 23pt, regular
            ("mid-size", .font, FontSizeManager.shared.createFont(for: .heading2)),  // 20pt, regular
            ("h3-size", .font, FontSizeManager.shared.createFont(for: .heading3)),   // 17pt, regular
            ("b", .font, NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)),
            ("i", .obliqueness, 0.2),
            ("u", .underlineStyle, NSUnderlineStyle.single.rawValue),
            ("delete", .strikethroughStyle, NSUnderlineStyle.single.rawValue)
        ]
        
        var processedText = text
        
        // 循环处理，直到没有更多标签
        var foundTag = true
        while foundTag {
            foundTag = false
            
            // 找到最外层的标签（位置最靠前的开始标签）
            var earliestMatch: (tag: String, attribute: NSAttributedString.Key, value: Any, match: NSTextCheckingResult)? = nil
            
            for (tag, attribute, value) in tagMappings {
                // 使用贪婪匹配来找到完整的标签对（包括嵌套的同类标签）
                let pattern = "<\(tag)>(.*)</\(tag)>"
                let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
                let range = NSRange(location: 0, length: processedText.utf16.count)
                
                if let match = regex.firstMatch(in: processedText, range: range) {
                    // 检查这个匹配是否比当前最早的匹配更靠前
                    if earliestMatch == nil || match.range.location < earliestMatch!.match.range.location {
                        earliestMatch = (tag, attribute, value, match)
                    }
                }
            }
            
            // 如果找到了最外层标签，处理它
            if let (tag, attribute, value, match) = earliestMatch {
                foundTag = true
                
                let contentRange = match.range(at: 1)
                guard let contentSwiftRange = Range(contentRange, in: processedText) else {
                    continue
                }
                
                // 提取内容（可能包含其他嵌套标签）
                var innerContent = String(processedText[contentSwiftRange])
                
                // 检查内容中是否有未配对的同类标签，如果有，需要使用非贪婪匹配
                // 例如：<b>粗体1</b>普通<b>粗体2</b> 应该分别处理两个 <b> 标签
                let openTagCount = innerContent.components(separatedBy: "<\(tag)>").count - 1
                let closeTagCount = innerContent.components(separatedBy: "</\(tag)>").count - 1
                
                if openTagCount != closeTagCount {
                    // 内容中有未配对的标签，使用非贪婪匹配
                    let nonGreedyPattern = "<\(tag)>(.*?)</\(tag)>"
                    let nonGreedyRegex = try NSRegularExpression(pattern: nonGreedyPattern, options: .dotMatchesLineSeparators)
                    let range = NSRange(location: 0, length: processedText.utf16.count)
                    
                    if let nonGreedyMatch = nonGreedyRegex.firstMatch(in: processedText, range: range) {
                        let nonGreedyContentRange = nonGreedyMatch.range(at: 1)
                        guard let nonGreedyContentSwiftRange = Range(nonGreedyContentRange, in: processedText) else {
                            continue
                        }
                        innerContent = String(processedText[nonGreedyContentSwiftRange])
                        
                        // 递归处理内部内容
                        var innerAttributes: [(NSRange, [NSAttributedString.Key: Any])] = []
                        let processedInnerContent = try processNestedTags(innerContent, attributes: &innerAttributes)
                        
                        // 计算当前标签在最终文本中的位置
                        let matchLocation = nonGreedyMatch.range.location
                        
                        // 替换标签为处理后的内容
                        guard let fullMatchSwiftRange = Range(nonGreedyMatch.range, in: processedText) else {
                            continue
                        }
                        processedText.replaceSubrange(fullMatchSwiftRange, with: processedInnerContent)
                        
                        // 添加当前标签的属性
                        let finalRange = NSRange(location: matchLocation, length: processedInnerContent.utf16.count)
                        attributes.append((finalRange, [attribute: value]))
                        
                        // 调整内部属性的位置
                        for (innerRange, innerAttrs) in innerAttributes {
                            let adjustedRange = NSRange(location: matchLocation + innerRange.location, length: innerRange.length)
                            attributes.append((adjustedRange, innerAttrs))
                        }
                        
                        continue
                    }
                }
                
                // 递归处理内部内容
                var innerAttributes: [(NSRange, [NSAttributedString.Key: Any])] = []
                let processedInnerContent = try processNestedTags(innerContent, attributes: &innerAttributes)
                
                // 计算当前标签在最终文本中的位置
                let matchLocation = match.range.location
                
                // 替换标签为处理后的内容
                guard let fullMatchSwiftRange = Range(match.range, in: processedText) else {
                    continue
                }
                processedText.replaceSubrange(fullMatchSwiftRange, with: processedInnerContent)
                
                // 添加当前标签的属性（范围是处理后内容的位置）
                let finalRange = NSRange(location: matchLocation, length: processedInnerContent.utf16.count)
                attributes.append((finalRange, [attribute: value]))
                
                // 调整内部属性的位置（加上当前标签的起始位置）
                for (innerRange, innerAttrs) in innerAttributes {
                    let adjustedRange = NSRange(location: matchLocation + innerRange.location, length: innerRange.length)
                    attributes.append((adjustedRange, innerAttrs))
                }
            }
        }
        
        // 处理背景色标签
        processedText = try processBackgroundTag(processedText, attributes: &attributes)
        
        // 处理对齐标签
        processedText = try processAlignmentTags(processedText, attributes: &attributes)
        
        return processedText
    }
    
    /// 处理单个标签（保留用于兼容性，但不再使用）
    /// - Parameters:
    ///   - text: 文本内容
    ///   - tag: 标签名
    ///   - attribute: 属性键
    ///   - value: 属性值
    ///   - attributes: 属性数组（引用传递）
    /// - Returns: 处理后的文本
    /// - Throws: ConversionError
    @available(*, deprecated, message: "使用 processNestedTags 代替")
    private func processTag(_ text: String, tag: String, attribute: NSAttributedString.Key, value: Any, attributes: inout [(NSRange, [NSAttributedString.Key: Any])]) throws -> String {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        
        var processedText = text
        var totalOffset = 0
        let openTagLength = tag.count + 2  // "<tag>" 的长度
        let closeTagLength = tag.count + 3 // "</tag>" 的长度
        
        // 循环处理所有匹配，每次处理后重新搜索
        // 这样可以正确处理嵌套标签，因为每次都在更新后的文本上搜索
        while true {
            let currentRange = NSRange(location: 0, length: processedText.utf16.count)
            guard let match = regex.firstMatch(in: processedText, range: currentRange) else {
                break
            }
            
            let contentRange = match.range(at: 1)
            
            // 在当前处理后的文本中，内容的位置就是 contentRange.location - openTagLength
            // 因为我们要移除开始标签
            let adjustedLocation = match.range.location
            
            // 提取内容
            guard let contentSwiftRange = Range(contentRange, in: processedText) else {
                break
            }
            let content = String(processedText[contentSwiftRange])
            
            // 计算最终范围（在移除标签后的文本中的位置）
            // adjustedLocation 是当前匹配的起始位置，移除开始标签后内容就在这个位置
            let finalRange = NSRange(location: adjustedLocation, length: content.utf16.count)
            
            // 记录属性
            attributes.append((finalRange, [attribute: value]))
            
            // 移除标签，保留内容
            guard let fullMatchSwiftRange = Range(match.range, in: processedText) else {
                break
            }
            processedText.replaceSubrange(fullMatchSwiftRange, with: content)
            totalOffset += openTagLength + closeTagLength
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
    
    /// 合并字体特性
    /// - Parameters:
    ///   - existing: 现有字体
    ///   - new: 新字体
    /// - Returns: 合并后的字体
    /// 
    /// 这个方法用于处理同一范围内有多个字体属性的情况（如同时有粗体和斜体）
    /// 它会保留现有字体的特性，并添加新字体的特性
    private func mergeFontTraits(existing: NSFont, new: NSFont) -> NSFont {
        let fontManager = NSFontManager.shared
        
        // 获取现有字体和新字体的特性
        let existingTraits = existing.fontDescriptor.symbolicTraits
        let newTraits = new.fontDescriptor.symbolicTraits
        
        // 使用较大的字体大小（通常标题字体会更大）
        let fontSize = max(existing.pointSize, new.pointSize)
        
        // 从现有字体开始
        var resultFont = existing
        
        // 如果字体大小不同，先调整大小
        if existing.pointSize != fontSize {
            resultFont = NSFont(descriptor: existing.fontDescriptor, size: fontSize) ?? existing
        }
        
        // 如果新字体有粗体特性，添加粗体
        if newTraits.contains(.bold) && !existingTraits.contains(.bold) {
            resultFont = fontManager.convert(resultFont, toHaveTrait: .boldFontMask)
        }
        
        // 如果新字体有斜体特性，添加斜体
        if newTraits.contains(.italic) && !existingTraits.contains(.italic) {
            resultFont = fontManager.convert(resultFont, toHaveTrait: .italicFontMask)
        }
        
        // 如果现有字体有粗体特性，确保保留
        if existingTraits.contains(.bold) && !resultFont.fontDescriptor.symbolicTraits.contains(.bold) {
            resultFont = fontManager.convert(resultFont, toHaveTrait: .boldFontMask)
        }
        
        // 如果现有字体有斜体特性，确保保留
        if existingTraits.contains(.italic) && !resultFont.fontDescriptor.symbolicTraits.contains(.italic) {
            resultFont = fontManager.convert(resultFont, toHaveTrait: .italicFontMask)
        }
        
        return resultFont
    }
    
    /// 创建段落样式
    /// - Parameters:
    ///   - indent: 缩进级别
    ///   - alignment: 对齐方式（默认为左对齐）
    /// - Returns: NSParagraphStyle
    private func createParagraphStyle(indent: Int, alignment: NSTextAlignment = .left) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = CGFloat((indent - 1) * 20)
        style.headIndent = CGFloat((indent - 1) * 20)
        style.alignment = alignment
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
    /// 
    /// 格式标签的嵌套顺序（从外到内）：
    /// 1. 标题标签（size, mid-size, h3-size）
    /// 2. 背景色标签（background）
    /// 3. 删除线标签（delete）
    /// 4. 下划线标签（u）
    /// 5. 斜体标签（i）
    /// 6. 粗体标签（b）
    /// 
    /// - Parameters:
    ///   - text: 文本内容
    ///   - run: AttributedString 运行段
    /// - Returns: 包含 XML 标签的文本
    /// - Requirements: 5.2, 5.3, 5.4, 5.5, 5.6, 5.7
    private func processAttributesToXMLTags(_ text: String, run: AttributedString.Runs.Run) -> String {
        var result = text
        
        // 收集所有需要应用的格式
        var hasBold = false
        var hasItalic = false
        var hasUnderline = false
        var hasStrikethrough = false
        var backgroundColor: Color? = nil
        var headingTag: String? = nil
        
        // 处理字体样式 - 检查 AppKit 字体属性
        if let font = run.appKit.font {
            let traits = font.fontDescriptor.symbolicTraits
            
            // 检查是否是粗体
            if traits.contains(.bold) {
                hasBold = true
            }
            
            // 检查是否是斜体
            if traits.contains(.italic) {
                hasItalic = true
            }
            
            // 检查字体大小来确定标题级别
            let fontSize = font.pointSize
            if fontSize >= 24 {
                headingTag = "size"
            } else if fontSize >= 20 {
                headingTag = "mid-size"
            } else if fontSize >= 16 && fontSize < 20 {
                headingTag = "h3-size"
            }
        }
        
        // 处理下划线 - 检查是否存在下划线样式
        if run.underlineStyle != nil {
            hasUnderline = true
        }
        
        // 处理删除线 - 检查是否存在删除线样式
        if run.strikethroughStyle != nil {
            hasStrikethrough = true
        }
        
        // 处理背景色
        if let bgColor = run.backgroundColor {
            backgroundColor = bgColor
        }
        
        // 按照正确的嵌套顺序应用标签（从内到外）
        // 最内层的标签最先应用
        
        // 6. 粗体标签（最内层）
        if hasBold {
            result = "<b>\(result)</b>"
        }
        
        // 5. 斜体标签
        if hasItalic {
            result = "<i>\(result)</i>"
        }
        
        // 4. 下划线标签
        if hasUnderline {
            result = "<u>\(result)</u>"
        }
        
        // 3. 删除线标签
        if hasStrikethrough {
            result = "<delete>\(result)</delete>"
        }
        
        // 2. 背景色标签
        if let bgColor = backgroundColor {
            let hexColor = bgColor.toHexString()
            result = "<background color=\"\(hexColor)\">\(result)</background>"
        }
        
        // 1. 标题标签（最外层）
        if let tag = headingTag {
            result = "<\(tag)>\(result)</\(tag)>"
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