import Foundation
import AppKit // For NSAttributedString and NSFont

class MiNoteContentParser {

    // MARK: - XML to NSAttributedString

    static func parseToAttributedString(_ xmlContent: String, noteRawData: [String: Any]? = nil) -> NSAttributedString {
        if xmlContent.isEmpty {
            return NSAttributedString(string: "", attributes: [.foregroundColor: NSColor.labelColor])
        }
        
        let mutableAttributedString = NSMutableAttributedString()
        
        // 创建段落样式，设置行间距（用于段落之间的内容）
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6.0  // 行间距：6点（与 MiNoteEditor 保持一致）

        // Remove the <new-format/> tag if present
        var cleanedContent = xmlContent.replacingOccurrences(of: "<new-format/>", with: "")
        
        // 提取图片信息字典（从 setting.data）
        var imageDict: [String: String] = [:] // fileId -> fileType
        if let rawData = noteRawData,
           let setting = rawData["setting"] as? [String: Any],
           let settingData = setting["data"] as? [[String: Any]] {
            print("[Parser] 找到 \(settingData.count) 个图片条目")
            for imgData in settingData {
                if let fileId = imgData["fileId"] as? String,
                   let mimeType = imgData["mimeType"] as? String,
                   mimeType.hasPrefix("image/") {
                    let fileType = String(mimeType.dropFirst("image/".count))
                    imageDict[fileId] = fileType
                    print("[Parser] 图片信息: fileId=\(fileId), fileType=\(fileType)")
                }
            }
        } else {
            print("[Parser] 警告：无法从 noteRawData 提取图片信息")
        }
        print("[Parser] 图片字典包含 \(imageDict.count) 个条目")
        
        // 处理图片引用：先替换图片引用为占位符，稍后插入图片
        // 格式1: ☺ fileId<0/></>
        let imagePattern1 = try! NSRegularExpression(pattern: "☺\\s+([^<\\s]+)(<0\\/><\\/>)?", options: [])
        let imageMatches1 = imagePattern1.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        
        // 格式2: <img fileid="fileId" ... />
        let imagePattern2 = try! NSRegularExpression(pattern: "<img[^>]+fileid=\"([^\"]+)\"[^>]*/>", options: [])
        let imageMatches2 = imagePattern2.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        
        // 格式3: [图片: fileId] (在 <text> 标签内)
        let imagePattern3 = try! NSRegularExpression(pattern: "\\[图片:\\s*([^\\]]+)\\]", options: [])
        let imageMatches3 = imagePattern3.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        
        // 收集所有图片引用位置（反向排序，以便从后往前替换）
        var imageReplacements: [(range: NSRange, fileId: String)] = []
        print("[Parser] 格式1 (☺): 找到 \(imageMatches1.count) 个匹配")
        for match in imageMatches1.reversed() {
            if match.numberOfRanges >= 2,
               let fileIdRange = Range(match.range(at: 1), in: cleanedContent) {
                let fileId = String(cleanedContent[fileIdRange])
                imageReplacements.append((match.range, fileId))
                print("[Parser] 格式1: 找到图片引用 fileId=\(fileId)")
            }
        }
        print("[Parser] 格式2 (<img>): 找到 \(imageMatches2.count) 个匹配")
        for match in imageMatches2.reversed() {
            if match.numberOfRanges >= 2,
               let fileIdRange = Range(match.range(at: 1), in: cleanedContent) {
                let fileId = String(cleanedContent[fileIdRange])
                imageReplacements.append((match.range, fileId))
                print("[Parser] 格式2: 找到图片引用 fileId=\(fileId)")
            }
        }
        print("[Parser] 格式3 ([图片:]): 找到 \(imageMatches3.count) 个匹配")
        for match in imageMatches3.reversed() {
            if match.numberOfRanges >= 2,
               let fileIdRange = Range(match.range(at: 1), in: cleanedContent) {
                let fileId = String(cleanedContent[fileIdRange]).trimmingCharacters(in: .whitespaces)
                imageReplacements.append((match.range, fileId))
                print("[Parser] 格式3: 找到图片引用 fileId=\(fileId)")
            }
        }
        
        print("[Parser] 总共找到 \(imageReplacements.count) 个图片引用需要替换")
        
        // 从后往前替换，避免索引偏移问题
        for replacement in imageReplacements {
            if let range = Range(replacement.range, in: cleanedContent) {
                let fileId = replacement.fileId
                let fileType = imageDict[fileId] ?? "jpeg" // 默认使用 jpeg
                // 使用 :: 作为分隔符，避免 fileId 或 fileType 中包含 _ 时的问题
                let placeholder = "🖼️IMAGE_PLACEHOLDER_\(fileId)::\(fileType)🖼️"
                print("[Parser] 替换图片引用: fileId=\(fileId), fileType=\(fileType), 占位符=\(placeholder)")
                cleanedContent.replaceSubrange(range, with: placeholder)
            }
        }

        // 处理独立的 checkbox 标签（不在 <text> 标签内）
        // 格式: <input type="checkbox" indent="1" level="3" />
        // 注意：这里先替换为占位符，稍后在处理文本时再替换为图标
        let checkboxPattern = try! NSRegularExpression(pattern: "<input[^>]*type=\"checkbox\"[^>]*/>", options: [])
        let checkboxMatches = checkboxPattern.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        
        // 从后往前替换，避免索引偏移
        for match in checkboxMatches.reversed() {
            if let range = Range(match.range, in: cleanedContent) {
                // 使用特殊占位符，稍后替换为图标
                cleanedContent.replaceSubrange(range, with: "☑️CHECKBOX_PLACEHOLDER☑️")
            }
        }
        
        // 处理分割线 <hr />
        let hrPattern = try! NSRegularExpression(pattern: "<hr[^>]*/>", options: [])
        let hrMatches = hrPattern.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        for match in hrMatches.reversed() {
            if let range = Range(match.range, in: cleanedContent) {
                cleanedContent.replaceSubrange(range, with: "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
            }
        }
        
        // 处理无序列表 <bullet indent="1" />
        let bulletPattern = try! NSRegularExpression(pattern: "<bullet[^>]*/>", options: [])
        let bulletMatches = bulletPattern.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        for match in bulletMatches.reversed() {
            if let range = Range(match.range, in: cleanedContent) {
                cleanedContent.replaceSubrange(range, with: "• ")
            }
        }
        
        // 处理有序列表 <order indent="1" inputNumber="0" />
        // 注意：保持原有的inputNumber，不重新计算序号
        let orderPattern = try! NSRegularExpression(pattern: "<order[^>]*inputNumber=\"(\\d+)\"[^>]*/>", options: [])
        let orderMatches = orderPattern.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        for match in orderMatches.reversed() {
            if let range = Range(match.range, in: cleanedContent),
               match.numberOfRanges >= 2,
               let numberRange = Range(match.range(at: 1), in: cleanedContent) {
                let numberStr = String(cleanedContent[numberRange])
                if let num = Int(numberStr) {
                    // 使用原有的inputNumber + 1作为显示序号
                    cleanedContent.replaceSubrange(range, with: "\(num + 1). ")
                } else {
                    cleanedContent.replaceSubrange(range, with: "1. ")
                }
            }
        }
        
        // 处理引用块 <quote>...</quote>
        // 注意：引用块需要特殊处理，在每行前添加竖线以保持连续性
        let quotePattern = try! NSRegularExpression(pattern: "<quote>(.*?)</quote>", options: [.dotMatchesLineSeparators])
        let quoteMatches = quotePattern.matches(in: cleanedContent, options: [], range: NSRange(cleanedContent.startIndex..., in: cleanedContent))
        for match in quoteMatches.reversed() {
            if let range = Range(match.range, in: cleanedContent),
               match.numberOfRanges >= 2,
               let contentRange = Range(match.range(at: 1), in: cleanedContent) {
                let quoteContent = String(cleanedContent[contentRange])
                // 在每行前添加引用标记，包括空行，以保持竖线连续性
                let quotedLines = quoteContent.components(separatedBy: "\n")
                    .map { line in
                        // 每行都添加竖线，保持连续性（包括空行）
                        return "│ \(line)"
                    }
                    .joined(separator: "\n")
                cleanedContent.replaceSubrange(range, with: "\n\(quotedLines)\n")
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
                        let attrs: [NSAttributedString.Key: Any] = [
                            .foregroundColor: NSColor.labelColor,
                            .paragraphStyle: paragraphStyle  // 添加段落样式（包含行间距）
                        ]
                        mutableAttributedString.append(NSAttributedString(string: interTextContent + "\n", attributes: attrs))
                    }
                }

                let textTagString = String(cleanedContent[range])
                if let attributedParagraph = parseTextTag(textTagString) {
                    mutableAttributedString.append(attributedParagraph)
                    // 添加换行符时也应用段落样式（包含行间距）
                    let newlineAttrs: [NSAttributedString.Key: Any] = [
                        .paragraphStyle: paragraphStyle
                    ]
                    mutableAttributedString.append(NSAttributedString(string: "\n", attributes: newlineAttrs)) // Add newline after each paragraph
                }
                lastRangeEnd = range.upperBound
            }
        }
        
        // Add any remaining content after the last text tag
        if lastRangeEnd < cleanedContent.endIndex {
            let remainingContent = String(cleanedContent[lastRangeEnd...])
            if !remainingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraphStyle  // 添加段落样式（包含行间距）
                ]
                mutableAttributedString.append(NSAttributedString(string: remainingContent, attributes: attrs))
            }
        }

        // 处理图片占位符，替换为实际图片
        // 处理checkbox占位符，替换为图标
        let finalString = mutableAttributedString.string
        let result = NSMutableAttributedString(attributedString: mutableAttributedString)
        
        // 先处理checkbox占位符
        let checkboxPlaceholderPattern = try! NSRegularExpression(pattern: "☑️CHECKBOX_PLACEHOLDER☑️", options: [])
        let checkboxPlaceholderMatches = checkboxPlaceholderPattern.matches(in: finalString, options: [], range: NSRange(finalString.startIndex..., in: finalString))
        for match in checkboxPlaceholderMatches.reversed() {
            // 创建checkbox图标
            if let checkboxImage = NSImage(systemSymbolName: "square", accessibilityDescription: "checkbox") {
                checkboxImage.size = NSSize(width: 16, height: 16)
                let attachment = NSTextAttachment()
                attachment.image = checkboxImage
                attachment.bounds = NSRect(x: 0, y: -2, width: 16, height: 16)
                let checkboxAttributedString = NSAttributedString(attachment: attachment)
                result.replaceCharacters(in: match.range, with: checkboxAttributedString)
                // 在图标后添加空格
                let spaceAttributedString = NSAttributedString(string: " ", attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: NSColor.labelColor
                ])
                result.insert(spaceAttributedString, at: match.range.location + 1)
            }
        }
        
        // 使用 :: 作为分隔符，避免 fileId 或 fileType 中包含 _ 时的问题
        let placeholderPattern = try! NSRegularExpression(pattern: "🖼️IMAGE_PLACEHOLDER_([^:]+)::([^🖼️]+)🖼️", options: [])
        let placeholderMatches = placeholderPattern.matches(in: finalString, options: [], range: NSRange(finalString.startIndex..., in: finalString))
        
        print("[Parser] 在最终字符串中找到 \(placeholderMatches.count) 个占位符")
        if placeholderMatches.isEmpty {
            // 如果没有找到占位符，打印最终字符串的一部分以便调试
            let preview = finalString.prefix(500)
            print("[Parser] 最终字符串预览（前500字符）: \(preview)")
        }
        
        // 从后往前替换，避免索引偏移
        for (index, match) in placeholderMatches.reversed().enumerated() {
            if match.numberOfRanges >= 3,
               let fileIdRange = Range(match.range(at: 1), in: finalString),
               let fileTypeRange = Range(match.range(at: 2), in: finalString) {
                let fileId = String(finalString[fileIdRange])
                let fileType = String(finalString[fileTypeRange])
                
                print("[Parser] 处理占位符 \(index + 1)/\(placeholderMatches.count): fileId=\(fileId), fileType=\(fileType)")
                
                // 从本地加载图片
                if let imageData = LocalStorageService.shared.loadImage(fileId: fileId, fileType: fileType),
                   let image = NSImage(data: imageData) {
                    print("[Parser] 成功加载图片: \(fileId).\(fileType), 大小: \(image.size)")
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
                    print("[Parser] 图片替换成功")
                } else {
                    // 图片不存在，显示占位文本
                    print("[Parser] 图片不存在: \(fileId).\(fileType)")
                    let placeholderText = "[图片: \(fileId)]"
                    result.replaceCharacters(in: match.range, with: NSAttributedString(string: placeholderText, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
                }
            } else {
                print("[Parser] 警告：占位符匹配失败，范围数量: \(match.numberOfRanges)")
            }
        }

        return result
    }

    private static func parseTextTag(_ textTagString: String) -> NSAttributedString? {
        // Extract content within the <text> tag
        let contentRegex = try! NSRegularExpression(pattern: "<text[^>]*>(.*?)<\\/text>", options: [.dotMatchesLineSeparators])
        guard let contentMatch = contentRegex.firstMatch(in: textTagString, options: [], range: NSRange(textTagString.startIndex..., in: textTagString)),
              let contentRange = Range(contentMatch.range(at: 1), in: textTagString) else {
            return nil
        }
        var innerContent = String(textTagString[contentRange])
        
        // 解析 indent 属性（从 <text> 标签中）
        var indentLevel: Int = 1
        if let indentMatch = try! NSRegularExpression(pattern: "indent=\"(\\d+)\"").firstMatch(in: textTagString, options: [], range: NSRange(textTagString.startIndex..., in: textTagString)),
           indentMatch.numberOfRanges >= 2,
           let indentRange = Range(indentMatch.range(at: 1), in: textTagString) {
            if let indent = Int(String(textTagString[indentRange])) {
                indentLevel = indent
            }
        }
        
        // 解码HTML实体（只处理与 XML 结构无关的通用实体，避免破坏标签本身）
        innerContent = innerContent
                                   .replacingOccurrences(of: "&amp;", with: "&")
                                   .replacingOccurrences(of: "&quot;", with: "\"")
                                   .replacingOccurrences(of: "&apos;", with: "'")

        // 使用一个简单的基于标签的解析器，将 <b>/<i>/<size> 等标签转换为 NSAttributedString 样式，
        // 同时从结果中移除所有标签文本，实现"直接渲染而不是显示标记"。
        let result = NSMutableAttributedString()
        
        // 创建段落样式，设置行间距
        // 注意：段落样式会在处理每个字符时根据当前状态动态创建
        
        // 当前样式状态
        struct StyleState {
            var isBold: Bool
            var isItalic: Bool
            var isUnderline: Bool
            var isStrikethrough: Bool
            var fontSize: CGFloat
            var backgroundColor: NSColor?
            var textAlignment: NSTextAlignment
            var headIndent: CGFloat  // 首行缩进
        }
        
        let baseFontSize = NSFont.systemFontSize
        // 根据 indent 级别计算缩进（每个级别 20 点）
        let indentValue = CGFloat(indentLevel - 1) * 20.0
        var currentState = StyleState(
            isBold: false,
            isItalic: false,
            isUnderline: false,
            isStrikethrough: false,
            fontSize: baseFontSize,
            backgroundColor: nil,
            textAlignment: .left,
            headIndent: indentValue
        )
        var stateStack: [StyleState] = []
        
        func makeFont(from state: StyleState) -> NSFont {
            var font = NSFont.systemFont(ofSize: state.fontSize)
            var traits: NSFontDescriptor.SymbolicTraits = []
            
            if state.isBold {
                traits.insert(.bold)
            }
            if state.isItalic {
                traits.insert(.italic)
            }
            
            if !traits.isEmpty {
                var fontDescriptor = font.fontDescriptor
                fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
                if let newFont = NSFont(descriptor: fontDescriptor, size: state.fontSize) {
                    font = newFont
                }
            }
            
            return font
        }
        
        /// 根据样式状态创建属性字典
        func makeAttributes(from state: StyleState) -> [NSAttributedString.Key: Any] {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 6.0  // 行间距：6点
            paragraphStyle.alignment = state.textAlignment
            paragraphStyle.headIndent = state.headIndent
            paragraphStyle.firstLineHeadIndent = state.headIndent
            
            var attrs: [NSAttributedString.Key: Any] = [
                .font: makeFont(from: state),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
            
            if let bg = state.backgroundColor {
                attrs[.backgroundColor] = bg
            }
            
            // 下划线
            if state.isUnderline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            
            // 删除线
            if state.isStrikethrough {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            
            return attrs
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
                    let attrs = makeAttributes(from: currentState)
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
                            currentState = StyleState(
                                isBold: false,
                                isItalic: false,
                                isUnderline: false,
                                isStrikethrough: false,
                                fontSize: baseFontSize,
                                backgroundColor: nil,
                                textAlignment: .left,
                                headIndent: 0
                            )
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
                    } else if tagString == "u" {
                        currentState.isUnderline = true
                    } else if tagString == "delete" {
                        currentState.isStrikethrough = true
                    } else if tagString == "size" {
                        currentState.fontSize = 24
                        currentState.isBold = true
                    } else if tagString == "mid-size" {
                        currentState.fontSize = 18
                        currentState.isBold = true
                    } else if tagString == "h3-size" {
                        currentState.fontSize = 14
                        currentState.isBold = true
                    } else if tagString == "center" {
                        currentState.textAlignment = .center
                    } else if tagString == "right" {
                        currentState.textAlignment = .right
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
                        // 使用图标而不是文本符号
                        let checkboxImage = NSImage(systemSymbolName: "square", accessibilityDescription: "checkbox") ?? NSImage()
                        checkboxImage.size = NSSize(width: 16, height: 16)
                        let attachment = NSTextAttachment()
                        attachment.image = checkboxImage
                        attachment.bounds = NSRect(x: 0, y: -2, width: 16, height: 16)
                        let checkboxAttributedString = NSAttributedString(attachment: attachment)
                        result.append(checkboxAttributedString)
                        // 在图标后添加空格
                        let spaceAttributedString = NSAttributedString(string: " ", attributes: makeAttributes(from: currentState))
                        result.append(spaceAttributedString)
                    }
                }
                
                // 跳过整个标签
                index = tagEndIndex + 1
            } else {
                // 普通字符，按当前样式追加
                let char = String(scalar)
                let attrs = makeAttributes(from: currentState)
                result.append(NSAttributedString(string: char, attributes: attrs))
                index += 1
            }
        }
        
        return result
    }

    // MARK: - NSAttributedString to XML

    static func parseToXML(_ attributedString: NSAttributedString) -> String {
        let mutableXML = NSMutableString()
        mutableXML.append("<new-format/>") // Always start with this tag

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

        // 获取段落对齐方式和缩进
        var paragraphIndent = 1
        var paragraphAlignment: NSTextAlignment = .left
        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            paragraphAlignment = paragraphStyle.alignment
            // 根据 headIndent 计算 indent 级别（每 20 点一个级别）
            let headIndent = paragraphStyle.headIndent
            paragraphIndent = max(1, Int(headIndent / 20.0) + 1)
        }
        
        paragraph.enumerateAttributes(in: fullRange, options: []) { (attributes, range, _) in
            let substring = paragraph.attributedSubstring(from: range).string
            var currentText = escapeXML(substring) // Escape content first
            
            // 检查是否是复选框附件（NSTextAttachment）
            var isCheckbox = false
            if let attachment = attributes[.attachment] as? NSTextAttachment,
               let image = attachment.image {
                // 检查是否是系统图标 "square"（checkbox图标）
                // 通过检查图片大小来判断（checkbox图标通常是16x16）
                if image.size.width <= 20 && image.size.width > 0 {
                    isCheckbox = true
                    currentText = "<input type=\"checkbox\" indent=\"\(paragraphIndent)\" level=\"3\" />"
                }
            }
            
            // 兼容旧的文本符号格式
            if !isCheckbox && (substring == "☐" || substring == "☑") {
                currentText = "<input type=\"checkbox\" indent=\"\(paragraphIndent)\" level=\"3\" />"
            } else if substring.hasPrefix("• ") {
                // 无序列表
                let listText = String(substring.dropFirst(2))
                mutableInnerXML.append("<bullet indent=\"\(paragraphIndent)\" />\(escapeXML(listText))")
                return
            } else if let match = try? NSRegularExpression(pattern: "^\\d+\\.\\s+(.+)").firstMatch(in: substring, options: [], range: NSRange(substring.startIndex..., in: substring)),
                      match.numberOfRanges >= 2,
                      let textRange = Range(match.range(at: 1), in: substring) {
                // 有序列表 - 保持原有序号，不重新计算
                let listText = String(substring[textRange])
                let numberMatch = try! NSRegularExpression(pattern: "^\\d+").firstMatch(in: substring, options: [], range: NSRange(substring.startIndex..., in: substring))
                let orderNumber = numberMatch != nil ? Int(substring[Range(numberMatch!.range, in: substring)!]) ?? 0 : 0
                // inputNumber = 显示序号 - 1（保持原有逻辑）
                let inputNumber = max(0, orderNumber - 1)
                mutableInnerXML.append("<order indent=\"\(paragraphIndent)\" inputNumber=\"\(inputNumber)\" />\(escapeXML(listText))")
                return
            } else if substring.contains("━━") {
                // 分割线
                mutableInnerXML.append("<hr />")
                return
            } else if substring.hasPrefix("│ ") {
                // 引用块 - 移除每行的 "│ " 前缀，稍后统一处理
                let quoteText = String(substring.dropFirst(2))
                mutableInnerXML.append(escapeXML(quoteText))
                return
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
                
                // 检查下划线
                if let underlineStyle = attributes[.underlineStyle] as? Int,
                   underlineStyle != 0 {
                    currentText = "<u>\(currentText)</u>"
                }
                
                // 检查删除线
                if let strikethroughStyle = attributes[.strikethroughStyle] as? Int,
                   strikethroughStyle != 0 {
                    currentText = "<delete>\(currentText)</delete>"
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
        
        // 检查是否是引用块（所有行都以 "│ " 开头）
        let paragraphText = paragraph.string
        let lines = paragraphText.components(separatedBy: "\n")
        let isQuoteBlock = !lines.isEmpty && lines.allSatisfy { line in
            line.hasPrefix("│ ") || line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        
        if isQuoteBlock {
            // 引用块：移除所有行的 "│ " 前缀，然后用 <quote> 包裹
            let quoteLines = lines.map { line in
                if line.hasPrefix("│ ") {
                    return String(line.dropFirst(2))
                }
                return line
            }
            let quoteContent = quoteLines.joined(separator: "\n")
            // 将引用内容转换为XML（每行一个text标签）
            let quoteXML = NSMutableString()
            quoteXML.append("<quote>")
            for quoteLine in quoteLines {
                if !quoteLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    quoteXML.append("<text indent=\"1\">\(escapeXML(quoteLine))</text>\n")
                } else {
                    quoteXML.append("<text indent=\"1\"></text>\n")
                }
            }
            quoteXML.append("</quote>")
            return quoteXML as String
        }
        
        // 根据对齐方式添加标签
        var finalText = mutableInnerXML as String
        if paragraphAlignment == .center {
            finalText = "<center>\(finalText)</center>"
        } else if paragraphAlignment == .right {
            finalText = "<right>\(finalText)</right>"
        }
        
        return "<text indent=\"\(paragraphIndent)\">\(finalText)</text>"
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
            
            // 检查下划线
            if let underlineStyle = attributes[.underlineStyle] as? Int,
               underlineStyle != 0 {
                currentText = "<u>\(currentText)</u>"
            }
            
            // 检查删除线
            if let strikethroughStyle = attributes[.strikethroughStyle] as? Int,
               strikethroughStyle != 0 {
                currentText = "<delete>\(currentText)</delete>"
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

