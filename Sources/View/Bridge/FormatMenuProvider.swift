//
//  FormatMenuProvider.swift
//  MiNoteMac
//
//  格式菜单提供者协议 - 定义编辑器的格式操作接口
//  用于统一格式菜单系统，确保工具栏和菜单栏使用相同的格式操作逻辑
//
//  _Requirements: 3.1, 3.2, 3.3_
//

import Foundation
import Combine

// MARK: - 格式菜单提供者协议

/// 格式菜单提供者协议
/// 定义编辑器的格式操作接口
/// _Requirements: 3.1, 3.2, 3.3_
@MainActor
public protocol FormatMenuProvider: AnyObject {
    
    // MARK: - 状态获取
    
    /// 获取当前格式状态
    /// - Returns: 当前格式状态
    /// _Requirements: 7.1_
    func getCurrentFormatState() -> FormatState
    
    /// 检查指定格式是否激活
    /// - Parameter format: 格式类型
    /// - Returns: 是否激活
    /// _Requirements: 7.3_
    func isFormatActive(_ format: TextFormat) -> Bool
    
    // MARK: - 格式应用
    
    /// 应用格式
    /// - Parameter format: 要应用的格式
    /// - Note: 自动处理互斥规则
    /// _Requirements: 7.2_
    func applyFormat(_ format: TextFormat)
    
    /// 切换格式
    /// - Parameter format: 要切换的格式
    /// - Note: 如果格式已激活则移除，否则应用
    func toggleFormat(_ format: TextFormat)
    
    /// 清除段落格式（恢复为正文）
    /// _Requirements: 2.2_
    func clearParagraphFormat()
    
    /// 清除对齐格式（恢复为左对齐）
    /// _Requirements: 3.2_
    func clearAlignmentFormat()
    
    // MARK: - 状态发布
    
    /// 格式状态变化发布者
    /// _Requirements: 8.1, 8.2, 8.3_
    var formatStatePublisher: AnyPublisher<FormatState, Never> { get }
    
    // MARK: - 编辑器信息
    
    /// 编辑器类型
    /// _Requirements: 7.4_
    var editorType: EditorType { get }
    
    /// 编辑器是否可用
    var isEditorAvailable: Bool { get }
}

// MARK: - 协议默认实现

public extension FormatMenuProvider {
    
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
    case success                        // 成功
    case editorNotAvailable             // 编辑器不可用
    case invalidRange                   // 无效范围
    case formatNotSupported(String)     // 格式不支持（使用字符串描述）
    case mutualExclusionApplied         // 应用了互斥规则
    case error(String)                  // 其他错误
    
    /// 是否成功
    public var isSuccess: Bool {
        switch self {
        case .success, .mutualExclusionApplied:
            return true
        default:
            return false
        }
    }
    
    /// 错误描述
    public var errorDescription: String? {
        switch self {
        case .success:
            return nil
        case .editorNotAvailable:
            return "编辑器不可用"
        case .invalidRange:
            return "无效的选择范围"
        case .formatNotSupported(let formatName):
            return "不支持的格式: \(formatName)"
        case .mutualExclusionApplied:
            return nil
        case .error(let message):
            return message
        }
    }
}
