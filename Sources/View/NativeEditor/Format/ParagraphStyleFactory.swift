//
//  ParagraphStyleFactory.swift
//  MiNoteMac
//
//  统一的段落样式工厂
//  集中管理所有段落样式的创建，确保行距、段落间距和行高属性的一致性
//

import AppKit
import Foundation

// MARK: - 段落样式工厂

/// 段落样式工厂
/// 统一创建所有段落样式，确保 lineSpacing、paragraphSpacing、minimumLineHeight 等属性不遗漏
public enum ParagraphStyleFactory {

    // MARK: - 常量

    /// 默认行间距
    public static let defaultLineSpacing: CGFloat = 4

    /// 默认段落间距
    public static let defaultParagraphSpacing: CGFloat = 8

    /// 行高倍数（用于计算 minimumLineHeight 和 maximumLineHeight）
    public static let lineHeightMultiplier: CGFloat = 1.2

    /// 缩进单位（像素）
    public static let indentUnit: CGFloat = 20

    /// 无序列表项目符号宽度
    public static let bulletWidth: CGFloat = 24

    /// 有序列表编号宽度
    public static let orderNumberWidth: CGFloat = 28

    /// 引用块边框宽度
    public static let quoteBorderWidth: CGFloat = 3

    /// 引用块内边距
    public static let quotePadding: CGFloat = 12

    // MARK: - 工厂方法

    /// 创建默认段落样式
    ///
    /// 包含 lineSpacing、paragraphSpacing，大字体时自动设置 minimumLineHeight 和 maximumLineHeight
    ///
    /// - Parameters:
    ///   - alignment: 对齐方式，默认 .left
    ///   - fontSize: 字体大小，默认正文大小（14pt）
    /// - Returns: 段落样式
    public static func makeDefault(
        alignment: NSTextAlignment = .left,
        fontSize: CGFloat = FontSizeConstants.body
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        applyLineHeightProperties(to: style, fontSize: fontSize)
        return style
    }

    /// 创建列表段落样式
    ///
    /// 包含缩进、制表位和行距属性，缩进计算逻辑与现有代码一致
    ///
    /// - Parameters:
    ///   - indent: 缩进级别（从 1 开始）
    ///   - bulletWidth: 列表标记宽度
    ///   - alignment: 对齐方式，默认 .left
    ///   - fontSize: 字体大小，默认正文大小（14pt）
    /// - Returns: 段落样式
    public static func makeList(
        indent: Int,
        bulletWidth: CGFloat,
        alignment: NSTextAlignment = .left,
        fontSize: CGFloat = FontSizeConstants.body
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        let baseIndent = CGFloat(indent - 1) * indentUnit

        style.firstLineHeadIndent = baseIndent
        style.headIndent = baseIndent + bulletWidth
        style.tabStops = [NSTextTab(textAlignment: .left, location: baseIndent + bulletWidth)]
        style.defaultTabInterval = indentUnit
        style.alignment = alignment

        applyLineHeightProperties(to: style, fontSize: fontSize)
        return style
    }

    /// 创建引用块段落样式
    ///
    /// 包含缩进和行距属性，缩进计算逻辑与现有代码一致
    ///
    /// - Parameters:
    ///   - indent: 缩进级别（从 1 开始），默认 1
    ///   - alignment: 对齐方式，默认 .left
    ///   - fontSize: 字体大小，默认正文大小（14pt）
    /// - Returns: 段落样式
    public static func makeQuote(
        indent: Int = 1,
        alignment: NSTextAlignment = .left,
        fontSize: CGFloat = FontSizeConstants.body
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        let baseIndent = CGFloat(indent - 1) * indentUnit

        style.firstLineHeadIndent = baseIndent + quoteBorderWidth + quotePadding
        style.headIndent = baseIndent + quoteBorderWidth + quotePadding
        style.alignment = alignment

        applyLineHeightProperties(to: style, fontSize: fontSize)
        return style
    }

    // MARK: - 私有方法

    /// 统一设置行距和行高属性
    ///
    /// fontSize > 14pt 时自动设置 minimumLineHeight 和 maximumLineHeight，
    /// 确保空行高度跟随字体大小
    private static func applyLineHeightProperties(to style: NSMutableParagraphStyle, fontSize: CGFloat) {
        style.lineSpacing = defaultLineSpacing
        style.paragraphSpacing = defaultParagraphSpacing

        if fontSize > FontSizeConstants.body {
            let lineHeight = fontSize * lineHeightMultiplier
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
        }
    }
}
