//
//  UnifiedFormatManager+Detection.swift
//  MiNoteMac
//
//  格式检测逻辑（光标位置格式状态判断）
//
//

import AppKit

// MARK: - 格式检测

public extension UnifiedFormatManager {

    /// 检测光标位置的格式状态
    ///
    /// 检测指定位置的完整格式状态，包括：
    /// - 内联格式（加粗、斜体、下划线、删除线、高亮）
    /// - 块级格式（标题、列表、引用）
    /// - 对齐属性
    ///
    /// - Parameter position: 光标位置
    /// - Returns: 完整的格式状态
    func detectFormatState(at position: Int) -> FormatState {
        guard let textStorage = currentTextStorage else {
            return FormatState.default
        }

        guard let textView = currentTextView else {
            return FormatState.default
        }

        // 获取选择信息
        let selectedRange = textView.selectedRange()
        let hasSelection = selectedRange.length > 0
        let selectionLength = selectedRange.length

        // 确定检测位置
        let detectPosition: Int
        if hasSelection {
            // 有选择时，使用选择起始位置
            detectPosition = selectedRange.location
        } else if position > 0, position <= textStorage.length {
            // 无选择时，使用前一个字符的位置（更符合用户预期）
            detectPosition = position - 1
        } else if position < textStorage.length {
            detectPosition = position
        } else {
            // 空文档或文档末尾
            return FormatState(hasSelection: hasSelection, selectionLength: selectionLength)
        }

        // 确保位置有效
        guard detectPosition >= 0, detectPosition < textStorage.length else {
            return FormatState(hasSelection: hasSelection, selectionLength: selectionLength)
        }

        // 获取属性
        let attributes = textStorage.attributes(at: detectPosition, effectiveRange: nil)

        // 构建格式状态
        var state = FormatState()
        state.hasSelection = hasSelection
        state.selectionLength = selectionLength

        // 检测内联格式
        state.isBold = InlineFormatHandler.isFormatActive(.bold, in: attributes)
        state.isItalic = InlineFormatHandler.isFormatActive(.italic, in: attributes)
        state.isUnderline = InlineFormatHandler.isFormatActive(.underline, in: attributes)
        state.isStrikethrough = InlineFormatHandler.isFormatActive(.strikethrough, in: attributes)
        state.isHighlight = InlineFormatHandler.isFormatActive(.highlight, in: attributes)

        // 检测块级格式
        if let blockFormat = BlockFormatHandler.detect(at: detectPosition, in: textStorage) {
            switch blockFormat {
            case .heading1:
                state.paragraphFormat = .heading1
            case .heading2:
                state.paragraphFormat = .heading2
            case .heading3:
                state.paragraphFormat = .heading3
            case .bulletList:
                state.paragraphFormat = .bulletList
            case .numberedList:
                state.paragraphFormat = .numberedList
            case .checkbox:
                state.paragraphFormat = .checkbox
            case .quote:
                state.isQuote = true
            default:
                break
            }
        }

        // 检测列表属性（缩进级别和编号）
        if state.paragraphFormat.isList {
            // 获取列表缩进级别
            if let listIndent = attributes[.listIndent] as? Int {
                state.listIndent = listIndent
            } else {
                // 尝试从 ListFormatHandler 获取
                state.listIndent = ListFormatHandler.getListIndent(in: textStorage, at: detectPosition)
            }

            // 获取列表编号（仅有序列表）
            if state.paragraphFormat == .numberedList {
                if let listNumber = attributes[.listNumber] as? Int {
                    state.listNumber = listNumber
                } else {
                    // 尝试从 ListFormatHandler 获取
                    state.listNumber = ListFormatHandler.getListNumber(in: textStorage, at: detectPosition)
                }
            }
        }

        // 检测对齐属性
        let alignment = BlockFormatHandler.detectAlignment(at: detectPosition, in: textStorage)
        switch alignment {
        case .center:
            state.alignment = .center
        case .right:
            state.alignment = .right
        default:
            state.alignment = .left
        }

        return state
    }

    /// 检测选择范围的格式状态
    ///
    /// 对于选择范围，检测所有字符共有的格式
    ///
    /// - Parameter range: 选择范围
    /// - Returns: 完整的格式状态
    func detectFormatState(in range: NSRange) -> FormatState {
        guard let textStorage = currentTextStorage else {
            return FormatState.default
        }

        guard range.length > 0 else {
            return detectFormatState(at: range.location)
        }

        // 初始化状态（假设所有格式都激活）
        var state = FormatState()
        state.hasSelection = true
        state.selectionLength = range.length
        state.isBold = true
        state.isItalic = true
        state.isUnderline = true
        state.isStrikethrough = true
        state.isHighlight = true

        // 遍历范围内的所有字符，检测共有格式
        var isFirstChar = true
        textStorage.enumerateAttributes(in: range, options: []) { attributes, _, _ in
            if isFirstChar {
                // 第一个字符，设置初始状态
                state.isBold = InlineFormatHandler.isFormatActive(.bold, in: attributes)
                state.isItalic = InlineFormatHandler.isFormatActive(.italic, in: attributes)
                state.isUnderline = InlineFormatHandler.isFormatActive(.underline, in: attributes)
                state.isStrikethrough = InlineFormatHandler.isFormatActive(.strikethrough, in: attributes)
                state.isHighlight = InlineFormatHandler.isFormatActive(.highlight, in: attributes)
                isFirstChar = false
            } else {
                // 后续字符，只保留共有格式
                if state.isBold, !InlineFormatHandler.isFormatActive(.bold, in: attributes) {
                    state.isBold = false
                }
                if state.isItalic, !InlineFormatHandler.isFormatActive(.italic, in: attributes) {
                    state.isItalic = false
                }
                if state.isUnderline, !InlineFormatHandler.isFormatActive(.underline, in: attributes) {
                    state.isUnderline = false
                }
                if state.isStrikethrough, !InlineFormatHandler.isFormatActive(.strikethrough, in: attributes) {
                    state.isStrikethrough = false
                }
                if state.isHighlight, !InlineFormatHandler.isFormatActive(.highlight, in: attributes) {
                    state.isHighlight = false
                }
            }
        }

        // 块级格式使用范围起始位置检测
        if let blockFormat = BlockFormatHandler.detect(at: range.location, in: textStorage) {
            switch blockFormat {
            case .heading1:
                state.paragraphFormat = .heading1
            case .heading2:
                state.paragraphFormat = .heading2
            case .heading3:
                state.paragraphFormat = .heading3
            case .bulletList:
                state.paragraphFormat = .bulletList
            case .numberedList:
                state.paragraphFormat = .numberedList
            case .checkbox:
                state.paragraphFormat = .checkbox
            case .quote:
                state.isQuote = true
            default:
                break
            }
        }

        // 对齐属性使用范围起始位置检测
        let alignment = BlockFormatHandler.detectAlignment(at: range.location, in: textStorage)
        switch alignment {
        case .center:
            state.alignment = .center
        case .right:
            state.alignment = .right
        default:
            state.alignment = .left
        }

        return state
    }

    /// 应用格式（接受外部 textStorage 参数）
    ///
    /// 路由到对应 Handler 处理
    ///
    /// - Parameters:
    ///   - format: 格式类型
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func applyFormat(_ format: TextFormat, to textStorage: NSTextStorage, range: NSRange) {
        switch format {
        case .bold:
            InlineFormatHandler.apply(.bold, to: range, in: textStorage, toggle: true)
        case .italic:
            InlineFormatHandler.apply(.italic, to: range, in: textStorage, toggle: true)
        case .underline:
            InlineFormatHandler.apply(.underline, to: range, in: textStorage, toggle: true)
        case .strikethrough:
            InlineFormatHandler.apply(.strikethrough, to: range, in: textStorage, toggle: true)
        case .highlight:
            InlineFormatHandler.apply(.highlight, to: range, in: textStorage, toggle: true)
        case .heading1:
            BlockFormatHandler.apply(.heading1, to: range, in: textStorage, toggle: true)
        case .heading2:
            BlockFormatHandler.apply(.heading2, to: range, in: textStorage, toggle: true)
        case .heading3:
            BlockFormatHandler.apply(.heading3, to: range, in: textStorage, toggle: true)
        case .alignCenter:
            BlockFormatHandler.apply(.alignCenter, to: range, in: textStorage, toggle: true)
        case .alignRight:
            BlockFormatHandler.apply(.alignRight, to: range, in: textStorage, toggle: true)
        case .bulletList:
            ListFormatHandler.toggleBulletList(to: textStorage, range: range)
        case .numberedList:
            ListFormatHandler.toggleOrderedList(to: textStorage, range: range)
        case .checkbox:
            ListFormatHandler.toggleCheckboxList(to: textStorage, range: range)
        case .quote:
            BlockFormatHandler.apply(.quote, to: range, in: textStorage, toggle: true)
        default:
            break
        }
    }

    /// 检测格式是否激活
    /// - Parameters:
    ///   - format: 格式类型
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否激活
    func isFormatActive(_ format: TextFormat, in textStorage: NSTextStorage, at position: Int) -> Bool {
        guard position >= 0, position < textStorage.length else { return false }

        let attributes = textStorage.attributes(at: position, effectiveRange: nil)

        switch format {
        case .bold:
            return InlineFormatHandler.isFormatActive(.bold, in: attributes)
        case .italic:
            return InlineFormatHandler.isFormatActive(.italic, in: attributes)
        case .underline:
            return InlineFormatHandler.isFormatActive(.underline, in: attributes)
        case .strikethrough:
            return InlineFormatHandler.isFormatActive(.strikethrough, in: attributes)
        case .highlight:
            return InlineFormatHandler.isFormatActive(.highlight, in: attributes)
        case .heading1:
            if let font = attributes[.font] as? NSFont {
                return FontSizeConstants.detectParagraphFormat(fontSize: font.pointSize) == .heading1
            }
            return false
        case .heading2:
            if let font = attributes[.font] as? NSFont {
                return FontSizeConstants.detectParagraphFormat(fontSize: font.pointSize) == .heading2
            }
            return false
        case .heading3:
            if let font = attributes[.font] as? NSFont {
                return FontSizeConstants.detectParagraphFormat(fontSize: font.pointSize) == .heading3
            }
            return false
        case .alignCenter:
            return BlockFormatHandler.detectAlignment(at: position, in: textStorage) == .center
        case .alignRight:
            return BlockFormatHandler.detectAlignment(at: position, in: textStorage) == .right
        case .bulletList:
            return ListFormatHandler.detectListType(in: textStorage, at: position) == .bullet
        case .numberedList:
            return ListFormatHandler.detectListType(in: textStorage, at: position) == .ordered
        case .checkbox:
            return ListFormatHandler.detectListType(in: textStorage, at: position) == .checkbox
        case .quote:
            return isQuoteBlock(in: textStorage, at: position)
        default:
            return false
        }
    }
}
