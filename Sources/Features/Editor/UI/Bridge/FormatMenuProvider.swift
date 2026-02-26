//
//  FormatMenuProvider.swift
//  MiNoteMac
//
//  格式菜单提供者协议 - 定义编辑器的格式操作接口
//  用于统一格式菜单系统，确保工具栏和菜单栏使用相同的格式操作逻辑
//
//

import Combine
import Foundation

// MARK: - 格式菜单提供者协议

/// 格式菜单提供者协议
/// 定义编辑器的格式操作接口
@MainActor
public protocol FormatMenuProvider: AnyObject {

    // MARK: - 状态获取

    /// 获取当前格式状态
    /// - Returns: 当前格式状态
    func getCurrentFormatState() -> FormatState

    /// 检查指定格式是否激活
    /// - Parameter format: 格式类型
    /// - Returns: 是否激活
    func isFormatActive(_ format: TextFormat) -> Bool

    // MARK: - 格式应用

    /// 应用格式
    /// - Parameter format: 要应用的格式
    /// - Note: 自动处理互斥规则
    func applyFormat(_ format: TextFormat)

    /// 切换格式
    /// - Parameter format: 要切换的格式
    /// - Note: 如果格式已激活则移除，否则应用
    func toggleFormat(_ format: TextFormat)

    /// 清除段落格式（恢复为正文）
    func clearParagraphFormat()

    /// 清除对齐格式（恢复为左对齐）
    func clearAlignmentFormat()

    // MARK: - 缩进操作

    /// 增加缩进
    func increaseIndent()

    /// 减少缩进
    func decreaseIndent()

    // MARK: - 字号操作

    /// 增大字体
    func increaseFontSize()

    /// 减小字体
    func decreaseFontSize()

    // MARK: - 状态发布

    /// 格式状态变化发布者
    var formatStatePublisher: AnyPublisher<FormatState, Never> { get }

}

// MARK: - 协议默认实现

public extension FormatMenuProvider {

    /// 缩进操作默认实现（空操作）
    func increaseIndent() {}
    func decreaseIndent() {}

    /// 字号操作默认实现（空操作）
    func increaseFontSize() {}
    func decreaseFontSize() {}

    /// 切换格式的默认实现
    /// 如果格式已激活则移除，否则应用
    func toggleFormat(_ format: TextFormat) {
        if isFormatActive(format) {
            // 格式已激活，需要移除
            // 对于段落格式，恢复为正文
            if let paragraphFormat = ParagraphFormat.from(format) {
                if paragraphFormat != .body {
                    clearParagraphFormat()
                }
            }
            // 对于对齐格式，恢复为左对齐
            else if let alignmentFormat = AlignmentFormat.from(format) {
                if alignmentFormat != .left {
                    clearAlignmentFormat()
                }
            }
            // 对于字符格式和引用块，直接应用（会切换状态）
            else {
                applyFormat(format)
            }
        } else {
            // 格式未激活，应用格式
            applyFormat(format)
        }
    }
}

// MARK: - 格式应用结果

/// 格式应用结果
/// 用于返回格式应用操作的结果
public enum FormatApplicationResult: Equatable, Sendable {
    case success // 成功
    case editorNotAvailable // 编辑器不可用
    case invalidRange // 无效范围
    case formatNotSupported(String) // 格式不支持（使用字符串描述）
    case mutualExclusionApplied // 应用了互斥规则
    case error(String) // 其他错误

    /// 是否成功
    public var isSuccess: Bool {
        switch self {
        case .success, .mutualExclusionApplied:
            true
        default:
            false
        }
    }

    /// 错误描述
    public var errorDescription: String? {
        switch self {
        case .success:
            nil
        case .editorNotAvailable:
            "编辑器不可用"
        case .invalidRange:
            "无效的选择范围"
        case let .formatNotSupported(formatName):
            "不支持的格式: \(formatName)"
        case .mutualExclusionApplied:
            nil
        case let .error(message):
            message
        }
    }
}
