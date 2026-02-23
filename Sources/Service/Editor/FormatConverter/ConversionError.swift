//
//  ConversionError.swift
//  MiNoteMac
//
//  格式转换错误类型定义
//

import Foundation

/// 转换错误类型
enum ConversionError: Error, LocalizedError {
    case invalidXML(String)
    case conversionFailed(Error)
    case conversionInconsistent
    case unsupportedElement(String)

    var errorDescription: String? {
        switch self {
        case let .invalidXML(message):
            "无效的 XML 格式: \(message)"
        case let .conversionFailed(error):
            "转换失败: \(error.localizedDescription)"
        case .conversionInconsistent:
            "转换结果不一致"
        case let .unsupportedElement(element):
            "不支持的元素: \(element)"
        }
    }
}
