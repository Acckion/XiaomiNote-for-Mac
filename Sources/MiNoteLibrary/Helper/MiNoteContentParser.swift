import Foundation
import AppKit
import CoreGraphics
import RichTextKit
import UniformTypeIdentifiers

// MARK: - CheckboxTextAttachment

/// 可交互的复选框附件
/// 使用自定义的 NSTextAttachmentCell 来实现可点击的复选框
class CheckboxTextAttachment: NSTextAttachment {
    var isChecked: Bool = false {
        didSet {
            updateImage()
        }
    }
    
    // MARK: - NSSecureCoding 支持
    /// 必须实现 supportsSecureCoding 以支持安全编码
    public override class var supportsSecureCoding: Bool {
        return true
    }
    
    override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        setupCheckbox()
    }
    
    required init?(coder: NSCoder) {
        // 先调用父类初始化
        super.init(coder: coder)
        
        // 然后解码自定义属性
        if coder.containsValue(forKey: "isChecked") {
            self.isChecked = coder.decodeBool(forKey: "isChecked")
        }
        
        setupCheckbox()
    }
    
    /// 编码方法（用于存档）
    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(isChecked, forKey: "isChecked")
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

// MARK: - HorizontalRuleAttachmentCell

#if macOS
/// 分割线附件单元格，用于绘制填满整个宽度的分割线
class HorizontalRuleAttachmentCell: NSTextAttachmentCell {
    
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // 绘制分割线，填满整个 cellFrame 宽度
        // 根据外观模式选择颜色，确保在深色和浅色模式下都有良好的可见性
        var separatorColor: NSColor
        
        // 尝试获取当前外观模式
        var appearance: NSAppearance?
        if let controlView = controlView {
            appearance = controlView.effectiveAppearance
            if appearance == nil, let window = controlView.window {
                appearance = window.effectiveAppearance
            }
        }
        if appearance == nil {
            appearance = NSAppearance.current
        }
        
        if let appearance = appearance,
           appearance.name == .darkAqua || appearance.name == .vibrantDark {
            // 深色模式：使用白色（用户要求）
            separatorColor = NSColor.white
        } else {
            // 浅色模式：使用系统分隔符颜色
            separatorColor = NSColor.separatorColor
        }
        
        separatorColor.setFill()
        
        // 创建一个填满宽度的矩形，高度为1
        // 使用 cellFrame 的宽度，确保填满整个可用区域
        let lineRect = NSRect(
            x: cellFrame.origin.x,
            y: cellFrame.midY - 0.5,  // 垂直居中
            width: cellFrame.width,   // 使用 cellFrame 的宽度，由 cellFrame(for:...) 计算
            height: 1.0
        )
        lineRect.fill()
    }
    
    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        // 计算可用宽度 - 使用行片段的宽度，这样可以填满整个可用区域
        // lineFrag 已经是文本容器提供的可用宽度，直接使用它
        var availableWidth = lineFrag.width
        
        // 尝试获取 textView 的实际宽度（如果可用）
        if let textView = textContainer.layoutManager?.firstTextView {
            let textViewWidth = textView.bounds.width
            // 减去左右内边距
            let padding = textContainer.lineFragmentPadding * 2
            let actualWidth = textViewWidth - padding
            
            // 如果 textView 的宽度可用，且大于 lineFrag 宽度，使用 textView 宽度
            if actualWidth > 0 && actualWidth > lineFrag.width {
                availableWidth = actualWidth
            }
        } else {
            // 如果无法获取 textView，尝试使用容器宽度
            let containerWidth = textContainer.containerSize.width
            if containerWidth < CGFloat.greatestFiniteMagnitude && containerWidth > lineFrag.width {
                let padding = textContainer.lineFragmentPadding * 2
                availableWidth = max(containerWidth - padding, lineFrag.width)
            }
        }
        
        // 确保宽度至少为行片段的宽度
        availableWidth = max(availableWidth, lineFrag.width)
        
        // 返回一个矩形，宽度填满可用空间，高度为1
        let rect = NSRect(
            x: lineFrag.origin.x,
            y: lineFrag.midY - 0.5,
            width: availableWidth,  // 使用计算出的可用宽度
            height: 1.0
        )
        
        return rect
    }
    
    override var cellSize: NSSize {
        // 返回一个非常宽的尺寸，让系统自动调整到容器宽度
        // 实际的绘制宽度由 draw 方法中的 cellFrame 决定
        return NSSize(width: 10000, height: 1.0)
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
        guard !xmlContent.isEmpty else {
            return NSAttributedString(string: "", attributes: defaultAttributes())
        }
        
        // 移除 <new-format/> 标签
        var cleanedContent = xmlContent.replacingOccurrences(of: "<new-format/>", with: "")
        
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
        
        // 解析所有 <text> 标签，同时检查标签之间的内容（可能包含 <hr /> 或图片占位符）
        // 使用更智能的方式：提取 <text> 标签及其之间的内容（包括图片占位符）
        let textTagsWithIntervals = extractTextTagsWithIntervals(from: processedContent)
        
        // 跟踪每个缩进级别的有序列表序号（用于自动递增）
        var orderCounters: [Int: Int] = [:]  // [indent: currentNumber]
        
        for (index, item) in textTagsWithIntervals.enumerated() {
            switch item {
            case .textTag(let indent, let content):
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
                }
                
            case .hr:
                if let hrAttr = parseHrTag() {
                    // 分割线附件本身已经是一个段落（包含paragraphStyle），不需要前后都添加换行符
                    // 只在分割线不是第一个元素时，在前面添加换行符
                    if index > 0 {
                        let newlineAttrs: [NSAttributedString.Key: Any] = [
                            .foregroundColor: NSColor.labelColor,
                            .font: NSFont.systemFont(ofSize: baseFontSize)
                        ]
                        result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                    }
                    result.append(hrAttr)
                    // 只在分割线不是最后一个元素时，在后面添加换行符
                    if index < textTagsWithIntervals.count - 1 {
                        let newlineAttrs: [NSAttributedString.Key: Any] = [
                            .foregroundColor: NSColor.labelColor,
                            .font: NSFont.systemFont(ofSize: baseFontSize)
                        ]
                        result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                    }
                }
            case .bullet(let indent, let text):
                if let bulletAttr = parseStandaloneBullet(indent: indent, text: text) {
                    result.append(bulletAttr)
                    if index < textTagsWithIntervals.count - 1 {
                        result.append(NSAttributedString(string: "\n", attributes: newlineAttributes()))
                    }
                }
            case .order(let indent, let inputNumber, let text):
                // 小米笔记的有序列表规则：
                // - 连续多行的有序列表，序号自动递增
                // - 第一行的inputNumber是实际值，后续行的inputNumber应该都是0
                // - 例如：inputNumber为0,0,0,0，渲染为1,2,3,4
                // - 例如：100,0,0,0渲染为100,101,102,103
                
                // 检查是否是连续的有序列表（前一个segment也是同缩进级别的order）
                let isFirstInSequence: Bool
                if index > 0 {
                    let prevItem = textTagsWithIntervals[index - 1]
                    if case .order(let prevIndent, _, _) = prevItem, prevIndent == indent {
                        isFirstInSequence = false  // 前一个也是同缩进的有序列表，说明这是连续的
                    } else {
                        isFirstInSequence = true  // 前一个不是有序列表或不同缩进，说明这是新序列的开始
                        // 重置该缩进级别的计数器
                        orderCounters[indent] = nil
                    }
                } else {
                    isFirstInSequence = true
                }
                
                let effectiveInputNumber: Int
                if isFirstInSequence {
                    // 这是序列的第一项，使用XML中的inputNumber
                    effectiveInputNumber = inputNumber
                    // 保存第一个inputNumber，用于后续项计算显示序号
                    orderCounters[indent] = inputNumber
                    // 初始化序号偏移计数器为0（第一项使用inputNumber，从第二项开始递增）
                    orderCounters[indent + 1000] = 0
                } else {
                    // 这是连续的有序列表项，inputNumber应该为0
                    // 但我们需要根据第一个inputNumber来计算当前应该显示的序号
                    let firstInputNumber = orderCounters[indent] ?? 0
                    let currentOffset = orderCounters[indent + 1000] ?? 0
                    // 显示序号 = 第一个inputNumber + 1 + 偏移量（+1是因为第二项应该比第一项大1）
                    let displayOrderNumber = (firstInputNumber + 1) + (currentOffset + 1)
                    effectiveInputNumber = displayOrderNumber - 1  // 转换为0-based的inputNumber用于显示
                    // 递增序号偏移计数器
                    orderCounters[indent + 1000] = currentOffset + 1
                }
                
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
            case .checkbox(let indent, let level, let text):
                if let checkboxAttr = parseStandaloneCheckbox(indent: indent, level: level, text: text) {
                    result.append(checkboxAttr)
                    if index < textTagsWithIntervals.count - 1 {
                        // 换行符不应该包含段落样式
                        let newlineAttrs: [NSAttributedString.Key: Any] = [
                            .foregroundColor: NSColor.labelColor,
                            .font: NSFont.systemFont(ofSize: baseFontSize)
                        ]
                        result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                    }
                }
            case .quote(let quoteIndexString):
                // 提取引用索引
                if let quoteIndex = Int(quoteIndexString),
                   quoteIndex < quotePlaceholders.count {
                    let actualQuoteContent = quotePlaceholders[quoteIndex].content
                    if let quoteAttr = parseQuoteBlock(actualQuoteContent) {
                        result.append(quoteAttr)
                        if index < textTagsWithIntervals.count - 1 {
                            result.append(NSAttributedString(string: "\n", attributes: newlineAttributes()))
                        }
                    }
                }
            case .image(let placeholder):
                print("！！！图片处理！！！ 🖼️ [Parser] ========== 处理独立图片占位符 ==========")
                print("！！！图片处理！！！ 🖼️ [Parser] 占位符: '\(placeholder)'")
                
                // 解析占位符获取 fileId 和 fileType
                let placeholderPattern = try! NSRegularExpression(pattern: "🖼️IMAGE_([^:]+)::([^🖼️]+)🖼️", options: [])
                if let match = placeholderPattern.firstMatch(in: placeholder, options: [], range: NSRange(placeholder.startIndex..., in: placeholder)),
                   match.numberOfRanges >= 3,
                   let fileIdRange = Range(match.range(at: 1), in: placeholder),
                   let fileTypeRange = Range(match.range(at: 2), in: placeholder) {
                    let fileId = String(placeholder[fileIdRange])
                    let fileType = String(placeholder[fileTypeRange])
                    print("！！！图片处理！！！ 🖼️ [Parser] 解析占位符: fileId=\(fileId), fileType=\(fileType)")
                    
                    // 创建图片附件
                    // 先创建一个临时 NSAttributedString 来处理图片
                    let tempResult = NSMutableAttributedString(string: placeholder)
                    processImagePlaceholders(in: tempResult)
                    
                    // 如果处理成功，应该只有一个字符（附件字符）
                    if tempResult.length == 1 {
                        result.append(tempResult)
                        print("！！！图片处理！！！ 🖼️ [Parser] ✅ 图片占位符已转换为附件")
                    } else {
                        print("！！！图片处理！！！ 🖼️ [Parser] ⚠️ 图片占位符处理失败，保持原样")
                        result.append(NSAttributedString(string: placeholder))
                    }
                    
                    if index < textTagsWithIntervals.count - 1 {
                        result.append(NSAttributedString(string: "\n", attributes: newlineAttributes()))
                    }
                } else {
                    print("！！！图片处理！！！ 🖼️ [Parser] ⚠️ 无法解析图片占位符格式")
                    result.append(NSAttributedString(string: placeholder))
                }
                print("！！！图片处理！！！ 🖼️ [Parser] ========== 图片占位符处理完成 ==========")
            }
        }
        
        // 在整个解析完成后，处理所有图片占位符（确保不在 <text> 标签内的图片也能被处理）
        processImagePlaceholders(in: result)
        
        return result
    }
    
    // MARK: - NSAttributedString to XML (本地格式转XML)
    
    /// 将本地 NSAttributedString 格式转换为小米笔记 XML 格式（用于上传到云端）
    /// 
    /// 转换规则（参考格式示例）：
    /// 1. 普通文本：<text indent="1">文本</text>\n
    /// 2. 大标题：<text indent="1"><size>大标题</size></text>\n
    /// 3. 二级标题：<text indent="1"><mid-size>二级标题</mid-size></text>\n
    /// 4. 三级标题：<text indent="1"><h3-size>三级标题</h3-size></text>\n
    /// 5. 加粗：<text indent="1"><b>加粗</b></text>\n
    /// 6. 斜体：<text indent="1"><i>斜体</i></text>\n
    /// 7. 下划线：<text indent="1"><u>下划线</u></text>\n
    /// 8. 删除线：<text indent="1"><delete>删除线</delete></text>\n
    /// 9. 无序列表：<bullet indent="1" />无序列表\n（不用<text>包裹）
    /// 10. 有序列表：<order indent="1" inputNumber="0" />有序列表\n（不用<text>包裹）
    /// 11. checkbox：<input type="checkbox" indent="1" level="3" />checkbox\n（不用<text>包裹）
    /// 12. 分割线：<hr />\n
    /// 13. 引用块：<quote><text indent="1">引用1</text>\n<text indent="1">引用2</text></quote>\n
    /// 14. 居中对齐：<text indent="1"><center>居中</center></text>\n
    /// 15. 右对齐：<text indent="1"><right>居右</right></text>\n
    /// 16. 缩进：修改 indent 数字（如 <text indent="2">缩进</text>）
    /// 
    /// - Parameter attributedString: 要转换的 NSAttributedString（本地格式）
    /// - Returns: 转换后的 XML 字符串（小米笔记格式）
    static func parseToXML(_ attributedString: NSAttributedString) -> String {
        guard attributedString.length > 0 else {
            return "<new-format/><text indent=\"1\"></text>"
        }
        
        var xmlParts: [String] = ["<new-format/>"]
        
        // 先收集所有段落（用于识别引用块和有序列表）
        var paragraphs: [NSAttributedString] = []
        let string = attributedString.string
        let fullRange = string.startIndex..<string.endIndex
        
        string.enumerateSubstrings(in: fullRange, options: .byParagraphs) { (substring, substringRange, _, _) in
            guard let substring = substring else { return }
            
            // 跳过空段落（但保留换行）
            let rangeLength = string.distance(from: substringRange.lowerBound, to: substringRange.upperBound)
            if substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rangeLength <= 1 {
                // 对于空段落，创建一个标记，后续处理时会转换为空text标签
                let emptyAttr = NSAttributedString(string: "\u{FFFD}")  // 使用特殊字符作为标记
                paragraphs.append(emptyAttr)
                return
            }
            
            // 转换为 NSRange 以获取属性
            let nsLocation = string.distance(from: string.startIndex, to: substringRange.lowerBound)
            let nsLength = rangeLength
            let paragraphRange = NSRange(location: nsLocation, length: nsLength)
            
            if paragraphRange.location < attributedString.length {
                let paragraphAttr = attributedString.attributedSubstring(from: paragraphRange)
                paragraphs.append(paragraphAttr)
            }
        }
        
        // 处理段落，识别引用块和有序列表
        var i = 0
        var orderCounters: [Int: Int] = [:]  // [indent: currentInputNumber] 用于跟踪有序列表序号
        
        while i < paragraphs.count {
            let paragraph = paragraphs[i]
            
            // 处理空段落
            if paragraph.length == 1 && paragraph.string == "\u{FFFD}" {
                // 检查下一个段落是否是分割线，如果是，跳过这个空段落（避免在分割线前添加空行）
                if i + 1 < paragraphs.count {
                    let nextParagraph = paragraphs[i + 1]
                    let nextParagraphString = nextParagraph.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if nextParagraph.length == 1 || nextParagraphString == "\u{FFFC}" || nextParagraphString.isEmpty {
                        if let attachment = nextParagraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment {
                            // 优先检查 RichTextKit 的分割线附件
                            if attachment is RichTextHorizontalRuleAttachment {
                                // 下一个是分割线，跳过这个空段落
                                i += 1
                                continue
                            }
                            
                            // 兼容旧的 HorizontalRuleAttachmentCell
                            #if macOS
                            if attachment.attachmentCell is HorizontalRuleAttachmentCell {
                                // 下一个是分割线，跳过这个空段落
                                i += 1
                                continue
                            }
                            #endif
                            if attachment.bounds.width >= 100 && attachment.bounds.height <= 2.0 {
                                // 下一个是分割线，跳过这个空段落
                                i += 1
                                continue
                            }
                        }
                    }
                }
                xmlParts.append("<text indent=\"1\"></text>")
                i += 1
                continue
            }
            
            // 检查是否是引用段落
            if isQuoteParagraph(paragraph) {
                // 收集连续的引用段落
                var quoteParagraphs: [NSAttributedString] = [paragraph]
                i += 1
                
                while i < paragraphs.count && isQuoteParagraph(paragraphs[i]) {
                    quoteParagraphs.append(paragraphs[i])
                    i += 1
                }
                
                // 转换为引用块XML
                let quoteXML = convertQuoteBlockToXML(quoteParagraphs)
                xmlParts.append(quoteXML)
                continue
            }
            
            // 检查是否是分割线（在有序列表之前检查，避免分割线被当作普通段落处理）
            let paragraphString = paragraph.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if paragraph.length == 1 || paragraphString == "\u{FFFC}" || paragraphString.isEmpty {
                if let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment {
                    // 优先检查 RichTextKit 的分割线附件
                    if attachment is RichTextHorizontalRuleAttachment {
                        xmlParts.append("<hr />")
                        i += 1
                        continue
                    }
                    
                    // 兼容旧的 HorizontalRuleAttachmentCell
                    #if macOS
                    if attachment.attachmentCell is HorizontalRuleAttachmentCell {
                        xmlParts.append("<hr />")
                        i += 1
                        continue
                    }
                    #endif
                    if attachment.bounds.width >= 100 && attachment.bounds.height <= 2.0 {
                        xmlParts.append("<hr />")
                        i += 1
                        continue
                    }
                }
            }
            
            // 检查是否是有序列表
            if let match = try? NSRegularExpression(pattern: "^\\d+\\.\\s+(.+)").firstMatch(in: paragraphString, options: [], range: NSRange(paragraphString.startIndex..., in: paragraphString)) {
                // 检查是否是连续的有序列表（前一个段落也是有序列表且同缩进）
                var prevWasOrder = false
                var prevIndent = 1
                if i > 0 {
                    let prevParagraph = paragraphs[i - 1]
                    let prevParagraphString = prevParagraph.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let prevMatch = try? NSRegularExpression(pattern: "^\\d+\\.\\s+(.+)").firstMatch(in: prevParagraphString, options: [], range: NSRange(prevParagraphString.startIndex..., in: prevParagraphString)) {
                        // 前一个也是有序列表，检查缩进是否相同
                        if let prevParagraphStyle = prevParagraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                            prevIndent = max(1, Int(prevParagraphStyle.headIndent / indentUnit) + 1)
                        }
                        var currentIndent = 1
                        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                            currentIndent = max(1, Int(paragraphStyle.headIndent / indentUnit) + 1)
                        }
                        prevWasOrder = (prevIndent == currentIndent)
                    }
                }
                
                // 如果不是连续的，需要重置该缩进级别的计数器
                if !prevWasOrder {
                    var currentIndent = 1
                    if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                        currentIndent = max(1, Int(paragraphStyle.headIndent / indentUnit) + 1)
                    }
                    // 只重置当前缩进级别的计数器
                    orderCounters[currentIndent] = nil
                }
                
                let orderXML = convertOrderToXML(paragraph, match: match, orderCounters: &orderCounters)
                xmlParts.append(orderXML)
                i += 1
                continue
            } else {
                // 不是有序列表，如果有之前的有序列表计数器，需要重置
                orderCounters.removeAll()
            }
            
            // 普通段落
            let paragraphXML = convertParagraphToXML(paragraph)
            xmlParts.append(paragraphXML)
            i += 1
        }
        
        return xmlParts.joined(separator: "\n")
    }
    
    /// 检查段落是否是引用段落
    private static func isQuoteParagraph(_ paragraph: NSAttributedString) -> Bool {
        guard paragraph.length > 0 else { return false }
        
        // 检查段落样式（引用块通常有左侧缩进约20）
        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            let quoteIndent: CGFloat = 20.0
            if abs(paragraphStyle.firstLineHeadIndent - quoteIndent) < 5.0 || abs(paragraphStyle.headIndent - quoteIndent) < 5.0 {
                // 检查是否有竖线附件
                if paragraph.string.hasPrefix("\u{FFFC}") {
                    return true
                }
            }
        }
        
        // 检查 RichTextKit 的引用块附件
        if paragraph.string.hasPrefix("\u{FFFC}"),
           let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment {
            if attachment is RichTextBlockQuoteAttachment {
                return true
            }
        }
        
        // 或者通过附件尺寸判断（引用块的竖线：宽度3-5，高度15-25）
        if paragraph.string.hasPrefix("\u{FFFC}"),
           let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
           let image = attachment.image {
            let imageWidth = image.size.width
            let imageHeight = image.size.height
            if imageWidth >= 3.0 && imageWidth <= 5.0 && imageHeight >= 15.0 && imageHeight <= 25.0 {
                return true
            }
        }
        
        return false
    }
    
    /// 转换引用块为XML
    /// 
    /// 格式：<quote><text indent="1">引用1</text>\n<text indent="1">引用2</text></quote>\n
    private static func convertQuoteBlockToXML(_ paragraphs: [NSAttributedString]) -> String {
        var quoteParts: [String] = []
        
        for paragraph in paragraphs {
            // 移除竖线附件和后面的空格
            var textAttr = paragraph
            let paragraphString = paragraph.string
            
            // 查找竖线附件后的文本起始位置（跳过附件字符和可能的空格）
            var textStart = 0
            if paragraphString.hasPrefix("\u{FFFC}") {
                textStart = 1  // 跳过附件字符
                // 跳过附件后的空格（通常有两个空格）
                while textStart < paragraphString.count && paragraphString[paragraphString.index(paragraphString.startIndex, offsetBy: textStart)] == " " {
                    textStart += 1
                }
            }
            
            if textStart > 0 && textStart < paragraph.length {
                let textRange = NSRange(location: textStart, length: paragraph.length - textStart)
                if textRange.location < paragraph.length && textRange.location + textRange.length <= paragraph.length {
                    textAttr = paragraph.attributedSubstring(from: textRange)
                }
            }
            
            // 转换为text标签（移除竖线后的内容，缩进为1）
            let textXML = convertNormalParagraphToXMLForQuote(textAttr)
            quoteParts.append(textXML)
        }
        
        return "<quote>\(quoteParts.joined(separator: "\n"))</quote>"
    }
    
    /// 转换普通段落为XML（用于引用块内，缩进固定为1）
    private static func convertNormalParagraphToXMLForQuote(_ paragraph: NSAttributedString) -> String {
        let fullRange = NSRange(location: 0, length: paragraph.length)
        
        // 引用块内的段落缩进固定为1
        let indent = 1
        var alignment: NSTextAlignment = .left
        
        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            alignment = paragraphStyle.alignment
        }
        
        var innerXML = NSMutableString()
        
        paragraph.enumerateAttributes(in: fullRange, options: []) { (attrs, range, _) in
            let substring = paragraph.attributedSubstring(from: range).string
            var currentText = escapeXML(substring)
            
            // 检查字体样式
            if let font = attrs[.font] as? NSFont {
                    var needsBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                    // 检查斜体：可以通过symbolicTraits或obliqueness属性
                    var needsItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                    // 如果symbolicTraits中没有斜体，检查obliqueness属性（斜体可能通过此属性设置）
                    if !needsItalic, let obliqueness = attrs[.obliqueness] as? CGFloat, obliqueness > 0 {
                        needsItalic = true
                    }
                    
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
        
        print("！！！图片处理！！！ 🖼️ [extractImageDict] ========== 开始提取图片信息 ==========")
        print("！！！图片处理！！！ 🖼️ [extractImageDict] noteRawData: \(noteRawData != nil ? "存在" : "nil")")
        
        guard let rawData = noteRawData else {
            print("！！！图片处理！！！ 🖼️ [extractImageDict] ⚠️ noteRawData 为 nil，返回空字典")
            return imageDict
        }
        
        print("！！！图片处理！！！ 🖼️ [extractImageDict] rawData 键: \(rawData.keys)")
        
        guard let setting = rawData["setting"] as? [String: Any] else {
            print("！！！图片处理！！！ 🖼️ [extractImageDict] ⚠️ rawData 中没有 setting 字段")
            return imageDict
        }
        
        print("！！！图片处理！！！ 🖼️ [extractImageDict] setting 键: \(setting.keys)")
        
        guard let settingData = setting["data"] as? [[String: Any]] else {
            print("！！！图片处理！！！ 🖼️ [extractImageDict] ⚠️ setting 中没有 data 字段或 data 不是数组")
            return imageDict
        }
        
        print("！！！图片处理！！！ 🖼️ [extractImageDict] settingData 数组长度: \(settingData.count)")
        
        for (index, imgData) in settingData.enumerated() {
            print("！！！图片处理！！！ 🖼️ [extractImageDict] 处理图片条目 \(index + 1)/\(settingData.count): \(imgData.keys)")
            
            if let fileId = imgData["fileId"] as? String,
               let mimeType = imgData["mimeType"] as? String {
                print("！！！图片处理！！！ 🖼️ [extractImageDict]    - fileId: \(fileId)")
                print("！！！图片处理！！！ 🖼️ [extractImageDict]    - mimeType: \(mimeType)")
                
                if mimeType.hasPrefix("image/") {
                    let fileType = String(mimeType.dropFirst("image/".count))
                    imageDict[fileId] = fileType
                    print("！！！图片处理！！！ 🖼️ [extractImageDict] ✅ 添加图片: fileId=\(fileId), fileType=\(fileType)")
                } else {
                    print("！！！图片处理！！！ 🖼️ [extractImageDict] ⚠️ mimeType 不是图片类型，跳过: \(mimeType)")
                }
            } else {
                print("！！！图片处理！！！ 🖼️ [extractImageDict] ⚠️ 图片条目缺少 fileId 或 mimeType")
            }
        }
        
        print("！！！图片处理！！！ 🖼️ [extractImageDict] ========== 提取完成，共 \(imageDict.count) 个图片 ==========")
        print("！！！图片处理！！！ 🖼️ [extractImageDict] imageDict: \(imageDict)")
        return imageDict
    }
    
    /// 预处理特殊元素（图片、复选框等）
    private static func preprocessSpecialElements(_ content: String, imageDict: [String: String]) -> String {
        var processed = content
        
        // 处理图片引用
        // 格式1: ☺ fileId<0/></> 或 ☺ fileId
        // 参考 Obsidian 插件：content.replace(/☺\s+([^<]+)(<0\/><\/>)?/gm, ...)
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
        // 参考 Obsidian 插件：content.replace(/<img fileid="([^"]+)" imgshow="0" imgdes="" \/>/g, ...)
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
        case image(placeholder: String)  // 图片占位符
    }
    
    /// 提取所有 <text> 标签及其之间的内容（包括 <hr />、独立的 <bullet />、<order />、<input />）
    private static func extractTextTagsWithIntervals(from content: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        
        // 首先提取所有独立标签（不在 <text> 内的）
        // 格式：<bullet indent="1" />文本内容\n
        // 格式：<order indent="1" inputNumber="0" />文本内容\n
        // 格式：<input type="checkbox" indent="1" level="3" />文本内容\n
        // 格式：<hr />\n
        
        // 先提取独立的 bullet、order、checkbox、hr 标签、引用占位符和图片占位符
        let standalonePatterns: [(pattern: NSRegularExpression, type: String)] = [
            (try! NSRegularExpression(pattern: "<bullet[^>]*indent=\"(\\d+)\"[^>]*/>", options: []), "bullet"),
            (try! NSRegularExpression(pattern: "<order[^>]*indent=\"(\\d+)\"[^>]*inputNumber=\"(\\d+)\"[^>]*/>", options: []), "order"),
            (try! NSRegularExpression(pattern: "<input[^>]*type=\"checkbox\"[^>]*indent=\"(\\d+)\"[^>]*level=\"(\\d+)\"[^>]*/>", options: []), "checkbox"),
            (try! NSRegularExpression(pattern: "<hr[^>]*/>", options: []), "hr"),
            (try! NSRegularExpression(pattern: "🔄QUOTE_PLACEHOLDER_(\\d+)🔄", options: []), "quote"),
            (try! NSRegularExpression(pattern: "🖼️IMAGE_([^:]+)::([^🖼️]+)🖼️", options: []), "image")
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
                allItems.append((match.range, match.type, false, match.indent, match.inputNumber, match.level, placeholder))
                continue
            }
            
            // 对于图片占位符，不需要提取后面的文本，因为占位符本身就是完整的内容
            if match.type == "image" {
                // 图片占位符格式：🖼️IMAGE_fileId::fileType🖼️
                // 直接使用占位符本身，不提取后面的文本
                let placeholderRange = Range(match.range, in: content)!
                let placeholder = String(content[placeholderRange])
                print("！！！图片处理！！！ 🔍 [extractTextTagsWithIntervals] 图片占位符: '\(placeholder)'")
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
                
                print("🔍 [extractTextTagsWithIntervals] 提取标签后文本: type=\(match.type), raw='\(rawText.prefix(20))', trimmed='\(text.prefix(20))'")
            } else {
                print("🔍 [extractTextTagsWithIntervals] 标签后无文本: type=\(match.type)")
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
                            segments.append(.quote(content: indexString))
                        } else {
                            // 如果不是占位符格式，可能是直接的内容（不应该发生）
                            segments.append(.quote(content: content))
                        }
                    } else {
                        segments.append(.quote(content: ""))
                    }
                case "image":
                    // 图片占位符格式：🖼️IMAGE_fileId::fileType🖼️
                    if let placeholder = item.content {
                        print("！！！图片处理！！！ 🔍 [extractTextTagsWithIntervals] 提取图片占位符: '\(placeholder)'")
                        segments.append(.image(placeholder: placeholder))
                    } else {
                        print("！！！图片处理！！！ ⚠️ [extractTextTagsWithIntervals] 图片占位符内容为 nil")
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
        guard !content.isEmpty else {
            // 空段落
            let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
            return NSAttributedString(string: "", attributes: [
                .paragraphStyle: paragraphStyle,
                .foregroundColor: NSColor.labelColor
            ])
        }
        
        // 检查是否是特殊元素（复选框、列表等，这些应该在独立标签中处理，不应该在<text>标签内）
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
        } else if let rightMatch = rightPattern.firstMatch(in: innerContent, options: [], range: NSRange(innerContent.startIndex..., in: innerContent)),
                  rightMatch.numberOfRanges >= 2,
                  let contentRange = Range(rightMatch.range(at: 1), in: innerContent) {
            alignment = .right
            innerContent = String(innerContent[contentRange])
        }
        
        // 先解码 HTML 实体
        innerContent = decodeHTMLEntities(innerContent)
        
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
                        handleStartTag(tagContent, styleStack: &styleStack, currentStyle: &currentStyle)
                    } else {
                        let endTagName = String(tagContent.dropFirst())  // 移除 "/"
                        handleEndTag(tagContent, styleStack: &styleStack, currentStyle: &currentStyle, baseIndent: indent)
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
            appendText(textBuffer, to: result, style: currentStyle, indent: indent, alignment: alignment)
        }
        
        // 处理图片占位符
        processImagePlaceholders(in: result)
        
        // 确保整个段落都应用正确的对齐方式
        if result.length > 0 {
            let fullRange = NSRange(location: 0, length: result.length)
            let paragraphStyle = createParagraphStyle(indent: indent, alignment: alignment)
            result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
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
                    // 小米笔记的有序列表规则：
                    // - 连续多行的有序列表，序号自动递增
                    // - 第一行的inputNumber是实际值，后续行的inputNumber应该都是0
                    
                    // 检查是否是连续的有序列表（前一个segment也是同缩进级别的order）
                    let isFirstInSequence: Bool
                    if index > 0 {
                        let prevItem = segments[index - 1]
                        if case .order(let prevIndent, _, _) = prevItem, prevIndent == indent {
                            isFirstInSequence = false  // 前一个也是同缩进的有序列表，说明这是连续的
                        } else {
                            isFirstInSequence = true  // 前一个不是有序列表或不同缩进，说明这是新序列的开始
                            // 重置该缩进级别的计数器
                            orderCounters[indent] = nil
                        }
                    } else {
                        isFirstInSequence = true
                    }
                    
                    let effectiveInputNumber: Int
                    if isFirstInSequence {
                        // 这是序列的第一项，使用XML中的inputNumber
                        effectiveInputNumber = inputNumber
                        // 保存第一个inputNumber，用于后续项计算显示序号
                        orderCounters[indent] = inputNumber
                        // 初始化序号偏移计数器为0（第一项使用inputNumber，从第二项开始递增）
                        orderCounters[indent + 1000] = 0
                    } else {
                        // 这是连续的有序列表项，inputNumber应该为0
                        // 但我们需要根据第一个inputNumber来计算当前应该显示的序号
                        let firstInputNumber = orderCounters[indent] ?? 0
                        let currentOffset = orderCounters[indent + 1000] ?? 0
                        // 显示序号 = 第一个inputNumber + 1 + 偏移量（+1是因为第二项应该比第一项大1）
                        let displayOrderNumber = (firstInputNumber + 1) + (currentOffset + 1)
                        effectiveInputNumber = displayOrderNumber - 1  // 转换为0-based的inputNumber用于显示
                        // 递增序号偏移计数器
                        orderCounters[indent + 1000] = currentOffset + 1
                    }
                    segmentAttr = parseStandaloneOrder(indent: indent, inputNumber: effectiveInputNumber, text: text)
                    
                case .checkbox(let indent, let level, let text):
                    print("🔍 [parseQuoteBlock] 处理 <input type=\"checkbox\" /> 标签，indent=\(indent), level=\(level), text='\(text)'")
                    segmentAttr = parseStandaloneCheckbox(indent: indent, level: level, text: text)
                    
                case .hr:
                    print("🔍 [parseQuoteBlock] 处理 <hr /> 标签")
                    segmentAttr = parseHrTag()
                    
                case .image(let placeholder):
                    print("！！！图片处理！！！ 🔍 [parseQuoteBlock] 处理图片占位符: '\(placeholder)'")
                    // 创建图片附件
                    // 先创建一个临时 NSAttributedString 来处理图片
                    let tempResult = NSMutableAttributedString(string: placeholder)
                    processImagePlaceholders(in: tempResult)
                    
                    // 如果处理成功，应该只有一个字符（附件字符）
                    if tempResult.length == 1 {
                        segmentAttr = tempResult
                        print("！！！图片处理！！！ 🔍 [parseQuoteBlock] ✅ 图片占位符已转换为附件")
                    } else {
                        print("！！！图片处理！！！ 🔍 [parseQuoteBlock] ⚠️ 图片占位符处理失败，保持原样")
                        segmentAttr = NSAttributedString(string: placeholder)
                    }
                    
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
                    
                    // 为引用块添加左侧缩进和竖线效果
                    let quoteIndent: CGFloat = 20.0
                    paragraphStyle.firstLineHeadIndent = quoteIndent
                    paragraphStyle.headIndent = quoteIndent
                    
                    mutableAttr.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: mutableAttr.length))
                    
                    // 使用 RichTextKit 的引用块附件
                    let blockQuoteAttachment = RichTextBlockQuoteAttachment(indicatorColor: NSColor.separatorColor)
                    let quoteLineAttr = NSMutableAttributedString(attributedString: NSAttributedString(attachment: blockQuoteAttachment))
                    
                    // 在内容前添加竖线和空格
                    let spaceAfterLine = NSAttributedString(string: "  ", attributes: newlineAttributes())  // 两个空格，更清晰
                    result.append(quoteLineAttr)
                    result.append(spaceAfterLine)
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
            // 使用 RichTextKit 的复选框附件
            let attachment = RichTextCheckboxAttachment(isChecked: false)
            let checkboxAttr = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            
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
        print("🔍 [parseStandaloneBullet] 解析无序列表，indent=\(indent), text='\(text)'")
        let result = NSMutableAttributedString()
        
        // 添加项目符号
        let bulletAttr = NSAttributedString(string: "• ", attributes: defaultAttributes())
        result.append(bulletAttr)
        
        // 解析文本内容（可能包含内联样式）
        if !text.isEmpty {
            // 对于独立标签后的文本，通常不包含 XML 标签，直接作为纯文本处理
            // 但如果包含样式标签（如 <b>、<i>），则尝试解析
            if text.contains("<") && text.contains(">") {
                // 可能包含样式标签，尝试解析
                if let textAttr = parseTextTag(text, indent: indent) {
                    result.append(textAttr)
                } else {
                    let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                    result.append(plainTextAttr)
                }
            } else {
                // 纯文本，直接添加
                let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                result.append(plainTextAttr)
            }
        }
        
        let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        
        return result.length > 0 ? result : nil
    }
    
    /// 解析独立有序列表（不在 <text> 标签内）
    private static func parseStandaloneOrder(indent: Int, inputNumber: Int, text: String) -> NSAttributedString? {
        print("🔍 [parseStandaloneOrder] 解析有序列表，indent=\(indent), inputNumber=\(inputNumber), text='\(text)'")
        let result = NSMutableAttributedString()
        
        // 添加序号（inputNumber 是 0-based，显示时 +1）
        // 注意：如果 inputNumber 为 0，表示这是第一个，应该显示为 1
        let orderNumber = inputNumber + 1
        let orderAttr = NSAttributedString(string: "\(orderNumber). ", attributes: defaultAttributes())
        result.append(orderAttr)
        
        // 解析文本内容（可能包含内联样式）
        if !text.isEmpty {
            // 对于独立标签后的文本，通常不包含 XML 标签，直接作为纯文本处理
            // 但如果包含样式标签（如 <b>、<i>），则尝试解析
            if text.contains("<") && text.contains(">") {
                // 可能包含样式标签，尝试解析
                if let textAttr = parseTextTag(text, indent: indent) {
                    result.append(textAttr)
                } else {
                    let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                    result.append(plainTextAttr)
                }
            } else {
                // 纯文本，直接添加
                let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                result.append(plainTextAttr)
            }
        }
        
        let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        
        return result.length > 0 ? result : nil
    }
    
    /// 解析独立复选框（不在 <text> 标签内）
    private static func parseStandaloneCheckbox(indent: Int, level: Int, text: String) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        
        // 创建可交互的复选框附件
        let attachment = CheckboxTextAttachment(data: nil, ofType: nil)
        attachment.isChecked = false  // 默认未选中
        
        // 在 macOS 上，确保 attachmentCell 已设置
        #if macOS
        if attachment.attachmentCell == nil {
            attachment.attachmentCell = CheckboxAttachmentCell(checkbox: attachment)
        }
        #endif
        
        let checkboxAttr = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        
        // 重要：在创建 NSAttributedString 后，需要重新设置 attachmentCell
        // 因为 NSAttributedString(attachment:) 可能不会保留 attachmentCell
        #if macOS
        if let att = checkboxAttr.attribute(.attachment, at: 0, effectiveRange: nil) as? CheckboxTextAttachment {
            if att.attachmentCell == nil {
                att.attachmentCell = CheckboxAttachmentCell(checkbox: att)
            }
            // 确保图片存在
            if att.image == nil {
                att.updateImage()
            }
        }
        #endif
        
        result.append(checkboxAttr)
        
        // 添加空格
        let spaceAttr = NSAttributedString(string: " ", attributes: defaultAttributes())
        result.append(spaceAttr)
        
        // 解析文本内容（可能包含内联样式）
        if !text.isEmpty {
            // 对于独立标签后的文本，通常不包含 XML 标签，直接作为纯文本处理
            // 但如果包含样式标签（如 <b>、<i>），则尝试解析
            if text.contains("<") && text.contains(">") {
                // 可能包含样式标签，尝试解析
                if let textAttr = parseTextTag(text, indent: indent) {
                    result.append(textAttr)
                } else {
                    let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                    result.append(plainTextAttr)
                }
            } else {
                // 纯文本，直接添加
                let plainTextAttr = NSAttributedString(string: text, attributes: defaultAttributes())
                result.append(plainTextAttr)
            }
        }
        
        let paragraphStyle = createParagraphStyle(indent: indent, alignment: .left)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        
        return result.length > 0 ? result : nil
    }
    
    /// 解析分割线标签
    private static func parseHrTag() -> NSAttributedString? {
        // 使用 RichTextKit 的分割线附件
        let attachment = RichTextHorizontalRuleAttachment()
        
        // 创建段落样式，让分割线填满整个宽度
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.paragraphSpacingBefore = 0.0
        paragraphStyle.paragraphSpacing = 0.0
        paragraphStyle.headIndent = 0
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.tailIndent = 0
        
        let attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        attributedString.addAttributes(attrs, range: NSRange(location: 0, length: attributedString.length))
        
        return attributedString
    }
    
    
    /// 处理图片占位符
    private static func processImagePlaceholders(in result: NSMutableAttributedString) {
        let string = result.string
        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ========== 开始处理图片占位符 ==========")
        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 输入字符串长度: \(string.count)")
        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 输入字符串内容: '\(string)'")
        
        let placeholderPattern = try! NSRegularExpression(pattern: "🖼️IMAGE_([^:]+)::([^🖼️]+)🖼️", options: [])
        let matches = placeholderPattern.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
        
        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 找到 \(matches.count) 个图片占位符")
        
        if matches.isEmpty {
            print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ⚠️ 没有找到图片占位符，跳过处理")
            return
        }
        
        // 从后往前处理，避免替换后位置变化影响前面的匹配
        for (index, match) in matches.reversed().enumerated() {
            // 每次循环都重新获取当前字符串，因为之前的替换可能已经改变了字符串
            let currentString = result.string
            let currentLength = result.length
            
            // 验证 match.range 是否在当前字符串范围内
            if match.range.location < 0 || match.range.location >= currentLength {
                print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ⚠️ 占位符范围超出边界，跳过: location=\(match.range.location), length=\(currentLength)")
                continue
            }
            
            // 调整 range 以确保不超出边界
            let safeRange = NSRange(
                location: match.range.location,
                length: min(match.range.length, currentLength - match.range.location)
            )
            
            if match.numberOfRanges >= 3,
               let fileIdRange = Range(match.range(at: 1), in: currentString),
               let fileTypeRange = Range(match.range(at: 2), in: currentString) {
                let fileId = String(currentString[fileIdRange])
                let fileType = String(currentString[fileTypeRange])
                
                print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ========== 处理图片占位符 #\(index + 1)/\(matches.count) ==========")
                print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] fileId=\(fileId), fileType=\(fileType)")
                print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 占位符范围: \(safeRange)")
                
                // 从本地加载图片
                print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 尝试从本地加载图片: fileId=\(fileId), fileType=\(fileType)")
                
                // 检查图片是否存在
                let imageExists = LocalStorageService.shared.imageExists(fileId: fileId, fileType: fileType)
                print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 图片文件存在: \(imageExists)")
                
                if let imageURL = LocalStorageService.shared.getImageURL(fileId: fileId, fileType: fileType) {
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 图片URL: \(imageURL.path)")
                }
                
                if let imageData = LocalStorageService.shared.loadImage(fileId: fileId, fileType: fileType) {
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ✅ 图片数据加载成功，大小: \(imageData.count) 字节")
                    
                    // 创建 NSImage
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 尝试从数据创建 NSImage...")
                    guard let image = NSImage(data: imageData) else {
                        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ❌ 无法从数据创建 NSImage")
                        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 图片数据前10字节: \(imageData.prefix(10).map { String(format: "%02x", $0) }.joined(separator: " "))")
                        let placeholderText = "[图片加载失败: \(fileId)]"
                        // 验证范围有效性
                        if safeRange.location >= 0 && safeRange.location + safeRange.length <= result.length {
                            result.replaceCharacters(in: safeRange, with: NSAttributedString(string: placeholderText, attributes: [.foregroundColor: NSColor.systemRed]))
                        } else {
                            print("！！！图片处理！！！ ⚠️ [processImagePlaceholders] 范围无效，无法替换占位文本")
                        }
                        continue
                    }
                    
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ✅ NSImage 创建成功")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 原始大小: width=\(image.size.width), height=\(image.size.height)")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 图片表示: \(image.representations.count) 个")
                    
                    // 确定 UTI 类型
                    let uti: UTType
                    if fileType.lowercased() == "jpg" || fileType.lowercased() == "jpeg" {
                        uti = .jpeg
                    } else if fileType.lowercased() == "png" {
                        uti = .png
                    } else if fileType.lowercased() == "gif" {
                        uti = .gif
                    } else {
                        // 默认使用 JPEG
                        uti = .jpeg
                    }
                    
                    // 使用 RichTextKit 的 RichTextImageAttachment
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 创建 RichTextImageAttachment...")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - UTI类型: \(uti.identifier)")
                    let attachment = RichTextImageAttachment(data: imageData, ofType: uti)
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ✅ RichTextImageAttachment 创建成功")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - attachment.contents: \(attachment.contents != nil ? "存在(\(attachment.contents!.count)字节)" : "nil")")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - attachment.image: \(attachment.image != nil ? "存在" : "nil")")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - attachment.attachmentCell: \(attachment.attachmentCell != nil ? "存在" : "nil")")
                    
                    // 设置图片大小（限制最大宽度，保持宽高比）
                    let maxWidth: CGFloat = 600
                    let imageSize = image.size
                    // 确保 imageSize 有效
                    let actualWidth = imageSize.width > 0 ? imageSize.width : maxWidth
                    let actualHeight = imageSize.height > 0 ? imageSize.height : maxWidth * 0.75
                    let aspectRatio = actualHeight / actualWidth
                    let displayWidth = min(maxWidth, actualWidth)
                    let displayHeight = displayWidth * aspectRatio
                    
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 计算显示尺寸:")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 原始: \(actualWidth) x \(actualHeight)")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 显示: \(displayWidth) x \(displayHeight)")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 宽高比: \(aspectRatio)")
                    
                    // 设置图片 bounds（确保图片垂直居中对齐）
                    // y 值需要调整以与文字基线对齐（负值表示向上偏移）
                    attachment.bounds = NSRect(x: 0, y: -displayHeight / 2 - 2, width: displayWidth, height: displayHeight)
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 设置图片 bounds: \(attachment.bounds)")
                    
                    // 在 macOS 上，RichTextImageAttachment 会自动处理 attachmentCell
                    // 但为了确保图片能正确显示，我们显式设置
                    #if macOS
                    // RichTextImageAttachment 的 attachmentCell 会从 contents 自动创建
                    // 但我们可以确保 image 属性被设置（用于备用）
                    if attachment.image == nil {
                        attachment.image = image
                        print("！！！图片处理！！！ 🔍 [processImagePlaceholders] 手动设置 attachment.image")
                    }
                    
                    // 验证 attachmentCell 是否存在
                    if attachment.attachmentCell == nil {
                        // 尝试从 imageData 创建 cell
                        if let attachmentImage = attachment.image ?? image {
                            let cell = NSTextAttachmentCell(imageCell: attachmentImage)
                            attachment.attachmentCell = cell
                            print("！！！图片处理！！！ 🔍 [processImagePlaceholders] 手动创建并设置 attachmentCell")
                        } else {
                            print("！！！图片处理！！！ ⚠️ [processImagePlaceholders] 无法创建 attachmentCell：image 为 nil")
                        }
                    } else {
                        print("！！！图片处理！！！ 🔍 [processImagePlaceholders] attachmentCell 已存在")
                    }
                    #endif
                    
                    // 创建包含附件的 NSAttributedString
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 创建包含附件的 NSAttributedString...")
                    let imageAttr = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ✅ NSAttributedString 创建成功，长度: \(imageAttr.length)")
                    
                    // 验证附件是否正确设置
                    if let att = imageAttr.attribute(.attachment, at: 0, effectiveRange: nil) as? RichTextImageAttachment {
                        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ✅ 附件已正确设置到 NSAttributedString")
                        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 附件类型: \(type(of: att))")
                        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 附件 bounds: \(att.bounds)")
                        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 附件 image: \(att.image != nil ? "存在" : "nil")")
                        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 附件 attachmentCell: \(att.attachmentCell != nil ? "存在" : "nil")")
                        // 确保 bounds 正确
                        if att.bounds != attachment.bounds {
                            att.bounds = attachment.bounds
                            print("！！！图片处理！！！ 🔍 [processImagePlaceholders] 更新附件的 bounds")
                        }
                        
                        #if macOS
                        // 再次确保 attachmentCell 存在
                        if att.attachmentCell == nil, let attImage = att.image ?? image {
                            let cell = NSTextAttachmentCell(imageCell: attImage)
                            att.attachmentCell = cell
                            print("！！！图片处理！！！ 🔍 [processImagePlaceholders] 在 NSAttributedString 中重新设置 attachmentCell")
                        }
                        #endif
                    } else {
                        print("！！！图片处理！！！ ⚠️ [processImagePlaceholders] 警告：附件未正确设置到 NSAttributedString")
                    }
                    
                    // 替换占位符
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 替换占位符...")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 占位符范围: \(safeRange)")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 替换前结果长度: \(result.length)")
                    
                    // 保存替换位置和新的长度
                    let replaceLocation = safeRange.location
                    let oldLength = safeRange.length
                    let newLength = imageAttr.length
                    
                    // 确保范围有效
                    guard replaceLocation >= 0 && replaceLocation + oldLength <= result.length else {
                        print("！！！图片处理！！！ ⚠️ [processImagePlaceholders] 占位符范围无效，跳过替换: location=\(replaceLocation), oldLength=\(oldLength), resultLength=\(result.length)")
                        continue
                    }
                    
                    result.replaceCharacters(in: safeRange, with: imageAttr)
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    - 替换后结果长度: \(result.length)")
                    
                    // 验证替换后的附件（使用替换后的新范围）
                    var attachmentInResult = false
                    let verifyRange = NSRange(location: replaceLocation, length: min(newLength, result.length - replaceLocation))
                    if verifyRange.location + verifyRange.length <= result.length {
                        result.enumerateAttribute(.attachment, in: verifyRange, options: []) { (value, range, _) in
                            if value != nil {
                                attachmentInResult = true
                                print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ✅ 验证：替换后在位置 \(range.location) 找到附件")
                            }
                        }
                    }
                    
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ✅ 成功替换图片占位符: fileId=\(fileId), 显示大小=(\(displayWidth), \(displayHeight)), 附件已添加: \(attachmentInResult)")
                } else {
                    // 图片不存在，显示占位文本
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ❌ 图片不存在或无法加载: fileId=\(fileId), fileType=\(fileType)")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 请检查:")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    1. 图片是否已下载到本地")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    2. fileId 和 fileType 是否正确")
                    print("！！！图片处理！！！ 🖼️ [processImagePlaceholders]    3. LocalStorageService 是否正确配置")
                    let placeholderText = "[图片: \(fileId).\(fileType)]"
                    let placeholderAttr = NSAttributedString(
                        string: placeholderText,
                        attributes: [
                            .foregroundColor: NSColor.secondaryLabelColor,
                            .font: NSFont.systemFont(ofSize: 12)
                        ]
                    )
                    // 验证范围有效性
                    if safeRange.location >= 0 && safeRange.location + safeRange.length <= result.length {
                        result.replaceCharacters(in: safeRange, with: placeholderAttr)
                    } else {
                        print("！！！图片处理！！！ ⚠️ [processImagePlaceholders] 范围无效，无法替换占位文本")
                    }
                }
            } else {
                print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ⚠️ 占位符格式不正确，跳过")
            }
        }
        
        // 最终验证：统计所有附件
        var totalAttachments = 0
        var imageAttachments = 0
        result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length), options: []) { (value, range, _) in
            if value != nil {
                totalAttachments += 1
                if value is RichTextImageAttachment {
                    imageAttachments += 1
                }
            }
        }
        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] ========== 处理完成 ==========")
        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 最终结果长度: \(result.length)")
        print("！！！图片处理！！！ 🖼️ [processImagePlaceholders] 总附件数量: \(totalAttachments) (其中图片: \(imageAttachments))")
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
                // 注意：m21 > 0 向右倾斜，m21 < 0 向左倾斜，这里使用 0.2 向右倾斜
                var fontDescriptor = systemFont.fontDescriptor
                let italicTransform = AffineTransform(m11: 1.0, m12: 0.0, m21: 0.2, m22: 1.0, tX: 0.0, tY: 0.0)
                print("  🔍 [appendText] 创建斜体变换矩阵: m11=1.0, m12=0.0, m21=0.2 (向右倾斜), m22=1.0")
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
                // 注意：m21 > 0 向右倾斜，m21 < 0 向左倾斜，这里使用 0.2 向右倾斜
                let italicTransform = AffineTransform(m11: 1.0, m12: 0.0, m21: 0.2, m22: 1.0, tX: 0.0, tY: 0.0)
                // 通过字体描述符应用变换
                var fontDescriptor = font.fontDescriptor
                fontDescriptor = fontDescriptor.withMatrix(italicTransform)
                if let italicFont = NSFont(descriptor: fontDescriptor, size: style.fontSize) {
                    font = italicFont
                    print("  ✅ [appendText] 通过变换矩阵应用斜体效果成功（向右倾斜）")
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
        // obliqueness 正值向右倾斜，负值向左倾斜，0.2 是常见的斜体倾斜度（向右倾斜）
        if style.isItalic {
            attrs[.obliqueness] = 0.2
            print("  ✅ [appendText] 已设置 obliqueness = 0.2 来应用斜体效果（向右倾斜，字体包含斜体特性: \(hasItalic)）")
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
        
        // 分割线：检查 RichTextHorizontalRuleAttachment 类型（优先）或旧的 HorizontalRuleAttachmentCell
        if paragraph.length == 1 || paragraphString == "\u{FFFC}" || paragraphString.isEmpty {
            if let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment {
                // 优先检查 RichTextKit 的分割线附件
                if attachment is RichTextHorizontalRuleAttachment {
                    return "<hr />"
                }
                
                // 兼容旧的 HorizontalRuleAttachmentCell
                #if macOS
                if attachment.attachmentCell is HorizontalRuleAttachmentCell {
                    return "<hr />"
                }
                #endif
                
                // 如果没有 attachmentCell，检查 bounds（分割线 bounds 通常宽度很大，高度为1）
                if attachment.bounds.width >= 100 && attachment.bounds.height <= 2.0 {
                    return "<hr />"
                }
            }
        }
        
        // 引用块的竖线附件检测（必须在checkbox检测之前）
        // 引用块的竖线特征：宽度约为 4，高度约为 20
        // 引用块可以通过段落样式（左侧缩进）来识别，但为了更准确，也检查竖线附件
        // 如果段落包含引用块的竖线，不应该被误判为checkbox
        var hasQuoteLine = false
        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            // 引用块通常有较大的左侧缩进（firstLineHeadIndent 和 headIndent 都约为 20）
            let quoteIndent: CGFloat = 20.0
            if abs(paragraphStyle.firstLineHeadIndent - quoteIndent) < 5.0 || abs(paragraphStyle.headIndent - quoteIndent) < 5.0 {
                hasQuoteLine = true
            }
        }
        
        // 检查 RichTextKit 的引用块附件
        if !hasQuoteLine, let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment {
            if attachment is RichTextBlockQuoteAttachment {
                hasQuoteLine = true
            }
        }
        
        // 或者通过附件尺寸判断（引用块的竖线：宽度3-5，高度15-25）
        if !hasQuoteLine, let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
           let image = attachment.image {
            let imageWidth = image.size.width
            let imageHeight = image.size.height
            hasQuoteLine = imageWidth >= 3.0 && imageWidth <= 5.0 && imageHeight >= 15.0 && imageHeight <= 25.0
        }
        
        // 复选框（排除引用块的竖线和分割线）
        if !hasQuoteLine, let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment {
            // 优先检查 RichTextKit 的复选框附件
            if attachment is RichTextCheckboxAttachment {
                return convertCheckboxToXML(paragraph)
            }
            
            // 兼容旧的 CheckboxTextAttachment
            if attachment is CheckboxTextAttachment {
                return convertCheckboxToXML(paragraph)
            }
            
            // 先检查是否是分割线（已经在上面处理）
            #if macOS
            if attachment.attachmentCell is HorizontalRuleAttachmentCell {
                // 已经处理为分割线，跳过
            } else if let image = attachment.image {
                let imageWidth = image.size.width
                let imageHeight = image.size.height
                // checkbox的特征：宽度<=20且>0，高度也较小（通常<=20）
                // 排除引用块的竖线（宽度3-5，高度15-25）
                let isCheckbox = imageWidth <= 20 && imageWidth > 0 && imageHeight <= 20 && !(imageWidth >= 3.0 && imageWidth <= 5.0 && imageHeight >= 15.0 && imageHeight <= 25.0)
                if isCheckbox {
                    return convertCheckboxToXML(paragraph)
                }
            }
            #else
            if let image = attachment.image {
                let imageWidth = image.size.width
                let imageHeight = image.size.height
                // checkbox的特征：宽度<=20且>0，高度也较小（通常<=20）
                // 排除引用块的竖线（宽度3-5，高度15-25）
                let isCheckbox = imageWidth <= 20 && imageWidth > 0 && imageHeight <= 20 && !(imageWidth >= 3.0 && imageWidth <= 5.0 && imageHeight >= 15.0 && imageHeight <= 25.0)
                if isCheckbox {
                    return convertCheckboxToXML(paragraph)
                }
            }
            #endif
        }
        
        // 无序列表
        if paragraphString.hasPrefix("• ") {
            return convertBulletToXML(paragraph)
        }
        
        // 注意：有序列表和引用块已经在 parseToXML 中处理，这里不会收到这些类型的段落
        
        // 分割线：检查是否包含足够多的 "─" 字符（至少30个），且主要是分割线字符
        let dashCount = paragraphString.filter { $0 == "─" }.count
        if dashCount >= 30 && paragraphString.trimmingCharacters(in: .whitespacesAndNewlines).allSatisfy({ $0 == "─" || $0 == " " || $0 == "\n" }) {
            return "<hr />"
        }
        
        // 普通段落
        return convertNormalParagraphToXML(paragraph)
    }
    
    /// 转换普通段落为 XML
    /// 
    /// 格式：<text indent="1">内容</text>\n
    /// 内容可以包含内联样式标签：<b>、<i>、<u>、<delete>、<size>、<mid-size>、<h3-size>、<center>、<right>、<background>等
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
                    // 检查斜体：可以通过symbolicTraits或obliqueness属性
                    var needsItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                    // 如果symbolicTraits中没有斜体，检查obliqueness属性（斜体可能通过此属性设置）
                    if !needsItalic, let obliqueness = attrs[.obliqueness] as? CGFloat, obliqueness > 0 {
                        needsItalic = true
                    }
                    
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
    
    /// 转换复选框为 XML（根据格式示例：不用<text>包裹）
    /// 
    /// 格式：<input type="checkbox" indent="1" level="3" />checkbox文本\n
    /// 注意：checkbox 标签后直接跟文本，不使用 <text> 标签包裹
    private static func convertCheckboxToXML(_ paragraph: NSAttributedString) -> String {
        var indent = 1
        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            indent = max(1, Int(paragraphStyle.headIndent / indentUnit) + 1)
        }
        
        // 提取复选框后的文本
        let checkboxTag = "<input type=\"checkbox\" indent=\"\(indent)\" level=\"3\" />"
        
        // 检查是否有文本内容
        let string = paragraph.string
        if string.count > 1 {
            // 跳过第一个字符（复选框图标），提取剩余文本
            let textRange = NSRange(location: 1, length: paragraph.length - 1)
            if textRange.location < paragraph.length {
                let textAttr = paragraph.attributedSubstring(from: textRange)
                // 提取纯文本内容（不转换XML，因为checkbox标签后直接跟文本）
                let textContent = escapeXML(textAttr.string.trimmingCharacters(in: .whitespacesAndNewlines))
                return "\(checkboxTag)\(textContent)"
            }
        }
        
        // 只有复选框，没有文本
        return checkboxTag
    }
    
    /// 转换无序列表为 XML（根据格式示例：不用<text>包裹）
    /// 
    /// 格式：<bullet indent="1" />无序列表文本\n
    /// 注意：bullet 标签后直接跟文本，不使用 <text> 标签包裹
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
                // 提取纯文本内容（不转换XML，因为bullet标签后直接跟文本）
                let textContent = escapeXML(textAttr.string.trimmingCharacters(in: .whitespacesAndNewlines))
                return "<bullet indent=\"\(indent)\" />\(textContent)"
            }
        }
        
        // 只有bullet，没有文本
        return "<bullet indent=\"\(indent)\" />"
    }
    
    /// 转换有序列表为 XML（根据格式示例：不用<text>包裹）
    /// 
    /// 格式：<order indent="1" inputNumber="0" />有序列表文本\n
    /// 注意：order 标签后直接跟文本，不使用 <text> 标签包裹
    /// inputNumber 是 0-based 索引（显示时会+1，所以0显示为1）
    /// 
    /// 小米笔记的有序列表规则：
    /// - 连续多行的有序列表，第一行的inputNumber是实际值，后续行的inputNumber都是0
    /// - 例如：inputNumber为0,0,0,0，渲染为1,2,3,4
    /// - 例如：100,0,0,0渲染为100,101,102,103
    private static func convertOrderToXML(_ paragraph: NSAttributedString, match: NSTextCheckingResult, orderCounters: inout [Int: Int]) -> String {
        var indent = 1
        if let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            indent = max(1, Int(paragraphStyle.headIndent / indentUnit) + 1)
        }
        
        let string = paragraph.string
        var inputNumber = 0
        
        // 正则表达式匹配 "^\\d+\\.\\s+(.+)" 
        // match.range 是整个匹配（包括数字、点、空格和文本）
        // match.range(at: 1) 是第一个捕获组（文本部分）
        if match.numberOfRanges >= 2 {
            // 提取数字部分（从 match.range 的开始到第一个点之前）
            let fullMatchRange = match.range
            if let fullRange = Range(fullMatchRange, in: string) {
                let fullMatchText = String(string[fullRange])
                // 提取数字：从开始到第一个点之前
                if let dotIndex = fullMatchText.firstIndex(of: ".") {
                    let numberText = String(fullMatchText[..<dotIndex])
                    if let orderNumber = Int(numberText) {
                        // 检查是否是连续有序列表的第一项
                        // orderCounters[indent]存储第一个inputNumber，如果为nil说明这是新序列
                        let isFirstInSequence = (orderCounters[indent] == nil)
                        
                        if isFirstInSequence {
                            // 这是序列的第一项，使用显示的序号转换为inputNumber（0-based）
                            inputNumber = max(0, orderNumber - 1)
                            // 保存第一个inputNumber
                            orderCounters[indent] = inputNumber
                        } else {
                            // 这是连续的有序列表项，inputNumber应该为0
                            inputNumber = 0
                        }
                        
                        // 提取文本部分（使用捕获组）
                        if let textRange = Range(match.range(at: 1), in: string) {
                            let textStart = string.distance(from: string.startIndex, to: textRange.lowerBound)
                            let textLength = string.distance(from: textRange.lowerBound, to: textRange.upperBound)
                            let textAttrRange = NSRange(location: textStart, length: textLength)
                            
                            if textAttrRange.location < paragraph.length && textAttrRange.location + textAttrRange.length <= paragraph.length {
                                let textAttr = paragraph.attributedSubstring(from: textAttrRange)
                                // 提取纯文本内容（不转换XML，因为order标签后直接跟文本）
                                let textContent = escapeXML(textAttr.string.trimmingCharacters(in: .whitespacesAndNewlines))
                                return "<order indent=\"\(indent)\" inputNumber=\"\(inputNumber)\" />\(textContent)"
                            }
                        }
                    }
                }
            }
        }
        
        // 只有order，没有文本
        let isFirstInSequence = (orderCounters[indent] == nil)
        if isFirstInSequence {
            inputNumber = 0
            orderCounters[indent] = 0
        } else {
            inputNumber = 0
        }
        return "<order indent=\"\(indent)\" inputNumber=\"\(inputNumber)\" />"
    }
    
    /// 转换文本内容为 XML（不包含 <text> 标签，用于嵌套在 <text> 内的内联样式）
    /// 
    /// 用于转换段落内的文本样式，如加粗、斜体、下划线等
    /// 返回的XML会嵌套在 <text> 标签内
    private static func convertTextToXML(_ attributedString: NSAttributedString) -> String {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        var innerXML = NSMutableString()
        
        attributedString.enumerateAttributes(in: fullRange, options: []) { (attrs, range, _) in
            let substring = attributedString.attributedSubstring(from: range).string
            var currentText = escapeXML(substring)

            // 检查字体样式
            if let font = attrs[.font] as? NSFont {
                var needsBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                // 检查斜体：可以通过symbolicTraits或obliqueness属性
                var needsItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                // 如果symbolicTraits中没有斜体，检查obliqueness属性（斜体可能通过此属性设置）
                if !needsItalic, let obliqueness = attrs[.obliqueness] as? CGFloat, obliqueness > 0 {
                    needsItalic = true
                }
                
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
    static func defaultAttributes() -> [NSAttributedString.Key: Any] {
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


