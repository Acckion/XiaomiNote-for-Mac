//
//  MixedFormatStateHandler.swift
//  MiNoteMac
//
//  混合格式状态处理器 - 处理选中文本包含多种格式时的状态检测和显示
//

import AppKit
import SwiftUI

// MARK: - 混合格式状态

/// 格式状态类型
enum FormatStateType: Equatable {
    /// 完全激活 - 选中范围内所有文本都有该格式
    case fullyActive
    /// 部分激活 - 选中范围内部分文本有该格式
    case partiallyActive
    /// 未激活 - 选中范围内没有文本有该格式
    case inactive
}

/// 混合格式状态信息
struct MixedFormatState: Equatable {
    /// 格式类型
    let format: TextFormat
    /// 状态类型
    let stateType: FormatStateType
    /// 激活比例（0.0 - 1.0）
    let activationRatio: Double
    /// 激活的字符数
    let activeCharacterCount: Int
    /// 总字符数
    let totalCharacterCount: Int

    /// 是否应该显示为激活状态（完全激活或部分激活）
    var shouldShowAsActive: Bool {
        stateType != .inactive
    }

    /// 是否是部分激活状态
    var isPartiallyActive: Bool {
        stateType == .partiallyActive
    }
}

// MARK: - 混合格式状态处理器

/// 混合格式状态处理器
///
/// 负责检测选中文本中的混合格式状态，并提供适当的状态显示逻辑。
@MainActor
class MixedFormatStateHandler {

    // MARK: - Singleton

    static let shared = MixedFormatStateHandler()

    private init() {}

    // MARK: - Properties

    /// 部分激活阈值 - 超过此比例才显示为部分激活
    var partialActivationThreshold = 0.0

    /// 是否启用部分激活状态显示
    var enablePartialActivationDisplay = true

    // MARK: - Public Methods

    /// 检测选中范围内的混合格式状态
    /// - Parameters:
    ///   - attributedString: 富文本内容
    ///   - range: 选中范围
    /// - Returns: 所有格式的混合状态字典
    func detectMixedFormatStates(
        in attributedString: NSAttributedString,
        range: NSRange
    ) -> [TextFormat: MixedFormatState] {
        var states: [TextFormat: MixedFormatState] = [:]

        // 检测所有内联格式
        let inlineFormats: [TextFormat] = [.bold, .italic, .underline, .strikethrough, .highlight]
        for format in inlineFormats {
            let state = detectFormatState(format, in: attributedString, range: range)
            states[format] = state
        }

        return states
    }

    /// 检测单个格式在选中范围内的状态
    /// - Parameters:
    ///   - format: 格式类型
    ///   - attributedString: 富文本内容
    ///   - range: 选中范围
    /// - Returns: 格式状态信息
    func detectFormatState(
        _ format: TextFormat,
        in attributedString: NSAttributedString,
        range: NSRange
    ) -> MixedFormatState {
        guard range.length > 0 else {
            // 空选择范围，检测光标位置的格式
            return detectFormatStateAtPosition(format, in: attributedString, position: range.location)
        }

        // 确保范围有效
        let effectiveRange = NSRange(
            location: range.location,
            length: min(range.length, attributedString.length - range.location)
        )

        guard effectiveRange.length > 0 else {
            return MixedFormatState(
                format: format,
                stateType: .inactive,
                activationRatio: 0.0,
                activeCharacterCount: 0,
                totalCharacterCount: 0
            )
        }

        // 统计格式激活的字符数
        var activeCount = 0
        let totalCount = effectiveRange.length

        attributedString.enumerateAttributes(in: effectiveRange, options: []) { attributes, attrRange, _ in
            if isFormatActive(format, in: attributes) {
                activeCount += attrRange.length
            }
        }

        // 计算激活比例
        let ratio = Double(activeCount) / Double(totalCount)

        // 确定状态类型
        let stateType: FormatStateType = if activeCount == 0 {
            .inactive
        } else if activeCount == totalCount {
            .fullyActive
        } else {
            .partiallyActive
        }

        return MixedFormatState(
            format: format,
            stateType: stateType,
            activationRatio: ratio,
            activeCharacterCount: activeCount,
            totalCharacterCount: totalCount
        )
    }

    /// 检测光标位置的格式状态
    /// - Parameters:
    ///   - format: 格式类型
    ///   - attributedString: 富文本内容
    ///   - position: 光标位置
    /// - Returns: 格式状态信息
    func detectFormatStateAtPosition(
        _ format: TextFormat,
        in attributedString: NSAttributedString,
        position: Int
    ) -> MixedFormatState {
        guard position >= 0, position < attributedString.length else {
            return MixedFormatState(
                format: format,
                stateType: .inactive,
                activationRatio: 0.0,
                activeCharacterCount: 0,
                totalCharacterCount: 0
            )
        }

        let attributes = attributedString.attributes(at: position, effectiveRange: nil)
        let isActive = isFormatActive(format, in: attributes)

        return MixedFormatState(
            format: format,
            stateType: isActive ? .fullyActive : .inactive,
            activationRatio: isActive ? 1.0 : 0.0,
            activeCharacterCount: isActive ? 1 : 0,
            totalCharacterCount: 1
        )
    }

    /// 获取应该显示为激活状态的格式集合
    /// - Parameters:
    ///   - attributedString: 富文本内容
    ///   - range: 选中范围
    /// - Returns: 应该显示为激活的格式集合
    func getActiveFormats(
        in attributedString: NSAttributedString,
        range: NSRange
    ) -> Set<TextFormat> {
        let states = detectMixedFormatStates(in: attributedString, range: range)
        var activeFormats: Set<TextFormat> = []

        for (format, state) in states {
            if state.shouldShowAsActive {
                activeFormats.insert(format)
            }
        }

        return activeFormats
    }

    /// 获取部分激活的格式集合
    /// - Parameters:
    ///   - attributedString: 富文本内容
    ///   - range: 选中范围
    /// - Returns: 部分激活的格式集合
    func getPartiallyActiveFormats(
        in attributedString: NSAttributedString,
        range: NSRange
    ) -> Set<TextFormat> {
        let states = detectMixedFormatStates(in: attributedString, range: range)
        var partialFormats: Set<TextFormat> = []

        for (format, state) in states {
            if state.isPartiallyActive {
                partialFormats.insert(format)
            }
        }

        return partialFormats
    }

    /// 获取完全激活的格式集合
    /// - Parameters:
    ///   - attributedString: 富文本内容
    ///   - range: 选中范围
    /// - Returns: 完全激活的格式集合
    func getFullyActiveFormats(
        in attributedString: NSAttributedString,
        range: NSRange
    ) -> Set<TextFormat> {
        let states = detectMixedFormatStates(in: attributedString, range: range)
        var fullyActiveFormats: Set<TextFormat> = []

        for (format, state) in states {
            if state.stateType == .fullyActive {
                fullyActiveFormats.insert(format)
            }
        }

        return fullyActiveFormats
    }

    // MARK: - Private Methods

    /// 检测属性中是否包含指定格式
    /// - Parameters:
    ///   - format: 格式类型
    ///   - attributes: 属性字典
    /// - Returns: 是否包含该格式
    private func isFormatActive(_ format: TextFormat, in attributes: [NSAttributedString.Key: Any]) -> Bool {
        switch format {
        case .bold:
            isBoldActive(in: attributes)
        case .italic:
            isItalicActive(in: attributes)
        case .underline:
            isUnderlineActive(in: attributes)
        case .strikethrough:
            isStrikethroughActive(in: attributes)
        case .highlight:
            isHighlightActive(in: attributes)
        default:
            false
        }
    }

    /// 检测加粗格式
    private func isBoldActive(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let font = attributes[.font] as? NSFont else { return false }

        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) {
            return true
        }

        // 备用检测：检查字体名称
        let fontName = font.fontName.lowercased()
        if fontName.contains("bold") || fontName.contains("-bold") {
            return true
        }

        // 备用检测：检查字体 weight
        if let weightTrait = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any],
           let weight = weightTrait[.weight] as? CGFloat,
           weight >= 0.4
        {
            return true
        }

        return false
    }

    /// 检测斜体格式
    private func isItalicActive(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let font = attributes[.font] as? NSFont else { return false }

        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.italic) {
            return true
        }

        // 备用检测：检查字体名称
        let fontName = font.fontName.lowercased()
        return fontName.contains("italic") || fontName.contains("oblique")
    }

    /// 检测下划线格式
    private func isUnderlineActive(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
            return true
        }
        return false
    }

    /// 检测删除线格式
    private func isStrikethroughActive(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
            return true
        }
        return false
    }

    /// 检测高亮格式
    private func isHighlightActive(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let backgroundColor = attributes[.backgroundColor] as? NSColor {
            // 排除透明或白色背景
            if backgroundColor.alphaComponent > 0.1, backgroundColor != .clear, backgroundColor != .white {
                return true
            }
        }
        return false
    }
}

// MARK: - NativeEditorContext Extension

extension NativeEditorContext {

    /// 获取当前选中范围的混合格式状态
    /// - Returns: 混合格式状态字典
    func getMixedFormatStates() -> [TextFormat: MixedFormatState] {
        let handler = MixedFormatStateHandler.shared
        return handler.detectMixedFormatStates(in: nsAttributedText, range: selectedRange)
    }

    /// 获取部分激活的格式集合
    /// - Returns: 部分激活的格式集合
    func getPartiallyActiveFormats() -> Set<TextFormat> {
        let handler = MixedFormatStateHandler.shared
        return handler.getPartiallyActiveFormats(in: nsAttributedText, range: selectedRange)
    }

    /// 检测指定格式是否部分激活
    /// - Parameter format: 格式类型
    /// - Returns: 是否部分激活
    func isFormatPartiallyActive(_ format: TextFormat) -> Bool {
        let handler = MixedFormatStateHandler.shared
        let state = handler.detectFormatState(format, in: nsAttributedText, range: selectedRange)
        return state.isPartiallyActive
    }

    /// 获取指定格式的激活比例
    /// - Parameter format: 格式类型
    /// - Returns: 激活比例（0.0 - 1.0）
    func getFormatActivationRatio(_ format: TextFormat) -> Double {
        let handler = MixedFormatStateHandler.shared
        let state = handler.detectFormatState(format, in: nsAttributedText, range: selectedRange)
        return state.activationRatio
    }

    /// 更新当前格式状态（包含混合格式检测）
    func updateCurrentFormatsWithMixedState() {
        // 如果有选中范围，使用混合格式检测
        if selectedRange.length > 0 {
            let handler = MixedFormatStateHandler.shared
            let activeFormats = handler.getActiveFormats(in: nsAttributedText, range: selectedRange)

            // 更新当前格式
            currentFormats = activeFormats

            // 更新工具栏按钮状态
            for format in TextFormat.allCases {
                toolbarButtonStates[format] = activeFormats.contains(format)
            }

            // 检测块级格式（标题、对齐、列表等）
            detectBlockFormatsInRange(selectedRange)
        } else {
            // 没有选中范围，使用原有的单点检测
            updateCurrentFormats()
        }
    }

    /// 检测选中范围内的块级格式
    /// - Parameter range: 选中范围
    private func detectBlockFormatsInRange(_ range: NSRange) {
        guard range.location < nsAttributedText.length else { return }

        let position = range.location
        let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)

        // 检测标题格式 - 使用 FontSizeManager 的统一检测逻辑
        if let font = attributes[.font] as? NSFont {
            let fontSize = font.pointSize
            let detectedFormat = FontSizeManager.shared.detectParagraphFormat(fontSize: fontSize)
            switch detectedFormat {
            case .heading1:
                currentFormats.insert(.heading1)
                toolbarButtonStates[.heading1] = true
            case .heading2:
                currentFormats.insert(.heading2)
                toolbarButtonStates[.heading2] = true
            case .heading3:
                currentFormats.insert(.heading3)
                toolbarButtonStates[.heading3] = true
            default:
                break
            }
        }

        // 检测对齐格式
        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            switch paragraphStyle.alignment {
            case .center:
                currentFormats.insert(.alignCenter)
                toolbarButtonStates[.alignCenter] = true
            case .right:
                currentFormats.insert(.alignRight)
                toolbarButtonStates[.alignRight] = true
            default:
                break
            }
        }

        // 检测引用块格式
        if let isQuote = attributes[.quoteBlock] as? Bool, isQuote {
            currentFormats.insert(.quote)
            toolbarButtonStates[.quote] = true
        }
    }
}
