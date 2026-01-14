//
//  MixedFormatApplicationHandler.swift
//  MiNoteMac
//
//  混合格式应用处理器 - 处理选中文本包含多种格式时的格式应用逻辑
//  需求: 6.3
//

import AppKit
import SwiftUI

// MARK: - 混合格式应用策略

/// 混合格式应用策略
enum MixedFormatApplicationStrategy {
    /// 统一应用 - 将格式应用到整个选中范围
    case unifyApply
    /// 统一移除 - 从整个选中范围移除格式
    case unifyRemove
    /// 切换 - 根据主要状态切换（如果大部分有格式则移除，否则应用）
    case toggle
}

// MARK: - 混合格式应用处理器

/// 混合格式应用处理器
/// 
/// 负责处理选中文本包含多种格式时的格式应用逻辑。
/// 需求: 6.3
@MainActor
class MixedFormatApplicationHandler {
    
    // MARK: - Singleton
    
    static let shared = MixedFormatApplicationHandler()
    
    private init() {}
    
    // MARK: - Properties
    
    /// 切换阈值 - 超过此比例时认为格式已应用
    var toggleThreshold: Double = 0.5
    
    /// 默认应用策略
    var defaultStrategy: MixedFormatApplicationStrategy = .toggle
    
    // MARK: - Public Methods
    
    /// 应用格式到混合格式范围
    /// - Parameters:
    ///   - format: 格式类型
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - strategy: 应用策略（可选，默认使用 toggle）
    /// 需求: 6.3
    func applyFormat(
        _ format: TextFormat,
        to textStorage: NSTextStorage,
        range: NSRange,
        strategy: MixedFormatApplicationStrategy? = nil
    ) {
        guard range.length > 0 else { return }
        
        let effectiveStrategy = strategy ?? defaultStrategy
        let mixedHandler = MixedFormatStateHandler.shared
        let state = mixedHandler.detectFormatState(format, in: textStorage, range: range)
        
        print("[MixedFormatApplication] 应用格式: \(format.displayName)")
        print("[MixedFormatApplication]   - 范围: \(range)")
        print("[MixedFormatApplication]   - 当前状态: \(state.stateType), 激活比例: \(String(format: "%.2f", state.activationRatio))")
        print("[MixedFormatApplication]   - 策略: \(effectiveStrategy)")
        
        // 根据策略决定操作
        let shouldApply: Bool
        switch effectiveStrategy {
        case .unifyApply:
            shouldApply = true
        case .unifyRemove:
            shouldApply = false
        case .toggle:
            // 根据激活比例决定
            shouldApply = state.activationRatio < toggleThreshold
        }
        
        print("[MixedFormatApplication]   - 决定: \(shouldApply ? "应用" : "移除")")
        
        // 执行格式操作
        textStorage.beginEditing()
        
        if shouldApply {
            applyFormatToEntireRange(format, to: textStorage, range: range)
        } else {
            removeFormatFromEntireRange(format, from: textStorage, range: range)
        }
        
        textStorage.endEditing()
        
        print("[MixedFormatApplication] ✅ 格式操作完成")
    }
    
    /// 强制应用格式到整个范围（不考虑当前状态）
    /// - Parameters:
    ///   - format: 格式类型
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func forceApplyFormat(
        _ format: TextFormat,
        to textStorage: NSTextStorage,
        range: NSRange
    ) {
        guard range.length > 0 else { return }
        
        textStorage.beginEditing()
        applyFormatToEntireRange(format, to: textStorage, range: range)
        textStorage.endEditing()
    }
    
    /// 强制移除格式从整个范围（不考虑当前状态）
    /// - Parameters:
    ///   - format: 格式类型
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func forceRemoveFormat(
        _ format: TextFormat,
        from textStorage: NSTextStorage,
        range: NSRange
    ) {
        guard range.length > 0 else { return }
        
        textStorage.beginEditing()
        removeFormatFromEntireRange(format, from: textStorage, range: range)
        textStorage.endEditing()
    }
    
    // MARK: - Private Methods
    
    /// 应用格式到整个范围
    private func applyFormatToEntireRange(
        _ format: TextFormat,
        to textStorage: NSTextStorage,
        range: NSRange
    ) {
        switch format {
        case .bold:
            applyBoldToEntireRange(to: textStorage, range: range)
        case .italic:
            applyItalicToEntireRange(to: textStorage, range: range)
        case .underline:
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .strikethrough:
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .highlight:
            let highlightColor = NSColor(hex: "#9affe8af") ?? NSColor.systemYellow
            textStorage.addAttribute(.backgroundColor, value: highlightColor, range: range)
        default:
            // 块级格式使用 FormatManager 处理
            FormatManager.shared.applyFormat(format, to: textStorage, range: range)
        }
    }
    
    /// 移除格式从整个范围
    private func removeFormatFromEntireRange(
        _ format: TextFormat,
        from textStorage: NSTextStorage,
        range: NSRange
    ) {
        switch format {
        case .bold:
            removeBoldFromEntireRange(from: textStorage, range: range)
        case .italic:
            removeItalicFromEntireRange(from: textStorage, range: range)
        case .underline:
            textStorage.removeAttribute(.underlineStyle, range: range)
        case .strikethrough:
            textStorage.removeAttribute(.strikethroughStyle, range: range)
        case .highlight:
            textStorage.removeAttribute(.backgroundColor, range: range)
        default:
            // 块级格式使用 FormatManager 处理
            // 对于块级格式，移除操作通常是切换操作
            break
        }
    }
    
    /// 应用加粗到整个范围
    private func applyBoldToEntireRange(to textStorage: NSTextStorage, range: NSRange) {
        let fontManager = NSFontManager.shared
        
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            // 修复：使用 13pt（正文字体大小），与 FormatAttributesBuilder.bodyFontSize 保持一致
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let traits = font.fontDescriptor.symbolicTraits
            
            // 如果还没有加粗，则添加
            if !traits.contains(.bold) {
                let boldFont = fontManager.convert(font, toHaveTrait: .boldFontMask)
                textStorage.addAttribute(.font, value: boldFont, range: attrRange)
            }
        }
    }
    
    /// 移除加粗从整个范围
    private func removeBoldFromEntireRange(from textStorage: NSTextStorage, range: NSRange) {
        let fontManager = NSFontManager.shared
        
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            
            // 如果有加粗，则移除
            if traits.contains(.bold) {
                let normalFont = fontManager.convert(font, toNotHaveTrait: .boldFontMask)
                textStorage.addAttribute(.font, value: normalFont, range: attrRange)
            }
        }
    }
    
    /// 应用斜体到整个范围
    private func applyItalicToEntireRange(to textStorage: NSTextStorage, range: NSRange) {
        let fontManager = NSFontManager.shared
        
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            // 修复：使用 13pt（正文字体大小），与 FormatAttributesBuilder.bodyFontSize 保持一致
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let traits = font.fontDescriptor.symbolicTraits
            
            // 如果还没有斜体，则添加
            if !traits.contains(.italic) {
                let italicFont = fontManager.convert(font, toHaveTrait: .italicFontMask)
                textStorage.addAttribute(.font, value: italicFont, range: attrRange)
            }
        }
    }
    
    /// 移除斜体从整个范围
    private func removeItalicFromEntireRange(from textStorage: NSTextStorage, range: NSRange) {
        let fontManager = NSFontManager.shared
        
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            
            // 如果有斜体，则移除
            if traits.contains(.italic) {
                let normalFont = fontManager.convert(font, toNotHaveTrait: .italicFontMask)
                textStorage.addAttribute(.font, value: normalFont, range: attrRange)
            }
        }
    }
}

// MARK: - NativeEditorContext Extension

extension NativeEditorContext {
    
    /// 应用格式到当前选中范围（支持混合格式处理）
    /// - Parameter format: 格式类型
    /// 需求: 6.3
    func applyFormatToSelection(_ format: TextFormat) {
        // 如果有选中范围，使用混合格式处理
        if selectedRange.length > 0 {
            // 发布格式变化，让 NativeEditorView 处理实际的格式应用
            // 混合格式处理逻辑已经集成到 NativeEditorView.Coordinator.applyFormat 中
            applyFormat(format)
        } else {
            // 没有选中范围，使用原有逻辑
            applyFormat(format)
        }
    }
}
