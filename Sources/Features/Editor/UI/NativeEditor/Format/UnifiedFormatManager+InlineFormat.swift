//
//  UnifiedFormatManager+InlineFormat.swift
//  MiNoteMac
//
//  内联格式应用逻辑（加粗、斜体、下划线、删除线、高亮）
//
//

import AppKit

// MARK: - 内联格式应用

public extension UnifiedFormatManager {

    /// 应用内联格式到选中文本
    ///
    /// 使用 InlineFormatHandler 统一处理所有内联格式
    ///
    /// - Parameters:
    ///   - format: 要应用的内联格式
    ///   - range: 应用范围
    ///   - toggle: 是否切换模式（默认 true）
    func applyInlineFormat(_ format: TextFormat, to range: NSRange, toggle: Bool = true) {
        guard let textStorage = currentTextStorage else {
            return
        }

        guard format.category == .inline else {
            return
        }

        InlineFormatHandler.apply(format, to: range, in: textStorage, toggle: toggle)
    }

    /// 应用多个内联格式到选中文本
    ///
    /// 确保多个内联格式可以同时生效
    ///
    /// - Parameters:
    ///   - formats: 要应用的内联格式集合
    ///   - range: 应用范围
    ///   - toggle: 是否切换模式（默认 true）
    func applyMultipleInlineFormats(_ formats: Set<TextFormat>, to range: NSRange, toggle: Bool = true) {
        guard let textStorage = currentTextStorage else {
            return
        }

        InlineFormatHandler.applyMultiple(formats, to: range, in: textStorage, toggle: toggle)
    }

    /// 检测指定位置的内联格式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 当前位置激活的内联格式集合
    func detectInlineFormats(at position: Int) -> Set<TextFormat> {
        guard let textStorage = currentTextStorage else {
            return []
        }

        return InlineFormatHandler.detect(at: position, in: textStorage)
    }

    /// 构建不包含内联格式的 typingAttributes
    ///
    /// 用于换行后清除内联格式
    ///
    /// - Parameter baseAttributes: 基础属性（可选）
    /// - Returns: 清除内联格式后的属性字典
    func buildCleanTypingAttributes(from baseAttributes: [NSAttributedString.Key: Any]? = nil) -> [NSAttributedString.Key: Any] {
        InlineFormatHandler.buildCleanTypingAttributes(from: baseAttributes)
    }
}
