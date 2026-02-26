import AppKit

/// 菜单状态管理器
/// 纯状态管理类，负责：
/// - 维护 MenuState（菜单项启用/禁用/勾选状态）
/// - 实现 validateMenuItem 逻辑
/// - 监听 NotificationCenter 通知更新状态
/// - 从 FormatStateManager 读取格式状态用于菜单勾选判断
@MainActor
class MenuStateManager: NSObject, NSMenuItemValidation {

    // MARK: - 属性

    /// 主窗口控制器的弱引用
    private weak var mainWindowController: MainWindowController?

    /// 格式状态管理器的弱引用
    private weak var formatStateManager: FormatStateManager?

    /// 当前格式状态缓存
    private var currentFormatState = FormatState()

    /// 菜单状态
    private(set) var menuState = MenuState()

    // MARK: - 初始化

    /// 初始化菜单状态管理器
    /// - Parameters:
    ///   - mainWindowController: 主窗口控制器
    ///   - formatStateManager: 格式状态管理器
    init(
        mainWindowController: MainWindowController?,
        formatStateManager: FormatStateManager?
    ) {
        self.mainWindowController = mainWindowController
        self.formatStateManager = formatStateManager
        super.init()
        setupStateObservers()
    }

    // MARK: - 公共方法

    /// 更新主窗口控制器引用
    /// - Parameter controller: 主窗口控制器
    func updateMainWindowController(_ controller: MainWindowController?) {
        mainWindowController = controller
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
        guard let tag = MenuItemTag(rawValue: menuItem.tag) else {
            return true
        }

        updateMenuStateFromContext()
        updateMenuItemCheckState(menuItem, for: tag)
        return menuState.shouldEnableMenuItem(for: tag)
    }

    // MARK: - 私有方法 - 状态管理

    /// 设置状态观察者
    /// 监听各种状态变化通知，更新菜单状态
    private func setupStateObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNoteSelectionChanged(_:)),
            name: .noteSelectionDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEditorFocusChanged(_:)),
            name: .editorFocusDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleViewModeChanged(_:)),
            name: .viewModeDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFormatStateChanged(_:)),
            name: .formatStateDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFolderVisibilityChanged(_:)),
            name: .folderVisibilityDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNoteCountVisibilityChanged(_:)),
            name: .noteCountVisibilityDidChange,
            object: nil
        )
    }

    // MARK: - 通知处理

    /// 处理笔记选中状态变化
    @objc private func handleNoteSelectionChanged(_ notification: Notification) {
        if let hasSelectedNote = notification.userInfo?["hasSelectedNote"] as? Bool {
            var newState = menuState
            newState.setNoteSelected(hasSelectedNote)
            menuState = newState
        } else {
            updateMenuStateFromContext()
        }
    }

    /// 处理编辑器焦点变化
    @objc private func handleEditorFocusChanged(_ notification: Notification) {
        if let isEditorFocused = notification.userInfo?["isEditorFocused"] as? Bool {
            var newState = menuState
            newState.setEditorFocused(isEditorFocused)
            menuState = newState
        } else {
            updateMenuStateFromContext()
        }
    }

    /// 处理视图模式变化
    @objc private func handleViewModeChanged(_ notification: Notification) {
        if let viewModeRaw = notification.userInfo?["viewMode"] as? String,
           let viewMode = ViewMode(rawValue: viewModeRaw)
        {
            var newState = menuState
            switch viewMode {
            case .list:
                newState.setViewMode(.list)
            case .gallery:
                newState.setViewMode(.gallery)
            }
            menuState = newState
        } else {
            updateMenuStateFromContext()
        }
    }

    /// 处理格式状态变化
    @objc private func handleFormatStateChanged(_ notification: Notification) {
        if let state = notification.userInfo?["state"] as? FormatState {
            currentFormatState = state
        }
    }

    /// 处理文件夹可见性变化
    @objc private func handleFolderVisibilityChanged(_ notification: Notification) {
        if let isFolderHidden = notification.userInfo?["isFolderHidden"] as? Bool {
            var newState = menuState
            newState.isFolderHidden = isFolderHidden
            menuState = newState
        }
    }

    /// 处理笔记数量显示变化
    @objc private func handleNoteCountVisibilityChanged(_ notification: Notification) {
        if let isNoteCountVisible = notification.userInfo?["isNoteCountVisible"] as? Bool {
            var newState = menuState
            newState.isNoteCountVisible = isNoteCountVisible
            menuState = newState
        }
    }

    // MARK: - 上下文状态更新

    /// 从当前上下文更新菜单状态
    /// 从编辑器上下文获取当前的非格式状态，并更新菜单状态
    /// 格式状态由 FormatStateManager 通过通知更新
    private func updateMenuStateFromContext() {
        var newState = menuState

        // 更新笔记选中状态
        let hasSelectedNote = mainWindowController?.coordinator.noteListState.selectedNote != nil
        newState.hasSelectedNote = hasSelectedNote

        // 更新编辑器焦点状态
        var isEditorFocused = false
        if let window = NSApp.mainWindow,
           let firstResponder = window.firstResponder
        {
            isEditorFocused = firstResponder is NSTextView
        }

        // 有选中笔记时，允许格式菜单操作
        if hasSelectedNote {
            isEditorFocused = true
        }
        newState.isEditorFocused = isEditorFocused

        // 更新视图模式状态
        let currentViewMode = ViewOptionsManager.shared.viewMode
        switch currentViewMode {
        case .list:
            newState.currentViewMode = .list
        case .gallery:
            newState.currentViewMode = .gallery
        }

        // 更新文件夹隐藏状态
        if let window = NSApp.mainWindow,
           let splitViewController = window.contentViewController as? NSSplitViewController,
           !splitViewController.splitViewItems.isEmpty
        {
            let uiCollapsedState = splitViewController.splitViewItems[0].isCollapsed
            newState.isFolderHidden = uiCollapsedState
        }

        // 更新笔记数量显示状态
        newState.isNoteCountVisible = ViewOptionsManager.shared.showNoteCount

        menuState = newState
    }

    /// 更新菜单项的勾选状态
    /// 非格式项由 MenuState 判断，格式项由 currentFormatState 判断
    /// - Parameters:
    ///   - menuItem: 菜单项
    ///   - tag: 菜单项标签
    private func updateMenuItemCheckState(_ menuItem: NSMenuItem, for tag: MenuItemTag) {
        let shouldCheck: Bool = if let formatCheck = checkFormatState(for: tag) {
            formatCheck
        } else {
            menuState.shouldCheckMenuItem(for: tag)
        }
        menuItem.state = shouldCheck ? .on : .off
        updateMenuItemDynamicTitle(menuItem, for: tag)
    }

    /// 检查格式相关的菜单项勾选状态
    /// 从 currentFormatState 读取段落格式、字符格式和对齐状态
    /// - Parameter tag: 菜单项标签
    /// - Returns: 勾选状态，非格式项返回 nil
    private func checkFormatState(for tag: MenuItemTag) -> Bool? {
        // 段落格式
        if let paragraphFormat = ParagraphFormat.from(tag: tag) {
            return currentFormatState.paragraphFormat == paragraphFormat
        }

        // 引用块
        if tag == .blockQuote {
            return currentFormatState.isQuote
        }

        // 字符格式
        switch tag {
        case .bold: return currentFormatState.isBold
        case .italic: return currentFormatState.isItalic
        case .underline: return currentFormatState.isUnderline
        case .strikethrough: return currentFormatState.isStrikethrough
        case .highlight: return currentFormatState.isHighlight
        default: break
        }

        // 对齐格式
        if let alignmentFormat = AlignmentFormat.from(tag: tag) {
            return currentFormatState.alignment == alignmentFormat
        }

        return nil
    }

    /// 更新菜单项的动态标题
    /// 根据当前状态更新菜单项标题（如"隐藏文件夹"/"显示文件夹"）
    /// - Parameters:
    ///   - menuItem: 菜单项
    ///   - tag: 菜单项标签
    private func updateMenuItemDynamicTitle(_ menuItem: NSMenuItem, for tag: MenuItemTag) {
        switch tag {
        case .hideFolders:
            menuItem.title = menuState.isFolderHidden ? "显示文件夹" : "隐藏文件夹"
        case .showNoteCount:
            menuItem.title = menuState.isNoteCountVisible ? "隐藏笔记数量" : "显示笔记数量"
        default:
            break
        }
    }

    // MARK: - 清理

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
