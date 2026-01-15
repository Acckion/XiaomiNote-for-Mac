//
//  AttributedStringToASTConverter.swift
//  MiNoteMac
//
//  NSAttributedString 到 AST 转换器
//  从 NSAttributedString 提取格式属性并生成 AST
//

import AppKit
import Foundation

// MARK: - NSAttributedString 到 AST 转换器

/// NSAttributedString 到 AST 转换器
///
/// 核心算法：
/// 1. 按段落分割 NSAttributedString
/// 2. 对每个段落，识别块级类型（通过附件或段落属性）
/// 3. 遍历属性运行段，提取格式信息，生成 FormatSpan 数组
/// 4. 使用 FormatSpanMerger 合并相邻相同格式
/// 5. 将 FormatSpan 转换为行内节点树
/// 6. 组装成块级节点
public final class AttributedStringToASTConverter: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// 格式跨度合并器
    private let spanMerger: FormatSpanMerger
    
    /// 是否在有序列表序列中（用于计算 inputNumber）
    /// _Requirements: 10.3_ - 遵循 inputNumber 规则
    private var isInOrderedListSequence: Bool = false
    
    /// 上一个有序列表的编号（用于验证连续性）
    private var lastOrderedListNumber: Int = 0
    
    // MARK: - Initialization
    
    public init() {
        self.spanMerger = FormatSpanMerger()
    }
    
    // MARK: - Public Methods
    
    /// 将 NSAttributedString 转换为文档 AST
    ///
    /// - Parameter attributedString: NSAttributedString
    /// - Returns: 文档 AST 节点
    /// _Requirements: 10.3_ - 正确计算 inputNumber
    public func convert(_ attributedString: NSAttributedString) -> DocumentNode {
        // 重置有序列表跟踪状态
        isInOrderedListSequence = false
        lastOrderedListNumber = 0
        
        // 按段落分割
        let paragraphs = splitIntoParagraphs(attributedString)
        
        // 转换每个段落为块级节点
        let blocks = paragraphs.compactMap { paragraph -> (any BlockNode)? in
            convertParagraphToBlock(paragraph)
        }
        
        return DocumentNode(blocks: blocks)
    }
    
    // MARK: - Private Methods - 段落分割
    
    /// 按段落分割 NSAttributedString
    ///
    /// - Parameter attributedString: NSAttributedString
    /// - Returns: 段落数组
    private func splitIntoParagraphs(_ attributedString: NSAttributedString) -> [NSAttributedString] {
        let string = attributedString.string
        var paragraphs: [NSAttributedString] = []
        
        var currentStart = 0
        let length = (string as NSString).length
        
        while currentStart < length {
            var lineEnd = 0
            var contentsEnd = 0
            (string as NSString).getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: currentStart, length: 0))
            
            let range = NSRange(location: currentStart, length: contentsEnd - currentStart)
            if range.length > 0 {
                let paragraph = attributedString.attributedSubstring(from: range)
                paragraphs.append(paragraph)
            }
            
            currentStart = lineEnd
        }
        
        return paragraphs
    }
    
    // MARK: - Private Methods - 段落转换
    
    /// 将单个段落转换为块级节点
    ///
    /// - Parameter paragraph: 段落 NSAttributedString
    /// - Returns: 块级节点
    /// _Requirements: 10.3_ - 非有序列表块重置序列状态
    private func convertParagraphToBlock(_ paragraph: NSAttributedString) -> (any BlockNode)? {
        // 检查是否为空段落
        if paragraph.length == 0 {
            return nil
        }
        
        // 检查第一个字符是否为附件
        if paragraph.length > 0 {
            let firstCharRange = NSRange(location: 0, length: 1)
            if let attachment = paragraph.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment {
                // 识别附件类型并创建对应的块级节点
                return convertAttachmentToBlock(attachment, paragraph: paragraph)
            }
        }
        
        // 非附件段落（普通文本块），重置有序列表序列状态
        // _Requirements: 10.3_ - 只有连续的有序列表才使用 inputNumber = 0
        isInOrderedListSequence = false
        lastOrderedListNumber = 0
        
        // 提取段落属性
        let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let indent = extractIndent(from: paragraphStyle)
        
        // 提取行内内容
        let inlineNodes = convertToInlineNodes(paragraph)
        
        // 创建文本块节点
        return TextBlockNode(indent: indent, content: inlineNodes)
    }
    
    /// 将附件转换为块级节点
    ///
    /// - Parameters:
    ///   - attachment: NSTextAttachment
    ///   - paragraph: 段落 NSAttributedString
    /// - Returns: 块级节点
    /// _Requirements: 10.1, 10.2, 10.3_ - 正确检测附件并计算 inputNumber
    private func convertAttachmentToBlock(_ attachment: NSTextAttachment, paragraph: NSAttributedString) -> (any BlockNode)? {
        // 提取段落属性（作为后备）
        let paragraphStyle = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let defaultIndent = extractIndent(from: paragraphStyle)
        
        // 提取附件后的文本内容（用于列表和复选框）
        // 注意：现在附件后不再有空格，但保留兼容性检查以处理旧数据
        var contentStart = 1
        if paragraph.length > 1 {
            let charAfterAttachment = (paragraph.string as NSString).substring(with: NSRange(location: 1, length: 1))
            if charAfterAttachment == " " {
                contentStart = 2  // 跳过空格（兼容旧数据）
            }
        }
        
        let contentRange = NSRange(location: contentStart, length: paragraph.length - contentStart)
        let contentString = contentRange.length > 0 ? paragraph.attributedSubstring(from: contentRange) : NSAttributedString()
        let inlineNodes = convertToInlineNodes(contentString)
        
        // 使用类型检查而不是字符串比较
        // 复选框附件
        if let checkboxAttachment = attachment as? InteractiveCheckboxAttachment {
            // 非有序列表，重置序列状态
            isInOrderedListSequence = false
            lastOrderedListNumber = 0
            
            // 优先使用附件自身的 indent 属性
            let indent = checkboxAttachment.indent
            return CheckboxNode(
                indent: indent,
                level: checkboxAttachment.level,
                isChecked: checkboxAttachment.isChecked,
                content: inlineNodes
            )
        }
        
        // 分割线附件
        if attachment is HorizontalRuleAttachment {
            // 非有序列表，重置序列状态
            isInOrderedListSequence = false
            lastOrderedListNumber = 0
            return HorizontalRuleNode()
        }
        
        // 图片附件
        if let imageAttachment = attachment as? ImageAttachment {
            // 非有序列表，重置序列状态
            isInOrderedListSequence = false
            lastOrderedListNumber = 0
            return ImageNode(
                fileId: imageAttachment.fileId,
                src: imageAttachment.src,
                width: Int(imageAttachment.displaySize.width),
                height: Int(imageAttachment.displaySize.height)
            )
        }
        
        // 音频附件
        if let audioAttachment = attachment as? AudioAttachment {
            // 非有序列表，重置序列状态
            isInOrderedListSequence = false
            lastOrderedListNumber = 0
            return AudioNode(
                fileId: audioAttachment.fileId ?? "",
                isTemporary: audioAttachment.isTemporaryPlaceholder
            )
        }
        
        // 无序列表附件
        if let bulletAttachment = attachment as? BulletAttachment {
            // 非有序列表，重置序列状态
            isInOrderedListSequence = false
            lastOrderedListNumber = 0
            
            // 优先使用附件自身的 indent 属性
            let indent = bulletAttachment.indent
            return BulletListNode(indent: indent, content: inlineNodes)
        }
        
        // 有序列表附件
        // _Requirements: 10.2, 10.3_ - 正确计算 inputNumber
        if let orderAttachment = attachment as? OrderAttachment {
            // 优先使用附件自身的 indent 属性
            let indent = orderAttachment.indent
            let currentNumber = orderAttachment.number
            
            // 计算 inputNumber
            // _Requirements: 10.3_ - inputNumber 规则：
            // - 第一项：inputNumber = 实际编号 - 1
            // - 后续连续项：inputNumber = 0
            let calculatedInputNumber: Int
            if isInOrderedListSequence && currentNumber == lastOrderedListNumber + 1 {
                // 连续编号，使用 0
                calculatedInputNumber = 0
            } else {
                // 新列表或非连续编号，使用 number - 1
                calculatedInputNumber = currentNumber - 1
            }
            
            // 更新跟踪状态
            isInOrderedListSequence = true
            lastOrderedListNumber = currentNumber
            
            return OrderedListNode(
                indent: indent,
                inputNumber: calculatedInputNumber,
                content: inlineNodes
            )
        }
        
        // 未识别的附件类型，重置序列状态并返回 nil
        isInOrderedListSequence = false
        lastOrderedListNumber = 0
        return nil
    }
    
    // MARK: - Private Methods - 属性提取
    
    /// 从段落样式中提取缩进级别
    ///
    /// - Parameter paragraphStyle: 段落样式
    /// - Returns: 缩进级别（默认为 1）
    private func extractIndent(from paragraphStyle: NSParagraphStyle?) -> Int {
        guard let paragraphStyle = paragraphStyle else { return 1 }
        
        // 缩进级别 = firstLineHeadIndent / 20.0
        // 小米笔记使用 20pt 作为一个缩进单位
        let indentPoints = paragraphStyle.firstLineHeadIndent
        
        // 如果缩进为 0，返回 1（默认缩进）
        if indentPoints < 1 {
            return 1
        }
        
        // 计算缩进级别，向上取整以确保精度
        let indentLevel = Int(round(indentPoints / 20.0))
        
        return max(1, indentLevel + 1)  // +1 因为小米笔记的缩进从 1 开始
    }
    
    /// 将 NSAttributedString 转换为行内节点数组
    ///
    /// 核心算法：
    /// 1. 遍历属性运行段
    /// 2. 对每个运行段，提取格式信息，创建 FormatSpan
    /// 3. 使用 FormatSpanMerger 合并相邻相同格式
    /// 4. 将 FormatSpan 转换为行内节点树
    ///
    /// - Parameter attributedString: NSAttributedString
    /// - Returns: 行内节点数组
    private func convertToInlineNodes(_ attributedString: NSAttributedString) -> [any InlineNode] {
        var spans: [FormatSpan] = []
        
        // 遍历属性运行段
        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { attributes, range, _ in
            let text = (attributedString.string as NSString).substring(with: range)
            
            // 跳过附件字符
            if attributes[.attachment] != nil {
                return
            }
            
            // 提取格式信息
            let formats = extractFormats(from: attributes)
            let highlightColor = extractHighlightColor(from: attributes)
            
            // 创建格式跨度
            let span = FormatSpan(text: text, formats: formats, highlightColor: highlightColor)
            spans.append(span)
        }
        
        // 合并相邻相同格式
        let mergedSpans = spanMerger.mergeAdjacentSpans(spans)
        
        // 转换为行内节点树
        return spanMerger.spansToInlineNodes(mergedSpans)
    }
    
    /// 从属性字典提取格式类型集合
    ///
    /// - Parameter attributes: 属性字典
    /// - Returns: 格式类型集合
    /// - Requirements: 7.1, 7.2, 7.3
    private func extractFormats(from attributes: [NSAttributedString.Key: Any]) -> Set<ASTNodeType> {
        var formats: Set<ASTNodeType> = []
        
        // 检查字体属性（粗体、斜体、标题）
        if let font = attributes[.font] as? NSFont {
            let fontSize = font.pointSize
            
            // 使用 FontSizeConstants 检测标题级别（非 MainActor 上下文）
            // _Requirements: 7.1, 7.2, 7.3_
            let detectedFormat = FontSizeConstants.detectParagraphFormat(fontSize: fontSize)
            let isHeading = detectedFormat.isHeading
            
            // 检查粗体（但不包括标题的粗体，因为标题会单独处理）
            if font.fontDescriptor.symbolicTraits.contains(.bold) && !isHeading {
                formats.insert(.bold)
            }
            if font.fontDescriptor.symbolicTraits.contains(.italic) {
                formats.insert(.italic)
            }
            
            // 使用 FontSizeConstants 的检测结果设置标题格式
            // _Requirements: 7.1, 7.2, 7.3_
            switch detectedFormat {
            case .heading1:
                formats.insert(.heading1)  // 大标题 23pt
            case .heading2:
                formats.insert(.heading2)  // 二级标题 20pt
            case .heading3:
                formats.insert(.heading3)  // 三级标题 17pt
            default:
                break
            }
        }
        
        // 检查倾斜度（斜体的另一种实现方式）
        if let obliqueness = attributes[.obliqueness] as? NSNumber, obliqueness.doubleValue > 0 {
            formats.insert(.italic)
        }
        
        // 检查下划线
        if let underlineStyle = attributes[.underlineStyle] as? NSNumber, underlineStyle.intValue > 0 {
            formats.insert(.underline)
        }
        
        // 检查删除线
        if let strikethroughStyle = attributes[.strikethroughStyle] as? NSNumber, strikethroughStyle.intValue > 0 {
            formats.insert(.strikethrough)
        }
        
        // 检查背景色（高亮）
        if attributes[.backgroundColor] != nil {
            formats.insert(.highlight)
        }
        
        // 检查段落对齐方式
        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            switch paragraphStyle.alignment {
            case .center:
                formats.insert(.centerAlign)
            case .right:
                formats.insert(.rightAlign)
            default:
                break
            }
        }
        
        return formats
    }
    
    /// 从属性字典提取高亮颜色
    ///
    /// - Parameter attributes: 属性字典
    /// - Returns: 颜色值（十六进制字符串）
    private func extractHighlightColor(from attributes: [NSAttributedString.Key: Any]) -> String? {
        guard let backgroundColor = attributes[.backgroundColor] as? NSColor else {
            return nil
        }
        
        // 转换为 RGB 颜色空间
        guard let rgbColor = backgroundColor.usingColorSpace(.sRGB) else {
            return nil
        }
        
        // 转换为十六进制字符串
        let red = Int(rgbColor.redComponent * 255)
        let green = Int(rgbColor.greenComponent * 255)
        let blue = Int(rgbColor.blueComponent * 255)
        
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
