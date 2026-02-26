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

// MARK: - ParagraphType 与 TextFormat 双向转换

public extension ParagraphType {

    /// 从 TextFormat 创建 ParagraphType
    /// 仅段落级格式（标题、列表、引用）可转换，内联和对齐格式返回 nil
    static func from(_ textFormat: TextFormat) -> ParagraphType? {
        switch textFormat {
        case .heading1: .heading(level: 1)
        case .heading2: .heading(level: 2)
        case .heading3: .heading(level: 3)
        case .bulletList: .list(.bullet)
        case .numberedList: .list(.ordered)
        case .checkbox: .list(.checkbox)
        case .quote: .quote
        default: nil
        }
    }

    /// 转换为 TextFormat
    /// .normal、.title、.code 等无对应 TextFormat 的类型返回 nil
    var textFormat: TextFormat? {
        switch self {
        case let .heading(level):
            switch level {
            case 1: .heading1
            case 2: .heading2
            case 3: .heading3
            default: nil
            }
        case let .list(listType):
            switch listType {
            case .bullet: .bulletList
            case .ordered: .numberedList
            case .checkbox: .checkbox
            case .none: nil
            }
        case .quote: .quote
        case .normal: nil
        default: nil
        }
    }
}

// MARK: - ParagraphType 与 ParagraphFormat 双向转换

public extension ParagraphType {

    /// 转换为 ParagraphFormat
    /// .title、.code、.quote 在 ParagraphFormat 中无对应值，映射到 .body
    var paragraphFormat: ParagraphFormat {
        switch self {
        case let .heading(level):
            switch level {
            case 1: .heading1
            case 2: .heading2
            case 3: .heading3
            default: .body
            }
        case let .list(listType):
            switch listType {
            case .bullet: .bulletList
            case .ordered: .numberedList
            case .checkbox: .checkbox
            case .none: .body
            }
        case .normal, .title, .quote, .code: .body
        }
    }
}
