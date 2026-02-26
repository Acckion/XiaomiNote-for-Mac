//
//  UnifiedFormatManager+BlockFormat.swift
//  MiNoteMac
//
//  块级格式应用逻辑（标题、对齐、换行处理等）
//
//

import AppKit

// MARK: - 块级格式应用

public extension UnifiedFormatManager {

    /// 应用块级格式到选中文本
    ///
    /// 段落格式通过 ParagraphManager 统一处理
    ///
    /// - Parameters:
    ///   - format: 要应用的块级格式
    ///   - range: 应用范围
    ///   - toggle: 是否切换模式（默认 true）
    ///   - paragraphManager: ParagraphManager 实例
    func applyBlockFormat(_ format: TextFormat, to range: NSRange, toggle _: Bool = true, paragraphManager: ParagraphManager? = nil) {
        guard let textStorage = currentTextStorage else {
            return
        }

        guard format.isBlockFormat else {
            return
        }

        // 对齐格式单独处理
        if format.category == .alignment {
            let targetAlignment: NSTextAlignment = switch format {
            case .alignCenter: .center
            case .alignRight: .right
            default: .left
            }
            ParagraphManager.toggleAlignment(targetAlignment, to: range, in: textStorage)
            return
        }

        // 段落格式通过 ParagraphManager toggle
        if let paragraphManager, let paragraphType = ParagraphType.from(format) {
            paragraphManager.toggleParagraphFormat(paragraphType, to: range, in: textStorage)
        }
    }

    /// 检测指定位置的块级格式
    func detectBlockFormat(at position: Int) -> TextFormat? {
        guard let textStorage = currentTextStorage else {
            return nil
        }

        let paragraphType = ParagraphManager.detectCurrentParagraphType(at: position, in: textStorage)
        return paragraphType.textFormat
    }

    /// 检测指定位置的对齐方式
    func detectAlignment(at position: Int) -> NSTextAlignment {
        guard let textStorage = currentTextStorage else {
            return .left
        }

        let alignFormat = ParagraphManager.detectAlignment(at: position, in: textStorage)
        return switch alignFormat {
        case .center: .center
        case .right: .right
        default: .left
        }
    }

    /// 移除块级格式
    func removeBlockFormat(from range: NSRange) {
        guard let textStorage = currentTextStorage else {
            return
        }

        ParagraphManager.removeBlockFormat(from: range, in: textStorage)
    }

    /// 检测列表项是否为空
    func isListItemEmpty(at position: Int) -> Bool {
        guard let textStorage = currentTextStorage else {
            return false
        }

        return ParagraphManager.isListItemEmpty(at: position, in: textStorage)
    }

    /// 获取指定位置的列表类型
    func getListType(at position: Int) -> TextFormat? {
        guard let textStorage = currentTextStorage else {
            return nil
        }

        let listType = ParagraphManager.detectListType(at: position, in: textStorage)
        switch listType {
        case .bullet: return .bulletList
        case .ordered: return .numberedList
        case .checkbox: return .checkbox
        case .none: return nil
        }
    }

    /// 检测是否是列表格式
    func isList(at position: Int) -> Bool {
        getListType(at: position) != nil
    }

    /// 构建换行上下文
    func buildNewLineContext(at position: Int) -> NewLineContext {
        guard let textStorage = currentTextStorage else {
            return .default
        }

        let string = textStorage.string as NSString

        let safePositionForLineRange: Int
        if position > 0, position < textStorage.length {
            let charAtPosition = string.character(at: position)
            if charAtPosition == 0x0A {
                safePositionForLineRange = position - 1
            } else {
                safePositionForLineRange = position
            }
        } else if position >= textStorage.length, textStorage.length > 0 {
            safePositionForLineRange = textStorage.length - 1
        } else {
            safePositionForLineRange = position
        }

        let lineRange = string.lineRange(for: NSRange(location: safePositionForLineRange, length: 0))

        let blockFormat: TextFormat? = if safePositionForLineRange < textStorage.length {
            ParagraphManager.detectCurrentParagraphType(at: safePositionForLineRange, in: textStorage).textFormat
        } else if safePositionForLineRange > 0 {
            ParagraphManager.detectCurrentParagraphType(at: safePositionForLineRange - 1, in: textStorage).textFormat
        } else {
            nil
        }

        let detectedAlignment: AlignmentFormat = if safePositionForLineRange < textStorage.length {
            ParagraphManager.detectAlignment(at: safePositionForLineRange, in: textStorage)
        } else if safePositionForLineRange > 0 {
            ParagraphManager.detectAlignment(at: safePositionForLineRange - 1, in: textStorage)
        } else {
            .left
        }
        let alignment: NSTextAlignment = switch detectedAlignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }

        let isListEmpty = ParagraphManager.isListItemEmpty(at: position, in: textStorage)

        return NewLineContext(
            currentLineRange: lineRange,
            currentBlockFormat: blockFormat,
            currentAlignment: alignment,
            isListItemEmpty: isListEmpty
        )
    }

    /// 处理换行
    func handleNewLine() -> Bool {
        guard let textView = currentTextView else {
            return false
        }

        let context = NewLineContext.build(from: textView)
        return NewLineHandler.handleNewLine(context: context, textView: textView)
    }
}
