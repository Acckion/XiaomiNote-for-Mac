import Foundation

/// 段落类型枚举
/// 定义编辑器中支持的所有段落类型
enum ParagraphType: Equatable, Hashable {
    /// 标题段落（特殊）- 始终是编辑器中的第一个段落
    case title
    
    /// 标题 H1-H6
    case heading(level: Int)
    
    /// 普通段落
    case normal
    
    /// 列表段落
    case list(ListType)
    
    /// 引用段落
    case quote
    
    /// 代码块段落
    case code
}

/// 列表类型
enum ListType: Equatable, Hashable {
    /// 无序列表（项目符号）
    case bullet
    
    /// 有序列表（编号）
    case numbered
    
    /// 复选框列表
    case checkbox(checked: Bool)
}

// MARK: - CustomStringConvertible

extension ParagraphType: CustomStringConvertible {
    var description: String {
        switch self {
        case .title:
            return "标题段落"
        case .heading(let level):
            return "H\(level) 标题"
        case .normal:
            return "普通段落"
        case .list(let listType):
            return "列表段落 (\(listType))"
        case .quote:
            return "引用段落"
        case .code:
            return "代码块段落"
        }
    }
}

extension ListType: CustomStringConvertible {
    var description: String {
        switch self {
        case .bullet:
            return "无序列表"
        case .numbered:
            return "有序列表"
        case .checkbox(let checked):
            return "复选框列表 (\(checked ? "已选中" : "未选中"))"
        }
    }
}
