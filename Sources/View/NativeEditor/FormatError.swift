//
//  FormatError.swift
//  MiNoteMac
//
//  格式应用错误类型 - 定义格式应用和状态同步相关的错误
//  需求: 4.1, 4.2
//

import Foundation
import AppKit

// MARK: - 格式错误类型

/// 格式应用错误类型
/// 
/// 定义了格式应用过程中可能发生的各种错误，包括：
/// - 范围错误：选择范围无效或超出文本长度
/// - 文本存储错误：textStorage 不可用
/// - 格式应用错误：格式应用失败
/// - 状态检测错误：格式状态检测失败
/// - 状态同步错误：格式状态同步失败
/// 
/// 需求: 4.1, 4.2
enum FormatError: Error, LocalizedError, Equatable {
    
    // MARK: - 范围错误
    
    /// 无效的选择范围
    case invalidRange(range: NSRange, textLength: Int)
    
    /// 空选择范围（内联格式需要选中文本）
    case emptySelectionForInlineFormat(format: String)
    
    /// 范围超出文本长度
    case rangeOutOfBounds(range: NSRange, textLength: Int)
    
    // MARK: - 文本存储错误
    
    /// textView 不可用
    case textViewUnavailable
    
    /// textStorage 不可用
    case textStorageUnavailable
    
    /// layoutManager 不可用
    case layoutManagerUnavailable
    
    // MARK: - 格式应用错误
    
    /// 格式应用失败
    case formatApplicationFailed(format: String, reason: String)
    
    /// 字体转换失败
    case fontConversionFailed(originalFont: String, targetTrait: String)
    
    /// 属性设置失败
    case attributeSettingFailed(attribute: String, reason: String)
    
    /// 不支持的格式类型
    case unsupportedFormat(format: String)
    
    // MARK: - 状态检测错误
    
    /// 格式状态检测失败
    case stateDetectionFailed(reason: String)
    
    /// 属性读取失败
    case attributeReadFailed(attribute: String, position: Int)
    
    // MARK: - 状态同步错误
    
    /// 状态同步失败
    case stateSyncFailed(reason: String)
    
    /// 状态同步超时
    case stateSyncTimeout(duration: TimeInterval)
    
    /// 状态不一致
    case stateInconsistency(expected: String, actual: String)
    
    // MARK: - 编辑器状态错误
    
    /// 编辑器不可编辑
    case editorNotEditable
    
    /// 编辑器未获得焦点
    case editorNotFocused
    
    // MARK: - LocalizedError
    
    var errorDescription: String? {
        switch self {
        case .invalidRange(let range, let textLength):
            return "无效的选择范围: \(range)，文本长度: \(textLength)"
        case .emptySelectionForInlineFormat(let format):
            return "内联格式 '\(format)' 需要选中文本"
        case .rangeOutOfBounds(let range, let textLength):
            return "选择范围超出文本长度: \(range)，文本长度: \(textLength)"
        case .textViewUnavailable:
            return "textView 不可用"
        case .textStorageUnavailable:
            return "textStorage 不可用"
        case .layoutManagerUnavailable:
            return "layoutManager 不可用"
        case .formatApplicationFailed(let format, let reason):
            return "格式 '\(format)' 应用失败: \(reason)"
        case .fontConversionFailed(let originalFont, let targetTrait):
            return "字体转换失败: 无法将 '\(originalFont)' 转换为 '\(targetTrait)'"
        case .attributeSettingFailed(let attribute, let reason):
            return "属性 '\(attribute)' 设置失败: \(reason)"
        case .unsupportedFormat(let format):
            return "不支持的格式类型: \(format)"
        case .stateDetectionFailed(let reason):
            return "格式状态检测失败: \(reason)"
        case .attributeReadFailed(let attribute, let position):
            return "无法读取位置 \(position) 的属性 '\(attribute)'"
        case .stateSyncFailed(let reason):
            return "状态同步失败: \(reason)"
        case .stateSyncTimeout(let duration):
            return "状态同步超时: \(String(format: "%.2f", duration * 1000))ms"
        case .stateInconsistency(let expected, let actual):
            return "状态不一致: 期望 '\(expected)'，实际 '\(actual)'"
        case .editorNotEditable:
            return "编辑器处于不可编辑状态"
        case .editorNotFocused:
            return "编辑器未获得焦点"
        }
    }
    
    /// 错误代码
    var errorCode: Int {
        switch self {
        case .invalidRange: return 6001
        case .emptySelectionForInlineFormat: return 6002
        case .rangeOutOfBounds: return 6003
        case .textViewUnavailable: return 6101
        case .textStorageUnavailable: return 6102
        case .layoutManagerUnavailable: return 6103
        case .formatApplicationFailed: return 6201
        case .fontConversionFailed: return 6202
        case .attributeSettingFailed: return 6203
        case .unsupportedFormat: return 6204
        case .stateDetectionFailed: return 6301
        case .attributeReadFailed: return 6302
        case .stateSyncFailed: return 6401
        case .stateSyncTimeout: return 6402
        case .stateInconsistency: return 6403
        case .editorNotEditable: return 6501
        case .editorNotFocused: return 6502
        }
    }
    
    /// 是否可恢复
    var isRecoverable: Bool {
        switch self {
        case .invalidRange, .emptySelectionForInlineFormat, .rangeOutOfBounds:
            return true
        case .textViewUnavailable, .textStorageUnavailable, .layoutManagerUnavailable:
            return false
        case .formatApplicationFailed, .fontConversionFailed, .attributeSettingFailed:
            return true
        case .unsupportedFormat:
            return false
        case .stateDetectionFailed, .attributeReadFailed:
            return true
        case .stateSyncFailed, .stateSyncTimeout, .stateInconsistency:
            return true
        case .editorNotEditable, .editorNotFocused:
            return true
        }
    }
    
    /// 建议的恢复操作
    var suggestedRecovery: FormatErrorRecoveryAction {
        switch self {
        case .invalidRange, .rangeOutOfBounds:
            return .adjustRange
        case .emptySelectionForInlineFormat:
            return .selectText
        case .textViewUnavailable, .textStorageUnavailable, .layoutManagerUnavailable:
            return .refreshEditor
        case .formatApplicationFailed, .fontConversionFailed, .attributeSettingFailed:
            return .retryWithFallback
        case .unsupportedFormat:
            return .ignoreOperation
        case .stateDetectionFailed, .attributeReadFailed:
            return .forceStateUpdate
        case .stateSyncFailed, .stateSyncTimeout, .stateInconsistency:
            return .forceStateUpdate
        case .editorNotEditable:
            return .enableEditing
        case .editorNotFocused:
            return .focusEditor
        }
    }
    
    // MARK: - Equatable
    
    static func == (lhs: FormatError, rhs: FormatError) -> Bool {
        return lhs.errorCode == rhs.errorCode
    }
}

// MARK: - 错误恢复操作

/// 格式错误恢复操作
enum FormatErrorRecoveryAction: String, CaseIterable {
    /// 调整范围
    case adjustRange = "adjustRange"
    
    /// 选择文本
    case selectText = "selectText"
    
    /// 刷新编辑器
    case refreshEditor = "refreshEditor"
    
    /// 使用回退方案重试
    case retryWithFallback = "retryWithFallback"
    
    /// 忽略操作
    case ignoreOperation = "ignoreOperation"
    
    /// 强制状态更新
    case forceStateUpdate = "forceStateUpdate"
    
    /// 启用编辑
    case enableEditing = "enableEditing"
    
    /// 聚焦编辑器
    case focusEditor = "focusEditor"
    
    /// 无操作
    case none = "none"
    
    var description: String {
        switch self {
        case .adjustRange:
            return "调整选择范围"
        case .selectText:
            return "请先选择文本"
        case .refreshEditor:
            return "刷新编辑器"
        case .retryWithFallback:
            return "使用备用方案重试"
        case .ignoreOperation:
            return "忽略此操作"
        case .forceStateUpdate:
            return "强制更新状态"
        case .enableEditing:
            return "启用编辑模式"
        case .focusEditor:
            return "聚焦编辑器"
        case .none:
            return "无操作"
        }
    }
}

// MARK: - 格式错误记录

/// 格式错误记录
struct FormatErrorRecord {
    /// 错误
    let error: FormatError
    
    /// 上下文信息
    let context: FormatErrorContext
    
    /// 时间戳
    let timestamp: Date
    
    /// 是否已处理
    var handled: Bool
    
    /// 恢复操作
    var recoveryAction: FormatErrorRecoveryAction?
    
    /// 描述
    var description: String {
        return "[\(ISO8601DateFormatter().string(from: timestamp))] \(error.localizedDescription ?? "未知错误") - \(context.description)"
    }
}

/// 格式错误上下文
struct FormatErrorContext {
    /// 操作类型
    let operation: String
    
    /// 格式类型
    let format: String?
    
    /// 选择范围
    let selectedRange: NSRange?
    
    /// 文本长度
    let textLength: Int?
    
    /// 光标位置
    let cursorPosition: Int?
    
    /// 额外信息
    let additionalInfo: [String: Any]?
    
    /// 描述
    var description: String {
        var parts: [String] = ["操作: \(operation)"]
        
        if let format = format {
            parts.append("格式: \(format)")
        }
        if let range = selectedRange {
            parts.append("范围: \(range)")
        }
        if let length = textLength {
            parts.append("文本长度: \(length)")
        }
        if let position = cursorPosition {
            parts.append("光标位置: \(position)")
        }
        
        return parts.joined(separator: ", ")
    }
    
    /// 创建空上下文
    static var empty: FormatErrorContext {
        return FormatErrorContext(
            operation: "unknown",
            format: nil,
            selectedRange: nil,
            textLength: nil,
            cursorPosition: nil,
            additionalInfo: nil
        )
    }
}
