//
//  EditorFormatDetector.swift
//  MiNoteMac
//
//  NativeEditorContext 的特殊元素检测扩展
//  负责光标位置的附件类型识别
//

import AppKit

/// NativeEditorContext 的特殊元素检测扩展
extension NativeEditorContext {

    /// 检测光标位置的特殊元素
    func detectSpecialElementAtCursor() {
        guard !nsAttributedText.string.isEmpty else {
            currentSpecialElement = nil
            return
        }

        let position = min(cursorPosition, nsAttributedText.length - 1)
        guard position >= 0 else {
            currentSpecialElement = nil
            return
        }

        // 检查是否有附件
        let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)

        if let attachment = attributes[.attachment] as? NSTextAttachment {
            // 识别附件类型
            if let checkboxAttachment = attachment as? InteractiveCheckboxAttachment {
                currentSpecialElement = .checkbox(
                    checked: checkboxAttachment.isChecked,
                    level: checkboxAttachment.level
                )
                // 更新工具栏状态
                toolbarButtonStates[.checkbox] = true
            } else if attachment is HorizontalRuleAttachment {
                currentSpecialElement = .horizontalRule
            } else if let bulletAttachment = attachment as? BulletAttachment {
                currentSpecialElement = .bulletPoint(indent: bulletAttachment.indent)
                toolbarButtonStates[.bulletList] = true
            } else if let orderAttachment = attachment as? OrderAttachment {
                currentSpecialElement = .numberedItem(
                    number: orderAttachment.number,
                    indent: orderAttachment.indent
                )
                toolbarButtonStates[.numberedList] = true
            } else if let imageAttachment = attachment as? ImageAttachment {
                currentSpecialElement = .image(
                    fileId: imageAttachment.fileId,
                    src: imageAttachment.src
                )
            } else {
                currentSpecialElement = nil
            }
        } else {
            currentSpecialElement = nil
            // 清除特殊元素相关的工具栏状态
            toolbarButtonStates[.checkbox] = false
            toolbarButtonStates[.bulletList] = false
            toolbarButtonStates[.numberedList] = false
        }
    }
}
