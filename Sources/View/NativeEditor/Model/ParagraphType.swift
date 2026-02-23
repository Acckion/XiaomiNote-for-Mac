import Foundation

/// 段落类型枚举
/// 定义编辑器中支持的所有段落类型
public enum ParagraphType: Equatable, Hashable {
    /// 标题段落（向后兼容保留，新架构中标题独立于编辑器）
    case title

    /// 标题 H1-H6
    case heading(level: Int)

    /// 普通段落
    case normal

    /// 列表段落
    /// 注意：使用 FormatTypes.swift 中定义的 ListType
    case list(ListType)

    /// 引用段落
    case quote

    /// 代码块段落
    case code
}

// 注意：ListType 已在 FormatTypes.swift 中定义
// public enum ListType: Equatable {
//     case bullet     // 无序列表
//     case ordered    // 有序列表
//     case checkbox   // 复选框列表
//     case none       // 非列表
// }

// MARK: - CustomStringConvertible

extension ParagraphType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .title:
            "标题段落"
        case let .heading(level):
            "H\(level) 标题"
        case .normal:
            "普通段落"
        case let .list(listType):
            "列表段落 (\(listType))"
        case .quote:
            "引用段落"
        case .code:
            "代码块段落"
        }
    }
}
