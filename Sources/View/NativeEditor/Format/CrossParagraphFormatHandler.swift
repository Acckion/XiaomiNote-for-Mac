//
//  CrossParagraphFormatHandler.swift
//  MiNoteMac
//
//  跨段落格式处理器 - 处理选中文本跨越多个段落时的格式应用逻辑
//

import AppKit
import SwiftUI

// MARK: - 段落信息

/// 段落信息结构
struct ParagraphInfo {
    /// 段落范围
    let range: NSRange
    /// 段落文本
    let text: String
    /// 段落索引
    let index: Int
    /// 是否是空段落
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 跨段落格式处理器

/// 跨段落格式处理器
///
/// 负责处理选中文本跨越多个段落时的格式应用逻辑。
@MainActor
class CrossParagraphFormatHandler {

    // MARK: - Singleton

    static let shared = CrossParagraphFormatHandler()

    private init() {}

    // MARK: - Public Methods

    /// 获取选中范围内的所有段落
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 选中范围
    /// - Returns: 段落信息数组
    func getParagraphs(in textStorage: NSAttributedString, range: NSRange) -> [ParagraphInfo] {
        var paragraphs: [ParagraphInfo] = []
        let string = textStorage.string as NSString

        var currentIndex = 0
        var paragraphIndex = 0

        // 遍历所有段落
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { substring, _, enclosingRange, _ in
            // 检查段落是否与选中范围相交
            let intersection = NSIntersectionRange(enclosingRange, range)
            if intersection
                .length > 0 || (range.location >= enclosingRange.location && range.location < enclosingRange.location + enclosingRange.length)
            {
                let paragraphInfo = ParagraphInfo(
                    range: enclosingRange,
                    text: substring ?? "",
                    index: paragraphIndex
                )
                paragraphs.append(paragraphInfo)
            }
            paragraphIndex += 1
        }

        return paragraphs
    }

    /// 检查选中范围是否跨越多个段落
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 选中范围
    /// - Returns: 是否跨越多个段落
    func isCrossParagraph(in textStorage: NSAttributedString, range: NSRange) -> Bool {
        let paragraphs = getParagraphs(in: textStorage, range: range)
        return paragraphs.count > 1
    }

    /// 应用段落级格式到跨段落选中范围
    /// - Parameters:
    ///   - format: 格式类型
    ///   - textStorage: 文本存储
    ///   - range: 选中范围
    func applyParagraphFormat(
        _ format: TextFormat,
        to textStorage: NSTextStorage,
        range: NSRange
    ) {
        guard format.isBlockFormat else {
            return
        }

        let paragraphs = getParagraphs(in: textStorage, range: range)

        textStorage.beginEditing()

        for paragraph in paragraphs {
            applyFormatToParagraph(format, to: textStorage, paragraphRange: paragraph.range)
        }

        textStorage.endEditing()
    }

    /// 应用对齐格式到跨段落选中范围
    /// - Parameters:
    ///   - alignment: 对齐方式
    ///   - textStorage: 文本存储
    ///   - range: 选中范围
    func applyAlignment(
        _ alignment: NSTextAlignment,
        to textStorage: NSTextStorage,
        range: NSRange
    ) {
        let paragraphs = getParagraphs(in: textStorage, range: range)

        textStorage.beginEditing()

        for paragraph in paragraphs {
            applyAlignmentToParagraph(alignment, to: textStorage, paragraphRange: paragraph.range)
        }

        textStorage.endEditing()
    }

    /// 检测跨段落选中范围的段落格式状态
    /// - Parameters:
    ///   - format: 格式类型
    ///   - textStorage: 文本存储
    ///   - range: 选中范围
    /// - Returns: 格式状态（全部激活、部分激活、未激活）
    func detectParagraphFormatState(
        _ format: TextFormat,
        in textStorage: NSAttributedString,
        range: NSRange
    ) -> FormatStateType {
        guard format.isBlockFormat else {
            return .inactive
        }

        let paragraphs = getParagraphs(in: textStorage, range: range)
        guard !paragraphs.isEmpty else {
            return .inactive
        }

        var activeCount = 0

        for paragraph in paragraphs {
            if isParagraphFormatActive(format, in: textStorage, paragraphRange: paragraph.range) {
                activeCount += 1
            }
        }

        if activeCount == paragraphs.count {
            return .fullyActive
        } else if activeCount > 0 {
            return .partiallyActive
        } else {
            return .inactive
        }
    }

    /// 检测跨段落选中范围的对齐状态
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 选中范围
    /// - Returns: 对齐方式（如果所有段落对齐一致）或 nil（如果不一致）
    func detectAlignment(
        in textStorage: NSAttributedString,
        range: NSRange
    ) -> NSTextAlignment? {
        let paragraphs = getParagraphs(in: textStorage, range: range)
        guard !paragraphs.isEmpty else {
            return nil
        }

        var alignments: Set<NSTextAlignment> = []

        for paragraph in paragraphs {
            if let alignment = getParagraphAlignment(in: textStorage, paragraphRange: paragraph.range) {
                alignments.insert(alignment)
            }
        }

        // 如果所有段落对齐一致，返回该对齐方式
        if alignments.count == 1 {
            return alignments.first
        }

        return nil
    }

    // MARK: - Private Methods

    /// 应用格式到单个段落
    private func applyFormatToParagraph(
        _ format: TextFormat,
        to textStorage: NSTextStorage,
        paragraphRange: NSRange
    ) {
        switch format {
        case .heading1:
            applyHeadingToParagraph(level: 1, to: textStorage, paragraphRange: paragraphRange)
        case .heading2:
            applyHeadingToParagraph(level: 2, to: textStorage, paragraphRange: paragraphRange)
        case .heading3:
            applyHeadingToParagraph(level: 3, to: textStorage, paragraphRange: paragraphRange)
        case .alignCenter:
            applyAlignmentToParagraph(.center, to: textStorage, paragraphRange: paragraphRange)
        case .alignRight:
            applyAlignmentToParagraph(.right, to: textStorage, paragraphRange: paragraphRange)
        case .bulletList, .numberedList, .checkbox, .quote:
            UnifiedFormatManager.shared.applyFormat(format, to: textStorage, range: paragraphRange)
        default:
            break
        }
    }

    /// 应用标题格式到段落
    private func applyHeadingToParagraph(
        level: Int,
        to textStorage: NSTextStorage,
        paragraphRange: NSRange
    ) {
        // 使用 FontSizeManager 获取字体大小
        let fontSize = FontSizeManager.shared.fontSize(for: level)

        // 使用常规字重，不再使用加粗
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textStorage.addAttribute(.font, value: font, range: paragraphRange)
    }

    /// 应用对齐格式到段落
    private func applyAlignmentToParagraph(
        _ alignment: NSTextAlignment,
        to textStorage: NSTextStorage,
        paragraphRange: NSRange
    ) {
        // 获取现有段落样式或创建新的
        var paragraphStyle: NSMutableParagraphStyle = if let existingStyle = textStorage.attribute(
            .paragraphStyle,
            at: paragraphRange.location,
            effectiveRange: nil
        ) as? NSParagraphStyle {
            existingStyle.mutableCopy() as! NSMutableParagraphStyle
        } else {
            NSMutableParagraphStyle()
        }

        paragraphStyle.alignment = alignment
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: paragraphRange)
    }

    /// 检查段落是否有指定格式
    private func isParagraphFormatActive(
        _ format: TextFormat,
        in textStorage: NSAttributedString,
        paragraphRange: NSRange
    ) -> Bool {
        guard paragraphRange.location < textStorage.length else {
            return false
        }

        let attributes = textStorage.attributes(at: paragraphRange.location, effectiveRange: nil)

        switch format {
        case .heading1, .heading2, .heading3:
            // 使用 FontSizeManager 的统一检测逻辑
            if let font = attributes[.font] as? NSFont {
                let detectedFormat = FontSizeManager.shared.detectParagraphFormat(fontSize: font.pointSize)
                switch format {
                case .heading1:
                    return detectedFormat == .heading1
                case .heading2:
                    return detectedFormat == .heading2
                case .heading3:
                    return detectedFormat == .heading3
                default:
                    return false
                }
            }
        case .alignCenter:
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle {
                return style.alignment == .center
            }
        case .alignRight:
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle {
                return style.alignment == .right
            }
        default:
            break
        }

        return false
    }

    /// 获取段落的对齐方式
    private func getParagraphAlignment(
        in textStorage: NSAttributedString,
        paragraphRange: NSRange
    ) -> NSTextAlignment? {
        guard paragraphRange.location < textStorage.length else {
            return nil
        }

        let attributes = textStorage.attributes(at: paragraphRange.location, effectiveRange: nil)

        if let style = attributes[.paragraphStyle] as? NSParagraphStyle {
            return style.alignment
        }

        return .left // 默认左对齐
    }
}

// MARK: - NativeEditorContext Extension

extension NativeEditorContext {

    /// 检查当前选中范围是否跨越多个段落
    /// - Returns: 是否跨越多个段落
    func isSelectionCrossParagraph() -> Bool {
        guard selectedRange.length > 0 else {
            return false
        }
        return CrossParagraphFormatHandler.shared.isCrossParagraph(in: nsAttributedText, range: selectedRange)
    }

    /// 获取当前选中范围内的段落数量
    /// - Returns: 段落数量
    func getSelectedParagraphCount() -> Int {
        guard selectedRange.length > 0 else {
            return 1
        }
        return CrossParagraphFormatHandler.shared.getParagraphs(in: nsAttributedText, range: selectedRange).count
    }
}
