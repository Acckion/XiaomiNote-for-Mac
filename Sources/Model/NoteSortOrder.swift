import Foundation

/// 笔记排序方式
public enum NoteSortOrder: String, Codable {
    case editDate
    case createDate
    case title
}

/// 排序方向
public enum SortDirection: String, Codable {
    case ascending
    case descending
}
