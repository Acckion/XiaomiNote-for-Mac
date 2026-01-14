//
//  InlineFormatHandler.swift
//  MiNoteMac
//
//  内联格式处理器 - 统一处理加粗、斜体、下划线、删除线、高亮格式
//  负责格式的应用、检测和 typingAttributes 构建
//
//  _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_
//

import Foundation
import AppKit

// MARK: - 内联格式处理器

/// 内联格式处理器
/// 统一处理所有内联格式（加粗、斜体、下划线、删除线、高亮）
/// _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_
public struct InlineFormatHandler {
    
    // MARK: - 常量
    
    /// 斜体 obliqueness 值（用于不支持斜体的字体）
    /// _Requirements: 1.5_
    public static let italicObliquenessValue: Double = 0.2
    
    /// 默认字体 (14pt)
    /// 注意：使用 nonisolated(unsafe) 因为 NSFont 不是 Sendable，但这里是只读常量
    /// 使用 FontSizeConstants.body (14pt) 保持与 FontSizeManager 一致
    /// _Requirements: 1.4, 4.5_
    nonisolated(unsafe) public static let defaultFont: NSFont = NSFont.systemFont(ofSize: FontSizeConstants.body)
    
    /// 高亮背景色
    /// 注意：使用 nonisolated(unsafe) 因为 NSColor 不是 Sendable，但这里是只读常量
    nonisolated(unsafe) public static let highlightColor: NSColor = NSColor.systemYellow.withAlphaComponent(0.5)
    
    // MARK: - 格式应用
    
    /// 应用内联格式到指定范围
    /// 
    /// 统一处理所有内联格式的应用逻辑：
    /// - 加粗：使用字体特性
    /// - 斜体：优先使用字体特性，不支持时使用 obliqueness
    /// - 下划线：使用 underlineStyle 属性
    /// - 删除线：使用 strikethroughStyle 属性
    /// - 高亮：使用 backgroundColor 属性
    /// 
    /// - Parameters:
    ///   - format: 要应用的内联格式
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - toggle: 是否切换模式（true 则切换，false 则强制应用）
    /// _Requirements: 1.1, 1.2, 1.3_
    public static func apply(
        _ format: TextFormat,
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool = true
    ) {
        guard range.length > 0 else { return }
        guard format.category == .inline else {
            print("[InlineFormatHandler] 警告：尝试应用非内联格式 \(format.displayName)")
            return
        }
        
        switch format {
        case .bold:
            applyBold(to: range, in: textStorage, toggle: toggle)
        case .italic:
            applyItalic(to: range, in: textStorage, toggle: toggle)
        case .underline:
            applyUnderline(to: range, in: textStorage, toggle: toggle)
        case .strikethrough:
            applyStrikethrough(to: range, in: textStorage, toggle: toggle)
        case .highlight:
            applyHighlight(to: range, in: textStorage, toggle: toggle)
        default:
            break
        }
    }
    
    /// 应用多个内联格式到指定范围
    /// 
    /// 确保多个内联格式可以同时生效，格式切换时保留其他已有格式
    /// 
    /// - Parameters:
    ///   - formats: 要应用的内联格式集合
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - toggle: 是否切换模式
    /// _Requirements: 1.4_
    public static func applyMultiple(
        _ formats: Set<TextFormat>,
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool = true
    ) {
        guard range.length > 0 else { return }
        
        // 过滤出内联格式
        let inlineFormats = formats.filter { $0.category == .inline }
        
        // 依次应用每个格式
        for format in inlineFormats {
            apply(format, to: range, in: textStorage, toggle: toggle)
        }
    }
    
    // MARK: - 格式检测
    
    /// 检测指定位置的内联格式
    /// 
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 当前位置激活的内联格式集合
    /// _Requirements: 1.3_
    public static func detect(at position: Int, in textStorage: NSTextStorage) -> Set<TextFormat> {
        guard position >= 0 && position < textStorage.length else {
            return []
        }
        
        var formats: Set<TextFormat> = []
        let attributes = textStorage.attributes(at: position, effectiveRange: nil)
        
        // 检测加粗
        if isBoldInAttributes(attributes) {
            formats.insert(.bold)
        }
        
        // 检测斜体
        if isItalicInAttributes(attributes) {
            formats.insert(.italic)
        }
        
        // 检测下划线
        if isUnderlineInAttributes(attributes) {
            formats.insert(.underline)
        }
        
        // 检测删除线
        if isStrikethroughInAttributes(attributes) {
            formats.insert(.strikethrough)
        }
        
        // 检测高亮
        if isHighlightInAttributes(attributes) {
            formats.insert(.highlight)
        }
        
        return formats
    }
    
    /// 检测指定格式是否在属性中激活
    /// 
    /// - Parameters:
    ///   - format: 要检测的格式
    ///   - attributes: 属性字典
    /// - Returns: 是否激活
    /// _Requirements: 1.3_
    public static func isFormatActive(
        _ format: TextFormat,
        in attributes: [NSAttributedString.Key: Any]
    ) -> Bool {
        switch format {
        case .bold:
            return isBoldInAttributes(attributes)
        case .italic:
            return isItalicInAttributes(attributes)
        case .underline:
            return isUnderlineInAttributes(attributes)
        case .strikethrough:
            return isStrikethroughInAttributes(attributes)
        case .highlight:
            return isHighlightInAttributes(attributes)
        default:
            return false
        }
    }
    
    // MARK: - typingAttributes 构建
    
    /// 构建不包含内联格式的 typingAttributes
    /// 
    /// 用于换行后清除内联格式，重置为默认正文样式
    /// 
    /// 关键修复：换行后始终使用默认字体大小（15pt），不继承前一行的字体大小
    /// 这修复了从标题行换行后新行变成三级标题样式的问题
    /// 
    /// - Parameter baseAttributes: 基础属性（可选，仅用于保留段落样式如对齐方式）
    /// - Returns: 清除内联格式后的属性字典
    /// _Requirements: 2.1-2.6_
    public static func buildCleanTypingAttributes(
        from baseAttributes: [NSAttributedString.Key: Any]? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        
        // 关键修复：始终使用默认字体（15pt），不继承前一行的字体大小
        // 之前的实现会保留 baseFont 的字体大小，导致从标题行换行后
        // 新行继承了标题的字体大小（如 16pt、20pt、24pt），显示为三级标题样式
        attributes[.font] = defaultFont
        
        // 设置默认文本颜色
        attributes[.foregroundColor] = NSColor.labelColor
        
        // 保留段落样式（如果有）- 主要用于继承对齐方式
        if let paragraphStyle = baseAttributes?[.paragraphStyle] {
            attributes[.paragraphStyle] = paragraphStyle
        }
        
        // 注意：不包含以下内联格式属性：
        // - obliqueness（斜体）
        // - underlineStyle（下划线）
        // - strikethroughStyle（删除线）
        // - backgroundColor（高亮）- 除非是引用块背景
        
        return attributes
    }
    
    /// 从属性中移除所有内联格式
    /// 
    /// - Parameter attributes: 原始属性字典
    /// - Returns: 移除内联格式后的属性字典
    /// _Requirements: 2.1-2.6_
    public static func removeInlineFormats(
        from attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var result = attributes
        
        // 移除斜体 obliqueness
        result.removeValue(forKey: .obliqueness)
        
        // 移除下划线
        result.removeValue(forKey: .underlineStyle)
        
        // 移除删除线
        result.removeValue(forKey: .strikethroughStyle)
        
        // 移除高亮背景色（但保留引用块背景）
        // 检查是否是引用块，如果不是则移除背景色
        if result[.quoteBlock] == nil {
            result.removeValue(forKey: .backgroundColor)
        }
        
        // 处理字体：移除加粗/斜体特性
        if let font = result[.font] as? NSFont {
            result[.font] = removeInlineTraitsFromFont(font)
        }
        
        return result
    }
    
    // MARK: - 私有方法 - 格式应用
    
    /// 应用加粗格式
    /// _Requirements: 1.1_
    private static func applyBold(
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool
    ) {
        applyFontTrait(.bold, to: range, in: textStorage, toggle: toggle)
    }
    
    /// 应用斜体格式
    /// 
    /// 优先使用字体特性，如果字体不支持斜体则使用 obliqueness 属性
    /// 
    /// _Requirements: 1.2, 1.5_
    private static func applyItalic(
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool
    ) {
        textStorage.beginEditing()
        
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            let font = (value as? NSFont) ?? defaultFont
            
            // 检查当前是否有斜体
            let hasItalicTrait = font.fontDescriptor.symbolicTraits.contains(.italic)
            let hasObliqueness = (textStorage.attribute(.obliqueness, at: attrRange.location, effectiveRange: nil) as? Double ?? 0) > 0
            let hasItalic = hasItalicTrait || hasObliqueness
            
            if toggle && hasItalic {
                // 移除斜体
                removeItalic(from: attrRange, in: textStorage, font: font)
            } else if !hasItalic {
                // 添加斜体
                addItalic(to: attrRange, in: textStorage, font: font)
            }
        }
        
        textStorage.endEditing()
    }
    
    /// 添加斜体效果
    /// _Requirements: 1.5_
    private static func addItalic(
        to range: NSRange,
        in textStorage: NSTextStorage,
        font: NSFont
    ) {
        // 尝试使用字体特性
        let fontManager = NSFontManager.shared
        let italicFont = fontManager.convert(font, toHaveTrait: .italicFontMask)
        
        // 检查是否成功获取斜体字体
        if italicFont.fontDescriptor.symbolicTraits.contains(.italic) {
            // 字体支持斜体，使用字体特性
            textStorage.addAttribute(.font, value: italicFont, range: range)
            // 确保移除 obliqueness（如果之前有的话）
            textStorage.removeAttribute(.obliqueness, range: range)
            print("[InlineFormatHandler] 添加斜体（字体特性）")
        } else {
            // 字体不支持斜体，使用 obliqueness 后备方案
            textStorage.addAttribute(.obliqueness, value: italicObliquenessValue, range: range)
            print("[InlineFormatHandler] 添加斜体（obliqueness 后备方案）")
        }
    }
    
    /// 移除斜体效果
    /// _Requirements: 1.5_
    private static func removeItalic(
        from range: NSRange,
        in textStorage: NSTextStorage,
        font: NSFont
    ) {
        // 移除字体斜体特性
        if font.fontDescriptor.symbolicTraits.contains(.italic) {
            let fontManager = NSFontManager.shared
            let regularFont = fontManager.convert(font, toNotHaveTrait: .italicFontMask)
            textStorage.addAttribute(.font, value: regularFont, range: range)
        }
        
        // 移除 obliqueness 属性
        textStorage.removeAttribute(.obliqueness, range: range)
        print("[InlineFormatHandler] 移除斜体")
    }
    
    /// 应用下划线格式
    /// _Requirements: 1.1_
    private static func applyUnderline(
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool
    ) {
        toggleAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            in: range,
            textStorage: textStorage,
            toggle: toggle
        )
    }
    
    /// 应用删除线格式
    /// _Requirements: 1.1_
    private static func applyStrikethrough(
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool
    ) {
        toggleAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            in: range,
            textStorage: textStorage,
            toggle: toggle
        )
    }
    
    /// 应用高亮格式
    /// _Requirements: 1.1_
    private static func applyHighlight(
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool
    ) {
        toggleAttribute(
            .backgroundColor,
            value: highlightColor,
            in: range,
            textStorage: textStorage,
            toggle: toggle
        )
    }
    
    // MARK: - 私有方法 - 格式检测
    
    /// 检测属性中是否有加粗
    private static func isBoldInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let font = attributes[.font] as? NSFont {
            return font.fontDescriptor.symbolicTraits.contains(.bold)
        }
        return false
    }
    
    /// 检测属性中是否有斜体
    /// 同时检查字体特性和 obliqueness 属性
    /// _Requirements: 1.5_
    private static func isItalicInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        // 检查 obliqueness 属性
        if let obliqueness = attributes[.obliqueness] as? Double, obliqueness > 0 {
            return true
        }
        
        // 检查字体特性
        if let font = attributes[.font] as? NSFont {
            return font.fontDescriptor.symbolicTraits.contains(.italic)
        }
        
        return false
    }
    
    /// 检测属性中是否有下划线
    private static func isUnderlineInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let value = attributes[.underlineStyle] as? Int {
            return value != 0
        }
        return false
    }
    
    /// 检测属性中是否有删除线
    private static func isStrikethroughInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let value = attributes[.strikethroughStyle] as? Int {
            return value != 0
        }
        return false
    }
    
    /// 检测属性中是否有高亮
    /// 注意：需要区分高亮和引用块背景
    private static func isHighlightInAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        // 如果是引用块，不算作高亮
        if attributes[.quoteBlock] != nil {
            return false
        }
        return attributes[.backgroundColor] != nil
    }
    
    // MARK: - 私有方法 - 辅助
    
    /// 应用字体特性（加粗）
    private static func applyFontTrait(
        _ trait: NSFontDescriptor.SymbolicTraits,
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool
    ) {
        let fontManager = NSFontManager.shared
        
        textStorage.beginEditing()
        
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            let font = (value as? NSFont) ?? defaultFont
            let currentTraits = font.fontDescriptor.symbolicTraits
            let hasTrait = currentTraits.contains(trait)
            
            var newFont: NSFont?
            
            if trait == .bold {
                if toggle && hasTrait {
                    newFont = fontManager.convert(font, toNotHaveTrait: .boldFontMask)
                } else if !hasTrait {
                    newFont = fontManager.convert(font, toHaveTrait: .boldFontMask)
                } else {
                    newFont = font
                }
            }
            
            if let finalFont = newFont {
                textStorage.addAttribute(.font, value: finalFont, range: attrRange)
            }
        }
        
        textStorage.endEditing()
    }
    
    /// 切换属性
    private static func toggleAttribute(
        _ key: NSAttributedString.Key,
        value: Any,
        in range: NSRange,
        textStorage: NSTextStorage,
        toggle: Bool
    ) {
        textStorage.beginEditing()
        
        var hasAttribute = false
        
        if toggle {
            // 检查是否已有该属性
            textStorage.enumerateAttribute(key, in: range, options: []) { existingValue, _, stop in
                if existingValue != nil {
                    hasAttribute = true
                    stop.pointee = true
                }
            }
        }
        
        if hasAttribute {
            textStorage.removeAttribute(key, range: range)
        } else {
            textStorage.addAttribute(key, value: value, range: range)
        }
        
        textStorage.endEditing()
    }
    
    /// 从字体中移除内联特性（加粗、斜体）
    /// _Requirements: 2.1-2.6_
    private static func removeInlineTraitsFromFont(_ font: NSFont) -> NSFont {
        let fontManager = NSFontManager.shared
        var resultFont = font
        
        // 移除加粗
        if font.fontDescriptor.symbolicTraits.contains(.bold) {
            resultFont = fontManager.convert(resultFont, toNotHaveTrait: .boldFontMask)
        }
        
        // 移除斜体
        if font.fontDescriptor.symbolicTraits.contains(.italic) {
            resultFont = fontManager.convert(resultFont, toNotHaveTrait: .italicFontMask)
        }
        
        return resultFont
    }
}

// MARK: - 内联格式集合扩展

extension Set where Element == TextFormat {
    
    /// 获取集合中的所有内联格式
    public var inlineFormats: Set<TextFormat> {
        return self.filter { $0.category == .inline }
    }
    
    /// 检查是否包含任何内联格式
    public var hasInlineFormats: Bool {
        return self.contains { $0.category == .inline }
    }
}
