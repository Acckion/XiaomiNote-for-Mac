import AppKit
import MiNoteLibrary

/// 菜单管理器
/// 负责应用程序菜单的设置和管理
/// 按照 Apple Notes 标准实现完整的 macOS 原生菜单体验
/// - Requirements: 1.1-1.9
@MainActor
class MenuManager {
    
    // MARK: - 属性
    
    /// 应用程序委托的弱引用（用于菜单动作的目标）
    internal weak var appDelegate: AppDelegate?
    
    /// 主窗口控制器的弱引用
    internal weak var mainWindowController: MainWindowController?
    
    /// 菜单状态
    /// 用于管理菜单项的启用/禁用和勾选状态
    private(set) var menuState: MenuState = MenuState()
    
    /// 菜单状态变化回调
    var onMenuStateChanged: ((MenuState) -> Void)?
    
    /// 状态变化观察者
    private var stateObserver: NSObjectProtocol?
    
    // MARK: - 初始化
    
    /// 初始化菜单管理器
    /// - Parameters:
    ///   - appDelegate: 应用程序委托
    ///   - mainWindowController: 主窗口控制器
    init(appDelegate: AppDelegate? = nil, mainWindowController: MainWindowController? = nil) {
        self.appDelegate = appDelegate
        self.mainWindowController = mainWindowController
        setupStateObserver()
        print("菜单管理器初始化")
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
        print("菜单管理器引用更新完成")
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
    
    // MARK: - 私有方法 - 图标设置
    
    /// 为菜单项设置 SF Symbols 图标
    /// - Parameters:
    ///   - menuItem: 菜单项
    ///   - symbolName: SF Symbols 图标名称
    private func setMenuItemIcon(_ menuItem: NSMenuItem, symbolName: String) {
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
            guard let self = self,
                  let state = notification.userInfo?["state"] as? MenuState else {
                return
            }
            // 状态变化时可以在这里执行额外的处理
            print("菜单状态已更新: 选中笔记=\(state.hasSelectedNote), 编辑器焦点=\(state.isEditorFocused)")
        }
    }
    
    /// 设置应用程序菜单
    func setupApplicationMenu() {
        // 获取主菜单
        guard let mainMenu = NSApp.mainMenu else {
            print("警告：无法获取主菜单")
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
        
        print("应用程序菜单设置完成")
    }
    
    // MARK: - 私有方法
    
    /// 设置应用程序菜单
    /// 按照 Apple Notes 标准实现完整的应用程序菜单
    /// - Requirements: 1.1-1.9
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
    /// - Requirements: 2.1-2.20
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
    /// - Requirements: 2.12-2.13
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
    
    /// 设置编辑菜单
    /// 按照 Apple Notes 标准实现完整的编辑菜单
    /// 使用标准 NSResponder 选择器，让系统自动路由到响应链中的正确响应者
    /// - Requirements: 3.1-3.11
    private func setupEditMenu(in mainMenu: NSMenu) {
        // 创建编辑菜单
        let editMenuItem = NSMenuItem()
        editMenuItem.title = "编辑"
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // ========== 撤销/重做部分 ==========
        
        // 3.1 添加"撤销"菜单项（⌘Z）
        // 使用 Selector("undo:") 让系统自动路由到 UndoManager
        let undoItem = NSMenuItem(
            title: "撤销",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        undoItem.keyEquivalentModifierMask = [.command]
        undoItem.tag = MenuItemTag.undo.rawValue
        setMenuItemIcon(undoItem, symbolName: "arrow.uturn.backward")
        editMenu.addItem(undoItem)
        
        // 3.2 添加"重做"菜单项（⇧⌘Z）
        // 使用 Selector("redo:") 让系统自动路由到 UndoManager
        let redoItem = NSMenuItem(
            title: "重做",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.tag = MenuItemTag.redo.rawValue
        setMenuItemIcon(redoItem, symbolName: "arrow.uturn.forward")
        editMenu.addItem(redoItem)
        
        // 3.3 添加分隔线
        editMenu.addItem(NSMenuItem.separator())
        
        // ========== 基础编辑操作部分 ==========
        
        // 3.4 添加"剪切"菜单项（⌘X）
        // 使用标准 NSText 选择器
        let cutItem = NSMenuItem(
            title: "剪切",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        cutItem.keyEquivalentModifierMask = [.command]
        cutItem.tag = MenuItemTag.cut.rawValue
        setMenuItemIcon(cutItem, symbolName: "scissors")
        editMenu.addItem(cutItem)
        
        // 3.5 添加"拷贝"菜单项（⌘C）
        // 使用标准 NSText 选择器
        let copyItem = NSMenuItem(
            title: "拷贝",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = [.command]
        copyItem.tag = MenuItemTag.copy.rawValue
        setMenuItemIcon(copyItem, symbolName: "doc.on.doc")
        editMenu.addItem(copyItem)
        
        // 3.6 添加"粘贴"菜单项（⌘V）
        // 使用标准 NSText 选择器
        let pasteItem = NSMenuItem(
            title: "粘贴",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        pasteItem.keyEquivalentModifierMask = [.command]
        pasteItem.tag = MenuItemTag.paste.rawValue
        setMenuItemIcon(pasteItem, symbolName: "doc.on.clipboard")
        editMenu.addItem(pasteItem)
        
        // 3.7 添加"粘贴并匹配样式"菜单项（⌥⇧⌘V）（待实现标记）
        let pasteAndMatchStyleItem = NSMenuItem(
            title: "粘贴并匹配样式",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        )
        pasteAndMatchStyleItem.keyEquivalentModifierMask = [.command, .option, .shift]
        pasteAndMatchStyleItem.tag = MenuItemTag.pasteAndMatchStyle.rawValue
        setMenuItemIcon(pasteAndMatchStyleItem, symbolName: "doc.on.clipboard.fill")
        editMenu.addItem(pasteAndMatchStyleItem)
        
        // 3.9 添加"删除"菜单项
        // 使用标准 NSText 选择器
        let deleteItem = NSMenuItem(
            title: "删除",
            action: #selector(NSText.delete(_:)),
            keyEquivalent: ""
        )
        deleteItem.tag = MenuItemTag.delete.rawValue
        setMenuItemIcon(deleteItem, symbolName: "trash")
        editMenu.addItem(deleteItem)
        
        // 3.10 添加"全选"菜单项（⌘A）
        // 使用标准 NSText 选择器
        let selectAllItem = NSMenuItem(
            title: "全选",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        selectAllItem.keyEquivalentModifierMask = [.command]
        selectAllItem.tag = MenuItemTag.selectAll.rawValue
        setMenuItemIcon(selectAllItem, symbolName: "selection.pin.in.out")
        editMenu.addItem(selectAllItem)
        
        // 3.11 添加分隔线
        editMenu.addItem(NSMenuItem.separator())
        
        // ========== 附件操作部分 ==========
        
        // 3.12 添加"附加文件..."菜单项
        let attachFileItem = NSMenuItem(
            title: "附加文件...",
            action: #selector(MenuActionHandler.attachFile(_:)),
            keyEquivalent: ""
        )
        attachFileItem.tag = MenuItemTag.attachFile.rawValue
        setMenuItemIcon(attachFileItem, symbolName: "paperclip")
        editMenu.addItem(attachFileItem)
        
        // 3.13 添加"添加链接..."菜单项（⌘K）
        let addLinkItem = NSMenuItem(
            title: "添加链接...",
            action: #selector(MenuActionHandler.addLink(_:)),
            keyEquivalent: "k"
        )
        addLinkItem.keyEquivalentModifierMask = [.command]
        addLinkItem.tag = MenuItemTag.addLink.rawValue
        setMenuItemIcon(addLinkItem, symbolName: "link")
        editMenu.addItem(addLinkItem)
        
        // 3.16 添加分隔线
        editMenu.addItem(NSMenuItem.separator())
        
        // ========== 查找功能部分 ==========
        
        // 3.17 添加"查找"子菜单
        let findMenuItem = NSMenuItem(
            title: "查找",
            action: nil,
            keyEquivalent: ""
        )
        findMenuItem.submenu = createFindSubmenu()
        setMenuItemIcon(findMenuItem, symbolName: "magnifyingglass")
        editMenu.addItem(findMenuItem)
        
        // ========== 文本处理部分（系统标准功能）==========
        
        // 3.23 添加"拼写和语法"子菜单
        let spellingMenuItem = NSMenuItem(
            title: "拼写和语法",
            action: nil,
            keyEquivalent: ""
        )
        spellingMenuItem.submenu = createSpellingSubmenu()
        setMenuItemIcon(spellingMenuItem, symbolName: "textformat.abc")
        editMenu.addItem(spellingMenuItem)
        
        // 3.24 添加"替换"子菜单
        let substitutionsMenuItem = NSMenuItem(
            title: "替换",
            action: nil,
            keyEquivalent: ""
        )
        substitutionsMenuItem.submenu = createSubstitutionsSubmenu()
        setMenuItemIcon(substitutionsMenuItem, symbolName: "arrow.2.squarepath")
        editMenu.addItem(substitutionsMenuItem)
        
        // 3.25 添加"转换"子菜单
        let transformationsMenuItem = NSMenuItem(
            title: "转换",
            action: nil,
            keyEquivalent: ""
        )
        transformationsMenuItem.submenu = createTransformationsSubmenu()
        setMenuItemIcon(transformationsMenuItem, symbolName: "textformat")
        editMenu.addItem(transformationsMenuItem)
        
        // 3.26 添加"语音"子菜单
        let speechMenuItem = NSMenuItem(
            title: "语音",
            action: nil,
            keyEquivalent: ""
        )
        speechMenuItem.submenu = createSpeechSubmenu()
        setMenuItemIcon(speechMenuItem, symbolName: "speaker.wave.2")
        editMenu.addItem(speechMenuItem)
        
        // 3.27 添加分隔线
        editMenu.addItem(NSMenuItem.separator())
        
        // 3.28 添加"开始听写"菜单项
        // 听写功能由系统管理，使用 nil action 让系统处理
        let startDictationItem = NSMenuItem(
            title: "开始听写",
            action: nil,
            keyEquivalent: ""
        )
        // 听写快捷键由系统管理（通常是 fn fn）
        // 设置为禁用状态，因为听写功能需要系统级别的支持
        startDictationItem.isEnabled = false
        editMenu.addItem(startDictationItem)
        
        // 3.29 添加"表情与符号"菜单项（⌃⌘空格）
        let emojiItem = NSMenuItem(
            title: "表情与符号",
            action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: " "
        )
        emojiItem.keyEquivalentModifierMask = [.control, .command]
        setMenuItemIcon(emojiItem, symbolName: "face.smiling")
        editMenu.addItem(emojiItem)
    }
    
    /// 创建"查找"子菜单
    /// 使用 performFindPanelAction: 和 NSTextFinder.Action 实现标准查找功能
    /// - Requirements: 3.17-3.22
    private func createFindSubmenu() -> NSMenu {
        let findMenu = NSMenu(title: "查找")
        
        // 3.19 添加"查找..."（⌘F）
        let findItem = NSMenuItem(
            title: "查找...",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "f"
        )
        findItem.keyEquivalentModifierMask = [.command]
        findItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        setMenuItemIcon(findItem, symbolName: "magnifyingglass")
        findMenu.addItem(findItem)
        
        // 3.20 添加"查找下一个"（⌘G）
        let findNextItem = NSMenuItem(
            title: "查找下一个",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "g"
        )
        findNextItem.keyEquivalentModifierMask = [.command]
        findNextItem.tag = Int(NSTextFinder.Action.nextMatch.rawValue)
        setMenuItemIcon(findNextItem, symbolName: "chevron.down")
        findMenu.addItem(findNextItem)
        
        // 3.21 添加"查找上一个"（⇧⌘G）
        let findPreviousItem = NSMenuItem(
            title: "查找上一个",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "g"
        )
        findPreviousItem.keyEquivalentModifierMask = [.command, .shift]
        findPreviousItem.tag = Int(NSTextFinder.Action.previousMatch.rawValue)
        setMenuItemIcon(findPreviousItem, symbolName: "chevron.up")
        findMenu.addItem(findPreviousItem)
        
        // 添加"使用所选内容查找"（⌘E）
        let useSelectionItem = NSMenuItem(
            title: "使用所选内容查找",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "e"
        )
        useSelectionItem.keyEquivalentModifierMask = [.command]
        useSelectionItem.tag = Int(NSTextFinder.Action.setSearchString.rawValue)
        setMenuItemIcon(useSelectionItem, symbolName: "text.magnifyingglass")
        findMenu.addItem(useSelectionItem)
        
        // 3.22 添加"查找并替换..."（⌥⌘F）
        let findAndReplaceItem = NSMenuItem(
            title: "查找并替换...",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "f"
        )
        findAndReplaceItem.keyEquivalentModifierMask = [.command, .option]
        findAndReplaceItem.tag = Int(NSTextFinder.Action.showReplaceInterface.rawValue)
        setMenuItemIcon(findAndReplaceItem, symbolName: "arrow.left.arrow.right")
        findMenu.addItem(findAndReplaceItem)
        
        return findMenu
    }
    
    /// 创建"拼写和语法"子菜单
    /// 使用系统标准实现
    /// - Requirements: 3.23
    private func createSpellingSubmenu() -> NSMenu {
        let spellingMenu = NSMenu(title: "拼写和语法")
        
        // 立即检查文稿
        let checkNowItem = NSMenuItem(
            title: "立即检查文稿",
            action: #selector(NSTextView.checkSpelling(_:)),
            keyEquivalent: ";"
        )
        checkNowItem.keyEquivalentModifierMask = [.command]
        setMenuItemIcon(checkNowItem, symbolName: "checkmark.circle")
        spellingMenu.addItem(checkNowItem)
        
        // 检查拼写和语法
        let checkSpellingItem = NSMenuItem(
            title: "检查拼写和语法",
            action: #selector(NSText.checkSpelling(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(checkSpellingItem, symbolName: "text.badge.checkmark")
        spellingMenu.addItem(checkSpellingItem)
        
        // 自动更正拼写
        let autoCorrectItem = NSMenuItem(
            title: "自动更正拼写",
            action: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(autoCorrectItem, symbolName: "wand.and.stars")
        spellingMenu.addItem(autoCorrectItem)
        
        return spellingMenu
    }
    
    /// 创建"替换"子菜单
    /// 使用系统标准实现
    /// - Requirements: 3.24
    private func createSubstitutionsSubmenu() -> NSMenu {
        let substitutionsMenu = NSMenu(title: "替换")
        
        // 显示替换
        let showSubstitutionsItem = NSMenuItem(
            title: "显示替换",
            action: #selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(showSubstitutionsItem, symbolName: "list.bullet.rectangle")
        substitutionsMenu.addItem(showSubstitutionsItem)
        
        substitutionsMenu.addItem(NSMenuItem.separator())
        
        // 智能拷贝/粘贴
        let smartCopyPasteItem = NSMenuItem(
            title: "智能拷贝/粘贴",
            action: #selector(NSTextView.toggleSmartInsertDelete(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(smartCopyPasteItem, symbolName: "doc.on.doc.fill")
        substitutionsMenu.addItem(smartCopyPasteItem)
        
        // 智能引号
        let smartQuotesItem = NSMenuItem(
            title: "智能引号",
            action: #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(smartQuotesItem, symbolName: "quote.opening")
        substitutionsMenu.addItem(smartQuotesItem)
        
        // 智能破折号
        let smartDashesItem = NSMenuItem(
            title: "智能破折号",
            action: #selector(NSTextView.toggleAutomaticDashSubstitution(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(smartDashesItem, symbolName: "minus")
        substitutionsMenu.addItem(smartDashesItem)
        
        // 智能链接
        let smartLinksItem = NSMenuItem(
            title: "智能链接",
            action: #selector(NSTextView.toggleAutomaticLinkDetection(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(smartLinksItem, symbolName: "link")
        substitutionsMenu.addItem(smartLinksItem)
        
        // 文本替换
        let textReplacementItem = NSMenuItem(
            title: "文本替换",
            action: #selector(NSTextView.toggleAutomaticTextReplacement(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(textReplacementItem, symbolName: "character.cursor.ibeam")
        substitutionsMenu.addItem(textReplacementItem)
        
        return substitutionsMenu
    }
    
    /// 创建"转换"子菜单
    /// 使用系统标准实现
    /// - Requirements: 3.25
    private func createTransformationsSubmenu() -> NSMenu {
        let transformationsMenu = NSMenu(title: "转换")
        
        // 全部大写
        let uppercaseItem = NSMenuItem(
            title: "全部大写",
            action: #selector(NSTextView.uppercaseWord(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(uppercaseItem, symbolName: "textformat.size.larger")
        transformationsMenu.addItem(uppercaseItem)
        
        // 全部小写
        let lowercaseItem = NSMenuItem(
            title: "全部小写",
            action: #selector(NSTextView.lowercaseWord(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(lowercaseItem, symbolName: "textformat.size.smaller")
        transformationsMenu.addItem(lowercaseItem)
        
        // 首字母大写
        let capitalizeItem = NSMenuItem(
            title: "首字母大写",
            action: #selector(NSTextView.capitalizeWord(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(capitalizeItem, symbolName: "textformat")
        transformationsMenu.addItem(capitalizeItem)
        
        return transformationsMenu
    }
    
    /// 创建"语音"子菜单
    /// 使用系统标准实现
    /// - Requirements: 3.26
    private func createSpeechSubmenu() -> NSMenu {
        let speechMenu = NSMenu(title: "语音")
        
        // 开始朗读
        let startSpeakingItem = NSMenuItem(
            title: "开始朗读",
            action: #selector(NSTextView.startSpeaking(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(startSpeakingItem, symbolName: "play.fill")
        speechMenu.addItem(startSpeakingItem)
        
        // 停止朗读
        let stopSpeakingItem = NSMenuItem(
            title: "停止朗读",
            action: #selector(NSTextView.stopSpeaking(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(stopSpeakingItem, symbolName: "stop.fill")
        speechMenu.addItem(stopSpeakingItem)
        
        return speechMenu
    }
    
    /// 设置格式菜单
    /// 按照 Apple Notes 标准实现完整的格式菜单
    /// - Requirements: 4.1-4.9, 5.1-5.11, 6.1-6.9, 7.1-7.7
    private func setupFormatMenu(in mainMenu: NSMenu) {
        // 创建格式菜单
        let formatMenuItem = NSMenuItem()
        formatMenuItem.title = "格式"
        let formatMenu = NSMenu(title: "格式")
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)
        
        // ========== 段落样式部分（Requirements: 4.1-4.9）==========
        
        // 4.1 添加"标题"菜单项（支持单选勾选状态）
        let headingItem = NSMenuItem(
            title: "标题",
            action: #selector(AppDelegate.setHeading(_:)),
            keyEquivalent: ""
        )
        headingItem.tag = MenuItemTag.heading.rawValue
        setMenuItemIcon(headingItem, symbolName: "textformat.size.larger")
        formatMenu.addItem(headingItem)
        
        // 4.2 添加"小标题"菜单项（支持单选勾选状态）
        let subheadingItem = NSMenuItem(
            title: "小标题",
            action: #selector(AppDelegate.setSubheading(_:)),
            keyEquivalent: ""
        )
        subheadingItem.tag = MenuItemTag.subheading.rawValue
        setMenuItemIcon(subheadingItem, symbolName: "textformat.size")
        formatMenu.addItem(subheadingItem)
        
        // 4.3 添加"副标题"菜单项（支持单选勾选状态）
        let subtitleItem = NSMenuItem(
            title: "副标题",
            action: #selector(AppDelegate.setSubtitle(_:)),
            keyEquivalent: ""
        )
        subtitleItem.tag = MenuItemTag.subtitle.rawValue
        setMenuItemIcon(subtitleItem, symbolName: "textformat.size.smaller")
        formatMenu.addItem(subtitleItem)
        
        // 4.4 添加"正文"菜单项（支持单选勾选状态）
        let bodyTextItem = NSMenuItem(
            title: "正文",
            action: #selector(AppDelegate.setBodyText(_:)),
            keyEquivalent: ""
        )
        bodyTextItem.tag = MenuItemTag.bodyText.rawValue
        setMenuItemIcon(bodyTextItem, symbolName: "text.justify")
        formatMenu.addItem(bodyTextItem)
        
        // 4.5 添加"有序列表"菜单项（支持单选勾选状态）
        let orderedListItem = NSMenuItem(
            title: "有序列表",
            action: #selector(AppDelegate.toggleOrderedList(_:)),
            keyEquivalent: ""
        )
        orderedListItem.tag = MenuItemTag.orderedList.rawValue
        setMenuItemIcon(orderedListItem, symbolName: "list.number")
        formatMenu.addItem(orderedListItem)
        
        // 4.6 添加"无序列表"菜单项（支持单选勾选状态）
        let unorderedListItem = NSMenuItem(
            title: "无序列表",
            action: #selector(AppDelegate.toggleUnorderedList(_:)),
            keyEquivalent: ""
        )
        unorderedListItem.tag = MenuItemTag.unorderedList.rawValue
        setMenuItemIcon(unorderedListItem, symbolName: "list.bullet")
        formatMenu.addItem(unorderedListItem)
        
        // 4.8 添加分隔线
        formatMenu.addItem(NSMenuItem.separator())
        
        // 4.9 添加"块引用"菜单项
        let blockQuoteItem = NSMenuItem(
            title: "块引用",
            action: #selector(AppDelegate.toggleBlockQuote(_:)),
            keyEquivalent: ""
        )
        blockQuoteItem.tag = MenuItemTag.blockQuote.rawValue
        setMenuItemIcon(blockQuoteItem, symbolName: "text.quote")
        formatMenu.addItem(blockQuoteItem)
        
        // 添加分隔线
        formatMenu.addItem(NSMenuItem.separator())
        
        // ========== 核对清单部分（Requirements: 5.1-5.11）==========
        
        // 5.1 添加"核对清单"菜单项
        let checklistItem = NSMenuItem(
            title: "核对清单",
            action: #selector(AppDelegate.toggleChecklist(_:)),
            keyEquivalent: ""
        )
        checklistItem.tag = MenuItemTag.checklist.rawValue
        setMenuItemIcon(checklistItem, symbolName: "checklist")
        formatMenu.addItem(checklistItem)
        
        // 5.2 添加"标记为已勾选"菜单项
        let markAsCheckedItem = NSMenuItem(
            title: "标记为已勾选",
            action: #selector(AppDelegate.markAsChecked(_:)),
            keyEquivalent: ""
        )
        markAsCheckedItem.tag = MenuItemTag.markAsChecked.rawValue
        setMenuItemIcon(markAsCheckedItem, symbolName: "checkmark.circle")
        formatMenu.addItem(markAsCheckedItem)
        
        // 5.3 添加"更多"子菜单
        let moreMenuItem = NSMenuItem(
            title: "更多",
            action: nil,
            keyEquivalent: ""
        )
        moreMenuItem.submenu = createChecklistMoreSubmenu()
        setMenuItemIcon(moreMenuItem, symbolName: "ellipsis.circle")
        formatMenu.addItem(moreMenuItem)
        
        // 5.8 添加分隔线
        formatMenu.addItem(NSMenuItem.separator())
        
        // 5.9 添加"移动项目"子菜单
        let moveItemMenuItem = NSMenuItem(
            title: "移动项目",
            action: nil,
            keyEquivalent: ""
        )
        moveItemMenuItem.submenu = createMoveItemSubmenu()
        setMenuItemIcon(moveItemMenuItem, symbolName: "arrow.up.arrow.down")
        formatMenu.addItem(moveItemMenuItem)
        
        // 6.1 添加分隔线
        formatMenu.addItem(NSMenuItem.separator())
        
        // ========== 外观和字体部分（Requirements: 6.1-6.9）==========
        
        // 6.2 添加"使用浅色背景显示笔记"菜单项（支持勾选状态）
        let lightBackgroundItem = NSMenuItem(
            title: "使用浅色背景显示笔记",
            action: #selector(AppDelegate.toggleLightBackground(_:)),
            keyEquivalent: ""
        )
        lightBackgroundItem.tag = MenuItemTag.lightBackground.rawValue
        setMenuItemIcon(lightBackgroundItem, symbolName: "sun.max")
        formatMenu.addItem(lightBackgroundItem)
        
        // 6.3 添加分隔线
        formatMenu.addItem(NSMenuItem.separator())
        
        // 6.4 添加"字体"子菜单
        let fontMenuItem = NSMenuItem(
            title: "字体",
            action: nil,
            keyEquivalent: ""
        )
        fontMenuItem.submenu = createFontSubmenu()
        setMenuItemIcon(fontMenuItem, symbolName: "textformat")
        formatMenu.addItem(fontMenuItem)
        
        // ========== 文本对齐和缩进部分（Requirements: 7.1-7.7）==========
        
        // 7.1 添加"文本"子菜单
        let textMenuItem = NSMenuItem(
            title: "文本",
            action: nil,
            keyEquivalent: ""
        )
        textMenuItem.submenu = createTextAlignmentSubmenu()
        setMenuItemIcon(textMenuItem, symbolName: "text.alignleft")
        formatMenu.addItem(textMenuItem)
        
        // 7.5 添加"缩进"子菜单
        let indentMenuItem = NSMenuItem(
            title: "缩进",
            action: nil,
            keyEquivalent: ""
        )
        indentMenuItem.submenu = createIndentSubmenu()
        setMenuItemIcon(indentMenuItem, symbolName: "increase.indent")
        formatMenu.addItem(indentMenuItem)
    }
    
    /// 创建"更多"子菜单（核对清单）
    /// - Requirements: 5.3-5.7
    private func createChecklistMoreSubmenu() -> NSMenu {
        let moreMenu = NSMenu(title: "更多")
        
        // 5.4 全部勾选
        let checkAllItem = NSMenuItem(
            title: "全部勾选",
            action: #selector(AppDelegate.checkAll(_:)),
            keyEquivalent: ""
        )
        checkAllItem.tag = MenuItemTag.checkAll.rawValue
        setMenuItemIcon(checkAllItem, symbolName: "checkmark.circle.fill")
        moreMenu.addItem(checkAllItem)
        
        // 5.5 全部取消勾选
        let uncheckAllItem = NSMenuItem(
            title: "全部取消勾选",
            action: #selector(AppDelegate.uncheckAll(_:)),
            keyEquivalent: ""
        )
        uncheckAllItem.tag = MenuItemTag.uncheckAll.rawValue
        setMenuItemIcon(uncheckAllItem, symbolName: "circle")
        moreMenu.addItem(uncheckAllItem)
        
        // 5.6 将勾选的项目移到底部
        let moveCheckedToBottomItem = NSMenuItem(
            title: "将勾选的项目移到底部",
            action: #selector(AppDelegate.moveCheckedToBottom(_:)),
            keyEquivalent: ""
        )
        moveCheckedToBottomItem.tag = MenuItemTag.moveCheckedToBottom.rawValue
        setMenuItemIcon(moveCheckedToBottomItem, symbolName: "arrow.down.to.line")
        moreMenu.addItem(moveCheckedToBottomItem)
        
        // 5.7 删除已勾选项目
        let deleteCheckedItemsItem = NSMenuItem(
            title: "删除已勾选项目",
            action: #selector(AppDelegate.deleteCheckedItems(_:)),
            keyEquivalent: ""
        )
        deleteCheckedItemsItem.tag = MenuItemTag.deleteCheckedItems.rawValue
        setMenuItemIcon(deleteCheckedItemsItem, symbolName: "trash")
        moreMenu.addItem(deleteCheckedItemsItem)
        
        return moreMenu
    }
    
    /// 创建"移动项目"子菜单
    /// - Requirements: 5.9-5.11
    private func createMoveItemSubmenu() -> NSMenu {
        let moveMenu = NSMenu(title: "移动项目")
        
        // 5.10 向上
        let moveUpItem = NSMenuItem(
            title: "向上",
            action: #selector(AppDelegate.moveItemUp(_:)),
            keyEquivalent: ""
        )
        moveUpItem.keyEquivalent = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        moveUpItem.keyEquivalentModifierMask = [.control, .command]
        moveUpItem.tag = MenuItemTag.moveItemUp.rawValue
        setMenuItemIcon(moveUpItem, symbolName: "arrow.up")
        moveMenu.addItem(moveUpItem)
        
        // 5.11 向下
        let moveDownItem = NSMenuItem(
            title: "向下",
            action: #selector(AppDelegate.moveItemDown(_:)),
            keyEquivalent: ""
        )
        moveDownItem.keyEquivalent = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        moveDownItem.keyEquivalentModifierMask = [.control, .command]
        moveDownItem.tag = MenuItemTag.moveItemDown.rawValue
        setMenuItemIcon(moveDownItem, symbolName: "arrow.down")
        moveMenu.addItem(moveDownItem)
        
        return moveMenu
    }
    
    /// 创建"字体"子菜单
    /// - Requirements: 6.4-6.9
    private func createFontSubmenu() -> NSMenu {
        let fontMenu = NSMenu(title: "字体")
        
        // 6.5 粗体（⌘B）
        let boldItem = NSMenuItem(
            title: "粗体",
            action: #selector(AppDelegate.toggleBold(_:)),
            keyEquivalent: "b"
        )
        boldItem.keyEquivalentModifierMask = [.command]
        boldItem.tag = MenuItemTag.bold.rawValue
        setMenuItemIcon(boldItem, symbolName: "bold")
        fontMenu.addItem(boldItem)
        
        // 6.6 斜体（⌘I）
        let italicItem = NSMenuItem(
            title: "斜体",
            action: #selector(AppDelegate.toggleItalic(_:)),
            keyEquivalent: "i"
        )
        italicItem.keyEquivalentModifierMask = [.command]
        italicItem.tag = MenuItemTag.italic.rawValue
        setMenuItemIcon(italicItem, symbolName: "italic")
        fontMenu.addItem(italicItem)
        
        // 6.7 下划线（⌘U）
        let underlineItem = NSMenuItem(
            title: "下划线",
            action: #selector(AppDelegate.toggleUnderline(_:)),
            keyEquivalent: "u"
        )
        underlineItem.keyEquivalentModifierMask = [.command]
        underlineItem.tag = MenuItemTag.underline.rawValue
        setMenuItemIcon(underlineItem, symbolName: "underline")
        fontMenu.addItem(underlineItem)
        
        // 6.8 删除线
        let strikethroughItem = NSMenuItem(
            title: "删除线",
            action: #selector(AppDelegate.toggleStrikethrough(_:)),
            keyEquivalent: ""
        )
        strikethroughItem.tag = MenuItemTag.strikethrough.rawValue
        setMenuItemIcon(strikethroughItem, symbolName: "strikethrough")
        fontMenu.addItem(strikethroughItem)
        
        // 6.9 高亮
        let highlightItem = NSMenuItem(
            title: "高亮",
            action: #selector(AppDelegate.toggleHighlight(_:)),
            keyEquivalent: ""
        )
        highlightItem.tag = MenuItemTag.highlight.rawValue
        setMenuItemIcon(highlightItem, symbolName: "highlighter")
        fontMenu.addItem(highlightItem)
        
        return fontMenu
    }
    
    /// 创建"文本"子菜单（文本对齐）
    /// - Requirements: 7.1-7.4
    private func createTextAlignmentSubmenu() -> NSMenu {
        let textMenu = NSMenu(title: "文本")
        
        // 7.2 左对齐
        let alignLeftItem = NSMenuItem(
            title: "左对齐",
            action: #selector(AppDelegate.alignLeft(_:)),
            keyEquivalent: ""
        )
        alignLeftItem.tag = MenuItemTag.alignLeft.rawValue
        setMenuItemIcon(alignLeftItem, symbolName: "text.alignleft")
        textMenu.addItem(alignLeftItem)
        
        // 7.3 居中
        let alignCenterItem = NSMenuItem(
            title: "居中",
            action: #selector(AppDelegate.alignCenter(_:)),
            keyEquivalent: ""
        )
        alignCenterItem.tag = MenuItemTag.alignCenter.rawValue
        setMenuItemIcon(alignCenterItem, symbolName: "text.aligncenter")
        textMenu.addItem(alignCenterItem)
        
        // 7.4 右对齐
        let alignRightItem = NSMenuItem(
            title: "右对齐",
            action: #selector(AppDelegate.alignRight(_:)),
            keyEquivalent: ""
        )
        alignRightItem.tag = MenuItemTag.alignRight.rawValue
        setMenuItemIcon(alignRightItem, symbolName: "text.alignright")
        textMenu.addItem(alignRightItem)
        
        return textMenu
    }
    
    /// 创建"缩进"子菜单
    /// - Requirements: 7.5-7.7
    private func createIndentSubmenu() -> NSMenu {
        let indentMenu = NSMenu(title: "缩进")
        
        // 7.6 增大（⌘]）
        let increaseIndentItem = NSMenuItem(
            title: "增大",
            action: #selector(AppDelegate.increaseIndent(_:)),
            keyEquivalent: "]"
        )
        increaseIndentItem.keyEquivalentModifierMask = [.command]
        increaseIndentItem.tag = MenuItemTag.increaseIndent.rawValue
        setMenuItemIcon(increaseIndentItem, symbolName: "increase.indent")
        indentMenu.addItem(increaseIndentItem)
        
        // 7.7 减小（⌘[）
        let decreaseIndentItem = NSMenuItem(
            title: "减小",
            action: #selector(AppDelegate.decreaseIndent(_:)),
            keyEquivalent: "["
        )
        decreaseIndentItem.keyEquivalentModifierMask = [.command]
        decreaseIndentItem.tag = MenuItemTag.decreaseIndent.rawValue
        setMenuItemIcon(decreaseIndentItem, symbolName: "decrease.indent")
        indentMenu.addItem(decreaseIndentItem)
        
        return indentMenu
    }
    
    /// 设置视图菜单
    /// 按照 Apple Notes 标准实现完整的显示菜单
    /// - Requirements: 8.1-8.5, 9.1-9.8, 10.1-10.4, 11.1-11.5, 12.1-12.4
    private func setupViewMenu(in mainMenu: NSMenu) {
        // 创建显示菜单
        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = "显示"
        let viewMenu = NSMenu(title: "显示")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // ========== 视图模式部分（Requirements: 8.1-8.5）==========
        
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
        recentNotesItem.isEnabled = false  // 待实现
        setMenuItemIcon(recentNotesItem, symbolName: "clock")
        viewMenu.addItem(recentNotesItem)
        
        // ========== 文件夹和笔记数量控制部分（Requirements: 9.1-9.8）==========
        
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
        attachmentViewItem.isEnabled = false  // 待实现
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
        showAttachmentBrowserItem.isEnabled = false  // 待实现
        setMenuItemIcon(showAttachmentBrowserItem, symbolName: "photo.on.rectangle")
        viewMenu.addItem(showAttachmentBrowserItem)
        
        // 9.8 添加"在笔记中显示"菜单项（待实现标记）
        let showInNoteItem = NSMenuItem(
            title: "在笔记中显示",
            action: nil,
            keyEquivalent: ""
        )
        showInNoteItem.isEnabled = false  // 待实现
        setMenuItemIcon(showInNoteItem, symbolName: "doc.text.magnifyingglass")
        viewMenu.addItem(showInNoteItem)
        
        // ========== 缩放控制部分（Requirements: 10.1-10.4）==========
        
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
        
        // ========== 区域折叠控制部分（Requirements: 11.1-11.5）==========
        
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
        
        // ========== 工具栏控制部分（Requirements: 12.1-12.4）==========
        
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
    }
    
    /// 设置窗口菜单
    /// 按照 Apple Notes 标准实现完整的窗口菜单
    /// 使用系统窗口菜单管理，让系统自动管理窗口列表
    /// - Requirements: 13.1-13.14
    private func setupWindowMenu(in mainMenu: NSMenu) {
        // 创建窗口菜单
        let windowMenuItem = NSMenuItem()
        windowMenuItem.title = "窗口"
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        // 13.1 注册系统窗口菜单，让系统自动管理窗口列表
        NSApp.windowsMenu = windowMenu
        
        // ========== 基础窗口控制部分（Requirements: 13.2-13.6）==========
        
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
        
        // ========== 窗口布局部分（Requirements: 13.7-13.9）==========
        
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
        
        // ========== 自定义窗口操作部分（Requirements: 13.10-13.11）==========
        
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
        
        // ========== 系统自动管理的窗口列表（Requirements: 13.12-13.13）==========
        // 13.12 系统会自动在此处添加打开的窗口列表
        // 13.13 系统会自动添加分隔线
        
        // ========== 前置全部窗口（Requirements: 13.14）==========
        
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
    }
    
    /// 创建"移动与调整大小"子菜单
    /// - Requirements: 13.7
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
    /// - Requirements: 13.8
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
        print("菜单管理器释放")
    }
}
