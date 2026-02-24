//
//  NativeEditorCoordinator.swift
//  MiNoteMac
//
//  原生编辑器 Coordinator - 负责 NSTextView 代理、内容同步、事件监听
//  从 NativeEditorView.swift 提取，保持为 NativeEditorView.Coordinator 类型
//

import AppKit
import Combine
import SwiftUI

// MARK: - NativeEditorView.Coordinator

extension NativeEditorView {

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
        private var performanceCache: PerformanceCache? {
            parent.editorContext.performanceCache
        }

        /// 打字优化器 - 检测简单输入场景并优化更新策略
        private var typingOptimizer: TypingOptimizer? {
            parent.editorContext.typingOptimizer
        }

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

        /// 处理撤销操作
        private func handleUndoOperation() {
            let formatsBefore = parent.editorContext.currentFormats

            // 同步内容并延迟更新格式状态
            syncContentToContext()
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

            // 同步内容并延迟更新格式状态
            syncContentToContext()
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
        func syncContentToContext() {
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
                parent.editorContext.audioPanelStateManager?.handleAudioAttachmentDeleted(fileId: fileId)
            }

            // 更新记录的音频附件集合
            previousAudioFileIds = currentAudioFileIds
        }

        // MARK: - NSTextFieldDelegate

        func controlTextDidChange(_ notification: Notification) {
            guard let titleField = notification.object as? TitleTextField else { return }
            guard !isUpdatingTitleProgrammatically else { return }

            isUpdatingTitleProgrammatically = true
            let newTitle = titleField.stringValue
            parent.editorContext.titleText = newTitle
            parent.editorContext.hasUnsavedChanges = true
            parent.editorContext.notifyTitleChange(newTitle)
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
            parent.editorContext.performanceMonitor?.recordInputMethodDetection()

            if textView.hasMarkedText() {
                parent.editorContext.performanceMonitor?.recordSkippedSaveInputMethod()
                return
            }

            isUpdatingFromTextView = true

            let attributedString = NSAttributedString(attributedString: textStorage)
            let contentChangeCallback = parent.onContentChange

            detectAndHandleAudioAttachmentDeletion(currentAttributedString: attributedString)

            parent.editorContext.performanceMonitor?.recordSaveRequest()

            // MARK: - Paper-Inspired Integration (Task 19.2)

            // 1. 使用 TypingOptimizer 判断更新策略
            let selectedRange = textView.selectedRange()
            let isSimpleTyping = typingOptimizer?.isSimpleTyping(
                change: "",
                at: selectedRange.location,
                in: textStorage
            ) ?? false

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
                    parent.editorContext.performanceMonitor?.recordSkippedSaveInputMethod()
                    self.isUpdatingFromTextView = false
                    return
                }

                parent.editorContext.performanceMonitor?.recordActualSave()

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
            editorContext.cursorFormatManager?.handleSelectionChange(selectedRange)

            // 使用 AttachmentSelectionManager 处理附件选择
            editorContext.attachmentSelectionManager?.handleSelectionChange(selectedRange)

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

        /// 格式应用方式（供 CoordinatorFormatApplier 使用）
        var currentApplicationMethod: FormatApplicationMethod?

        /// 段落管理器访问（供 CoordinatorFormatApplier 使用）
        var formatParagraphManager: ParagraphManager {
            paragraphManager
        }
    }
}
