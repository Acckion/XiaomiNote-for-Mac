import AppKit
import MiNoteLibrary

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

    /// 更新段落样式
    /// - Parameter style: 当前段落样式
    func updateParagraphStyle(_ style: ParagraphStyle) {
        var newState = menuState
        newState.setParagraphStyle(style)
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

        // 同步更新 MenuState
        var newMenuState = menuState
        newMenuState.currentParagraphStyle = convertToParagraphStyle(state.paragraphFormat)
        newMenuState.isBold = state.isBold
        newMenuState.isItalic = state.isItalic
        newMenuState.isUnderline = state.isUnderline
        newMenuState.isStrikethrough = state.isStrikethrough
        newMenuState.isHighlight = state.isHighlight
        newMenuState.isBlockQuoteEnabled = state.isQuote
        newMenuState.textAlignment = convertToNSTextAlignment(state.alignment)
        menuState = newMenuState
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
        let tag: MenuItemTag = switch format {
        case .heading1:
            .heading
        case .heading2:
            .subheading
        case .heading3:
            .subtitle
        case .body:
            .bodyText
        case .bulletList:
            .unorderedList
        case .numberedList:
            .orderedList
        case .checkbox:
            .checklist
        }
        return menu.item(withTag: tag.rawValue)
    }

    /// 将 ParagraphFormat 转换为 ParagraphStyle
    /// - Parameter format: 段落格式
    /// - Returns: 段落样式
    private func convertToParagraphStyle(_ format: ParagraphFormat) -> ParagraphStyle {
        switch format {
        case .heading1:
            .heading
        case .heading2:
            .subheading
        case .heading3:
            .subtitle
        case .body:
            .body
        case .bulletList:
            .unorderedList
        case .numberedList:
            .orderedList
        case .checkbox:
            .body // 复选框在 MenuState 中没有对应项，使用正文
        }
    }

    /// 将 AlignmentFormat 转换为 NSTextAlignment
    /// - Parameter alignment: 对齐格式
    /// - Returns: NSTextAlignment
    private func convertToNSTextAlignment(_ alignment: AlignmentFormat) -> NSTextAlignment {
        switch alignment {
        case .left:
            .left
        case .center:
            .center
        case .right:
            .right
        }
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

        // 1.3 添加"设置..."菜单项（⌘,）
        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(AppDelegate.showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = appDelegate
        setMenuItemIcon(settingsItem, symbolName: "gearshape")
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

        // 2.1 添加"新建笔记"菜单项（⌘N）
        let newNoteItem = NSMenuItem(
            title: "新建笔记",
            action: #selector(AppDelegate.createNewNote(_:)),
            keyEquivalent: "n"
        )
        newNoteItem.keyEquivalentModifierMask = [.command]
        newNoteItem.tag = MenuItemTag.newNote.rawValue
        setMenuItemIcon(newNoteItem, symbolName: "square.and.pencil")
        fileMenu.addItem(newNoteItem)

        // 2.2 添加"新建文件夹"菜单项（⇧⌘N）
        let newFolderItem = NSMenuItem(
            title: "新建文件夹",
            action: #selector(AppDelegate.createNewFolder(_:)),
            keyEquivalent: "n"
        )
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        newFolderItem.tag = MenuItemTag.newFolder.rawValue
        setMenuItemIcon(newFolderItem, symbolName: "folder.badge.plus")
        fileMenu.addItem(newFolderItem)

        // 2.3 添加"新建智能文件夹"菜单项
        let newSmartFolderItem = NSMenuItem(
            title: "新建智能文件夹",
            action: #selector(AppDelegate.createSmartFolder(_:)),
            keyEquivalent: ""
        )
        newSmartFolderItem.tag = MenuItemTag.newSmartFolder.rawValue
        setMenuItemIcon(newSmartFolderItem, symbolName: "folder.badge.gearshape")
        fileMenu.addItem(newSmartFolderItem)

        // 2.4 添加分隔线
        fileMenu.addItem(NSMenuItem.separator())

        // 2.5 添加"共享"菜单项
        let shareItem = NSMenuItem(
            title: "共享",
            action: #selector(AppDelegate.shareNote(_:)),
            keyEquivalent: ""
        )
        shareItem.tag = MenuItemTag.share.rawValue
        setMenuItemIcon(shareItem, symbolName: "square.and.arrow.up")
        fileMenu.addItem(shareItem)

        // 2.6 添加分隔线
        fileMenu.addItem(NSMenuItem.separator())

        // 2.7 添加"关闭"菜单项（⌘W）
        // 使用标准 NSWindow 选择器 performClose:
        let closeItem = NSMenuItem(
            title: "关闭",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.keyEquivalentModifierMask = [.command]
        setMenuItemIcon(closeItem, symbolName: "xmark")
        fileMenu.addItem(closeItem)

        // 2.8 添加分隔线
        fileMenu.addItem(NSMenuItem.separator())

        // ========== 导入导出部分 ==========

        // 2.9 添加"导入至笔记..."菜单项
        let importNotesItem = NSMenuItem(
            title: "导入至笔记...",
            action: #selector(AppDelegate.importNotes(_:)),
            keyEquivalent: ""
        )
        importNotesItem.tag = MenuItemTag.importNotes.rawValue
        setMenuItemIcon(importNotesItem, symbolName: "square.and.arrow.down")
        fileMenu.addItem(importNotesItem)

        // 2.10 添加"导入 Markdown..."菜单项
        let importMarkdownItem = NSMenuItem(
            title: "导入 Markdown...",
            action: #selector(AppDelegate.importMarkdown(_:)),
            keyEquivalent: ""
        )
        importMarkdownItem.tag = MenuItemTag.importMarkdown.rawValue
        setMenuItemIcon(importMarkdownItem, symbolName: "doc.text")
        fileMenu.addItem(importMarkdownItem)

        // 2.11 添加分隔线
        fileMenu.addItem(NSMenuItem.separator())

        // 2.12 添加"导出为"子菜单
        let exportMenuItem = NSMenuItem(
            title: "导出为",
            action: nil,
            keyEquivalent: ""
        )
        exportMenuItem.submenu = createExportSubmenu()
        setMenuItemIcon(exportMenuItem, symbolName: "square.and.arrow.up.on.square")
        fileMenu.addItem(exportMenuItem)

        // 2.14 添加分隔线
        fileMenu.addItem(NSMenuItem.separator())

        // ========== 笔记操作部分 ==========

        // 2.15 添加"置顶笔记"菜单项
        let toggleStarItem = NSMenuItem(
            title: "置顶笔记",
            action: #selector(AppDelegate.toggleStarNote(_:)),
            keyEquivalent: ""
        )
        toggleStarItem.tag = MenuItemTag.toggleStar.rawValue
        setMenuItemIcon(toggleStarItem, symbolName: "pin")
        fileMenu.addItem(toggleStarItem)

        // 2.16 添加"添加到私密笔记"菜单项（待实现）
        let addToPrivateNotesItem = NSMenuItem(
            title: "添加到私密笔记",
            action: #selector(AppDelegate.addToPrivateNotes(_:)),
            keyEquivalent: ""
        )
        addToPrivateNotesItem.tag = MenuItemTag.addToPrivateNotes.rawValue
        // 标记为待实现
        addToPrivateNotesItem.isEnabled = false
        setMenuItemIcon(addToPrivateNotesItem, symbolName: "lock")
        fileMenu.addItem(addToPrivateNotesItem)

        // 2.17 添加"复制笔记"菜单项
        let duplicateNoteItem = NSMenuItem(
            title: "复制笔记",
            action: #selector(AppDelegate.duplicateNote(_:)),
            keyEquivalent: ""
        )
        duplicateNoteItem.tag = MenuItemTag.duplicateNote.rawValue
        setMenuItemIcon(duplicateNoteItem, symbolName: "doc.on.doc")
        fileMenu.addItem(duplicateNoteItem)

        // 2.18 添加分隔线
        fileMenu.addItem(NSMenuItem.separator())

        // 2.19 添加"打印..."菜单项（⌘P）
        // 使用标准 NSResponder 选择器 print:
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

        // 导出为 PDF
        let exportPDFItem = NSMenuItem(
            title: "PDF...",
            action: #selector(AppDelegate.exportAsPDF(_:)),
            keyEquivalent: ""
        )
        exportPDFItem.tag = MenuItemTag.exportAsPDF.rawValue
        setMenuItemIcon(exportPDFItem, symbolName: "doc.richtext")
        exportMenu.addItem(exportPDFItem)

        // 导出为 Markdown
        let exportMarkdownItem = NSMenuItem(
            title: "Markdown...",
            action: #selector(AppDelegate.exportAsMarkdown(_:)),
            keyEquivalent: ""
        )
        exportMarkdownItem.tag = MenuItemTag.exportAsMarkdown.rawValue
        setMenuItemIcon(exportMarkdownItem, symbolName: "doc.text")
        exportMenu.addItem(exportMarkdownItem)

        // 导出为纯文本
        let exportPlainTextItem = NSMenuItem(
            title: "纯文本...",
            action: #selector(AppDelegate.exportAsPlainText(_:)),
            keyEquivalent: ""
        )
        exportPlainTextItem.tag = MenuItemTag.exportAsPlainText.rawValue
        setMenuItemIcon(exportPlainTextItem, symbolName: "doc.plaintext")
        exportMenu.addItem(exportPlainTextItem)

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

        // 8.1 添加"列表视图"菜单项（支持单选勾选状态）
        let listViewItem = NSMenuItem(
            title: "列表视图",
            action: #selector(AppDelegate.setListView(_:)),
            keyEquivalent: ""
        )
        listViewItem.tag = MenuItemTag.listView.rawValue
        setMenuItemIcon(listViewItem, symbolName: "list.bullet")
        viewMenu.addItem(listViewItem)

        // 8.2 添加"画廊视图"菜单项（支持单选勾选状态）
        let galleryViewItem = NSMenuItem(
            title: "画廊视图",
            action: #selector(AppDelegate.setGalleryView(_:)),
            keyEquivalent: ""
        )
        galleryViewItem.tag = MenuItemTag.galleryView.rawValue
        setMenuItemIcon(galleryViewItem, symbolName: "square.grid.2x2")
        viewMenu.addItem(galleryViewItem)

        // 8.4 添加分隔线
        viewMenu.addItem(NSMenuItem.separator())

        // 8.5 添加"最近笔记"菜单项（待实现标记）
        let recentNotesItem = NSMenuItem(
            title: "最近笔记",
            action: nil,
            keyEquivalent: ""
        )
        recentNotesItem.isEnabled = false // 待实现
        setMenuItemIcon(recentNotesItem, symbolName: "clock")
        viewMenu.addItem(recentNotesItem)

        // 9.1 添加分隔线
        viewMenu.addItem(NSMenuItem.separator())

        // 9.2 添加"隐藏文件夹"菜单项（支持切换状态）
        let hideFoldersItem = NSMenuItem(
            title: "隐藏文件夹",
            action: #selector(AppDelegate.toggleFolderVisibility(_:)),
            keyEquivalent: ""
        )
        hideFoldersItem.tag = MenuItemTag.hideFolders.rawValue
        setMenuItemIcon(hideFoldersItem, symbolName: "folder")
        viewMenu.addItem(hideFoldersItem)

        // 9.3 添加"显示笔记数量"菜单项（支持切换状态）
        let showNoteCountItem = NSMenuItem(
            title: "显示笔记数量",
            action: #selector(AppDelegate.toggleNoteCount(_:)),
            keyEquivalent: ""
        )
        showNoteCountItem.tag = MenuItemTag.showNoteCount.rawValue
        setMenuItemIcon(showNoteCountItem, symbolName: "number")
        viewMenu.addItem(showNoteCountItem)

        // 9.4 添加分隔线
        viewMenu.addItem(NSMenuItem.separator())

        // 9.5 添加"附件视图"菜单项（待实现标记）
        let attachmentViewItem = NSMenuItem(
            title: "附件视图",
            action: nil,
            keyEquivalent: ""
        )
        attachmentViewItem.isEnabled = false // 待实现
        setMenuItemIcon(attachmentViewItem, symbolName: "paperclip")
        viewMenu.addItem(attachmentViewItem)

        // 9.6 添加分隔线
        viewMenu.addItem(NSMenuItem.separator())

        // 9.7 添加"显示附件浏览器"菜单项（待实现标记）
        let showAttachmentBrowserItem = NSMenuItem(
            title: "显示附件浏览器",
            action: nil,
            keyEquivalent: ""
        )
        showAttachmentBrowserItem.isEnabled = false // 待实现
        setMenuItemIcon(showAttachmentBrowserItem, symbolName: "photo.on.rectangle")
        viewMenu.addItem(showAttachmentBrowserItem)

        // 9.8 添加"在笔记中显示"菜单项（待实现标记）
        let showInNoteItem = NSMenuItem(
            title: "在笔记中显示",
            action: nil,
            keyEquivalent: ""
        )
        showInNoteItem.isEnabled = false // 待实现
        setMenuItemIcon(showInNoteItem, symbolName: "doc.text.magnifyingglass")
        viewMenu.addItem(showInNoteItem)

        // 10.1 添加分隔线
        viewMenu.addItem(NSMenuItem.separator())

        // 10.2 添加"放大"菜单项（⌘+）
        let zoomInItem = NSMenuItem(
            title: "放大",
            action: #selector(AppDelegate.zoomIn(_:)),
            keyEquivalent: "+"
        )
        zoomInItem.keyEquivalentModifierMask = [.command]
        zoomInItem.tag = MenuItemTag.zoomIn.rawValue
        setMenuItemIcon(zoomInItem, symbolName: "plus.magnifyingglass")
        viewMenu.addItem(zoomInItem)

        // 10.3 添加"缩小"菜单项（⌘-）
        let zoomOutItem = NSMenuItem(
            title: "缩小",
            action: #selector(AppDelegate.zoomOut(_:)),
            keyEquivalent: "-"
        )
        zoomOutItem.keyEquivalentModifierMask = [.command]
        zoomOutItem.tag = MenuItemTag.zoomOut.rawValue
        setMenuItemIcon(zoomOutItem, symbolName: "minus.magnifyingglass")
        viewMenu.addItem(zoomOutItem)

        // 10.4 添加"实际大小"菜单项（⌘0）
        let actualSizeItem = NSMenuItem(
            title: "实际大小",
            action: #selector(AppDelegate.actualSize(_:)),
            keyEquivalent: "0"
        )
        actualSizeItem.keyEquivalentModifierMask = [.command]
        actualSizeItem.tag = MenuItemTag.actualSize.rawValue
        setMenuItemIcon(actualSizeItem, symbolName: "1.magnifyingglass")
        viewMenu.addItem(actualSizeItem)

        // 11.1 添加分隔线
        viewMenu.addItem(NSMenuItem.separator())

        // 11.2 添加"展开区域"菜单项
        let expandSectionItem = NSMenuItem(
            title: "展开区域",
            action: #selector(AppDelegate.expandSection(_:)),
            keyEquivalent: ""
        )
        expandSectionItem.tag = MenuItemTag.expandSection.rawValue
        setMenuItemIcon(expandSectionItem, symbolName: "chevron.down")
        viewMenu.addItem(expandSectionItem)

        // 11.3 添加"展开所有区域"菜单项
        let expandAllSectionsItem = NSMenuItem(
            title: "展开所有区域",
            action: #selector(AppDelegate.expandAllSections(_:)),
            keyEquivalent: ""
        )
        expandAllSectionsItem.tag = MenuItemTag.expandAllSections.rawValue
        setMenuItemIcon(expandAllSectionsItem, symbolName: "chevron.down.2")
        viewMenu.addItem(expandAllSectionsItem)

        // 11.4 添加"折叠区域"菜单项
        let collapseSectionItem = NSMenuItem(
            title: "折叠区域",
            action: #selector(AppDelegate.collapseSection(_:)),
            keyEquivalent: ""
        )
        collapseSectionItem.tag = MenuItemTag.collapseSection.rawValue
        setMenuItemIcon(collapseSectionItem, symbolName: "chevron.up")
        viewMenu.addItem(collapseSectionItem)

        // 11.5 添加"折叠所有区域"菜单项
        let collapseAllSectionsItem = NSMenuItem(
            title: "折叠所有区域",
            action: #selector(AppDelegate.collapseAllSections(_:)),
            keyEquivalent: ""
        )
        collapseAllSectionsItem.tag = MenuItemTag.collapseAllSections.rawValue
        setMenuItemIcon(collapseAllSectionsItem, symbolName: "chevron.up.2")
        viewMenu.addItem(collapseAllSectionsItem)

        // 12.1 添加分隔线
        viewMenu.addItem(NSMenuItem.separator())

        // 12.2 添加"隐藏工具栏"菜单项
        // 使用标准 NSWindow 选择器 toggleToolbarShown:
        let toggleToolbarItem = NSMenuItem(
            title: "隐藏工具栏",
            action: #selector(NSWindow.toggleToolbarShown(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(toggleToolbarItem, symbolName: "menubar.rectangle")
        viewMenu.addItem(toggleToolbarItem)

        // 12.3 添加"自定义工具栏..."菜单项
        // 使用标准 NSWindow 选择器 runToolbarCustomizationPalette:
        let customizeToolbarItem = NSMenuItem(
            title: "自定义工具栏...",
            action: #selector(NSWindow.runToolbarCustomizationPalette(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(customizeToolbarItem, symbolName: "slider.horizontal.3")
        viewMenu.addItem(customizeToolbarItem)

        // 12.4 添加"进入全屏幕"菜单项（⌃⌘F）
        // 使用标准 NSWindow 选择器 toggleFullScreen:
        let toggleFullScreenItem = NSMenuItem(
            title: "进入全屏幕",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        toggleFullScreenItem.keyEquivalentModifierMask = [.control, .command]
        setMenuItemIcon(toggleFullScreenItem, symbolName: "arrow.up.left.and.arrow.down.right")
        viewMenu.addItem(toggleFullScreenItem)

        // 添加分隔线
        viewMenu.addItem(NSMenuItem.separator())

        // 添加"打开调试菜单"项
        let debugMenuItem = NSMenuItem()
        debugMenuItem.title = "打开调试菜单"
        debugMenuItem.action = #selector(AppDelegate.showDebugSettings(_:))
        debugMenuItem.target = appDelegate
        setMenuItemIcon(debugMenuItem, symbolName: "ladybug")
        viewMenu.addItem(debugMenuItem)

        // 添加"测试语音文件 API"项
        let testAudioAPIItem = NSMenuItem()
        testAudioAPIItem.title = "测试语音文件 API"
        testAudioAPIItem.action = #selector(AppDelegate.testAudioFileAPI(_:))
        testAudioAPIItem.target = appDelegate
        setMenuItemIcon(testAudioAPIItem, symbolName: "waveform")
        viewMenu.addItem(testAudioAPIItem)
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

        // 13.4 添加"填充"菜单项
        let fillItem = NSMenuItem(
            title: "填充",
            action: #selector(AppDelegate.fillWindow(_:)),
            keyEquivalent: ""
        )
        fillItem.tag = MenuItemTag.fill.rawValue
        setMenuItemIcon(fillItem, symbolName: "rectangle.expand.vertical")
        windowMenu.addItem(fillItem)

        // 13.5 添加"居中"菜单项
        // 使用标准 NSWindow 选择器 center
        let centerItem = NSMenuItem(
            title: "居中",
            action: #selector(AppDelegate.centerWindow(_:)),
            keyEquivalent: ""
        )
        centerItem.tag = MenuItemTag.center.rawValue
        setMenuItemIcon(centerItem, symbolName: "rectangle.center.inset.filled")
        windowMenu.addItem(centerItem)

        // 13.6 添加分隔线
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

        // 13.10 添加"在新窗口中打开笔记"菜单项
        let openInNewWindowItem = NSMenuItem(
            title: "在新窗口中打开笔记",
            action: #selector(AppDelegate.openNoteInNewWindow(_:)),
            keyEquivalent: ""
        )
        openInNewWindowItem.tag = MenuItemTag.openNoteInNewWindow.rawValue
        setMenuItemIcon(openInNewWindowItem, symbolName: "rectangle.on.rectangle")
        windowMenu.addItem(openInNewWindowItem)

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

        // 移动到左半边
        let moveToLeftItem = NSMenuItem(
            title: "移动到屏幕左半边",
            action: #selector(AppDelegate.moveWindowToLeftHalf(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(moveToLeftItem, symbolName: "rectangle.lefthalf.filled")
        moveAndResizeMenu.addItem(moveToLeftItem)

        // 移动到右半边
        let moveToRightItem = NSMenuItem(
            title: "移动到屏幕右半边",
            action: #selector(AppDelegate.moveWindowToRightHalf(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(moveToRightItem, symbolName: "rectangle.righthalf.filled")
        moveAndResizeMenu.addItem(moveToRightItem)

        moveAndResizeMenu.addItem(NSMenuItem.separator())

        // 移动到上半边
        let moveToTopItem = NSMenuItem(
            title: "移动到屏幕上半边",
            action: #selector(AppDelegate.moveWindowToTopHalf(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(moveToTopItem, symbolName: "rectangle.tophalf.filled")
        moveAndResizeMenu.addItem(moveToTopItem)

        // 移动到下半边
        let moveToBottomItem = NSMenuItem(
            title: "移动到屏幕下半边",
            action: #selector(AppDelegate.moveWindowToBottomHalf(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(moveToBottomItem, symbolName: "rectangle.bottomhalf.filled")
        moveAndResizeMenu.addItem(moveToBottomItem)

        moveAndResizeMenu.addItem(NSMenuItem.separator())

        // 最大化
        let maximizeItem = NSMenuItem(
            title: "最大化",
            action: #selector(AppDelegate.maximizeWindow(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(maximizeItem, symbolName: "arrow.up.left.and.arrow.down.right")
        moveAndResizeMenu.addItem(maximizeItem)

        // 恢复
        let restoreItem = NSMenuItem(
            title: "恢复",
            action: #selector(AppDelegate.restoreWindow(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(restoreItem, symbolName: "arrow.down.right.and.arrow.up.left")
        moveAndResizeMenu.addItem(restoreItem)

        return moveAndResizeMenu
    }

    /// 创建"全屏幕平铺"子菜单
    private func createFullScreenTileSubmenu() -> NSMenu {
        let fullScreenTileMenu = NSMenu(title: "全屏幕平铺")

        // 平铺到屏幕左侧
        let tileLeftItem = NSMenuItem(
            title: "平铺到屏幕左侧",
            action: #selector(AppDelegate.tileWindowToLeft(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(tileLeftItem, symbolName: "rectangle.split.2x1.fill")
        fullScreenTileMenu.addItem(tileLeftItem)

        // 平铺到屏幕右侧
        let tileRightItem = NSMenuItem(
            title: "平铺到屏幕右侧",
            action: #selector(AppDelegate.tileWindowToRight(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(tileRightItem, symbolName: "rectangle.split.2x1.fill")
        fullScreenTileMenu.addItem(tileRightItem)

        return fullScreenTileMenu
    }

    /// 创建"调试工具"子菜单
    private func createDebugToolsSubmenu() -> NSMenu {
        let debugMenu = NSMenu(title: "调试工具")

        // 调试设置窗口
        let debugSettingsItem = NSMenuItem(
            title: "调试设置",
            action: #selector(AppDelegate.showDebugSettings(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(debugSettingsItem, symbolName: "gearshape.2")
        debugMenu.addItem(debugSettingsItem)

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

        // 添加帮助菜单项
        let helpItem = NSMenuItem()
        helpItem.title = "笔记帮助"
        helpItem.action = #selector(AppDelegate.showHelp(_:))
        helpItem.target = appDelegate
        setMenuItemIcon(helpItem, symbolName: "questionmark.circle")
        helpMenu.addItem(helpItem)
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
