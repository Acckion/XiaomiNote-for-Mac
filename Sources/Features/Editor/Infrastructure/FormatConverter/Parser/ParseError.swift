//
//  ParseError.swift
//  MiNoteMac
//
//  XML 解析错误类型定义
//  提供详细的错误信息和错误恢复策略
//

import Foundation

// MARK: - ParseError

/// 解析错误类型
public enum ParseError: Error, LocalizedError, Sendable {
    /// XML 格式无效
    case invalidXML(String)

    /// 意外的输入结束
    case unexpectedEndOfInput

    /// 标签不匹配
    case unmatchedTag(expected: String, found: String)

    /// 不支持的元素
    case unsupportedElement(String)

    /// 意外的 Token
    case unexpectedToken(XMLToken)

    /// 缺少必需的属性
    case missingAttribute(tag: String, attribute: String)

    /// 格式错误（如未闭合标签）
    case malformedXML(String)

    /// 转换失败
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidXML(message):
            "无效的 XML 格式: \(message)"
        case .unexpectedEndOfInput:
            "意外的输入结束"
        case let .unmatchedTag(expected, found):
            "标签不匹配: 期望 </\(expected)>，找到 </\(found)>"
        case let .unsupportedElement(element):
            "不支持的元素: \(element)"
        case let .unexpectedToken(token):
            "意外的 Token: \(token)"
        case let .missingAttribute(tag, attribute):
            "标签 <\(tag)> 缺少必需的属性: \(attribute)"
        case let .malformedXML(message):
            "格式错误的 XML: \(message)"
        case let .conversionFailed(message):
            "转换失败: \(message)"
        }
    }
}

// MARK: - ParseWarning

/// 解析警告（非致命错误）
public struct ParseWarning: Sendable {
    /// 警告消息
    public let message: String

    /// 警告位置（可选）
    public let location: String?

    /// 警告类型
    public let type: WarningType

    public enum WarningType: Sendable {
        /// 跳过不支持的元素
        case unsupportedElement

        /// 缺少可选属性
        case missingOptionalAttribute

        /// 使用默认值
        case usingDefaultValue

        /// 其他警告
        case other
    }

    public init(message: String, location: String? = nil, type: WarningType = .other) {
        self.message = message
        self.location = location
        self.type = type
    }
}

// MARK: - ErrorRecoveryStrategy

/// 错误恢复策略
public enum ErrorRecoveryStrategy: Sendable {
    /// 跳过当前元素，继续处理
    case skipElement

    /// 使用纯文本回退
    case fallbackToPlainText

    /// 使用默认值
    case useDefaultValue

    /// 终止解析
    case abort
}

// MARK: - ParseResult

/// 解析结果（包含结果和警告）
public struct ParseResult<T: Sendable>: Sendable {
    /// 解析结果
    public let value: T

    /// 解析过程中的警告
    public let warnings: [ParseWarning]

    /// 是否有警告
    public var hasWarnings: Bool {
        !warnings.isEmpty
    }

    public init(value: T, warnings: [ParseWarning] = []) {
        self.value = value
        self.warnings = warnings
    }
}

// MARK: - ErrorLogger

/// 错误日志记录器
public protocol ErrorLogger: Sendable {
    /// 记录错误
    func logError(_ error: Error, context: [String: String])

    /// 记录警告
    func logWarning(_ warning: ParseWarning)

    /// 记录调试信息
    func logDebug(_ message: String)
}

/// 默认的控制台日志记录器
public struct ConsoleErrorLogger: ErrorLogger, Sendable {
    public init() {}

    public func logError(_ error: Error, context: [String: String]) {
        var message = "解析错误: \(error.localizedDescription)"
        if !context.isEmpty {
            message += " 上下文: \(context)"
        }
        LogService.shared.error(.editor, message)
    }

    public func logWarning(_ warning: ParseWarning) {
        var message = "解析警告: \(warning.message)"
        if let location = warning.location {
            message += " (位置: \(location))"
        }
        LogService.shared.warning(.editor, message)
    }

    public func logDebug(_ message: String) {
        LogService.shared.debug(.editor, message)
    }
}

// MARK: - ErrorRecoveryHandler

/// 错误恢复处理器
public protocol ErrorRecoveryHandler: Sendable {
    /// 处理解析错误，返回恢复策略
    func handleError(_ error: ParseError, context: ErrorContext) -> ErrorRecoveryStrategy

    /// 从错误中恢复，返回回退值
    func recoverFromError<T: Sendable>(_ error: ParseError, context: ErrorContext) -> T?
}

/// 错误上下文
public struct ErrorContext: Sendable {
    /// 当前解析的元素名称
    public let elementName: String?

    /// 当前解析的内容
    public let content: String?

    /// 当前位置
    public let position: Int?

    public init(elementName: String? = nil, content: String? = nil, position: Int? = nil) {
        self.elementName = elementName
        self.content = content
        self.position = position
    }
}

/// 默认的错误恢复处理器
public struct DefaultErrorRecoveryHandler: ErrorRecoveryHandler, Sendable {
    private let logger: ErrorLogger

    public init(logger: ErrorLogger = ConsoleErrorLogger()) {
        self.logger = logger
    }

    public func handleError(_ error: ParseError, context: ErrorContext) -> ErrorRecoveryStrategy {
        // 记录错误
        var logContext: [String: String] = [:]
        if let elementName = context.elementName {
            logContext["element"] = elementName
        }
        if let position = context.position {
            logContext["position"] = "\(position)"
        }
        logger.logError(error, context: logContext)

        // 根据错误类型决定恢复策略
        switch error {
        case .unsupportedElement:
            // 跳过不支持的元素
            return .skipElement

        case .missingAttribute:
            // 使用默认值
            return .useDefaultValue

        case .malformedXML, .unmatchedTag:
            // 格式错误，尝试纯文本回退
            return .fallbackToPlainText

        case .invalidXML, .unexpectedEndOfInput, .unexpectedToken, .conversionFailed:
            // 严重错误，终止解析
            return .abort
        }
    }

    public func recoverFromError<T: Sendable>(_ error: ParseError, context: ErrorContext) -> T? {
        // 根据错误类型提供回退值
        switch error {
        case .unsupportedElement:
            // 返回 nil，跳过该元素
            return nil

        case .missingAttribute:
            // 对于缺少属性的情况，返回默认值
            // 这里需要根据具体类型处理
            return nil

        case .malformedXML, .unmatchedTag:
            // 对于格式错误，如果是字符串类型，返回纯文本
            if T.self == String.self {
                return context.content as? T
            }
            return nil

        default:
            return nil
        }
    }
}
