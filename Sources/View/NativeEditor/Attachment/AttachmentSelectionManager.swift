import AppKit

/// 光标相对于附件的位置
enum CursorPositionRelativeToAttachment {
    case beforeAttachment // 光标在附件左边
    case afterAttachment // 光标在附件右边
    case notAtAttachment // 光标不在附件处
}

/// 附件选择管理器
/// 负责检测光标位置、管理选择状态、协调高亮显示
@MainActor
class AttachmentSelectionManager {
    // MARK: - Properties

    /// 单例实例
    static let shared = AttachmentSelectionManager()

    /// 当前选中的附件
    private(set) var selectedAttachment: NSTextAttachment?

    /// 当前选中附件的字符索引
    private(set) var selectedAttachmentIndex: Int?

    /// 光标相对于附件的位置
    private(set) var cursorPosition: CursorPositionRelativeToAttachment = .notAtAttachment

    /// 高亮视图
    private var highlightView: AttachmentHighlightView?

    /// 注册的 textView
    private weak var textView: NSTextView?

    // MARK: - Initialization

    init() {}

    // MARK: - Registration

    /// 注册 textView
    func register(textView: NSTextView) {
        self.textView = textView
    }

    /// 取消注册
    func unregister() {
        removeHighlight()
        textView = nil
        selectedAttachment = nil
        selectedAttachmentIndex = nil
    }

    // MARK: - Selection Detection

    /// 处理选择变化
    func handleSelectionChange(_ selectedRange: NSRange) {
        guard let textView,
              let textStorage = textView.textStorage
        else {
            return
        }

        // 文本选择时移除高亮
        if selectedRange.length > 0 {
            cursorPosition = .notAtAttachment
            removeHighlight()
            showCursor()
            return
        }

        if let (attachment, index, position) = detectAttachmentAndPosition(at: selectedRange.location, in: textStorage) {
            cursorPosition = position

            if isSelectableAttachment(attachment) {
                if position == .afterAttachment {
                    showHighlight(for: attachment, at: index)
                    hideCursor()
                } else {
                    removeHighlight()
                    showCursor()
                }
                return
            }
        }

        cursorPosition = .notAtAttachment
        removeHighlight()
        showCursor()
    }

    /// 检测光标相对于附件的位置
    func detectAttachmentAndPosition(
        at location: Int,
        in textStorage: NSTextStorage
    ) -> (NSTextAttachment, Int, CursorPositionRelativeToAttachment)? {
        guard location >= 0, location <= textStorage.length else {
            return nil
        }

        // 情况1: 光标在附件左边
        if location < textStorage.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            if let attachment = textStorage.attribute(.attachment, at: location, effectiveRange: &effectiveRange) as? NSTextAttachment {
                return (attachment, location, .beforeAttachment)
            }
        }

        // 情况2: 光标在附件右边
        if location > 0, location <= textStorage.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            if let attachment = textStorage.attribute(.attachment, at: location - 1, effectiveRange: &effectiveRange) as? NSTextAttachment {
                return (attachment, location - 1, .afterAttachment)
            }
        }

        return nil
    }

    /// 检测光标是否在附件处（兼容旧代码）
    func detectAttachment(at location: Int, in textStorage: NSTextStorage) -> (NSTextAttachment, Int)? {
        if let (attachment, index, _) = detectAttachmentAndPosition(at: location, in: textStorage) {
            return (attachment, index)
        }
        return nil
    }

    /// 检查附件类型是否支持选择高亮
    func isSelectableAttachment(_ attachment: NSTextAttachment) -> Bool {
        attachment is HorizontalRuleAttachment ||
            attachment is ImageAttachment ||
            attachment is AudioAttachment
    }

    // MARK: - Highlight Management

    /// 显示附件高亮
    func showHighlight(for attachment: NSTextAttachment, at index: Int) {
        guard let textView else {
            return
        }

        guard let rect = getAttachmentRect(at: index, in: textView) else {
            return
        }

        selectedAttachment = attachment
        selectedAttachmentIndex = index

        if highlightView == nil {
            highlightView = AttachmentHighlightView(frame: rect)
            textView.addSubview(highlightView!)
        } else {
            highlightView?.updateFrame(rect, animated: false)
        }

        if attachment is HorizontalRuleAttachment {
            highlightView?.highlightStyle = .thickLine
        } else {
            highlightView?.highlightStyle = .border
        }

        highlightView?.show()
    }

    /// 移除附件高亮
    func removeHighlight() {
        highlightView?.hide()
        highlightView?.removeFromSuperview()
        highlightView = nil
        selectedAttachment = nil
        selectedAttachmentIndex = nil
    }

    /// 获取附件的显示区域
    func getAttachmentRect(at index: Int, in textView: NSTextView) -> CGRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            return nil
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)

        var glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )

        glyphRect.origin.x += textView.textContainerInset.width
        glyphRect.origin.y += textView.textContainerInset.height

        let padding: CGFloat = 2
        glyphRect = glyphRect.insetBy(dx: -padding, dy: -padding)

        return glyphRect
    }

    // MARK: - Cursor Management

    /// 隐藏文本光标
    func hideCursor() {
        guard let textView else { return }
        textView.insertionPointColor = .clear
        textView.setNeedsDisplay(textView.visibleRect)
    }

    /// 显示文本光标
    func showCursor() {
        guard let textView else { return }
        textView.insertionPointColor = .controlAccentColor
        textView.setNeedsDisplay(textView.visibleRect)
    }

    // MARK: - Query

    /// 是否有选中的附件
    var hasSelectedAttachment: Bool {
        selectedAttachment != nil
    }

    /// 光标是否在附件左边
    var isCursorBeforeAttachment: Bool {
        cursorPosition == .beforeAttachment
    }

    /// 光标是否在附件右边
    var isCursorAfterAttachment: Bool {
        cursorPosition == .afterAttachment
    }
}
