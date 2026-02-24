//
//  NativeEditorView.swift
//  MiNoteMac
//
//  原生编辑器视图 - 基于 NSTextView 的富文本编辑器
//

import AppKit
import Combine
import SwiftUI

// MARK: - NativeEditorView

/// 原生编辑器 SwiftUI 视图
/// 使用 NSViewRepresentable 包装 NSTextView 以支持完整的富文本编辑功能
struct NativeEditorView: NSViewRepresentable {

    // MARK: - Properties

    /// 编辑器上下文
    @ObservedObject var editorContext: NativeEditorContext

    /// 内容变化回调
    var onContentChange: ((NSAttributedString) -> Void)?

    /// 选择变化回调
    var onSelectionChange: ((NSRange) -> Void)?

    /// 是否可编辑
    var isEditable = true

    /// 是否显示行号
    var showLineNumbers = false

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSScrollView {
        // 测量初始化时间
        let startTime = CFAbsoluteTimeGetCurrent()
        let scrollView = createScrollView(context: context)
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000

        // 检查是否超过阈值
        if duration > 100 {
            LogService.shared.warning(.editor, "初始化时间超过 100ms (\(String(format: "%.2f", duration))ms)")
        }

        return scrollView
    }

    /// 创建滚动视图（内部方法）
    private func createScrollView(context: Context) -> NSScrollView {
        // 创建滚动视图
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // 创建垂直 StackView 作为 documentView（标题 + 正文）
        let stackView = FlippedStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // 创建标题 TextField
        let titleField = TitleTextField()
        titleField.isEditable = isEditable
        titleField.delegate = context.coordinator
        titleField.stringValue = editorContext.titleText

        // 创建优化的文本视图
        let textView = NativeTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFindBar = true

        // 禁用不必要的自动功能以提高性能
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false

        // 设置文本容器
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        // 设置外观
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        // 使用 FontSizeConstants 统一管理默认字体 (14pt)
        textView.font = NSFont.systemFont(ofSize: FontSizeConstants.body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor

        // 内边距：左右 16pt，上下 0（上边距由 stackView 布局控制）
        textView.textContainerInset = NSSize(width: 16, height: 0)

        // 设置自动调整大小
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // NSStackView 中使用 Auto Layout，需要关闭 autoresizing mask 转换
        // 但 NSTextView 的高度由内容决定，需要通过 invalidateIntrinsicContentSize 驱动
        textView.translatesAutoresizingMaskIntoConstraints = false

        // 组装 StackView
        stackView.addArrangedSubview(titleField)
        stackView.addArrangedSubview(textView)

        // 配置滚动视图
        scrollView.documentView = stackView

        // 约束：stackView 宽度跟随 scrollView.contentView
        NSLayoutConstraint.activate([
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        // 标题 TextField 约束：左右内边距与 textView 的 textContainerInset 对齐
        // NSTextField 文本起始位置比 NSTextView 偏左约 5pt，所以用 21pt 对齐
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 21),
            titleField.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -21),
            titleField.topAnchor.constraint(equalTo: stackView.topAnchor, constant: 16),
        ])

        // textView 宽度跟随 stackView，高度至少填满可见区域
        let textViewHeightConstraint = textView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor, constant: -60)
        textViewHeightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            textView.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            textViewHeightConstraint,
        ])

        // 保存引用
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.titleField = titleField

        // 加载初始内容
        if !editorContext.nsAttributedText.string.isEmpty {
            textView.textStorage?.setAttributedString(editorContext.nsAttributedText)
        }

        // 接线编辑器依赖到 NativeTextView
        textView.imageStorageManager = editorContext.imageStorageManager
        textView.customRenderer = editorContext.customRenderer
        textView.unifiedFormatManager = editorContext.unifiedFormatManager
        textView.attachmentSelectionManager = editorContext.attachmentSelectionManager
        textView.attachmentKeyboardHandler = editorContext.attachmentKeyboardHandler

        // 预热渲染器缓存
        editorContext.customRenderer.warmUpCache()

        // 注册 CursorFormatManager
        editorContext.cursorFormatManager?.register(textView: textView, context: editorContext)
        editorContext.unifiedFormatManager?.register(textView: textView, context: editorContext)
        editorContext.attachmentSelectionManager?.register(textView: textView)

        return scrollView
    }

    /// 视图销毁时取消注册 CursorFormatManager 和 UnifiedFormatManager
    static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        coordinator.parent.editorContext.cursorFormatManager?.unregister()
        coordinator.parent.editorContext.unifiedFormatManager?.unregister()
        coordinator.parent.editorContext.attachmentSelectionManager?.unregister()
    }

    func updateNSView(_: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        // 更新可编辑状态
        textView.isEditable = isEditable
        context.coordinator.titleField?.isEditable = isEditable

        // 同步标题文本（避免循环更新）
        if let titleField = context.coordinator.titleField,
           !context.coordinator.isUpdatingTitleProgrammatically,
           titleField.stringValue != editorContext.titleText
        {
            context.coordinator.isUpdatingTitleProgrammatically = true
            titleField.stringValue = editorContext.titleText
            context.coordinator.isUpdatingTitleProgrammatically = false
        }

        // 确保文字颜色适配当前外观（深色/浅色模式）
        textView.textColor = .labelColor

        // 检查内容是否需要更新（避免循环更新）
        if !context.coordinator.isUpdatingFromTextView {
            let currentText = textView.attributedString()
            let newText = editorContext.nsAttributedText

            // 修改：增加版本号比较，确保内容变化时强制更新
            // 当笔记切换时，即使字符串内容相同但格式不同，也需要更新
            let versionChanged = context.coordinator.lastContentVersion != editorContext.contentVersion
            let contentChanged = currentText.string != newText.string
            let lengthChanged = currentText.length != newText.length

            if versionChanged || contentChanged || lengthChanged {
                context.coordinator.lastContentVersion = editorContext.contentVersion

                // 保存当前选择范围
                let selectedRange = textView.selectedRange()

                // 标记正在从 SwiftUI 更新，防止 textViewDidChangeSelection 中的 @Published 赋值
                context.coordinator.isUpdatingFromSwiftUI = true

                // 更新内容
                textView.textStorage?.setAttributedString(newText)

                // 新增：强制刷新显示，确保格式正确渲染
                textView.needsDisplay = true

                // 初始化音频附件集合（用于删除检测）
                context.coordinator.previousAudioFileIds = context.coordinator.extractAudioFileIds(from: newText)

                // 恢复选择范围（如果有效）
                if selectedRange.location <= textView.string.count {
                    let newRange = NSRange(
                        location: min(selectedRange.location, textView.string.count),
                        length: min(selectedRange.length, max(0, textView.string.count - selectedRange.location))
                    )
                    textView.setSelectedRange(newRange)
                }

                context.coordinator.isUpdatingFromSwiftUI = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let nativeEditorFormatCommand = Notification.Name("nativeEditorFormatCommand")
    static let nativeEditorRequestContentSync = Notification.Name("nativeEditorRequestContentSync")
    // nativeEditorNeedsRefresh 已在 NativeEditorErrorHandler.swift 中定义
}

// MARK: - Preview

#if DEBUG
    struct NativeEditorView_Previews: PreviewProvider {
        static var previews: some View {
            NativeEditorView(editorContext: NativeEditorContext())
                .frame(width: 600, height: 400)
        }
    }
#endif
