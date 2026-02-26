import AppKit

/// 菜单管理器
/// 负责应用程序菜单的设置和管理
/// 按照 Apple Notes 标准实现完整的 macOS 原生菜单体验
@MainActor
class MenuManager {

    // MARK: - 属性

    /// 应用程序委托的弱引用（用于菜单动作的目标）
    weak var appDelegate: AppDelegate?

    /// 主窗口控制器的弱引用
    weak var mainWindowController: MainWindowController?

    /// 菜单状态
    /// 用于管理菜单项的启用/禁用和勾选状态
    private(set) var menuState = MenuState()

    /// 菜单状态变化回调
    var onMenuStateChanged: ((MenuState) -> Void)?

    /// 状态变化观察者
    private var stateObserver: NSObjectProtocol?

    /// 格式状态变化观察者
    private var formatStateObserver: NSObjectProtocol?

    // MARK: - 初始化

    /// 初始化菜单管理器
    /// - Parameters:
    ///   - appDelegate: 应用程序委托
    ///   - mainWindowController: 主窗口控制器
    init(appDelegate: AppDelegate? = nil, mainWindowController: MainWindowController? = nil) {
        self.appDelegate = appDelegate
        self.mainWindowController = mainWindowController
        setupStateObserver()
    }

    // MARK: - 公共方法

    /// 更新应用程序委托引用
    /// - Parameters:
    ///   - appDelegate: 应用程序委托
    ///   - mainWindowController: 主窗口控制器
    func updateReferences(appDelegate: AppDelegate?, mainWindowController: MainWindowController?) {
        // 更新弱引用
        self.appDelegate = appDelegate
        self.mainWindowController = mainWindowController
    }

    /// 更新菜单状态
    /// - Parameter newState: 新的菜单状态
    func updateMenuState(_ newState: MenuState) {
        let oldState = menuState
        menuState = newState

        // 如果状态发生变化，通知回调
        if oldState != newState {
            onMenuStateChanged?(newState)
            newState.postChangeNotification()
        }
    }

    /// 更新笔记选中状态
    /// - Parameter selected: 是否有选中笔记
    func updateNoteSelection(_ selected: Bool) {
        var newState = menuState
        newState.setNoteSelected(selected)
        updateMenuState(newState)
    }

    /// 更新编辑器焦点状态
    /// - Parameter focused: 编辑器是否有焦点
    func updateEditorFocus(_ focused: Bool) {
        var newState = menuState
        newState.setEditorFocused(focused)
        updateMenuState(newState)
    }

    /// 更新视图模式
    /// - Parameter mode: 当前视图模式
    func updateViewMode(_ mode: MenuViewMode) {
        var newState = menuState
        newState.setViewMode(mode)
        updateMenuState(newState)
    }

    // MARK: - 格式菜单状态更新

    /// 更新格式菜单状态
    /// 根据 FormatState 更新菜单栏中格式菜单项的勾选状态
    /// - Parameter state: 格式状态
    func updateFormatMenuState(_ state: FormatState) {
        // 更新段落格式菜单项
        updateParagraphFormatMenuItems(state.paragraphFormat)

        // 更新对齐格式菜单项
        updateAlignmentMenuItems(state.alignment)

        // 更新字符格式菜单项
        updateCharacterFormatMenuItems(state)

        // 更新引用块菜单项
        updateQuoteMenuItem(state.isQuote)
    }

    /// 更新段落格式菜单项
    /// - Parameter format: 当前段落格式
    private func updateParagraphFormatMenuItems(_ format: ParagraphFormat) {
        guard let mainMenu = NSApp.mainMenu,
              let formatMenu = mainMenu.item(withTitle: "格式")?.submenu
        else {
            return
        }

        // 遍历所有段落格式菜单项，设置勾选状态
        for paragraphFormat in ParagraphFormat.allCases {
            if let menuItem = findMenuItem(for: paragraphFormat, in: formatMenu) {
                let shouldCheck = (paragraphFormat == format)
                menuItem.state = shouldCheck ? .on : .off
            }
        }
    }

    /// 更新对齐格式菜单项
    /// - Parameter alignment: 当前对齐格式
    private func updateAlignmentMenuItems(_ alignment: AlignmentFormat) {
        guard let mainMenu = NSApp.mainMenu,
              let formatMenu = mainMenu.item(withTitle: "格式")?.submenu,
              let textMenu = formatMenu.item(withTitle: "文本")?.submenu
        else {
            return
        }

        // 更新左对齐
        if let alignLeftItem = textMenu.item(withTag: MenuItemTag.alignLeft.rawValue) {
            alignLeftItem.state = (alignment == .left) ? .on : .off
        }

        // 更新居中
        if let alignCenterItem = textMenu.item(withTag: MenuItemTag.alignCenter.rawValue) {
            alignCenterItem.state = (alignment == .center) ? .on : .off
        }

        // 更新右对齐
        if let alignRightItem = textMenu.item(withTag: MenuItemTag.alignRight.rawValue) {
            alignRightItem.state = (alignment == .right) ? .on : .off
        }
    }

    /// 更新字符格式菜单项
    /// - Parameter state: 格式状态
    private func updateCharacterFormatMenuItems(_ state: FormatState) {
        guard let mainMenu = NSApp.mainMenu,
              let formatMenu = mainMenu.item(withTitle: "格式")?.submenu,
              let fontMenu = formatMenu.item(withTitle: "字体")?.submenu
        else {
            return
        }

        // 更新粗体
        if let boldItem = fontMenu.item(withTag: MenuItemTag.bold.rawValue) {
            boldItem.state = state.isBold ? .on : .off
        }

        // 更新斜体
        if let italicItem = fontMenu.item(withTag: MenuItemTag.italic.rawValue) {
            italicItem.state = state.isItalic ? .on : .off
        }

        // 更新下划线
        if let underlineItem = fontMenu.item(withTag: MenuItemTag.underline.rawValue) {
            underlineItem.state = state.isUnderline ? .on : .off
        }

        // 更新删除线
        if let strikethroughItem = fontMenu.item(withTag: MenuItemTag.strikethrough.rawValue) {
            strikethroughItem.state = state.isStrikethrough ? .on : .off
        }

        // 更新高亮
        if let highlightItem = fontMenu.item(withTag: MenuItemTag.highlight.rawValue) {
            highlightItem.state = state.isHighlight ? .on : .off
        }
    }

    /// 更新引用块菜单项
    /// - Parameter isQuote: 是否为引用块
    private func updateQuoteMenuItem(_ isQuote: Bool) {
        guard let mainMenu = NSApp.mainMenu,
              let formatMenu = mainMenu.item(withTitle: "格式")?.submenu
        else {
            return
        }

        // 更新块引用菜单项
        if let blockQuoteItem = formatMenu.item(withTag: MenuItemTag.blockQuote.rawValue) {
            blockQuoteItem.state = isQuote ? .on : .off
        }
    }

    // MARK: - 格式菜单辅助方法

    /// 查找段落格式对应的菜单项
    /// - Parameters:
    ///   - format: 段落格式
    ///   - menu: 菜单
    /// - Returns: 菜单项
    private func findMenuItem(for format: ParagraphFormat, in menu: NSMenu) -> NSMenuItem? {
        menu.item(withTag: format.menuItemTag.rawValue)
    }

    // MARK: - 注册表驱动构建

    /// 从 CommandRegistry 构建菜单项
    /// 所有注册表驱动的菜单项统一通过此方法创建
    func buildMenuItem(for tag: MenuItemTag) -> NSMenuItem {
        guard let entry = CommandRegistry.shared.entry(for: tag) else {
            fatalError("未注册的菜单项: \(tag)")
        }
        let item = NSMenuItem(
            title: entry.title,
            action: #selector(AppDelegate.performCommand(_:)),
            keyEquivalent: entry.keyEquivalent
        )
        item.keyEquivalentModifierMask = entry.modifiers
        item.tag = tag.rawValue
        if let symbolName = entry.symbolName {
            setMenuItemIcon(item, symbolName: symbolName)
        }
        return item
    }

    // MARK: - 私有方法 - 图标设置

    /// 为菜单项设置 SF Symbols 图标
    /// - Parameters:
    ///   - menuItem: 菜单项
    ///   - symbolName: SF Symbols 图标名称
    func setMenuItemIcon(_ menuItem: NSMenuItem, symbolName: String) {
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            image.size = NSSize(width: 16, height: 16)
            menuItem.image = image
        }
    }

    // MARK: - 私有方法 - 状态观察

    /// 设置状态观察者
    private func setupStateObserver() {
        stateObserver = NotificationCenter.default.addObserver(
            forName: MenuState.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let state = notification.userInfo?["state"] as? MenuState
            else {
                return
            }
            // 状态变化时可以在这里执行额外的处理
            _ = state
        }

        // 监听格式状态变化通知
        formatStateObserver = NotificationCenter.default.addObserver(
            forName: .formatStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            // 从通知中提取格式状态
            if let state = notification.userInfo?["state"] as? FormatState {
                updateFormatMenuState(state)
            }
        }
    }

    /// 设置应用程序菜单
    func setupApplicationMenu() {
        // 获取主菜单
        guard let mainMenu = NSApp.mainMenu else {
            return
        }

        // 清除现有菜单项（如果有）
        mainMenu.items.removeAll()

        // 首先创建应用程序菜单
        setupAppMenu(in: mainMenu)

        // 设置其他菜单项
        setupFileMenu(in: mainMenu)
        setupEditMenu(in: mainMenu)
        setupFormatMenu(in: mainMenu)
        setupViewMenu(in: mainMenu)
        setupWindowMenu(in: mainMenu)
        setupHelpMenu(in: mainMenu)
    }

    // MARK: - 私有方法

    /// 设置应用程序菜单
    /// 按照 Apple Notes 标准实现完整的应用程序菜单
    private func setupAppMenu(in mainMenu: NSMenu) {
        // 创建应用程序菜单项
        let appMenuItem = NSMenuItem()
        appMenuItem.title = "小米笔记"
        let appMenu = NSMenu(title: "小米笔记")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 1.1 添加"关于小米笔记"菜单项
        // 使用标准 NSApplication 选择器
        let aboutItem = NSMenuItem(
            title: "关于小米笔记",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(aboutItem, symbolName: "info.circle")
        appMenu.addItem(aboutItem)

        // 1.2 添加分隔线
        appMenu.addItem(NSMenuItem.separator())

        // 1.3 设置（注册表驱动）
        let settingsItem = buildMenuItem(for: .showSettings)
        appMenu.addItem(settingsItem)

        // 1.4 添加分隔线
        appMenu.addItem(NSMenuItem.separator())

        // 1.5 添加"隐藏小米笔记"菜单项（⌘H）
        // 使用标准 NSApplication 选择器
        let hideItem = NSMenuItem(
            title: "隐藏小米笔记",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.keyEquivalentModifierMask = [.command]
        setMenuItemIcon(hideItem, symbolName: "eye.slash")
        appMenu.addItem(hideItem)

        // 1.6 添加"隐藏其他"菜单项（⌥⌘H）
        // 使用标准 NSApplication 选择器
        let hideOthersItem = NSMenuItem(
            title: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        setMenuItemIcon(hideOthersItem, symbolName: "eye.slash.fill")
        appMenu.addItem(hideOthersItem)

        // 1.7 添加"全部显示"菜单项
        // 使用标准 NSApplication 选择器
        let showAllItem = NSMenuItem(
            title: "全部显示",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(showAllItem, symbolName: "eye")
        appMenu.addItem(showAllItem)

        // 1.8 添加分隔线
        appMenu.addItem(NSMenuItem.separator())

        // 1.9 添加"退出小米笔记"菜单项（⌘Q）
        // 使用标准 NSApplication 选择器
        let quitItem = NSMenuItem(
            title: "退出小米笔记",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        setMenuItemIcon(quitItem, symbolName: "power")
        appMenu.addItem(quitItem)
    }

    /// 设置文件菜单
    /// 按照 Apple Notes 标准实现完整的文件菜单
    private func setupFileMenu(in mainMenu: NSMenu) {
        // 创建文件菜单
        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = "文件"
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // ========== 新建部分 ==========

        fileMenu.addItem(buildMenuItem(for: .newNote))
        fileMenu.addItem(buildMenuItem(for: .newFolder))
        fileMenu.addItem(buildMenuItem(for: .newSmartFolder))

        fileMenu.addItem(NSMenuItem.separator())

        fileMenu.addItem(buildMenuItem(for: .share))

        fileMenu.addItem(NSMenuItem.separator())

        // 关闭（系统 selector）
        let closeItem = NSMenuItem(
            title: "关闭",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.keyEquivalentModifierMask = [.command]
        setMenuItemIcon(closeItem, symbolName: "xmark")
        fileMenu.addItem(closeItem)

        fileMenu.addItem(NSMenuItem.separator())

        // ========== 导入导出部分 ==========

        fileMenu.addItem(buildMenuItem(for: .importNotes))
        fileMenu.addItem(buildMenuItem(for: .importMarkdown))

        fileMenu.addItem(NSMenuItem.separator())

        let exportMenuItem = NSMenuItem(
            title: "导出为",
            action: nil,
            keyEquivalent: ""
        )
        exportMenuItem.submenu = createExportSubmenu()
        setMenuItemIcon(exportMenuItem, symbolName: "square.and.arrow.up.on.square")
        fileMenu.addItem(exportMenuItem)

        fileMenu.addItem(NSMenuItem.separator())

        // ========== 笔记操作部分 ==========

        fileMenu.addItem(buildMenuItem(for: .toggleStar))

        let addToPrivateNotesItem = buildMenuItem(for: .addToPrivateNotes)
        addToPrivateNotesItem.isEnabled = false
        fileMenu.addItem(addToPrivateNotesItem)

        fileMenu.addItem(buildMenuItem(for: .duplicateNote))

        fileMenu.addItem(NSMenuItem.separator())

        // 打印（系统 selector）
        let printItem = NSMenuItem(
            title: "打印...",
            action: #selector(NSView.printView(_:)),
            keyEquivalent: "p"
        )
        printItem.keyEquivalentModifierMask = [.command]
        printItem.tag = MenuItemTag.printNote.rawValue
        setMenuItemIcon(printItem, symbolName: "printer")
        fileMenu.addItem(printItem)
    }

    /// 创建"导出为"子菜单
    private func createExportSubmenu() -> NSMenu {
        let exportMenu = NSMenu(title: "导出为")
        exportMenu.addItem(buildMenuItem(for: .exportAsPDF))
        exportMenu.addItem(buildMenuItem(for: .exportAsMarkdown))
        exportMenu.addItem(buildMenuItem(for: .exportAsPlainText))
        return exportMenu
    }

    /// 设置视图菜单
    /// 按照 Apple Notes 标准实现完整的显示菜单
    private func setupViewMenu(in mainMenu: NSMenu) {
        // 创建显示菜单
        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = "显示"
        let viewMenu = NSMenu(title: "显示")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // 视图模式（注册表驱动）
        viewMenu.addItem(buildMenuItem(for: .listView))
        viewMenu.addItem(buildMenuItem(for: .galleryView))

        viewMenu.addItem(NSMenuItem.separator())

        // 最近笔记（待实现）
        let recentNotesItem = NSMenuItem(
            title: "最近笔记",
            action: nil,
            keyEquivalent: ""
        )
        recentNotesItem.isEnabled = false
        setMenuItemIcon(recentNotesItem, symbolName: "clock")
        viewMenu.addItem(recentNotesItem)

        viewMenu.addItem(NSMenuItem.separator())

        // 文件夹选项（注册表驱动）
        viewMenu.addItem(buildMenuItem(for: .hideFolders))
        viewMenu.addItem(buildMenuItem(for: .showNoteCount))

        viewMenu.addItem(NSMenuItem.separator())

        // 附件视图（待实现）
        let attachmentViewItem = NSMenuItem(
            title: "附件视图",
            action: nil,
            keyEquivalent: ""
        )
        attachmentViewItem.isEnabled = false
        setMenuItemIcon(attachmentViewItem, symbolName: "paperclip")
        viewMenu.addItem(attachmentViewItem)

        viewMenu.addItem(NSMenuItem.separator())

        // 显示附件浏览器（待实现）
        let showAttachmentBrowserItem = NSMenuItem(
            title: "显示附件浏览器",
            action: nil,
            keyEquivalent: ""
        )
        showAttachmentBrowserItem.isEnabled = false
        setMenuItemIcon(showAttachmentBrowserItem, symbolName: "photo.on.rectangle")
        viewMenu.addItem(showAttachmentBrowserItem)

        // 在笔记中显示（待实现）
        let showInNoteItem = NSMenuItem(
            title: "在笔记中显示",
            action: nil,
            keyEquivalent: ""
        )
        showInNoteItem.isEnabled = false
        setMenuItemIcon(showInNoteItem, symbolName: "doc.text.magnifyingglass")
        viewMenu.addItem(showInNoteItem)

        viewMenu.addItem(NSMenuItem.separator())

        // 缩放（注册表驱动）
        viewMenu.addItem(buildMenuItem(for: .zoomIn))
        viewMenu.addItem(buildMenuItem(for: .zoomOut))
        viewMenu.addItem(buildMenuItem(for: .actualSize))

        viewMenu.addItem(NSMenuItem.separator())

        // 工具栏（系统 selector）
        let toggleToolbarItem = NSMenuItem(
            title: "隐藏工具栏",
            action: #selector(NSWindow.toggleToolbarShown(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(toggleToolbarItem, symbolName: "menubar.rectangle")
        viewMenu.addItem(toggleToolbarItem)

        let customizeToolbarItem = NSMenuItem(
            title: "自定义工具栏...",
            action: #selector(NSWindow.runToolbarCustomizationPalette(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(customizeToolbarItem, symbolName: "slider.horizontal.3")
        viewMenu.addItem(customizeToolbarItem)

        // 全屏幕（系统 selector）
        let toggleFullScreenItem = NSMenuItem(
            title: "进入全屏幕",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        toggleFullScreenItem.keyEquivalentModifierMask = [.control, .command]
        setMenuItemIcon(toggleFullScreenItem, symbolName: "arrow.up.left.and.arrow.down.right")
        viewMenu.addItem(toggleFullScreenItem)

        viewMenu.addItem(NSMenuItem.separator())

        // 调试菜单项（注册表驱动）
        viewMenu.addItem(buildMenuItem(for: .showDebugSettings))
        viewMenu.addItem(buildMenuItem(for: .testAudioFileAPI))
    }

    /// 设置窗口菜单
    /// 按照 Apple Notes 标准实现完整的窗口菜单
    /// 使用系统窗口菜单管理，让系统自动管理窗口列表
    private func setupWindowMenu(in mainMenu: NSMenu) {
        // 创建窗口菜单
        let windowMenuItem = NSMenuItem()
        windowMenuItem.title = "窗口"
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // 13.1 注册系统窗口菜单，让系统自动管理窗口列表
        NSApp.windowsMenu = windowMenu

        // 13.2 添加"最小化"菜单项（⌘M）
        // 使用标准 NSWindow 选择器 performMiniaturize:
        let minimizeItem = NSMenuItem(
            title: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        minimizeItem.keyEquivalentModifierMask = [.command]
        minimizeItem.tag = MenuItemTag.minimize.rawValue
        setMenuItemIcon(minimizeItem, symbolName: "minus.square")
        windowMenu.addItem(minimizeItem)

        // 13.3 添加"缩放"菜单项
        // 使用标准 NSWindow 选择器 performZoom:
        let zoomItem = NSMenuItem(
            title: "缩放",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        zoomItem.tag = MenuItemTag.zoom.rawValue
        setMenuItemIcon(zoomItem, symbolName: "arrow.up.left.and.arrow.down.right")
        windowMenu.addItem(zoomItem)

        // 13.4 填充和居中（注册表驱动）
        windowMenu.addItem(buildMenuItem(for: .fill))
        windowMenu.addItem(buildMenuItem(for: .center))

        windowMenu.addItem(NSMenuItem.separator())

        // 13.7 添加"移动与调整大小"子菜单（系统标准）
        let moveAndResizeMenuItem = NSMenuItem(
            title: "移动与调整大小",
            action: nil,
            keyEquivalent: ""
        )
        moveAndResizeMenuItem.submenu = createMoveAndResizeSubmenu()
        setMenuItemIcon(moveAndResizeMenuItem, symbolName: "arrow.up.and.down.and.arrow.left.and.right")
        windowMenu.addItem(moveAndResizeMenuItem)

        // 13.8 添加"全屏幕平铺"子菜单（系统标准）
        let fullScreenTileMenuItem = NSMenuItem(
            title: "全屏幕平铺",
            action: nil,
            keyEquivalent: ""
        )
        fullScreenTileMenuItem.submenu = createFullScreenTileSubmenu()
        setMenuItemIcon(fullScreenTileMenuItem, symbolName: "rectangle.split.2x1")
        windowMenu.addItem(fullScreenTileMenuItem)

        // 13.9 添加分隔线
        windowMenu.addItem(NSMenuItem.separator())

        // 在新窗口中打开笔记（注册表驱动）
        windowMenu.addItem(buildMenuItem(for: .openNoteInNewWindow))

        // 13.11 添加分隔线
        windowMenu.addItem(NSMenuItem.separator())
        // 13.12 系统会自动在此处添加打开的窗口列表
        // 13.13 系统会自动添加分隔线

        // 13.14 添加"前置全部窗口"菜单项
        // 使用标准 NSApplication 选择器 arrangeInFront:
        let bringAllToFrontItem = NSMenuItem(
            title: "前置全部窗口",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        bringAllToFrontItem.tag = MenuItemTag.bringAllToFront.rawValue
        setMenuItemIcon(bringAllToFrontItem, symbolName: "rectangle.stack")
        windowMenu.addItem(bringAllToFrontItem)

        // 添加调试工具子菜单
        #if DEBUG
            windowMenu.addItem(NSMenuItem.separator())
            let debugMenuItem = NSMenuItem(
                title: "调试工具",
                action: nil,
                keyEquivalent: ""
            )
            debugMenuItem.submenu = createDebugToolsSubmenu()
            setMenuItemIcon(debugMenuItem, symbolName: "wrench.and.screwdriver")
            windowMenu.addItem(debugMenuItem)
        #endif
    }

    /// 创建"移动与调整大小"子菜单
    private func createMoveAndResizeSubmenu() -> NSMenu {
        let moveAndResizeMenu = NSMenu(title: "移动与调整大小")

        moveAndResizeMenu.addItem(buildMenuItem(for: .moveToLeftHalf))
        moveAndResizeMenu.addItem(buildMenuItem(for: .moveToRightHalf))

        moveAndResizeMenu.addItem(NSMenuItem.separator())

        moveAndResizeMenu.addItem(buildMenuItem(for: .moveToTopHalf))
        moveAndResizeMenu.addItem(buildMenuItem(for: .moveToBottomHalf))

        moveAndResizeMenu.addItem(NSMenuItem.separator())

        moveAndResizeMenu.addItem(buildMenuItem(for: .maximizeWindow))
        moveAndResizeMenu.addItem(buildMenuItem(for: .restoreWindow))

        return moveAndResizeMenu
    }

    /// 创建"全屏幕平铺"子菜单
    private func createFullScreenTileSubmenu() -> NSMenu {
        let fullScreenTileMenu = NSMenu(title: "全屏幕平铺")
        fullScreenTileMenu.addItem(buildMenuItem(for: .tileToLeft))
        fullScreenTileMenu.addItem(buildMenuItem(for: .tileToRight))
        return fullScreenTileMenu
    }

    /// 创建"调试工具"子菜单
    private func createDebugToolsSubmenu() -> NSMenu {
        let debugMenu = NSMenu(title: "调试工具")
        debugMenu.addItem(buildMenuItem(for: .showDebugSettings))
        return debugMenu
    }

    /// 设置帮助菜单
    private func setupHelpMenu(in mainMenu: NSMenu) {
        // 查找或创建帮助菜单
        let helpMenu: NSMenu
        if let existingHelpMenu = mainMenu.items.first(where: { $0.title == "帮助" })?.submenu {
            helpMenu = existingHelpMenu
        } else {
            let helpMenuItem = NSMenuItem()
            helpMenuItem.title = "帮助"
            helpMenu = NSMenu(title: "帮助")
            helpMenuItem.submenu = helpMenu
            mainMenu.addItem(helpMenuItem)
        }

        // 帮助（注册表驱动）
        helpMenu.addItem(buildMenuItem(for: .showHelp))
    }

    // MARK: - 清理

    /// 移除状态观察者
    /// 在对象释放前调用此方法清理资源
    func cleanup() {
        if let observer = stateObserver {
            NotificationCenter.default.removeObserver(observer)
            stateObserver = nil
        }
    }

    deinit {
        // 菜单管理器释放
    }
}
