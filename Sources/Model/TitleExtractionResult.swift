//
//  TitleExtractionResult.swift
//  MiNoteMac
//
//  标题提取结果数据模型
//  包含标题提取操作的结果和相关元数据
//
//  Created by Title Content Integration Fix
//

import Foundation

// MARK: - 标题提取结果

/// 标题提取结果
///
/// 包含提取的标题文本和相关元数据
/// _需求: 6.1, 6.2_ - 提供详细的操作结果和元数据
public struct TitleExtractionResult {
    /// 提取的标题文本
    public let title: String
    
    /// 标题来源
    public let source: TitleSource
    
    /// 是否有效
    public let isValid: Bool
    
    /// 提取时间
    public let extractionTime: Date
    
    /// 原始内容长度
    public let originalLength: Int
    
    /// 处理后长度
    public let processedLength: Int
    
    /// 错误信息（如果有）
    public let error: String?
    
    /// 初始化方法
    public init(
        title: String,
        source: TitleSource,
        isValid: Bool,
        extractionTime: Date,
        originalLength: Int,
        processedLength: Int,
        error: String? = nil
    ) {
        self.title = title
        self.source = source
        self.isValid = isValid
        self.extractionTime = extractionTime
        self.originalLength = originalLength
        self.processedLength = processedLength
        self.error = error
    }
}

// MARK: - 标题来源枚举

/// 标题来源枚举
/// _需求: 6.1_ - 记录标题的来源以便调试和追踪
public enum TitleSource: String, CaseIterable {
    /// 来自 XML 内容
    case xml = "xml"
    
    /// 来自原生编辑器
    case nativeEditor = "nativeEditor"
    
    /// 来自用户输入
    case userInput = "userInput"
    
    /// 来自缓存
    case cache = "cache"
    
    /// 显示名称
    public var displayName: String {
        switch self {
        case .xml:
            return "XML 内容"
        case .nativeEditor:
            return "原生编辑器"
        case .userInput:
            return "用户输入"
        case .cache:
            return "缓存"
        }
    }
}

// MARK: - 保存流程状态枚举

/// 保存流程状态枚举
/// 用于跟踪保存操作的整体状态
/// _需求: 6.2_ - 记录保存流程的执行状态
public enum SavePipelineState: String, CaseIterable {
    /// 未开始
    case notStarted = "notStarted"
    
    /// 准备中
    case preparing = "preparing"
    
    /// 执行中
    case executing = "executing"
    
    /// 已完成
    case completed = "completed"
    
    /// 已失败
    case failed = "failed"
    
    /// 已取消
    case cancelled = "cancelled"
    
    /// 显示名称
    public var displayName: String {
        switch self {
        case .notStarted:
            return "未开始"
        case .preparing:
            return "准备中"
        case .executing:
            return "执行中"
        case .completed:
            return "已完成"
        case .failed:
            return "已失败"
        case .cancelled:
            return "已取消"
        }
    }
    
    /// 是否为终止状态
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .notStarted, .preparing, .executing:
            return false
        }
    }
}

// MARK: - 保存步骤枚举

/// 保存步骤枚举
/// 定义保存流程中的具体步骤
/// _需求: 6.2_ - 记录保存流程的详细步骤
public enum SaveStep: String, CaseIterable, Sendable {
    /// 开始保存
    case startSave = "startSave"
    
    /// 提取标题
    case extractTitle = "extractTitle"
    
    /// 验证标题
    case validateTitle = "validateTitle"
    
    /// 移除标题标签
    case removeTitleTag = "removeTitleTag"
    
    /// 构建笔记对象
    case buildNote = "buildNote"
    
    /// 调用 API
    case callAPI = "callAPI"
    
    /// 更新状态
    case updateState = "updateState"
    
    /// 完成保存
    case completeSave = "completeSave"
    
    /// 显示名称
    public var displayName: String {
        switch self {
        case .startSave:
            return "开始保存"
        case .extractTitle:
            return "提取标题"
        case .validateTitle:
            return "验证标题"
        case .removeTitleTag:
            return "移除标题标签"
        case .buildNote:
            return "构建笔记对象"
        case .callAPI:
            return "调用 API"
        case .updateState:
            return "更新状态"
        case .completeSave:
            return "完成保存"
        }
    }
    
    /// 步骤顺序（用于排序和验证）
    public var order: Int {
        switch self {
        case .startSave: return 1
        case .extractTitle: return 2
        case .validateTitle: return 3
        case .removeTitleTag: return 4
        case .buildNote: return 5
        case .callAPI: return 6
        case .updateState: return 7
        case .completeSave: return 8
        }
    }
}

// MARK: - 扩展：Equatable 和 Hashable

extension TitleExtractionResult: Equatable {
    public static func == (lhs: TitleExtractionResult, rhs: TitleExtractionResult) -> Bool {
        return lhs.title == rhs.title &&
               lhs.source == rhs.source &&
               lhs.isValid == rhs.isValid &&
               lhs.originalLength == rhs.originalLength &&
               lhs.processedLength == rhs.processedLength &&
               lhs.error == rhs.error
    }
}

extension TitleExtractionResult: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(source)
        hasher.combine(isValid)
        hasher.combine(originalLength)
        hasher.combine(processedLength)
        hasher.combine(error)
    }
}

// MARK: - 扩展：CustomStringConvertible

extension TitleExtractionResult: CustomStringConvertible {
    public var description: String {
        let status = isValid ? "有效" : "无效"
        let errorInfo = error != nil ? " (错误: \(error!))" : ""
        return "TitleExtractionResult(标题: '\(title)', 来源: \(source.displayName), 状态: \(status)\(errorInfo))"
    }
}

extension SavePipelineState: CustomStringConvertible {
    public var description: String {
        return displayName
    }
}

extension SaveStep: CustomStringConvertible {
    public var description: String {
        return displayName
    }
}