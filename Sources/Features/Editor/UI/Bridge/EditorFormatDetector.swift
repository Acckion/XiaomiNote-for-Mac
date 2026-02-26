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
    /// 工具栏格式状态由 CursorFormatManager 统一驱动，此处仅负责附件类型识别
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

        let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)

        if let attachment = attributes[.attachment] as? NSTextAttachment {
            if let checkboxAttachment = attachment as? InteractiveCheckboxAttachment {
                currentSpecialElement = .checkbox(
                    checked: checkboxAttachment.isChecked,
                    level: checkboxAttachment.level
                )
            } else if attachment is HorizontalRuleAttachment {
                currentSpecialElement = .horizontalRule
            } else if let bulletAttachment = attachment as? BulletAttachment {
                currentSpecialElement = .bulletPoint(indent: bulletAttachment.indent)
            } else if let orderAttachment = attachment as? OrderAttachment {
                currentSpecialElement = .numberedItem(
                    number: orderAttachment.number,
                    indent: orderAttachment.indent
                )
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
        }
    }
}
