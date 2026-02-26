//
//  ASTToAttributedStringConverter.swift
//  MiNoteMac
//
//  AST 到 NSAttributedString 转换器
//  将抽象语法树转换为 macOS 原生富文本格式
//

import AppKit

// MARK: - 自定义属性键

/// 自定义 NSAttributedString 属性键，用于字体属性的累积
private extension NSAttributedString.Key {
    /// 粗体标记（用于累积字体特征）
    static let fontTraitBold = NSAttributedString.Key("fontTraitBold")
    /// 字体大小（用于累积字体特征）
    static let fontSize = NSAttributedString.Key("fontSize")
    /// 字体粗细（用于累积字体特征）
    static let fontWeight = NSAttributedString.Key("fontWeight")
}

/// AST 到 NSAttributedString 转换器
///
/// 使用 Visitor 模式遍历 AST，将每个节点转换为对应的 NSAttributedString
/// 支持递归属性继承，确保嵌套格式正确应用
public final class ASTToAttributedStringConverter {

    // MARK: - Properties

    /// 文件夹 ID（用于图片加载）
    private let folderId: String?

    /// 默认字体
    private let defaultFont: NSFont

    /// 默认段落样式
    private let defaultParagraphStyle: NSMutableParagraphStyle

    /// 当前有序列表编号（用于跟踪连续有序列表）
    private var currentOrderedListNumber = 0

    // MARK: - Initialization

    /// 创建转换器
    /// - Parameter folderId: 文件夹 ID（用于图片加载）
    public init(folderId: String? = nil) {
        self.folderId = folderId

        // 使用 FontSizeConstants 获取默认字体大小
        self.defaultFont = NSFont.systemFont(ofSize: FontSizeConstants.body)

        // 设置默认段落样式
        self.defaultParagraphStyle = ParagraphStyleFactory.makeDefault()
    }

    // MARK: - Public Methods

    /// 将文档 AST 转换为 NSAttributedString
    ///
    /// - Parameter document: 文档 AST 节点
    /// - Returns: NSAttributedString
    public func convert(_ document: DocumentNode) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // 每次转换文档时重置有序列表编号计数器
        currentOrderedListNumber = 0

        var contentBlocks = document.blocks

        // 跳过 TitleBlockNode，标题已独立于正文，不再渲染到 NSTextView 中
        if document.blocks.first is TitleBlockNode {
            contentBlocks = Array(document.blocks.dropFirst())
        }

        for (index, block) in contentBlocks.enumerated() {
            let blockString = convertBlock(block)
            result.append(blockString)

            if index < contentBlocks.count - 1 {
                // 换行符需要继承当前块的属性，确保空行保持正确的字体和段落样式
                let newlineAttributes = resolveNewlineAttributes(for: block, blockString: blockString)
                result.append(NSAttributedString(string: "\n", attributes: newlineAttributes))
            }
        }

        return result
    }

    // MARK: - Block Conversion

    /// 将块级节点转换为 NSAttributedString
    ///
    /// - Parameter block: 块级节点
    /// - Returns: NSAttributedString
    private func convertBlock(_ block: any BlockNode) -> NSAttributedString {
        // 非有序列表块会重置编号计数器
        if block.nodeType != .orderedList {
            currentOrderedListNumber = 0
        }

        switch block.nodeType {
        case .titleBlock:
            // 标题块在 convert() 中已跳过，此处为容错处理，返回空字符串
            return NSAttributedString()
        case .textBlock:
            return convertTextBlock(block as! TextBlockNode)
        case .bulletList:
            return convertBulletList(block as! BulletListNode)
        case .orderedList:
            return convertOrderedList(block as! OrderedListNode)
        case .checkbox:
            return convertCheckbox(block as! CheckboxNode)
        case .horizontalRule:
            return convertHorizontalRule(block as! HorizontalRuleNode)
        case .image:
            return convertImage(block as! ImageNode)
        case .audio:
            return convertAudio(block as! AudioNode)
        case .quote:
            return convertQuote(block as! QuoteNode)
        default:
            // 不应该到达这里
            return NSAttributedString()
        }
    }

    /// 转换文本块节点
    /// - Parameter node: 文本块节点
    /// - Returns: NSAttributedString
    private func convertTextBlock(_ node: TextBlockNode) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // 转换行内内容
        let inlineString = convertInlineNodes(node.content, inheritedAttributes: [:])
        result.append(inlineString)

        // 应用缩进
        if node.indent > 1 {
            applyIndent(to: result, level: node.indent)
        }

        return result
    }

    /// 转换无序列表节点
    /// - Parameter node: 无序列表节点
    /// - Returns: NSAttributedString
    private func convertBulletList(_ node: BulletListNode) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // 创建项目符号附件
        let bulletAttachment = BulletAttachment(indent: node.indent)
        let attachmentString = NSAttributedString(attachment: bulletAttachment)
        result.append(attachmentString)

        // 注意：不再添加空格，附件本身已有足够的间距
        // 这确保 XML 往返转换的一致性

        // 转换行内内容
        let inlineString = convertInlineNodes(node.content, inheritedAttributes: [:])
        result.append(inlineString)

        // 设置列表类型属性，以便 BlockFormatHandler.detect() 能正确检测列表格式
        // 这对于列表换行继承功能至关重要
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.listType, value: ListType.bullet, range: fullRange)
        result.addAttribute(.listIndent, value: node.indent, range: fullRange)

        // 应用列表段落样式（包含行间距和段落间距）
        let paragraphStyle = createListParagraphStyle(indent: node.indent, bulletWidth: 24)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        return result
    }

    /// 转换有序列表节点
    /// - Parameter node: 有序列表节点
    /// - Returns: NSAttributedString
    private func convertOrderedList(_ node: OrderedListNode) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // 计算实际显示编号
        // - inputNumber = 0 表示继续编号（使用上一个编号 + 1）
        // - inputNumber > 0 表示新列表起始值（实际值 = inputNumber + 1）
        let displayNumber: Int
        if node.inputNumber == 0 {
            // 继续编号
            currentOrderedListNumber += 1
            displayNumber = currentOrderedListNumber
        } else {
            // 新列表起始值
            displayNumber = node.inputNumber + 1
            currentOrderedListNumber = displayNumber
        }

        // 创建编号附件
        let orderAttachment = OrderAttachment(number: displayNumber, inputNumber: node.inputNumber, indent: node.indent)
        let attachmentString = NSAttributedString(attachment: orderAttachment)
        result.append(attachmentString)

        // 注意：不再添加空格，附件本身已有足够的间距
        // 这确保 XML 往返转换的一致性

        // 转换行内内容
        let inlineString = convertInlineNodes(node.content, inheritedAttributes: [:])
        result.append(inlineString)

        // 设置列表类型属性，以便 BlockFormatHandler.detect() 能正确检测列表格式
        // 这对于列表换行继承功能至关重要
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.listType, value: ListType.ordered, range: fullRange)
        result.addAttribute(.listIndent, value: node.indent, range: fullRange)
        result.addAttribute(.listNumber, value: displayNumber, range: fullRange)

        // 应用列表段落样式（包含行间距和段落间距）
        let paragraphStyle = createListParagraphStyle(indent: node.indent, bulletWidth: 28)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        return result
    }

    /// 转换复选框节点
    /// - Parameter node: 复选框节点
    /// - Returns: NSAttributedString
    private func convertCheckbox(_ node: CheckboxNode) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // 创建复选框附件
        let checkboxAttachment = InteractiveCheckboxAttachment(
            checked: node.isChecked,
            level: node.level,
            indent: node.indent
        )
        let attachmentString = NSAttributedString(attachment: checkboxAttachment)
        result.append(attachmentString)

        // 注意：不再添加空格，附件本身已有足够的间距
        // 这确保 XML 往返转换的一致性

        // 转换行内内容
        let inlineString = convertInlineNodes(node.content, inheritedAttributes: [:])
        result.append(inlineString)

        // 设置列表类型属性，以便 BlockFormatHandler.detect() 能正确检测列表格式
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.listType, value: ListType.checkbox, range: fullRange)
        result.addAttribute(.listIndent, value: node.indent, range: fullRange)
        result.addAttribute(.checkboxLevel, value: node.level, range: fullRange)
        result.addAttribute(.checkboxChecked, value: node.isChecked, range: fullRange)

        // 应用列表段落样式（包含行间距和段落间距）
        let paragraphStyle = createListParagraphStyle(indent: node.indent, bulletWidth: 24)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        return result
    }

    /// 转换分割线节点
    /// - Parameter node: 分割线节点
    /// - Returns: NSAttributedString
    private func convertHorizontalRule(_: HorizontalRuleNode) -> NSAttributedString {
        let hrAttachment = HorizontalRuleAttachment()
        return NSAttributedString(attachment: hrAttachment)
    }

    /// 转换图片节点
    /// - Parameter node: 图片节点
    /// - Returns: NSAttributedString
    private func convertImage(_ node: ImageNode) -> NSAttributedString {
        let imageAttachment = if let fileId = node.fileId {
            // 使用 fileId 创建附件，传递 description 和 imgshow
            ImageAttachment(
                src: "minote://image/\(fileId)",
                fileId: fileId,
                folderId: folderId,
                imageDescription: node.description,
                imgshow: node.imgshow
            )
        } else if let src = node.src {
            // 使用 src 创建附件，传递 description 和 imgshow
            ImageAttachment(
                src: src,
                fileId: nil,
                folderId: folderId,
                imageDescription: node.description,
                imgshow: node.imgshow
            )
        } else {
            // 创建占位符，传递 description 和 imgshow
            ImageAttachment(
                src: "",
                fileId: nil,
                folderId: folderId,
                imageDescription: node.description,
                imgshow: node.imgshow
            )
        }

        // 设置图片尺寸（如果有）
        if let width = node.width, let height = node.height {
            imageAttachment.displaySize = NSSize(width: CGFloat(width), height: CGFloat(height))
        }

        return NSAttributedString(attachment: imageAttachment)
    }

    /// 转换音频节点
    /// - Parameter node: 音频节点
    /// - Returns: NSAttributedString
    private func convertAudio(_ node: AudioNode) -> NSAttributedString {
        let audioAttachment = AudioAttachment(fileId: node.fileId)
        audioAttachment.isTemporaryPlaceholder = node.isTemporary
        return NSAttributedString(attachment: audioAttachment)
    }

    /// 转换引用块节点
    /// - Parameter node: 引用块节点
    /// - Returns: NSAttributedString
    private func convertQuote(_ node: QuoteNode) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for (index, textBlock) in node.textBlocks.enumerated() {
            let blockString = convertTextBlock(textBlock)
            result.append(blockString)

            // 在文本块之间添加换行符
            if index < node.textBlocks.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        // 应用引用块样式（左侧边框、背景色等）
        applyQuoteStyle(to: result)

        return result
    }

    // MARK: - Inline Conversion

    /// 将行内节点数组转换为 NSAttributedString
    ///
    /// 使用递归方式处理嵌套格式，属性会继承并累积
    ///
    /// - Parameters:
    ///   - nodes: 行内节点数组
    ///   - inheritedAttributes: 继承的属性
    /// - Returns: NSAttributedString
    private func convertInlineNodes(_ nodes: [any InlineNode], inheritedAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for node in nodes {
            let nodeString = convertInlineNode(node, inheritedAttributes: inheritedAttributes)
            result.append(nodeString)
        }

        return result
    }

    /// 转换单个行内节点
    /// - Parameters:
    ///   - node: 行内节点
    ///   - inheritedAttributes: 继承的属性
    /// - Returns: NSAttributedString
    private func convertInlineNode(_ node: any InlineNode, inheritedAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        if let textNode = node as? TextNode {
            // 纯文本节点
            convertTextNode(textNode, inheritedAttributes: inheritedAttributes)
        } else if let formattedNode = node as? FormattedNode {
            // 格式化节点
            convertFormattedNode(formattedNode, inheritedAttributes: inheritedAttributes)
        } else {
            // 不应该到达这里
            NSAttributedString()
        }
    }

    /// 转换纯文本节点
    /// - Parameters:
    ///   - node: 纯文本节点
    ///   - inheritedAttributes: 继承的属性
    /// - Returns: NSAttributedString
    private func convertTextNode(_ node: TextNode, inheritedAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        // 先从继承属性开始
        var attributes = inheritedAttributes

        // 如果没有段落样式，添加默认段落样式
        if attributes[.paragraphStyle] == nil {
            attributes[.paragraphStyle] = defaultParagraphStyle
        }

        // 处理字体属性的累积（粗体、大小、粗细）
        attributes = resolveFontAttributes(attributes)

        // 如果解析后仍然没有字体，添加默认字体
        if attributes[.font] == nil {
            attributes[.font] = defaultFont
        }

        return NSAttributedString(string: node.text, attributes: attributes)
    }

    /// 转换格式化节点
    /// - Parameters:
    ///   - node: 格式化节点
    ///   - inheritedAttributes: 继承的属性
    /// - Returns: NSAttributedString
    private func convertFormattedNode(_ node: FormattedNode, inheritedAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        // 获取当前节点的格式属性
        let formatAttributes = attributesForFormat(node)

        // 合并继承属性和当前格式属性
        var newAttributes = inheritedAttributes
        newAttributes.merge(formatAttributes) { _, new in new }

        // 递归转换子节点
        return convertInlineNodes(node.content, inheritedAttributes: newAttributes)
    }

    // MARK: - Attribute Mapping

    /// 获取默认属性
    /// - Returns: 默认属性字典
    private func getDefaultAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: defaultFont,
            .paragraphStyle: defaultParagraphStyle,
        ]
    }

    /// 获取格式节点对应的属性
    ///
    /// 根据格式类型返回对应的 NSAttributedString 属性
    /// 支持字体属性的累积（例如同时应用粗体和斜体）
    ///
    /// - Parameter node: 格式化节点
    /// - Returns: 属性字典
    private func attributesForFormat(_ node: FormattedNode) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]

        switch node.nodeType {
        case .bold:
            // 粗体：使用 bold font trait
            // 注意：这里返回一个标记，实际字体会在 applyFontTraits 中处理
            attributes[.fontTraitBold] = true

        case .italic:
            // 斜体：使用 obliqueness
            attributes[.obliqueness] = 0.2

        case .underline:
            // 下划线
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue

        case .strikethrough:
            // 删除线
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue

        case .highlight:
            // 高亮/背景色
            if let colorString = node.color {
                attributes[.backgroundColor] = parseColor(colorString)
            }

        case .heading1:
            // 大标题：使用 FontSizeConstants，常规字重（不加粗）
            attributes[.fontSize] = FontSizeConstants.heading1 // 23pt
            // 不设置 fontWeight，使用默认的 regular

        case .heading2:
            // 二级标题：使用 FontSizeConstants，常规字重（不加粗）
            attributes[.fontSize] = FontSizeConstants.heading2 // 20pt
            // 不设置 fontWeight，使用默认的 regular

        case .heading3:
            // 三级标题：使用 FontSizeConstants，常规字重（不加粗）
            attributes[.fontSize] = FontSizeConstants.heading3 // 17pt
            // 不设置 fontWeight，使用默认的 regular

        case .centerAlign:
            // 居中对齐
            attributes[.paragraphStyle] = ParagraphStyleFactory.makeDefault(alignment: .center)

        case .rightAlign:
            // 右对齐
            attributes[.paragraphStyle] = ParagraphStyleFactory.makeDefault(alignment: .right)

        default:
            break
        }

        return attributes
    }

    // MARK: - Helper Methods

    /// 从块级节点和转换结果中推断换行符应携带的属性
    ///
    /// 空标题行转换后 blockString 长度为 0，换行符需要从 AST 节点推断字体和段落样式，
    /// 否则空行会丢失标题格式
    private func resolveNewlineAttributes(for block: any BlockNode, blockString: NSAttributedString) -> [NSAttributedString.Key: Any] {
        // 优先从已转换的内容末尾继承属性
        if blockString.length > 0 {
            return blockString.attributes(at: blockString.length - 1, effectiveRange: nil)
        }

        // blockString 为空时，从 AST 节点推断（空标题行场景）
        guard let textBlock = block as? TextBlockNode else {
            return getDefaultAttributes()
        }

        // 检查是否包含标题格式节点
        let headingType = textBlock.content.compactMap { $0 as? FormattedNode }.first(where: {
            $0.nodeType == .heading1 || $0.nodeType == .heading2 || $0.nodeType == .heading3
        })?.nodeType

        guard let headingType else {
            return getDefaultAttributes()
        }

        let fontSize: CGFloat = switch headingType {
        case .heading1: FontSizeConstants.heading1
        case .heading2: FontSizeConstants.heading2
        case .heading3: FontSizeConstants.heading3
        default: FontSizeConstants.body
        }

        return [
            .font: NSFont.systemFont(ofSize: fontSize),
            .paragraphStyle: ParagraphStyleFactory.makeDefault(fontSize: fontSize),
        ]
    }

    /// 应用缩进到 NSAttributedString
    /// - Parameters:
    ///   - attributedString: 要应用缩进的字符串
    ///   - level: 缩进级别
    private func applyIndent(to attributedString: NSMutableAttributedString, level: Int) {
        let range = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttribute(.paragraphStyle, in: range) { value, subRange, _ in
            let paragraphStyle: NSMutableParagraphStyle = if let existingStyle = value as? NSParagraphStyle {
                existingStyle.mutableCopy() as! NSMutableParagraphStyle
            } else {
                NSMutableParagraphStyle()
            }

            // 每级缩进 20pt
            let indentAmount = CGFloat(level - 1) * 20
            paragraphStyle.firstLineHeadIndent = indentAmount
            paragraphStyle.headIndent = indentAmount

            attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: subRange)
        }
    }

    /// 应用引用块样式
    /// - Parameter attributedString: 要应用样式的字符串
    private func applyQuoteStyle(to attributedString: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: attributedString.length)

        // 应用引用块的段落样式
        let paragraphStyle = ParagraphStyleFactory.makeQuote()
        paragraphStyle.tailIndent = -20

        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        // 应用浅灰色文本颜色
        attributedString.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
    }

    /// 解析颜色字符串
    /// - Parameter colorString: 颜色字符串（如 "#FF0000" 或 "red"）
    /// - Returns: NSColor
    private func parseColor(_ colorString: String) -> NSColor {
        // 处理十六进制颜色
        if colorString.hasPrefix("#") {
            let hex = String(colorString.dropFirst())
            var rgb: UInt64 = 0

            Scanner(string: hex).scanHexInt64(&rgb)

            let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            let b = CGFloat(rgb & 0x0000FF) / 255.0

            return NSColor(red: r, green: g, blue: b, alpha: 1.0)
        }

        // 处理命名颜色
        switch colorString.lowercased() {
        case "red":
            return NSColor.systemRed
        case "green":
            return NSColor.systemGreen
        case "blue":
            return NSColor.systemBlue
        case "yellow":
            return NSColor.systemYellow
        case "orange":
            return NSColor.systemOrange
        case "purple":
            return NSColor.systemPurple
        case "pink":
            return NSColor.systemPink
        default:
            return NSColor.systemYellow // 默认黄色高亮
        }
    }

    /// 解析字体属性
    ///
    /// 将自定义的字体标记（粗体、大小、粗细）合并为实际的 NSFont
    ///
    /// - Parameter attributes: 属性字典
    /// - Returns: 解析后的属性字典
    private func resolveFontAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = attributes

        // 提取字体相关属性
        let isBold = attributes[.fontTraitBold] as? Bool ?? false

        // fontSize 可能是 CGFloat 或 Double
        let fontSize: CGFloat? = {
            if let size = attributes[.fontSize] as? CGFloat {
                return size
            } else if let size = attributes[.fontSize] as? Double {
                return CGFloat(size)
            }
            return nil
        }()

        let fontWeight = attributes[.fontWeight] as? NSFont.Weight

        // 如果有字体相关的自定义属性，构建新字体
        if isBold || fontSize != nil || fontWeight != nil {
            // 使用 FontSizeConstants 的默认字体大小
            let size = fontSize ?? FontSizeConstants.body
            // 只有明确设置了 fontWeight 或 isBold 时才使用粗体
            // 标题格式不再默认加粗
            let weight = fontWeight ?? (isBold ? .bold : .regular)

            let font = NSFont.systemFont(ofSize: size, weight: weight)
            result[.font] = font

            // 移除自定义属性
            result.removeValue(forKey: .fontTraitBold)
            result.removeValue(forKey: .fontSize)
            result.removeValue(forKey: .fontWeight)
        }

        return result
    }

    /// 创建列表段落样式
    ///
    /// 设置列表项的缩进、制表位、行间距和段落间距
    ///
    /// - Parameters:
    ///   - indent: 缩进级别
    ///   - bulletWidth: 项目符号宽度
    /// - Returns: 段落样式
    private func createListParagraphStyle(indent: Int, bulletWidth: CGFloat) -> NSParagraphStyle {
        ParagraphStyleFactory.makeList(indent: indent, bulletWidth: bulletWidth)
    }
}
