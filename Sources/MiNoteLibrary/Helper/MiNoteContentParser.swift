import Foundation
import AppKit
import CoreGraphics
import RichTextKit

// MARK: - CheckboxTextAttachment

/// 可交互的复选框附件
/// 使用自定义的 NSTextAttachmentCell 来实现可点击的复选框
class CheckboxTextAttachment: NSTextAttachment {
    var isChecked: Bool = false {
        didSet {
            updateImage()
        }
    }
    
    override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupCheckbox()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCheckbox()
    }
    
    private func setupCheckbox() {
        print("🔍 [CheckboxTextAttachment] setupCheckbox 被调用")
        updateImage()
        bounds = NSRect(x: 0, y: -4, width: 16, height: 16)
        print("🔍 [CheckboxTextAttachment] 设置 bounds: \(bounds), image=\(self.image != nil ? "存在" : "nil")")
    }
    
    private func updateImage() {
        let symbolName = isChecked ? "checkmark.square.fill" : "square"
        print("🔍 [CheckboxTextAttachment] updateImage 被调用，isChecked=\(isChecked), symbolName=\(symbolName)")
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "checkbox") {
            image.size = NSSize(width: 16, height: 16)
            self.image = image
            print("🔍 [CheckboxTextAttachment] 成功创建图片，size=\(image.size)")
        } else {
            print("⚠️ [CheckboxTextAttachment] 无法创建系统符号图片: \(symbolName)")
        }
    }
    
    #if macOS
    override var attachmentCell: NSTextAttachmentCellProtocol? {
        get {
            return CheckboxAttachmentCell(checkbox: self)
        }
        set {
            super.attachmentCell = newValue
        }
    }
    #endif
}

#if macOS
/// 复选框附件单元格，处理点击事件
class CheckboxAttachmentCell: NSTextAttachmentCell {
    weak var checkbox: CheckboxTextAttachment?
    
    init(checkbox: CheckboxTextAttachment) {
        self.checkbox = checkbox
        // 使用 checkbox 的 image 初始化 imageCell
        super.init(imageCell: checkbox.image)
        print("🔍 [CheckboxAttachmentCell] 初始化，image=\(image != nil ? "存在" : "nil")")
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // 确保使用最新的图片
        if let checkbox = checkbox {
            // 更新图片（如果 checkbox 状态改变）
            if let updatedImage = checkbox.image {
                image = updatedImage
            }
        }
        
        // 绘制图片
        if let imageToDraw = image {
            imageToDraw.draw(in: cellFrame)
            print("🔍 [CheckboxAttachmentCell] draw 被调用，frame=\(cellFrame), image=存在")
        } else {
            print("⚠️ [CheckboxAttachmentCell] draw 被调用，但没有图片可绘制")
        }
    }
    
    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        var rect = super.cellFrame(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
        rect.origin.y -= 2
        return rect
    }
    
    override func hitTest(for point: NSPoint, in cellFrame: NSRect, of controlView: NSView?) -> NSCell.HitResult {
        if cellFrame.contains(point) {
            return .contentArea
        }
        return .none
    }
    
    override func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        if let checkbox = checkbox {
            checkbox.isChecked.toggle()
            // 更新图片
            image = checkbox.image
            // 通知文本视图更新
            if let textView = controlView as? NSTextView {
                textView.setNeedsDisplay(cellFrame)
            }
            return true
        }
        return false
    }
}
#endif

// MARK: - MiNoteContentParser

/// 小米笔记内容解析器
/// 负责小米笔记 XML 格式与 NSAttributedString 之间的双向转换
class MiNoteContentParser {
    
    // MARK: - 常量定义
    
    private static let baseFontSize: CGFloat = NSFont.systemFontSize
    private static let h1FontSize: CGFloat = 24.0  // 减小一级标题大小
    private static let h2FontSize: CGFloat = 18.0
    private static let h3FontSize: CGFloat = 14.0
    private static let indentUnit: CGFloat = 20.0  // 每个缩进级别 20 点
    private static let lineSpacing: CGFloat = 6.0   // 行间距 6 点

    // MARK: - XML to NSAttributedString

    /// 将小米笔记 XML 格式转换为 NSAttributedString
    /// - Parameters:
    ///   - xmlContent: 小米笔记 XML 内容
    ///   - noteRawData: 笔记原始数据（用于提取图片信息等）
    /// - Returns: 转换后的 NSAttributedString
    static func parseToAttributedString(_ xmlContent: String, noteRawData: [String: Any]? = nil) -> NSAttributedString {
        print("🔍 [Parser] ========== 开始解析 XML ==========")
        print("🔍 [Parser] 输入 XML 长度: \(xmlContent.count)")
        print("🔍 [Parser] 输入 XML 内容（前500字符）: \(String(xmlContent.prefix(500)))")
        
        guard !xmlContent.isEmpty else {
            print("🔍 [Parser] XML 内容为空，返回空字符串")
            return NSAttributedString(string: "", attributes: defaultAttributes())
        }
        
        // 移除 <new-format/> 标签
        var cleanedContent = xmlContent.replacingOccurrences(of: "<new-format/>", with: "")
        print("🔍 [Parser] 清理后内容长度: \(cleanedContent.count)")
        
        // 提取图片信息
        let imageDict = extractImageDict(from: noteRawData)
        
        // 处理特殊元素（图片、复选框、分割线、列表等）
        cleanedContent = preprocessSpecialElements(cleanedContent, imageDict: imageDict)
        
        // 解析 XML 结构
        let result = NSMutableAttributedString()
        
        // 先处理引用块（因为它们可能包含多个 <text> 标签）
        // 将引用块替换为占位符，稍后处理
        var quotePlaceholders: [(placeholder: String, content: String)] = []
        var processedContent = cleanedContent
        let quotePattern = try! NSRegularExpression(pattern: "<quote>(.*?)</quote>", options: [.dotMatchesLineSeparators])
        let quoteMatches = quotePattern.matches(in: processedContent, options: [], range: NSRange(processedContent.startIndex..., in: processedContent))
        
        for (index, match) in quoteMatches.reversed().enumerated() {
            if match.numberOfRanges >= 2,
               let contentRange = Range(match.range(at: 1), in: processedContent) {
                let quoteContent = String(processedContent[contentRange])
                let placeholder = "🔄QUOTE_PLACEHOLDER_\(index)🔄"
                quotePlaceholders.append((placeholder, quoteContent))
                if let range = Range(match.range, in: processedContent) {
                    processedContent.replaceSubrange(range, with: placeholder)
                }
            }
        }
        
        // 注意：不要提前处理 <hr />，让 extractTextTagsWithIntervals 统一处理
        // 这样可以正确识别 <hr /> 在两个 <text> 标签之间的情况
        
        // 解析所有 <text> 标签，同时检查标签之间的内容（可能包含 <hr />）
        print("🔍 [Parser] 准备提取 <text> 标签，processedContent 长度: \(processedContent.count)")
        print("🔍 [Parser] processedContent 预览（前1000字符）:\n\(String(processedContent.prefix(1000)))")
        
        // 使用更智能的方式：提取 <text> 标签及其之间的内容
        let textTagsWithIntervals = extractTextTagsWithIntervals(from: processedContent)
        print("🔍 [Parser] 找到 \(textTagsWithIntervals.count) 个文本段落（包括间隔）")
        
        // 跟踪每个缩进级别的有序列表序号（用于自动递增）
        var orderCounters: [Int: Int] = [:]  // [indent: currentNumber]
        
        for (index, item) in textTagsWithIntervals.enumerated() {
            switch item {
            case .textTag(let indent, let content):
                print("🔍 [Parser] 处理第 \(index + 1) 个 <text> 标签，indent=\(indent)")
                print("🔍 [Parser] 标签内容（前200字符）: \(String(content.prefix(200)))")
                // 检查是否是引用块占位符
                if content.hasPrefix("🔄QUOTE_PLACEHOLDER_") {
                    if let quoteIndex = Int(content.replacingOccurrences(of: "🔄QUOTE_PLACEHOLDER_", with: "").replacingOccurrences(of: "🔄", with: "")),
                       quoteIndex < quotePlaceholders.count {
                        let quoteContent = quotePlaceholders[quoteIndex].content
                        if let quoteAttr = parseQuoteBlock(quoteContent) {
                            result.append(quoteAttr)
                            if index < textTagsWithIntervals.count - 1 {
                                // 换行符不应该包含段落样式
                                let newlineAttrs: [NSAttributedString.Key: Any] = [
                                    .foregroundColor: NSColor.labelColor,
                                    .font: NSFont.systemFont(ofSize: baseFontSize)
                                ]
                                result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                            }
                        }
                    }
                } else if let textAttr = parseTextTag(content, indent: indent) {
                    print("🔍 [Parser] 成功解析文本标签，长度: \(textAttr.length)")
                    // 检查第一个字符的属性
                    if textAttr.length > 0 {
                        let attrs = textAttr.attributes(at: 0, effectiveRange: nil)
                        if let font = attrs[.font] as? NSFont {
                            print("🔍 [Parser] 第一个字符字体: size=\(font.pointSize), bold=\(font.fontDescriptor.symbolicTraits.contains(.bold)), italic=\(font.fontDescriptor.symbolicTraits.contains(.italic))")
                        }
                    }
                    result.append(textAttr)
                    // 在段落之间添加换行（除了最后一个）
                    // 重要：换行符不应该包含段落样式，让下一个段落使用自己的缩进
                    if index < textTagsWithIntervals.count - 1 {
                        // 创建没有段落样式的换行符属性，避免缩进样式泄漏到下一个段落
                        let newlineAttrs: [NSAttributedString.Key: Any] = [
                            .foregroundColor: NSColor.labelColor,
                            .font: NSFont.systemFont(ofSize: baseFontSize)
                            // 注意：不包含 .paragraphStyle，让下一个段落使用自己的样式
                        ]
                        result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                    }
                } else {
                    print("⚠️ [Parser] 警告：无法解析文本标签")
                }
                
            case .hr:
                print("🔍 [Parser] 处理分割线（独立标签或 <text> 标签之间）")
                if let hrAttr = parseHrTag() {
                    print("🔍 [Parser] 成功创建分割线，长度: \(hrAttr.length)")
                    // 检查是否包含附件
                    var hasAttachment = false
                    hrAttr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: hrAttr.length), options: []) { (value, range, _) in
                        if value != nil {
                            hasAttachment = true
                        }
                    }
                    print("🔍 [Parser] 分割线是否包含附件: \(hasAttachment)")
                    
                    // 换行符不应该包含段落样式
                    let newlineAttrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: NSColor.labelColor,
                        .font: NSFont.systemFont(ofSize: baseFontSize)
                    ]
                    result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                    result.append(hrAttr)
                    result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                } else {
                    print("⚠️ [Parser] 警告：无法创建分割线")
                }
            case .bullet(let indent, let text):
                print("🔍 [Parser] 处理独立无序列表，indent=\(indent), text=\(text)")
                if let bulletAttr = parseStandaloneBullet(indent: indent, text: text) {
                    result.append(bulletAttr)
                    if index < textTagsWithIntervals.count - 1 {
                        result.append(NSAttributedString(string: "\n", attributes: newlineAttributes()))
                    }
                }
            case .order(let indent, let inputNumber, let text):
                print("🔍 [Parser] 处理独立有序列表，indent=\(indent), inputNumber=\(inputNumber), text=\(text)")
                // 自动递增序号：如果这是相同缩进级别的连续有序列表项，递增序号
                // 否则，使用 inputNumber（如果为 0，则从 1 开始）
                let currentCounter = orderCounters[indent] ?? 0
                let effectiveInputNumber: Int
                if inputNumber == 0 && currentCounter == 0 {
                    // 第一个有序列表项，从 1 开始
                    effectiveInputNumber = 0
                    orderCounters[indent] = 1
                } else if inputNumber > 0 {
                    // 使用 XML 中指定的 inputNumber
                    effectiveInputNumber = inputNumber
                    orderCounters[indent] = inputNumber + 1
                } else {
                    // 自动递增
                    effectiveInputNumber = currentCounter
                    orderCounters[indent] = currentCounter + 1
                }
                print("🔍 [Parser] 有序列表序号：inputNumber=\(inputNumber), currentCounter=\(currentCounter), effectiveInputNumber=\(effectiveInputNumber)")
                if let orderAttr = parseStandaloneOrder(indent: indent, inputNumber: effectiveInputNumber, text: text) {
                    result.append(orderAttr)
                    if index < textTagsWithIntervals.count - 1 {
                        // 换行符不应该包含段落样式
                        let newlineAttrs: [NSAttributedString.Key: Any] = [
                            .foregroundColor: NSColor.labelColor,
                            .font: NSFont.systemFont(ofSize: baseFontSize)
                        ]
                        result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                    }
                }
                // 如果不是有序列表，重置该缩进级别的计数器
                // （这里不需要重置，因为下一个非有序列表项会自然中断序列）
            case .checkbox(let indent, let level, let text):
                print("🔍 [Parser] ========== 处理独立复选框 ==========")
                print("🔍 [Parser] indent=\(indent), level=\(level), text='\(text)'")
                if let checkboxAttr = parseStandaloneCheckbox(indent: indent, level: level, text: text) {
                    print("🔍 [Parser] 复选框解析成功，长度: \(checkboxAttr.length)")
                    
                    // 验证附件
                    var hasAttachment = false
                    checkboxAttr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: checkboxAttr.length), options: []) { (value, range, _) in
                        if value != nil {
                            hasAttachment = true
                            print("🔍 [Parser] 复选框附件存在于位置: \(range.location)")
                            if let att = value as? CheckboxTextAttachment {
                                print("🔍 [Parser] 附件类型正确: CheckboxTextAttachment, image=\(att.image != nil ? "存在" : "nil")")
                            }
                        }
                    }
                    print("🔍 [Parser] 复选框是否包含附件: \(hasAttachment)")
                    print("🔍 [Parser] 复选框字符串: '\(checkboxAttr.string)'")
                    
                    result.append(checkboxAttr)
                    
                    // 验证添加到结果后
                    print("🔍 [Parser] 复选框已添加到结果，当前结果长度: \(result.length)")
                    var hasAttachmentInResult = false
                    result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length), options: []) { (value, range, _) in
                        if value != nil {
                            hasAttachmentInResult = true
                            print("🔍 [Parser] 结果中复选框附件存在于位置: \(range.location)")
                        }
                    }
                    print("🔍 [Parser] 结果中是否包含复选框附件: \(hasAttachmentInResult)")
                    
                    if index < textTagsWithIntervals.count - 1 {
                        // 换行符不应该包含段落样式
                        let newlineAttrs: [NSAttributedString.Key: Any] = [
                            .foregroundColor: NSColor.labelColor,
                            .font: NSFont.systemFont(ofSize: baseFontSize)
                        ]
                        result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                    }
                } else {
                    print("⚠️ [Parser] 警告：无法解析复选框")
                }
                print("🔍 [Parser] ========== 复选框处理完成 ==========")
            case .quote(let quoteIndexString):
                print("🔍 [Parser] ========== 处理独立引用块 ==========")
                print("🔍 [Parser] quoteIndexString='\(quoteIndexString)'")
                // 提取引用索引
                if let quoteIndex = Int(quoteIndexString),
                   quoteIndex < quotePlaceholders.count {
                    let actualQuoteContent = quotePlaceholders[quoteIndex].content
                    print("🔍 [Parser] 引用块 #\(quoteIndex) 内容长度: \(actualQuoteContent.count)")
                    print("🔍 [Parser] 引用块 #\(quoteIndex) 内容预览: \(String(actualQuoteContent.prefix(200)))")
                    print("🔍 [Parser] 引用块 #\(quoteIndex) 完整内容:\n\(actualQuoteContent)")
                    
                    if let quoteAttr = parseQuoteBlock(actualQuoteContent) {
                        print("🔍 [Parser] 引用块解析成功，长度: \(quoteAttr.length)")
                        print("🔍 [Parser] 引用块字符串: '\(quoteAttr.string.prefix(100))'")
                        
                        result.append(quoteAttr)
                        
                        // 验证添加到结果后
                        print("🔍 [Parser] 引用块已添加到结果，当前结果长度: \(result.length)")
                        
                        if index < textTagsWithIntervals.count - 1 {
                            result.append(NSAttributedString(string: "\n", attributes: newlineAttributes()))
                        }
                    } else {
                        print("⚠️ [Parser] 警告：无法解析引用块 #\(quoteIndex)")
                    }
                } else {
                    print("⚠️ [Parser] 警告：引用块索引无效: \(quoteIndexString)")
                    print("🔍 [Parser] quotePlaceholders.count=\(quotePlaceholders.count)")
                }
                print("🔍 [Parser] ========== 引用块处理完成 ==========")
            }
        }
        
        print("🔍 [Parser] 最终结果长度: \(result.length)")
        print("🔍 [Parser] ========== 解析完成 ==========")
        return result
    }
    
    // MARK: - NSAttributedString to XML
    
    /// 将 NSAttributedString 转换为小米笔记 XML 格式
    /// - Parameter attributedString: 要转换的 NSAttributedString
    /// - Returns: 转换后的 XML 字符串
    static func parseToXML(_ attributedString: NSAttributedString) -> String {
        guard attributedString.length > 0 else {
            return "<new-format/><text indent=\"1\"></text>"
        }
        
        var xmlParts: [String] = ["<new-format/>"]
        
        // 按段落分割（使用 enumerateSubstrings 更可靠）
        let string = attributedString.string
        let fullRange = string.startIndex..<string.endIndex
        
        string.enumerateSubstrings(in: fullRange, options: .byParagraphs) { (substring, substringRange, _, _) in
            guard let substring = substring else { return }
            
            // 跳过空段落（但保留换行）
            let rangeLength = string.distance(from: substringRange.lowerBound, to: substringRange.upperBound)
            if substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rangeLength <= 1 {
                xmlParts.append("<text indent=\"1\"></text>")
                return
            }
            
            // 转换为 NSRange 以获取属性
            let nsLocation = string.distance(from: string.startIndex, to: substringRange.lowerBound)
            let nsLength = rangeLength
            let paragraphRange = NSRange(location: nsLocation, length: nsLength)
            
            if paragraphRange.location < attributedString.length {
                let paragraphAttr = attributedString.attributedSubstring(from: paragraphRange)
                let paragraphXML = convertParagraphToXML(paragraphAttr)
                xmlParts.append(paragraphXML)
            }
        }
        
        return xmlParts.joined(separator: "\n")
    }
    
    // MARK: - 纯文本转 XML
    
    /// 将纯文本转换为小米笔记 XML 格式
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
    
    // MARK: - 私有辅助方法
    
    // MARK: XML 解析辅助方法
    
    /// 提取图片信息字典
    private static func extractImageDict(from noteRawData: [String: Any]?) -> [String: String] {
        var imageDict: [String: String] = [:]
        
        guard let rawData = noteRawData,
           let setting = rawData["setting"] as? [String: Any],
              let settingData = setting["data"] as? [[String: Any]] else {
            return imageDict
        }
        
            for imgData in settingData {
                if let fileId = imgData["fileId"] as? String,
                   let mimeType = imgData["mimeType"] as? String,
                   mimeType.hasPrefix("image/") {
                    let fileType = String(mimeType.dropFirst("image/".count))
                    imageDict[fileId] = fileType
            }
        }
        
        return imageDict
    }
    
    /// 预处理特殊元素（图片、复选框等）
    private static func preprocessSpecialElements(_ content: String, imageDict: [String: String]) -> String {
        var processed = content
        
        // 处理图片引用
        // 格式1: ☺ fileId<0/></>
        let imagePattern1 = try! NSRegularExpression(pattern: "☺\\s+([^<\\s]+)(<0\\/><\\/>)?", options: [])
        let imageMatches1 = imagePattern1.matches(in: processed, options: [], range: NSRange(processed.startIndex..., in: processed))
        for match in imageMatches1.reversed() {
            if match.numberOfRanges >= 2,
               let fileIdRange = Range(match.range(at: 1), in: processed) {
                let fileId = String(processed[fileIdRange])
                let fileType = imageDict[fileId] ?? "jpeg"
                let placeholder = "🖼️IMAGE_\(fileId)::\(fileType)🖼️"
                if let range = Range(match.range, in: processed) {
                    processed.replaceSubrange(range, with: placeholder)
                }
            }
        }
        
        // 格式2: <img fileid="fileId" ... />
        let imagePattern2 = try! NSRegularExpression(pattern: "<img[^>]+fileid=\"([^\"]+)\"[^>]*/>", options: [])
        let imageMatches2 = imagePattern2.matches(in: processed, options: [], range: NSRange(processed.startIndex..., in: processed))
        for match in imageMatches2.reversed() {
            if match.numberOfRanges >= 2,
               let fileIdRange = Range(match.range(at: 1), in: processed) {
                let fileId = String(processed[fileIdRange])
                let fileType = imageDict[fileId] ?? "jpeg"
                let placeholder = "🖼️IMAGE_\(fileId)::\(fileType)🖼️"
                if let range = Range(match.range, in: processed) {
                    processed.replaceSubrange(range, with: placeholder)
                }
            }
        }
        
        // 格式3: [图片: fileId]
        let imagePattern3 = try! NSRegularExpression(pattern: "\\[图片:\\s*([^\\]]+)\\]", options: [])
        let imageMatches3 = imagePattern3.matches(in: processed, options: [], range: NSRange(processed.startIndex..., in: processed))
        for match in imageMatches3.reversed() {
            if match.numberOfRanges >= 2,
               let fileIdRange = Range(match.range(at: 1), in: processed) {
                let fileId = String(processed[fileIdRange]).trimmingCharacters(in: .whitespaces)
                let fileType = imageDict[fileId] ?? "jpeg"
                let placeholder = "🖼️IMAGE_\(fileId)::\(fileType)🖼️"
                if let range = Range(match.range, in: processed) {
                    processed.replaceSubrange(range, with: placeholder)
                }
            }
        }
        
        return processed
    }
    
    /// 提取引用块
    private static func extractQuoteBlocks(from content: String) -> [(range: NSRange, content: String)] {
        var quoteBlocks: [(range: NSRange, content: String)] = []
        
        let quotePattern = try! NSRegularExpression(pattern: "<quote>(.*?)</quote>", options: [.dotMatchesLineSeparators])
        let matches = quotePattern.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        for match in matches.reversed() {
            if match.numberOfRanges >= 2,
               let contentRange = Range(match.range(at: 1), in: content) {
                let quoteContent = String(content[contentRange])
                quoteBlocks.append((match.range, quoteContent))
            }
        }
        
        return quoteBlocks
    }
    
    
    /// 文本段落类型（用于区分各种标签）
    private enum TextSegment {
        case textTag(indent: Int, content: String)
        case hr
        case bullet(indent: Int, text: String)  // 无序列表
        case order(indent: Int, inputNumber: Int, text: String)  // 有序列表
        case checkbox(indent: Int, level: Int, text: String)  // 复选框
        case quote(content: String)  // 引用块
    }
    
    /// 提取所有 <text> 标签及其之间的内容（包括 <hr />、独立的 <bullet />、<order />、<input />）
    private static func extractTextTagsWithIntervals(from content: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        
        print("🔍 [extractTextTagsWithIntervals] 开始提取，内容长度: \(content.count)")
        print("🔍 [extractTextTagsWithIntervals] 内容预览（前500字符）: \(String(content.prefix(500)))")
        
        // 首先提取所有独立标签（不在 <text> 内的）
        // 格式：<bullet indent="1" />文本内容\n
        // 格式：<order indent="1" inputNumber="0" />文本内容\n
        // 格式：<input type="checkbox" indent="1" level="3" />文本内容\n
        // 格式：<hr />\n
        
        // 先提取独立的 bullet、order、checkbox、hr 标签和引用占位符
        let standalonePatterns: [(pattern: NSRegularExpression, type: String)] = [
            (try! NSRegularExpression(pattern: "<bullet[^>]*indent=\"(\\d+)\"[^>]*/>", options: []), "bullet"),
            (try! NSRegularExpression(pattern: "<order[^>]*indent=\"(\\d+)\"[^>]*inputNumber=\"(\\d+)\"[^>]*/>", options: []), "order"),
            (try! NSRegularExpression(pattern: "<input[^>]*type=\"checkbox\"[^>]*indent=\"(\\d+)\"[^>]*level=\"(\\d+)\"[^>]*/>", options: []), "checkbox"),
            (try! NSRegularExpression(pattern: "<hr[^>]*/>", options: []), "hr"),
            (try! NSRegularExpression(pattern: "🔄QUOTE_PLACEHOLDER_(\\d+)🔄", options: []), "quote")
        ]
        
        var allMatches: [(range: NSRange, type: String, indent: Int?, inputNumber: Int?, level: Int?)] = []
        
        for (pattern, type) in standalonePatterns {
            let matches = pattern.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
            for match in matches {
                var indent: Int? = nil
                var inputNumber: Int? = nil
                var level: Int? = nil
                
                if type == "bullet" && match.numberOfRanges >= 2,
                   let indentRange = Range(match.range(at: 1), in: content) {
                    indent = Int(String(content[indentRange]))
                } else if type == "order" && match.numberOfRanges >= 3,
                          let indentRange = Range(match.range(at: 1), in: content),
                          let inputNumberRange = Range(match.range(at: 2), in: content) {
                    indent = Int(String(content[indentRange]))
                    inputNumber = Int(String(content[inputNumberRange]))
                } else if type == "checkbox" && match.numberOfRanges >= 3,
                          let indentRange = Range(match.range(at: 1), in: content),
                          let levelRange = Range(match.range(at: 2), in: content) {
                    indent = Int(String(content[indentRange]))
                    level = Int(String(content[levelRange]))
                } else if type == "quote" && match.numberOfRanges >= 2 {
                    // 引用占位符，不需要额外参数
                }
                
                allMatches.append((match.range, type, indent, inputNumber, level))
            }
        }
        
        // 按位置排序
        allMatches.sort { $0.range.location < $1.range.location }
        
        // 提取 <text> 标签
        let textTagPattern = try! NSRegularExpression(pattern: "<text[^>]*>(.*?)</text>", options: [.dotMatchesLineSeparators])
        let textMatches = textTagPattern.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        print("🔍 [extractTextTagsWithIntervals] 找到 \(textMatches.count) 个 <text> 标签，\(allMatches.count) 个独立标签")
        
        // 合并所有匹配项（独立标签和 <text> 标签），按位置排序
        var allItems: [(range: NSRange, type: String, isTextTag: Bool, indent: Int?, inputNumber: Int?, level: Int?, content: String?)] = []
        
        // 添加独立标签
        for match in allMatches {
            // 对于引用占位符，不需要提取后面的文本，因为占位符本身就是完整的内容
            if match.type == "quote" {
                // 引用占位符格式：🔄QUOTE_PLACEHOLDER_0🔄
                // 直接使用占位符本身，不提取后面的文本
                let placeholderRange = Range(match.range, in: content)!
                let placeholder = String(content[placeholderRange])
                print("🔍 [extractTextTagsWithIntervals] 引用占位符: '\(placeholder)'")
                allItems.append((match.range, match.type, false, match.indent, match.inputNumber, match.level, placeholder))
                continue
            }
            
            // 提取标签后的文本（直到下一个标签或换行符）
            let tagEnd = match.range.location + match.range.length
            var textEnd = content.count
            
            // 查找下一个标签或换行符
            if tagEnd < content.count {
                let remainingStartIndex = content.index(content.startIndex, offsetBy: tagEnd)
                let remainingContent = String(content[remainingStartIndex...])
                
                // 先查找换行符
                if let newlineIndex = remainingContent.firstIndex(of: "\n") {
                    // 计算从 remainingStartIndex 到 newlineIndex 的距离
                    let newlineOffset = remainingContent.distance(from: remainingContent.startIndex, to: newlineIndex)
                    textEnd = tagEnd + newlineOffset
                    print("🔍 [extractTextTagsWithIntervals] 找到换行符，tagEnd=\(tagEnd), newlineOffset=\(newlineOffset), textEnd=\(textEnd)")
                } else {
                    // 如果没有换行符，检查是否有下一个标签
                    var nextTagLocation = content.count
                    for item in allMatches {
                        if item.range.location > tagEnd {
                            nextTagLocation = min(nextTagLocation, item.range.location)
                        }
                    }
                    for textMatch in textMatches {
                        if textMatch.range.location > tagEnd {
                            nextTagLocation = min(nextTagLocation, textMatch.range.location)
                        }
                    }
                    textEnd = nextTagLocation
                }
            }
            
            // 提取文本（去除前后空白，但保留中间内容）
            var text = ""
            if tagEnd < textEnd && textEnd <= content.count {
                let textStartIndex = content.index(content.startIndex, offsetBy: tagEnd)
                let textEndIndex = content.index(content.startIndex, offsetBy: textEnd)
                let rawText = String(content[textStartIndex..<textEndIndex])
                // 只去除前后的空白和换行，保留中间内容
                text = rawText.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t"))
                print("🔍 [extractTextTagsWithIntervals] 提取到文本: '\(text)' (原始: '\(rawText)')")
            }
            
            allItems.append((match.range, match.type, false, match.indent, match.inputNumber, match.level, text))
        }
        
        // 添加 <text> 标签
        for match in textMatches {
            var indent = 1
            if let fullRange = Range(match.range, in: content) {
                let fullTag = String(content[fullRange])
                if let indentMatch = try! NSRegularExpression(pattern: "indent=\"(\\d+)\"").firstMatch(in: fullTag, options: [], range: NSRange(fullTag.startIndex..., in: fullTag)),
                   indentMatch.numberOfRanges >= 2,
                   let indentRange = Range(indentMatch.range(at: 1), in: fullTag) {
                    indent = Int(String(fullTag[indentRange])) ?? 1
                }
            }
            
            var textContent = ""
            if match.numberOfRanges >= 2,
               let contentRange = Range(match.range(at: 1), in: content) {
                textContent = String(content[contentRange])
            }
            
            allItems.append((match.range, "text", true, indent, nil, nil, textContent))
        }
        
        // 按位置排序
        allItems.sort { $0.range.location < $1.range.location }
        
        // 转换为 TextSegment
        for item in allItems {
            if item.isTextTag {
                segments.append(.textTag(indent: item.indent ?? 1, content: item.content ?? ""))
            } else {
                switch item.type {
                case "bullet":
                    segments.append(.bullet(indent: item.indent ?? 1, text: item.content ?? ""))
                case "order":
                    segments.append(.order(indent: item.indent ?? 1, inputNumber: item.inputNumber ?? 0, text: item.content ?? ""))
                case "checkbox":
                    segments.append(.checkbox(indent: item.indent ?? 1, level: item.level ?? 0, text: item.content ?? ""))
                case "hr":
                    segments.append(.hr)
                case "quote":
                    // 提取引用索引
                    // 引用占位符格式：🔄QUOTE_PLACEHOLDER_0🔄
                    // 需要提取其中的数字索引
                    if let content = item.content {
                        if content.hasPrefix("🔄QUOTE_PLACEHOLDER_") && content.hasSuffix("🔄") {
                            // 提取数字索引
                            let indexString = content
                                .replacingOccurrences(of: "🔄QUOTE_PLACEHOLDER_", with: "")
                                .replacingOccurrences(of: "🔄", with: "")
                            print("🔍 [extractTextTagsWithIntervals] 提取引用索引: '\(indexString)' from '\(content)'")
                            segments.append(.quote(content: indexString))
                        } else {
                            // 如果不是占位符格式，可能是直接的内容（不应该发生）
                            print("⚠️ [extractTextTagsWithIntervals] 引用内容不是占位符格式: '\(content)'")
                            segments.append(.quote(content: content))
                        }
                    } else {
                        print("⚠️ [extractTextTagsWithIntervals] 引用内容为 nil")
                        segments.append(.quote(content: ""))
                    }
                default:
                    break
                }
            }
        }
        
        return segments
    }
    
    /// 提取所有 <text> 标签（保留用于兼容性）
    private static func extractTextTags(from content: String) -> [(indent: Int, content: String)] {
        let segments = extractTextTagsWithIntervals(from: content)
        return segments.compactMap { segment in
            if case .textTag(let indent, let content) = segment {
                return (indent, content)
            }
            return nil
        }
    }
    
    /// 解析 <text> 标签内容
    private static func parseTextTag(_ content: String, indent: Int) -> NSAttributedString? {
        print("🔍 [parseTextTag] 开始解析，indent=\(indent), 内容长度=\(content.count)")
        print("🔍 [parseTextTag] 内容: \(String(content.prefix(200)))")
        
        guard !content.isEmpty else {
            print("🔍 [parseTextTag] 内容为空，返回空段落")
            // 空段落
            let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
            return NSAttributedString(string: "", attributes: [
                .paragraphStyle: paragraphStyle,
                .foregroundColor: NSColor.labelColor
            ])
        }
        
        // 检查是否是特殊元素（复选框、列表等）
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<input") {
            return parseCheckboxTag(content, indent: indent)
        }
        
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<bullet") {
            return parseBulletTag(content, indent: indent)
        }
        
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<order") {
            return parseOrderTag(content, indent: indent)
        }
        
        // 检查是否是分割线（可能在 <text> 标签内）
        // 使用正则表达式更准确地检测 <hr /> 标签
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hrPattern = try! NSRegularExpression(pattern: "<hr[^>]*/?>", options: [])
        if let hrMatch = hrPattern.firstMatch(in: trimmedContent, options: [], range: NSRange(trimmedContent.startIndex..., in: trimmedContent)) {
            // 检查是否整个内容就是 <hr />（可能前后有空白）
            let hrRange = Range(hrMatch.range, in: trimmedContent)!
            let hrText = String(trimmedContent[hrRange])
            let beforeHR = String(trimmedContent[..<hrRange.lowerBound])
            let afterHR = String(trimmedContent[hrRange.upperBound...])
            
            // 如果 <hr /> 前后只有空白字符，说明这是独立的分割线
            if beforeHR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               afterHR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("🔍 [parseTextTag] 检测到分割线标签（在 <text> 标签内）")
                return parseHrTag()
            }
        }
        
        // 解析内联样式和文本内容
        // 先处理对齐标签（<center> 和 <right>），提取它们的内容
        var innerContent = content
        var alignment: NSTextAlignment = .left
        
        // 检查并移除对齐标签（使用正则表达式更准确）
        let centerPattern = try! NSRegularExpression(pattern: "<center>(.*?)</center>", options: [.dotMatchesLineSeparators])
        let rightPattern = try! NSRegularExpression(pattern: "<right>(.*?)</right>", options: [.dotMatchesLineSeparators])
        
        if let centerMatch = centerPattern.firstMatch(in: innerContent, options: [], range: NSRange(innerContent.startIndex..., in: innerContent)),
           centerMatch.numberOfRanges >= 2,
           let contentRange = Range(centerMatch.range(at: 1), in: innerContent) {
            alignment = .center
            innerContent = String(innerContent[contentRange])
            print("🔍 [parseTextTag] 检测到居中标签，提取内容: '\(innerContent)'")
        } else if let rightMatch = rightPattern.firstMatch(in: innerContent, options: [], range: NSRange(innerContent.startIndex..., in: innerContent)),
                  rightMatch.numberOfRanges >= 2,
                  let contentRange = Range(rightMatch.range(at: 1), in: innerContent) {
            alignment = .right
            innerContent = String(innerContent[contentRange])
            print("🔍 [parseTextTag] 检测到居右标签，提取内容: '\(innerContent)'")
        }
        
        // 先解码 HTML 实体
        innerContent = decodeHTMLEntities(innerContent)
        print("🔍 [parseTextTag] 解码后内容: \(String(innerContent.prefix(200)))")
        
        let result = NSMutableAttributedString()
        var currentIndex = innerContent.startIndex
        var styleStack: [StyleState] = []
        var currentStyle = StyleState(indent: indent)
        
        // 使用更高效的方式：先找到所有标签位置，然后按顺序处理
        var textBuffer = ""
        var tagCount = 0
        
        while currentIndex < innerContent.endIndex {
            if innerContent[currentIndex] == "<" {
                // 如果有累积的文本，先输出
                if !textBuffer.isEmpty {
                    appendText(textBuffer, to: result, style: currentStyle, indent: indent, alignment: alignment)
                    textBuffer = ""
                }
                
                // 解析标签
                if let tagEnd = innerContent[currentIndex...].firstIndex(of: ">") {
                    let tagContent = String(innerContent[innerContent.index(after: currentIndex)..<tagEnd])
                    
                    // 跳过对齐标签（已经处理过了）
                    if tagContent == "center" || tagContent == "right" || tagContent == "/center" || tagContent == "/right" {
                        currentIndex = innerContent.index(after: tagEnd)
                        continue
                    }
                    
                    // 处理开始标签
                    if !tagContent.hasPrefix("/") {
                        tagCount += 1
                        print("🔍 [parseTextTag] 遇到开始标签 #\(tagCount): <\(tagContent)>")
                        print("🔍 [parseTextTag] 当前样式: fontSize=\(currentStyle.fontSize), isBold=\(currentStyle.isBold), isItalic=\(currentStyle.isItalic)")
                        
                        // 特别关注斜体标签
                        if tagContent == "i" {
                            print("🔍 [parseTextTag] ========== 检测到斜体开始标签 <i> ==========")
                        }
                        
                        handleStartTag(tagContent, styleStack: &styleStack, currentStyle: &currentStyle)
                        print("🔍 [parseTextTag] 处理后样式: fontSize=\(currentStyle.fontSize), isBold=\(currentStyle.isBold), isItalic=\(currentStyle.isItalic)")
                        
                        if tagContent == "i" {
                            print("🔍 [parseTextTag] ========== 斜体开始标签处理完成 ==========")
                        }
                    } else {
                        let endTagName = String(tagContent.dropFirst())  // 移除 "/"
                        print("🔍 [parseTextTag] 遇到结束标签: </\(endTagName)>")
                        
                        // 特别关注斜体结束标签
                        if endTagName == "i" {
                            print("🔍 [parseTextTag] ========== 检测到斜体结束标签 </i> ==========")
                            print("🔍 [parseTextTag] 结束前样式: fontSize=\(currentStyle.fontSize), isBold=\(currentStyle.isBold), isItalic=\(currentStyle.isItalic)")
                        }
                        
                        handleEndTag(tagContent, styleStack: &styleStack, currentStyle: &currentStyle, baseIndent: indent)
                        print("🔍 [parseTextTag] 恢复后样式: fontSize=\(currentStyle.fontSize), isBold=\(currentStyle.isBold), isItalic=\(currentStyle.isItalic)")
                        
                        if endTagName == "i" {
                            print("🔍 [parseTextTag] ========== 斜体结束标签处理完成 ==========")
                        }
                    }
                    
                    currentIndex = innerContent.index(after: tagEnd)
                } else {
                    // 无效标签（没有找到 ">"），作为普通文本处理
                    textBuffer.append(innerContent[currentIndex])
                    currentIndex = innerContent.index(after: currentIndex)
                }
            } else {
                // 普通字符，累积到缓冲区
                textBuffer.append(innerContent[currentIndex])
                currentIndex = innerContent.index(after: currentIndex)
            }
        }
        
        // 输出剩余的文本
        if !textBuffer.isEmpty {
            print("🔍 [parseTextTag] 输出剩余文本缓冲区: '\(textBuffer)'")
            print("🔍 [parseTextTag] 输出时样式状态: fontSize=\(currentStyle.fontSize), isBold=\(currentStyle.isBold), isItalic=\(currentStyle.isItalic)")
            appendText(textBuffer, to: result, style: currentStyle, indent: indent, alignment: alignment)
            
            // 验证输出后的字体属性
            if result.length > 0 {
                let lastRange = NSRange(location: max(0, result.length - textBuffer.count), length: min(textBuffer.count, result.length))
                if lastRange.location < result.length {
                    let attrs = result.attributes(at: lastRange.location, effectiveRange: nil)
                    if let font = attrs[.font] as? NSFont {
                        let traits = font.fontDescriptor.symbolicTraits
                        let hasItalic = traits.contains(.italic)
                        print("🔍 [parseTextTag] 输出后字体验证: fontName=\(font.fontName), size=\(font.pointSize), hasItalic=\(hasItalic)")
                    }
                }
            }
        }
        
        print("🔍 [parseTextTag] 处理图片占位符前，结果长度: \(result.length)")
        // 处理图片占位符
        processImagePlaceholders(in: result)
        print("🔍 [parseTextTag] 处理图片占位符后，结果长度: \(result.length)")
        
        // 确保整个段落都应用正确的对齐方式
        if result.length > 0 {
            let fullRange = NSRange(location: 0, length: result.length)
            let paragraphStyle = createParagraphStyle(indent: indent, alignment: alignment)
            result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            
            // 检查最终结果的属性
            let attrs = result.attributes(at: 0, effectiveRange: nil)
            if let font = attrs[.font] as? NSFont {
                print("🔍 [parseTextTag] 最终第一个字符字体: size=\(font.pointSize), bold=\(font.fontDescriptor.symbolicTraits.contains(.bold)), italic=\(font.fontDescriptor.symbolicTraits.contains(.italic))")
            }
            if let paraStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
                print("🔍 [parseTextTag] 最终段落对齐: \(paraStyle.alignment == .left ? "left" : paraStyle.alignment == .center ? "center" : "right")")
            }
        }
        
        return result.length > 0 ? result : nil
    }
    
    /// 解析引用块
    /// 引用块内可能包含任何格式的内容：<text>、<bullet />、<order />、<hr />、<input type="checkbox" /> 等
    private static func parseQuoteBlock(_ content: String) -> NSAttributedString? {
        print("🔍 [parseQuoteBlock] 开始解析引用块，内容长度: \(content.count)")
        print("🔍 [parseQuoteBlock] 内容预览: \(String(content.prefix(200)))")
        
        let result = NSMutableAttributedString()
        
        // 使用 extractTextTagsWithIntervals 来提取引用块内的所有内容
        // 这样可以正确处理 <text>、<bullet />、<order />、<hr />、<input type="checkbox" /> 等所有格式
        let segments = extractTextTagsWithIntervals(from: content)
        print("🔍 [parseQuoteBlock] 找到 \(segments.count) 个段落（包括各种格式）")
        
        if segments.isEmpty {
            // 如果没有找到任何段落，尝试直接解析为纯文本
            print("🔍 [parseQuoteBlock] 没有找到段落，尝试直接解析为纯文本")
            if let textAttr = parseTextTag(content, indent: 1) {
                let paragraphStyle = createParagraphStyle(indent: 1, alignment: .left)
                paragraphStyle.firstLineHeadIndent = paragraphStyle.headIndent + 10
                paragraphStyle.headIndent = paragraphStyle.firstLineHeadIndent
                
                let mutableAttr = NSMutableAttributedString(attributedString: textAttr)
                mutableAttr.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: mutableAttr.length))
                result.append(mutableAttr)
            }
        } else {
            // 跟踪每个缩进级别的有序列表序号（用于自动递增）
            var orderCounters: [Int: Int] = [:]  // [indent: currentNumber]
            
            for (index, segment) in segments.enumerated() {
                var segmentAttr: NSAttributedString? = nil
                
                switch segment {
                case .textTag(let indent, let textContent):
                    print("🔍 [parseQuoteBlock] 处理 <text> 标签，indent=\(indent), content='\(textContent.prefix(50))'")
                    segmentAttr = parseTextTag(textContent, indent: indent)
                    
                case .bullet(let indent, let text):
                    print("🔍 [parseQuoteBlock] 处理 <bullet /> 标签，indent=\(indent), text='\(text)'")
                    segmentAttr = parseStandaloneBullet(indent: indent, text: text)
                    
                case .order(let indent, let inputNumber, let text):
                    print("🔍 [parseQuoteBlock] 处理 <order /> 标签，indent=\(indent), inputNumber=\(inputNumber), text='\(text)'")
                    // Auto-increment logic for ordered lists
                    let currentCounter = orderCounters[indent] ?? 0
                    let effectiveInputNumber: Int
                    if inputNumber == 0 && currentCounter == 0 {
                        effectiveInputNumber = 0
                        orderCounters[indent] = 1
                    } else if inputNumber > 0 {
                        effectiveInputNumber = inputNumber
                        orderCounters[indent] = inputNumber + 1
                    } else {
                        effectiveInputNumber = currentCounter
                        orderCounters[indent] = currentCounter + 1
                    }
                    segmentAttr = parseStandaloneOrder(indent: indent, inputNumber: effectiveInputNumber, text: text)
                    
                case .checkbox(let indent, let level, let text):
                    print("🔍 [parseQuoteBlock] 处理 <input type=\"checkbox\" /> 标签，indent=\(indent), level=\(level), text='\(text)'")
                    segmentAttr = parseStandaloneCheckbox(indent: indent, level: level, text: text)
                    
                case .hr:
                    print("🔍 [parseQuoteBlock] 处理 <hr /> 标签")
                    segmentAttr = parseHrTag()
                    
                case .quote:
                    // 引用块内不应该再有引用块，但为了安全起见，跳过
                    print("⚠️ [parseQuoteBlock] 警告：引用块内发现嵌套引用块，跳过")
                    continue
                }
                
                if let attr = segmentAttr {
                    // 为引用块内的所有内容添加特殊样式（左侧缩进效果）
                    let mutableAttr = NSMutableAttributedString(attributedString: attr)
                    
                    // 获取现有的段落样式
                    var paragraphStyle: NSMutableParagraphStyle
                    if let existingStyle = mutableAttr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                        paragraphStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
                    } else {
                        paragraphStyle = createParagraphStyle(indent: 1, alignment: .left)
                    }
                    
                    // 为引用块添加额外的左侧缩进（视觉上的引用效果）
                    paragraphStyle.firstLineHeadIndent = paragraphStyle.headIndent + 10
                    paragraphStyle.headIndent = paragraphStyle.firstLineHeadIndent
                    
                    mutableAttr.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: mutableAttr.length))
                    
                    result.append(mutableAttr)
                    
                    // 在段落之间添加换行（除了最后一个）
                    if index < segments.count - 1 {
                        result.append(NSAttributedString(string: "\n", attributes: newlineAttributes()))
                    }
                } else {
                    print("⚠️ [parseQuoteBlock] 警告：无法解析段落 #\(index)")
                }
            }
        }
        
        print("🔍 [parseQuoteBlock] 引用块解析完成，结果长度: \(result.length)")
        return result.length > 0 ? result : nil
    }
    
    /// 解析复选框标签
    private static func parseCheckboxTag(_ content: String, indent: Int) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        
        // 提取复选框后的文本
        let checkboxPattern = try! NSRegularExpression(pattern: "<input[^>]*type=\"checkbox\"[^>]*/>", options: [])
        if let match = checkboxPattern.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) {
            // 创建可交互的复选框附件
            let attachment = CheckboxTextAttachment(data: nil, ofType: nil)
            attachment.isChecked = false  // 默认未选中
            let checkboxAttr = NSAttributedString(attachment: attachment)
            result.append(checkboxAttr)
            
            // 添加空格
            let spaceAttr = NSAttributedString(string: " ", attributes: defaultAttributes())
            result.append(spaceAttr)
            
            // 提取复选框后的文本
            if match.range.location + match.range.length < content.count {
                let textAfterCheckbox = String(content[content.index(content.startIndex, offsetBy: match.range.location + match.range.length)...])
                if !textAfterCheckbox.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let textAttr = parseTextTag(textAfterCheckbox, indent: indent) {
                        result.append(textAttr)
                    }
                }
            }
        }
        
        // 应用段落样式
        let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        
        return result.length > 0 ? result : nil
    }
    
    /// 解析无序列表标签
    private static func parseBulletTag(_ content: String, indent: Int) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        
        // 提取列表项文本
        let bulletPattern = try! NSRegularExpression(pattern: "<bullet[^>]*/>", options: [])
        if let match = bulletPattern.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) {
            let textAfterBullet = String(content[content.index(content.startIndex, offsetBy: match.range.location + match.range.length)...])
            if !textAfterBullet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let textAttr = parseTextTag(textAfterBullet, indent: indent) {
                    // 在文本前添加项目符号
                    let bulletAttr = NSAttributedString(string: "• ", attributes: defaultAttributes())
                    result.append(bulletAttr)
                    result.append(textAttr)
                }
            }
        }
        
        let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        
        return result.length > 0 ? result : nil
    }
    
    /// 解析有序列表标签
    private static func parseOrderTag(_ content: String, indent: Int) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        
        // 提取序号和文本
        let orderPattern = try! NSRegularExpression(pattern: "<order[^>]*inputNumber=\"(\\d+)\"[^>]*/>", options: [])
        if let match = orderPattern.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
           match.numberOfRanges >= 2,
           let numberRange = Range(match.range(at: 1), in: content) {
            let inputNumber = Int(String(content[numberRange])) ?? 0
            let orderNumber = inputNumber + 1  // inputNumber 是 0-based，显示时 +1
            
            let textAfterOrder = String(content[content.index(content.startIndex, offsetBy: match.range.location + match.range.length)...])
            if !textAfterOrder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let textAttr = parseTextTag(textAfterOrder, indent: indent) {
                    // 在文本前添加序号
                    let orderAttr = NSAttributedString(string: "\(orderNumber). ", attributes: defaultAttributes())
                    result.append(orderAttr)
                    result.append(textAttr)
                }
            }
        }
        
        let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        
        return result.length > 0 ? result : nil
    }
    
    // MARK: - 独立标签解析（不在 <text> 内的）
    
    /// 解析独立无序列表（不在 <text> 标签内）
    private static func parseStandaloneBullet(indent: Int, text: String) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        
        print("🔍 [parseStandaloneBullet] 开始解析，indent=\(indent), text='\(text)'")
        
        // 添加项目符号
        let bulletAttr = NSAttributedString(string: "• ", attributes: defaultAttributes())
        result.append(bulletAttr)
        
        // 解析文本内容（可能包含内联样式）
        if !text.isEmpty {
            print("🔍 [parseStandaloneBullet] 文本不为空，长度=\(text.count)")
            // 对于独立标签后的文本，通常不包含 XML 标签，直接作为纯文本处理
            // 但如果包含样式标签（如 <b>、<i>），则尝试解析
            if text.contains("<") && text.contains(">") {
                // 可能包含样式标签，尝试解析
                print("🔍 [parseStandaloneBullet] 文本包含标签，尝试解析")
                if let textAttr = parseTextTag(text, indent: indent) {
                    print("🔍 [parseStandaloneBullet] 成功解析为富文本，长度: \(textAttr.length)")
                    result.append(textAttr)
                } else {
                    print("🔍 [parseStandaloneBullet] 解析失败，使用纯文本")
                    let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                    result.append(plainTextAttr)
                }
            } else {
                // 纯文本，直接添加
                print("🔍 [parseStandaloneBullet] 纯文本，直接添加: '\(text)'")
                let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                result.append(plainTextAttr)
            }
        } else {
            print("⚠️ [parseStandaloneBullet] 文本为空")
        }
        
        let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        
        print("🔍 [parseStandaloneBullet] 最终结果长度: \(result.length), 字符串: '\(result.string)'")
        return result.length > 0 ? result : nil
    }
    
    /// 解析独立有序列表（不在 <text> 标签内）
    private static func parseStandaloneOrder(indent: Int, inputNumber: Int, text: String) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        
        print("🔍 [parseStandaloneOrder] 开始解析，indent=\(indent), inputNumber=\(inputNumber), text='\(text)'")
        
        // 添加序号（inputNumber 是 0-based，显示时 +1）
        // 注意：如果 inputNumber 为 0，表示这是第一个，应该显示为 1
        let orderNumber = inputNumber + 1
        let orderAttr = NSAttributedString(string: "\(orderNumber). ", attributes: defaultAttributes())
        result.append(orderAttr)
        print("🔍 [parseStandaloneOrder] 添加序号: \(orderNumber)")
        
        // 解析文本内容（可能包含内联样式）
        if !text.isEmpty {
            print("🔍 [parseStandaloneOrder] 文本不为空，长度=\(text.count)")
            // 对于独立标签后的文本，通常不包含 XML 标签，直接作为纯文本处理
            // 但如果包含样式标签（如 <b>、<i>），则尝试解析
            if text.contains("<") && text.contains(">") {
                // 可能包含样式标签，尝试解析
                print("🔍 [parseStandaloneOrder] 文本包含标签，尝试解析")
                if let textAttr = parseTextTag(text, indent: indent) {
                    print("🔍 [parseStandaloneOrder] 成功解析为富文本，长度: \(textAttr.length)")
                    result.append(textAttr)
                } else {
                    print("🔍 [parseStandaloneOrder] 解析失败，使用纯文本")
                    let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                    result.append(plainTextAttr)
                }
            } else {
                // 纯文本，直接添加
                print("🔍 [parseStandaloneOrder] 纯文本，直接添加: '\(text)'")
                let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                result.append(plainTextAttr)
            }
        } else {
            print("⚠️ [parseStandaloneOrder] 文本为空")
        }
        
        let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        
        print("🔍 [parseStandaloneOrder] 最终结果长度: \(result.length), 字符串: '\(result.string)'")
        return result.length > 0 ? result : nil
    }
    
    /// 解析独立复选框（不在 <text> 标签内）
    private static func parseStandaloneCheckbox(indent: Int, level: Int, text: String) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        
        print("🔍 [parseStandaloneCheckbox] 开始解析，indent=\(indent), level=\(level), text='\(text)'")
        
        // 创建可交互的复选框附件
        print("🔍 [parseStandaloneCheckbox] 开始创建 CheckboxTextAttachment")
        let attachment = CheckboxTextAttachment(data: nil, ofType: nil)
        attachment.isChecked = false  // 默认未选中
        
        // 在 macOS 上，确保 attachmentCell 已设置
        #if macOS
        if attachment.attachmentCell == nil {
            attachment.attachmentCell = CheckboxAttachmentCell(checkbox: attachment)
            print("🔍 [parseStandaloneCheckbox] 手动设置 attachmentCell")
        }
        print("🔍 [parseStandaloneCheckbox] attachmentCell=\(attachment.attachmentCell != nil ? "存在" : "nil")")
        #endif
        
        print("🔍 [parseStandaloneCheckbox] CheckboxTextAttachment 创建完成，image=\(attachment.image != nil ? "存在" : "nil"), bounds=\(attachment.bounds)")
        
        let checkboxAttr = NSAttributedString(attachment: attachment)
        print("🔍 [parseStandaloneCheckbox] 创建 NSAttributedString(attachment)，长度: \(checkboxAttr.length)")
        
        // 验证附件是否正确添加
        var hasAttachmentInAttr = false
        checkboxAttr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: checkboxAttr.length), options: []) { (value, range, _) in
            if value != nil {
                hasAttachmentInAttr = true
                print("🔍 [parseStandaloneCheckbox] 验证：附件存在于位置 \(range.location)")
            }
        }
        print("🔍 [parseStandaloneCheckbox] 附件验证结果: \(hasAttachmentInAttr)")
        
        result.append(checkboxAttr)
        
        // 添加空格
        let spaceAttr = NSAttributedString(string: " ", attributes: defaultAttributes())
        result.append(spaceAttr)
        print("🔍 [parseStandaloneCheckbox] 添加可交互复选框图标和空格，当前长度: \(result.length)")
        
        // 解析文本内容（可能包含内联样式）
        if !text.isEmpty {
            print("🔍 [parseStandaloneCheckbox] 文本不为空，长度=\(text.count)")
            // 对于独立标签后的文本，通常不包含 XML 标签，直接作为纯文本处理
            // 但如果包含样式标签（如 <b>、<i>），则尝试解析
            if text.contains("<") && text.contains(">") {
                // 可能包含样式标签，尝试解析
                print("🔍 [parseStandaloneCheckbox] 文本包含标签，尝试解析")
                if let textAttr = parseTextTag(text, indent: indent) {
                    print("🔍 [parseStandaloneCheckbox] 成功解析为富文本，长度: \(textAttr.length)")
                    result.append(textAttr)
                } else {
                    print("🔍 [parseStandaloneCheckbox] 解析失败，使用纯文本")
                    let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                    result.append(plainTextAttr)
                }
            } else {
                // 纯文本，直接添加
                print("🔍 [parseStandaloneCheckbox] 纯文本，直接添加: '\(text)'")
                let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                result.append(plainTextAttr)
            }
        } else {
            print("⚠️ [parseStandaloneCheckbox] 文本为空")
        }
        
        let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        
        print("🔍 [parseStandaloneCheckbox] 最终结果长度: \(result.length), 字符串: '\(result.string)'")
        // 检查是否包含附件
        if result.length > 0 {
            var hasAttachment = false
            result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length), options: []) { (value, range, _) in
                if value != nil {
                    hasAttachment = true
                }
            }
            print("🔍 [parseStandaloneCheckbox] 是否包含附件: \(hasAttachment)")
        }
        
        return result.length > 0 ? result : nil
    }
    
    /// 解析分割线标签
    private static func parseHrTag() -> NSAttributedString? {
        print("🔍 [parseHrTag] 开始创建分割线")
        
        // 使用 NSTextAttachment 创建分割线，而不是使用多个字符
        // 创建一个简单的分割线图片
        let lineHeight: CGFloat = 1.0
        let lineWidth: CGFloat = 400.0  // 分割线宽度
        
        print("🔍 [parseHrTag] 分割线尺寸: width=\(lineWidth), height=\(lineHeight)")
        
        // 创建分割线图片 - 使用更可靠的方法
        let image = NSImage(size: NSSize(width: lineWidth, height: lineHeight))
        image.lockFocus()
        
        // 设置分隔符颜色（使用系统分隔符颜色，自动适配深色模式）
        let separatorColor = NSColor.separatorColor
        separatorColor.setFill()
        let rect = NSRect(x: 0, y: 0, width: lineWidth, height: lineHeight)
        rect.fill()
        
        image.unlockFocus()
        
        // 确保图片正确渲染
        image.isTemplate = false
        image.cacheMode = .never
        
        print("🔍 [parseHrTag] 分割线图片创建完成，size=\(image.size), isTemplate=\(image.isTemplate)")
        
        // 创建附件 - 确保图片正确设置
        let attachment = NSTextAttachment()
        attachment.image = image
        // 调整 bounds 以确保正确显示
        attachment.bounds = NSRect(x: 0, y: -3, width: lineWidth, height: lineHeight)
        
        // 在 macOS 上，需要设置 attachmentCell 以确保正确渲染
        #if macOS
        if let image = image {
            let cell = NSTextAttachmentCell(imageCell: image)
            attachment.attachmentCell = cell
            print("🔍 [parseHrTag] 设置 attachmentCell，image=存在")
        } else {
            print("⚠️ [parseHrTag] 无法设置 attachmentCell，因为 image 为 nil")
        }
        #endif
        
        print("🔍 [parseHrTag] 创建附件，bounds=\(attachment.bounds), image=\(attachment.image != nil ? "存在" : "nil"), attachmentCell=\(attachment.attachmentCell != nil ? "存在" : "nil")")
        
        // 创建段落样式，使分割线居中
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacingBefore = 8.0
        paragraphStyle.paragraphSpacing = 8.0
        
        let attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        attributedString.addAttributes(attrs, range: NSRange(location: 0, length: attributedString.length))
        
        // 重要：在创建 NSAttributedString 后，需要重新设置 attachmentCell
        // 因为 NSAttributedString(attachment:) 可能不会保留 attachmentCell
        #if macOS
        if let att = attributedString.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment {
            if att.attachmentCell == nil, let image = att.image {
                let cell = NSTextAttachmentCell(imageCell: image)
                att.attachmentCell = cell
                print("🔍 [parseHrTag] 在创建 NSAttributedString 后重新设置 attachmentCell")
            }
        }
        #endif
        
        print("🔍 [parseHrTag] 属性字符串创建完成，长度: \(attributedString.length)")
        
        // 验证附件是否正确添加
        var hasAttachment = false
        attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length), options: []) { (value, range, _) in
            if value != nil {
                hasAttachment = true
                if let att = value as? NSTextAttachment {
                    print("🔍 [parseHrTag] 附件验证: image=\(att.image != nil ? "存在" : "nil"), bounds=\(att.bounds), attachmentCell=\(att.attachmentCell != nil ? "存在" : "nil")")
                }
            }
        }
        print("🔍 [parseHrTag] 分割线创建完成，包含附件: \(hasAttachment), 长度: \(attributedString.length)")
        
        // 额外验证：检查字符串内容
        print("🔍 [parseHrTag] 最终字符串内容: '\(attributedString.string)'")
        print("🔍 [parseHrTag] 最终字符串长度: \(attributedString.string.count)")
        
        // 检查附件图片是否真的存在
        if let att = attributedString.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment {
            print("🔍 [parseHrTag] 附件详细信息:")
            print("  - image: \(att.image != nil ? "存在，size=\(att.image!.size)" : "nil")")
            print("  - bounds: \(att.bounds)")
            print("  - attachmentCell: \(att.attachmentCell != nil ? "存在" : "nil")")
        }
        
        return attributedString
    }
    
    
    /// 处理图片占位符
    private static func processImagePlaceholders(in result: NSMutableAttributedString) {
        let string = result.string
        let placeholderPattern = try! NSRegularExpression(pattern: "🖼️IMAGE_([^:]+)::([^🖼️]+)🖼️", options: [])
        let matches = placeholderPattern.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
        
        for match in matches.reversed() {
            if match.numberOfRanges >= 3,
               let fileIdRange = Range(match.range(at: 1), in: string),
               let fileTypeRange = Range(match.range(at: 2), in: string) {
                let fileId = String(string[fileIdRange])
                let fileType = String(string[fileTypeRange])
                
                // 从本地加载图片
                if let imageData = LocalStorageService.shared.loadImage(fileId: fileId, fileType: fileType),
                   let image = NSImage(data: imageData) {
                    // 使用 RichTextKit 的 RichTextImageAttachment 以确保在编辑器中正确显示
                    let uti = (fileType == "jpg" || fileType == "jpeg") ? "public.jpeg" : "public.png"
                    let attachment = RichTextImageAttachment(data: imageData, ofType: uti)
                    
                    // 设置图片大小
                    let maxWidth: CGFloat = 600
                    let imageSize = image.size
                    let aspectRatio = imageSize.height / imageSize.width
                    let displayWidth = min(maxWidth, imageSize.width)
                    let displayHeight = displayWidth * aspectRatio
                    attachment.bounds = NSRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
                    
                    // 在 macOS 上，确保设置 attachmentCell（RichTextImageAttachment 会自动处理，但为了保险起见）
                    #if macOS
                    if attachment.attachmentCell == nil, let attachmentImage = attachment.image {
                        let cell = NSTextAttachmentCell(imageCell: attachmentImage)
                        attachment.attachmentCell = cell
                        print("🔍 [processImagePlaceholders] 手动设置图片 attachmentCell，size=\(attachmentImage.size)")
                    }
                    #endif
                    
                    let imageAttr = NSAttributedString(attachment: attachment)
                    
                    // 重要：在创建 NSAttributedString 后，需要重新设置 attachmentCell
                    // 因为 NSAttributedString(attachment:) 可能不会保留 attachmentCell
                    #if macOS
                    if let mutableAttr = imageAttr.mutableCopy() as? NSMutableAttributedString,
                       let att = mutableAttr.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment {
                        if att.attachmentCell == nil, let attachmentImage = att.image {
                            let cell = NSTextAttachmentCell(imageCell: attachmentImage)
                            att.attachmentCell = cell
                            print("🔍 [processImagePlaceholders] 在创建 NSAttributedString 后重新设置 attachmentCell")
                        }
                        // 使用修复后的附件
                        result.replaceCharacters(in: match.range, with: mutableAttr)
                    } else {
                        result.replaceCharacters(in: match.range, with: imageAttr)
                    }
                    #else
                    result.replaceCharacters(in: match.range, with: imageAttr)
                    #endif
                    
                    print("🔍 [processImagePlaceholders] 替换图片占位符，fileId=\(fileId), size=(\(displayWidth), \(displayHeight))")
                        } else {
                    // 图片不存在，显示占位文本
                    let placeholderText = "[图片: \(fileId)]"
                    result.replaceCharacters(in: match.range, with: NSAttributedString(string: placeholderText, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
                }
            }
        }
    }
    
    // MARK: 样式状态管理
    
    /// 样式状态结构
    private struct StyleState {
        var isBold: Bool = false
        var isItalic: Bool = false
        var isUnderline: Bool = false
        var isStrikethrough: Bool = false
        var fontSize: CGFloat = baseFontSize
        var backgroundColor: NSColor? = nil
        var indent: Int = 1
        
        init(indent: Int = 1) {
            self.indent = indent
        }
    }
    
    /// 处理开始标签
    private static func handleStartTag(_ tagContent: String, styleStack: inout [StyleState], currentStyle: inout StyleState) {
        styleStack.append(currentStyle)
        
        switch tagContent {
        case "b":
            currentStyle.isBold = true
            print("  ✅ [handleStartTag] 应用加粗")
        case "i":
            print("  🔍 [handleStartTag] ========== 开始处理斜体标签 <i> ==========")
            print("  🔍 [handleStartTag] 处理前样式状态: isItalic=\(currentStyle.isItalic), isBold=\(currentStyle.isBold), fontSize=\(currentStyle.fontSize)")
            currentStyle.isItalic = true
            print("  ✅ [handleStartTag] 应用斜体，处理后样式状态: isItalic=\(currentStyle.isItalic)")
            print("  🔍 [handleStartTag] ========== 斜体标签处理完成 ==========")
        case "u":
            currentStyle.isUnderline = true
            print("  ✅ [handleStartTag] 应用下划线")
        case "delete":
            currentStyle.isStrikethrough = true
            print("  ✅ [handleStartTag] 应用删除线")
        case "size":
            currentStyle.fontSize = h1FontSize
            currentStyle.isBold = true
            print("  ✅ [handleStartTag] 应用一级标题: fontSize=\(h1FontSize), bold=true")
        case "mid-size":
            currentStyle.fontSize = h2FontSize
            currentStyle.isBold = true
            print("  ✅ [handleStartTag] 应用二级标题: fontSize=\(h2FontSize), bold=true")
        case "h3-size":
            currentStyle.fontSize = h3FontSize
            currentStyle.isBold = true
            print("  ✅ [handleStartTag] 应用三级标题: fontSize=\(h3FontSize), bold=true")
        default:
            if tagContent.hasPrefix("background") {
                // 解析背景色：background color="#9affe8af"
                if let colorRange = tagContent.range(of: "color=\"") {
                            let start = colorRange.upperBound
                    if let end = tagContent[start...].firstIndex(of: "\"") {
                        let hexString = String(tagContent[start..<end])
                        currentStyle.backgroundColor = NSColor(hex: hexString)
                        print("  ✅ [handleStartTag] 应用背景色: \(hexString)")
                    }
                }
            } else {
                print("  ⚠️ [handleStartTag] 未知标签: \(tagContent)")
            }
        }
    }
    
    /// 处理结束标签
    private static func handleEndTag(_ tagContent: String, styleStack: inout [StyleState], currentStyle: inout StyleState, baseIndent: Int) {
        if !styleStack.isEmpty {
            currentStyle = styleStack.removeLast()
            } else {
            // 重置为默认样式
            currentStyle = StyleState(indent: baseIndent)
        }
    }
    
    /// 追加文本到结果（批量处理，更高效）
    private static func appendText(_ text: String, to result: NSMutableAttributedString, style: StyleState, indent: Int, alignment: NSTextAlignment) {
        guard !text.isEmpty else { return }
        
        print("  📝 [appendText] 追加文本: '\(text.prefix(50))', 样式: fontSize=\(style.fontSize), isBold=\(style.isBold), isItalic=\(style.isItalic)")
        
        let paragraphStyle = createParagraphStyle(indent: indent, alignment: alignment)
        
        var attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
        
        // 字体
        var font = NSFont.systemFont(ofSize: style.fontSize)  // 默认字体
        
        // 根据样式创建字体
        if style.isBold && style.isItalic {
            // 同时包含加粗和斜体
            if let boldItalicFont = NSFont(name: "Helvetica-BoldOblique", size: style.fontSize) {
                font = boldItalicFont
            } else if let boldItalicFont = NSFont(name: ".SFNS-BoldItalic", size: style.fontSize) {
                font = boldItalicFont
            } else {
                // 回退：先创建加粗字体，再添加斜体
                var fontDescriptor = NSFont.systemFont(ofSize: style.fontSize).fontDescriptor
                fontDescriptor = fontDescriptor.withSymbolicTraits([.bold, .italic])
                font = NSFont(descriptor: fontDescriptor, size: style.fontSize) ?? NSFont.boldSystemFont(ofSize: style.fontSize)
            }
            print("  ✅ [appendText] 创建加粗斜体字体: size=\(font.pointSize)")
        } else if style.isBold {
            // 只有加粗
            font = NSFont.boldSystemFont(ofSize: style.fontSize)
            print("  ✅ [appendText] 创建加粗字体: size=\(font.pointSize)")
        } else if style.isItalic {
            // 只有斜体 - 使用最可靠的方法创建斜体字体
            print("  🔍 [appendText] ========== 开始创建斜体字体 ==========")
            print("  🔍 [appendText] 样式状态: isItalic=\(style.isItalic), fontSize=\(style.fontSize)")
            
            let systemFont = NSFont.systemFont(ofSize: style.fontSize)
            print("  🔍 [appendText] 系统字体: \(systemFont.fontName), size=\(systemFont.pointSize)")
            var italicFontCreated = false
            
            // 方法1：使用 fontDescriptor.withSymbolicTraits（最可靠的方法）
            print("  🔍 [appendText] 方法1: 尝试使用 fontDescriptor.withSymbolicTraits")
            var fontDescriptor = systemFont.fontDescriptor
            var traits = fontDescriptor.symbolicTraits
            print("  🔍 [appendText] 原始 traits: \(traits)")
            traits.insert(.italic)
            print("  🔍 [appendText] 插入斜体后的 traits: \(traits)")
            fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
            
            if let italicFont = NSFont(descriptor: fontDescriptor, size: style.fontSize) {
                let actualTraits = italicFont.fontDescriptor.symbolicTraits
                let hasItalicTrait = actualTraits.contains(.italic)
                print("  🔍 [appendText] 方法1结果: 字体=\(italicFont.fontName), size=\(italicFont.pointSize), 包含斜体特性=\(hasItalicTrait)")
                if hasItalicTrait {
                    font = italicFont
                    italicFontCreated = true
                    print("  ✅ [appendText] 方法1成功: 使用 fontDescriptor 创建斜体字体成功")
                } else {
                    print("  ⚠️ [appendText] 方法1失败: 字体创建成功但未包含斜体特性")
                }
            } else {
                print("  ⚠️ [appendText] 方法1失败: 无法创建字体")
            }
            
            // 如果方法1失败或斜体特性未应用，尝试方法2
            if !italicFontCreated {
                print("  🔍 [appendText] 方法2: 尝试使用系统斜体字体名称")
                // 方法2：尝试使用系统斜体字体名称
                let italicFontNames = [
                    ".SFNS-RegularItalic",
                    "HelveticaNeue-Italic",
                    "Helvetica-Oblique",
                    "Arial-ItalicMT",
                    "TimesNewRomanPS-ItalicMT"
                ]
                
                for fontName in italicFontNames {
                    print("  🔍 [appendText] 尝试字体名称: \(fontName)")
                    if let italicFont = NSFont(name: fontName, size: style.fontSize) {
                        let actualTraits = italicFont.fontDescriptor.symbolicTraits
                        let hasItalicTrait = actualTraits.contains(.italic)
                        print("  🔍 [appendText] 字体 \(fontName) 创建成功，包含斜体特性=\(hasItalicTrait)")
                        if hasItalicTrait {
                            font = italicFont
                            italicFontCreated = true
                            print("  ✅ [appendText] 方法2成功: 使用系统斜体字体 \(fontName)")
                            break
                        }
                    } else {
                        print("  ⚠️ [appendText] 字体 \(fontName) 创建失败")
                    }
                }
            }
            
            // 如果方法2也失败，尝试方法3
            if !italicFontCreated {
                print("  🔍 [appendText] 方法3: 尝试使用 NSFontManager")
                // 方法3：使用 NSFontManager（如果可用）
                let fontManager = NSFontManager.shared
                let convertedFont = fontManager.convert(systemFont, toHaveTrait: NSFontTraitMask.italicFontMask)
                if convertedFont != systemFont {
                    let actualTraits = convertedFont.fontDescriptor.symbolicTraits
                    let hasItalicTrait = actualTraits.contains(.italic)
                    print("  🔍 [appendText] NSFontManager 转换结果: 字体=\(convertedFont.fontName), 包含斜体特性=\(hasItalicTrait)")
                    if hasItalicTrait {
                        font = convertedFont
                        italicFontCreated = true
                        print("  ✅ [appendText] 方法3成功: 使用 NSFontManager 创建斜体字体成功")
                    } else {
                        print("  ⚠️ [appendText] 方法3失败: 转换后字体未包含斜体特性")
                    }
                } else {
                    print("  ⚠️ [appendText] 方法3失败: NSFontManager 转换未改变字体")
                }
            }
            
            // 如果方法3也失败，尝试方法4：使用 NSAffineTransform 应用斜体效果
            if !italicFontCreated {
                print("  🔍 [appendText] 方法4: 尝试使用 NSAffineTransform")
                // 方法4：使用 NSAffineTransform 创建斜体效果（作为最后手段）
                var fontDescriptor = systemFont.fontDescriptor
                let italicTransform = AffineTransform(m11: 1.0, m12: 0.0, m21: -0.2, m22: 1.0, tX: 0.0, tY: 0.0)
                print("  🔍 [appendText] 创建斜体变换矩阵: m11=1.0, m12=0.0, m21=-0.2, m22=1.0")
                fontDescriptor = fontDescriptor.withMatrix(italicTransform)
                
                if let transformedFont = NSFont(descriptor: fontDescriptor, size: style.fontSize) {
                    font = transformedFont
                    italicFontCreated = true
                    print("  ✅ [appendText] 方法4成功: 使用 NSAffineTransform 创建斜体效果")
                } else {
                    print("  ⚠️ [appendText] 方法4失败: 无法创建变换后的字体")
                }
            }
            
            // 如果所有方法都失败，使用系统字体
            if !italicFontCreated {
                font = systemFont
                print("  ⚠️ [appendText] 警告：所有方法都无法创建真正的斜体字体，使用系统字体")
            }
            
            // 最终验证斜体是否成功应用
            let finalTraits = font.fontDescriptor.symbolicTraits
            let hasItalic = finalTraits.contains(.italic)
            print("  🔍 [appendText] 最终斜体字体验证:")
            print("    - 字体名称: \(font.fontName)")
            print("    - 字体大小: \(font.pointSize)")
            print("    - 实际包含斜体特性: \(hasItalic)")
            print("    - 期望斜体: \(style.isItalic)")
            print("    - 字体 traits: \(finalTraits)")
            
            // 如果字体本身不支持斜体，但我们需要斜体效果，使用 NSAffineTransform 作为属性
            if !hasItalic && style.isItalic {
                print("  🔍 [appendText] 字体不支持斜体特性，尝试通过变换矩阵应用斜体效果")
                // 创建斜体变换矩阵
                let italicTransform = AffineTransform(m11: 1.0, m12: 0.0, m21: -0.2, m22: 1.0, tX: 0.0, tY: 0.0)
                // 通过字体描述符应用变换
                var fontDescriptor = font.fontDescriptor
                fontDescriptor = fontDescriptor.withMatrix(italicTransform)
                if let italicFont = NSFont(descriptor: fontDescriptor, size: style.fontSize) {
                    font = italicFont
                    print("  ✅ [appendText] 通过变换矩阵应用斜体效果成功")
                } else {
                    print("  ⚠️ [appendText] 通过变换矩阵应用斜体效果失败")
                }
            }
            print("  🔍 [appendText] ========== 斜体字体创建完成 ==========")
        } else {
            // 普通字体
            font = NSFont.systemFont(ofSize: style.fontSize)
            print("  📝 [appendText] 使用普通字体: size=\(font.pointSize)")
        }
        
        // 验证字体特性
        let actualTraits = font.fontDescriptor.symbolicTraits
        let hasBold = actualTraits.contains(.bold)
        let hasItalic = actualTraits.contains(.italic)
        print("  🔍 [appendText] 字体实际特性: bold=\(hasBold), italic=\(hasItalic), 期望: bold=\(style.isBold), italic=\(style.isItalic)")
        
        attrs[.font] = font
        
        // 应用斜体效果：使用 obliqueness 属性确保斜体一定会渲染
        // 这是 macOS 上最可靠的斜体渲染方法，即使字体本身包含斜体特性也设置
        // obliqueness 值通常在 -0.1 到 -0.3 之间，-0.2 是常见的斜体倾斜度
        if style.isItalic {
            attrs[.obliqueness] = -0.2
            print("  ✅ [appendText] 已设置 obliqueness = -0.2 来应用斜体效果（字体包含斜体特性: \(hasItalic)）")
        }
        
        // 背景色
        if let bgColor = style.backgroundColor {
            attrs[.backgroundColor] = bgColor
        }
        
        // 下划线
        if style.isUnderline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        
        // 删除线
        if style.isStrikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        
        result.append(NSAttributedString(string: text, attributes: attrs))
    }
    
    /// 解码 HTML 实体
    private static func decodeHTMLEntities(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
    
    // MARK: XML 生成辅助方法
    
    /// 转换段落为 XML
    private static func convertParagraphToXML(_ paragraph: NSAttributedString) -> String {
        guard paragraph.length > 0 else {
            return "<text indent=\"1\"></text>"
        }
        
        // 检查是否是特殊元素
        let paragraphString = paragraph.string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 分割线：优先检查 NSTextAttachment（分割线是通过图片附件创建的）
        // 检查段落是否只包含附件（分割线通常只包含一个附件，没有其他文本）
        if paragraph.length == 1 {
            if let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
               let image = attachment.image {
                // 分割线的特征：宽度约为 400，高度约为 1
                let imageWidth = image.size.width
                let imageHeight = image.size.height
                let isHorizontalLine = imageWidth >= 300 && imageWidth <= 500 && imageHeight >= 0.5 && imageHeight <= 2.0
                
                if isHorizontalLine {
                    print("🔍 [convertParagraphToXML] 检测到分割线（通过 NSTextAttachment，宽度=\(imageWidth), 高度=\(imageHeight)），转换为 <hr />")
                    return "<hr />"
                }
            }
        }
        
        // 如果段落字符串只包含附件占位符（\u{FFFC}），也检查是否是分割线
        if paragraphString == "\u{FFFC}" || paragraphString.isEmpty {
            if let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
               let image = attachment.image {
                let imageWidth = image.size.width
                let imageHeight = image.size.height
                let isHorizontalLine = imageWidth >= 300 && imageWidth <= 500 && imageHeight >= 0.5 && imageHeight <= 2.0
                
                if isHorizontalLine {
                    print("🔍 [convertParagraphToXML] 检测到分割线（通过附件占位符），转换为 <hr />")
                    return "<hr />"
                }
            }
        }
        
        // 复选框
        if let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
           let image = attachment.image,
           image.size.width <= 20 && image.size.width > 0 {
            return convertCheckboxToXML(paragraph)
        }
        
        // 无序列表
        if paragraphString.hasPrefix("• ") {
            return convertBulletToXML(paragraph)
        }
        
        // 有序列表
        if let match = try? NSRegularExpression(pattern: "^\\d+\\.\\s+(.+)").firstMatch(in: paragraphString, options: [], range: NSRange(paragraphString.startIndex..., in: paragraphString)) {
            return convertOrderToXML(paragraph, match: match)
        }
        
        // 分割线：检查是否包含足够多的 "─" 字符（至少30个），且主要是分割线字符
        let dashCount = paragraphString.filter { $0 == "─" }.count
        if dashCount >= 30 && paragraphString.trimmingCharacters(in: .whitespacesAndNewlines).allSatisfy({ $0 == "─" || $0 == " " || $0 == "\n" }) {
            print("🔍 [convertParagraphToXML] 检测到分割线（通过字符），转换为 <hr />")
            return "<hr />"
        }
        
        // 普通段落
        return convertNormalParagraphToXML(paragraph)
    }
    
    /// 转换普通段落为 XML
    private static func convertNormalParagraphToXML(_ paragraph: NSAttributedString) -> String {
        let fullRange = NSRange(location: 0, length: paragraph.length)
        
        // 获取段落样式
        var indent = 1
        var alignment: NSTextAlignment = .left
        
        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            alignment = paragraphStyle.alignment
            indent = max(1, Int(paragraphStyle.headIndent / indentUnit) + 1)
        }
        
        var innerXML = NSMutableString()
        
        paragraph.enumerateAttributes(in: fullRange, options: []) { (attrs, range, _) in
            let substring = paragraph.attributedSubstring(from: range).string
            var currentText = escapeXML(substring)
            
            // 检查字体样式
            if let font = attrs[.font] as? NSFont {
                    var needsBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                    var needsItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                    
                // 标题样式
                if font.pointSize >= h1FontSize {
                        currentText = "<size>\(currentText)</size>"
                    needsBold = false
                } else if font.pointSize >= h2FontSize {
                        currentText = "<mid-size>\(currentText)</mid-size>"
                    needsBold = false
                } else if font.pointSize >= h3FontSize {
                        currentText = "<h3-size>\(currentText)</h3-size>"
                    needsBold = false
                    }

                    if needsBold {
                        currentText = "<b>\(currentText)</b>"
                    }
                    if needsItalic {
                        currentText = "<i>\(currentText)</i>"
                    }
                }
                
            // 下划线
            if let underlineStyle = attrs[.underlineStyle] as? Int, underlineStyle != 0 {
                    currentText = "<u>\(currentText)</u>"
                }
                
            // 删除线
            if let strikethroughStyle = attrs[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
                    currentText = "<delete>\(currentText)</delete>"
                }

            // 背景色
            if let bgColor = attrs[.backgroundColor] as? NSColor,
               let hexColor = bgColor.toHex() {
                        currentText = "<background color=\"#\(hexColor)\">\(currentText)</background>"
                    }
            
            innerXML.append(currentText)
        }
        
        // 对齐方式
        var finalText = innerXML as String
        if alignment == .center {
            finalText = "<center>\(finalText)</center>"
        } else if alignment == .right {
            finalText = "<right>\(finalText)</right>"
        }
        
        return "<text indent=\"\(indent)\">\(finalText)</text>"
    }
    
    /// 转换复选框为 XML
    private static func convertCheckboxToXML(_ paragraph: NSAttributedString) -> String {
        var indent = 1
        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            indent = max(1, Int(paragraphStyle.headIndent / indentUnit) + 1)
        }
        
        // 提取复选框后的文本
        let checkboxXML = "<input type=\"checkbox\" indent=\"\(indent)\" level=\"3\" />"
        
        // 检查是否有文本内容
        let string = paragraph.string
        if string.count > 1 {
            // 跳过第一个字符（复选框图标），提取剩余文本
            let textRange = NSRange(location: 1, length: paragraph.length - 1)
            if textRange.location < paragraph.length {
                let textAttr = paragraph.attributedSubstring(from: textRange)
                let textXML = convertTextToXML(textAttr)
                return "<text indent=\"\(indent)\">\(checkboxXML)\(textXML)</text>"
            }
        }
        
        return "<text indent=\"\(indent)\">\(checkboxXML)</text>"
    }
    
    /// 转换无序列表为 XML
    private static func convertBulletToXML(_ paragraph: NSAttributedString) -> String {
        var indent = 1
        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            indent = max(1, Int(paragraphStyle.headIndent / indentUnit) + 1)
        }
        
        let string = paragraph.string
        if string.hasPrefix("• ") {
            let textRange = NSRange(location: 2, length: paragraph.length - 2)
            if textRange.location < paragraph.length {
                let textAttr = paragraph.attributedSubstring(from: textRange)
                let textXML = convertTextToXML(textAttr)
                return "<text indent=\"\(indent)\"><bullet indent=\"\(indent)\" />\(textXML)</text>"
            }
        }
        
        return "<text indent=\"\(indent)\"><bullet indent=\"\(indent)\" /></text>"
    }
    
    /// 转换有序列表为 XML
    private static func convertOrderToXML(_ paragraph: NSAttributedString, match: NSTextCheckingResult) -> String {
        var indent = 1
        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            indent = max(1, Int(paragraphStyle.headIndent / indentUnit) + 1)
        }
        
        let string = paragraph.string
        if match.numberOfRanges >= 2,
           let numberRange = Range(match.range, in: string) {
            let numberText = String(string[numberRange])
            if let orderNumber = Int(numberText.replacingOccurrences(of: ". ", with: "")) {
                let inputNumber = max(0, orderNumber - 1)  // 转换为 0-based
                
                if match.numberOfRanges >= 2,
                   let textRange = Range(match.range(at: 1), in: string) {
                    let textStart = string.distance(from: string.startIndex, to: textRange.lowerBound)
                    let textAttrRange = NSRange(location: textStart, length: paragraph.length - textStart)
                    if textAttrRange.location < paragraph.length {
                        let textAttr = paragraph.attributedSubstring(from: textAttrRange)
                        let textXML = convertTextToXML(textAttr)
                        return "<text indent=\"\(indent)\"><order indent=\"\(indent)\" inputNumber=\"\(inputNumber)\" />\(textXML)</text>"
                    }
                }
            }
        }
        
        return "<text indent=\"\(indent)\"><order indent=\"\(indent)\" inputNumber=\"0\" /></text>"
    }
    
    /// 转换文本内容为 XML（不包含 <text> 标签）
    private static func convertTextToXML(_ attributedString: NSAttributedString) -> String {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        var innerXML = NSMutableString()
        
        attributedString.enumerateAttributes(in: fullRange, options: []) { (attrs, range, _) in
            let substring = attributedString.attributedSubstring(from: range).string
            var currentText = escapeXML(substring)

            // 检查字体样式
            if let font = attrs[.font] as? NSFont {
                var needsBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                var needsItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                
                // 标题样式
                if font.pointSize >= h1FontSize {
                    currentText = "<size>\(currentText)</size>"
                    needsBold = false
                } else if font.pointSize >= h2FontSize {
                    currentText = "<mid-size>\(currentText)</mid-size>"
                    needsBold = false
                } else if font.pointSize >= h3FontSize {
                    currentText = "<h3-size>\(currentText)</h3-size>"
                    needsBold = false
                }

                if needsBold {
                    currentText = "<b>\(currentText)</b>"
                }
                if needsItalic {
                    currentText = "<i>\(currentText)</i>"
                }
            }
            
            // 下划线
            if let underlineStyle = attrs[.underlineStyle] as? Int, underlineStyle != 0 {
                currentText = "<u>\(currentText)</u>"
            }
            
            // 删除线
            if let strikethroughStyle = attrs[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
                currentText = "<delete>\(currentText)</delete>"
            }

            // 背景色
            if let bgColor = attrs[.backgroundColor] as? NSColor,
               let hexColor = bgColor.toHex() {
                    currentText = "<background color=\"#\(hexColor)\">\(currentText)</background>"
                }
            
            innerXML.append(currentText)
        }
        
        return innerXML as String
    }
    
    // MARK: 工具方法
    
    /// 创建段落样式
    private static func createParagraphStyle(indent: Int, alignment: NSTextAlignment) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.alignment = alignment
        style.headIndent = CGFloat(indent - 1) * indentUnit
        style.firstLineHeadIndent = style.headIndent
        return style
    }
    
    /// 默认属性
    private static func defaultAttributes() -> [NSAttributedString.Key: Any] {
        return [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: baseFontSize),
            .paragraphStyle: createParagraphStyle(indent: 1, alignment: .left)
        ]
    }
    
    /// 换行符属性（不包含段落样式，避免缩进样式泄漏到下一个段落）
    private static func newlineAttributes() -> [NSAttributedString.Key: Any] {
        return [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: baseFontSize)
            // 注意：不包含 .paragraphStyle，让下一个段落使用自己的样式
        ]
    }
    
    /// 转义 XML 特殊字符
    private static func escapeXML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
                   .replacingOccurrences(of: "<", with: "&lt;")
                   .replacingOccurrences(of: ">", with: "&gt;")
                   .replacingOccurrences(of: "\"", with: "&quot;")
                   .replacingOccurrences(of: "'", with: "&apos;")
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

