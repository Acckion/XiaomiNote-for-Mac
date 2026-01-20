import AppKit
import MiNoteLibrary
import CommonCrypto

/// 菜单动作处理器
/// 负责处理应用程序菜单的各种动作
/// 实现 NSMenuItemValidation 协议以管理菜单项的启用/禁用状态
@MainActor
class MenuActionHandler: NSObject, NSMenuItemValidation {
    
    // MARK: - 属性
    
    /// 主窗口控制器的弱引用
    private weak var mainWindowController: MainWindowController?
    
    /// 窗口管理器
    private let windowManager: WindowManager
    
    /// 菜单状态
    /// 用于管理菜单项的启用/禁用和勾选状态
    private(set) var menuState: MenuState = MenuState()
    
    // MARK: - 初始化
    
    /// 初始化菜单动作处理器
    /// - Parameters:
    ///   - mainWindowController: 主窗口控制器
    ///   - windowManager: 窗口管理器
    init(mainWindowController: MainWindowController? = nil, windowManager: WindowManager) {
        self.mainWindowController = mainWindowController
        self.windowManager = windowManager
        super.init()
        setupStateObservers()
    }
    
    // MARK: - 公共方法
    
    /// 更新主窗口控制器引用
    /// - Parameter controller: 主窗口控制器
    func updateMainWindowController(_ controller: MainWindowController?) {
        self.mainWindowController = controller
        // 更新菜单状态
        updateMenuStateFromContext()
    }
    
    /// 更新菜单状态
    /// - Parameter newState: 新的菜单状态
    func updateMenuState(_ newState: MenuState) {
        menuState = newState
    }
    
    // MARK: - NSMenuItemValidation
    
    /// 验证菜单项是否应该启用
    /// 根据 MenuItemTag 和 MenuState 返回正确的启用状态
    /// - Parameter menuItem: 要验证的菜单项
    /// - Returns: 菜单项是否应该启用
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // 获取菜单项标签
        guard let tag = MenuItemTag(rawValue: menuItem.tag) else {
            // 未知标签的菜单项默认启用
            return true
        }
        
        // 更新菜单状态
        updateMenuStateFromContext()
        
        // 更新菜单项的勾选状态
        updateMenuItemCheckState(menuItem, for: tag)
        
        // 检查是否在标题段落中，如果是则禁用格式菜单
        if isFormatMenuItem(tag) && isInTitleParagraph() {
            print("[MenuActionHandler] 标题段落中禁用格式菜单: \(tag)")
            return false
        }
        
        // 根据标签类型返回启用状态
        let shouldEnable = menuState.shouldEnableMenuItem(for: tag)
        
        return shouldEnable
    }
    
    // MARK: - 私有方法 - 状态管理
    
    /// 设置状态观察者
    /// 
    /// 监听各种状态变化通知，更新菜单状态
    private func setupStateObservers() {
        // 监听笔记选中状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNoteSelectionChanged(_:)),
            name: .noteSelectionDidChange,
            object: nil
        )
        
        // 监听编辑器焦点变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEditorFocusChanged(_:)),
            name: .editorFocusDidChange,
            object: nil
        )
        
        // 监听视图模式变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleViewModeChanged(_:)),
            name: .viewModeDidChange,
            object: nil
        )
        
        // 监听段落样式变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleParagraphStyleChanged(_:)),
            name: .paragraphStyleDidChange,
            object: nil
        )
        
        // 监听文件夹可见性变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFolderVisibilityChanged(_:)),
            name: .folderVisibilityDidChange,
            object: nil
        )
        
        // 监听笔记数量显示变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNoteCountVisibilityChanged(_:)),
            name: .noteCountVisibilityDidChange,
            object: nil
        )
    }
    
    /// 处理笔记选中状态变化
    @objc private func handleNoteSelectionChanged(_ notification: Notification) {
        // 从通知中获取选中状态
        if let hasSelectedNote = notification.userInfo?["hasSelectedNote"] as? Bool {
            var newState = menuState
            newState.setNoteSelected(hasSelectedNote)
            menuState = newState
        } else {
            // 如果通知中没有状态信息，从上下文更新
            updateMenuStateFromContext()
        }
    }
    
    /// 处理编辑器焦点变化
    /// _Requirements: 14.5_
    @objc private func handleEditorFocusChanged(_ notification: Notification) {
        // 从通知中获取焦点状态
        if let isEditorFocused = notification.userInfo?["isEditorFocused"] as? Bool {
            var newState = menuState
            newState.setEditorFocused(isEditorFocused)
            menuState = newState
        } else {
            // 如果通知中没有状态信息，从上下文更新
            updateMenuStateFromContext()
        }
    }
    
    /// 处理视图模式变化
    /// _Requirements: 14.7_
    @objc private func handleViewModeChanged(_ notification: Notification) {
        // 从通知中获取视图模式
        if let viewModeRaw = notification.userInfo?["viewMode"] as? String,
           let viewMode = ViewMode(rawValue: viewModeRaw) {
            var newState = menuState
            switch viewMode {
            case .list:
                newState.setViewMode(.list)
            case .gallery:
                newState.setViewMode(.gallery)
            }
            menuState = newState
        } else {
            // 如果通知中没有状态信息，从上下文更新
            updateMenuStateFromContext()
        }
    }
    
    /// 处理段落样式变化
    /// _Requirements: 14.6_
    @objc private func handleParagraphStyleChanged(_ notification: Notification) {
        // 从通知中获取段落样式
        if let paragraphStyleRaw = notification.userInfo?["paragraphStyle"] as? String,
           let paragraphStyle = ParagraphStyle(rawValue: paragraphStyleRaw) {
            var newState = menuState
            newState.setParagraphStyle(paragraphStyle)
            menuState = newState
        }
    }
    
    /// 处理文件夹可见性变化
    @objc private func handleFolderVisibilityChanged(_ notification: Notification) {
        // 从通知中获取文件夹隐藏状态
        if let isFolderHidden = notification.userInfo?["isFolderHidden"] as? Bool {
            var newState = menuState
            newState.isFolderHidden = isFolderHidden
            menuState = newState
        }
    }
    
    /// 处理笔记数量显示变化
    /// _Requirements: 5.5_
    @objc private func handleNoteCountVisibilityChanged(_ notification: Notification) {
        // 从通知中获取笔记数量显示状态
        if let isNoteCountVisible = notification.userInfo?["isNoteCountVisible"] as? Bool {
            var newState = menuState
            newState.isNoteCountVisible = isNoteCountVisible
            menuState = newState
        }
    }
    
    /// 从当前上下文更新菜单状态
    /// 
    /// 从编辑器上下文获取当前的格式状态，并更新菜单状态
    /// _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_
    private func updateMenuStateFromContext() {
        var newState = menuState
        
        // 更新笔记选中状态
        let hasSelectedNote = mainWindowController?.viewModel?.selectedNote != nil
        newState.hasSelectedNote = hasSelectedNote
        
        // 更新编辑器焦点状态
        // 检查当前第一响应者是否是编辑器（NSTextView 或其子类）
        var isEditorFocused = false
        if let window = NSApp.mainWindow,
           let firstResponder = window.firstResponder {
            // 检查是否是 NSTextView 或其子类
            isEditorFocused = firstResponder is NSTextView
        }

        
        // 如果有选中的笔记，即使编辑器没有焦点，也应该允许格式菜单操作
        // 这样用户可以在点击菜单时应用格式
        if hasSelectedNote {
            isEditorFocused = true
        }
        newState.isEditorFocused = isEditorFocused
        
        // 更新视图模式状态
        // 注意：ViewOptionsManager 使用的是 ViewOptionsState.ViewMode
        // 而 MenuState 使用的是 MenuViewMode
        let currentViewMode = ViewOptionsManager.shared.viewMode
        switch currentViewMode {
        case .list:
            newState.currentViewMode = .list
        case .gallery:
            newState.currentViewMode = .gallery
        }
        
        // 更新文件夹隐藏状态
        // 从 UI 读取当前实际的折叠状态，确保菜单标题与实际状态一致
        if let window = NSApp.mainWindow,
           let splitViewController = window.contentViewController as? NSSplitViewController,
           splitViewController.splitViewItems.count > 0 {
            let uiCollapsedState = splitViewController.splitViewItems[0].isCollapsed
            newState.isFolderHidden = uiCollapsedState
        }
        
        // 更新笔记数量显示状态
        // _Requirements: 9.3_
        newState.isNoteCountVisible = ViewOptionsManager.shared.showNoteCount
        
        // 更新段落样式状态（从编辑器上下文获取）
        // _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_
        // 关键修复：检查当前使用的是哪种编辑器
        let isUsingNativeEditor = mainWindowController?.isUsingNativeEditor ?? false
        
        if isUsingNativeEditor {
            // 原生编辑器：从 NativeEditorContext 获取格式状态
            if let nativeEditorContext = mainWindowController?.getCurrentNativeEditorContext() {
                // 注意：不再调用 requestContentSync，因为它是异步的
                // nsAttributedText 应该已经在 textViewDidChangeSelection 中同步更新了
                // 如果需要确保内容是最新的，可以直接从 textView 获取
                
                // 强制更新格式状态
                // 这与工具栏格式菜单（NativeFormatMenuView）的行为保持一致
                nativeEditorContext.forceUpdateFormats()
                
                let paragraphStyleString = nativeEditorContext.getCurrentParagraphStyleString()
                if let paragraphStyle = ParagraphStyle(rawValue: paragraphStyleString) {
                    newState.setParagraphStyle(paragraphStyle)
                }
            }
        }
        
        menuState = newState
    }
    
    /// 更新菜单项的勾选状态
    /// - Parameters:
    ///   - menuItem: 菜单项
    ///   - tag: 菜单项标签
    private func updateMenuItemCheckState(_ menuItem: NSMenuItem, for tag: MenuItemTag) {
        let shouldCheck = menuState.shouldCheckMenuItem(for: tag)
        menuItem.state = shouldCheck ? .on : .off
        
        // 更新动态标题
        // _Requirements: 9.2, 9.3_
        updateMenuItemDynamicTitle(menuItem, for: tag)
    }
    
    /// 更新菜单项的动态标题
    /// 
    /// 根据当前状态更新菜单项标题（如"隐藏文件夹"/"显示文件夹"）
    /// - Parameters:
    ///   - menuItem: 菜单项
    ///   - tag: 菜单项标签
    /// _Requirements: 9.2, 9.3_
    private func updateMenuItemDynamicTitle(_ menuItem: NSMenuItem, for tag: MenuItemTag) {
        switch tag {
        case .hideFolders:
            // 根据文件夹隐藏状态更新标题
            menuItem.title = menuState.isFolderHidden ? "显示文件夹" : "隐藏文件夹"
        case .showNoteCount:
            // 根据笔记数量显示状态更新标题
            menuItem.title = menuState.isNoteCountVisible ? "隐藏笔记数量" : "显示笔记数量"
        default:
            break
        }
    }
    
    /// 检查菜单项是否为格式菜单项
    /// - Parameter tag: 菜单项标签
    /// - Returns: 是否为格式菜单项
    private func isFormatMenuItem(_ tag: MenuItemTag) -> Bool {
        switch tag {
        case .bold, .italic, .underline, .strikethrough, .highlight,
             .heading, .subheading, .subtitle, .bodyText,
             .unorderedList, .orderedList, .checklist,
             .alignLeft, .alignCenter, .alignRight,
             .blockQuote:
            return true
        default:
            return false
        }
    }
    
    /// 检查当前光标是否在标题段落中
    /// - Returns: 是否在标题段落中
    private func isInTitleParagraph() -> Bool {
        // 检查当前使用的是哪种编辑器
        let isUsingNativeEditor = mainWindowController?.isUsingNativeEditor ?? false
        
        if isUsingNativeEditor {
            // 原生编辑器：从 NativeEditorContext 检查
            if let nativeEditorContext = mainWindowController?.getCurrentNativeEditorContext() {
                // 使用 nsAttributedText 而不是 textStorage
                let textStorage = nativeEditorContext.nsAttributedText
                let cursorPosition = nativeEditorContext.selectedRange.location
                
                // 检查光标位置是否在标题段落中
                if cursorPosition < textStorage.length {
                    // 获取光标所在行的范围
                    let string = textStorage.string as NSString
                    let lineRange = string.lineRange(for: NSRange(location: cursorPosition, length: 0))
                    
                    // 检查该行是否有 .isTitle 属性
                    if lineRange.location < textStorage.length {
                        let attributes = textStorage.attributes(at: lineRange.location, effectiveRange: nil)
                        if let isTitle = attributes[.isTitle] as? Bool, isTitle {
                            return true
                        }
                    }
                }
            }
        }
        
        return false
    }
    
    // MARK: - 应用程序菜单动作
    
    /// 显示关于面板
    func showAboutPanel(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "小米笔记"
        alert.informativeText = "版本 2.1.0\n\n一个简洁的笔记应用程序，支持小米笔记同步。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 显示设置窗口
    func showSettings(_ sender: Any?) {
        // 创建设置窗口控制器
        let settingsWindowController = SettingsWindowController(viewModel: mainWindowController?.viewModel)
        
        // 显示窗口
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    /// 显示帮助
    func showHelp(_ sender: Any?) {
        // 这里可以打开帮助文档
    }
    
    // MARK: - 窗口菜单动作
    
    /// 创建新窗口
    func createNewWindow(_ sender: Any?) {
        windowManager.createNewWindow()
    }
    
    // MARK: - 编辑菜单动作
    
    /// 撤销
    func undo(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.undo(sender)
    }
    
    /// 重做
    func redo(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.redo(sender)
    }
    
    /// 剪切
    func cut(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.cut(sender)
    }
    
    /// 复制
    func copy(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.copy(sender)
    }
    
    /// 粘贴
    func paste(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.paste(sender)
    }
    
    /// 全选
    func selectAll(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.selectAll(sender)
    }
    
    // MARK: - 格式菜单动作
    
    /// 切换粗体
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    /// _Requirements: 8.1, 8.2_
    func toggleBold(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.bold)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.toggleBold(sender)
        }
    }
    
    /// 切换斜体
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    /// _Requirements: 8.1, 8.2_
    func toggleItalic(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.italic)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.toggleItalic(sender)
        }
    }
    
    /// 切换下划线
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    /// _Requirements: 8.1, 8.2_
    func toggleUnderline(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.underline)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.toggleUnderline(sender)
        }
    }
    
    /// 切换删除线
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    /// _Requirements: 8.1, 8.2_
    func toggleStrikethrough(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.strikethrough)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.toggleStrikethrough(sender)
        }
    }
    
    /// 增大字体
    func increaseFontSize(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.increaseFontSize(sender)
    }
    
    /// 减小字体
    func decreaseFontSize(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.decreaseFontSize(sender)
    }
    
    /// 增加缩进
    func increaseIndent(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.increaseIndent(sender)
    }
    
    /// 减少缩进
    func decreaseIndent(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.decreaseIndent(sender)
    }
    
    /// 居左对齐
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    /// _Requirements: 8.1, 8.2_
    func alignLeft(_ sender: Any?) {
        // 优先使用 FormatStateManager 清除对齐格式（恢复左对齐）
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.clearAlignmentFormat()
        } else {
            // 回退到主窗口控制器
            mainWindowController?.alignLeft(sender)
        }
    }
    
    /// 居中对齐
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    /// _Requirements: 8.1, 8.2_
    func alignCenter(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.applyFormat(.alignCenter)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.alignCenter(sender)
        }
    }
    
    /// 居右对齐
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    /// _Requirements: 8.1, 8.2_
    func alignRight(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.applyFormat(.alignRight)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.alignRight(sender)
        }
    }
    
    /// 切换无序列表
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    /// _Requirements: 8.1, 8.2_
    func toggleBulletList(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.bulletList)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.toggleBulletList(sender)
        }
    }
    
    /// 切换有序列表
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    func toggleNumberedList(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.numberedList)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.toggleNumberedList(sender)
        }
    }
    
    /// 切换复选框列表
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    func toggleCheckboxList(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.checkbox)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.toggleCheckboxList(sender)
        }
    }
    
    /// 设置大标题
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    func setHeading1(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.applyFormat(.heading1)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.setHeading1(sender)
        }
    }
    
    /// 设置二级标题
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    func setHeading2(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.applyFormat(.heading2)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.setHeading2(sender)
        }
    }
    
    /// 设置三级标题
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    func setHeading3(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.applyFormat(.heading3)
        } else {
            // 回退到主窗口控制器
            mainWindowController?.setHeading3(sender)
        }
    }
    
    /// 设置正文
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑
    /// _Requirements: 8.1, 8.2_
    func setBodyText(_ sender: Any?) {
        // 优先使用 FormatStateManager 清除段落格式（恢复正文）
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.clearParagraphFormat()
        } else {
            // 回退到主窗口控制器
            mainWindowController?.setBodyText(sender)
        }
    }
    
    // MARK: - 格式菜单动作（Apple Notes 风格）
    
    /// 设置标题（Apple Notes 风格）
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑 
    @objc func setHeading(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.applyFormat(.heading1)
        } else {
            mainWindowController?.setHeading1(sender)
        }
    }
    
    /// 设置小标题
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑 
    @objc func setSubheading(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.applyFormat(.heading2)
        } else {
            mainWindowController?.setHeading2(sender)
        }
    }
    
    /// 设置副标题
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑 
    @objc func setSubtitle(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.applyFormat(.heading3)
        } else {
            mainWindowController?.setHeading3(sender)
        }
    }
    
    /// 切换有序列表
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑 
    @objc func toggleOrderedList(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.numberedList)
        } else {
            mainWindowController?.toggleNumberedList(sender)
        }
    }
    
    /// 切换无序列表
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑 
    @objc func toggleUnorderedList(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.bulletList)
        } else {
            mainWindowController?.toggleBulletList(sender)
        }
    }
    
    /// 切换块引用
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑 
    @objc func toggleBlockQuote(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.quote)
        } else {
            mainWindowController?.toggleBlockQuote(sender)
        }
    }
    
    // MARK: - 核对清单动作
    
    /// 切换核对清单
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑 
    @objc func toggleChecklist(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.checkbox)
        } else {
            mainWindowController?.toggleCheckboxList(sender)
        }
    }
    
    /// 标记为已勾选 
    @objc func markAsChecked(_ sender: Any?) {
        mainWindowController?.markAsChecked(sender)
    }
    
    /// 全部勾选 
    @objc func checkAll(_ sender: Any?) {
        mainWindowController?.checkAll(sender)
    }
    
    /// 全部取消勾选 
    @objc func uncheckAll(_ sender: Any?) {
        mainWindowController?.uncheckAll(sender)
    }
    
    /// 将勾选的项目移到底部 
    @objc func moveCheckedToBottom(_ sender: Any?) {
        mainWindowController?.moveCheckedToBottom(sender)
    }
    
    /// 删除已勾选项目 
    @objc func deleteCheckedItems(_ sender: Any?) {
        mainWindowController?.deleteCheckedItems(sender)
    }
    
    /// 向上移动项目 
    @objc func moveItemUp(_ sender: Any?) {
        mainWindowController?.moveItemUp(sender)
    }
    
    /// 向下移动项目 
    @objc func moveItemDown(_ sender: Any?) {
        mainWindowController?.moveItemDown(sender)
    }
    
    // MARK: - 外观动作
    
    /// 切换浅色背景 
    @objc func toggleLightBackground(_ sender: Any?) {
        mainWindowController?.toggleLightBackground(sender)
    }
    
    /// 切换高亮
    /// 使用 FormatStateManager 确保菜单操作和工具栏操作使用相同的逻辑 
    @objc func toggleHighlight(_ sender: Any?) {
        // 优先使用 FormatStateManager 应用格式
        if FormatStateManager.shared.hasActiveEditor {
            FormatStateManager.shared.toggleFormat(.highlight)
        } else {
            mainWindowController?.toggleHighlight(sender)
        }
    }
    
    // MARK: - 其他菜单动作
    
    /// 显示调试设置窗口
    func showDebugSettings(_ sender: Any?) {
        // 创建调试窗口控制器
        let debugWindowController = DebugWindowController(viewModel: mainWindowController?.viewModel)
        
        // 显示窗口
        debugWindowController.showWindow(nil)
        debugWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    /// 显示登录sheet
    func showLogin(_ sender: Any?) {
        // 通过主窗口控制器显示登录sheet
        mainWindowController?.showLogin(sender)
    }
    
    /// 显示Cookie刷新sheet
    func showCookieRefresh(_ sender: Any?) {
        // 通过主窗口控制器显示Cookie刷新sheet
        mainWindowController?.showCookieRefresh(sender)
    }
    
    /// 显示离线操作
    func showOfflineOperations(_ sender: Any?) {
        // 这里可以打开离线操作窗口
    }
    
    /// 显示段落管理器调试窗口
    func showParagraphDebugWindow(_ sender: Any?) {
        windowManager.showParagraphDebugWindow()
    }
    
    // MARK: - 文件菜单新增动作
    
    /// 创建新笔记
    func createNewNote(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.createNewNote(sender)
    }
    
    /// 创建新文件夹
    func createNewFolder(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.createNewFolder(sender)
    }
    
    /// 共享笔记
    func shareNote(_ sender: Any?) {
        // 转发到主窗口控制器
        mainWindowController?.shareNote(sender)
    }
    
    /// 导入笔记
    func importNotes(_ sender: Any?) {
        // 实现导入功能
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.text, .plainText, .rtf]
        panel.message = "选择要导入的笔记文件"
        
        panel.begin { [weak self] response in
            if response == .OK {
                for url in panel.urls {
                    Task {
                        do {
                            let content = try String(contentsOf: url, encoding: .utf8)
                            let fileName = url.deletingPathExtension().lastPathComponent
                            
                            let newNote = Note(
                                id: UUID().uuidString,
                                title: fileName,
                                content: content,
                                folderId: self?.mainWindowController?.viewModel?.selectedFolder?.id ?? "0",
                                isStarred: false,
                                createdAt: Date(),
                                updatedAt: Date()
                            )
                            
                            try await self?.mainWindowController?.viewModel?.createNote(newNote)
                        } catch {
                            print("[MenuActionHandler] 导入笔记失败: \(error)")
                            DispatchQueue.main.async {
                                let errorAlert = NSAlert()
                                errorAlert.messageText = "导入失败"
                                errorAlert.informativeText = "无法导入文件: \(url.lastPathComponent)\n\(error.localizedDescription)"
                                errorAlert.alertStyle = .warning
                                errorAlert.runModal()
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// 导出笔记
    func exportNote(_ sender: Any?) {
        print("导出笔记")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = "请先选择一个要导出的笔记"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = note.title.isEmpty ? "无标题" : note.title
        panel.message = "导出笔记"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try note.content.write(to: url, atomically: true, encoding: String.Encoding.utf8)
                } catch {
                    print("[MenuActionHandler] 导出笔记失败: \(error)")
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "导出失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    errorAlert.runModal()
                }
            }
        }
    }
    
    /// 置顶/取消置顶笔记
    func toggleStarNote(_ sender: Any?) {
        print("置顶/取消置顶笔记")
        guard let note = mainWindowController?.viewModel?.selectedNote else { return }
        mainWindowController?.viewModel?.toggleStar(note)
    }
    
    /// 复制笔记
    func copyNote(_ sender: Any?) {
        print("复制笔记")
        guard let note = mainWindowController?.viewModel?.selectedNote else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // 复制标题和内容
        let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
        pasteboard.setString(content, forType: .string)
    }
    
    // MARK: - 文件菜单新增动作
    
    /// 创建智能文件夹 
    func createSmartFolder(_ sender: Any?) {
        print("创建智能文件夹")
        // 智能文件夹功能待实现
        let alert = NSAlert()
        alert.messageText = "功能开发中"
        alert.informativeText = "智能文件夹功能正在开发中，敬请期待。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 导入 Markdown 文件 
    func importMarkdown(_ sender: Any?) {
        print("导入 Markdown")
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
        panel.message = "选择要导入的 Markdown 文件"
        
        panel.begin { [weak self] response in
            if response == .OK {
                for url in panel.urls {
                    Task {
                        do {
                            let content = try String(contentsOf: url, encoding: .utf8)
                            let fileName = url.deletingPathExtension().lastPathComponent
                            
                            let newNote = Note(
                                id: UUID().uuidString,
                                title: fileName,
                                content: content,
                                folderId: self?.mainWindowController?.viewModel?.selectedFolder?.id ?? "0",
                                isStarred: false,
                                createdAt: Date(),
                                updatedAt: Date()
                            )
                            
                            try await self?.mainWindowController?.viewModel?.createNote(newNote)
                            print("[MenuActionHandler] 成功导入 Markdown 文件: \(fileName)")
                        } catch {
                            print("[MenuActionHandler] 导入 Markdown 失败: \(error)")
                            DispatchQueue.main.async {
                                let errorAlert = NSAlert()
                                errorAlert.messageText = "导入失败"
                                errorAlert.informativeText = "无法导入文件: \(url.lastPathComponent)\n\(error.localizedDescription)"
                                errorAlert.alertStyle = .warning
                                errorAlert.runModal()
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// 导出为 PDF 
    func exportAsPDF(_ sender: Any?) {
        print("导出为 PDF")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            showNoNoteSelectedAlert()
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (note.title.isEmpty ? "无标题" : note.title) + ".pdf"
        panel.message = "导出笔记为 PDF"
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.exportNoteToPDF(note: note, url: url)
            }
        }
    }
    
    /// 导出为 Markdown 
    func exportAsMarkdown(_ sender: Any?) {
        print("导出为 Markdown")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            showNoNoteSelectedAlert()
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = (note.title.isEmpty ? "无标题" : note.title) + ".md"
        panel.message = "导出笔记为 Markdown"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    // 将笔记内容转换为 Markdown 格式
                    let markdownContent = self.convertToMarkdown(note: note)
                    try markdownContent.write(to: url, atomically: true, encoding: .utf8)
                    print("[MenuActionHandler] 成功导出 Markdown: \(url.path)")
                } catch {
                    print("[MenuActionHandler] 导出 Markdown 失败: \(error)")
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "导出失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    errorAlert.runModal()
                }
            }
        }
    }
    
    /// 导出为纯文本 
    func exportAsPlainText(_ sender: Any?) {
        print("导出为纯文本")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            showNoNoteSelectedAlert()
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (note.title.isEmpty ? "无标题" : note.title) + ".txt"
        panel.message = "导出笔记为纯文本"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    // 组合标题和内容
                    let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    print("[MenuActionHandler] 成功导出纯文本: \(url.path)")
                } catch {
                    print("[MenuActionHandler] 导出纯文本失败: \(error)")
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "导出失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    errorAlert.runModal()
                }
            }
        }
    }
    
    /// 添加到私密笔记 
    func addToPrivateNotes(_ sender: Any?) {
        print("添加到私密笔记")
        // 私密笔记功能待实现
        let alert = NSAlert()
        alert.messageText = "功能开发中"
        alert.informativeText = "私密笔记功能正在开发中，敬请期待。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 复制笔记（创建副本） 
    func duplicateNote(_ sender: Any?) {
        print("复制笔记（创建副本）")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            showNoNoteSelectedAlert()
            return
        }
        
        Task {
            do {
                // 创建笔记副本
                let duplicatedNote = Note(
                    id: UUID().uuidString,
                    title: note.title.isEmpty ? "无标题 副本" : "\(note.title) 副本",
                    content: note.content,
                    folderId: note.folderId,
                    isStarred: false,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                
                try await mainWindowController?.viewModel?.createNote(duplicatedNote)
                print("[MenuActionHandler] 成功复制笔记: \(duplicatedNote.title)")
            } catch {
                print("[MenuActionHandler] 复制笔记失败: \(error)")
                DispatchQueue.main.async {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "复制失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    errorAlert.runModal()
                }
            }
        }
    }
    
    // MARK: - 私有辅助方法
    
    /// 显示未选中笔记的提示
    private func showNoNoteSelectedAlert() {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = "请先选择一个笔记"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 将笔记导出为 PDF
    private func exportNoteToPDF(note: Note, url: URL) {
        // 创建打印信息
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 612, height: 792) // Letter size
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        
        // 创建文本视图用于渲染
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        textView.string = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
        
        // 创建 PDF 数据
        let pdfData = textView.dataWithPDF(inside: textView.bounds)
        
        do {
            try pdfData.write(to: url)
            print("[MenuActionHandler] 成功导出 PDF: \(url.path)")
        } catch {
            print("[MenuActionHandler] 导出 PDF 失败: \(error)")
            let errorAlert = NSAlert()
            errorAlert.messageText = "导出失败"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }
    
    /// 将笔记转换为 Markdown 格式
    private func convertToMarkdown(note: Note) -> String {
        var markdown = ""
        
        // 添加标题
        if !note.title.isEmpty {
            markdown += "# \(note.title)\n\n"
        }
        
        // 添加内容（简单处理，实际可能需要更复杂的 HTML 到 Markdown 转换）
        markdown += note.content
        
        return markdown
    }

    // MARK: - 查找功能

    /// 显示查找面板
    func showFindPanel(_ sender: Any?) {
        print("显示查找面板")
        print("[DEBUG] MenuActionHandler - mainWindowController: \(mainWindowController != nil)")
        if let controller = mainWindowController {
            print("[DEBUG] MenuActionHandler - 调用主窗口控制器的showFindPanel")
            controller.showFindPanel(sender)
        } else {
            print("[ERROR] MenuActionHandler - mainWindowController为nil")
        }
    }

    /// 显示查找和替换面板
    func showFindAndReplacePanel(_ sender: Any?) {
        print("显示查找和替换面板")
        mainWindowController?.showFindAndReplacePanel(sender)
    }

    /// 查找下一个
    func findNext(_ sender: Any?) {
        print("查找下一个")
        mainWindowController?.findNext(sender)
    }

    /// 查找上一个
    func findPrevious(_ sender: Any?) {
        print("查找上一个")
        mainWindowController?.findPrevious(sender)
    }
    
    // MARK: - 附件操作
    
    /// 附加文件
    /// 直接调用 MainWindowController.insertAttachment() 复用工具栏中已有的实现逻辑 
    @objc func attachFile(_ sender: Any?) {
        print("[MenuActionHandler] 附加文件 - 转发到 MainWindowController.insertAttachment()")
        // 直接调用 MainWindowController 的 insertAttachment 方法
        // 复用工具栏中已有的实现逻辑（包括文件选择对话框和图片插入）
        mainWindowController?.insertAttachment(sender)
    }
    
    /// 添加链接 
    @objc func addLink(_ sender: Any?) {
        print("添加链接")
        // 显示添加链接对话框
        let alert = NSAlert()
        alert.messageText = "添加链接"
        alert.informativeText = "请输入链接地址："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputField.placeholderString = "https://example.com"
        alert.accessoryView = inputField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let urlString = inputField.stringValue
            if !urlString.isEmpty {
                print("[MenuActionHandler] 添加链接: \(urlString)")
                mainWindowController?.addLink(urlString)
            }
        }
    }
    
    // MARK: - 显示菜单动作
    
    /// 设置列表视图 
    @objc func setListView(_ sender: Any?) {
        print("设置列表视图")
        ViewOptionsManager.shared.setViewMode(.list)
    }
    
    /// 设置画廊视图 
    @objc func setGalleryView(_ sender: Any?) {
        print("设置画廊视图")
        ViewOptionsManager.shared.setViewMode(.gallery)
    }
    
    /// 切换文件夹可见性 
    @objc func toggleFolderVisibility(_ sender: Any?) {
        // 通过 MainWindowController 切换侧边栏
        if let window = NSApp.mainWindow,
           let splitViewController = window.contentViewController as? NSSplitViewController,
           splitViewController.splitViewItems.count > 0 {
            let sidebarItem = splitViewController.splitViewItems[0]
            let currentCollapsedState = sidebarItem.isCollapsed
            let newCollapsedState = !currentCollapsedState
            
            // 先更新菜单状态，确保状态一致性
            // _Requirements: 4.4, 4.5_
            var newState = menuState
            newState.isFolderHidden = newCollapsedState
            menuState = newState
            
            // 然后执行动画切换侧边栏
            sidebarItem.animator().isCollapsed = newCollapsedState
            
            // 发送文件夹可见性变化通知
            // _Requirements: 4.4_
            NotificationCenter.default.post(
                name: .folderVisibilityDidChange,
                object: nil,
                userInfo: ["isFolderHidden": newCollapsedState]
            )
        }
    }
    
    /// 切换笔记数量显示 
    @objc func toggleNoteCount(_ sender: Any?) {
        // 通过 ViewOptionsManager 切换笔记数量显示
        ViewOptionsManager.shared.toggleNoteCount()
        
        // 更新菜单状态
        var newState = menuState
        newState.isNoteCountVisible = ViewOptionsManager.shared.showNoteCount
        menuState = newState
    }
    
    /// 放大 
    @objc func zoomIn(_ sender: Any?) {
        print("放大")
        mainWindowController?.zoomIn(sender)
    }
    
    /// 缩小 
    @objc func zoomOut(_ sender: Any?) {
        print("缩小")
        mainWindowController?.zoomOut(sender)
    }
    
    /// 实际大小 
    @objc func actualSize(_ sender: Any?) {
        print("实际大小")
        mainWindowController?.actualSize(sender)
    }
    
    /// 展开区域 
    @objc func expandSection(_ sender: Any?) {
        print("展开区域")
        mainWindowController?.expandSection(sender)
    }
    
    /// 展开所有区域 
    @objc func expandAllSections(_ sender: Any?) {
        print("展开所有区域")
        mainWindowController?.expandAllSections(sender)
    }
    
    /// 折叠区域 
    @objc func collapseSection(_ sender: Any?) {
        print("折叠区域")
        mainWindowController?.collapseSection(sender)
    }
    
    /// 折叠所有区域 
    @objc func collapseAllSections(_ sender: Any?) {
        print("折叠所有区域")
        mainWindowController?.collapseAllSections(sender)
    }
    
    // MARK: - 窗口菜单动作
    
    /// 填充窗口到屏幕 
    @objc func fillWindow(_ sender: Any?) {
        print("填充窗口")
        guard let window = NSApp.mainWindow,
              let screen = window.screen else { return }
        
        // 获取屏幕可用区域（排除菜单栏和 Dock）
        let visibleFrame = screen.visibleFrame
        
        // 设置窗口大小为屏幕可用区域
        window.setFrame(visibleFrame, display: true, animate: true)
    }
    
    /// 居中窗口 
    @objc func centerWindow(_ sender: Any?) {
        print("居中窗口")
        guard let window = NSApp.mainWindow else { return }
        window.center()
    }
    
    /// 移动窗口到屏幕左半边 
    @objc func moveWindowToLeftHalf(_ sender: Any?) {
        print("移动窗口到屏幕左半边")
        guard let window = NSApp.mainWindow,
              let screen = window.screen else { return }
        
        let visibleFrame = screen.visibleFrame
        let newFrame = NSRect(
            x: visibleFrame.origin.x,
            y: visibleFrame.origin.y,
            width: visibleFrame.width / 2,
            height: visibleFrame.height
        )
        window.setFrame(newFrame, display: true, animate: true)
    }
    
    /// 移动窗口到屏幕右半边 
    @objc func moveWindowToRightHalf(_ sender: Any?) {
        print("移动窗口到屏幕右半边")
        guard let window = NSApp.mainWindow,
              let screen = window.screen else { return }
        
        let visibleFrame = screen.visibleFrame
        let newFrame = NSRect(
            x: visibleFrame.origin.x + visibleFrame.width / 2,
            y: visibleFrame.origin.y,
            width: visibleFrame.width / 2,
            height: visibleFrame.height
        )
        window.setFrame(newFrame, display: true, animate: true)
    }
    
    /// 移动窗口到屏幕上半边 
    @objc func moveWindowToTopHalf(_ sender: Any?) {
        print("移动窗口到屏幕上半边")
        guard let window = NSApp.mainWindow,
              let screen = window.screen else { return }
        
        let visibleFrame = screen.visibleFrame
        let newFrame = NSRect(
            x: visibleFrame.origin.x,
            y: visibleFrame.origin.y + visibleFrame.height / 2,
            width: visibleFrame.width,
            height: visibleFrame.height / 2
        )
        window.setFrame(newFrame, display: true, animate: true)
    }
    
    /// 移动窗口到屏幕下半边 
    @objc func moveWindowToBottomHalf(_ sender: Any?) {
        print("移动窗口到屏幕下半边")
        guard let window = NSApp.mainWindow,
              let screen = window.screen else { return }
        
        let visibleFrame = screen.visibleFrame
        let newFrame = NSRect(
            x: visibleFrame.origin.x,
            y: visibleFrame.origin.y,
            width: visibleFrame.width,
            height: visibleFrame.height / 2
        )
        window.setFrame(newFrame, display: true, animate: true)
    }
    
    /// 最大化窗口 
    @objc func maximizeWindow(_ sender: Any?) {
        print("最大化窗口")
        guard let window = NSApp.mainWindow else { return }
        window.performZoom(sender)
    }
    
    /// 恢复窗口 
    @objc func restoreWindow(_ sender: Any?) {
        print("恢复窗口")
        guard let window = NSApp.mainWindow else { return }
        
        // 如果窗口处于缩放状态，则恢复到之前的大小
        if window.isZoomed {
            window.performZoom(sender)
        }
    }
    
    /// 平铺窗口到屏幕左侧（全屏幕平铺） 
    @objc func tileWindowToLeft(_ sender: Any?) {
        print("平铺窗口到屏幕左侧")
        guard NSApp.mainWindow != nil else { return }
        
        // 使用系统的全屏幕平铺功能
        // 注意：这需要 macOS 10.15+ 的 API
        if #available(macOS 10.15, *) {
            // 尝试进入全屏幕平铺模式
            // 由于 macOS 没有直接的 API 来实现全屏幕平铺，
            // 我们使用移动到左半边作为替代
            moveWindowToLeftHalf(sender)
        }
    }
    
    /// 平铺窗口到屏幕右侧（全屏幕平铺） 
    @objc func tileWindowToRight(_ sender: Any?) {
        print("平铺窗口到屏幕右侧")
        guard NSApp.mainWindow != nil else { return }
        
        // 使用系统的全屏幕平铺功能
        if #available(macOS 10.15, *) {
            // 尝试进入全屏幕平铺模式
            // 由于 macOS 没有直接的 API 来实现全屏幕平铺，
            // 我们使用移动到右半边作为替代
            moveWindowToRightHalf(sender)
        }
    }
    
    /// 在新窗口中打开笔记 
    @objc func openNoteInNewWindow(_ sender: Any?) {
        print("在新窗口中打开笔记")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            let alert = NSAlert()
            alert.messageText = "操作失败"
            alert.informativeText = "请先选择一个笔记"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        // 创建新窗口并显示选中的笔记
        windowManager.createNewWindow()
        
        // 在新窗口中选中相同的笔记
        if let newWindowController = windowManager.mainWindowController {
            newWindowController.viewModel?.selectNoteWithCoordinator(note)
        }
    }

    // MARK: - 调试测试方法
    
    /// 测试语音文件 API（解析 + 上传）
    /// 1. 获取包含语音的笔记，验证 sound 标签和 setting.data 元数据解析
    /// 2. 测试语音文件上传 API（使用模拟数据）
    @objc func testAudioFileAPI(_ sender: Any?) {
        print("\n========== 语音文件 API 测试开始 ==========")
        
        Task {
            do {
                // 从 UserDefaults 获取 Cookie
                guard let cookie = UserDefaults.standard.string(forKey: "minote_cookie"), !cookie.isEmpty else {
                    print("[AudioTest] ❌ 未找到 Cookie，请先登录")
                    self.showTestResult(success: false, message: "未找到 Cookie，请先登录")
                    return
                }
                
                // 从 Cookie 中提取 serviceToken
                guard extractServiceToken(from: cookie) != nil else {
                    print("[AudioTest] ❌ 无法从 Cookie 中提取 serviceToken")
                    self.showTestResult(success: false, message: "无法从 Cookie 中提取 serviceToken")
                    return
                }
                
                // ========== 第一部分：解析测试 ==========
                print("\n---------- 第一部分：解析测试 ----------")
                
                let testNoteId = "48926433520534752"
                print("[AudioTest] 正在获取笔记: \(testNoteId)")
                
                let ts = Int(Date().timeIntervalSince1970 * 1000)
                let urlString = "https://i.mi.com/note/note/\(testNoteId)/?ts=\(ts)"
                
                guard let url = URL(string: urlString) else {
                    print("[AudioTest] ❌ URL 无效")
                    self.showTestResult(success: false, message: "URL 无效")
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
                
                let (data, httpResponse) = try await URLSession.shared.data(for: request)
                
                guard let response = httpResponse as? HTTPURLResponse else {
                    print("[AudioTest] ❌ 无效的响应")
                    self.showTestResult(success: false, message: "无效的响应")
                    return
                }
                
                print("[AudioTest] HTTP 状态码: \(response.statusCode)")
                
                guard response.statusCode == 200 else {
                    print("[AudioTest] ❌ 请求失败，状态码: \(response.statusCode)")
                    self.showTestResult(success: false, message: "请求失败，状态码: \(response.statusCode)")
                    return
                }
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[AudioTest] ❌ JSON 解析失败")
                    self.showTestResult(success: false, message: "JSON 解析失败")
                    return
                }
                
                guard let code = json["code"] as? Int, code == 0 else {
                    let description = json["description"] as? String ?? "未知错误"
                    print("[AudioTest] ❌ API 请求失败: \(description)")
                    self.showTestResult(success: false, message: "API 请求失败: \(description)")
                    return
                }
                
                guard let responseData = json["data"] as? [String: Any],
                      let entry = responseData["entry"] as? [String: Any] else {
                    print("[AudioTest] ❌ 响应格式错误：无法解析 data.entry")
                    self.showTestResult(success: false, message: "响应格式错误")
                    return
                }
                
                print("[AudioTest] ✅ 成功获取笔记数据")
                
                // 解析 content 中的 sound 标签
                if let content = entry["content"] as? String {
                    print("[AudioTest] 笔记内容: \(content)")
                    
                    let soundPattern = #"<sound\s+fileid=\"([^\"]+)\"\s*/>"#
                    if let regex = try? NSRegularExpression(pattern: soundPattern),
                       let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                       let fileIdRange = Range(match.range(at: 1), in: content) {
                        let fileId = String(content[fileIdRange])
                        print("[AudioTest] ✅ 解析到 sound 标签，fileId: \(fileId)")
                    } else {
                        print("[AudioTest] ⚠️ 未找到 sound 标签")
                    }
                }
                
                // 解析 setting.data 元数据
                if let setting = entry["setting"] as? [String: Any],
                   let dataArray = setting["data"] as? [[String: Any]] {
                    print("[AudioTest] ✅ 找到 setting.data 元数据，共 \(dataArray.count) 个文件")
                    
                    for (index, fileInfo) in dataArray.enumerated() {
                        let fileId = fileInfo["fileId"] as? String ?? "未知"
                        let digest = fileInfo["digest"] as? String ?? "未知"
                        let mimeType = fileInfo["mimeType"] as? String ?? "未知"
                        
                        print("[AudioTest] 文件 \(index + 1):")
                        print("  - fileId: \(fileId)")
                        print("  - digest: \(digest)")
                        print("  - mimeType: \(mimeType)")
                        
                        if mimeType.hasPrefix("audio/") {
                            print("  - ✅ 确认为音频文件")
                        }
                    }
                } else {
                    print("[AudioTest] ⚠️ 未找到 setting.data 元数据")
                }
                
                // 解析 extraInfo
                if let extraInfoString = entry["extraInfo"] as? String,
                   let extraInfoData = extraInfoString.data(using: .utf8),
                   let extraInfo = try? JSONSerialization.jsonObject(with: extraInfoData) as? [String: Any] {
                    let title = extraInfo["title"] as? String ?? "无标题"
                    print("[AudioTest] 笔记标题: \(title)")
                }
                
                print("[AudioTest] ✅ 解析测试完成")
                
                // ========== 第二部分：上传测试 ==========
                print("\n---------- 第二部分：上传测试（使用 MiNoteService.uploadAudio）----------")
                
                // 创建模拟音频数据（一个简单的测试文件）
                let testAudioData = "Test audio file content for API testing".data(using: .utf8)!
                let testFileName = "test_audio_\(Int(Date().timeIntervalSince1970)).mp3"
                let testMimeType = "audio/mpeg"
                
                print("[AudioTest] 测试文件: \(testFileName)")
                print("[AudioTest] 文件大小: \(testAudioData.count) 字节")
                print("[AudioTest] MIME 类型: \(testMimeType)")
                
                // 使用 MiNoteService.uploadAudio 方法上传
                print("[AudioTest] 正在调用 MiNoteService.uploadAudio...")
                
                let uploadResult = try await MiNoteService.shared.uploadAudio(
                    audioData: testAudioData,
                    fileName: testFileName,
                    mimeType: testMimeType
                )
                
                // 解析上传结果
                guard let fileId = uploadResult["fileId"] as? String else {
                    print("[AudioTest] ❌ 上传成功但未返回 fileId")
                    self.showTestResult(success: false, message: "上传成功但未返回 fileId")
                    return
                }
                
                let digest = uploadResult["digest"] as? String ?? "未知"
                let mimeType = uploadResult["mimeType"] as? String ?? "未知"
                
                print("[AudioTest] ✅ 上传成功！")
                print("[AudioTest] fileId: \(fileId)")
                print("[AudioTest] digest: \(digest)")
                print("[AudioTest] mimeType: \(mimeType)")
                
                print("\n========== 语音文件 API 测试完成 ==========")
                self.showTestResult(success: true, message: "语音文件 API 测试完成！\n\n包含：\n1. 解析测试 ✅\n2. 上传测试 ✅\n\n上传结果：\nfileId: \(fileId)\ndigest: \(digest)")
                
            } catch {
                print("[AudioTest] ❌ 测试失败: \(error)")
                self.showTestResult(success: false, message: "测试失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 辅助方法（语音文件测试）
    
    /// 从 Cookie 中提取 serviceToken（用于解析测试）
    private func extractServiceToken(from cookie: String) -> String? {
        let pattern = "serviceToken=([^;]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let range = NSRange(location: 0, length: cookie.utf16.count)
        if let match = regex.firstMatch(in: cookie, options: [], range: range),
           let tokenRange = Range(match.range(at: 1), in: cookie) {
            return String(cookie[tokenRange])
        }
        return nil
    }
    
    /// 显示测试结果弹窗
    @MainActor
    private func showTestResult(success: Bool, message: String) {
        let alert = NSAlert()
        alert.messageText = success ? "测试成功" : "测试失败"
        alert.informativeText = message
        alert.alertStyle = success ? .informational : .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // MARK: - 清理

    deinit {
        print("菜单动作处理器释放")
    }
}
