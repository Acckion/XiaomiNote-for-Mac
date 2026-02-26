//
//  EditorEnums.swift
//  MiNoteMac
//
//  编辑器相关枚举定义
//

import SwiftUI

/// 文本格式类型枚举
public enum TextFormat: CaseIterable, Hashable, Sendable {
    case bold // 加粗
    case italic // 斜体
    case underline // 下划线
    case strikethrough // 删除线
    case highlight // 高亮
    case heading1 // 大标题
    case heading2 // 二级标题
    case heading3 // 三级标题
    case alignCenter // 居中对齐
    case alignRight // 右对齐
    case bulletList // 无序列表
    case numberedList // 有序列表
    case checkbox // 复选框
    case quote // 引用块
    case horizontalRule // 分割线

    /// 格式的显示名称
    var displayName: String {
        switch self {
        case .bold: "加粗"
        case .italic: "斜体"
        case .underline: "下划线"
        case .strikethrough: "删除线"
        case .highlight: "高亮"
        case .heading1: "大标题"
        case .heading2: "二级标题"
        case .heading3: "三级标题"
        case .alignCenter: "居中"
        case .alignRight: "右对齐"
        case .bulletList: "无序列表"
        case .numberedList: "有序列表"
        case .checkbox: "复选框"
        case .quote: "引用"
        case .horizontalRule: "分割线"
        }
    }

    /// 格式的快捷键
    var keyboardShortcut: KeyEquivalent? {
        switch self {
        case .bold: "b"
        case .italic: "i"
        case .underline: "u"
        default: nil
        }
    }

    /// 是否需要 Command 修饰键
    var requiresCommand: Bool {
        switch self {
        case .bold, .italic, .underline: true
        default: false
        }
    }

    /// 是否是块级格式（影响整行）
    var isBlockFormat: Bool {
        switch self {
        case .heading1, .heading2, .heading3, .alignCenter, .alignRight,
             .bulletList, .numberedList, .checkbox, .quote, .horizontalRule:
            true
        default:
            false
        }
    }

    /// 是否是内联格式（只影响选中文本）
    var isInlineFormat: Bool {
        !isBlockFormat
    }
}

/// 特殊元素类型枚举
enum SpecialElement: Equatable {
    case checkbox(checked: Bool, level: Int)
    case horizontalRule
    case bulletPoint(indent: Int)
    case numberedItem(number: Int, indent: Int)
    case quote(content: String)
    case image(fileId: String?, src: String?)
    case audio(fileId: String, digest: String?, mimeType: String?)

    /// 元素的显示名称
    var displayName: String {
        switch self {
        case .checkbox: "复选框"
        case .horizontalRule: "分割线"
        case .bulletPoint: "项目符号"
        case .numberedItem: "编号列表"
        case .quote: "引用块"
        case .image: "图片"
        case .audio: "语音录音"
        }
    }

    /// 是否为文件附件（图片/音频），需要即时保存以配合上传流程
    var isFileAttachment: Bool {
        switch self {
        case .image, .audio: true
        default: false
        }
    }
}

/// 缩进操作类型枚举
enum IndentOperation: Equatable {
    case increase // 增加缩进
    case decrease // 减少缩进

    /// 操作的显示名称
    var displayName: String {
        switch self {
        case .increase: "增加缩进"
        case .decrease: "减少缩进"
        }
    }
}
