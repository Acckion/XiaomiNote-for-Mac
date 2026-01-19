import Foundation
import AppKit

/// 段落模型
/// 表示编辑器中的一个段落，包含其范围、类型、属性和版本信息
struct Paragraph {
    /// 段落在文本中的范围
    let range: NSRange
    
    /// 段落类型
    let type: ParagraphType
    
    /// 段落的元属性（Meta Attributes）
    /// 标识文本结构的属性，如标题、列表、引用等
    let metaAttributes: [String: Any]
    
    /// 段落的布局属性（Layout Attributes）
    /// 影响布局的属性，如 NSParagraphStyle、字体大小等
    let layoutAttributes: [String: Any]
    
    /// 段落的装饰属性（Decorative Attributes）
    /// 纯视觉效果的属性，如颜色、背景色等
    let decorativeAttributes: [String: Any]
    
    /// 段落版本号（用于增量更新）
    /// 每次段落内容变化时递增，用于判断是否需要重新解析
    var version: Int
    
    /// 段落是否需要重新解析
    /// 当元属性变化或内容发生结构性变化时设置为 true
    var needsReparse: Bool
    
    /// 初始化段落
    /// - Parameters:
    ///   - range: 段落在文本中的范围
    ///   - type: 段落类型
    ///   - metaAttributes: 元属性字典
    ///   - layoutAttributes: 布局属性字典
    ///   - decorativeAttributes: 装饰属性字典
    ///   - version: 版本号，默认为 0
    ///   - needsReparse: 是否需要重新解析，默认为 true
    init(
        range: NSRange,
        type: ParagraphType,
        metaAttributes: [String: Any] = [:],
        layoutAttributes: [String: Any] = [:],
        decorativeAttributes: [String: Any] = [:],
        version: Int = 0,
        needsReparse: Bool = true
    ) {
        self.range = range
        self.type = type
        self.metaAttributes = metaAttributes
        self.layoutAttributes = layoutAttributes
        self.decorativeAttributes = decorativeAttributes
        self.version = version
        self.needsReparse = needsReparse
    }
}

// MARK: - Convenience Properties

extension Paragraph {
    /// 段落是否为标题段落
    var isTitle: Bool {
        type == .title
    }
    
    /// 段落是否为标题（H1-H6）
    var isHeading: Bool {
        if case .heading = type {
            return true
        }
        return false
    }
    
    /// 段落是否为列表
    var isList: Bool {
        if case .list = type {
            return true
        }
        return false
    }
    
    /// 段落是否为引用
    var isQuote: Bool {
        type == .quote
    }
    
    /// 段落是否为代码块
    var isCode: Bool {
        type == .code
    }
    
    /// 段落的长度
    var length: Int {
        range.length
    }
    
    /// 段落的起始位置
    var location: Int {
        range.location
    }
    
    /// 段落的结束位置（不包含）
    var endLocation: Int {
        range.location + range.length
    }
}

// MARK: - Mutation Methods

extension Paragraph {
    /// 创建一个新的段落，更新版本号
    /// - Returns: 版本号递增的新段落
    func incrementVersion() -> Paragraph {
        var newParagraph = self
        newParagraph.version += 1
        return newParagraph
    }
    
    /// 创建一个新的段落，标记为需要重新解析
    /// - Returns: 标记为需要重新解析的新段落
    func markNeedsReparse() -> Paragraph {
        var newParagraph = self
        newParagraph.needsReparse = true
        return newParagraph
    }
    
    /// 创建一个新的段落，清除重新解析标记
    /// - Returns: 清除重新解析标记的新段落
    func clearReparseFlag() -> Paragraph {
        var newParagraph = self
        newParagraph.needsReparse = false
        return newParagraph
    }
    
    /// 创建一个新的段落，更新范围
    /// - Parameter newRange: 新的范围
    /// - Returns: 更新范围后的新段落
    func withRange(_ newRange: NSRange) -> Paragraph {
        Paragraph(
            range: newRange,
            type: type,
            metaAttributes: metaAttributes,
            layoutAttributes: layoutAttributes,
            decorativeAttributes: decorativeAttributes,
            version: version,
            needsReparse: needsReparse
        )
    }
    
    /// 创建一个新的段落，更新类型
    /// - Parameter newType: 新的段落类型
    /// - Returns: 更新类型后的新段落
    func withType(_ newType: ParagraphType) -> Paragraph {
        Paragraph(
            range: range,
            type: newType,
            metaAttributes: metaAttributes,
            layoutAttributes: layoutAttributes,
            decorativeAttributes: decorativeAttributes,
            version: version + 1,  // 类型变化时递增版本
            needsReparse: true     // 类型变化需要重新解析
        )
    }
}

// MARK: - CustomStringConvertible

extension Paragraph: CustomStringConvertible {
    var description: String {
        "Paragraph(range: \(range), type: \(type), version: \(version), needsReparse: \(needsReparse))"
    }
}

// MARK: - Equatable

extension Paragraph: Equatable {
    static func == (lhs: Paragraph, rhs: Paragraph) -> Bool {
        lhs.range == rhs.range &&
        lhs.type == rhs.type &&
        lhs.version == rhs.version &&
        lhs.needsReparse == rhs.needsReparse
        // 注意：这里不比较属性字典，因为字典比较复杂且通常不需要
    }
}
