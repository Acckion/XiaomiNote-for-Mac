import SwiftUI
import AppKit

struct MiNoteEditor: NSViewRepresentable {
    @Binding var xmlContent: String
    @Binding var isEditable: Bool
    var onTextViewCreated: ((NSTextView) -> Void)? = nil

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
        
        // 启用富文本编辑
        textView.allowsUndo = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        // 设置文本容器宽度，使其可以自动换行
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude)

        // Set initial content
        textView.textStorage?.setAttributedString(MiNoteContentParser.parseToAttributedString(xmlContent))
        
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
        
        // Update content only if it's different from the current attributed string
        // This prevents infinite loops and preserves cursor position
        let newAttributedString = MiNoteContentParser.parseToAttributedString(xmlContent)
        if !textView.attributedString().isEqual(to: newAttributedString) {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(newAttributedString)
            textView.setSelectedRange(selectedRange)
        }
        
        textView.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MiNoteEditor
        var textView: NSTextView?

        init(_ parent: MiNoteEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Convert NSAttributedString back to XML content
            parent.xmlContent = MiNoteContentParser.parseToXML(textView.attributedString())
        }
    }
}
