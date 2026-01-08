//
//  NativeEditorView.swift
//  MiNoteMac
//
//  原生编辑器视图 - 基于 NSTextView 的富文本编辑器
//  需求: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8
//

import SwiftUI
import AppKit
import Combine

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
    var isEditable: Bool = true
    
    /// 是否显示行号
    var showLineNumbers: Bool = false
    
    // MARK: - NSViewRepresentable
    
    func makeNSView(context: Context) -> NSScrollView {
        // 测量初始化时间
        let startTime = CFAbsoluteTimeGetCurrent()
        let scrollView = createScrollView(context: context)
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        
        // 检查是否超过阈值
        if duration > 100 {
            print("[NativeEditorView] 警告: 初始化时间超过 100ms (\(String(format: "%.2f", duration))ms)")
        } else {
            print("[NativeEditorView] 初始化完成，耗时: \(String(format: "%.2f", duration))ms")
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
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = .labelColor  // 使用 labelColor 自动适配深色模式
        
        // 设置内边距
        textView.textContainerInset = NSSize(width: 16, height: 16)
        
        // 设置自动调整大小
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        // 配置滚动视图
        scrollView.documentView = textView
        
        // 保存引用
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        
        // 加载初始内容
        if !editorContext.nsAttributedText.string.isEmpty {
            textView.textStorage?.setAttributedString(editorContext.nsAttributedText)
        }
        
        // 预热渲染器缓存
        CustomRenderer.shared.warmUpCache()
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NativeTextView else { return }
        
        // 更新可编辑状态
        textView.isEditable = isEditable
        
        // 确保文字颜色适配当前外观（深色/浅色模式）
        textView.textColor = .labelColor
        
        // 检查内容是否需要更新（避免循环更新）
        if !context.coordinator.isUpdatingFromTextView {
            let currentText = textView.attributedString()
            let newText = editorContext.nsAttributedText
            
            // 使用字符串内容比较，而不是 NSAttributedString 的完整比较
            // 因为属性可能不同但内容相同
            let contentChanged = currentText.string != newText.string
            let lengthChanged = currentText.length != newText.length
            
            if contentChanged || lengthChanged {
                print("[NativeEditorView] 更新内容 - 当前长度: \(currentText.length), 新长度: \(newText.length)")
                
                // 保存当前选择范围
                let selectedRange = textView.selectedRange()
                
                // 更新内容
                textView.textStorage?.setAttributedString(newText)
                
                // 恢复选择范围（如果有效）
                if selectedRange.location <= textView.string.count {
                    let newRange = NSRange(
                        location: min(selectedRange.location, textView.string.count),
                        length: min(selectedRange.length, max(0, textView.string.count - selectedRange.location))
                    )
                    textView.setSelectedRange(newRange)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    
    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditorView
        weak var textView: NativeTextView?
        weak var scrollView: NSScrollView?
        var isUpdatingFromTextView = false
        private var cancellables = Set<AnyCancellable>()
        
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
            
            // 监听内容同步请求
            NotificationCenter.default.publisher(for: .nativeEditorRequestContentSync)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self = self,
                          let context = notification.object as? NativeEditorContext,
                          context === self.parent.editorContext else { return }
                    
                    self.syncContentToContext()
                }
                .store(in: &cancellables)
            
            // 需求 5.1, 5.2, 5.3: 监听快捷键格式命令
            // 当用户使用 Cmd+B/I/U 快捷键时，确保格式菜单状态同步更新
            NotificationCenter.default.publisher(for: .nativeEditorFormatCommand)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self = self,
                          let format = notification.object as? TextFormat else { return }
                    
                    print("[NativeEditorView] 收到快捷键格式命令: \(format.displayName)")
                    self.handleKeyboardShortcutFormat(format)
                }
                .store(in: &cancellables)
            
            // 需求 5.5: 监听撤销/重做操作
            // 当用户撤销或重做格式操作时，确保格式菜单状态正确更新
            NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self = self else { return }
                    print("[NativeEditorView] 检测到撤销操作")
                    self.handleUndoRedoOperation()
                }
                .store(in: &cancellables)
            
            NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self = self else { return }
                    print("[NativeEditorView] 检测到重做操作")
                    self.handleUndoRedoOperation()
                }
                .store(in: &cancellables)
        }
        
        // MARK: - 快捷键格式处理 (需求 5.1, 5.2, 5.3, 5.4)
        
        /// 处理快捷键格式命令
        /// - Parameter format: 格式类型
        /// 需求: 5.1, 5.2, 5.3 - 确保快捷键操作后菜单状态更新
        /// 需求: 5.4 - 确保格式应用方式一致性
        private func handleKeyboardShortcutFormat(_ format: TextFormat) {
            print("[NativeEditorView] handleKeyboardShortcutFormat: \(format.displayName)")
            
            // 1. 应用格式（与菜单应用使用相同的方法，确保一致性）
            applyFormatWithMethod(.keyboard, format: format)
            
            // 2. 同步内容到上下文
            syncContentToContext()
            
            // 3. 强制更新格式状态，确保菜单状态同步
            Task { @MainActor in
                // 延迟一小段时间确保格式应用完成
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                self.parent.editorContext.forceUpdateFormats()
                print("[NativeEditorView] 快捷键格式应用完成，状态已更新")
            }
        }
        
        // MARK: - 撤销/重做处理 (需求 5.5)
        
        /// 处理撤销/重做操作
        /// 需求: 5.5 - 确保撤销后状态正确更新
        private func handleUndoRedoOperation() {
            print("[NativeEditorView] handleUndoRedoOperation")
            
            // 1. 同步内容到上下文
            syncContentToContext()
            
            // 2. 强制更新格式状态
            Task { @MainActor in
                // 延迟一小段时间确保撤销/重做操作完成
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                self.parent.editorContext.forceUpdateFormats()
                print("[NativeEditorView] 撤销/重做操作后状态已更新")
            }
        }
        
        /// 同步 textView 内容到 editorContext
        private func syncContentToContext() {
            guard let textView = textView else {
                print("[NativeEditorView] syncContentToContext: textView 为 nil")
                return
            }
            
            guard let textStorage = textView.textStorage else {
                print("[NativeEditorView] syncContentToContext: textStorage 为 nil")
                return
            }
            
            // 直接从 textStorage 获取内容（而不是 attributedString()）
            let attributedString = NSAttributedString(attributedString: textStorage)
            let selectedRange = textView.selectedRange()
            
            print("[NativeEditorView] syncContentToContext: 同步内容")
            print("[NativeEditorView]   - textStorage.length: \(textStorage.length)")
            print("[NativeEditorView]   - 选择范围: \(selectedRange)")
            
            // 打印位置 16 处的属性（用于调试）
            if selectedRange.location < textStorage.length {
                let attrs = textStorage.attributes(at: selectedRange.location, effectiveRange: nil)
                print("[NativeEditorView]   - 位置 \(selectedRange.location) 的属性数量: \(attrs.count)")
                for (key, value) in attrs {
                    print("[NativeEditorView]     - \(key): \(value)")
                }
                
                // 检查字体
                if let font = attrs[.font] as? NSFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    print("[NativeEditorView]     - 字体: \(font.fontName), 大小: \(font.pointSize)")
                    print("[NativeEditorView]     - 是否粗体: \(traits.contains(.bold))")
                    print("[NativeEditorView]     - 是否斜体: \(traits.contains(.italic))")
                }
            }
            
            Task { @MainActor in
                // 关键修复：直接更新 nsAttributedText，不做字符串比较
                // 因为字符串可能相同但属性不同
                self.parent.editorContext.nsAttributedText = attributedString
                print("[NativeEditorView] syncContentToContext: nsAttributedText 已更新 (长度: \(attributedString.length))")
                
                // 更新选择范围
                self.parent.editorContext.updateSelectedRange(selectedRange)
                
                // 强制更新格式状态
                self.parent.editorContext.updateCurrentFormats()
            }
        }
        
        // MARK: - NSTextViewDelegate
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            isUpdatingFromTextView = true
            
            // 更新编辑器上下文 - 使用 Task 延迟执行，避免在视图更新中修改 @Published 属性
            let attributedString = textView.attributedString()
            let contentChangeCallback = parent.onContentChange
            
            Task { @MainActor in
                self.parent.editorContext.updateNSContent(attributedString)
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
            
            // 使用 Task 延迟执行，避免在视图更新中修改 @Published 属性
            Task { @MainActor in
                // 关键修复：始终同步 nsAttributedText，确保属性正确
                // 不做字符串比较，因为字符串可能相同但属性不同
                self.parent.editorContext.nsAttributedText = currentAttributedString
                
                self.parent.editorContext.updateSelectedRange(selectedRange)
                // 调用回调
                selectionChangeCallback?(selectedRange)
            }
        }
        
        func textView(_ textView: NSTextView, clickedOn cell: NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int) {
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
        /// 需求: 5.4 - 确保格式应用方式一致性
        func applyFormatWithMethod(_ method: FormatApplicationMethod, format: TextFormat) {
            // 临时存储应用方式，供 applyFormat 使用
            currentApplicationMethod = method
            applyFormat(format)
            currentApplicationMethod = nil
        }
        
        /// 应用格式到选中文本
        /// 需求: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8
        /// 性能需求: 3.1 - 确保50ms内开始格式应用
        /// 错误处理需求: 4.1 - 格式应用失败时记录错误日志并保持界面状态一致
        /// 一致性需求: 5.4 - 记录格式应用操作以进行一致性检查
        func applyFormat(_ format: TextFormat) {
            // 开始性能测量 - 需求 3.1
            let performanceOptimizer = FormatApplicationPerformanceOptimizer.shared
            let errorHandler = FormatErrorHandler.shared
            let consistencyChecker = FormatApplicationConsistencyChecker.shared
            
            // 1. 预检查 - 验证编辑器状态
            guard let textView = textView else {
                print("[FormatApplicator] ❌ 错误: textView 为 nil")
                // 需求 4.1: 记录错误日志
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
                print("[FormatApplicator] ❌ 错误: textStorage 为 nil")
                // 需求 4.1: 记录错误日志
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
            
            // 记录应用前的格式状态 - 需求 5.4
            let beforeState = parent.editorContext.currentFormats
            
            // 开始性能测量
            let measurementContext = performanceOptimizer.beginMeasurement(
                format: format,
                selectedRange: selectedRange
            )
            
            print("[FormatApplicator] 开始应用格式: \(format.displayName)")
            print("[FormatApplicator] 选择范围: location=\(selectedRange.location), length=\(selectedRange.length)")
            
            // 2. 处理空选择范围的情况
            // 对于内联格式，如果没有选中文本，则不应用格式
            // 对于块级格式，即使没有选中文本也可以应用到当前行
            if selectedRange.length == 0 && format.isInlineFormat {
                print("[FormatApplicator] ⚠️ 警告: 内联格式需要选中文本，当前未选中任何文本")
                performanceOptimizer.endMeasurement(measurementContext, success: false, errorMessage: "内联格式需要选中文本")
                // 需求 4.1: 记录错误日志
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
                print("[FormatApplicator] ❌ 错误: 选择范围超出文本长度 (range: \(effectiveRange), textLength: \(textLength))")
                performanceOptimizer.endMeasurement(measurementContext, success: false, errorMessage: "选择范围超出文本长度")
                // 需求 4.1: 记录错误日志
                errorHandler.handleRangeError(range: effectiveRange, textLength: textLength)
                return
            }
            
            print("[FormatApplicator] 有效范围: location=\(effectiveRange.location), length=\(effectiveRange.length)")
            
            // 4. 应用格式
            do {
                try applyFormatSafely(format, to: effectiveRange, in: textStorage)
                
                // 5. 更新编辑器上下文状态
                updateContextAfterFormatApplication(format)
                
                // 6. 通知内容变化
                textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
                
                // 7. 记录成功日志和性能数据
                print("[FormatApplicator] ✅ 成功应用格式: \(format.displayName)")
                performanceOptimizer.endMeasurement(measurementContext, success: true)
                
                // 8. 记录一致性检查数据 - 需求 5.4
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
                // 9. 错误处理 - 需求 4.1
                print("[FormatApplicator] ❌ 格式应用失败: \(error)")
                performanceOptimizer.endMeasurement(measurementContext, success: false, errorMessage: error.localizedDescription)
                
                // 记录一致性检查数据（失败情况）- 需求 5.4
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
        
        /// 处理格式错误恢复
        /// - Parameters:
        ///   - result: 错误处理结果
        ///   - format: 格式类型
        /// 需求: 4.1
        private func handleFormatErrorRecovery(_ result: FormatErrorHandlingResult, format: TextFormat) {
            switch result.recoveryAction {
            case .retryWithFallback:
                // 尝试使用回退方案
                print("[FormatApplicator] 尝试使用回退方案重新应用格式: \(format.displayName)")
                // 这里可以实现回退逻辑，例如使用更简单的格式应用方式
                
            case .forceStateUpdate:
                // 强制更新状态
                print("[FormatApplicator] 强制更新格式状态")
                parent.editorContext.forceUpdateFormats()
                
            case .refreshEditor:
                // 刷新编辑器
                print("[FormatApplicator] 刷新编辑器")
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
            
            // 根据格式类型应用相应的格式
            switch format {
            case .bold:
                applyFontTrait(.bold, to: range, in: textStorage)
            case .italic:
                applyFontTrait(.italic, to: range, in: textStorage)
            case .underline:
                toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range, in: textStorage)
            case .strikethrough:
                toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range, in: textStorage)
            case .highlight:
                let highlightColor = NSColor(hex: "#9affe8af") ?? NSColor.systemYellow
                toggleAttribute(.backgroundColor, value: highlightColor, range: range, in: textStorage)
            case .heading1:
                applyHeadingStyle(size: 24, weight: .bold, to: range, in: textStorage, level: .h1)
            case .heading2:
                applyHeadingStyle(size: 20, weight: .semibold, to: range, in: textStorage, level: .h2)
            case .heading3:
                applyHeadingStyle(size: 16, weight: .medium, to: range, in: textStorage, level: .h3)
            case .alignCenter:
                applyAlignment(.center, to: range, in: textStorage)
            case .alignRight:
                applyAlignment(.right, to: range, in: textStorage)
            case .bulletList:
                applyBulletList(to: range, in: textStorage)
            case .numberedList:
                applyOrderedList(to: range, in: textStorage)
            case .checkbox:
                applyCheckboxList(to: range, in: textStorage)
            case .quote:
                applyQuoteBlock(to: range, in: textStorage)
            case .horizontalRule:
                // 分割线是特殊元素，不是格式
                print("[FormatApplicator] ⚠️ 警告: 分割线应该通过 insertSpecialElement 插入，而不是 applyFormat")
            }
        }
        
        /// 更新编辑器上下文状态
        /// - Parameter format: 应用的格式
        private func updateContextAfterFormatApplication(_ format: TextFormat) {
            // 延迟更新状态，避免在视图更新中修改 @Published 属性
            Task { @MainActor in
                self.parent.editorContext.updateCurrentFormats()
            }
        }

        
        /// 应用字体特性
        /// 需求: 1.1, 1.2
        /// - Parameters:
        ///   - trait: 字体特性
        ///   - range: 应用范围
        ///   - textStorage: 文本存储
        private func applyFontTrait(_ trait: NSFontDescriptor.SymbolicTraits, to range: NSRange, in textStorage: NSTextStorage) {
            print("[FormatApplicator] 应用字体特性: \(trait), range: \(range)")
            
            let fontManager = NSFontManager.shared
            
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                guard let font = value as? NSFont else {
                    print("[FormatApplicator] ⚠️ 警告: 在范围 \(attrRange) 没有找到字体，使用默认字体")
                    // 使用默认字体
                    let defaultFont = NSFont.systemFont(ofSize: 15)
                    textStorage.addAttribute(.font, value: defaultFont, range: attrRange)
                    return
                }
                
                let currentTraits = font.fontDescriptor.symbolicTraits
                let hasTrait = currentTraits.contains(trait)
                
                print("[FormatApplicator] 当前字体: \(font.fontName), 大小: \(font.pointSize), 已有特性: \(hasTrait)")
                
                var newFont: NSFont?
                
                // 使用 NSFontManager 来正确处理字体特性转换
                if trait == .italic {
                    if hasTrait {
                        // 移除斜体
                        newFont = fontManager.convert(font, toNotHaveTrait: .italicFontMask)
                        print("[FormatApplicator] 移除斜体特性")
                    } else {
                        // 添加斜体
                        newFont = fontManager.convert(font, toHaveTrait: .italicFontMask)
                        print("[FormatApplicator] 添加斜体特性")
                    }
                } else if trait == .bold {
                    if hasTrait {
                        // 移除粗体
                        newFont = fontManager.convert(font, toNotHaveTrait: .boldFontMask)
                        print("[FormatApplicator] 移除粗体特性")
                    } else {
                        // 添加粗体
                        newFont = fontManager.convert(font, toHaveTrait: .boldFontMask)
                        print("[FormatApplicator] 添加粗体特性")
                    }
                } else {
                    // 其他特性使用原来的方法
                    var newTraits = currentTraits
                    if hasTrait {
                        newTraits.remove(trait)
                    } else {
                        newTraits.insert(trait)
                    }
                    let newDescriptor = font.fontDescriptor.withSymbolicTraits(newTraits)
                    newFont = NSFont(descriptor: newDescriptor, size: font.pointSize)
                }
                
                // 验证字体转换是否成功
                if let finalFont = newFont {
                    // 验证新字体是否真的具有或不具有目标特性
                    let newTraits = finalFont.fontDescriptor.symbolicTraits
                    let hasNewTrait = newTraits.contains(trait)
                    
                    if hasTrait && hasNewTrait {
                        // 应该移除特性但还在，可能是字体不支持
                        print("[FormatApplicator] ⚠️ 警告: 无法移除字体特性，字体可能不支持")
                        // 尝试使用系统字体
                        let systemFont = NSFont.systemFont(ofSize: font.pointSize)
                        let convertedFont = hasTrait ? 
                            fontManager.convert(systemFont, toNotHaveTrait: trait == .bold ? .boldFontMask : .italicFontMask) :
                            fontManager.convert(systemFont, toHaveTrait: trait == .bold ? .boldFontMask : .italicFontMask)
                        textStorage.addAttribute(.font, value: convertedFont, range: attrRange)
                    } else if !hasTrait && !hasNewTrait {
                        // 应该添加特性但没有，可能是字体不支持
                        print("[FormatApplicator] ⚠️ 警告: 无法添加字体特性，字体可能不支持")
                        // 尝试使用系统字体
                        let systemFont = NSFont.systemFont(ofSize: font.pointSize)
                        let convertedFont = fontManager.convert(systemFont, toHaveTrait: trait == .bold ? .boldFontMask : .italicFontMask)
                        textStorage.addAttribute(.font, value: convertedFont, range: attrRange)
                    } else {
                        // 转换成功
                        textStorage.addAttribute(.font, value: finalFont, range: attrRange)
                        print("[FormatApplicator] ✅ 字体特性应用成功: \(finalFont.fontName)")
                    }
                } else {
                    print("[FormatApplicator] ❌ 错误: 字体转换失败，保持原字体")
                }
            }
        }
        
        /// 切换属性
        /// 需求: 1.3, 1.4, 1.5
        /// - Parameters:
        ///   - key: 属性键
        ///   - value: 属性值
        ///   - range: 应用范围
        ///   - textStorage: 文本存储
        private func toggleAttribute(_ key: NSAttributedString.Key, value: Any, range: NSRange, in textStorage: NSTextStorage) {
            print("[FormatApplicator] 切换属性: \(key), range: \(range)")
            
            var hasAttribute = false
            var attributeRanges: [(NSRange, Any?)] = []
            
            // 检查范围内是否已有该属性
            textStorage.enumerateAttribute(key, in: range, options: []) { existingValue, attrRange, _ in
                attributeRanges.append((attrRange, existingValue))
                if existingValue != nil {
                    hasAttribute = true
                }
            }
            
            print("[FormatApplicator] 属性检查结果: hasAttribute=\(hasAttribute), 范围数量=\(attributeRanges.count)")
            
            if hasAttribute {
                // 移除属性
                print("[FormatApplicator] 移除属性: \(key)")
                textStorage.removeAttribute(key, range: range)
                
                // 验证移除是否成功
                var stillHasAttribute = false
                textStorage.enumerateAttribute(key, in: range, options: []) { existingValue, _, stop in
                    if existingValue != nil {
                        stillHasAttribute = true
                        stop.pointee = true
                    }
                }
                
                if stillHasAttribute {
                    print("[FormatApplicator] ⚠️ 警告: 属性移除后仍然存在")
                } else {
                    print("[FormatApplicator] ✅ 属性移除成功")
                }
            } else {
                // 添加属性
                print("[FormatApplicator] 添加属性: \(key), value: \(value)")
                textStorage.addAttribute(key, value: value, range: range)
                
                // 验证添加是否成功
                var attributeAdded = false
                textStorage.enumerateAttribute(key, in: range, options: []) { existingValue, _, stop in
                    if existingValue != nil {
                        attributeAdded = true
                        stop.pointee = true
                    }
                }
                
                if attributeAdded {
                    print("[FormatApplicator] ✅ 属性添加成功")
                } else {
                    print("[FormatApplicator] ⚠️ 警告: 属性添加后未找到")
                }
            }
        }
        
        /// 应用标题样式
        private func applyHeadingStyle(size: CGFloat, weight: NSFont.Weight, to range: NSRange, in textStorage: NSTextStorage, level: HeadingLevel = .none) {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            
            // 获取当前行的范围
            let lineRange = (textStorage.string as NSString).lineRange(for: range)
            
            textStorage.addAttribute(.font, value: font, range: lineRange)
            
            // 设置标题级别属性
            if level != .none {
                textStorage.addAttribute(.headingLevel, value: level.rawValue, range: lineRange)
            }
        }
        
        /// 应用对齐方式
        private func applyAlignment(_ alignment: NSTextAlignment, to range: NSRange, in textStorage: NSTextStorage) {
            // 获取当前行的范围
            let lineRange = (textStorage.string as NSString).lineRange(for: range)
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        }
        
        /// 应用无序列表格式
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
                        .font: NSFont.systemFont(ofSize: 15),
                        .listType: ListType.bullet,
                        .listIndent: 1
                    ])
                    textStorage.insert(bulletString, at: lineRange.location)
                }
            }
        }
        
        /// 应用有序列表格式
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
                        .font: NSFont.systemFont(ofSize: 15),
                        .listType: ListType.ordered,
                        .listIndent: 1,
                        .listNumber: number
                    ])
                    textStorage.insert(orderString, at: lineRange.location)
                }
            }
        }
        
        /// 应用复选框列表格式
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
                if !lineText.hasPrefix("☐ ") && !lineText.hasPrefix("☑ ") {
                    // 使用 InteractiveCheckboxAttachment 创建复选框
                    let renderer = CustomRenderer.shared
                    let attachment = renderer.createCheckboxAttachment(checked: false, level: 3, indent: indent)
                    let attachmentString = NSAttributedString(attachment: attachment)
                    
                    let checkboxString = NSMutableAttributedString(attributedString: attachmentString)
                    checkboxString.append(NSAttributedString(string: " "))
                    
                    textStorage.insert(checkboxString, at: lineRange.location)
                }
            }
        }
        
        /// 应用引用块格式
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
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }
            
            let selectedRange = textView.selectedRange()
            let insertionPoint = selectedRange.location
            
            textStorage.beginEditing()
            
            switch element {
            case .checkbox(let checked, let level):
                insertCheckbox(checked: checked, level: level, at: insertionPoint, in: textStorage)
            case .horizontalRule:
                insertHorizontalRule(at: insertionPoint, in: textStorage)
            case .bulletPoint(let indent):
                insertBulletPoint(indent: indent, at: insertionPoint, in: textStorage)
            case .numberedItem(let number, let indent):
                insertNumberedItem(number: number, indent: indent, at: insertionPoint, in: textStorage)
            case .quote(let content):
                insertQuote(content: content, at: insertionPoint, in: textStorage)
            case .image(let fileId, let src):
                insertImage(fileId: fileId, src: src, at: insertionPoint, in: textStorage)
            }
            
            textStorage.endEditing()
            
            // 通知内容变化
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        }
        
        /// 插入复选框
        private func insertCheckbox(checked: Bool, level: Int, at location: Int, in textStorage: NSTextStorage) {
            let renderer = CustomRenderer.shared
            let attachment = renderer.createCheckboxAttachment(checked: checked, level: level, indent: 1)
            let attachmentString = NSAttributedString(attachment: attachment)
            
            let result = NSMutableAttributedString(attributedString: attachmentString)
            result.append(NSAttributedString(string: " "))
            
            textStorage.insert(result, at: location)
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
            
            if let src = src {
                // 从 URL 创建（延迟加载）
                attachment = CustomRenderer.shared.createImageAttachment(
                    src: src,
                    fileId: fileId,
                    folderId: parent.editorContext.currentFolderId
                )
            } else if let fileId = fileId, let folderId = parent.editorContext.currentFolderId {
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
    }
}

// MARK: - NativeTextView

/// 自定义 NSTextView 子类，支持额外的交互功能
class NativeTextView: NSTextView {
    
    /// 复选框点击回调
    var onCheckboxClick: ((InteractiveCheckboxAttachment, Int) -> Void)?
    
    /// 列表状态管理器
    private var listStateManager = ListStateManager()
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // 检查是否点击了附件
        if let layoutManager = layoutManager,
           let textContainer = textContainer {
            let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            
            if charIndex < textStorage?.length ?? 0 {
                if let attachment = textStorage?.attribute(.attachment, at: charIndex, effectiveRange: nil) as? InteractiveCheckboxAttachment {
                    // 获取附件的边界
                    let glyphRange = NSRange(location: glyphIndex, length: 1)
                    let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    
                    // 检查点击是否在附件区域内
                    let adjustedRect = boundingRect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
                    if adjustedRect.contains(point) {
                        // 切换复选框状态
                        attachment.isChecked.toggle()
                        
                        // 刷新显示
                        layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: charIndex, length: 1))
                        
                        // 触发回调
                        onCheckboxClick?(attachment, charIndex)
                        
                        // 通知代理
                        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
                        
                        return
                    }
                }
            }
        }
        
        super.mouseDown(with: event)
    }
    
    // MARK: - Keyboard Events
    
    override func keyDown(with event: NSEvent) {
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
            if event.modifierFlags.contains(.shift) && event.charactersIgnoringModifiers == "-" {
                insertHorizontalRuleAtCursor()
                return
            }
        }
        
        // 处理回车键 - 列表项创建
        if event.keyCode == 36 { // Return key
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
            if deleteSelectedHorizontalRule() {
                return
            }
        }
        
        super.keyDown(with: event)
    }
    
    // MARK: - List Handling
    
    /// 处理回车键创建新列表项
    /// - Returns: 是否处理了回车键
    private func handleReturnKeyForList() -> Bool {
        guard let textStorage = textStorage else { return false }
        
        let selectedRange = self.selectedRange()
        let position = selectedRange.location
        
        // 首先检查是否在引用块中
        if FormatManager.shared.isQuoteBlock(in: textStorage, at: position) {
            return handleReturnKeyForQuote()
        }
        
        // 检查当前行是否是列表项
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
        guard let textStorage = textStorage else { return false }
        
        let selectedRange = self.selectedRange()
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
        guard let textStorage = textStorage else { return false }
        
        let selectedRange = self.selectedRange()
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
            .font: NSFont.systemFont(ofSize: 15),
            .listType: ListType.bullet,
            .listIndent: indent
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
            .font: NSFont.systemFont(ofSize: 15),
            .listType: ListType.ordered,
            .listIndent: indent,
            .listNumber: number
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
        let attachmentString = NSAttributedString(attachment: attachment)
        
        let result = NSMutableAttributedString(attributedString: attachmentString)
        result.append(NSAttributedString(string: " ", attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .listType: ListType.checkbox,
            .listIndent: indent
        ]))
        
        return result
    }
    
    /// 获取列表前缀长度
    private func getListPrefixLength(listType: ListType) -> Int {
        switch listType {
        case .bullet:
            return 2 // "• "
        case .ordered:
            return 3 // "1. " (假设单位数编号)
        case .checkbox:
            return 2 // 附件字符 + 空格
        case .none:
            return 0
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
        guard let textStorage = textStorage else { return }
        
        // 获取当前文件夹 ID（从编辑器上下文获取）
        // 如果没有文件夹 ID，使用默认值
        let folderId = "default"
        
        // 保存图片到本地存储
        guard let saveResult = ImageStorageManager.shared.saveImage(image, folderId: folderId) else {
            print("[NativeTextView] 保存图片失败")
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
        
        let selectedRange = self.selectedRange()
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
        
        print("[NativeTextView] 图片插入成功: \(fileId)")
    }
    
    // MARK: - Horizontal Rule Support
    
    /// 在光标位置插入分割线
    func insertHorizontalRuleAtCursor() {
        guard let textStorage = textStorage else { return }
        
        let selectedRange = self.selectedRange()
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
        guard let textStorage = textStorage else { return false }
        
        let selectedRange = self.selectedRange()
        
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
    private func calculateOrderedListNumber(for lineIndex: Int, in textStorage: NSTextStorage) -> Int {
        // 简化实现：从 1 开始
        return lineIndex + 1
    }
    
    /// 更新编号（当列表发生变化时）
    func updateNumbers(from lineIndex: Int, in textStorage: NSTextStorage) {
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
