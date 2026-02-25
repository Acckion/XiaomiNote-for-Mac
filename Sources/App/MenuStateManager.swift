import AppKit
import MiNoteLibrary

/// 菜单状态管理器
/// 纯状态管理类，负责：
/// - 维护 MenuState（菜单项启用/禁用/勾选状态）
/// - 实现 validateMenuItem 逻辑
/// - 监听 NotificationCenter 通知更新状态
/// - 从上下文（编辑器、窗口）读取当前状态
@MainActor
class MenuStateManager: NSObject, NSMenuItemValidation {

    // MARK: - 属性

    /// 主窗口控制器的弱引用
    private weak var mainWindowController: MainWindowController?

    /// 菜单状态
    private(set) var menuState = MenuState()

    // MARK: - 初始化

    /// 初始化菜单状态管理器
    /// - Parameter mainWindowController: 主窗口控制器
    init(mainWindowController: MainWindowController?) {
        self.mainWindowController = mainWindowController
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
            selector: #selector(handleParagraphStyleChanged(_:)),
            name: .paragraphStyleDidChange,
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

    /// 处理段落样式变化
    @objc private func handleParagraphStyleChanged(_ notification: Notification) {
        if let paragraphStyleRaw = notification.userInfo?["paragraphStyle"] as? String,
           let paragraphStyle = ParagraphStyle(rawValue: paragraphStyleRaw)
        {
            var newState = menuState
            newState.setParagraphStyle(paragraphStyle)
            menuState = newState
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
    /// 从编辑器上下文获取当前的格式状态，并更新菜单状态
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

        // 更新段落样式状态
        if let nativeEditorContext = mainWindowController?.getCurrentNativeEditorContext() {
            nativeEditorContext.forceUpdateFormats()
            let paragraphStyleString = nativeEditorContext.getCurrentParagraphStyleString()
            if let paragraphStyle = ParagraphStyle(rawValue: paragraphStyleString) {
                newState.setParagraphStyle(paragraphStyle)
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
        updateMenuItemDynamicTitle(menuItem, for: tag)
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
