//
//  NativeEditorContext.swift
//  MiNoteMac
//
//  原生编辑器上下文 - 管理编辑器状态、格式应用和用户交互
//

import AppKit
import Combine
import SwiftUI

/// 原生编辑器上下文 - 管理编辑器状态和操作
@MainActor
public class NativeEditorContext: ObservableObject {
    // MARK: - Published Properties

    /// 当前应用的格式集合
    @Published var currentFormats: Set<TextFormat> = []

    /// 光标位置
    @Published var cursorPosition = 0

    /// 选择范围
    @Published public var selectedRange = NSRange(location: 0, length: 0)

    /// 编辑器是否获得焦点
    @Published var isEditorFocused = false

    /// 当前编辑的内容（NSAttributedString 用于与 NSTextView 交互）
    @Published var attributedText = AttributedString()

    /// 当前编辑的 NSAttributedString（用于 NSTextView）
    @Published public var nsAttributedText = NSAttributedString()

    /// 标题文本（独立于正文，由 loadFromXML 提取）
    @Published public var titleText = ""

    /// 当前检测到的特殊元素类型
    @Published var currentSpecialElement: SpecialElement?

    /// 当前缩进级别
    @Published var currentIndentLevel = 1

    /// 当前文件夹 ID（用于图片存储）
    @Published var currentFolderId: String?

    /// 是否有未保存的更改
    @Published var hasUnsavedChanges = false

    /// 工具栏按钮状态
    @Published var toolbarButtonStates: [TextFormat: Bool] = [:]

    /// 内容版本号，用于强制触发视图更新
    ///
    /// 当笔记切换时，SwiftUI 可能无法正确检测 NSAttributedString 的属性变化
    /// 通过递增版本号，可以强制触发 NativeEditorView 的 updateNSView 方法
    ///
    @Published var contentVersion = 0

    // MARK: - 内容保护属性

    /// 保存失败时的备份内容
    ///
    /// 当保存操作失败时，将当前编辑内容备份到此属性
    /// 用于后续重试保存或恢复内容
    ///
    @Published var backupContent: NSAttributedString?

    /// 最后一次保存失败的错误信息
    ///
    @Published var lastSaveError: String?

    /// 是否有待重试的保存操作
    ///
    @Published var hasPendingRetry = false

    /// 部分激活的格式集合（用于混合格式状态显示）
    @Published var partiallyActiveFormats: Set<TextFormat> = []

    /// 格式激活比例（用于混合格式状态显示）
    @Published var formatActivationRatios: [TextFormat: Double] = [:]

    // MARK: - 版本号机制属性

    /// 变化追踪器
    ///
    /// 使用版本号机制追踪内容变化，避免内容比较的性能开销和误判问题
    ///
    let changeTracker = EditorChangeTracker()

    /// 自动保存管理器
    ///
    /// 负责自动保存的调度、防抖和并发控制
    ///
    lazy var autoSaveManager = AutoSaveManager { [weak self] in
        await self?.performAutoSave()
    }

    /// 是否需要保存（基于版本号机制）
    ///
    /// 通过版本号差异判断是否需要保存，避免内容比较的性能开销
    ///
    public var needsSave: Bool {
        changeTracker.needsSave
    }

    // MARK: - Private Properties

    /// 原始 XML 是否以 <new-format/> 开头
    /// 用于在导出 XML 时保持格式标记的一致性
    private var hasNewFormatPrefix = false

    /// 格式变化发布者
    private let formatChangeSubject = PassthroughSubject<TextFormat, Never>()

    /// 特殊元素插入发布者
    private let specialElementSubject = PassthroughSubject<SpecialElement, Never>()

    /// 内容变化发布者
    let contentChangeSubject = PassthroughSubject<NSAttributedString, Never>()

    /// 选择变化发布者
    private let selectionChangeSubject = PassthroughSubject<NSRange, Never>()

    /// 缩进操作发布者
    private let indentChangeSubject = PassthroughSubject<IndentOperation, Never>()

    /// 标题变化发布者（用于绕过 SwiftUI 无法观察计算属性链上 @Published 变化的问题）
    let titleChangeSubject = PassthroughSubject<String, Never>()

    /// 格式转换器
    private let formatConverter = XiaoMiFormatConverter.shared

    /// 自定义渲染器
    let customRenderer = CustomRenderer.shared

    /// 格式状态同步器
    let formatStateSynchronizer = FormatStateSynchronizer.createDefault()

    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 格式提供者

    /// 格式提供者（延迟初始化）
    private var _formatProvider: NativeFormatProvider?

    /// 格式提供者（公开访问）
    public var formatProvider: NativeFormatProvider {
        if _formatProvider == nil {
            _formatProvider = NativeFormatProvider(editorContext: self)
        }
        guard let formatProvider = _formatProvider else {
            fatalError("Format provider not available")
        }
        return formatProvider
    }

    // MARK: - Public Publishers

    /// 格式变化发布者
    var formatChangePublisher: AnyPublisher<TextFormat, Never> {
        formatChangeSubject.eraseToAnyPublisher()
    }

    /// 特殊元素插入发布者
    var specialElementPublisher: AnyPublisher<SpecialElement, Never> {
        specialElementSubject.eraseToAnyPublisher()
    }

    /// 内容变化发布者
    var contentChangePublisher: AnyPublisher<NSAttributedString, Never> {
        contentChangeSubject.eraseToAnyPublisher()
    }

    /// 选择变化发布者
    var selectionChangePublisher: AnyPublisher<NSRange, Never> {
        selectionChangeSubject.eraseToAnyPublisher()
    }

    /// 缩进操作发布者
    var indentChangePublisher: AnyPublisher<IndentOperation, Never> {
        indentChangeSubject.eraseToAnyPublisher()
    }

    /// 标题变化发布者
    var titleChangePublisher: AnyPublisher<String, Never> {
        titleChangeSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init() {
        // 初始化工具栏按钮状态
        for format in TextFormat.allCases {
            toolbarButtonStates[format] = false
        }

        // 设置内部观察者
        setupInternalObservers()

        // 设置格式状态同步器的更新回调
        formatStateSynchronizer.setUpdateCallback { [weak self] in
            self?.updateCurrentFormats()
        }

        // 延迟注册格式提供者到 FormatStateManager
        // 使用 Task 确保在主线程上执行
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 触发 formatProvider 的延迟初始化
            _ = formatProvider
        }
    }

    // MARK: - Public Methods - 格式应用

    /// 当前格式应用方式（用于一致性检查）
    @Published var currentApplicationMethod: FormatApplicationMethod = .programmatic

    /// 应用格式到选中文本
    /// - Parameter format: 要应用的格式
    func applyFormat(_ format: TextFormat) {
        applyFormat(format, method: .programmatic)
    }

    /// 应用格式到选中文本（带应用方式标识）
    /// - Parameters:
    ///   - format: 要应用的格式
    ///   - method: 应用方式
    func applyFormat(_ format: TextFormat, method: FormatApplicationMethod) {
        // 记录应用方式
        currentApplicationMethod = method

        // 使用批量更新机制，减少视图重绘次数
        batchUpdateState {
            // 切换格式状态
            if currentFormats.contains(format) {
                currentFormats.remove(format)
                toolbarButtonStates[format] = false
            } else {
                // 处理互斥格式（内联版本，避免嵌套批量更新）
                handleMutuallyExclusiveFormatsInline(for: format)
                currentFormats.insert(format)
                toolbarButtonStates[format] = true
            }
        }

        // 发布格式变化
        formatChangeSubject.send(format)

        // 使用 CursorFormatManager 处理工具栏格式切换
        CursorFormatManager.shared.handleToolbarFormatToggle(format)

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 使用版本号机制追踪格式变化
        changeTracker.formatDidChange()
        autoSaveManager.scheduleAutoSave()

        // 重置应用方式
        currentApplicationMethod = .programmatic
    }

    /// 设置格式状态（不触发切换）
    /// - Parameters:
    ///   - format: 格式类型
    ///   - active: 是否激活
    func setFormatState(_ format: TextFormat, active: Bool) {
        if active {
            currentFormats.insert(format)
        } else {
            currentFormats.remove(format)
        }
        toolbarButtonStates[format] = active
    }

    /// 清除所有格式
    func clearAllFormats() {
        // 使用批量更新机制，减少视图重绘次数
        batchUpdateState {
            currentFormats.removeAll()
            for format in TextFormat.allCases {
                toolbarButtonStates[format] = false
            }
        }

        // 使用版本号机制追踪格式变化
        changeTracker.formatDidChange()
        autoSaveManager.scheduleAutoSave()
    }

    /// 清除标题格式（将文本恢复为正文样式）
    func clearHeadingFormat() {

        // 使用批量更新机制，减少视图重绘次数
        batchUpdateState {
            // 移除所有标题格式
            currentFormats.remove(.heading1)
            currentFormats.remove(.heading2)
            currentFormats.remove(.heading3)
            toolbarButtonStates[.heading1] = false
            toolbarButtonStates[.heading2] = false
            toolbarButtonStates[.heading3] = false
        }

        // 重置字体大小为正文大小（13pt）
        resetFontSizeToBody()

        // 注意：不要调用 formatChangeSubject.send(.heading1)！
        // 因为这会触发 NativeEditorView.Coordinator 中的 applyFormat(.heading1)
        // 导致大标题格式被错误地应用
        // _修复: heading2/heading3 转正文时错误应用大标题格式_

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 使用版本号机制追踪格式变化
        changeTracker.formatDidChange()
        autoSaveManager.scheduleAutoSave()

        // 强制更新格式状态，确保 UI 同步
        updateCurrentFormats()

    }

    /// 重置字体大小为正文大小
    ///
    /// 将选中文本或当前行的字体大小重置为正文大小，同时保留字体特性（加粗、斜体等）
    /// 用于将标题转换为正文时，确保字体大小正确重置
    ///
    /// - 选择模式：重置选中文本的字体大小
    /// - 光标模式：重置当前行的字体大小
    private func resetFontSizeToBody() {
        // 使用 FontSizeManager 获取正文字体大小
        let bodySize = FontSizeManager.shared.bodySize

        // 确定要处理的范围
        let range: NSRange
        if selectedRange.length > 0 {
            // 选择模式：使用选中范围
            range = selectedRange
        } else {
            // 光标模式：获取当前行的范围
            let string = nsAttributedText.string as NSString
            let lineRange = string.lineRange(for: NSRange(location: cursorPosition, length: 0))
            range = lineRange
        }

        // 检查范围是否有效
        guard range.length > 0 else {
            return
        }

        // 创建可变副本
        let mutableText = nsAttributedText.mutableCopy() as! NSMutableAttributedString

        // 遍历范围，重置字体大小
        mutableText.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            if let font = value as? NSFont {
                // 使用 FontSizeManager 创建新字体，保留字体特性（加粗、斜体）
                let traits = font.fontDescriptor.symbolicTraits
                let newFont = FontSizeManager.shared.createFont(ofSize: bodySize, traits: traits)

                // 应用新字体
                mutableText.addAttribute(.font, value: newFont, range: subRange)
            }
        }

        // 更新编辑器内容
        updateNSContent(mutableText)
    }

    /// 清除对齐格式（恢复默认左对齐）
    func clearAlignmentFormat() {

        // 使用批量更新机制，减少视图重绘次数
        batchUpdateState {
            // 移除居中和居右格式
            currentFormats.remove(.alignCenter)
            currentFormats.remove(.alignRight)
            toolbarButtonStates[.alignCenter] = false
            toolbarButtonStates[.alignRight] = false
        }

        // 注意：不要调用 formatChangeSubject.send(.alignCenter)！
        // 因为这会触发 NativeEditorView.Coordinator 中的 applyFormat(.alignCenter)
        // 导致居中对齐格式被错误地应用
        // _修复: 与 clearHeadingFormat 保持一致_

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 使用版本号机制追踪格式变化
        changeTracker.formatDidChange()
        autoSaveManager.scheduleAutoSave()

        // 强制更新格式状态，确保 UI 同步
        updateCurrentFormats()
    }

    /// 插入特殊元素
    /// - Parameter element: 要插入的特殊元素
    func insertSpecialElement(_ element: SpecialElement) {
        specialElementSubject.send(element)
        hasUnsavedChanges = true

        // 使用版本号机制追踪附件变化
        changeTracker.attachmentDidChange()
        autoSaveManager.scheduleAutoSave()
    }

    /// 插入分割线
    func insertHorizontalRule() {
        insertSpecialElement(.horizontalRule)
    }

    /// 插入复选框
    /// - Parameters:
    ///   - checked: 是否选中（默认为 false）
    ///   - level: 复选框级别（默认为 3）
    func insertCheckbox(checked: Bool = false, level: Int = 3) {
        insertSpecialElement(.checkbox(checked: checked, level: level))
    }

    /// 插入引用块
    /// - Parameter content: 引用内容（默认为空）
    func insertQuote(content: String = "") {
        insertSpecialElement(.quote(content: content))
    }

    /// 插入图片
    /// - Parameters:
    ///   - fileId: 文件 ID（可选）
    ///   - src: 图片源 URL（可选）
    func insertImage(fileId: String? = nil, src: String? = nil) {
        insertSpecialElement(.image(fileId: fileId, src: src))
    }

    /// 插入图片（从 NSImage）
    /// - Parameter image: 要插入的图片
    func insertImage(_ image: NSImage) {
        // 保存图片到本地存储
        let folderId = currentFolderId ?? "default"

        if let saveResult = ImageStorageManager.shared.saveImage(image, folderId: folderId) {
            insertSpecialElement(.image(fileId: saveResult.fileId, src: nil))
        }
    }

    /// 插入语音录音
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    func insertAudio(fileId: String, digest: String? = nil, mimeType: String? = nil) {
        insertSpecialElement(.audio(fileId: fileId, digest: digest, mimeType: mimeType))
    }

    // MARK: - Public Methods - 缩进操作

    /// 增加缩进
    func increaseIndent() {
        indentChangeSubject.send(.increase)
        hasUnsavedChanges = true
    }

    /// 减少缩进
    func decreaseIndent() {
        indentChangeSubject.send(.decrease)
        hasUnsavedChanges = true
    }

    // MARK: - Public Methods - 光标和选择管理

    /// 更新光标位置
    /// - Parameter position: 新的光标位置
    func updateCursorPosition(_ position: Int) {
        cursorPosition = position
        // 使用同步器调度状态更新（防抖）
        formatStateSynchronizer.scheduleStateUpdate()
        detectSpecialElementAtCursor()
    }

    /// 更新选择范围
    /// - Parameter range: 新的选择范围
    func updateSelectedRange(_ range: NSRange) {
        selectedRange = range
        cursorPosition = range.location
        formatStateSynchronizer.scheduleStateUpdate()
        detectSpecialElementAtCursor()
        selectionChangeSubject.send(range)
    }

    /// 设置编辑器焦点状态
    /// - Parameter focused: 是否获得焦点
    ///
    /// 当焦点状态变化时，发送 `.editorFocusDidChange` 通知以更新菜单状态
    func setEditorFocused(_ focused: Bool) {
        guard isEditorFocused != focused else { return }

        isEditorFocused = focused

        // 发送编辑器焦点变化通知
        postEditorFocusNotification(focused)

        if focused {
            // 注册格式提供者到 FormatStateManager
            FormatStateManager.shared.setActiveProvider(formatProvider)

            // 同步编辑器上下文状态
            updateCurrentFormats()
            detectSpecialElementAtCursor()
        } else {
            // 编辑器失去焦点时，清除活动提供者
            // 注意：这里不清除，因为用户可能只是临时切换焦点
            // FormatStateManager.shared.clearActiveProvider()
        }
    }

    /// 发送编辑器焦点变化通知
    ///
    /// 当编辑器焦点状态变化时，发送通知以更新菜单状态
    ///
    private func postEditorFocusNotification(_ focused: Bool) {
        NotificationCenter.default.post(
            name: .editorFocusDidChange,
            object: self,
            userInfo: ["isEditorFocused": focused]
        )
    }

    // MARK: - Public Methods - 内容管理

    /// 更新编辑器内容（AttributedString）
    /// - Parameter text: 新的内容
    func updateContent(_ text: AttributedString) {
        attributedText = text
        hasUnsavedChanges = true
    }

    /// 更新编辑器内容（NSAttributedString）
    /// - Parameter text: 新的内容
    func updateNSContent(_ text: NSAttributedString) {
        nsAttributedText = text
        contentChangeSubject.send(text)

        // 使用版本号机制追踪文本变化
        changeTracker.textDidChange()
        autoSaveManager.scheduleAutoSave()
    }

    /// 异步更新编辑器内容（NSAttributedString）
    ///
    /// 将状态更新包装在 Task 中异步执行，避免在视图更新过程中修改 @Published 属性
    ///
    /// - Parameter text: 新的内容
    func updateNSContentAsync(_ text: NSAttributedString) {
        Task { @MainActor in
            nsAttributedText = text
            contentChangeSubject.send(text)

            // 使用版本号机制追踪文本变化
            changeTracker.textDidChange()
            autoSaveManager.scheduleAutoSave()
        }
    }

    /// 异步更新 hasUnsavedChanges 状态
    ///
    /// 将状态更新包装在 Task 中异步执行，避免在视图更新周期内修改 @Published 属性
    ///
    /// - Parameter value: 新的状态值
    ///
    func updateHasUnsavedChangesAsync(_ value: Bool) {
        Task { @MainActor in
            hasUnsavedChanges = value
        }
    }

    /// 从 XML 加载正文内容（不含标题）
    ///
    /// - Parameter xml: 小米笔记 XML 格式内容
    ///
    func loadFromXML(_ xml: String) {
        changeTracker.performProgrammaticChange {
            loadFromXMLInternal(xml)
        }
        changeTracker.reset()
    }

    /// 内部加载 XML 方法
    /// - Parameter xml: 小米笔记 XML 格式内容
    private func loadFromXMLInternal(_ xml: String) {
        guard !xml.isEmpty else {
            attributedText = AttributedString()
            nsAttributedText = NSAttributedString()
            titleText = ""
            hasUnsavedChanges = false
            hasNewFormatPrefix = false
            return
        }

        let trimmedXml = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedNewFormat = trimmedXml.hasPrefix("<new-format/>")

        do {
            let nsAttributed = try formatConverter.xmlToNSAttributedString(xml, folderId: currentFolderId)

            let mutableAttributed = NSMutableAttributedString(attributedString: nsAttributed)
            let fullRange = NSRange(location: 0, length: mutableAttributed.length)

            mutableAttributed.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                if value == nil {
                    mutableAttributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                }
            }

            hasNewFormatPrefix = detectedNewFormat
            nsAttributedText = mutableAttributed
            contentVersion += 1
            if let attributed = try? AttributedString(mutableAttributed, including: \.appKit) {
                attributedText = attributed
            }
            hasUnsavedChanges = false
        } catch {
            attributedText = AttributedString()
            nsAttributedText = NSAttributedString()
            hasUnsavedChanges = false
        }
    }

    /// 导出正文为 XML（不含标题）
    ///
    /// - Returns: 小米笔记 XML 格式内容（仅正文）
    func exportToXML() -> String {
        // 处理空正文的情况
        guard nsAttributedText.length > 0 else {
            return ""
        }

        let trimmedString = nsAttributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedString.isEmpty {
            return ""
        }

        do {
            var xmlContent = try formatConverter.nsAttributedStringToXML(nsAttributedText)

            if hasNewFormatPrefix, !xmlContent.hasPrefix("<new-format/>") {
                xmlContent = "<new-format/>" + xmlContent
            }

            return xmlContent
        } catch {
            return ""
        }
    }

    /// 检查格式是否激活
    /// - Parameter format: 格式类型
    /// - Returns: 是否激活
    func isFormatActive(_ format: TextFormat) -> Bool {
        currentFormats.contains(format)
    }

    /// 获取当前行的块级格式
    /// - Returns: 块级格式，如果没有则返回 nil
    func getCurrentBlockFormat() -> TextFormat? {
        currentFormats.first { $0.isBlockFormat }
    }

    // MARK: - 格式状态同步器方法

    /// 立即更新格式状态（不使用防抖）
    ///
    /// 在某些情况下（如用户点击格式按钮），我们需要立即更新状态
    /// 菜单栏格式菜单也需要调用此方法来获取当前格式状态
    public func forceUpdateFormats() {
        formatStateSynchronizer.performImmediateUpdate()
    }

    /// 请求从外部源同步内容
    ///
    /// 当需要确保 nsAttributedText 是最新的时候调用此方法
    /// 这会发送一个通知，让 NativeEditorView 同步内容
    /// 菜单栏格式菜单需要调用此方法来确保内容是最新的
    public func requestContentSync() {
        // 发送通知请求同步
        NotificationCenter.default.post(name: .nativeEditorRequestContentSync, object: self)
    }

    // MARK: - Private Methods

    /// 设置内部观察者
    ///
    /// 配置内容变化监听，确保：
    /// 1. 通过 contentChangeSubject 发布内容变化
    /// 2. hasUnsavedChanges 正确更新
    ///
    private func setupInternalObservers() {
        // 监听 nsAttributedText 变化
        // 当内容变化时，更新 hasUnsavedChanges 状态
        $nsAttributedText
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }

                // 检查是否是程序化修改
                if changeTracker.isInProgrammaticChange {
                    return
                }

                // 更新未保存状态
                hasUnsavedChanges = true

                // 发布内容变化通知
                // 注意：这里不直接发送 contentChangeSubject，因为 updateNSContent 方法已经会发送
                // 这里只处理通过 @Published 属性直接修改的情况
            }
            .store(in: &cancellables)

        // 监听版本号变化,用于状态同步
        changeTracker.$contentVersion
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }

                // 使用 needsSave 判断是否需要保存
                let needsSave = needsSave

                // 发送保存状态变化通知
                NotificationCenter.default.post(
                    name: .nativeEditorSaveStatusDidChange,
                    object: self,
                    userInfo: ["needsSave": needsSave]
                )

            }
            .store(in: &cancellables)
    }

    /// 批量更新状态
    ///
    /// 直接执行更新闭包，@Published 属性的修改会自动触发 objectWillChange
    /// 不需要手动调用 objectWillChange.send()，否则会在视图渲染周期内产生额外发布
    func batchUpdateState(updates: () -> Void) {
        updates()
    }

    /// 处理互斥格式（内联版本，不使用批量更新）
    ///
    /// 此方法用于在已经处于批量更新上下文中时调用，避免嵌套批量更新
    ///
    /// - Parameter format: 要应用的格式
    private func handleMutuallyExclusiveFormatsInline(for format: TextFormat) {
        // 标题格式互斥
        if format == .heading1 || format == .heading2 || format == .heading3 {
            currentFormats.remove(.heading1)
            currentFormats.remove(.heading2)
            currentFormats.remove(.heading3)
            toolbarButtonStates[.heading1] = false
            toolbarButtonStates[.heading2] = false
            toolbarButtonStates[.heading3] = false
        }

        // 对齐格式互斥
        if format == .alignCenter || format == .alignRight {
            currentFormats.remove(.alignCenter)
            currentFormats.remove(.alignRight)
            toolbarButtonStates[.alignCenter] = false
            toolbarButtonStates[.alignRight] = false
        }

        // 列表格式互斥
        if format == .bulletList || format == .numberedList || format == .checkbox {
            currentFormats.remove(.bulletList)
            currentFormats.remove(.numberedList)
            currentFormats.remove(.checkbox)
            toolbarButtonStates[.bulletList] = false
            toolbarButtonStates[.numberedList] = false
            toolbarButtonStates[.checkbox] = false
        }
    }

    /// 处理互斥格式
    /// - Parameter format: 要应用的格式
    private func handleMutuallyExclusiveFormats(for format: TextFormat) {
        // 使用批量更新机制，减少视图重绘次数
        batchUpdateState {
            handleMutuallyExclusiveFormatsInline(for: format)
        }
    }

    /// 放大
    func zoomIn() {
        // 发送缩放通知，让编辑器视图处理
        NotificationCenter.default.post(name: .editorZoomIn, object: nil)
    }

    /// 缩小
    func zoomOut() {
        // 发送缩放通知，让编辑器视图处理
        NotificationCenter.default.post(name: .editorZoomOut, object: nil)
    }

    /// 重置缩放
    func resetZoom() {
        // 发送重置缩放通知，让编辑器视图处理
        NotificationCenter.default.post(name: .editorResetZoom, object: nil)
    }
}

// MARK: - 缩放通知扩展

extension Notification.Name {
    /// 编辑器放大通知
    static let editorZoomIn = Notification.Name("editorZoomIn")
    /// 编辑器缩小通知
    static let editorZoomOut = Notification.Name("editorZoomOut")
    /// 编辑器重置缩放通知
    static let editorResetZoom = Notification.Name("editorResetZoom")
}
