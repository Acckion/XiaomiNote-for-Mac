//  标题提取结果数据模型
//  包含标题提取操作的结果和相关元数据


import Foundation

// MARK: - 标题提取结果

/// 标题提取结果
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
public enum TitleSource: String, CaseIterable {
    /// 来自 XML 内容
    case xml

    /// 来自原生编辑器
    case nativeEditor

    /// 来自用户输入
    case userInput

    /// 来自缓存
    case cache

    /// 显示名称
    public var displayName: String {
        switch self {
        case .xml:
            "XML 内容"
        case .nativeEditor:
            "原生编辑器"
        case .userInput:
            "用户输入"
        case .cache:
            "缓存"
        }
    }
}

// MARK: - 保存流程状态枚举

/// 保存流程状态枚举
public enum SavePipelineState: String, CaseIterable {
    /// 未开始
    case notStarted

    /// 准备中
    case preparing

    /// 执行中
    case executing

    /// 已完成
    case completed

    /// 已失败
    case failed

    /// 已取消
    case cancelled

    /// 显示名称
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
/// 定义保存流程中的具体步骤
public enum SaveStep: String, CaseIterable, Sendable {
    /// 开始保存
    case startSave

    /// 提取标题
    case extractTitle

    /// 验证标题
    case validateTitle

    /// 移除标题标签
    case removeTitleTag

    /// 构建笔记对象
    case buildNote

    /// 调用 API
    case callAPI

    /// 更新状态
    case updateState

    /// 完成保存
    case completeSave

    /// 显示名称
    public var displayName: String {
        switch self {
        case .startSave:
            "开始保存"
        case .extractTitle:
            "提取标题"
        case .validateTitle:
            "验证标题"
        case .removeTitleTag:
            "移除标题标签"
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

    /// 步骤顺序（用于排序和验证）
    public var order: Int {
        switch self {
        case .startSave: 1
        case .extractTitle: 2
        case .validateTitle: 3
        case .removeTitleTag: 4
        case .buildNote: 5
        case .callAPI: 6
        case .updateState: 7
        case .completeSave: 8
        }
    }
}

// MARK: - 扩展：Equatable 和 Hashable

extension TitleExtractionResult: Equatable {
    public static func == (lhs: TitleExtractionResult, rhs: TitleExtractionResult) -> Bool {
        lhs.title == rhs.title &&
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
        displayName
    }
}

extension SaveStep: CustomStringConvertible {
    public var description: String {
        displayName
    }
}
