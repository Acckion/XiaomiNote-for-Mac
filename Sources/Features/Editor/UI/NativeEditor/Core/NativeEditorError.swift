//
//  NativeEditorError.swift
//  MiNoteMac
//
//  原生编辑器错误类型

import Foundation

/// 原生编辑器错误类型
enum NativeEditorError: Error, LocalizedError {
    // 初始化错误
    case initializationFailed(reason: String)
    case systemVersionNotSupported(required: String, current: String)
    case frameworkNotAvailable(framework: String)

    // 渲染错误
    case renderingFailed(element: String, reason: String)
    case attachmentCreationFailed(type: String)
    case layoutManagerError(reason: String)

    // 格式转换错误
    case xmlParsingFailed(xml: String, reason: String)
    case attributedStringConversionFailed(reason: String)
    case unsupportedXMLElement(element: String)
    case invalidXMLStructure(details: String)

    // 内容错误
    case contentLoadFailed(reason: String)
    case contentSaveFailed(reason: String)
    case imageLoadFailed(fileId: String?, reason: String)

    // 状态错误
    case invalidEditorState(state: String)
    case contextSyncFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case let .initializationFailed(reason):
            "编辑器初始化失败: \(reason)"
        case let .systemVersionNotSupported(required, current):
            "系统版本不支持: 需要 \(required)，当前 \(current)"
        case let .frameworkNotAvailable(framework):
            "框架不可用: \(framework)"
        case let .renderingFailed(element, reason):
            "渲染失败 [\(element)]: \(reason)"
        case let .attachmentCreationFailed(type):
            "附件创建失败: \(type)"
        case let .layoutManagerError(reason):
            "布局管理器错误: \(reason)"
        case let .xmlParsingFailed(_, reason):
            "XML 解析失败: \(reason)"
        case let .attributedStringConversionFailed(reason):
            "AttributedString 转换失败: \(reason)"
        case let .unsupportedXMLElement(element):
            "不支持的 XML 元素: \(element)"
        case let .invalidXMLStructure(details):
            "无效的 XML 结构: \(details)"
        case let .contentLoadFailed(reason):
            "内容加载失败: \(reason)"
        case let .contentSaveFailed(reason):
            "内容保存失败: \(reason)"
        case let .imageLoadFailed(fileId, reason):
            "图片加载失败 [\(fileId ?? "unknown")]: \(reason)"
        case let .invalidEditorState(state):
            "无效的编辑器状态: \(state)"
        case let .contextSyncFailed(reason):
            "上下文同步失败: \(reason)"
        }
    }
}
