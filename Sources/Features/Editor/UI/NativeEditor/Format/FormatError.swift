//
//  FormatError.swift
//  MiNoteMac
//
//  格式应用错误类型 - 定义格式应用和状态同步相关的错误
//

import AppKit
import Foundation

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
        case let .invalidRange(range, textLength):
            "无效的选择范围: \(range)，文本长度: \(textLength)"
        case let .emptySelectionForInlineFormat(format):
            "内联格式 '\(format)' 需要选中文本"
        case let .rangeOutOfBounds(range, textLength):
            "选择范围超出文本长度: \(range)，文本长度: \(textLength)"
        case .textViewUnavailable:
            "textView 不可用"
        case .textStorageUnavailable:
            "textStorage 不可用"
        case .layoutManagerUnavailable:
            "layoutManager 不可用"
        case let .formatApplicationFailed(format, reason):
            "格式 '\(format)' 应用失败: \(reason)"
        case let .fontConversionFailed(originalFont, targetTrait):
            "字体转换失败: 无法将 '\(originalFont)' 转换为 '\(targetTrait)'"
        case let .attributeSettingFailed(attribute, reason):
            "属性 '\(attribute)' 设置失败: \(reason)"
        case let .unsupportedFormat(format):
            "不支持的格式类型: \(format)"
        case let .stateDetectionFailed(reason):
            "格式状态检测失败: \(reason)"
        case let .attributeReadFailed(attribute, position):
            "无法读取位置 \(position) 的属性 '\(attribute)'"
        case let .stateSyncFailed(reason):
            "状态同步失败: \(reason)"
        case let .stateSyncTimeout(duration):
            "状态同步超时: \(String(format: "%.2f", duration * 1000))ms"
        case let .stateInconsistency(expected, actual):
            "状态不一致: 期望 '\(expected)'，实际 '\(actual)'"
        case .editorNotEditable:
            "编辑器处于不可编辑状态"
        case .editorNotFocused:
            "编辑器未获得焦点"
        }
    }

    /// 错误代码
    var errorCode: Int {
        switch self {
        case .invalidRange: 6001
        case .emptySelectionForInlineFormat: 6002
        case .rangeOutOfBounds: 6003
        case .textViewUnavailable: 6101
        case .textStorageUnavailable: 6102
        case .layoutManagerUnavailable: 6103
        case .formatApplicationFailed: 6201
        case .fontConversionFailed: 6202
        case .attributeSettingFailed: 6203
        case .unsupportedFormat: 6204
        case .stateDetectionFailed: 6301
        case .attributeReadFailed: 6302
        case .stateSyncFailed: 6401
        case .stateSyncTimeout: 6402
        case .stateInconsistency: 6403
        case .editorNotEditable: 6501
        case .editorNotFocused: 6502
        }
    }

    /// 是否可恢复
    var isRecoverable: Bool {
        switch self {
        case .invalidRange, .emptySelectionForInlineFormat, .rangeOutOfBounds:
            true
        case .textViewUnavailable, .textStorageUnavailable, .layoutManagerUnavailable:
            false
        case .formatApplicationFailed, .fontConversionFailed, .attributeSettingFailed:
            true
        case .unsupportedFormat:
            false
        case .stateDetectionFailed, .attributeReadFailed:
            true
        case .stateSyncFailed, .stateSyncTimeout, .stateInconsistency:
            true
        case .editorNotEditable, .editorNotFocused:
            true
        }
    }

    /// 建议的恢复操作
    var suggestedRecovery: FormatErrorRecoveryAction {
        switch self {
        case .invalidRange, .rangeOutOfBounds:
            .adjustRange
        case .emptySelectionForInlineFormat:
            .selectText
        case .textViewUnavailable, .textStorageUnavailable, .layoutManagerUnavailable:
            .refreshEditor
        case .formatApplicationFailed, .fontConversionFailed, .attributeSettingFailed:
            .retryWithFallback
        case .unsupportedFormat:
            .ignoreOperation
        case .stateDetectionFailed, .attributeReadFailed:
            .forceStateUpdate
        case .stateSyncFailed, .stateSyncTimeout, .stateInconsistency:
            .forceStateUpdate
        case .editorNotEditable:
            .enableEditing
        case .editorNotFocused:
            .focusEditor
        }
    }

    // MARK: - Equatable

    static func == (lhs: FormatError, rhs: FormatError) -> Bool {
        lhs.errorCode == rhs.errorCode
    }
}

// MARK: - 错误恢复操作

/// 格式错误恢复操作
enum FormatErrorRecoveryAction: String, CaseIterable {
    /// 调整范围
    case adjustRange

    /// 选择文本
    case selectText

    /// 刷新编辑器
    case refreshEditor

    /// 使用回退方案重试
    case retryWithFallback

    /// 忽略操作
    case ignoreOperation

    /// 强制状态更新
    case forceStateUpdate

    /// 启用编辑
    case enableEditing

    /// 聚焦编辑器
    case focusEditor

    /// 无操作
    case none

    var description: String {
        switch self {
        case .adjustRange:
            "调整选择范围"
        case .selectText:
            "请先选择文本"
        case .refreshEditor:
            "刷新编辑器"
        case .retryWithFallback:
            "使用备用方案重试"
        case .ignoreOperation:
            "忽略此操作"
        case .forceStateUpdate:
            "强制更新状态"
        case .enableEditing:
            "启用编辑模式"
        case .focusEditor:
            "聚焦编辑器"
        case .none:
            "无操作"
        }
    }
}

// MARK: - 格式错误上下文

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
        var parts = ["操作: \(operation)"]

        if let format {
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
        FormatErrorContext(
            operation: "unknown",
            format: nil,
            selectedRange: nil,
            textLength: nil,
            cursorPosition: nil,
            additionalInfo: nil
        )
    }
}
