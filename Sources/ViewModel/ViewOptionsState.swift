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
public enum ViewMode: String, Codable, CaseIterable {
    /// 列表视图 - 传统的垂直列表形式展示笔记
    case list

    /// 画廊视图 - 以卡片网格形式展示笔记预览
    case gallery
}

// MARK: - ViewMode 扩展

public extension ViewMode {
    /// 显示名称
    var displayName: String {
        switch self {
        case .list:
            "列表视图"
        case .gallery:
            "画廊视图"
        }
    }

    /// 图标名称
    var icon: String {
        switch self {
        case .list:
            "list.bullet"
        case .gallery:
            "square.grid.2x2"
        }
    }
}

// MARK: - 视图选项状态

/// 视图选项状态
///
/// 管理笔记列表的显示选项，包括排序方式、排序方向、日期分组和视图模式
public struct ViewOptionsState: Codable, Equatable {
    /// 排序方式
    public var sortOrder: NoteSortOrder

    /// 排序方向
    public var sortDirection: SortDirection

    /// 是否启用日期分组
    public var isDateGroupingEnabled: Bool

    /// 视图模式
    public var viewMode: ViewMode

    /// 是否显示笔记数量
    public var showNoteCount: Bool

    /// 初始化方法
    /// - Parameters:
    ///   - sortOrder: 排序方式，默认为编辑时间
    ///   - sortDirection: 排序方向，默认为降序
    ///   - isDateGroupingEnabled: 是否启用日期分组，默认为 true
    ///   - viewMode: 视图模式，默认为列表视图
    ///   - showNoteCount: 是否显示笔记数量，默认为 true
    public init(
        sortOrder: NoteSortOrder = .editDate,
        sortDirection: SortDirection = .descending,
        isDateGroupingEnabled: Bool = true,
        viewMode: ViewMode = .list,
        showNoteCount: Bool = true
    ) {
        self.sortOrder = sortOrder
        self.sortDirection = sortDirection
        self.isDateGroupingEnabled = isDateGroupingEnabled
        self.viewMode = viewMode
        self.showNoteCount = showNoteCount
    }

    /// 默认值
    public static var `default`: ViewOptionsState {
        ViewOptionsState(
            sortOrder: .editDate,
            sortDirection: .descending,
            isDateGroupingEnabled: true,
            viewMode: .list,
            showNoteCount: true
        )
    }
}

// MARK: - NoteSortOrder 扩展

extension NoteSortOrder {
    /// 显示名称
    var displayName: String {
        switch self {
        case .editDate:
            "编辑时间"
        case .createDate:
            "创建时间"
        case .title:
            "标题"
        }
    }

    /// 图标名称
    var icon: String {
        switch self {
        case .editDate:
            "pencil"
        case .createDate:
            "calendar.badge.plus"
        case .title:
            "textformat"
        }
    }
}

// MARK: - SortDirection 扩展

extension SortDirection {
    /// 显示名称
    var displayName: String {
        switch self {
        case .ascending:
            "升序"
        case .descending:
            "降序"
        }
    }

    /// 图标名称
    var icon: String {
        switch self {
        case .ascending:
            "arrow.up"
        case .descending:
            "arrow.down"
        }
    }
}
