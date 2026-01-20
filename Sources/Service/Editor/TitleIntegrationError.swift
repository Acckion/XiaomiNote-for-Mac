//
//  TitleIntegrationError.swift
//  MiNoteMac
//
//  标题集成错误类型定义
//  定义标题提取和保存过程中可能出现的所有错误类型
//
//  Created by Title Content Integration Fix
//

import Foundation

/// 标题集成错误类型
/// 
/// 定义标题提取、验证和保存过程中可能出现的所有错误
/// _需求: 6.1_ - 提供完善的错误处理和日志记录
public enum TitleIntegrationError: Error, LocalizedError {
    
    // MARK: - 标题提取错误
    
    /// XML 格式错误
    case xmlFormatError(String)
    
    /// 标题标签缺失
    case titleTagMissing
    
    /// 标题标签格式错误
    case titleTagMalformed(String)
    
    /// 编辑器内容为空
    case editorContentEmpty
    
    /// 编辑器状态无效
    case editorStateInvalid(String)
    
    // MARK: - 标题验证错误
    
    /// 标题长度超限
    case titleTooLong(Int, maxLength: Int)
    
    /// 标题包含非法字符
    case titleContainsInvalidCharacters([Character])
    
    /// 标题包含换行符
    case titleContainsNewlines
    
    /// 标题包含控制字符
    case titleContainsControlCharacters
    
    // MARK: - 保存流程错误
    
    /// 保存流程状态错误
    case saveStateError(String)
    
    /// 保存步骤执行失败
    case saveStepFailed(SaveStep, reason: String)
    
    /// 保存流程超时
    case saveTimeout(TimeInterval)
    
    /// 保存流程被取消
    case saveCancelled
    
    // MARK: - API 调用错误
    
    /// API 调用失败
    case apiCallFailed(Error)
    
    /// API 响应格式错误
    case apiResponseInvalid(String)
    
    /// 网络连接错误
    case networkError(Error)
    
    // MARK: - 状态同步错误
    
    /// 状态同步失败
    case stateSyncFailed(String)
    
    /// UI 更新失败
    case uiUpdateFailed(String)
    
    /// 缓存更新失败
    case cacheUpdateFailed(String)
    
    // MARK: - 系统错误
    
    /// 内存不足
    case memoryInsufficient
    
    /// 文件系统错误
    case fileSystemError(Error)
    
    /// 未知错误
    case unknown(Error)
    
    // MARK: - LocalizedError 实现
    
    /// 错误描述
    public var errorDescription: String? {
        switch self {
        // 标题提取错误
        case .xmlFormatError(let details):
            return "XML 格式错误：\(details)"
        case .titleTagMissing:
            return "缺少标题标签"
        case .titleTagMalformed(let details):
            return "标题标签格式错误：\(details)"
        case .editorContentEmpty:
            return "编辑器内容为空"
        case .editorStateInvalid(let details):
            return "编辑器状态无效：\(details)"
            
        // 标题验证错误
        case .titleTooLong(let length, let maxLength):
            return "标题长度超限：当前 \(length) 字符，最大允许 \(maxLength) 字符"
        case .titleContainsInvalidCharacters(let characters):
            let charList = characters.map { "'\($0)'" }.joined(separator: ", ")
            return "标题包含非法字符：\(charList)"
        case .titleContainsNewlines:
            return "标题不能包含换行符"
        case .titleContainsControlCharacters:
            return "标题不能包含控制字符"
            
        // 保存流程错误
        case .saveStateError(let details):
            return "保存状态错误：\(details)"
        case .saveStepFailed(let step, let reason):
            return "保存步骤失败：\(step.displayName) - \(reason)"
        case .saveTimeout(let timeout):
            return "保存操作超时：\(timeout) 秒"
        case .saveCancelled:
            return "保存操作已取消"
            
        // API 调用错误
        case .apiCallFailed(let error):
            return "API 调用失败：\(error.localizedDescription)"
        case .apiResponseInvalid(let details):
            return "API 响应格式错误：\(details)"
        case .networkError(let error):
            return "网络连接错误：\(error.localizedDescription)"
            
        // 状态同步错误
        case .stateSyncFailed(let details):
            return "状态同步失败：\(details)"
        case .uiUpdateFailed(let details):
            return "UI 更新失败：\(details)"
        case .cacheUpdateFailed(let details):
            return "缓存更新失败：\(details)"
            
        // 系统错误
        case .memoryInsufficient:
            return "内存不足"
        case .fileSystemError(let error):
            return "文件系统错误：\(error.localizedDescription)"
        case .unknown(let error):
            return "未知错误：\(error.localizedDescription)"
        }
    }
    
    /// 失败原因
    public var failureReason: String? {
        switch self {
        case .xmlFormatError:
            return "XML 内容格式不正确，无法解析标题标签"
        case .titleTagMissing:
            return "XML 内容中没有找到 <title> 标签"
        case .titleTagMalformed:
            return "标题标签的开始或结束标记不完整"
        case .editorContentEmpty:
            return "编辑器中没有任何内容可以提取"
        case .editorStateInvalid:
            return "编辑器的内部状态不一致或已损坏"
        case .titleTooLong:
            return "标题长度超过了系统允许的最大限制"
        case .titleContainsInvalidCharacters:
            return "标题中包含了不被支持的特殊字符"
        case .titleContainsNewlines:
            return "标题是单行文本，不能包含换行符"
        case .titleContainsControlCharacters:
            return "标题中包含了不可见的控制字符"
        case .saveStateError:
            return "保存流程的状态管理出现异常"
        case .saveStepFailed:
            return "保存流程中的某个步骤执行失败"
        case .saveTimeout:
            return "保存操作耗时过长，已超过预设的超时时间"
        case .saveCancelled:
            return "用户或系统取消了保存操作"
        case .apiCallFailed:
            return "调用小米笔记 API 时发生错误"
        case .apiResponseInvalid:
            return "API 返回的数据格式不符合预期"
        case .networkError:
            return "网络连接出现问题，无法完成 API 调用"
        case .stateSyncFailed:
            return "本地状态与服务器状态同步失败"
        case .uiUpdateFailed:
            return "界面更新过程中出现错误"
        case .cacheUpdateFailed:
            return "本地缓存更新失败"
        case .memoryInsufficient:
            return "系统可用内存不足，无法完成操作"
        case .fileSystemError:
            return "文件系统操作失败"
        case .unknown:
            return "发生了未预期的错误"
        }
    }
    
    /// 恢复建议
    public var recoverySuggestion: String? {
        switch self {
        case .xmlFormatError, .titleTagMissing, .titleTagMalformed:
            return "请检查笔记内容的格式，或尝试重新编辑标题"
        case .editorContentEmpty:
            return "请在编辑器中输入一些内容后再尝试保存"
        case .editorStateInvalid:
            return "请尝试刷新编辑器或重新打开笔记"
        case .titleTooLong:
            return "请缩短标题长度，建议控制在 200 字符以内"
        case .titleContainsInvalidCharacters, .titleContainsNewlines, .titleContainsControlCharacters:
            return "请修改标题，移除不支持的字符"
        case .saveStateError, .saveStepFailed:
            return "请稍后重试，或检查网络连接状态"
        case .saveTimeout:
            return "请检查网络连接，稍后重试保存操作"
        case .saveCancelled:
            return "如需保存，请重新执行保存操作"
        case .apiCallFailed, .networkError:
            return "请检查网络连接，确认小米账号登录状态后重试"
        case .apiResponseInvalid:
            return "请稍后重试，如问题持续存在请联系技术支持"
        case .stateSyncFailed, .uiUpdateFailed, .cacheUpdateFailed:
            return "请尝试刷新应用或重新启动"
        case .memoryInsufficient:
            return "请关闭其他应用释放内存，或重启设备"
        case .fileSystemError:
            return "请检查磁盘空间和文件权限"
        case .unknown:
            return "请尝试重新执行操作，如问题持续存在请重启应用"
        }
    }
    
    // MARK: - 错误分类
    
    /// 错误严重程度
    public var severity: ErrorSeverity {
        switch self {
        case .titleContainsNewlines, .titleContainsControlCharacters, .titleContainsInvalidCharacters:
            return .warning
        case .titleTooLong, .editorContentEmpty, .saveCancelled:
            return .minor
        case .xmlFormatError, .titleTagMissing, .titleTagMalformed, .editorStateInvalid,
             .saveStateError, .saveStepFailed, .stateSyncFailed, .uiUpdateFailed, .cacheUpdateFailed:
            return .moderate
        case .saveTimeout, .apiCallFailed, .apiResponseInvalid, .networkError:
            return .major
        case .memoryInsufficient, .fileSystemError, .unknown:
            return .critical
        }
    }
    
    /// 是否可重试
    public var isRetryable: Bool {
        switch self {
        case .xmlFormatError, .titleTagMissing, .titleTagMalformed, .editorContentEmpty,
             .titleTooLong, .titleContainsInvalidCharacters, .titleContainsNewlines, .titleContainsControlCharacters:
            return false
        case .editorStateInvalid, .saveStateError, .saveStepFailed, .saveTimeout,
             .apiCallFailed, .apiResponseInvalid, .networkError, .stateSyncFailed,
             .uiUpdateFailed, .cacheUpdateFailed, .memoryInsufficient, .fileSystemError, .unknown:
            return true
        case .saveCancelled:
            return false
        }
    }
    
    /// 错误代码（用于日志和调试）
    public var errorCode: String {
        switch self {
        case .xmlFormatError: return "TIE001"
        case .titleTagMissing: return "TIE002"
        case .titleTagMalformed: return "TIE003"
        case .editorContentEmpty: return "TIE004"
        case .editorStateInvalid: return "TIE005"
        case .titleTooLong: return "TIE101"
        case .titleContainsInvalidCharacters: return "TIE102"
        case .titleContainsNewlines: return "TIE103"
        case .titleContainsControlCharacters: return "TIE104"
        case .saveStateError: return "TIE201"
        case .saveStepFailed: return "TIE202"
        case .saveTimeout: return "TIE203"
        case .saveCancelled: return "TIE204"
        case .apiCallFailed: return "TIE301"
        case .apiResponseInvalid: return "TIE302"
        case .networkError: return "TIE303"
        case .stateSyncFailed: return "TIE401"
        case .uiUpdateFailed: return "TIE402"
        case .cacheUpdateFailed: return "TIE403"
        case .memoryInsufficient: return "TIE501"
        case .fileSystemError: return "TIE502"
        case .unknown: return "TIE999"
        }
    }
}

// MARK: - 错误严重程度枚举

/// 错误严重程度
public enum ErrorSeverity: Int, CaseIterable {
    /// 警告（不影响功能）
    case warning = 1
    
    /// 轻微错误（影响体验）
    case minor = 2
    
    /// 中等错误（影响功能）
    case moderate = 3
    
    /// 严重错误（功能不可用）
    case major = 4
    
    /// 致命错误（系统不稳定）
    case critical = 5
    
    /// 显示名称
    public var displayName: String {
        switch self {
        case .warning: return "警告"
        case .minor: return "轻微"
        case .moderate: return "中等"
        case .major: return "严重"
        case .critical: return "致命"
        }
    }
    
    /// 颜色标识（用于 UI 显示）
    public var colorName: String {
        switch self {
        case .warning: return "yellow"
        case .minor: return "orange"
        case .moderate: return "red"
        case .major: return "purple"
        case .critical: return "black"
        }
    }
}

// MARK: - 扩展：CustomStringConvertible

extension TitleIntegrationError: CustomStringConvertible {
    public var description: String {
        return "[\(errorCode)] \(errorDescription ?? "未知错误")"
    }
}

extension ErrorSeverity: CustomStringConvertible {
    public var description: String {
        return displayName
    }
}

// MARK: - 便利方法

extension TitleIntegrationError {
    /// 创建 XML 格式错误
    public static func xmlFormat(_ details: String) -> TitleIntegrationError {
        return .xmlFormatError(details)
    }
    
    /// 创建标题验证错误
    public static func titleValidation(_ reason: String) -> TitleIntegrationError {
        if reason.contains("长度") {
            return .titleTooLong(0, maxLength: 200) // 默认值，实际使用时应传入具体长度
        } else if reason.contains("换行") {
            return .titleContainsNewlines
        } else if reason.contains("控制字符") {
            return .titleContainsControlCharacters
        } else {
            return .titleContainsInvalidCharacters([])
        }
    }
    
    /// 创建保存步骤错误
    public static func saveStep(_ step: SaveStep, reason: String) -> TitleIntegrationError {
        return .saveStepFailed(step, reason: reason)
    }
    
    /// 包装其他错误
    public static func wrap(_ error: Error) -> TitleIntegrationError {
        if let titleError = error as? TitleIntegrationError {
            return titleError
        } else {
            return .unknown(error)
        }
    }
}