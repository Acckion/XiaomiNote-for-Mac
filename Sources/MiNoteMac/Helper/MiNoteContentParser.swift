import Foundation
import AppKit // For NSAttributedString and NSFont

class MiNoteContentParser {

    // MARK: - XML to NSAttributedString

    static func parseToAttributedString(_ xmlContent: String, noteRawData: [String: Any]? = nil) -> NSAttributedString {
        print("[MiNoteContentParser] parseToAttributedString called, xmlContent length: \(xmlContent.count)")
        if xmlContent.isEmpty {
            print("[MiNoteContentParser] WARNING: xmlContent is empty")
            return NSAttributedString(string: "", attributes: [.foregroundColor: NSColor.labelColor])
        }
        
        // 打印前100个字符以查看内容
        let preview = xmlContent.prefix(100)
        print("[MiNoteContentParser] xmlContent preview: \(preview)")
        
        let mutableAttributedString = NSMutableAttributedString()

        // Remove the <new-format/> tag if present
        var cleanedContent = xmlContent.replacingOccurrences(of: "<new-format/>", with: "")
        
        // 提取图片信息字典（从 setting.data）
        var imageDict: [String: String] = [:] // fileId -> fileType
        if let rawData = noteRawData,
           let setting = rawData["setting"] as? [String: Any],
           let settingData = setting["data"] as? [[String: Any]] {
            for imgData in settingData {
                if let fileId = imgData["fileId"] as? String,
                   let mimeType = imgData["mimeType"] as? String,
                   mimeType.hasPrefix("image/") {
                    let fileType = String(mimeType.dropFirst("image/".count))
                    imageDict[fileId] = fileType
                }
            }
        }
        
        // 处理图片引用：先替换图片引用为占位符，稍后插入图片
        // 格式1: ☺ fileId<0/></>
        let imagePattern1 = try! NSRegularExpression(pattern: "☺\\s+([^<\\s]+)(<0\\/><\\/>)?", options: [])
        let imageMatches1 = imagePattern1.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        
        // 格式2: <img fileid="fileId" ... />
        let imagePattern2 = try! NSRegularExpression(pattern: "<img[^>]+fileid=\"([^\"]+)\"[^>]*/>", options: [])
        let imageMatches2 = imagePattern2.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        
        // 收集所有图片引用位置（反向排序，以便从后往前替换）
        var imageReplacements: [(range: NSRange, fileId: String)] = []
        for match in imageMatches1.reversed() {
            if match.numberOfRanges >= 2,
               let fileIdRange = Range(match.range(at: 1), in: cleanedContent) {
                let fileId = String(cleanedContent[fileIdRange])
                imageReplacements.append((match.range, fileId))
            }
        }
        for match in imageMatches2.reversed() {
            if match.numberOfRanges >= 2,
               let fileIdRange = Range(match.range(at: 1), in: cleanedContent) {
                let fileId = String(cleanedContent[fileIdRange])
                imageReplacements.append((match.range, fileId))
            }
        }
        
        // 从后往前替换，避免索引偏移问题
        for replacement in imageReplacements {
            if let range = Range(replacement.range, in: cleanedContent) {
                let fileId = replacement.fileId
                let fileType = imageDict[fileId] ?? "jpeg" // 默认使用 jpeg
                let placeholder = "🖼️IMAGE_PLACEHOLDER_\(fileId)_\(fileType)🖼️"
                cleanedContent.replaceSubrange(range, with: placeholder)
            }
        }

        // 处理独立的 checkbox 标签（不在 <text> 标签内）
        // 格式: <input type="checkbox" indent="1" level="3" />
        let checkboxPattern = try! NSRegularExpression(pattern: "<input[^>]*type=\"checkbox\"[^>]*/>", options: [])
        let checkboxMatches = checkboxPattern.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        
        // 从后往前替换，避免索引偏移
        for match in checkboxMatches.reversed() {
            if let range = Range(match.range, in: cleanedContent) {
                let checkboxSymbol = "☐ " // 未选中的复选框
                cleanedContent.replaceSubrange(range, with: checkboxSymbol)
            }
        }

        // Split content by <text> tags to process each paragraph
        // This regex captures the content within <text> tags, including the tags themselves for context
        let textTagRegex = try! NSRegularExpression(pattern: "<text[^>]*>.*?<\\/text>", options: [.dotMatchesLineSeparators])
        let matches = textTagRegex.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))

        var lastRangeEnd = cleanedContent.startIndex
        for match in matches {
            if let range = Range(match.range, in: cleanedContent) {
                // Add newline for content between text tags if any
                if lastRangeEnd < range.lowerBound {
                    let interTextContent = String(cleanedContent[lastRangeEnd..<range.lowerBound])
                    if !interTextContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        mutableAttributedString.append(NSAttributedString(string: interTextContent + "\n"))
                    }
                }

                let textTagString = String(cleanedContent[range])
                if let attributedParagraph = parseTextTag(textTagString) {
                    mutableAttributedString.append(attributedParagraph)
                    mutableAttributedString.append(NSAttributedString(string: "\n")) // Add newline after each paragraph
                }
                lastRangeEnd = range.upperBound
            }
        }
        
        // Add any remaining content after the last text tag
        if lastRangeEnd < cleanedContent.endIndex {
            let remainingContent = String(cleanedContent[lastRangeEnd...])
            if !remainingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mutableAttributedString.append(NSAttributedString(string: remainingContent))
            }
        }

        // 处理图片占位符，替换为实际图片
        let finalString = mutableAttributedString.string
        let placeholderPattern = try! NSRegularExpression(pattern: "🖼️IMAGE_PLACEHOLDER_([^_]+)_([^🖼️]+)🖼️", options: [])
        let placeholderMatches = placeholderPattern.matches(in: finalString, options: [], range: NSRange(finalString.startIndex..., in: finalString))
        
        // 从后往前替换，避免索引偏移
        let result = NSMutableAttributedString(attributedString: mutableAttributedString)
        for match in placeholderMatches.reversed() {
            if match.numberOfRanges >= 3,
               let fileIdRange = Range(match.range(at: 1), in: finalString),
               let fileTypeRange = Range(match.range(at: 2), in: finalString) {
                let fileId = String(finalString[fileIdRange])
                let fileType = String(finalString[fileTypeRange])
                
                // 从本地加载图片
                if let imageData = LocalStorageService.shared.loadImage(fileId: fileId, fileType: fileType),
                   let image = NSImage(data: imageData) {
                    // 创建图片附件
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    
                    // 设置图片大小（最大宽度 600，保持宽高比）
                    let maxWidth: CGFloat = 600
                    let imageSize = image.size
                    let aspectRatio = imageSize.height / imageSize.width
                    let displayWidth = min(maxWidth, imageSize.width)
                    let displayHeight = displayWidth * aspectRatio
                    attachment.bounds = NSRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
                    
                    let imageAttributedString = NSAttributedString(attachment: attachment)
                    result.replaceCharacters(in: match.range, with: imageAttributedString)
                    print("[MiNoteContentParser] 插入图片: \(fileId).\(fileType)")
                } else {
                    // 图片不存在，显示占位文本
                    let placeholderText = "[图片: \(fileId)]"
                    result.replaceCharacters(in: match.range, with: NSAttributedString(string: placeholderText, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
                    print("[MiNoteContentParser] 图片不存在，显示占位符: \(fileId).\(fileType)")
                }
            }
        }

        return result
    }

    private static func parseTextTag(_ textTagString: String) -> NSAttributedString? {
        print("[MiNoteContentParser] parseTextTag called, textTagString: \(textTagString.prefix(50))...")
        
        // Extract content within the <text> tag
        let contentRegex = try! NSRegularExpression(pattern: "<text[^>]*>(.*?)<\\/text>", options: [.dotMatchesLineSeparators])
        guard let contentMatch = contentRegex.firstMatch(in: textTagString, options: [], range: NSRange(textTagString.startIndex..., in: textTagString)),
              let contentRange = Range(contentMatch.range(at: 1), in: textTagString) else {
            print("[MiNoteContentParser] WARNING: No content match found in textTagString")
            return nil
        }
        var innerContent = String(textTagString[contentRange])
        print("[MiNoteContentParser] innerContent extracted: \(innerContent.prefix(50))...")
        
        // 解码HTML实体（只处理与 XML 结构无关的通用实体，避免破坏标签本身）
        innerContent = innerContent
                                   .replacingOccurrences(of: "&amp;", with: "&")
                                   .replacingOccurrences(of: "&quot;", with: "\"")
                                   .replacingOccurrences(of: "&apos;", with: "'")

        // 使用一个简单的基于标签的解析器，将 <b>/<i>/<size> 等标签转换为 NSAttributedString 样式，
        // 同时从结果中移除所有标签文本，实现“直接渲染而不是显示标记”。
        let result = NSMutableAttributedString()
        
        // 当前样式状态
        struct StyleState {
            var isBold: Bool
            var isItalic: Bool
            var fontSize: CGFloat
            var backgroundColor: NSColor?
        }
        
        let baseFontSize = NSFont.systemFontSize
        var currentState = StyleState(isBold: false, isItalic: false, fontSize: baseFontSize, backgroundColor: nil)
        var stateStack: [StyleState] = []
        
        func makeFont(from state: StyleState) -> NSFont {
            var font = NSFont.systemFont(ofSize: state.fontSize)
            let manager = NSFontManager.shared
            if state.isBold {
                font = manager.convert(font, toHaveTrait: .boldFontMask)
            }
            if state.isItalic {
                font = manager.convert(font, toHaveTrait: .italicFontMask)
            }
            return font
        }
        
        let scalars = Array(innerContent.unicodeScalars)
        var index = 0
        
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "<" {
                // 解析标签
                var tagEndIndex = index + 1
                var foundEnd = false
                while tagEndIndex < scalars.count {
                    if scalars[tagEndIndex] == ">" {
                        foundEnd = true
                        break
                    }
                    tagEndIndex += 1
                }
                
                if !foundEnd {
                    // 非法标签，作为普通文本处理
                    let char = String(scalar)
                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: makeFont(from: currentState),
                        .foregroundColor: NSColor.labelColor  // 使用系统颜色，自动适配深色模式
                    ]
                    if let bg = currentState.backgroundColor {
                        attrs[.backgroundColor] = bg
                    }
                    result.append(NSAttributedString(string: char, attributes: attrs))
                    index += 1
                    continue
                }
                
                let tagContentScalars = scalars[(index + 1)..<tagEndIndex]
                let tagString = String(String.UnicodeScalarView(tagContentScalars))
                
                // 处理开始/结束标签
                if tagString.hasPrefix("/") {
                    // 结束标签
                    let name = String(tagString.dropFirst())
                    if !stateStack.isEmpty {
                        stateStack.removeLast()
                        if let last = stateStack.last {
                            currentState = last
                        } else {
                            currentState = StyleState(isBold: false, isItalic: false, fontSize: baseFontSize, backgroundColor: nil)
                        }
                    }
                    // 标签本身不输出到结果
                } else {
                    // 开始标签
                    stateStack.append(currentState)
                    
                    if tagString == "b" {
                        currentState.isBold = true
                    } else if tagString == "i" {
                        currentState.isItalic = true
                    } else if tagString == "size" {
                        currentState.fontSize = 24
                        currentState.isBold = true
                    } else if tagString == "mid-size" {
                        currentState.fontSize = 18
                        currentState.isBold = true
                    } else if tagString == "h3-size" {
                        currentState.fontSize = 14
                        currentState.isBold = true
                    } else if tagString.hasPrefix("background") {
                        // 解析 background color
                        // 形如：background color="#9affe8af"
                        if let colorRange = tagString.range(of: "color=\"") {
                            let start = colorRange.upperBound
                            if let end = tagString[start...].firstIndex(of: "\"") {
                                let hexString = String(tagString[start..<end])
                                if let color = NSColor(hex: hexString) {
                                    currentState.backgroundColor = color
                                }
                            }
                        }
                    } else if tagString.hasPrefix("input") && tagString.contains("type=\"checkbox\"") {
                        // 处理 checkbox 标签：<input type="checkbox" indent="1" level="3" />
                        let checkboxSymbol = "☐ "
                        var attrs: [NSAttributedString.Key: Any] = [
                            .font: makeFont(from: currentState),
                            .foregroundColor: NSColor.labelColor
                        ]
                        if let bg = currentState.backgroundColor {
                            attrs[.backgroundColor] = bg
                        }
                        result.append(NSAttributedString(string: checkboxSymbol, attributes: attrs))
                    }
                }
                
                // 跳过整个标签
                index = tagEndIndex + 1
            } else {
                // 普通字符，按当前样式追加
                let char = String(scalar)
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: makeFont(from: currentState),
                    .foregroundColor: NSColor.labelColor  // 使用系统颜色，自动适配深色模式
                ]
                if let bg = currentState.backgroundColor {
                    attrs[.backgroundColor] = bg
                }
                result.append(NSAttributedString(string: char, attributes: attrs))
                index += 1
            }
        }
        
        return result
    }

    // MARK: - NSAttributedString to XML

    static func parseToXML(_ attributedString: NSAttributedString) -> String {
        print("[MiNoteContentParser] parseToXML called, attributedString length: \(attributedString.length)")
        
        let mutableXML = NSMutableString()
        mutableXML.append("<new-format/>") // Always start with this tag
        print("[MiNoteContentParser] Added <new-format/> tag")

        let string = attributedString.string
        let fullRange = string.startIndex..<string.endIndex
        var currentPosition = 0

        string.enumerateSubstrings(in: fullRange, options: .byParagraphs) { (substring, substringRange, _, stop) in
            guard let substring = substring else { return }

            // Skip empty paragraphs that might result from multiple newlines
            let rangeLength = string.distance(from: substringRange.lowerBound, to: substringRange.upperBound)
            if substring.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty && rangeLength <= 1 {
                // If it's just a newline, we still need a <text> tag for it
                mutableXML.append("<text indent=\"1\"></text>\n")
                return
            }
            
            // Convert Range<String.Index> to NSRange for attributedSubstring
            let nsLocation = string.distance(from: string.startIndex, to: substringRange.lowerBound)
            let nsLength = rangeLength
            let paragraphRange = NSRange(location: nsLocation, length: nsLength)

            let paragraphAttributedString = attributedString.attributedSubstring(from: paragraphRange)
            let paragraphXML = convertParagraphToXML(paragraphAttributedString)
            mutableXML.append(paragraphXML)
            mutableXML.append("\n") // Add newline between text tags
        }

        return mutableXML as String
    }

    private static func convertParagraphToXML(_ paragraph: NSAttributedString) -> String {
        let mutableInnerXML = NSMutableString()
        let fullRange = NSRange(location: 0, length: paragraph.length)
        
        // 检查是否整个段落只是一个复选框
        let paragraphString = paragraph.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if paragraphString == "☐" || paragraphString == "☑" || paragraphString.hasPrefix("☐") || paragraphString.hasPrefix("☑") {
            // 提取复选框后的文本
            let checkboxSymbol = paragraphString.hasPrefix("☐") ? "☐" : "☑"
            let textAfterCheckbox = String(paragraphString.dropFirst(checkboxSymbol.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 生成 checkbox XML
            let checkboxXML = "<input type=\"checkbox\" indent=\"1\" level=\"3\" />"
            if !textAfterCheckbox.isEmpty {
                // 如果有文本，需要处理文本的格式
                let textRange = NSRange(location: checkboxSymbol.count, length: paragraph.length - checkboxSymbol.count)
                if textRange.location < paragraph.length {
                    let textAttributedString = paragraph.attributedSubstring(from: textRange)
                    let textXML = convertTextToXML(textAttributedString)
                    return "<text indent=\"1\">\(checkboxXML)\(textXML)</text>"
                }
            }
            return "<text indent=\"1\">\(checkboxXML)</text>"
        }

        paragraph.enumerateAttributes(in: fullRange, options: []) { (attributes, range, _) in
            let substring = paragraph.attributedSubstring(from: range).string
            var currentText = escapeXML(substring) // Escape content first
            
            // 检查是否是复选框符号
            if substring == "☐" || substring == "☑" {
                currentText = "<input type=\"checkbox\" indent=\"1\" level=\"3\" />"
            } else {
                // Check for font attributes (size, bold, italic)
                if let font = attributes[.font] as? NSFont {
                    var needsBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                    var needsItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                    
                    // Check for specific sizes that map to H1, H2, H3
                    if font.pointSize >= 24 { // H1
                        currentText = "<size>\(currentText)</size>"
                        needsBold = false // Handled by size tag
                    } else if font.pointSize >= 18 { // H2
                        currentText = "<mid-size>\(currentText)</mid-size>"
                        needsBold = false // Handled by size tag
                    } else if font.pointSize >= 14 { // H3
                        currentText = "<h3-size>\(currentText)</h3-size>"
                        needsBold = false // Handled by size tag
                    }

                    if needsBold {
                        currentText = "<b>\(currentText)</b>"
                    }
                    if needsItalic {
                        currentText = "<i>\(currentText)</i>"
                    }
                }

                // Check for background color
                if let backgroundColor = attributes[.backgroundColor] as? NSColor {
                    if let hexColor = backgroundColor.toHex() {
                        currentText = "<background color=\"#\(hexColor)\">\(currentText)</background>"
                    }
                }
            }
            
            mutableInnerXML.append(currentText)
        }
        
        // Default indent for now
        return "<text indent=\"1\">\(mutableInnerXML)</text>"
    }
    
    /// 将文本内容转换为 XML（不包含 <text> 标签）
    private static func convertTextToXML(_ attributedString: NSAttributedString) -> String {
        let mutableInnerXML = NSMutableString()
        let fullRange = NSRange(location: 0, length: attributedString.length)
        
        attributedString.enumerateAttributes(in: fullRange, options: []) { (attributes, range, _) in
            let substring = attributedString.attributedSubstring(from: range).string
            var currentText = escapeXML(substring)

            // Check for font attributes (size, bold, italic)
            if let font = attributes[.font] as? NSFont {
                var needsBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                var needsItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                
                // Check for specific sizes that map to H1, H2, H3
                if font.pointSize >= 24 { // H1
                    currentText = "<size>\(currentText)</size>"
                    needsBold = false // Handled by size tag
                } else if font.pointSize >= 18 { // H2
                    currentText = "<mid-size>\(currentText)</mid-size>"
                    needsBold = false // Handled by size tag
                } else if font.pointSize >= 14 { // H3
                    currentText = "<h3-size>\(currentText)</h3-size>"
                    needsBold = false // Handled by size tag
                }

                if needsBold {
                    currentText = "<b>\(currentText)</b>"
                }
                if needsItalic {
                    currentText = "<i>\(currentText)</i>"
                }
            }

            // Check for background color
            if let backgroundColor = attributes[.backgroundColor] as? NSColor {
                if let hexColor = backgroundColor.toHex() {
                    currentText = "<background color=\"#\(hexColor)\">\(currentText)</background>"
                }
            }
            
            mutableInnerXML.append(currentText)
        }
        
        return mutableInnerXML as String
    }

    private static func escapeXML(_ text: String) -> String {
        return text.replacingOccurrences(of: "&", with: "&amp;")
                   .replacingOccurrences(of: "<", with: "&lt;")
                   .replacingOccurrences(of: ">", with: "&gt;")
                   .replacingOccurrences(of: "\"", with: "&quot;")
                   .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    // MARK: - Helper Methods
    
    /// 将纯文本转换为小米笔记 XML 格式
    /// 用于新建笔记时，将用户输入的纯文本转换为合法的 XML 格式
    static func plainTextToXML(_ plainText: String) -> String {
        if plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "<new-format/><text indent=\"1\"></text>"
        }
        
        let lines = plainText.components(separatedBy: .newlines)
        var xmlParts: [String] = ["<new-format/>"]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let escaped = escapeXML(trimmed.isEmpty ? "" : trimmed)
            xmlParts.append("<text indent=\"1\">\(escaped)</text>")
        }
        
        return xmlParts.joined(separator: "\n")
    }
}

// MARK: - NSFont Extension for applying traits

extension NSMutableAttributedString {
    func applyFontTrait(_ trait: NSFontDescriptor.SymbolicTraits, range: NSRange) {
        self.enumerateAttribute(.font, in: range, options: []) { (value, subrange, _) in
            if let oldFont = value as? NSFont {
                // Convert NSFontDescriptor.SymbolicTraits to NSFontTraitMask
                let traitMask = NSFontTraitMask(rawValue: UInt(trait.rawValue))
                let newFont = NSFontManager.shared.convert(oldFont, toHaveTrait: traitMask)
                self.addAttribute(.font, value: newFont, range: subrange)
            }
        }
    }
}

// MARK: - NSColor Extension for Hex conversion

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    func toHex() -> String? {
        guard let rgbColor = usingColorSpace(.sRGB) else { return nil }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        let a = Int(rgbColor.alphaComponent * 255)

        if a == 255 { // Opaque color
            return String(format: "%02X%02X%02X", r, g, b)
        } else { // Color with alpha
            return String(format: "%02X%02X%02X%02X", r, g, b, a)
        }
    }
}
