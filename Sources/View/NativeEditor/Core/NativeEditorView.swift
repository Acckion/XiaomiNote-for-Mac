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
        stackView.spacing = 0
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
        // 使用 FontSizeManager 统一管理默认字体 (14pt)
        textView.font = FontSizeManager.shared.defaultFont
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

        // 预热渲染器缓存
        CustomRenderer.shared.warmUpCache()

        // 注册 CursorFormatManager
        CursorFormatManager.shared.register(textView: textView, context: editorContext)
        UnifiedFormatManager.shared.register(textView: textView, context: editorContext)
        AttachmentSelectionManager.shared.register(textView: textView)

        return scrollView
    }

    /// 视图销毁时取消注册 CursorFormatManager 和 UnifiedFormatManager
    static func dismantleNSView(_: NSScrollView, coordinator _: Coordinator) {
        CursorFormatManager.shared.unregister()
        UnifiedFormatManager.shared.unregister()
        AttachmentSelectionManager.shared.unregister()
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

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate, NSTextFieldDelegate {
        var parent: NativeEditorView
        weak var textView: NativeTextView?
        weak var scrollView: NSScrollView?
        weak var titleField: TitleTextField?
        var isUpdatingFromTextView = false

        /// 标记是否正在从 SwiftUI updateNSView 更新（诊断用）
        var isUpdatingFromSwiftUI = false

        /// 标记是否正在程序化更新标题（防止循环）
        var isUpdatingTitleProgrammatically = false

        private var cancellables = Set<AnyCancellable>()

        /// 上一次的音频附件文件 ID 集合（用于检测删除）
        var previousAudioFileIds: Set<String> = []

        /// 上一次的内容版本号（用于检测内容变化）
        var lastContentVersion = 0

        // MARK: - Paper-Inspired Managers (Task 19.1)

        /// 段落管理器 - 负责段落边界检测和段落列表维护
        private let paragraphManager = ParagraphManager()

        /// 属性管理器 - 负责分层属性管理
        private let attributeManager = AttributeManager()

        /// 性能缓存 - 缓存常用的属性对象
        private let performanceCache = PerformanceCache.shared

        /// 打字优化器 - 检测简单输入场景并优化更新策略
        private let typingOptimizer = TypingOptimizer.shared

        /// 选择锚点管理器 - 管理文本选择的锚点
        private let selectionAnchorManager = SelectionAnchorManager()

        /// 撤销合并管理器 - 管理撤销操作的合并策略
        private let undoCoalescingManager = UndoCoalescingManager()

        init(_ parent: NativeEditorView) {
            self.parent = parent
            super.init()
            setupObservers()
        }

        private func setupObservers() {
            // 监听格式变化
            parent.editorContext.formatChangePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] format in
                    self?.applyFormat(format)
                }
                .store(in: &cancellables)

            // 监听特殊元素插入
            parent.editorContext.specialElementPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] element in
                    self?.insertSpecialElement(element)
                }
                .store(in: &cancellables)

            // 监听缩进操作
            parent.editorContext.indentChangePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] operation in
                    self?.applyIndentOperation(operation)
                }
                .store(in: &cancellables)

            // 监听内容变化（用于录音模板插入等外部内容更新）
            // 当 NativeEditorContext.updateNSContent 被调用时，直接更新 textView
            // 这解决了 SwiftUI 无法检测 NSAttributedString 内容变化的问题
            parent.editorContext.contentChangePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newContent in
                    self?.handleExternalContentUpdate(newContent)
                }
                .store(in: &cancellables)

            // 监听内容同步请求
            NotificationCenter.default.publisher(for: .nativeEditorRequestContentSync)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self,
                          let context = notification.object as? NativeEditorContext,
                          context === parent.editorContext else { return }

                    syncContentToContext()
                }
                .store(in: &cancellables)

            // 监听编辑器焦点变化 - 当 textView 成为第一响应者时更新焦点状态
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self,
                          let textView,
                          let window = notification.object as? NSWindow,
                          textView.window === window else { return }

                    // 检查 textView 是否是第一响应者
                    if window.firstResponder === textView {
                        parent.editorContext.setEditorFocused(true)
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .nativeEditorFormatCommand)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self,
                          let format = notification.object as? TextFormat else { return }

                    handleKeyboardShortcutFormat(format)
                }
                .store(in: &cancellables)

            // 当用户撤销或重做格式操作时，确保格式菜单状态正确更新
            NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self else { return }

                    // 验证通知来源是否与当前编辑器相关
                    if let undoManager = notification.object as? UndoManager,
                       let textViewUndoManager = textView?.undoManager,
                       undoManager === textViewUndoManager
                    {
                        handleUndoOperation()
                    } else {
                        handleUndoOperation()
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self else { return }

                    // 验证通知来源是否与当前编辑器相关
                    if let undoManager = notification.object as? UndoManager,
                       let textViewUndoManager = textView?.undoManager,
                       undoManager === textViewUndoManager
                    {
                        handleRedoOperation()
                    } else {
                        handleRedoOperation()
                    }
                }
                .store(in: &cancellables)
        }

        // MARK: - 快捷键格式处理

        /// 处理快捷键格式命令
        /// - Parameter format: 格式类型
        private func handleKeyboardShortcutFormat(_ format: TextFormat) {
            applyFormatWithMethod(.keyboard, format: format)
            syncContentToContext()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                self.parent.editorContext.forceUpdateFormats()
            }
        }

        // MARK: - 撤销/重做处理

        /// 撤销/重做状态处理器
        private let undoRedoHandler = UndoRedoStateHandler.shared

        /// 处理撤销操作
        private func handleUndoOperation() {
            let formatsBefore = parent.editorContext.currentFormats

            undoRedoHandler.setContentSyncCallback { [weak self] in
                self?.syncContentToContext()
            }
            undoRedoHandler.setStateUpdateCallback { [weak self] in
                self?.parent.editorContext.forceUpdateFormats()
            }
            undoRedoHandler.handleOperation(.undo)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.syncContentToContext()
                self.parent.editorContext.forceUpdateFormats()
                let formatsAfter = self.parent.editorContext.currentFormats
                if formatsBefore != formatsAfter {
                    LogService.shared.debug(.editor, "撤销操作完成，格式已变化")
                }
            }
        }

        /// 处理重做操作
        private func handleRedoOperation() {
            let formatsBefore = parent.editorContext.currentFormats

            undoRedoHandler.setContentSyncCallback { [weak self] in
                self?.syncContentToContext()
            }
            undoRedoHandler.setStateUpdateCallback { [weak self] in
                self?.parent.editorContext.forceUpdateFormats()
            }
            undoRedoHandler.handleOperation(.redo)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.syncContentToContext()
                self.parent.editorContext.forceUpdateFormats()
                let formatsAfter = self.parent.editorContext.currentFormats
                if formatsBefore != formatsAfter {
                    LogService.shared.debug(.editor, "重做操作完成，格式已变化")
                }
            }
        }

        /// 处理撤销/重做操作（兼容旧代码）
        private func handleUndoRedoOperation() {
            syncContentToContext()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                self.parent.editorContext.forceUpdateFormats()
            }
        }

        // MARK: - 外部内容更新处理

        /// 处理外部内容更新（如录音模板插入、笔记切换）
        ///
        /// 当 NativeEditorContext.updateNSContent 或 loadFromXML 被调用时，此方法会被触发
        /// 直接更新 textView 的内容，解决 SwiftUI 无法检测 NSAttributedString 变化的问题
        ///
        /// - Parameter newContent: 新的内容
        private func handleExternalContentUpdate(_ newContent: NSAttributedString) {
            guard let textView else { return }
            guard let textStorage = textView.textStorage else { return }
            guard !isUpdatingFromTextView else { return }

            if textStorage.string == newContent.string { return }

            let selectedRange = textView.selectedRange()
            isUpdatingFromTextView = true
            textStorage.setAttributedString(newContent)
            textView.needsDisplay = true
            previousAudioFileIds = extractAudioFileIds(from: newContent)

            let newLength = textStorage.length
            if selectedRange.location <= newLength {
                let newRange = NSRange(
                    location: min(selectedRange.location, newLength),
                    length: min(selectedRange.length, max(0, newLength - selectedRange.location))
                )
                textView.setSelectedRange(newRange)
            }

            isUpdatingFromTextView = false
        }

        /// 统计 NSAttributedString 中的附件数量
        /// - Parameter attributedString: 要检查的富文本
        /// - Returns: 附件数量
        private func countAttachments(in attributedString: NSAttributedString) -> Int {
            var count = 0
            attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length)) { value, _, _ in
                if value != nil {
                    count += 1
                }
            }
            return count
        }

        /// 同步 textView 内容到 editorContext
        private func syncContentToContext() {
            guard let textView else {
                return
            }

            guard let textStorage = textView.textStorage else {
                return
            }

            // 直接从 textStorage 获取内容（而不是 attributedString()）
            let attributedString = NSAttributedString(attributedString: textStorage)
            let selectedRange = textView.selectedRange()

            // 打印位置 16 处的属性（用于调试）
            if selectedRange.location < textStorage.length {
                let attrs = textStorage.attributes(at: selectedRange.location, effectiveRange: nil)
                for (key, value) in attrs {}

                // 检查字体
                if let font = attrs[.font] as? NSFont {
                    let traits = font.fontDescriptor.symbolicTraits
                }
            }

            // 关键修复：同步更新 nsAttributedText，确保菜单栏验证时数据是最新的
            // 之前使用 Task 异步更新，导致 validateMenuItem 调用时数据还没更新
            parent.editorContext.nsAttributedText = attributedString

            // 更新选择范围
            parent.editorContext.updateSelectedRange(selectedRange)

            // 异步更新格式状态，避免在视图更新中触发其他视图更新
            parent.editorContext.updateCurrentFormatsAsync()
        }

        // MARK: - 音频附件删除检测

        /// 提取 NSAttributedString 中的音频附件文件 ID
        /// - Parameter attributedString: 要检查的富文本
        /// - Returns: 音频附件文件 ID 集合
        func extractAudioFileIds(from attributedString: NSAttributedString) -> Set<String> {
            var fileIds: Set<String> = []

            attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length)) { value, _, _ in
                if let audioAttachment = value as? AudioAttachment,
                   let fileId = audioAttachment.fileId
                {
                    fileIds.insert(fileId)
                }
            }

            return fileIds
        }

        /// 检测并处理音频附件删除
        /// - Parameter currentAttributedString: 当前的富文本内容
        private func detectAndHandleAudioAttachmentDeletion(currentAttributedString: NSAttributedString) {
            let currentAudioFileIds = extractAudioFileIds(from: currentAttributedString)

            // 找出被删除的音频附件
            let deletedFileIds = previousAudioFileIds.subtracting(currentAudioFileIds)

            // 处理每个被删除的音频附件
            for fileId in deletedFileIds {
                AudioPanelStateManager.shared.handleAudioAttachmentDeleted(fileId: fileId)
            }

            // 更新记录的音频附件集合
            previousAudioFileIds = currentAudioFileIds
        }

        // MARK: - NSTextFieldDelegate

        func controlTextDidChange(_ notification: Notification) {
            guard let titleField = notification.object as? TitleTextField else { return }
            guard !isUpdatingTitleProgrammatically else { return }

            isUpdatingTitleProgrammatically = true
            parent.editorContext.titleText = titleField.stringValue
            parent.editorContext.hasUnsavedChanges = true
            isUpdatingTitleProgrammatically = false
        }

        /// 处理标题 TextField 的特殊按键（Enter/Tab → 焦点转移到正文）
        func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if control is TitleTextField,
               commandSelector == #selector(NSResponder.insertNewline(_:)) ||
               commandSelector == #selector(NSResponder.insertTab(_:))
            {
                guard let textView else { return true }
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                return true
            }
            return false
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard notification.object is TitleTextField else { return }
            parent.editorContext.setEditorFocused(true)
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard let textStorage = textView.textStorage else { return }

            // 记录输入法检测（性能监控）
            PerformanceMonitor.shared.recordInputMethodDetection()

            // 检查是否处于输入法组合状态（如中文拼音输入）
            // 如果有 markedText，说明用户正在输入拼音但还未选择候选词
            // 此时不应该触发保存，否则会中断输入法的候选词选择
            if textView.hasMarkedText() {
                // 记录跳过保存（输入法状态）
                PerformanceMonitor.shared.recordSkippedSaveInputMethod()
                return
            }

            isUpdatingFromTextView = true

            // 关键修复：使用 NSAttributedString(attributedString: textStorage) 而不是 textView.attributedString()
            // textView.attributedString() 可能不会保留自定义属性（如 XMLContent、RecordingTemplate 等）
            // 而直接从 textStorage 创建 NSAttributedString 会保留所有属性
            let attributedString = NSAttributedString(attributedString: textStorage)
            let contentChangeCallback = parent.onContentChange

            // 检测音频附件删除
            detectAndHandleAudioAttachmentDeletion(currentAttributedString: attributedString)

            // 记录保存请求（性能监控）
            PerformanceMonitor.shared.recordSaveRequest()

            // MARK: - Paper-Inspired Integration (Task 19.2)

            // 1. 使用 TypingOptimizer 判断更新策略
            let selectedRange = textView.selectedRange()
            let isSimpleTyping = typingOptimizer.isSimpleTyping(
                change: "", // 简化：不传递具体变化内容
                at: selectedRange.location,
                in: textStorage
            )

            if isSimpleTyping {
                // 简单输入场景：只更新打字属性，不进行完整解析
                // 注意：这里仍然需要同步内容，但可以跳过段落重新解析
            } else {

                // 2. 使用 ParagraphManager 更新段落列表
                // 计算变化范围（简化：使用整个文档范围）
                let changedRange = NSRange(location: 0, length: textStorage.length)
                paragraphManager.updateParagraphs(in: textStorage, changedRange: changedRange)

                // 3. 使用 AttributeManager 更新属性
                // 获取受影响的段落
                let affectedParagraphs = paragraphManager.paragraphs(in: changedRange)
                for paragraph in affectedParagraphs where paragraph.needsReparse {
                    attributeManager.applyLayeredAttributes(for: paragraph, in: textStorage)
                }
            }

            // 优化：延迟 50ms 再检查输入法状态，确保组合输入真正完成
            // 这样可以避免在用户选择候选词的瞬间触发保存
            // 50ms 的延迟对用户来说几乎无感知，但足以让输入法完成候选词选择
            Task { @MainActor in
                // 短暂延迟，等待输入法状态稳定
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

                // 再次检查输入法状态
                // 如果用户仍在输入（例如连续输入多个拼音），则跳过此次更新
                if textView.hasMarkedText() {
                    // 记录跳过保存（输入法状态）
                    PerformanceMonitor.shared.recordSkippedSaveInputMethod()
                    self.isUpdatingFromTextView = false
                    return
                }

                // 记录实际保存（性能监控）
                PerformanceMonitor.shared.recordActualSave()

                self.parent.editorContext.updateNSContentAsync(attributedString)
                // 调用回调
                contentChangeCallback?(attributedString)
                self.isUpdatingFromTextView = false
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard let textStorage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()
            let selectionChangeCallback = parent.onSelectionChange

            // 直接从 textStorage 获取内容（保留所有属性）
            let currentAttributedString = NSAttributedString(attributedString: textStorage)

            if isUpdatingFromSwiftUI {
                // updateNSView 期间的 selection change 是程序化的，完全跳过
                return
            }

            // 将 @Published 属性修改延迟到下一个 run loop，
            // 避免在 SwiftUI 视图更新周期（包括 updateNSView 后的布局阶段）内触发 Publishing 警告
            let editorContext = parent.editorContext
            let wasFocused = editorContext.isEditorFocused
            DispatchQueue.main.async {
                editorContext.nsAttributedText = currentAttributedString
                editorContext.updateSelectedRange(selectedRange)
                if !wasFocused {
                    editorContext.setEditorFocused(true)
                }
            }

            // MARK: - Paper-Inspired Integration (Task 19.4)

            // 1. 使用 SelectionAnchorManager 管理锚点
            // 检查是否是选择开始（从无选择到有选择）
            if selectedRange.length > 0, selectionAnchorManager.anchorLocation == nil {
                // 设置锚点为选择的起始位置
                selectionAnchorManager.setAnchor(at: selectedRange.location)
            } else if selectedRange.length == 0 {
                // 清除锚点（无选择）
                selectionAnchorManager.clearAnchor()
            }

            // 使用 CursorFormatManager 处理选择变化
            CursorFormatManager.shared.handleSelectionChange(selectedRange)

            // 使用 AttachmentSelectionManager 处理附件选择
            AttachmentSelectionManager.shared.handleSelectionChange(selectedRange)

            // 异步调用回调，避免在视图更新中触发其他视图更新
            Task { @MainActor in
                selectionChangeCallback?(selectedRange)
            }
        }

        func textView(_ textView: NSTextView, clickedOn cell: NSTextAttachmentCellProtocol, in _: NSRect, at charIndex: Int) {
            // 处理附件点击
            if let attachment = cell.attachment as? InteractiveCheckboxAttachment {
                // 切换复选框状态
                attachment.isChecked.toggle()

                // 刷新显示
                textView.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: charIndex, length: 1))

                // 通知内容变化
                textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            }
        }

        // MARK: - Format Application

        /// 当前格式应用方式（临时存储）
        private var currentApplicationMethod: FormatApplicationMethod?

        /// 应用格式（带应用方式标识）
        /// - Parameters:
        ///   - method: 应用方式
        ///   - format: 格式类型
        func applyFormatWithMethod(_ method: FormatApplicationMethod, format: TextFormat) {
            // 临时存储应用方式，供 applyFormat 使用
            currentApplicationMethod = method
            applyFormat(format)
            currentApplicationMethod = nil
        }

        /// 应用格式到选中文本
        func applyFormat(_ format: TextFormat) {
            // 开始性能测量
            let performanceOptimizer = FormatApplicationPerformanceOptimizer.shared
            let errorHandler = FormatErrorHandler.shared
            let consistencyChecker = FormatApplicationConsistencyChecker.shared

            // 1. 预检查 - 验证编辑器状态
            guard let textView else {
                let context = FormatErrorContext(
                    operation: "applyFormat",
                    format: format.displayName,
                    selectedRange: nil,
                    textLength: nil,
                    cursorPosition: nil,
                    additionalInfo: nil
                )
                errorHandler.handleError(.textViewUnavailable, context: context)
                return
            }

            guard let textStorage = textView.textStorage else {
                let context = FormatErrorContext(
                    operation: "applyFormat",
                    format: format.displayName,
                    selectedRange: nil,
                    textLength: nil,
                    cursorPosition: nil,
                    additionalInfo: nil
                )
                errorHandler.handleError(.textStorageUnavailable, context: context)
                return
            }

            let selectedRange = textView.selectedRange()
            let textLength = textStorage.length

            // 记录应用前的格式状态
            let beforeState = parent.editorContext.currentFormats

            // 开始性能测量
            let measurementContext = performanceOptimizer.beginMeasurement(
                format: format,
                selectedRange: selectedRange
            )

            // 2. 处理空选择范围的情况
            // 对于内联格式，如果没有选中文本，则不应用格式
            // 对于块级格式，即使没有选中文本也可以应用到当前行
            if selectedRange.length == 0, format.isInlineFormat {
                performanceOptimizer.endMeasurement(measurementContext, success: false, errorMessage: "内联格式需要选中文本")
                let context = FormatErrorContext(
                    operation: "applyFormat",
                    format: format.displayName,
                    selectedRange: selectedRange,
                    textLength: textLength,
                    cursorPosition: selectedRange.location,
                    additionalInfo: nil
                )
                errorHandler.handleError(.emptySelectionForInlineFormat(format: format.displayName), context: context)
                return
            }

            // 3. 验证范围有效性
            let effectiveRange: NSRange
            if selectedRange.length > 0 {
                effectiveRange = selectedRange
            } else {
                // 块级格式：使用当前行的范围
                let lineRange = (textStorage.string as NSString).lineRange(for: selectedRange)
                effectiveRange = lineRange
            }

            guard effectiveRange.location + effectiveRange.length <= textLength else {
                performanceOptimizer.endMeasurement(measurementContext, success: false, errorMessage: "选择范围超出文本长度")
                errorHandler.handleRangeError(range: effectiveRange, textLength: textLength)
                return
            }

            // MARK: - Paper-Inspired Integration (Task 19.3)

            // 4. 应用格式
            do {
                // 检查是否为段落级格式
                if format.category == .blockTitle || format.category == .blockList || format.category == .blockQuote {
                    // 使用 ParagraphManager 应用段落格式

                    // 将 TextFormat 转换为 ParagraphType
                    let paragraphType = convertTextFormatToParagraphType(format)
                    paragraphManager.applyParagraphFormat(paragraphType, to: effectiveRange, in: textStorage)
                } else {
                    // 内联格式：使用原有逻辑
                    try applyFormatSafely(format, to: effectiveRange, in: textStorage)
                }

                // 5. 更新编辑器上下文状态
                updateContextAfterFormatApplication(format)

                // 6. 通知内容变化
                textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

                // 7. 记录成功日志和性能数据
                performanceOptimizer.endMeasurement(measurementContext, success: true)

                // 8. 记录一致性检查数据
                let afterState = parent.editorContext.currentFormats
                // 优先使用显式设置的方式，否则从 editorContext 获取
                let applicationMethod = currentApplicationMethod ?? parent.editorContext.currentApplicationMethod
                consistencyChecker.recordFormatApplication(
                    method: applicationMethod,
                    format: format,
                    selectedRange: selectedRange,
                    textLength: textLength,
                    beforeState: beforeState,
                    afterState: afterState,
                    success: true
                )

                // 9. 重置错误计数（成功后重置）
                errorHandler.resetErrorCount()
            } catch {
                // 9. 错误处理
                performanceOptimizer.endMeasurement(measurementContext, success: false, errorMessage: error.localizedDescription)

                // 记录一致性检查数据（失败情况）
                let afterState = parent.editorContext.currentFormats
                // 优先使用显式设置的方式，否则从 editorContext 获取
                let applicationMethod = currentApplicationMethod ?? parent.editorContext.currentApplicationMethod
                consistencyChecker.recordFormatApplication(
                    method: applicationMethod,
                    format: format,
                    selectedRange: selectedRange,
                    textLength: textLength,
                    beforeState: beforeState,
                    afterState: afterState,
                    success: false,
                    errorMessage: error.localizedDescription
                )

                // 记录错误并尝试恢复
                let result = errorHandler.handleFormatApplicationError(
                    format: format,
                    range: effectiveRange,
                    textLength: textLength,
                    underlyingError: error
                )

                // 根据恢复操作执行相应处理
                handleFormatErrorRecovery(result, format: format)

                // 触发状态重新同步
                parent.editorContext.updateCurrentFormats()
            }
        }

        /// 将 TextFormat 转换为 ParagraphType
        /// - Parameter format: 文本格式
        /// - Returns: 段落类型
        private func convertTextFormatToParagraphType(_ format: TextFormat) -> ParagraphType {
            switch format {
            case .heading1:
                .heading(level: 1)
            case .heading2:
                .heading(level: 2)
            case .heading3:
                .heading(level: 3)
            case .bulletList:
                .list(.bullet)
            case .numberedList:
                .list(.ordered)
            case .checkbox:
                .list(.checkbox)
            case .quote:
                .quote
            default:
                .normal
            }
        }

        /// 处理格式错误恢复
        /// - Parameters:
        ///   - result: 错误处理结果
        ///   - format: 格式类型
        private func handleFormatErrorRecovery(_ result: FormatErrorHandlingResult, format _: TextFormat) {
            switch result.recoveryAction {
            case .retryWithFallback:
                break

            case .forceStateUpdate:
                // 强制更新状态
                parent.editorContext.forceUpdateFormats()

            case .refreshEditor:
                // 刷新编辑器
                NotificationCenter.default.post(name: .nativeEditorNeedsRefresh, object: nil)

            default:
                // 其他情况不做额外处理
                break
            }
        }

        /// 安全地应用格式（带错误处理）
        /// - Parameters:
        ///   - format: 格式类型
        ///   - range: 应用范围
        ///   - textStorage: 文本存储
        /// - Throws: 格式应用错误
        private func applyFormatSafely(_ format: TextFormat, to range: NSRange, in textStorage: NSTextStorage) throws {
            // 开始编辑
            textStorage.beginEditing()

            defer {
                // 确保无论如何都结束编辑
                textStorage.endEditing()
            }

            // 特殊处理：列表格式使用 ListFormatHandler
            if format == .bulletList || format == .numberedList {

                if format == .bulletList {
                    // 使用 ListFormatHandler 切换无序列表
                    ListFormatHandler.toggleBulletList(to: textStorage, range: range)
                } else if format == .numberedList {
                    // 使用 ListFormatHandler 切换有序列表
                    ListFormatHandler.toggleOrderedList(to: textStorage, range: range)
                }

                return
            }

            // 使用 UnifiedFormatManager 统一处理其他格式应用
            if UnifiedFormatManager.shared.isRegistered {
                // 根据格式类型调用对应的处理器
                switch format.category {
                case .inline:
                    // 内联格式：使用 InlineFormatHandler
                    InlineFormatHandler.apply(format, to: range, in: textStorage, toggle: true)

                case .blockTitle, .blockList, .blockQuote:
                    // 块级格式：使用 BlockFormatHandler
                    BlockFormatHandler.apply(format, to: range, in: textStorage, toggle: true)

                case .alignment:
                    // 对齐格式：使用 BlockFormatHandler
                    BlockFormatHandler.apply(format, to: range, in: textStorage, toggle: true)
                }

            } else {
                // 回退到旧的处理逻辑（兼容性）
                // 注意：applyFontTrait 和 toggleAttribute 逻辑已整合到 UnifiedFormatManager
                // 直接使用 InlineFormatHandler 和 BlockFormatHandler
                switch format.category {
                case .inline:
                    InlineFormatHandler.apply(format, to: range, in: textStorage, toggle: true)

                case .blockTitle, .blockList, .blockQuote:
                    // 块级格式：使用 BlockFormatHandler
                    BlockFormatHandler.apply(format, to: range, in: textStorage, toggle: true)

                case .alignment:
                    // 对齐格式：使用 BlockFormatHandler
                    BlockFormatHandler.apply(format, to: range, in: textStorage, toggle: true)
                }

            }
        }

        /// 更新编辑器上下文状态
        /// - Parameter format: 应用的格式
        private func updateContextAfterFormatApplication(_: TextFormat) {
            // 延迟更新状态，避免在视图更新中修改 @Published 属性
            parent.editorContext.updateCurrentFormatsAsync()
        }

        // MARK: - 块级格式辅助方法（保留用于特殊情况）

        // 注意：这些方法已被 BlockFormatHandler 替代，保留用于向后兼容
        // 未来版本可以考虑移除这些方法

        /// 应用标题样式
        /// - Note: 已被 BlockFormatHandler.apply 替代
        @available(*, deprecated, message: "使用 BlockFormatHandler.apply 替代")
        private func applyHeadingStyle(
            size: CGFloat,
            weight: NSFont.Weight,
            to range: NSRange,
            in textStorage: NSTextStorage,
            level _: HeadingLevel = .none
        ) {
            let font = NSFont.systemFont(ofSize: size, weight: weight)

            // 获取当前行的范围
            let lineRange = (textStorage.string as NSString).lineRange(for: range)

            textStorage.addAttribute(.font, value: font, range: lineRange)
            // 不再设置 headingLevel 属性，标题格式完全通过字体大小来标识
        }

        /// 应用对齐方式
        /// - Note: 已被 BlockFormatHandler.apply 替代
        @available(*, deprecated, message: "使用 BlockFormatHandler.apply 替代")
        private func applyAlignment(_ alignment: NSTextAlignment, to range: NSRange, in textStorage: NSTextStorage) {
            // 获取当前行的范围
            let lineRange = (textStorage.string as NSString).lineRange(for: range)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment

            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        }

        /// 应用无序列表格式
        /// - Note: 已被 BlockFormatHandler.apply 替代
        @available(*, deprecated, message: "使用 BlockFormatHandler.apply 替代")
        private func applyBulletList(to range: NSRange, in textStorage: NSTextStorage) {
            let lineRange = (textStorage.string as NSString).lineRange(for: range)
            let currentListType = FormatManager.shared.getListType(in: textStorage, at: range.location)

            if currentListType == .bullet {
                // 已经是无序列表，移除格式
                FormatManager.shared.removeListFormat(from: textStorage, range: lineRange)
            } else {
                // 应用无序列表格式
                FormatManager.shared.applyBulletList(to: textStorage, range: lineRange)

                // 在行首插入项目符号（如果还没有）
                let lineText = (textStorage.string as NSString).substring(with: lineRange)
                if !lineText.hasPrefix("• ") {
                    let bulletString = NSAttributedString(string: "• ", attributes: [
                        .font: FontSizeManager.shared.defaultFont,
                        .listType: ListType.bullet,
                        .listIndent: 1,
                    ])
                    textStorage.insert(bulletString, at: lineRange.location)
                }
            }
        }

        /// 应用有序列表格式
        /// - Note: 已被 BlockFormatHandler.apply 替代
        @available(*, deprecated, message: "使用 BlockFormatHandler.apply 替代")
        private func applyOrderedList(to range: NSRange, in textStorage: NSTextStorage) {
            let lineRange = (textStorage.string as NSString).lineRange(for: range)
            let currentListType = FormatManager.shared.getListType(in: textStorage, at: range.location)

            if currentListType == .ordered {
                // 已经是有序列表，移除格式
                FormatManager.shared.removeListFormat(from: textStorage, range: lineRange)
            } else {
                // 计算编号
                let number = FormatManager.shared.getListNumber(in: textStorage, at: range.location)

                // 应用有序列表格式
                FormatManager.shared.applyOrderedList(to: textStorage, range: lineRange, number: number)

                // 在行首插入编号（如果还没有）
                let lineText = (textStorage.string as NSString).substring(with: lineRange)
                let pattern = "^\\d+\\. "
                if lineText.range(of: pattern, options: .regularExpression) == nil {
                    let orderString = NSAttributedString(string: "\(number). ", attributes: [
                        .font: FontSizeManager.shared.defaultFont,
                        .listType: ListType.ordered,
                        .listIndent: 1,
                        .listNumber: number,
                    ])
                    textStorage.insert(orderString, at: lineRange.location)
                }
            }
        }

        /// 应用复选框列表格式
        /// - Note: 已被 BlockFormatHandler.apply 替代
        @available(*, deprecated, message: "使用 BlockFormatHandler.apply 替代")
        private func applyCheckboxList(to range: NSRange, in textStorage: NSTextStorage) {
            let lineRange = (textStorage.string as NSString).lineRange(for: range)
            let currentListType = FormatManager.shared.getListType(in: textStorage, at: range.location)

            if currentListType == .checkbox {
                // 已经是复选框列表，移除格式
                FormatManager.shared.removeListFormat(from: textStorage, range: lineRange)

                // 移除复选框符号
                let lineText = (textStorage.string as NSString).substring(with: lineRange)
                if lineText.hasPrefix("☐ ") || lineText.hasPrefix("☑ ") {
                    textStorage.deleteCharacters(in: NSRange(location: lineRange.location, length: 2))
                }
            } else {
                // 如果是其他列表类型，先移除
                if currentListType != .none {
                    FormatManager.shared.removeListFormat(from: textStorage, range: lineRange)
                }

                // 应用复选框列表格式
                let indent = FormatManager.shared.getListIndent(in: textStorage, at: range.location)
                FormatManager.shared.applyCheckboxList(to: textStorage, range: lineRange, indent: indent)

                // 在行首插入复选框（如果还没有）
                let lineText = (textStorage.string as NSString).substring(with: lineRange)
                if !lineText.hasPrefix("☐ "), !lineText.hasPrefix("☑ ") {
                    // 使用 InteractiveCheckboxAttachment 创建复选框
                    let renderer = CustomRenderer.shared
                    let attachment = renderer.createCheckboxAttachment(checked: false, level: 3, indent: indent)
                    let attachmentString = NSAttributedString(attachment: attachment)

                    // 注意：不再添加空格，附件本身已有足够的间距
                    textStorage.insert(attachmentString, at: lineRange.location)
                }
            }
        }

        /// 应用引用块格式
        /// - Note: 已被 BlockFormatHandler.apply 替代
        @available(*, deprecated, message: "使用 BlockFormatHandler.apply 替代")
        private func applyQuoteBlock(to range: NSRange, in textStorage: NSTextStorage) {
            let lineRange = (textStorage.string as NSString).lineRange(for: range)
            let isQuote = FormatManager.shared.isQuoteBlock(in: textStorage, at: range.location)

            if isQuote {
                // 已经是引用块，移除格式
                FormatManager.shared.removeQuoteBlock(from: textStorage, range: lineRange)
            } else {
                // 应用引用块格式
                FormatManager.shared.applyQuoteBlock(to: textStorage, range: lineRange)
            }
        }

        // MARK: - Special Element Insertion

        /// 插入特殊元素
        func insertSpecialElement(_ element: SpecialElement) {
            guard let textView,
                  let textStorage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()
            let insertionPoint = selectedRange.location

            textStorage.beginEditing()

            switch element {
            case let .checkbox(checked, level):
                insertCheckbox(checked: checked, level: level, at: insertionPoint, in: textStorage)
            case .horizontalRule:
                insertHorizontalRule(at: insertionPoint, in: textStorage)
            case let .bulletPoint(indent):
                insertBulletPoint(indent: indent, at: insertionPoint, in: textStorage)
            case let .numberedItem(number, indent):
                insertNumberedItem(number: number, indent: indent, at: insertionPoint, in: textStorage)
            case let .quote(content):
                insertQuote(content: content, at: insertionPoint, in: textStorage)
            case let .image(fileId, src):
                insertImage(fileId: fileId, src: src, at: insertionPoint, in: textStorage)
            case let .audio(fileId, digest, mimeType):
                insertAudio(fileId: fileId, digest: digest, mimeType: mimeType, at: insertionPoint, in: textStorage)
            }

            textStorage.endEditing()

            // 通知内容变化
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        }

        // MARK: - Indent Operations

        /// 应用缩进操作
        func applyIndentOperation(_ operation: IndentOperation) {
            guard let textView,
                  let textStorage = textView.textStorage
            else {
                return
            }

            let selectedRange = textView.selectedRange()

            textStorage.beginEditing()

            let formatManager = FormatManager.shared

            switch operation {
            case .increase:
                formatManager.increaseIndent(to: textStorage, range: selectedRange)
            case .decrease:
                formatManager.decreaseIndent(to: textStorage, range: selectedRange)
            }

            textStorage.endEditing()

            // 更新缩进级别状态
            let newIndentLevel = formatManager.getCurrentIndentLevel(in: textStorage, at: selectedRange.location)
            parent.editorContext.currentIndentLevel = newIndentLevel

            // 通知内容变化
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        }

        /// 插入复选框
        ///
        /// 使用 ListFormatHandler.toggleCheckboxList 实现复选框列表的切换
        /// 这确保了：
        /// 1. 如果当前行已经是复选框列表，则移除格式
        /// 2. 如果当前行是其他列表类型，则转换为复选框列表
        /// 3. 如果当前行不是列表，则应用复选框列表格式
        ///
        private func insertCheckbox(checked _: Bool, level _: Int, at location: Int, in textStorage: NSTextStorage) {
            // 使用 ListFormatHandler.toggleCheckboxList 实现复选框列表切换
            // 这会正确处理：
            // 1. 在行首插入 InteractiveCheckboxAttachment
            // 2. 设置列表类型属性
            // 3. 处理标题格式互斥
            // 4. 处理其他列表类型的转换
            let range = NSRange(location: location, length: 0)
            ListFormatHandler.toggleCheckboxList(to: textStorage, range: range)
        }

        /// 插入分割线
        private func insertHorizontalRule(at location: Int, in textStorage: NSTextStorage) {
            let renderer = CustomRenderer.shared
            let attachment = renderer.createHorizontalRuleAttachment()
            let attachmentString = NSAttributedString(attachment: attachment)

            let result = NSMutableAttributedString(string: "\n")
            result.append(attachmentString)
            result.append(NSAttributedString(string: "\n"))

            textStorage.insert(result, at: location)
        }

        /// 插入项目符号
        private func insertBulletPoint(indent: Int, at location: Int, in textStorage: NSTextStorage) {
            let renderer = CustomRenderer.shared
            let attachment = renderer.createBulletAttachment(indent: indent)
            let attachmentString = NSAttributedString(attachment: attachment)

            let result = NSMutableAttributedString(attributedString: attachmentString)

            textStorage.insert(result, at: location)
        }

        /// 插入编号列表项
        private func insertNumberedItem(number: Int, indent: Int, at location: Int, in textStorage: NSTextStorage) {
            let renderer = CustomRenderer.shared
            let attachment = renderer.createOrderAttachment(number: number, indent: indent)
            let attachmentString = NSAttributedString(attachment: attachment)

            let result = NSMutableAttributedString(attributedString: attachmentString)

            textStorage.insert(result, at: location)
        }

        /// 插入引用块
        private func insertQuote(content: String, at location: Int, in textStorage: NSTextStorage) {
            let renderer = CustomRenderer.shared
            let quoteString = renderer.createQuoteAttributedString(content: content.isEmpty ? " " : content, indent: 1)

            let result = NSMutableAttributedString(string: "\n")
            result.append(quoteString)
            result.append(NSAttributedString(string: "\n"))

            textStorage.insert(result, at: location)
        }

        /// 插入图片
        private func insertImage(fileId: String?, src: String?, at location: Int, in textStorage: NSTextStorage) {
            // 创建图片附件
            let attachment: ImageAttachment

            if let src {
                // 从 URL 创建（延迟加载）
                attachment = CustomRenderer.shared.createImageAttachment(
                    src: src,
                    fileId: fileId,
                    folderId: parent.editorContext.currentFolderId
                )
            } else if let fileId, let folderId = parent.editorContext.currentFolderId {
                // 从本地存储加载
                if let image = ImageStorageManager.shared.loadImage(fileId: fileId, folderId: folderId) {
                    attachment = CustomRenderer.shared.createImageAttachment(
                        image: image,
                        fileId: fileId,
                        folderId: folderId
                    )
                } else {
                    // 创建占位符附件
                    attachment = ImageAttachment(src: "minote://\(fileId)", fileId: fileId, folderId: folderId)
                }
            } else {
                // 无法创建图片，插入占位符文本
                let placeholder = NSAttributedString(string: "[图片]")
                textStorage.insert(placeholder, at: location)
                return
            }

            let attachmentString = NSAttributedString(attachment: attachment)

            // 构建插入内容：换行 + 图片 + 换行
            let result = NSMutableAttributedString()

            // 如果不在行首，先添加换行
            if location > 0 {
                let string = textStorage.string as NSString
                let prevChar = string.character(at: location - 1)
                if prevChar != 10 { // 10 是换行符的 ASCII 码
                    result.append(NSAttributedString(string: "\n"))
                }
            }

            result.append(attachmentString)
            result.append(NSAttributedString(string: "\n"))

            textStorage.insert(result, at: location)
        }

        /// 插入语音录音
        /// - Parameters:
        ///   - fileId: 语音文件 ID
        ///   - digest: 文件摘要（可选）
        ///   - mimeType: MIME 类型（可选）
        ///   - location: 插入位置
        ///   - textStorage: 文本存储
        private func insertAudio(fileId: String, digest: String?, mimeType: String?, at location: Int, in textStorage: NSTextStorage) {

            // 创建音频附件
            let attachment = AudioAttachment(fileId: fileId, digest: digest, mimeType: mimeType)
            let attachmentString = NSAttributedString(attachment: attachment)

            // 构建插入内容：换行 + 音频 + 换行
            let result = NSMutableAttributedString()

            // 如果不在行首，先添加换行
            if location > 0 {
                let string = textStorage.string as NSString
                let prevChar = string.character(at: location - 1)
                if prevChar != 10 { // 10 是换行符的 ASCII 码
                    result.append(NSAttributedString(string: "\n"))
                }
            }

            result.append(attachmentString)
            result.append(NSAttributedString(string: "\n"))

            textStorage.insert(result, at: location)

            // 刷新布局以确保附件正确显示
            if let layoutManager = textView?.layoutManager {
                let insertedRange = NSRange(location: location, length: result.length)
                layoutManager.invalidateLayout(forCharacterRange: insertedRange, actualCharacterRange: nil)
                layoutManager.invalidateDisplay(forCharacterRange: insertedRange)
            }

            // 将光标移动到插入内容之后
            let newCursorPosition = location + result.length
            textView?.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

        }
    }
}

// MARK: - NativeTextView

/// 自定义 NSTextView 子类，支持额外的交互功能
/// 扩展了光标位置限制功能，确保光标不能移动到列表标记区域内
class NativeTextView: NSTextView {

    /// 复选框点击回调
    var onCheckboxClick: ((InteractiveCheckboxAttachment, Int) -> Void)?

    /// 列表状态管理器
    private var listStateManager = ListStateManager()

    /// 是否启用列表光标限制
    /// 默认启用，可以在需要时临时禁用
    var enableListCursorRestriction = true

    /// 是否正在内部调整选择范围（防止递归）
    private var isAdjustingSelection = false

    // MARK: - Cursor Position Restriction

    /// 重写 setSelectedRange 方法，限制光标位置
    /// 确保光标不能移动到列表标记区域内
    override func setSelectedRange(_ charRange: NSRange) {

        // 先调用父类方法
        super.setSelectedRange(charRange)

        // 通知附件选择管理器（仅在非递归调用时）
        if !isAdjustingSelection {
            AttachmentSelectionManager.shared.handleSelectionChange(charRange)
        } else {}

        // 如果禁用限制、没有 textStorage 或有选择范围，不进行列表光标限制
        guard enableListCursorRestriction,
              let textStorage,
              charRange.length == 0,
              !isAdjustingSelection
        else {
            return
        }

        // 调整光标位置，确保不在列表标记区域内
        let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
            in: textStorage,
            from: charRange.location
        )

        let adjustedRange = NSRange(location: adjustedPosition, length: 0)
        if adjustedRange.location != charRange.location {
            isAdjustingSelection = true
            super.setSelectedRange(adjustedRange)
            // 通知附件选择管理器调整后的位置
            AttachmentSelectionManager.shared.handleSelectionChange(adjustedRange)
            isAdjustingSelection = false
        }
    }

    /// 重写 moveLeft 方法，处理左移光标到上一行
    /// 当光标在列表项（包括 checkbox）内容起始位置时，左移应跳到上一行末尾
    override func moveLeft(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveLeft(sender)
            return
        }

        let currentRange = selectedRange()
        let currentPosition = currentRange.location

        // 检查当前位置是否在列表项内容起始位置（包括 checkbox）
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: currentPosition) {
            if currentPosition == listInfo.contentStartPosition {
                // 光标在内容起始位置，跳到上一行末尾
                if listInfo.lineRange.location > 0 {
                    let prevLineEnd = listInfo.lineRange.location - 1
                    setSelectedRange(NSRange(location: prevLineEnd, length: 0))
                    return
                }
            }
        }

        // 执行默认左移
        super.moveLeft(sender)

        // 检查移动后的位置是否在列表标记区域内（包括 checkbox）
        let newPosition = selectedRange().location
        if ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: newPosition) {
            // 调整到内容起始位置
            let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: newPosition)
            super.setSelectedRange(NSRange(location: adjustedPosition, length: 0))
        }
    }

    /// 重写 moveToBeginningOfLine 方法，移动到内容起始位置
    /// 对于列表项（包括 checkbox），移动到内容区域起始位置而非行首
    override func moveToBeginningOfLine(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveToBeginningOfLine(sender)
            return
        }

        let currentPosition = selectedRange().location

        // 检查当前行是否是列表项（包括 checkbox）
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: currentPosition) {
            // 移动到内容起始位置
            setSelectedRange(NSRange(location: listInfo.contentStartPosition, length: 0))
            return
        }

        // 非列表行，使用默认行为
        super.moveToBeginningOfLine(sender)
    }

    /// 重写 moveWordLeft 方法，处理 Option+左方向键
    /// 确保不会移动到列表标记区域内（包括 checkbox）
    override func moveWordLeft(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveWordLeft(sender)
            return
        }

        let currentPosition = selectedRange().location

        // 检查当前位置是否在列表项内容起始位置（包括 checkbox）
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: currentPosition) {
            if currentPosition == listInfo.contentStartPosition {
                // 光标在内容起始位置，跳到上一行末尾
                if listInfo.lineRange.location > 0 {
                    let prevLineEnd = listInfo.lineRange.location - 1
                    setSelectedRange(NSRange(location: prevLineEnd, length: 0))
                    return
                }
            }
        }

        // 执行默认单词左移
        super.moveWordLeft(sender)

        // 检查移动后的位置是否在列表标记区域内（包括 checkbox）
        let newPosition = selectedRange().location
        if ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: newPosition) {
            // 调整到内容起始位置
            let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: newPosition)
            super.setSelectedRange(NSRange(location: adjustedPosition, length: 0))
        }
    }

    // MARK: - Selection Restriction

    /// 重写 moveLeftAndModifySelection 方法，处理 Shift+左方向键选择
    /// 当选择起点在列表项内容起始位置时，向左扩展选择应跳到上一行而非选中列表标记
    override func moveLeftAndModifySelection(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveLeftAndModifySelection(sender)
            return
        }

        let currentRange = selectedRange()
        let selectionStart = currentRange.location
        let selectionEnd = currentRange.location + currentRange.length

        // 检查选择的起始位置是否在列表项内容起始位置
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: selectionStart) {
            if selectionStart == listInfo.contentStartPosition {
                // 选择起点在内容起始位置，扩展选择到上一行末尾
                if listInfo.lineRange.location > 0 {
                    let prevLineEnd = listInfo.lineRange.location - 1
                    // 计算新的选择范围：从上一行末尾到当前选择末尾
                    let newLength = selectionEnd - prevLineEnd
                    super.setSelectedRange(NSRange(location: prevLineEnd, length: newLength))
                    return
                }
            }
        }

        // 执行默认选择扩展
        super.moveLeftAndModifySelection(sender)

        // 检查选择后的起始位置是否在列表标记区域内
        let newRange = selectedRange()
        let newStart = newRange.location

        if ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: newStart) {
            // 调整选择起始位置到内容起始位置
            let adjustedStart = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: newStart)
            let adjustedLength = newRange.length - (adjustedStart - newStart)
            if adjustedLength >= 0 {
                super.setSelectedRange(NSRange(location: adjustedStart, length: adjustedLength))
            }
        }
    }

    /// 重写 moveToBeginningOfLineAndModifySelection 方法，处理 Cmd+Shift+左方向键选择
    /// 对于列表项，选择到内容区域起始位置而非行首
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveToBeginningOfLineAndModifySelection(sender)
            return
        }

        let currentRange = selectedRange()
        let selectionEnd = currentRange.location + currentRange.length

        // 检查当前行是否是列表项
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: selectionEnd) {
            // 选择到内容起始位置
            let contentStart = listInfo.contentStartPosition
            let newLength = selectionEnd - contentStart
            if newLength >= 0 {
                super.setSelectedRange(NSRange(location: contentStart, length: newLength))
                return
            }
        }

        // 非列表行，使用默认行为
        super.moveToBeginningOfLineAndModifySelection(sender)
    }

    /// 重写 moveWordLeftAndModifySelection 方法，处理 Option+Shift+左方向键选择
    /// 确保选择不会包含列表标记
    override func moveWordLeftAndModifySelection(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveWordLeftAndModifySelection(sender)
            return
        }

        let currentRange = selectedRange()
        let selectionStart = currentRange.location
        let selectionEnd = currentRange.location + currentRange.length

        // 检查选择的起始位置是否在列表项内容起始位置
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: selectionStart) {
            if selectionStart == listInfo.contentStartPosition {
                // 选择起点在内容起始位置，扩展选择到上一行末尾
                if listInfo.lineRange.location > 0 {
                    let prevLineEnd = listInfo.lineRange.location - 1
                    let newLength = selectionEnd - prevLineEnd
                    super.setSelectedRange(NSRange(location: prevLineEnd, length: newLength))
                    return
                }
            }
        }

        // 执行默认单词选择扩展
        super.moveWordLeftAndModifySelection(sender)

        // 检查选择后的起始位置是否在列表标记区域内
        let newRange = selectedRange()
        let newStart = newRange.location

        if ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: newStart) {
            // 调整选择起始位置到内容起始位置
            let adjustedStart = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: newStart)
            let adjustedLength = newRange.length - (adjustedStart - newStart)
            if adjustedLength >= 0 {
                super.setSelectedRange(NSRange(location: adjustedStart, length: adjustedLength))
            }
        }
    }

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

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        // 先尝试让附件键盘处理器处理
        if AttachmentKeyboardHandler.shared.handleKeyDown(event, in: self) {
            return
        }

        // 向上方向键：光标在第一行开头时，焦点转移到标题 TextField
        if event.keyCode == 126 { // Up arrow
            let cursorLocation = selectedRange().location
            if cursorLocation == 0 {
                if let scrollView = enclosingScrollView,
                   let stackView = scrollView.documentView as? FlippedStackView,
                   let titleField = stackView.arrangedSubviews.first as? TitleTextField
                {
                    window?.makeFirstResponder(titleField)
                    // 将光标移到标题末尾
                    titleField.currentEditor()?.selectedRange = NSRange(location: titleField.stringValue.count, length: 0)
                    return
                }
            }
        }

        // 处理快捷键
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "b":
                // Cmd+B: 加粗
                NotificationCenter.default.post(name: .nativeEditorFormatCommand, object: TextFormat.bold)
                return
            case "i":
                // Cmd+I: 斜体
                NotificationCenter.default.post(name: .nativeEditorFormatCommand, object: TextFormat.italic)
                return
            case "u":
                // Cmd+U: 下划线
                NotificationCenter.default.post(name: .nativeEditorFormatCommand, object: TextFormat.underline)
                return
            default:
                break
            }

            // Cmd+Shift+- : 插入分割线
            if event.modifierFlags.contains(.shift), event.charactersIgnoringModifiers == "-" {
                insertHorizontalRuleAtCursor()
                return
            }

            // Cmd+Shift+U : 切换当前行勾选框状态
            if event.modifierFlags.contains(.shift), event.charactersIgnoringModifiers?.lowercased() == "u" {
                if toggleCurrentLineCheckboxState() {
                    return
                }
            }
        }

        // 处理回车键 - 使用 UnifiedFormatManager 统一处理换行逻辑
        if event.keyCode == 36 { // Return key
            // 关键修复：检查输入法组合状态
            // 如果用户正在使用输入法（如中文输入法输入英文），按回车应该只是确认输入，不换行
            // hasMarkedText() 返回 true 表示输入法正在组合中（如拼音未选择候选词）
            if hasMarkedText() {
                // 调用父类方法，让系统处理输入法的确认操作
                super.keyDown(with: event)
                return
            }

            // 首先尝试使用 UnifiedFormatManager 处理换行
            // 如果 UnifiedFormatManager 已注册且处理了换行，则不执行默认行为
            if UnifiedFormatManager.shared.isRegistered {
                if UnifiedFormatManager.shared.handleNewLine() {
                    // 通知内容变化
                    delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
                    return
                }
            }

            // 回退到旧的处理逻辑（兼容性）
            // 注意：高亮清除逻辑已整合到 UnifiedFormatManager

            if handleReturnKeyForList() {
                return
            }
        }

        // 处理 Tab 键 - 列表缩进
        if event.keyCode == 48 { // Tab key
            if handleTabKeyForList(increase: !event.modifierFlags.contains(.shift)) {
                return
            }
        }

        // 处理删除键 - 删除分割线
        if event.keyCode == 51 { // Delete key (Backspace)
            // 尝试删除分割线
            if deleteSelectedHorizontalRule() {
                return
            }

            // 然后尝试处理列表项合并
            if handleBackspaceKeyForList() {
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - List Handling

    /// 处理回车键创建新列表项
    /// 使用 ListBehaviorHandler 统一处理列表回车行为
    /// - Returns: 是否处理了回车键
    private func handleReturnKeyForList() -> Bool {
        guard let textStorage else { return false }

        let selectedRange = selectedRange()
        let position = selectedRange.location

        // 首先检查是否在引用块中
        if FormatManager.shared.isQuoteBlock(in: textStorage, at: position) {
            return handleReturnKeyForQuote()
        }

        // 使用 ListBehaviorHandler 处理列表回车
        if ListBehaviorHandler.handleEnterKey(textView: self) {
            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        // 检查当前行是否是列表项（回退逻辑）
        let listType = FormatManager.shared.getListType(in: textStorage, at: position)
        guard listType != .none else { return false }

        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: selectedRange)
        let lineText = string.substring(with: lineRange).trimmingCharacters(in: .newlines)

        // 检查当前行是否为空（只有列表符号）
        let isEmptyListItem = isListItemEmpty(lineText: lineText, listType: listType)

        if isEmptyListItem {
            // 空列表项，移除列表格式
            textStorage.beginEditing()
            FormatManager.shared.removeListFormat(from: textStorage, range: lineRange)
            textStorage.endEditing()

            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        // 非空列表项，创建新的列表项
        let indent = FormatManager.shared.getListIndent(in: textStorage, at: position)

        textStorage.beginEditing()

        // 插入换行符
        let insertionPoint = selectedRange.location
        textStorage.replaceCharacters(in: selectedRange, with: "\n")

        // 在新行应用列表格式
        let newLineStart = insertionPoint + 1
        let newLineRange = NSRange(location: newLineStart, length: 0)

        switch listType {
        case .bullet:
            FormatManager.shared.applyBulletList(to: textStorage, range: newLineRange, indent: indent)
            // 插入项目符号
            let bulletString = createBulletString(indent: indent)
            textStorage.insert(bulletString, at: newLineStart)

        case .ordered:
            let newNumber = FormatManager.shared.getListNumber(in: textStorage, at: position) + 1
            FormatManager.shared.applyOrderedList(to: textStorage, range: newLineRange, number: newNumber, indent: indent)
            // 插入编号
            let orderString = createOrderString(number: newNumber, indent: indent)
            textStorage.insert(orderString, at: newLineStart)

        case .checkbox:
            // 复选框列表处理
            let checkboxString = createCheckboxString(indent: indent)
            textStorage.insert(checkboxString, at: newLineStart)

        case .none:
            break
        }

        textStorage.endEditing()

        // 移动光标到新行
        let newCursorPosition = newLineStart + getListPrefixLength(listType: listType)
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))

        // 通知内容变化
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

        return true
    }

    /// 处理 Tab 键调整列表缩进
    /// - Parameter increase: 是否增加缩进
    /// - Returns: 是否处理了 Tab 键
    private func handleTabKeyForList(increase: Bool) -> Bool {
        guard let textStorage else { return false }

        let selectedRange = selectedRange()
        let position = selectedRange.location

        // 检查当前行是否是列表项
        let listType = FormatManager.shared.getListType(in: textStorage, at: position)
        guard listType != .none else { return false }

        if increase {
            FormatManager.shared.increaseListIndent(to: textStorage, range: selectedRange)
        } else {
            FormatManager.shared.decreaseListIndent(to: textStorage, range: selectedRange)
        }

        // 通知内容变化
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

        return true
    }

    /// 处理引用块中的回车键
    /// - Returns: 是否处理了回车键
    private func handleReturnKeyForQuote() -> Bool {
        guard let textStorage else { return false }

        let selectedRange = selectedRange()
        let position = selectedRange.location

        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: selectedRange)
        let lineText = string.substring(with: lineRange).trimmingCharacters(in: .newlines)

        // 检查当前行是否为空（只有空白字符）
        let isEmptyLine = lineText.trimmingCharacters(in: .whitespaces).isEmpty

        if isEmptyLine {
            // 空行，退出引用块
            textStorage.beginEditing()
            FormatManager.shared.removeQuoteBlock(from: textStorage, range: lineRange)
            textStorage.endEditing()

            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        // 非空行，继续引用格式
        let indent = FormatManager.shared.getQuoteIndent(in: textStorage, at: position)

        textStorage.beginEditing()

        // 插入换行符
        let insertionPoint = selectedRange.location
        textStorage.replaceCharacters(in: selectedRange, with: "\n")

        // 在新行应用引用块格式
        let newLineStart = insertionPoint + 1
        let newLineRange = NSRange(location: newLineStart, length: 0)

        FormatManager.shared.applyQuoteBlock(to: textStorage, range: newLineRange, indent: indent)

        textStorage.endEditing()

        // 移动光标到新行
        setSelectedRange(NSRange(location: newLineStart, length: 0))

        // 通知内容变化
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

        return true
    }

    /// 处理删除键（Backspace）合并列表项
    /// 当光标在列表项内容起始位置时，将当前行内容合并到上一行
    /// - Returns: 是否处理了删除键
    private func handleBackspaceKeyForList() -> Bool {
        guard let textStorage else { return false }

        // 使用 ListBehaviorHandler 处理删除键
        if ListBehaviorHandler.handleBackspaceKey(textView: self) {
            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        return false
    }

    /// 切换当前行勾选框状态
    /// 使用快捷键 Cmd+Shift+U 切换当前行的勾选框状态
    /// - Returns: 是否成功切换
    private func toggleCurrentLineCheckboxState() -> Bool {
        guard let textStorage else { return false }

        let position = selectedRange().location

        // 检查当前行是否是勾选框列表
        let listType = ListFormatHandler.detectListType(in: textStorage, at: position)
        guard listType == .checkbox else {
            return false
        }

        // 使用 ListBehaviorHandler 切换勾选框状态
        if ListBehaviorHandler.toggleCheckboxState(textView: self, at: position) {
            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        return false
    }

    /// 检查列表项是否为空
    private func isListItemEmpty(lineText: String, listType: ListType) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)

        switch listType {
        case .bullet:
            // 检查是否只有项目符号
            return trimmed == "•" || trimmed.isEmpty
        case .ordered:
            // 检查是否只有编号
            let pattern = "^\\d+\\.$"
            return trimmed.range(of: pattern, options: .regularExpression) != nil || trimmed.isEmpty
        case .checkbox:
            // 检查是否只有复选框（包括附件字符）
            // 附件字符是 Unicode 对象替换字符 \u{FFFC}
            let withoutAttachment = trimmed.replacingOccurrences(of: "\u{FFFC}", with: "")
            return withoutAttachment.isEmpty || trimmed == "☐" || trimmed == "☑"
        case .none:
            return trimmed.isEmpty
        }
    }

    /// 创建项目符号字符串
    private func createBulletString(indent: Int) -> NSAttributedString {
        let bullet = "• "
        var attributes: [NSAttributedString.Key: Any] = [
            .font: FontSizeManager.shared.defaultFont,
            .listType: ListType.bullet,
            .listIndent: indent,
        ]

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = CGFloat(indent - 1) * 20
        paragraphStyle.headIndent = CGFloat(indent - 1) * 20 + 24
        attributes[.paragraphStyle] = paragraphStyle

        return NSAttributedString(string: bullet, attributes: attributes)
    }

    /// 创建有序列表编号字符串
    private func createOrderString(number: Int, indent: Int) -> NSAttributedString {
        let orderText = "\(number). "
        var attributes: [NSAttributedString.Key: Any] = [
            .font: FontSizeManager.shared.defaultFont,
            .listType: ListType.ordered,
            .listIndent: indent,
            .listNumber: number,
        ]

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = CGFloat(indent - 1) * 20
        paragraphStyle.headIndent = CGFloat(indent - 1) * 20 + 28
        attributes[.paragraphStyle] = paragraphStyle

        return NSAttributedString(string: orderText, attributes: attributes)
    }

    /// 创建复选框字符串
    private func createCheckboxString(indent: Int) -> NSAttributedString {
        // 使用 InteractiveCheckboxAttachment 创建可交互的复选框
        let renderer = CustomRenderer.shared
        let attachment = renderer.createCheckboxAttachment(checked: false, level: 3, indent: indent)
        let attachmentString = NSMutableAttributedString(attachment: attachment)

        // 注意：不再添加空格，附件本身已有足够的间距
        // 设置列表类型属性
        let fullRange = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttributes([
            .font: FontSizeManager.shared.defaultFont,
            .listType: ListType.checkbox,
            .listIndent: indent,
        ], range: fullRange)

        return attachmentString
    }

    /// 获取列表前缀长度
    private func getListPrefixLength(listType: ListType) -> Int {
        switch listType {
        case .bullet:
            2 // "• "
        case .ordered:
            3 // "1. " (假设单位数编号)
        case .checkbox:
            2 // 附件字符 + 空格
        case .none:
            0
        }
    }

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
        guard let saveResult = ImageStorageManager.shared.saveImage(image, folderId: folderId) else {
            return
        }

        let fileId = saveResult.fileId

        // 创建图片附件
        let attachment = CustomRenderer.shared.createImageAttachment(
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

    // MARK: - Horizontal Rule Support

    /// 在光标位置插入分割线
    func insertHorizontalRuleAtCursor() {
        guard let textStorage else { return }

        let selectedRange = selectedRange()
        let insertionPoint = selectedRange.location

        textStorage.beginEditing()

        // 创建分割线附件
        let renderer = CustomRenderer.shared
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
            if let attachment = textStorage.attribute(.attachment, at: selectedRange.location, effectiveRange: nil) as? HorizontalRuleAttachment {
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

// MARK: - Notification Names

extension Notification.Name {
    static let nativeEditorFormatCommand = Notification.Name("nativeEditorFormatCommand")
    static let nativeEditorRequestContentSync = Notification.Name("nativeEditorRequestContentSync")
    // nativeEditorNeedsRefresh 已在 NativeEditorErrorHandler.swift 中定义
}

// MARK: - ListStateManager

/// 列表状态管理器 - 跟踪和管理列表的连续性和编号
class ListStateManager {

    /// 有序列表编号缓存
    private var orderedListNumbers: [Int: Int] = [:] // [lineIndex: number]

    /// 重置状态
    func reset() {
        orderedListNumbers.removeAll()
    }

    /// 获取指定行的有序列表编号
    /// - Parameters:
    ///   - lineIndex: 行索引
    ///   - textStorage: 文本存储
    /// - Returns: 列表编号
    func getOrderedListNumber(for lineIndex: Int, in textStorage: NSTextStorage) -> Int {
        if let cached = orderedListNumbers[lineIndex] {
            return cached
        }

        // 计算编号
        let number = calculateOrderedListNumber(for: lineIndex, in: textStorage)
        orderedListNumbers[lineIndex] = number
        return number
    }

    /// 计算有序列表编号
    private func calculateOrderedListNumber(for lineIndex: Int, in _: NSTextStorage) -> Int {
        // 简化实现：从 1 开始
        lineIndex + 1
    }

    /// 更新编号（当列表发生变化时）
    func updateNumbers(from lineIndex: Int, in _: NSTextStorage) {
        // 清除从指定行开始的所有缓存
        orderedListNumbers = orderedListNumbers.filter { $0.key < lineIndex }
    }
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
