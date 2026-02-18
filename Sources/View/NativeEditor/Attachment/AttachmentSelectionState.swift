//
//  AttachmentSelectionState.swift
//  MiNoteMac
//
//  Created by Kiro AI
//

import AppKit

/// 附件选择状态
/// 用于跟踪当前选中的附件及其相关信息
struct AttachmentSelectionState {
    /// 选中的附件
    let attachment: NSTextAttachment

    /// 附件的字符索引
    let characterIndex: Int

    /// 附件的显示区域
    let rect: CGRect

    /// 附件类型
    let type: AttachmentType
}

/// 附件类型枚举
/// 定义了编辑器支持的所有附件类型
enum AttachmentType {
    case horizontalRule // 分割线
    case image // 图片
    case audio // 录音
    case checkbox // 复选框
    case bullet // 项目符号
    case order // 有序列表
}
