import SwiftUI
import AppKit

struct MiNoteEditor: NSViewRepresentable {
    @Binding var xmlContent: String
    @Binding var isEditable: Bool
    var noteRawData: [String: Any]? = nil
    var onTextViewCreated: ((NSTextView) -> Void)? = nil
    var title: String = ""  // 标题文本
    var onTitleChange: ((String) -> Void)? = nil  // 标题变化回调

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 16, height: 10)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        
        // 设置文本颜色，自动适配深色模式
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        
        // 设置默认段落样式，增加行间距
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6.0  // 行间距：6点（可根据需要调整）
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        
        // 启用富文本编辑
        textView.allowsUndo = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        // 设置文本容器宽度，使其可以自动换行
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude)

        // Set initial content with title
        let contentWithTitle = createContentWithTitle(title: title, xmlContent: xmlContent, noteRawData: noteRawData)
        textView.textStorage?.setAttributedString(contentWithTitle)
        
        // 存储标题范围，用于检测标题变化
        context.coordinator.titleRange = NSRange(location: 0, length: title.isEmpty ? 0 : title.count)
        
        textView.isEditable = isEditable
        
        // 通知外部 textView 已创建
        context.coordinator.textView = textView
        onTextViewCreated?(textView)
        
        // 通过 NotificationCenter 通知工具栏
        NotificationCenter.default.post(name: NSNotification.Name("MiNoteEditorTextViewCreated"), object: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        
        // 确保文本颜色和背景色正确（适配深色模式）
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        
        // Update content with title only if it's different from the current attributed string
        // This prevents infinite loops and preserves cursor position
        let newAttributedString = createContentWithTitle(title: title, xmlContent: xmlContent, noteRawData: noteRawData)
        if !textView.attributedString().isEqual(to: newAttributedString) {
            let selectedRange = textView.selectedRange()
            let oldTitleRange = context.coordinator.titleRange
            
            textView.textStorage?.setAttributedString(newAttributedString)
            
            // 更新标题范围
            context.coordinator.titleRange = NSRange(location: 0, length: title.isEmpty ? 0 : title.count)
            
            // 如果光标在标题区域，保持相对位置；否则恢复原位置
            if selectedRange.location < oldTitleRange.length {
                // 光标在标题区域，调整到新标题的相应位置
                let newLocation = min(selectedRange.location, context.coordinator.titleRange.length)
                textView.setSelectedRange(NSRange(location: newLocation, length: 0))
            } else {
                // 光标在正文区域，需要调整位置（因为标题长度可能变化）
                let titleLengthDiff = context.coordinator.titleRange.length - oldTitleRange.length
                let newLocation = max(context.coordinator.titleRange.length + 2, selectedRange.location + titleLengthDiff)
                textView.setSelectedRange(NSRange(location: newLocation, length: selectedRange.length))
            }
        }
        
        textView.isEditable = isEditable
    }
    
    /// 创建包含标题的内容
    private func createContentWithTitle(title: String, xmlContent: String, noteRawData: [String: Any]?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        // 创建段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6.0
        
        // 如果有标题，添加标题
        if !title.isEmpty {
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 28, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
            result.append(NSAttributedString(string: title, attributes: titleAttrs))
            result.append(NSAttributedString(string: "\n\n", attributes: [
                .paragraphStyle: paragraphStyle
            ]))
        }
        
        // 添加正文内容
        let contentAttributedString = MiNoteContentParser.parseToAttributedString(xmlContent, noteRawData: noteRawData)
        result.append(contentAttributedString)
        
        return result
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MiNoteEditor
        var textView: NSTextView?
        var titleRange: NSRange = NSRange(location: 0, length: 0)  // 标题的范围

        init(_ parent: MiNoteEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let textStorage = textView.textStorage else { return }
            
            let fullString = textView.string as NSString
            let fullLength = textStorage.length
            
            // 提取标题（第一行，直到第一个换行符）
            var newTitle = ""
            var titleEndIndex = 0
            
            let newlineRange = fullString.range(of: "\n")
            if newlineRange.location != NSNotFound {
                newTitle = fullString.substring(to: newlineRange.location)
                titleEndIndex = newlineRange.location
            } else if fullLength > 0 {
                newTitle = fullString as String
                titleEndIndex = fullLength
            }
            
            // 如果标题发生变化，通知外部
            if newTitle != parent.title {
                parent.onTitleChange?(newTitle)
            }
            
            // 更新标题范围
            titleRange = NSRange(location: 0, length: titleEndIndex)
            
            // 提取正文内容（标题之后的内容，跳过标题后的换行符）
            // 标题后通常有一个或两个换行符（标题和正文之间的空行）
            var contentStartIndex = titleEndIndex
            if contentStartIndex < fullLength {
                // 跳过第一个换行符
                if contentStartIndex < fullLength {
                    let char = fullString.substring(with: NSRange(location: contentStartIndex, length: 1))
                    if char == "\n" {
                        contentStartIndex += 1
                    }
                }
                // 跳过第二个换行符（如果有）
                if contentStartIndex < fullLength {
                    let char = fullString.substring(with: NSRange(location: contentStartIndex, length: 1))
                    if char == "\n" {
                        contentStartIndex += 1
                    }
                }
            }
            
            // 从 textStorage 中提取正文部分的属性字符串
            if contentStartIndex < fullLength {
                let contentRange = NSRange(location: contentStartIndex, length: fullLength - contentStartIndex)
                let contentAttributedString = textStorage.attributedSubstring(from: contentRange)
                parent.xmlContent = MiNoteContentParser.parseToXML(contentAttributedString)
            } else {
                // 没有正文内容
                parent.xmlContent = ""
            }
        }
    }
}
