import AppKit
import Foundation

/// 属性层类型
/// 定义三种不同的属性层，用于分层管理文本属性
enum AttributeLayerType {
    /// 元属性层 - 标识文本结构的属性（如标题、列表、引用等）
    case meta

    /// 布局属性层 - 影响布局的属性（如 NSParagraphStyle、字体大小等）
    case layout

    /// 装饰属性层 - 纯视觉效果的属性（如颜色、背景色等）
    case decorative
}

/// 属性层协议
/// 定义属性层的基本行为，用于分层管理和应用文本属性
protocol AttributeLayer {
    /// 层类型
    var type: AttributeLayerType { get }

    /// 应用属性到指定范围
    /// - Parameters:
    ///   - attributes: 要应用的属性字典
    ///   - range: 应用范围
    ///   - textStorage: 文本存储对象
    func apply(
        attributes: [NSAttributedString.Key: Any],
        to range: NSRange,
        in textStorage: NSTextStorage
    )

    /// 移除指定的属性
    /// - Parameters:
    ///   - keys: 要移除的属性键数组
    ///   - range: 移除范围
    ///   - textStorage: 文本存储对象
    func remove(
        attributeKeys keys: [NSAttributedString.Key],
        from range: NSRange,
        in textStorage: NSTextStorage
    )

    /// 获取指定位置的属性
    /// - Parameters:
    ///   - location: 文本位置
    ///   - textStorage: 文本存储对象
    /// - Returns: 该位置的属性字典
    func attributes(
        at location: Int,
        in textStorage: NSTextStorage
    ) -> [NSAttributedString.Key: Any]
}

// MARK: - Meta Attribute Layer

/// 元属性层实现
/// 管理标识文本结构的属性，如段落类型、列表级别等
class MetaAttributeLayer: AttributeLayer {
    let type: AttributeLayerType = .meta

    func apply(
        attributes: [NSAttributedString.Key: Any],
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        // 元属性的变化会触发完整的段落重新解析
        // 因此需要在应用前记录日志
        #if DEBUG
            print("[MetaAttributeLayer] 应用元属性到范围 \(range): \(attributes.keys)")
        #endif

        textStorage.addAttributes(attributes, range: range)
    }

    func remove(
        attributeKeys keys: [NSAttributedString.Key],
        from range: NSRange,
        in textStorage: NSTextStorage
    ) {
        #if DEBUG
            print("[MetaAttributeLayer] 移除元属性从范围 \(range): \(keys)")
        #endif

        for key in keys {
            textStorage.removeAttribute(key, range: range)
        }
    }

    func attributes(
        at location: Int,
        in textStorage: NSTextStorage
    ) -> [NSAttributedString.Key: Any] {
        guard location < textStorage.length else {
            return [:]
        }

        let allAttributes = textStorage.attributes(at: location, effectiveRange: nil)

        // 过滤出元属性
        return allAttributes.filter { key, _ in
            isMetaAttribute(key)
        }
    }

    /// 判断是否为元属性
    private func isMetaAttribute(_ key: NSAttributedString.Key) -> Bool {
        // 元属性包括：段落类型、列表级别、列表类型等
        key == .paragraphType ||
            key == .listLevel ||
            key == .listType ||
            key == .isTitle
    }
}

// MARK: - Layout Attribute Layer

/// 布局属性层实现
/// 管理影响布局的属性，如段落样式、字体大小等
class LayoutAttributeLayer: AttributeLayer {
    let type: AttributeLayerType = .layout

    func apply(
        attributes: [NSAttributedString.Key: Any],
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        // 布局属性的变化会触发布局更新
        #if DEBUG
            print("[LayoutAttributeLayer] 应用布局属性到范围 \(range): \(attributes.keys)")
        #endif

        textStorage.addAttributes(attributes, range: range)
    }

    func remove(
        attributeKeys keys: [NSAttributedString.Key],
        from range: NSRange,
        in textStorage: NSTextStorage
    ) {
        #if DEBUG
            print("[LayoutAttributeLayer] 移除布局属性从范围 \(range): \(keys)")
        #endif

        for key in keys {
            textStorage.removeAttribute(key, range: range)
        }
    }

    func attributes(
        at location: Int,
        in textStorage: NSTextStorage
    ) -> [NSAttributedString.Key: Any] {
        guard location < textStorage.length else {
            return [:]
        }

        let allAttributes = textStorage.attributes(at: location, effectiveRange: nil)

        // 过滤出布局属性
        return allAttributes.filter { key, _ in
            isLayoutAttribute(key)
        }
    }

    /// 判断是否为布局属性
    private func isLayoutAttribute(_ key: NSAttributedString.Key) -> Bool {
        // 布局属性包括：段落样式、字体等
        key == .paragraphStyle ||
            key == .font
    }
}

// MARK: - Decorative Attribute Layer

/// 装饰属性层实现
/// 管理纯视觉效果的属性，如颜色、背景色、下划线等
class DecorativeAttributeLayer: AttributeLayer {
    let type: AttributeLayerType = .decorative

    func apply(
        attributes: [NSAttributedString.Key: Any],
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        // 装饰属性的变化只触发视觉重绘，不影响布局
        #if DEBUG
            print("[DecorativeAttributeLayer] 应用装饰属性到范围 \(range): \(attributes.keys)")
        #endif

        textStorage.addAttributes(attributes, range: range)
    }

    func remove(
        attributeKeys keys: [NSAttributedString.Key],
        from range: NSRange,
        in textStorage: NSTextStorage
    ) {
        #if DEBUG
            print("[DecorativeAttributeLayer] 移除装饰属性从范围 \(range): \(keys)")
        #endif

        for key in keys {
            textStorage.removeAttribute(key, range: range)
        }
    }

    func attributes(
        at location: Int,
        in textStorage: NSTextStorage
    ) -> [NSAttributedString.Key: Any] {
        guard location < textStorage.length else {
            return [:]
        }

        let allAttributes = textStorage.attributes(at: location, effectiveRange: nil)

        // 过滤出装饰属性
        return allAttributes.filter { key, _ in
            isDecorativeAttribute(key)
        }
    }

    /// 判断是否为装饰属性
    private func isDecorativeAttribute(_ key: NSAttributedString.Key) -> Bool {
        // 装饰属性包括：颜色、背景色、下划线、删除线等
        key == .foregroundColor ||
            key == .backgroundColor ||
            key == .underlineStyle ||
            key == .strikethroughStyle ||
            key == .strokeColor ||
            key == .strokeWidth
    }
}

// MARK: - Custom Attribute Keys

extension NSAttributedString.Key {
    /// 段落类型属性键
    static let paragraphType = NSAttributedString.Key("ParagraphType")

    /// 段落版本属性键
    static let paragraphVersion = NSAttributedString.Key("ParagraphVersion")

    /// 是否为标题段落属性键
    public static let isTitle = NSAttributedString.Key("IsTitle")

    /// 列表级别属性键
    static let listLevel = NSAttributedString.Key("ListLevel")

    // 注意：listType 已在 FormatManager.swift 中定义
    // static let listType = NSAttributedString.Key("listType")
}
