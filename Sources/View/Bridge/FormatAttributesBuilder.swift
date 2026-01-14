//
//  FormatAttributesBuilder.swift
//  MiNoteMac
//
//  格式属性构建器 - 将 FormatState 转换为 NSAttributedString 属性字典
//  用于构建 typingAttributes，确保新输入的文字能继承正确的格式
//
//  _Requirements: 2.1-2.6, 3.1_
//

import Foundation
import AppKit

// MARK: - 格式属性构建器

/// 格式属性构建器
/// 将 FormatState 转换为 NSAttributedString 属性字典
/// _Requirements: 2.1-2.6, 3.1_
@MainActor
public struct FormatAttributesBuilder {
    
    // MARK: - 常量
    
    /// 默认字体
    /// 使用 FontSizeManager 统一管理，14pt（正文字体大小）
    /// _Requirements: 1.4, 3.2, 3.3_
    public static var defaultFont: NSFont { FontSizeManager.shared.defaultFont }
    
    /// 默认文本颜色
    public static let defaultTextColor = NSColor.labelColor
    
    /// 高亮背景色
    /// _Requirements: 2.5_
    public static let highlightColor = NSColor.yellow.withAlphaComponent(0.5)
    
    /// 标题字体大小 - 使用 FontSizeManager 统一管理
    /// _Requirements: 1.1, 1.2, 1.3, 1.4_
    private static var heading1FontSize: CGFloat { FontSizeManager.shared.heading1Size }  // 23pt
    private static var heading2FontSize: CGFloat { FontSizeManager.shared.heading2Size }  // 20pt
    private static var heading3FontSize: CGFloat { FontSizeManager.shared.heading3Size }  // 17pt
    private static var bodyFontSize: CGFloat { FontSizeManager.shared.bodySize }          // 14pt
    
    // MARK: - 主要构建方法
    
    /// 构建属性字典
    /// 
    /// 根据 FormatState 构建完整的 NSAttributedString 属性字典
    /// 用于设置 NSTextView 的 typingAttributes
    /// 
    /// - Parameter state: 格式状态
    /// - Returns: 属性字典
    /// _Requirements: 2.1-2.6, 3.1_
    public static func build(from state: FormatState) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        
        // 1. 构建字体（处理加粗、斜体）
        // _Requirements: 2.1, 2.2_
        let font = buildFont(from: state)
        attributes[.font] = font
        
        // 2. 设置文本颜色
        attributes[.foregroundColor] = defaultTextColor
        
        // 3. 添加下划线属性
        // _Requirements: 2.3_
        addUnderlineAttributes(to: &attributes, state: state)
        
        // 4. 添加删除线属性
        // _Requirements: 2.4_
        addStrikethroughAttributes(to: &attributes, state: state)
        
        // 5. 添加高亮属性
        // _Requirements: 2.5_
        addHighlightAttributes(to: &attributes, state: state)
        
        // 6. 添加斜体属性（使用 obliqueness 支持中文）
        // _Requirements: 2.2_
        addItalicObliqueness(to: &attributes, font: font, state: state)
        
        return attributes
    }
    
    // MARK: - 字体构建
    
    /// 构建字体
    /// 
    /// 根据格式状态构建字体，只处理加粗
    /// 斜体统一使用 obliqueness 属性实现，不依赖字体特性
    /// 
    /// - Parameter state: 格式状态
    /// - Returns: 字体
    /// _Requirements: 2.1, 2.2_
    public static func buildFont(from state: FormatState) -> NSFont {
        // 确定字体大小（根据段落格式）
        let fontSize = determineFontSize(for: state.paragraphFormat)
        
        // 构建字体描述符特性（只处理加粗，斜体使用 obliqueness）
        var traits: NSFontDescriptor.SymbolicTraits = []
        
        // 加粗
        // _Requirements: 2.1_
        if state.isBold {
            traits.insert(.bold)
        }
        
        // 注意：斜体不再使用字体特性，统一使用 obliqueness 属性
        // 这样可以确保中英文斜体行为一致
        
        // 创建基础字体
        let baseFont = NSFont.systemFont(ofSize: fontSize)
        
        // 如果没有特殊特性，返回基础字体
        if traits.isEmpty {
            return baseFont
        }
        
        // 尝试应用字体特性
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        if let font = NSFont(descriptor: descriptor, size: fontSize) {
            return font
        }
        
        // 如果无法应用特性，返回基础字体
        return baseFont
    }
    
    /// 确定字体大小
    /// 
    /// 根据段落格式确定字体大小
    /// 
    /// - Parameter paragraphFormat: 段落格式
    /// - Returns: 字体大小
    private static func determineFontSize(for paragraphFormat: ParagraphFormat) -> CGFloat {
        switch paragraphFormat {
        case .heading1:
            return heading1FontSize
        case .heading2:
            return heading2FontSize
        case .heading3:
            return heading3FontSize
        default:
            return bodyFontSize
        }
    }
    
    // MARK: - 装饰属性
    
    /// 添加下划线属性
    /// 
    /// 如果格式状态包含下划线，添加下划线样式属性
    /// 
    /// - Parameters:
    ///   - attributes: 属性字典（inout）
    ///   - state: 格式状态
    /// _Requirements: 2.3_
    public static func addUnderlineAttributes(to attributes: inout [NSAttributedString.Key: Any], state: FormatState) {
        if state.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
    }
    
    /// 添加删除线属性
    /// 
    /// 如果格式状态包含删除线，添加删除线样式属性
    /// 
    /// - Parameters:
    ///   - attributes: 属性字典（inout）
    ///   - state: 格式状态
    /// _Requirements: 2.4_
    public static func addStrikethroughAttributes(to attributes: inout [NSAttributedString.Key: Any], state: FormatState) {
        if state.isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
    }
    
    /// 添加高亮属性
    /// 
    /// 如果格式状态包含高亮，添加背景色属性
    /// 
    /// - Parameters:
    ///   - attributes: 属性字典（inout）
    ///   - state: 格式状态
    /// _Requirements: 2.5_
    public static func addHighlightAttributes(to attributes: inout [NSAttributedString.Key: Any], state: FormatState) {
        if state.isHighlight {
            attributes[.backgroundColor] = highlightColor
        }
    }
    
    /// 添加斜体 obliqueness 属性
    /// 
    /// 统一使用 obliqueness 属性实现斜体效果
    /// 不依赖字体的 .italic 特性，确保中英文斜体行为一致
    /// 
    /// - Parameters:
    ///   - attributes: 属性字典（inout）
    ///   - font: 当前字体（未使用，保留参数以保持 API 兼容）
    ///   - state: 格式状态
    /// _Requirements: 2.2_
    private static func addItalicObliqueness(to attributes: inout [NSAttributedString.Key: Any], font: NSFont, state: FormatState) {
        if state.isItalic {
            // 统一使用 obliqueness 实现斜体，不依赖字体特性
            // 0.2 是一个适中的斜体角度
            attributes[.obliqueness] = 0.2
        }
    }
    
    // MARK: - 便捷方法
    
    /// 构建默认属性字典
    /// 
    /// 返回默认格式状态对应的属性字典
    /// 用于空文档或光标在文档开头的情况
    /// 
    /// - Returns: 默认属性字典
    /// _Requirements: 3.2, 3.3_
    public static func buildDefault() -> [NSAttributedString.Key: Any] {
        return build(from: FormatState.default)
    }
    
    /// 从现有属性构建格式状态
    /// 
    /// 从 NSAttributedString 属性字典反向构建 FormatState
    /// 用于检测光标位置的格式状态
    /// 
    /// - Parameter attributes: 属性字典
    /// - Returns: 格式状态
    public static func extractFormatState(from attributes: [NSAttributedString.Key: Any]) -> FormatState {
        var state = FormatState()
        
        // 检测字体属性（加粗、斜体）
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            
            // 加粗检测
            if traits.contains(.bold) {
                state.isBold = true
            } else {
                // 备用检测：检查字体名称
                let fontName = font.fontName.lowercased()
                if fontName.contains("bold") {
                    state.isBold = true
                }
            }
            
            // 斜体检测
            if traits.contains(.italic) {
                state.isItalic = true
            } else {
                // 备用检测：检查字体名称
                let fontName = font.fontName.lowercased()
                if fontName.contains("italic") || fontName.contains("oblique") {
                    state.isItalic = true
                }
            }
        }
        
        // 斜体检测 - 使用 obliqueness 属性
        if let obliqueness = attributes[.obliqueness] as? Double, obliqueness > 0 {
            state.isItalic = true
        }
        
        // 下划线检测
        if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
            state.isUnderline = true
        }
        
        // 删除线检测
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
            state.isStrikethrough = true
        }
        
        // 高亮检测
        if let backgroundColor = attributes[.backgroundColor] as? NSColor {
            // 排除透明或白色背景
            if backgroundColor.alphaComponent > 0.1 && backgroundColor != .clear && backgroundColor != .white {
                state.isHighlight = true
            }
        }
        
        return state
    }
    
    /// 合并两个属性字典
    /// 
    /// 将新属性合并到现有属性中，新属性优先
    /// 
    /// - Parameters:
    ///   - existing: 现有属性字典
    ///   - new: 新属性字典
    /// - Returns: 合并后的属性字典
    public static func merge(existing: [NSAttributedString.Key: Any], with new: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = existing
        for (key, value) in new {
            result[key] = value
        }
        return result
    }
}
