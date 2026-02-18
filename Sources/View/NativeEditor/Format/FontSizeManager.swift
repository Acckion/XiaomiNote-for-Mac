//
//  FontSizeManager.swift
//  MiNoteMac
//
//  字体大小管理器 - 统一管理所有字体大小常量和检测逻辑
//  确保整个系统使用一致的字体大小定义
//
//  字体大小规范：
//  - 大标题 (H1): 23pt
//  - 二级标题 (H2): 20pt
//  - 三级标题 (H3): 17pt
//  - 正文 (Body): 14pt
//
//  检测阈值：
//  - H1: fontSize >= 23
//  - H2: 20 <= fontSize < 23
//  - H3: 17 <= fontSize < 20
//  - Body: fontSize < 17
//
//  _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 6.1, 6.2, 6.3, 6.4, 6.5_
//

import AppKit

/// 字体大小管理器
/// 统一管理所有字体大小常量和检测逻辑
@MainActor
public final class FontSizeManager {

    // MARK: - Singleton

    /// 共享实例
    public static let shared = FontSizeManager()

    private init() {}

    // MARK: - 字体大小常量

    /// 大标题字体大小 (23pt)
    /// _Requirements: 1.1_
    public let heading1Size: CGFloat = 23

    /// 二级标题字体大小 (20pt)
    /// _Requirements: 1.2_
    public let heading2Size: CGFloat = 20

    /// 三级标题字体大小 (17pt)
    /// _Requirements: 1.3_
    public let heading3Size: CGFloat = 17

    /// 正文字体大小 (14pt)
    /// _Requirements: 1.4_
    public let bodySize: CGFloat = 14

    // MARK: - 检测阈值（与字体大小相同）

    /// 大标题检测阈值 (>= 23pt)
    /// _Requirements: 6.2_
    public var heading1Threshold: CGFloat {
        heading1Size
    }

    /// 二级标题检测阈值 (>= 20pt, < 23pt)
    /// _Requirements: 6.3_
    public var heading2Threshold: CGFloat {
        heading2Size
    }

    /// 三级标题检测阈值 (>= 17pt, < 20pt)
    /// _Requirements: 6.4_
    public var heading3Threshold: CGFloat {
        heading3Size
    }

    // MARK: - 公共方法

    /// 根据段落格式获取字体大小
    /// - Parameter format: 段落格式
    /// - Returns: 对应的字体大小
    /// _Requirements: 1.5_
    public func fontSize(for format: ParagraphFormat) -> CGFloat {
        switch format {
        case .heading1:
            heading1Size
        case .heading2:
            heading2Size
        case .heading3:
            heading3Size
        default:
            bodySize
        }
    }

    /// 根据标题级别获取字体大小
    /// - Parameter level: 标题级别 (1, 2, 3)
    /// - Returns: 对应的字体大小
    /// _Requirements: 1.5_
    public func fontSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            heading1Size
        case 2:
            heading2Size
        case 3:
            heading3Size
        default:
            bodySize
        }
    }

    /// 根据字体大小检测段落格式
    /// - Parameter fontSize: 字体大小
    /// - Returns: 检测到的段落格式
    /// _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_
    public func detectParagraphFormat(fontSize: CGFloat) -> ParagraphFormat {
        // 处理无效值
        guard fontSize > 0 else {
            return .body
        }

        // 使用统一的阈值检测
        // H1: fontSize >= 23
        // H2: 20 <= fontSize < 23
        // H3: 17 <= fontSize < 20
        // Body: fontSize < 17
        if fontSize >= heading1Threshold {
            return .heading1
        } else if fontSize >= heading2Threshold {
            return .heading2
        } else if fontSize >= heading3Threshold {
            return .heading3
        } else {
            return .body
        }
    }

    /// 根据字体大小检测标题级别
    /// - Parameter fontSize: 字体大小
    /// - Returns: 标题级别 (0=正文, 1=H1, 2=H2, 3=H3)
    /// _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_
    public func detectHeadingLevel(fontSize: CGFloat) -> Int {
        let format = detectParagraphFormat(fontSize: fontSize)
        switch format {
        case .heading1:
            return 1
        case .heading2:
            return 2
        case .heading3:
            return 3
        default:
            return 0
        }
    }

    /// 创建指定格式的字体（默认不加粗）
    /// - Parameters:
    ///   - format: 段落格式
    ///   - traits: 额外的字体特性（如加粗、斜体）
    /// - Returns: 创建的字体
    /// _Requirements: 2.1, 2.2, 2.3_
    public func createFont(
        for format: ParagraphFormat,
        traits: NSFontDescriptor.SymbolicTraits = []
    ) -> NSFont {
        let size = fontSize(for: format)
        return createFont(ofSize: size, traits: traits)
    }

    /// 创建指定大小的字体
    /// - Parameters:
    ///   - size: 字体大小
    ///   - traits: 额外的字体特性
    /// - Returns: 创建的字体
    public func createFont(
        ofSize size: CGFloat,
        traits: NSFontDescriptor.SymbolicTraits = []
    ) -> NSFont {
        // 如果没有额外特性，直接返回常规字重的系统字体
        if traits.isEmpty {
            return NSFont.systemFont(ofSize: size, weight: .regular)
        }

        // 创建基础字体
        let baseFont = NSFont.systemFont(ofSize: size, weight: .regular)
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)

        // 如果无法创建带特性的字体，返回基础字体
        return NSFont(descriptor: descriptor, size: size) ?? baseFont
    }

    /// 默认字体（正文大小，常规字重）
    /// _Requirements: 1.4_
    public var defaultFont: NSFont {
        createFont(for: .body)
    }
}

// MARK: - 静态常量（用于非 MainActor 上下文）

/// 字体大小常量枚举
/// 用于非 MainActor 上下文中访问字体大小值
/// _Requirements: 1.1, 1.2, 1.3, 1.4_
public enum FontSizeConstants {
    /// 大标题字体大小常量 (23pt)
    /// _Requirements: 1.1_
    public nonisolated(unsafe) static let heading1: CGFloat = 23

    /// 二级标题字体大小常量 (20pt)
    /// _Requirements: 1.2_
    public nonisolated(unsafe) static let heading2: CGFloat = 20

    /// 三级标题字体大小常量 (17pt)
    /// _Requirements: 1.3_
    public nonisolated(unsafe) static let heading3: CGFloat = 17

    /// 正文字体大小常量 (14pt)
    /// _Requirements: 1.4_
    public nonisolated(unsafe) static let body: CGFloat = 14

    /// 根据字体大小检测段落格式（静态方法，用于非 MainActor 上下文）
    /// - Parameter fontSize: 字体大小
    /// - Returns: 检测到的段落格式
    /// _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_
    public static func detectParagraphFormat(fontSize: CGFloat) -> ParagraphFormat {
        // 处理无效值
        guard fontSize > 0 else {
            return .body
        }

        // 使用统一的阈值检测
        // H1: fontSize >= 23
        // H2: 20 <= fontSize < 23
        // H3: 17 <= fontSize < 20
        // Body: fontSize < 17
        if fontSize >= heading1 {
            return .heading1
        } else if fontSize >= heading2 {
            return .heading2
        } else if fontSize >= heading3 {
            return .heading3
        } else {
            return .body
        }
    }
}

// MARK: - ParagraphFormat 扩展

public extension ParagraphFormat {
    /// 获取该格式对应的字体大小
    /// 注意：此属性需要在 MainActor 上下文中使用
    @MainActor
    var fontSize: CGFloat {
        FontSizeManager.shared.fontSize(for: self)
    }
}
