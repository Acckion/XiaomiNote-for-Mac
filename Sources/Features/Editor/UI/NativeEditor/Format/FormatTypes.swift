//
//  FormatTypes.swift
//  MiNoteMac
//
//  格式模块公共类型定义
//

import Foundation

// MARK: - 列表类型枚举

/// 列表类型
public enum ListType: Equatable {
    case bullet // 无序列表
    case ordered // 有序列表
    case checkbox // 复选框列表
    case none // 非列表
}

// MARK: - 标题级别枚举

/// 标题级别
enum HeadingLevel: Int {
    case none = 0
    case h1 = 1 // 大标题
    case h2 = 2 // 二级标题
    case h3 = 3 // 三级标题
}

// MARK: - NSAttributedString.Key 扩展

import AppKit

extension NSAttributedString.Key {
    /// 列表类型属性键
    static let listType = NSAttributedString.Key("listType")

    /// 列表缩进级别属性键
    static let listIndent = NSAttributedString.Key("listIndent")

    /// 列表编号属性键
    static let listNumber = NSAttributedString.Key("listNumber")

    /// 标题级别属性键
    static let headingLevel = NSAttributedString.Key("headingLevel")

    /// 复选框级别属性键（对应 XML 中的 level 属性）
    static let checkboxLevel = NSAttributedString.Key("checkboxLevel")

    /// 复选框选中状态属性键
    static let checkboxChecked = NSAttributedString.Key("checkboxChecked")
}
