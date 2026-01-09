//
//  ViewOptionsState.swift
//  MiNoteMac
//
//  视图选项状态管理
//

import Foundation

// MARK: - 视图模式枚举

/// 视图模式枚举
/// 
/// 定义笔记列表的显示模式
/// _Requirements: 4.2, 4.3_
public enum ViewMode: String, Codable, CaseIterable {
    /// 列表视图 - 传统的垂直列表形式展示笔记
    case list = "list"
    
    /// 画廊视图 - 以卡片网格形式展示笔记预览
    case gallery = "gallery"
}

// MARK: - ViewMode 扩展

extension ViewMode {
    /// 显示名称
    var displayName: String {
        switch self {
        case .list:
            return "列表视图"
        case .gallery:
            return "画廊视图"
        }
    }
    
    /// 图标名称
    var icon: String {
        switch self {
        case .list:
            return "list.bullet"
        case .gallery:
            return "square.grid.2x2"
        }
    }
}

// MARK: - 视图选项状态

/// 视图选项状态
/// 
/// 管理笔记列表的显示选项，包括排序方式、排序方向、日期分组和视图模式
/// _Requirements: 2.3, 2.7, 2.9, 3.3, 3.6, 4.7_
public struct ViewOptionsState: Codable, Equatable {
    /// 排序方式
    public var sortOrder: NoteSortOrder
    
    /// 排序方向
    public var sortDirection: SortDirection
    
    /// 是否启用日期分组
    public var isDateGroupingEnabled: Bool
    
    /// 视图模式
    public var viewMode: ViewMode
    
    /// 初始化方法
    /// - Parameters:
    ///   - sortOrder: 排序方式，默认为编辑时间
    ///   - sortDirection: 排序方向，默认为降序
    ///   - isDateGroupingEnabled: 是否启用日期分组，默认为 true
    ///   - viewMode: 视图模式，默认为列表视图
    public init(
        sortOrder: NoteSortOrder = .editDate,
        sortDirection: SortDirection = .descending,
        isDateGroupingEnabled: Bool = true,
        viewMode: ViewMode = .list
    ) {
        self.sortOrder = sortOrder
        self.sortDirection = sortDirection
        self.isDateGroupingEnabled = isDateGroupingEnabled
        self.viewMode = viewMode
    }
    
    /// 默认值
    public static var `default`: ViewOptionsState {
        ViewOptionsState(
            sortOrder: .editDate,
            sortDirection: .descending,
            isDateGroupingEnabled: true,
            viewMode: .list
        )
    }
}

// MARK: - NoteSortOrder 扩展

extension NoteSortOrder {
    /// 显示名称
    var displayName: String {
        switch self {
        case .editDate:
            return "编辑时间"
        case .createDate:
            return "创建时间"
        case .title:
            return "标题"
        }
    }
    
    /// 图标名称
    var icon: String {
        switch self {
        case .editDate:
            return "pencil"
        case .createDate:
            return "calendar.badge.plus"
        case .title:
            return "textformat"
        }
    }
}

// MARK: - SortDirection 扩展

extension SortDirection {
    /// 显示名称
    var displayName: String {
        switch self {
        case .ascending:
            return "升序"
        case .descending:
            return "降序"
        }
    }
    
    /// 图标名称
    var icon: String {
        switch self {
        case .ascending:
            return "arrow.up"
        case .descending:
            return "arrow.down"
        }
    }
}
