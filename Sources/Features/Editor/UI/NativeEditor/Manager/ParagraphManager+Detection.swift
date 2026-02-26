import AppKit
import Foundation

// MARK: - 格式检测方法

public extension ParagraphManager {

    /// 检测指定位置的段落格式
    ///
    /// 检测优先级：
    /// 1. 行首列表附件（BulletAttachment / OrderAttachment / InteractiveCheckboxAttachment）
    /// 2. listType 属性（备用）
    /// 3. quoteBlock 属性
    /// 4. 基于字体大小检测标题（FontSizeConstants.detectParagraphFormat）
    /// 5. 以上都不匹配 → 返回 .body
    ///
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 段落格式
    static func detectParagraphFormat(
        at position: Int,
        in textStorage: NSTextStorage
    ) -> ParagraphFormat {
        guard position >= 0, position < textStorage.length else {
            return .body
        }

        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))

        // 1. 检查行首列表附件
        var listAttachmentType: ListType?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, stop in
            if value is BulletAttachment {
                listAttachmentType = .bullet
                stop.pointee = true
            } else if value is OrderAttachment {
                listAttachmentType = .ordered
                stop.pointee = true
            } else if value is InteractiveCheckboxAttachment {
                listAttachmentType = .checkbox
                stop.pointee = true
            }
        }

        if let listType = listAttachmentType {
            switch listType {
            case .bullet: return .bulletList
            case .ordered: return .numberedList
            case .checkbox: return .checkbox
            case .none: break
            }
        }

        let attributes = textStorage.attributes(at: lineRange.location, effectiveRange: nil)

        // 2. 检查 listType 属性（备用）
        if let listType = attributes[.listType] as? ListType {
            switch listType {
            case .bullet: return .bulletList
            case .ordered: return .numberedList
            case .checkbox: return .checkbox
            case .none: break
            }
        }

        // 3. 检查 quoteBlock 属性
        if let isQuote = attributes[.quoteBlock] as? Bool, isQuote {
            // 引用在 ParagraphFormat 中没有对应值，返回 .body
            // 引用状态通过 FormatState.isQuote 单独跟踪
            return .body
        }

        // 4. 基于字体大小检测标题
        if let font = attributes[.font] as? NSFont {
            let format = FontSizeConstants.detectParagraphFormat(fontSize: font.pointSize)
            if format != .body {
                return format
            }
        }

        // 5. 默认返回正文
        return .body
    }

    /// 检测指定位置的对齐方式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 对齐格式
    static func detectAlignment(
        at position: Int,
        in textStorage: NSTextStorage
    ) -> AlignmentFormat {
        guard position >= 0, position < textStorage.length else {
            return .left
        }

        let attributes = textStorage.attributes(at: position, effectiveRange: nil)

        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            switch paragraphStyle.alignment {
            case .center: return .center
            case .right: return .right
            default: return .left
            }
        }

        return .left
    }

    /// 检测当前行的列表类型
    ///
    /// - Parameters:
    ///   - position: 光标位置
    ///   - textStorage: 文本存储
    /// - Returns: 列表类型
    static func detectListType(
        at position: Int,
        in textStorage: NSTextStorage
    ) -> ListType {
        guard position >= 0, position < textStorage.length else {
            return .none
        }

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

    /// 检测列表项是否为空
    ///
    /// 空列表项定义：只包含列表附件，没有实际文本内容
    ///
    /// - Parameters:
    ///   - position: 光标位置
    ///   - textStorage: 文本存储
    /// - Returns: 是否为空列表项
    static func isListItemEmpty(
        at position: Int,
        in textStorage: NSTextStorage
    ) -> Bool {
        guard position >= 0, position <= textStorage.length else {
            return false
        }

        let string = textStorage.string as NSString

        // 处理光标在文档末尾或换行符位置的情况
        let safePosition: Int
        if position >= textStorage.length, textStorage.length > 0 {
            safePosition = textStorage.length - 1
        } else if position > 0, position < textStorage.length {
            let charAtPosition = string.character(at: position)
            if charAtPosition == 0x0A {
                safePosition = position - 1
            } else {
                safePosition = position
            }
        } else {
            safePosition = max(0, min(position, textStorage.length - 1))
        }

        let lineRange = string.lineRange(for: NSRange(location: safePosition, length: 0))
        guard lineRange.length > 0 else { return false }

        // 检查整行是否有列表格式或列表附件
        var hasListFormat = false
        var hasListAttachment = false

        textStorage.enumerateAttributes(in: lineRange, options: []) { attrs, _, _ in
            if let listType = attrs[.listType] as? ListType, listType != .none {
                hasListFormat = true
            }
            if let attachment = attrs[.attachment] {
                if attachment is BulletAttachment || attachment is OrderAttachment || attachment is InteractiveCheckboxAttachment {
                    hasListAttachment = true
                }
            }
        }

        guard hasListFormat || hasListAttachment else { return false }

        // 获取行内容，移除附件字符后检查是否为空
        let lineContent = string.substring(with: lineRange)
        let trimmedContent = lineContent.trimmingCharacters(in: .newlines)
        let contentWithoutAttachment = trimmedContent.replacingOccurrences(of: "\u{FFFC}", with: "")

        return contentWithoutAttachment.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 获取列表缩进级别
    ///
    /// - Parameters:
    ///   - position: 位置
    ///   - textStorage: 文本存储
    /// - Returns: 缩进级别（默认为 1）
    static func getListIndent(
        at position: Int,
        in textStorage: NSTextStorage
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
    ///   - position: 位置
    ///   - textStorage: 文本存储
    /// - Returns: 列表编号（默认为 1）
    static func getListNumber(
        at position: Int,
        in textStorage: NSTextStorage
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
    ///   - position: 位置
    ///   - textStorage: 文本存储
    /// - Returns: 计算出的列表编号
    static func calculateListNumber(
        at position: Int,
        in textStorage: NSTextStorage
    ) -> Int {
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))

        var number = 1
        var searchPosition = lineRange.location
        let currentIndent = getListIndent(at: position, in: textStorage)

        while searchPosition > 0 {
            let prevLineEnd = searchPosition - 1
            let prevLineRange = string.lineRange(for: NSRange(location: prevLineEnd, length: 0))

            if prevLineRange.location < textStorage.length {
                let prevListType = detectListType(at: prevLineRange.location, in: textStorage)
                let prevIndent = getListIndent(at: prevLineRange.location, in: textStorage)

                if prevListType == .ordered, prevIndent == currentIndent {
                    let prevNumber = getListNumber(at: prevLineRange.location, in: textStorage)
                    number = prevNumber + 1
                    break
                } else if prevListType == .none || prevIndent < currentIndent {
                    break
                }
            }

            searchPosition = prevLineRange.location
        }

        return number
    }

    /// 检测指定位置是否为引用格式
    internal static func isQuoteFormat(at position: Int, in textStorage: NSTextStorage) -> Bool {
        guard position >= 0, position < textStorage.length else { return false }
        let attrs = textStorage.attributes(at: position, effectiveRange: nil)
        return (attrs[.quoteBlock] as? Bool) == true
    }

    /// 检测当前段落的 ParagraphType（内部使用，包含引用检测）
    internal static func detectCurrentParagraphType(at position: Int, in textStorage: NSTextStorage) -> ParagraphType {
        // 先检测引用（因为 detectParagraphFormat 对引用返回 .body）
        if isQuoteFormat(at: position, in: textStorage) {
            return .quote
        }

        let format = detectParagraphFormat(at: position, in: textStorage)
        return format.paragraphType
    }
}

// MARK: - Toggle 入口

extension ParagraphManager {

    /// 段落格式 toggle 统一入口
    ///
    /// Toggle 语义：
    /// 1. 当前格式 == 目标格式 → 移除格式，恢复正文
    /// 2. 当前格式 != 目标格式 → 先移除旧格式，再应用新格式
    /// 3. 当前是正文 → 直接应用目标格式
    /// 4. 处理标题 <-> 列表互斥规则
    ///
    /// - Parameters:
    ///   - type: 目标段落类型
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    public func toggleParagraphFormat(
        _ type: ParagraphType,
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        let currentType = Self.detectCurrentParagraphType(at: lineRange.location, in: textStorage)

        // 当前格式 == 目标格式 → 移除，恢复正文
        if currentType == type {
            Self.removeBlockFormat(from: lineRange, in: textStorage)
            return
        }

        // 当前不是正文 → 先移除旧格式
        if currentType != .normal {
            Self.removeBlockFormat(from: lineRange, in: textStorage)
            // removeBlockFormat 可能改变了文本长度（移除列表附件），重新计算行范围
            let updatedLineRange = (textStorage.string as NSString).lineRange(
                for: NSRange(location: lineRange.location, length: 0)
            )
            applyParagraphType(type, to: updatedLineRange, in: textStorage)
            return
        }

        // 当前是正文 → 直接应用
        applyParagraphType(type, to: lineRange, in: textStorage)
    }

    /// 应用指定段落类型
    private func applyParagraphType(
        _ type: ParagraphType,
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        switch type {
        case let .heading(level):
            Self.applyHeading(level: level, to: range, in: textStorage)
        case let .list(listType):
            switch listType {
            case .bullet:
                Self.applyBulletList(to: textStorage, range: range)
            case .ordered:
                let number = Self.calculateListNumber(at: range.location, in: textStorage)
                Self.applyOrderedList(to: textStorage, range: range, number: number)
            case .checkbox:
                Self.applyCheckboxList(to: textStorage, range: range)
            case .none:
                break
            }
        case .quote:
            Self.applyQuote(to: range, in: textStorage)
        case .normal:
            Self.removeBlockFormat(from: range, in: textStorage)
        default:
            break
        }
    }
}
