//
//  NativeTextView+AttachmentInteraction.swift
//  MiNoteMac
//
//  附件点击和拖拽交互逻辑
//

import AppKit

extension NativeTextView {

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // 检查是否点击了附件
        if let layoutManager,
           let textContainer,
           let textStorage
        {
            let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            if charIndex < textStorage.length {
                // 检查是否点击了复选框附件
                if let attachment = textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? InteractiveCheckboxAttachment {
                    // 获取附件的边界
                    let glyphRange = NSRange(location: glyphIndex, length: 1)
                    let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                    // 检查点击是否在附件区域内
                    let adjustedRect = boundingRect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
                    if adjustedRect.contains(point) {
                        // 切换复选框状态
                        let newCheckedState = !attachment.isChecked
                        attachment.isChecked = newCheckedState

                        // 关键修复：强制标记 textStorage 为已修改
                        // 通过重新设置附件属性来触发 textStorage 的变化通知
                        textStorage.beginEditing()
                        textStorage.addAttribute(.attachment, value: attachment, range: NSRange(location: charIndex, length: 1))
                        textStorage.endEditing()

                        // 刷新显示
                        layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: charIndex, length: 1))

                        // 触发回调
                        onCheckboxClick?(attachment, charIndex)

                        // 通知代理 - 内容已变化
                        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

                        return
                    }
                }

                // 检查是否点击了音频附件
                if let audioAttachment = textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? AudioAttachment {
                    // 获取附件的边界
                    let glyphRange = NSRange(location: glyphIndex, length: 1)
                    let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                    // 检查点击是否在附件区域内
                    let adjustedRect = boundingRect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
                    if adjustedRect.contains(point) {
                        // 获取文件 ID
                        guard let fileId = audioAttachment.fileId, !fileId.isEmpty else {
                            return
                        }

                        // 发送通知，让音频面板处理播放
                        NotificationCenter.default.postAudioAttachmentClicked(fileId: fileId)

                        return
                    }
                }
            }
        }

        super.mouseDown(with: event)
    }

    // MARK: - Horizontal Rule Support

    /// 在光标位置插入分割线
    func insertHorizontalRuleAtCursor() {
        guard let textStorage else { return }

        let selectedRange = selectedRange()
        let insertionPoint = selectedRange.location

        textStorage.beginEditing()

        // 创建分割线附件
        let renderer = customRenderer ?? CustomRenderer()
        let attachment = renderer.createHorizontalRuleAttachment()
        let attachmentString = NSAttributedString(attachment: attachment)

        // 构建插入内容：换行 + 分割线 + 换行
        let result = NSMutableAttributedString()

        // 如果不在行首，先添加换行
        if insertionPoint > 0 {
            let string = textStorage.string as NSString
            let prevChar = string.character(at: insertionPoint - 1)
            if prevChar != 10 { // 10 是换行符的 ASCII 码
                result.append(NSAttributedString(string: "\n"))
            }
        }

        result.append(attachmentString)
        result.append(NSAttributedString(string: "\n"))

        // 删除选中内容并插入分割线
        textStorage.replaceCharacters(in: selectedRange, with: result)

        textStorage.endEditing()

        // 移动光标到分割线后
        let newCursorPosition = insertionPoint + result.length
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))

        // 通知代理
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }

    /// 删除选中的分割线
    func deleteSelectedHorizontalRule() -> Bool {
        guard let textStorage else { return false }

        let selectedRange = selectedRange()

        // 检查选中位置是否是分割线
        if selectedRange.location < textStorage.length {
            if let _ = textStorage.attribute(.attachment, at: selectedRange.location, effectiveRange: nil) as? HorizontalRuleAttachment {
                textStorage.beginEditing()

                // 删除分割线（包括可能的换行符）
                var deleteRange = NSRange(location: selectedRange.location, length: 1)

                // 检查前后是否有换行符需要一起删除
                let string = textStorage.string as NSString
                if deleteRange.location > 0 {
                    let prevChar = string.character(at: deleteRange.location - 1)
                    if prevChar == 10 {
                        deleteRange.location -= 1
                        deleteRange.length += 1
                    }
                }
                if deleteRange.location + deleteRange.length < string.length {
                    let nextChar = string.character(at: deleteRange.location + deleteRange.length)
                    if nextChar == 10 {
                        deleteRange.length += 1
                    }
                }

                textStorage.deleteCharacters(in: deleteRange)

                textStorage.endEditing()

                // 通知代理
                delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

                return true
            }
        }

        return false
    }
}
