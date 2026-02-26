import AppKit
import Foundation

// MARK: - 列表格式操作

public extension ParagraphManager {

    // MARK: - 常量

    /// 正文字体大小
    private static var bodyFontSize: CGFloat {
        FontSizeConstants.body
    }

    /// 默认字体
    private nonisolated(unsafe) static let defaultFont = NSFont.systemFont(ofSize: FontSizeConstants.body, weight: .regular)

    // MARK: - 列表应用

    /// 应用无序列表格式
    ///
    /// 在行首插入 BulletAttachment，设置列表类型属性
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - indent: 缩进级别（默认为 1）
    static func applyBulletList(
        to textStorage: NSTextStorage,
        range: NSRange,
        indent: Int = 1
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        handleListHeadingMutualExclusion(in: textStorage, range: lineRange)

        textStorage.beginEditing()

        let bulletAttachment = BulletAttachment(indent: indent)
        let attachmentString = NSAttributedString(attachment: bulletAttachment)

        let lineStart = lineRange.location
        textStorage.insert(attachmentString, at: lineStart)

        let newLineRange = NSRange(location: lineStart, length: lineRange.length + 1)

        textStorage.addAttribute(.listType, value: ListType.bullet, range: newLineRange)
        textStorage.addAttribute(.listIndent, value: indent, range: newLineRange)

        let paragraphStyle = ParagraphStyleFactory.makeList(
            indent: indent,
            bulletWidth: ParagraphStyleFactory.bulletWidth
        )
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)

        applyBodyFontSizePreservingTraits(to: textStorage, range: newLineRange)

        textStorage.endEditing()
    }

    /// 应用有序列表格式
    ///
    /// 在行首插入 OrderAttachment，设置列表类型属性
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - number: 起始编号（默认为 1）
    ///   - indent: 缩进级别（默认为 1）
    static func applyOrderedList(
        to textStorage: NSTextStorage,
        range: NSRange,
        number: Int = 1,
        indent: Int = 1
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        handleListHeadingMutualExclusion(in: textStorage, range: lineRange)

        textStorage.beginEditing()

        let orderAttachment = OrderAttachment(number: number, inputNumber: 0, indent: indent)
        let attachmentString = NSAttributedString(attachment: orderAttachment)

        let lineStart = lineRange.location
        textStorage.insert(attachmentString, at: lineStart)

        let newLineRange = NSRange(location: lineStart, length: lineRange.length + 1)

        textStorage.addAttribute(.listType, value: ListType.ordered, range: newLineRange)
        textStorage.addAttribute(.listIndent, value: indent, range: newLineRange)
        textStorage.addAttribute(.listNumber, value: number, range: newLineRange)

        let paragraphStyle = ParagraphStyleFactory.makeList(
            indent: indent,
            bulletWidth: ParagraphStyleFactory.orderNumberWidth
        )
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)

        applyBodyFontSizePreservingTraits(to: textStorage, range: newLineRange)

        textStorage.endEditing()
    }

    /// 应用复选框列表格式
    ///
    /// 在行首插入 InteractiveCheckboxAttachment，设置列表类型属性
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - indent: 缩进级别（默认为 1）
    ///   - level: 复选框级别（默认为 3）
    static func applyCheckboxList(
        to textStorage: NSTextStorage,
        range: NSRange,
        indent: Int = 1,
        level: Int = 3
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        handleListHeadingMutualExclusion(in: textStorage, range: lineRange)

        textStorage.beginEditing()

        let checkboxAttachment = InteractiveCheckboxAttachment(checked: false, level: level, indent: indent)
        let attachmentString = NSAttributedString(attachment: checkboxAttachment)

        let lineStart = lineRange.location
        textStorage.insert(attachmentString, at: lineStart)

        let newLineRange = NSRange(location: lineStart, length: lineRange.length + 1)

        textStorage.addAttribute(.listType, value: ListType.checkbox, range: newLineRange)
        textStorage.addAttribute(.listIndent, value: indent, range: newLineRange)
        textStorage.addAttribute(.checkboxLevel, value: level, range: newLineRange)
        textStorage.addAttribute(.checkboxChecked, value: false, range: newLineRange)

        let paragraphStyle = ParagraphStyleFactory.makeList(
            indent: indent,
            bulletWidth: ParagraphStyleFactory.bulletWidth
        )
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)

        applyBodyFontSizePreservingTraits(to: textStorage, range: newLineRange)

        textStorage.endEditing()
    }

    // MARK: - 列表移除

    /// 移除列表格式
    ///
    /// 移除列表附件和列表类型属性，保留文本内容
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    static func removeListFormat(
        from textStorage: NSTextStorage,
        range: NSRange
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        textStorage.beginEditing()

        // 查找并移除列表附件
        var attachmentRange: NSRange?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if value is BulletAttachment || value is OrderAttachment || value is InteractiveCheckboxAttachment {
                attachmentRange = attrRange
                stop.pointee = true
            }
        }

        if let range = attachmentRange {
            textStorage.deleteCharacters(in: range)
        }

        // 重新计算行范围
        let newLineRange: NSRange = if let range = attachmentRange {
            NSRange(location: lineRange.location, length: lineRange.length - range.length)
        } else {
            lineRange
        }

        if newLineRange.length > 0 {
            textStorage.removeAttribute(.listType, range: newLineRange)
            textStorage.removeAttribute(.listIndent, range: newLineRange)
            textStorage.removeAttribute(.listNumber, range: newLineRange)
            textStorage.removeAttribute(.checkboxLevel, range: newLineRange)
            textStorage.removeAttribute(.checkboxChecked, range: newLineRange)

            let paragraphStyle = ParagraphStyleFactory.makeDefault()
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)
        }

        textStorage.endEditing()
    }

    // MARK: - 列表类型转换

    /// 转换列表类型
    ///
    /// 在有序/无序列表之间转换，保留文本内容和缩进级别
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - targetType: 目标列表类型
    static func convertListType(
        in textStorage: NSTextStorage,
        range: NSRange,
        to targetType: ListType
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        let currentIndent = getListIndent(at: lineRange.location, in: textStorage)

        textStorage.beginEditing()

        // 查找并移除旧附件
        var attachmentRange: NSRange?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if value is BulletAttachment || value is OrderAttachment {
                attachmentRange = attrRange
                stop.pointee = true
            }
        }

        if let range = attachmentRange {
            textStorage.deleteCharacters(in: range)
        }

        // 创建新附件
        let newAttachment: NSTextAttachment
        let newBulletWidth: CGFloat

        switch targetType {
        case .bullet:
            newAttachment = BulletAttachment(indent: currentIndent)
            newBulletWidth = ParagraphStyleFactory.bulletWidth
        case .ordered:
            let number = calculateListNumber(at: lineRange.location, in: textStorage)
            newAttachment = OrderAttachment(number: number, inputNumber: 0, indent: currentIndent)
            newBulletWidth = ParagraphStyleFactory.orderNumberWidth
        default:
            textStorage.endEditing()
            return
        }

        let attachmentString = NSAttributedString(attachment: newAttachment)
        textStorage.insert(attachmentString, at: lineRange.location)

        let newLineRange = NSRange(
            location: lineRange.location,
            length: lineRange.length + 1 - (attachmentRange?.length ?? 0)
        )

        textStorage.addAttribute(.listType, value: targetType, range: newLineRange)
        textStorage.addAttribute(.listIndent, value: currentIndent, range: newLineRange)

        if targetType == .ordered {
            let number = calculateListNumber(at: lineRange.location, in: textStorage)
            textStorage.addAttribute(.listNumber, value: number, range: newLineRange)
        } else {
            textStorage.removeAttribute(.listNumber, range: newLineRange)
        }

        let paragraphStyle = ParagraphStyleFactory.makeList(indent: currentIndent, bulletWidth: newBulletWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)

        textStorage.endEditing()
    }

    // MARK: - 格式互斥处理

    /// 处理列表与标题的互斥
    ///
    /// 应用列表格式时，检测并移除标题格式，将字体大小重置为正文大小（14pt），
    /// 同时保留加粗、斜体等字体特性
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围（应该是整行范围）
    static func handleListHeadingMutualExclusion(
        in textStorage: NSTextStorage,
        range: NSRange
    ) {
        guard range.length > 0 else { return }

        // 检测是否有标题格式
        guard range.location < textStorage.length else { return }
        if let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
            let format = FontSizeConstants.detectParagraphFormat(fontSize: font.pointSize)
            guard format != .body else { return }
        } else {
            return
        }

        // 有标题格式，重置字体大小但保留特性
        applyBodyFontSizePreservingTraits(to: textStorage, range: range)
    }

    /// 应用正文字体大小，同时保留字体特性（加粗、斜体等）
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    static func applyBodyFontSizePreservingTraits(
        to textStorage: NSTextStorage,
        range: NSRange
    ) {
        guard range.length > 0 else { return }

        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            if let currentFont = value as? NSFont {
                let traits = currentFont.fontDescriptor.symbolicTraits

                if abs(currentFont.pointSize - bodyFontSize) < 0.1, traits.isEmpty {
                    return
                }

                let newFont: NSFont
                if traits.isEmpty {
                    newFont = defaultFont
                } else {
                    let descriptor = NSFont.systemFont(ofSize: bodyFontSize, weight: .regular)
                        .fontDescriptor.withSymbolicTraits(traits)
                    newFont = NSFont(descriptor: descriptor, size: bodyFontSize) ?? defaultFont
                }

                textStorage.addAttribute(.font, value: newFont, range: attrRange)
            } else {
                textStorage.addAttribute(.font, value: defaultFont, range: attrRange)
            }
        }
    }
}
