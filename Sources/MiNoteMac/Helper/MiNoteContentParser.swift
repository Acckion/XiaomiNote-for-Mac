import Foundation
import AppKit // For NSAttributedString and NSFont

class MiNoteContentParser {

    // MARK: - XML to NSAttributedString

    static func parseToAttributedString(_ xmlContent: String) -> NSAttributedString {
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
        let cleanedContent = xmlContent.replacingOccurrences(of: "<new-format/>", with: "")

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

        return mutableAttributedString
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

        paragraph.enumerateAttributes(in: fullRange, options: []) { (attributes, range, _) in
            let substring = paragraph.attributedSubstring(from: range).string
            var currentText = escapeXML(substring) // Escape content first

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
        
        // Default indent for now
        return "<text indent=\"1\">\(mutableInnerXML)</text>"
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
