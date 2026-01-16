//
//  AttachmentSelectionManager.swift
//  MiNoteMac
//
//  Created by Kiro AI
//

import AppKit

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
    
    /// 高亮视图
    private var highlightView: AttachmentHighlightView?
    
    /// 注册的 textView
    private weak var textView: NSTextView?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Registration
    
    /// 注册 textView
    /// - Parameter textView: 要注册的 NSTextView
    func register(textView: NSTextView) {
        self.textView = textView
        print("[AttachmentSelectionManager] 已注册 textView")
    }
    
    /// 取消注册
    func unregister() {
        removeHighlight()
        textView = nil
        selectedAttachment = nil
        selectedAttachmentIndex = nil
        print("[AttachmentSelectionManager] 已取消注册")
    }
    
    // MARK: - Selection Detection
    
    /// 处理选择变化
    /// - Parameter selectedRange: 新的选择范围
    func handleSelectionChange(_ selectedRange: NSRange) {
        guard let textView = textView,
              let textStorage = textView.textStorage else {
            print("[AttachmentSelectionManager] 错误: textView 或 textStorage 为 nil")
            return
        }
        
        print("[AttachmentSelectionManager] 处理选择变化: location=\(selectedRange.location), length=\(selectedRange.length)")
        
        // 如果选择范围长度大于 0，说明是文本选择，移除高亮
        if selectedRange.length > 0 {
            print("[AttachmentSelectionManager] 文本选择，移除高亮")
            removeHighlight()
            showCursor()
            return
        }
        
        // 检测光标位置是否在附件处
        if let (attachment, index) = detectAttachment(at: selectedRange.location, in: textStorage) {
            print("[AttachmentSelectionManager] 检测到附件: \(type(of: attachment)), index=\(index)")
            // 检查是否支持选择高亮
            if isSelectableAttachment(attachment) {
                print("[AttachmentSelectionManager] 附件支持选择高亮，显示高亮")
                // 显示高亮
                showHighlight(for: attachment, at: index)
                hideCursor()
                return
            } else {
                print("[AttachmentSelectionManager] 附件不支持选择高亮")
            }
        } else {
            print("[AttachmentSelectionManager] 未检测到附件")
        }
        
        // 光标不在附件处，移除高亮
        removeHighlight()
        showCursor()
    }
    
    /// 检测光标是否在附件处
    /// - Parameters:
    ///   - location: 光标位置
    ///   - textStorage: 文本存储
    /// - Returns: (附件, 字符索引) 或 nil
    func detectAttachment(at location: Int, in textStorage: NSTextStorage) -> (NSTextAttachment, Int)? {
        // 检查位置是否有效
        guard location >= 0 && location < textStorage.length else {
            return nil
        }
        
        // 检查当前位置的字符
        var effectiveRange = NSRange(location: 0, length: 0)
        if let attachment = textStorage.attribute(.attachment, at: location, effectiveRange: &effectiveRange) as? NSTextAttachment {
            // 光标正好在附件字符上
            return (attachment, location)
        }
        
        // 检查前一个位置（光标可能在附件后方）
        if location > 0 {
            if let attachment = textStorage.attribute(.attachment, at: location - 1, effectiveRange: &effectiveRange) as? NSTextAttachment {
                return (attachment, location - 1)
            }
        }
        
        return nil
    }
    
    /// 检查附件类型是否支持选择高亮
    /// - Parameter attachment: 附件对象
    /// - Returns: 是否支持
    func isSelectableAttachment(_ attachment: NSTextAttachment) -> Bool {
        // 支持所有附件类型的选择高亮
        // 包括：分割线、图片、录音、复选框、项目符号、有序列表
        return attachment is HorizontalRuleAttachment ||
               attachment is ImageAttachment ||
               attachment is AudioAttachment ||
               attachment is InteractiveCheckboxAttachment ||
               attachment is BulletAttachment ||
               attachment is OrderAttachment
    }
    
    // MARK: - Highlight Management
    
    /// 显示附件高亮
    /// - Parameters:
    ///   - attachment: 附件对象
    ///   - index: 字符索引
    func showHighlight(for attachment: NSTextAttachment, at index: Int) {
        guard let textView = textView else {
            print("[AttachmentSelectionManager] 错误: textView 为 nil")
            return
        }
        
        // 获取附件的显示区域
        guard let rect = getAttachmentRect(at: index, in: textView) else {
            print("[AttachmentSelectionManager] 错误: 无法获取附件显示区域")
            return
        }
        
        print("[AttachmentSelectionManager] 附件显示区域: \(rect)")
        
        // 保存选中状态
        selectedAttachment = attachment
        selectedAttachmentIndex = index
        
        // 创建或重用高亮视图
        if highlightView == nil {
            highlightView = AttachmentHighlightView(frame: rect)
            textView.addSubview(highlightView!)
            print("[AttachmentSelectionManager] 创建高亮视图，frame=\(rect)")
        } else {
            highlightView?.updateFrame(rect, animated: true)
            print("[AttachmentSelectionManager] 更新高亮视图，frame=\(rect)")
        }
        
        // 显示高亮
        highlightView?.show()
        print("[AttachmentSelectionManager] 显示高亮，alphaValue=\(highlightView?.alphaValue ?? 0)")
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
    /// - Parameters:
    ///   - index: 字符索引
    ///   - textView: 文本视图
    /// - Returns: 附件的显示区域
    func getAttachmentRect(at index: Int, in textView: NSTextView) -> CGRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }
        
        // 获取字符的 glyph 索引
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
        
        // 获取 glyph 的边界矩形
        var glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1),
                                                    in: textContainer)
        
        // 转换到 textView 坐标系
        glyphRect.origin.x += textContainer.lineFragmentPadding
        glyphRect.origin.y += textView.textContainerInset.height
        
        // 添加一些内边距使高亮更明显
        let padding: CGFloat = 2
        glyphRect = glyphRect.insetBy(dx: -padding, dy: -padding)
        
        return glyphRect
    }
    
    // MARK: - Cursor Management
    
    /// 隐藏文本光标
    func hideCursor() {
        guard let textView = textView else { return }
        
        // 方法1: 设置光标颜色为透明
        textView.insertionPointColor = .clear
        
        // 方法2: 强制刷新显示
        textView.setNeedsDisplay(textView.visibleRect)
        
        print("[AttachmentSelectionManager] 已隐藏光标")
    }
    
    /// 显示文本光标
    func showCursor() {
        guard let textView = textView else { return }
        
        // 恢复光标颜色
        textView.insertionPointColor = .textColor
        
        // 强制刷新显示
        textView.setNeedsDisplay(textView.visibleRect)
        
        print("[AttachmentSelectionManager] 已显示光标")
    }
    
    // MARK: - Query
    
    /// 是否有选中的附件
    var hasSelectedAttachment: Bool {
        return selectedAttachment != nil
    }
}
