import AppKit
import Foundation

/// 属性管理器
/// 负责管理和应用分层属性，协调三个属性层的工作
class AttributeManager {
    // MARK: - Properties

    /// 元属性层
    private let metaLayer: MetaAttributeLayer

    /// 布局属性层
    private let layoutLayer: LayoutAttributeLayer

    /// 装饰属性层
    private let decorativeLayer: DecorativeAttributeLayer

    // MARK: - Initialization

    /// 初始化属性管理器
    init() {
        self.metaLayer = MetaAttributeLayer()
        self.layoutLayer = LayoutAttributeLayer()
        self.decorativeLayer = DecorativeAttributeLayer()
    }

    // MARK: - Public Methods

    /// 应用分层属性到段落
    /// 按照 Meta → Layout → Decorative 的顺序应用属性
    /// - Parameters:
    ///   - paragraph: 段落对象
    ///   - textStorage: 文本存储对象
    func applyLayeredAttributes(
        for paragraph: Paragraph,
        in textStorage: NSTextStorage
    ) {
        let range = paragraph.range

        // 验证范围有效性
        guard range.location >= 0, NSMaxRange(range) <= textStorage.length else {
            return
        }

        // 按层次应用属性：Meta → Layout → Decorative
        // 这个顺序确保了结构属性优先，然后是布局，最后是装饰

        // 1. 应用元属性
        if !paragraph.metaAttributes.isEmpty {
            let metaAttrs = convertToAttributedStringKeys(paragraph.metaAttributes)
            metaLayer.apply(attributes: metaAttrs, to: range, in: textStorage)
        }

        // 2. 应用布局属性
        if !paragraph.layoutAttributes.isEmpty {
            let layoutAttrs = convertToAttributedStringKeys(paragraph.layoutAttributes)
            layoutLayer.apply(attributes: layoutAttrs, to: range, in: textStorage)
        }

        // 3. 应用装饰属性
        if !paragraph.decorativeAttributes.isEmpty {
            let decorativeAttrs = convertToAttributedStringKeys(paragraph.decorativeAttributes)
            decorativeLayer.apply(attributes: decorativeAttrs, to: range, in: textStorage)
        }
    }

    /// 更新指定属性层
    /// - Parameters:
    ///   - layerType: 要更新的层类型
    ///   - range: 更新范围
    ///   - textStorage: 文本存储对象
    func updateLayer(
        _ layerType: AttributeLayerType,
        in range: NSRange,
        textStorage: NSTextStorage
    ) {
        // 验证范围有效性
        guard range.location >= 0, NSMaxRange(range) <= textStorage.length else {
            return
        }

        // 根据层类型选择对应的层进行更新
        let layer: AttributeLayer = switch layerType {
        case .meta:
            metaLayer
        case .layout:
            layoutLayer
        case .decorative:
            decorativeLayer
        }

        // 获取当前位置的属性并重新应用
        // 这确保了属性的一致性
        if range.length > 0 {
            let attrs = layer.attributes(at: range.location, in: textStorage)
            if !attrs.isEmpty {
                layer.apply(attributes: attrs, to: range, in: textStorage)
            }
        }
    }

    /// 检测属性变化类型
    /// 比较新旧属性，识别哪些层发生了变化
    /// - Parameters:
    ///   - oldAttributes: 旧属性字典
    ///   - newAttributes: 新属性字典
    /// - Returns: 发生变化的层类型数组
    func detectChangedLayers(
        from oldAttributes: [NSAttributedString.Key: Any],
        to newAttributes: [NSAttributedString.Key: Any]
    ) -> [AttributeLayerType] {
        var changedLayers: [AttributeLayerType] = []

        // 检测元属性变化
        if hasMetaAttributeChanged(from: oldAttributes, to: newAttributes) {
            changedLayers.append(.meta)
        }

        // 检测布局属性变化
        if hasLayoutAttributeChanged(from: oldAttributes, to: newAttributes) {
            changedLayers.append(.layout)
        }

        // 检测装饰属性变化
        if hasDecorativeAttributeChanged(from: oldAttributes, to: newAttributes) {
            changedLayers.append(.decorative)
        }

        return changedLayers
    }

    /// 查询指定位置的分层属性
    /// - Parameters:
    ///   - location: 文本位置
    ///   - textStorage: 文本存储对象
    /// - Returns: 包含三个层属性的元组
    func queryLayeredAttributes(
        at location: Int,
        in textStorage: NSTextStorage
    ) -> (
        meta: [NSAttributedString.Key: Any],
        layout: [NSAttributedString.Key: Any],
        decorative: [NSAttributedString.Key: Any]
    ) {

        guard location >= 0, location < textStorage.length else {
            return ([:], [:], [:])
        }

        let metaAttrs = metaLayer.attributes(at: location, in: textStorage)
        let layoutAttrs = layoutLayer.attributes(at: location, in: textStorage)
        let decorativeAttrs = decorativeLayer.attributes(at: location, in: textStorage)

        return (metaAttrs, layoutAttrs, decorativeAttrs)
    }

    /// 解决属性冲突
    /// 当多个层定义了相同的属性时，按优先级解决冲突
    /// 优先级：Meta > Layout > Decorative
    /// - Parameter attributes: 包含所有层属性的字典
    /// - Returns: 解决冲突后的属性字典
    func resolveAttributeConflicts(
        _ attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var resolved: [NSAttributedString.Key: Any] = [:]

        // 首先应用装饰属性（最低优先级）
        for (key, value) in attributes {
            if isDecorativeAttribute(key) {
                resolved[key] = value
            }
        }

        // 然后应用布局属性（中等优先级）
        for (key, value) in attributes {
            if isLayoutAttribute(key) {
                resolved[key] = value
            }
        }

        // 最后应用元属性（最高优先级）
        for (key, value) in attributes {
            if isMetaAttribute(key) {
                resolved[key] = value
            }
        }

        return resolved
    }

    // MARK: - Private Helper Methods

    /// 检测元属性是否变化
    private func hasMetaAttributeChanged(
        from oldAttributes: [NSAttributedString.Key: Any],
        to newAttributes: [NSAttributedString.Key: Any]
    ) -> Bool {
        let oldMetaKeys = oldAttributes.keys.filter { isMetaAttribute($0) }
        let newMetaKeys = newAttributes.keys.filter { isMetaAttribute($0) }

        // 检查键集合是否变化
        if Set(oldMetaKeys) != Set(newMetaKeys) {
            return true
        }

        // 检查值是否变化
        for key in oldMetaKeys {
            if !areAttributeValuesEqual(oldAttributes[key], newAttributes[key]) {
                return true
            }
        }

        return false
    }

    /// 检测布局属性是否变化
    private func hasLayoutAttributeChanged(
        from oldAttributes: [NSAttributedString.Key: Any],
        to newAttributes: [NSAttributedString.Key: Any]
    ) -> Bool {
        let oldLayoutKeys = oldAttributes.keys.filter { isLayoutAttribute($0) }
        let newLayoutKeys = newAttributes.keys.filter { isLayoutAttribute($0) }

        if Set(oldLayoutKeys) != Set(newLayoutKeys) {
            return true
        }

        for key in oldLayoutKeys {
            if !areAttributeValuesEqual(oldAttributes[key], newAttributes[key]) {
                return true
            }
        }

        return false
    }

    /// 检测装饰属性是否变化
    private func hasDecorativeAttributeChanged(
        from oldAttributes: [NSAttributedString.Key: Any],
        to newAttributes: [NSAttributedString.Key: Any]
    ) -> Bool {
        let oldDecorativeKeys = oldAttributes.keys.filter { isDecorativeAttribute($0) }
        let newDecorativeKeys = newAttributes.keys.filter { isDecorativeAttribute($0) }

        if Set(oldDecorativeKeys) != Set(newDecorativeKeys) {
            return true
        }

        for key in oldDecorativeKeys {
            if !areAttributeValuesEqual(oldAttributes[key], newAttributes[key]) {
                return true
            }
        }

        return false
    }

    /// 判断是否为元属性
    private func isMetaAttribute(_ key: NSAttributedString.Key) -> Bool {
        key == .paragraphType ||
            key == .listLevel ||
            key == .listType ||
            key == .isTitle
    }

    /// 判断是否为布局属性
    private func isLayoutAttribute(_ key: NSAttributedString.Key) -> Bool {
        key == .paragraphStyle ||
            key == .font
    }

    /// 判断是否为装饰属性
    private func isDecorativeAttribute(_ key: NSAttributedString.Key) -> Bool {
        key == .foregroundColor ||
            key == .backgroundColor ||
            key == .underlineStyle ||
            key == .strikethroughStyle ||
            key == .strokeColor ||
            key == .strokeWidth
    }

    /// 比较两个属性值是否相等
    /// 处理不同类型的属性值比较
    private func areAttributeValuesEqual(_ value1: Any?, _ value2: Any?) -> Bool {
        // 如果都为 nil，则相等
        if value1 == nil, value2 == nil {
            return true
        }

        // 如果一个为 nil，另一个不为 nil，则不相等
        guard let v1 = value1, let v2 = value2 else {
            return false
        }

        // 处理 NSObject 类型的比较
        if let obj1 = v1 as? NSObject, let obj2 = v2 as? NSObject {
            return obj1.isEqual(obj2)
        }

        // 处理基本类型的比较
        if let num1 = v1 as? NSNumber, let num2 = v2 as? NSNumber {
            return num1 == num2
        }

        if let str1 = v1 as? String, let str2 = v2 as? String {
            return str1 == str2
        }

        // 默认使用指针比较
        return false
    }

    /// 将 [String: Any] 转换为 [NSAttributedString.Key: Any]
    /// 用于将段落的属性字典转换为 NSAttributedString 可用的格式
    private func convertToAttributedStringKeys(
        _ attributes: [String: Any]
    ) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [:]

        for (key, value) in attributes {
            let attributeKey = NSAttributedString.Key(key)
            result[attributeKey] = value
        }

        return result
    }
}

// MARK: - Convenience Methods

extension AttributeManager {
    /// 应用元属性到指定范围
    /// - Parameters:
    ///   - attributes: 元属性字典
    ///   - range: 应用范围
    ///   - textStorage: 文本存储对象
    func applyMetaAttributes(
        _ attributes: [NSAttributedString.Key: Any],
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        metaLayer.apply(attributes: attributes, to: range, in: textStorage)
    }

    /// 应用布局属性到指定范围
    /// - Parameters:
    ///   - attributes: 布局属性字典
    ///   - range: 应用范围
    ///   - textStorage: 文本存储对象
    func applyLayoutAttributes(
        _ attributes: [NSAttributedString.Key: Any],
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        layoutLayer.apply(attributes: attributes, to: range, in: textStorage)
    }

    /// 应用装饰属性到指定范围
    /// - Parameters:
    ///   - attributes: 装饰属性字典
    ///   - range: 应用范围
    ///   - textStorage: 文本存储对象
    func applyDecorativeAttributes(
        _ attributes: [NSAttributedString.Key: Any],
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        decorativeLayer.apply(attributes: attributes, to: range, in: textStorage)
    }

    /// 移除元属性
    /// - Parameters:
    ///   - keys: 要移除的属性键数组
    ///   - range: 移除范围
    ///   - textStorage: 文本存储对象
    func removeMetaAttributes(
        _ keys: [NSAttributedString.Key],
        from range: NSRange,
        in textStorage: NSTextStorage
    ) {
        metaLayer.remove(attributeKeys: keys, from: range, in: textStorage)
    }

    /// 移除布局属性
    /// - Parameters:
    ///   - keys: 要移除的属性键数组
    ///   - range: 移除范围
    ///   - textStorage: 文本存储对象
    func removeLayoutAttributes(
        _ keys: [NSAttributedString.Key],
        from range: NSRange,
        in textStorage: NSTextStorage
    ) {
        layoutLayer.remove(attributeKeys: keys, from: range, in: textStorage)
    }

    /// 移除装饰属性
    /// - Parameters:
    ///   - keys: 要移除的属性键数组
    ///   - range: 移除范围
    ///   - textStorage: 文本存储对象
    func removeDecorativeAttributes(
        _ keys: [NSAttributedString.Key],
        from range: NSRange,
        in textStorage: NSTextStorage
    ) {
        decorativeLayer.remove(attributeKeys: keys, from: range, in: textStorage)
    }
}
