//
//  ListFormatHandler.swift
//  MiNoteMac
//
//  列表格式处理器 - 统一处理有序列表和无序列表的格式操作
//  负责列表的创建、切换、转换、继承和取消功能
//
//

import AppKit
import Foundation

// MARK: - 列表格式处理器

/// 列表格式处理器
/// 负责处理列表格式的应用、切换、转换和移除
@MainActor
public struct ListFormatHandler {

    // MARK: - 常量

    /// 正文字体大小 (14pt)
    /// 使用 FontSizeManager 统一管理
    public static var bodyFontSize: CGFloat {
        FontSizeManager.shared.bodySize
    }

    /// 默认字体 (14pt)
    /// 使用 FontSizeManager 统一管理
    public static var defaultFont: NSFont {
        FontSizeManager.shared.defaultFont
    }

    /// 缩进单位（像素）
    public static let indentUnit: CGFloat = 20

    /// 项目符号宽度
    public static let bulletWidth: CGFloat = 24

    /// 有序列表编号宽度
    public static let orderNumberWidth: CGFloat = 28

    /// 默认行间距（与正文一致）
    public static let defaultLineSpacing: CGFloat = 4

    /// 默认段落间距（与正文一致）
    public static let defaultParagraphSpacing: CGFloat = 8

    // MARK: - 列表应用

    /// 应用无序列表格式
    ///
    /// 在行首插入 BulletAttachment，设置列表类型属性
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - indent: 缩进级别（默认为 1）
    public static func applyBulletList(
        to textStorage: NSTextStorage,
        range: NSRange,
        indent: Int = 1
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        // 先处理列表与标题的互斥（会保留字体特性如加粗、斜体）
        handleListHeadingMutualExclusion(in: textStorage, range: lineRange)

        textStorage.beginEditing()

        // 创建 BulletAttachment
        let bulletAttachment = BulletAttachment(indent: indent)
        let attachmentString = NSAttributedString(attachment: bulletAttachment)

        // 在行首插入附件
        let lineStart = lineRange.location
        textStorage.insert(attachmentString, at: lineStart)

        // 更新行范围（因为插入了附件）
        let newLineRange = NSRange(location: lineStart, length: lineRange.length + 1)

        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.bullet, range: newLineRange)
        textStorage.addAttribute(.listIndent, value: indent, range: newLineRange)

        // 设置段落样式
        let paragraphStyle = createListParagraphStyle(indent: indent, bulletWidth: bulletWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)

        // 确保使用正文字体大小，但保留字体特性（加粗、斜体等）
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
    public static func applyOrderedList(
        to textStorage: NSTextStorage,
        range: NSRange,
        number: Int = 1,
        indent: Int = 1
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        // 先处理列表与标题的互斥（会保留字体特性如加粗、斜体）
        handleListHeadingMutualExclusion(in: textStorage, range: lineRange)

        textStorage.beginEditing()

        // 创建 OrderAttachment
        let orderAttachment = OrderAttachment(number: number, inputNumber: 0, indent: indent)
        let attachmentString = NSAttributedString(attachment: orderAttachment)

        // 在行首插入附件
        let lineStart = lineRange.location
        textStorage.insert(attachmentString, at: lineStart)

        // 更新行范围（因为插入了附件）
        let newLineRange = NSRange(location: lineStart, length: lineRange.length + 1)

        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.ordered, range: newLineRange)
        textStorage.addAttribute(.listIndent, value: indent, range: newLineRange)
        textStorage.addAttribute(.listNumber, value: number, range: newLineRange)

        // 设置段落样式
        let paragraphStyle = createListParagraphStyle(indent: indent, bulletWidth: orderNumberWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)

        // 确保使用正文字体大小，但保留字体特性（加粗、斜体等）
        applyBodyFontSizePreservingTraits(to: textStorage, range: newLineRange)

        textStorage.endEditing()
    }

    // MARK: - 复选框列表应用

    /// 复选框宽度
    public static let checkboxWidth: CGFloat = 24

    /// 应用复选框列表格式
    ///
    /// 在行首插入 InteractiveCheckboxAttachment，设置列表类型属性
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - indent: 缩进级别（默认为 1）
    ///   - level: 复选框级别（默认为 3，对应 XML 中的 level 属性）
    public static func applyCheckboxList(
        to textStorage: NSTextStorage,
        range: NSRange,
        indent: Int = 1,
        level: Int = 3
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        // 先处理列表与标题的互斥（会保留字体特性如加粗、斜体）
        handleListHeadingMutualExclusion(in: textStorage, range: lineRange)

        textStorage.beginEditing()

        // 创建 InteractiveCheckboxAttachment（默认未勾选）
        let checkboxAttachment = InteractiveCheckboxAttachment(checked: false, level: level, indent: indent)
        let attachmentString = NSAttributedString(attachment: checkboxAttachment)

        // 在行首插入附件
        let lineStart = lineRange.location
        textStorage.insert(attachmentString, at: lineStart)

        // 更新行范围（因为插入了附件）
        let newLineRange = NSRange(location: lineStart, length: lineRange.length + 1)

        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.checkbox, range: newLineRange)
        textStorage.addAttribute(.listIndent, value: indent, range: newLineRange)
        textStorage.addAttribute(.checkboxLevel, value: level, range: newLineRange)
        textStorage.addAttribute(.checkboxChecked, value: false, range: newLineRange)

        // 设置段落样式
        let paragraphStyle = createListParagraphStyle(indent: indent, bulletWidth: checkboxWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)

        // 确保使用正文字体大小，但保留字体特性（加粗、斜体等）
        applyBodyFontSizePreservingTraits(to: textStorage, range: newLineRange)

        textStorage.endEditing()
    }

    /// 移除复选框列表格式
    ///
    /// 移除复选框附件和列表类型属性，保留文本内容
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    public static func removeCheckboxList(
        from textStorage: NSTextStorage,
        range: NSRange
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        textStorage.beginEditing()

        // 查找并移除复选框附件
        var attachmentRange: NSRange?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if value is InteractiveCheckboxAttachment {
                attachmentRange = attrRange
                stop.pointee = true
            }
        }

        // 移除附件
        if let range = attachmentRange {
            textStorage.deleteCharacters(in: range)
        }

        // 重新计算行范围（因为可能删除了附件）
        let newLineRange: NSRange = if let range = attachmentRange {
            NSRange(location: lineRange.location, length: lineRange.length - range.length)
        } else {
            lineRange
        }

        // 移除列表相关属性
        if newLineRange.length > 0 {
            textStorage.removeAttribute(.listType, range: newLineRange)
            textStorage.removeAttribute(.listIndent, range: newLineRange)
            textStorage.removeAttribute(.checkboxLevel, range: newLineRange)
            textStorage.removeAttribute(.checkboxChecked, range: newLineRange)

            // 重置段落样式
            let paragraphStyle = NSMutableParagraphStyle()
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)
        }

        textStorage.endEditing()
    }

    /// 切换复选框列表格式
    ///
    /// 如果当前行是复选框列表，则移除；否则应用复选框列表
    /// 如果当前行是有序/无序列表，则转换为复选框列表
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    public static func toggleCheckboxList(
        to textStorage: NSTextStorage,
        range: NSRange
    ) {
        let currentType = detectListType(in: textStorage, at: range.location)

        switch currentType {
        case .checkbox:
            removeCheckboxList(from: textStorage, range: range)
        case .bullet, .ordered:
            removeListFormat(from: textStorage, range: range)
            applyCheckboxList(to: textStorage, range: range)
        case .none:
            applyCheckboxList(to: textStorage, range: range)
        }
    }

    // MARK: - 列表移除

    /// 移除列表格式
    ///
    /// 移除列表附件和列表类型属性，保留文本内容
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    public static func removeListFormat(
        from textStorage: NSTextStorage,
        range: NSRange
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        textStorage.beginEditing()

        // 查找并移除列表附件（包括复选框附件）
        var attachmentRange: NSRange?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if value is BulletAttachment || value is OrderAttachment || value is InteractiveCheckboxAttachment {
                attachmentRange = attrRange
                stop.pointee = true
            }
        }

        // 移除附件
        if let range = attachmentRange {
            textStorage.deleteCharacters(in: range)
        }

        // 重新计算行范围（因为可能删除了附件）
        let newLineRange: NSRange = if let range = attachmentRange {
            NSRange(location: lineRange.location, length: lineRange.length - range.length)
        } else {
            lineRange
        }

        // 移除列表相关属性
        if newLineRange.length > 0 {
            textStorage.removeAttribute(.listType, range: newLineRange)
            textStorage.removeAttribute(.listIndent, range: newLineRange)
            textStorage.removeAttribute(.listNumber, range: newLineRange)
            textStorage.removeAttribute(.checkboxLevel, range: newLineRange)
            textStorage.removeAttribute(.checkboxChecked, range: newLineRange)

            // 重置段落样式
            let paragraphStyle = NSMutableParagraphStyle()
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)
        }

        textStorage.endEditing()
    }

    // MARK: - 列表切换

    /// 切换无序列表格式
    ///
    /// 如果当前行是无序列表，则移除；否则应用无序列表
    /// 如果当前行是有序列表，则转换为无序列表
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    public static func toggleBulletList(
        to textStorage: NSTextStorage,
        range: NSRange
    ) {
        let currentType = detectListType(in: textStorage, at: range.location)

        switch currentType {
        case .bullet:
            removeListFormat(from: textStorage, range: range)
        case .ordered:
            convertListType(in: textStorage, range: range, to: .bullet)
        case .checkbox:
            removeListFormat(from: textStorage, range: range)
            applyBulletList(to: textStorage, range: range)
        case .none:
            applyBulletList(to: textStorage, range: range)
        }
    }

    /// 切换有序列表格式
    ///
    /// 如果当前行是有序列表，则移除；否则应用有序列表
    /// 如果当前行是无序列表，则转换为有序列表
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    public static func toggleOrderedList(
        to textStorage: NSTextStorage,
        range: NSRange
    ) {
        let currentType = detectListType(in: textStorage, at: range.location)

        switch currentType {
        case .ordered:
            removeListFormat(from: textStorage, range: range)
        case .bullet:
            convertListType(in: textStorage, range: range, to: .ordered)
        case .checkbox:
            removeListFormat(from: textStorage, range: range)
            let number = calculateListNumber(in: textStorage, at: range.location)
            applyOrderedList(to: textStorage, range: range, number: number)
        case .none:
            let number = calculateListNumber(in: textStorage, at: range.location)
            applyOrderedList(to: textStorage, range: range, number: number)
        }
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
    public static func convertListType(
        in textStorage: NSTextStorage,
        range: NSRange,
        to targetType: ListType
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        // 获取当前缩进级别
        let currentIndent = getListIndent(in: textStorage, at: lineRange.location)

        textStorage.beginEditing()

        // 查找并替换列表附件
        var attachmentRange: NSRange?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if value is BulletAttachment || value is OrderAttachment {
                attachmentRange = attrRange
                stop.pointee = true
            }
        }

        // 移除旧附件
        if let range = attachmentRange {
            textStorage.deleteCharacters(in: range)
        }

        // 创建新附件
        let newAttachment: NSTextAttachment
        let newBulletWidth: CGFloat

        switch targetType {
        case .bullet:
            newAttachment = BulletAttachment(indent: currentIndent)
            newBulletWidth = bulletWidth
        case .ordered:
            let number = calculateListNumber(in: textStorage, at: lineRange.location)
            newAttachment = OrderAttachment(number: number, inputNumber: 0, indent: currentIndent)
            newBulletWidth = orderNumberWidth
        default:
            textStorage.endEditing()
            return
        }

        // 插入新附件
        let attachmentString = NSAttributedString(attachment: newAttachment)
        textStorage.insert(attachmentString, at: lineRange.location)

        // 更新行范围
        let newLineRange = NSRange(location: lineRange.location, length: lineRange.length + 1 - (attachmentRange?.length ?? 0))

        // 更新列表类型属性
        textStorage.addAttribute(.listType, value: targetType, range: newLineRange)
        textStorage.addAttribute(.listIndent, value: currentIndent, range: newLineRange)

        if targetType == .ordered {
            let number = calculateListNumber(in: textStorage, at: lineRange.location)
            textStorage.addAttribute(.listNumber, value: number, range: newLineRange)
        } else {
            textStorage.removeAttribute(.listNumber, range: newLineRange)
        }

        // 更新段落样式
        let paragraphStyle = createListParagraphStyle(indent: currentIndent, bulletWidth: newBulletWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)

        textStorage.endEditing()
    }

    // MARK: - 格式互斥处理

    /// 处理列表与标题的互斥
    ///
    /// 应用列表格式时先移除标题格式，确保列表行使用正文字体大小（14pt）
    /// 此方法会：
    /// 1. 检测当前行是否有标题格式
    /// 2. 如果有标题格式，将字体大小重置为正文大小（14pt）
    /// 3. 保留其他字体特性（如加粗、斜体）
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围（应该是整行范围）
    public static func handleListHeadingMutualExclusion(
        in textStorage: NSTextStorage,
        range: NSRange
    ) {
        guard range.length > 0 else { return }

        // 检测当前是否有标题格式
        let headingLevel = detectHeadingLevel(in: textStorage, at: range.location)

        if headingLevel > 0 {
            // 有标题格式，需要移除它并应用正文字体大小
            // 遍历范围内的所有字体属性，保留字体特性（加粗、斜体等），只修改字体大小
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                if let currentFont = value as? NSFont {
                    // 获取当前字体的特性
                    let traits = currentFont.fontDescriptor.symbolicTraits

                    // 创建新字体，保留特性但使用正文大小
                    let newFont: NSFont
                    if traits.isEmpty {
                        newFont = defaultFont
                    } else {
                        let descriptor = NSFont.systemFont(ofSize: bodyFontSize, weight: .regular).fontDescriptor.withSymbolicTraits(traits)
                        newFont = NSFont(descriptor: descriptor, size: bodyFontSize) ?? defaultFont
                    }

                    textStorage.addAttribute(.font, value: newFont, range: attrRange)
                } else {
                    // 没有字体属性，设置默认字体
                    textStorage.addAttribute(.font, value: defaultFont, range: attrRange)
                }
            }


        }
    }

    /// 处理标题与列表的互斥（供 BlockFormatHandler 调用）
    ///
    /// 应用标题格式时先移除列表格式
    /// 此方法会：
    /// 1. 检测当前行是否有列表格式
    /// 2. 如果有列表格式，移除列表附件和列表属性
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围（应该是整行范围）
    /// - Returns: 是否移除了列表格式
    @discardableResult
    public static func handleHeadingListMutualExclusion(
        in textStorage: NSTextStorage,
        range: NSRange
    ) -> Bool {
        // 检测当前是否有列表格式
        let listType = detectListType(in: textStorage, at: range.location)

        if listType != .none {
            // 有列表格式，移除它
            removeListFormat(from: textStorage, range: range)
            return true
        }

        return false
    }

    // MARK: - 列表检测

    /// 检测当前行的列表类型
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 光标位置
    /// - Returns: 列表类型
    public static func detectListType(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> ListType {
        guard position >= 0, position < textStorage.length else {
            return .none
        }

        // 获取当前行范围
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))

        // 检查行首是否有列表附件
        var foundType: ListType = .none
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, stop in
            if value is BulletAttachment {
                foundType = .bullet
                stop.pointee = true
            } else if value is OrderAttachment {
                foundType = .ordered
                stop.pointee = true
            } else if value is InteractiveCheckboxAttachment {
                foundType = .checkbox
                stop.pointee = true
            }
        }

        // 如果没有找到附件，检查 listType 属性
        if foundType == .none {
            if let listType = textStorage.attribute(.listType, at: lineRange.location, effectiveRange: nil) as? ListType {
                foundType = listType
            }
        }

        return foundType
    }

    /// 检测当前行是否为空列表项
    ///
    /// 空列表项定义：只包含列表附件，没有实际文本内容
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 光标位置
    /// - Returns: 是否为空列表项
    public static func isEmptyListItem(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool {
        guard position >= 0, position <= textStorage.length else {
            return false
        }

        // 检测是否是列表
        let listType = detectListType(in: textStorage, at: position)
        guard listType != .none else {
            return false
        }

        // 获取当前行范围
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))

        // 获取行内容
        let lineContent = string.substring(with: lineRange)

        // 移除换行符
        let trimmedContent = lineContent.trimmingCharacters(in: .newlines)

        // 检查是否只有附件字符（Unicode 对象替换字符 \u{FFFC}）
        let contentWithoutAttachment = trimmedContent.replacingOccurrences(of: "\u{FFFC}", with: "")

        // 空列表项：移除附件后内容为空或只有空白字符
        return contentWithoutAttachment.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 辅助方法 - 标题检测

    /// 检测标题级别
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 标题级别（0 = 无标题，1-3 = 标题级别）
    private static func detectHeadingLevel(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Int {
        guard position >= 0, position < textStorage.length else {
            return 0
        }

        if let font = textStorage.attribute(.font, at: position, effectiveRange: nil) as? NSFont {
            return FontSizeManager.shared.detectHeadingLevel(fontSize: font.pointSize)
        }

        return 0
    }

    // MARK: - 辅助方法 - 列表属性获取

    /// 获取列表缩进级别
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 缩进级别（默认为 1）
    public static func getListIndent(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Int {
        guard position >= 0, position < textStorage.length else {
            return 1
        }

        if let indent = textStorage.attribute(.listIndent, at: position, effectiveRange: nil) as? Int {
            return indent
        }

        return 1
    }

    /// 获取列表编号
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 列表编号（默认为 1）
    public static func getListNumber(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Int {
        guard position >= 0, position < textStorage.length else {
            return 1
        }

        if let number = textStorage.attribute(.listNumber, at: position, effectiveRange: nil) as? Int {
            return number
        }

        return 1
    }

    /// 计算列表编号
    ///
    /// 向上查找同级别的有序列表项，计算当前项的编号
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 计算出的列表编号
    public static func calculateListNumber(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Int {
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))

        // 向上查找同级别的有序列表项
        var number = 1
        var searchPosition = lineRange.location
        let currentIndent = getListIndent(in: textStorage, at: position)

        while searchPosition > 0 {
            // 获取上一行的范围
            let prevLineEnd = searchPosition - 1
            let prevLineRange = string.lineRange(for: NSRange(location: prevLineEnd, length: 0))

            // 检查上一行是否是有序列表
            if prevLineRange.location < textStorage.length {
                let prevListType = detectListType(in: textStorage, at: prevLineRange.location)
                let prevIndent = getListIndent(in: textStorage, at: prevLineRange.location)

                if prevListType == .ordered && prevIndent == currentIndent {
                    // 找到同级别的有序列表项，编号加 1
                    let prevNumber = getListNumber(in: textStorage, at: prevLineRange.location)
                    number = prevNumber + 1
                    break
                } else if prevListType == .none || prevIndent < currentIndent {
                    // 遇到非列表或更低级别的缩进，停止搜索
                    break
                }
                // 如果是更高级别的缩进，继续向上搜索
            }

            searchPosition = prevLineRange.location
        }

        return number
    }

    // MARK: - 辅助方法 - 段落样式

    /// 创建列表段落样式
    ///
    /// - Parameters:
    ///   - indent: 缩进级别
    ///   - bulletWidth: 项目符号宽度
    /// - Returns: 段落样式
    private static func createListParagraphStyle(indent: Int, bulletWidth: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let baseIndent = CGFloat(indent - 1) * indentUnit

        // 设置首行缩进（为项目符号留出空间）
        style.firstLineHeadIndent = baseIndent
        // 设置后续行缩进（与项目符号后的文本对齐）
        style.headIndent = baseIndent + bulletWidth
        // 设置制表位
        style.tabStops = [NSTextTab(textAlignment: .left, location: baseIndent + bulletWidth)]
        style.defaultTabInterval = indentUnit

        // 设置行间距和段落间距（与正文一致）
        style.lineSpacing = defaultLineSpacing
        style.paragraphSpacing = defaultParagraphSpacing

        return style
    }

    // MARK: - 辅助方法 - 字体处理

    /// 应用正文字体大小，同时保留字体特性（加粗、斜体等）
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    private static func applyBodyFontSizePreservingTraits(
        to textStorage: NSTextStorage,
        range: NSRange
    ) {
        guard range.length > 0 else { return }

        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            if let currentFont = value as? NSFont {
                // 获取当前字体的特性
                let traits = currentFont.fontDescriptor.symbolicTraits

                // 如果字体大小已经是正文大小，且没有特性需要保留，跳过
                if abs(currentFont.pointSize - bodyFontSize) < 0.1, traits.isEmpty {
                    return
                }

                // 创建新字体，保留特性但使用正文大小
                let newFont: NSFont
                if traits.isEmpty {
                    newFont = defaultFont
                } else {
                    let descriptor = NSFont.systemFont(ofSize: bodyFontSize, weight: .regular).fontDescriptor.withSymbolicTraits(traits)
                    newFont = NSFont(descriptor: descriptor, size: bodyFontSize) ?? defaultFont
                }

                textStorage.addAttribute(.font, value: newFont, range: attrRange)
            } else {
                // 没有字体属性，设置默认字体
                textStorage.addAttribute(.font, value: defaultFont, range: attrRange)
            }
        }
    }
}
