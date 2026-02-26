//
//  NativeTextView+Paste.swift
//  MiNoteMac
//
//  粘贴逻辑（富文本、纯文本、图片）
//

import AppKit

extension NativeTextView {

    // MARK: - Paste Support

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // 检查是否有图片
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            // 处理图片粘贴
            insertImage(image)
            return
        }

        // 默认粘贴行为
        super.paste(sender)
    }

    /// 插入图片
    private func insertImage(_ image: NSImage) {
        guard let textStorage else { return }

        // 获取当前文件夹 ID（从编辑器上下文获取）
        // 如果没有文件夹 ID，使用默认值
        let folderId = "default"

        // 保存图片到本地存储
        guard let imageStorageManager,
              let saveResult = imageStorageManager.saveImage(image, folderId: folderId)
        else {
            return
        }

        let fileId = saveResult.fileId

        // 创建图片附件
        guard let customRenderer else { return }
        let attachment = customRenderer.createImageAttachment(
            image: image,
            fileId: fileId,
            folderId: folderId
        )

        let attachmentString = NSAttributedString(attachment: attachment)

        // 构建插入内容
        let result = NSMutableAttributedString()

        let selectedRange = selectedRange()
        let insertionPoint = selectedRange.location

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

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: selectedRange, with: result)
        textStorage.endEditing()

        // 移动光标到图片后
        let newCursorPosition = insertionPoint + result.length
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))

        // 通知代理
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

    }
}
