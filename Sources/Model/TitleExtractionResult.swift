//  保存流程数据模型
//  包含保存流程的状态和步骤定义

import Foundation

// MARK: - 保存流程状态枚举

/// 保存流程状态枚举
public enum SavePipelineState: String, CaseIterable {
    case notStarted
    case preparing
    case executing
    case completed
    case failed
    case cancelled

    public var displayName: String {
        switch self {
        case .notStarted:
            "未开始"
        case .preparing:
            "准备中"
        case .executing:
            "执行中"
        case .completed:
            "已完成"
        case .failed:
            "已失败"
        case .cancelled:
            "已取消"
        }
    }

    /// 是否为终止状态
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            true
        case .notStarted, .preparing, .executing:
            false
        }
    }
}

// MARK: - 保存步骤枚举

/// 保存步骤枚举
public enum SaveStep: String, CaseIterable, Sendable {
    case startSave
    case buildNote
    case callAPI
    case updateState
    case completeSave

    public var displayName: String {
        switch self {
        case .startSave:
            "开始保存"
        case .buildNote:
            "构建笔记对象"
        case .callAPI:
            "调用 API"
        case .updateState:
            "更新状态"
        case .completeSave:
            "完成保存"
        }
    }

    public var order: Int {
        switch self {
        case .startSave: 1
        case .buildNote: 2
        case .callAPI: 3
        case .updateState: 4
        case .completeSave: 5
        }
    }
}

// MARK: - 扩展

extension SavePipelineState: CustomStringConvertible {
    public var description: String {
        displayName
    }
}

extension SaveStep: CustomStringConvertible {
    public var description: String {
        displayName
    }
}
