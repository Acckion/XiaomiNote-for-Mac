import AppKit
import MiNoteLibrary

/// 菜单管理器
/// 负责应用程序菜单的设置和管理
@MainActor
class MenuManager {
    
    // MARK: - 属性
    
    /// 应用程序委托的弱引用（用于菜单动作的目标）
    internal weak var appDelegate: AppDelegate?
    
    /// 主窗口控制器的弱引用
    internal weak var mainWindowController: MainWindowController?
    
    // MARK: - 初始化
    
    /// 初始化菜单管理器
    /// - Parameters:
    ///   - appDelegate: 应用程序委托
    ///   - mainWindowController: 主窗口控制器
    init(appDelegate: AppDelegate? = nil, mainWindowController: MainWindowController? = nil) {
        self.appDelegate = appDelegate
        self.mainWindowController = mainWindowController
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
    private func setupAppMenu(in mainMenu: NSMenu) {
        // 创建应用程序菜单项
        let appMenuItem = NSMenuItem()
        appMenuItem.title = "笔记"
        let appMenu = NSMenu(title: "笔记")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 添加关于菜单项
        let aboutItem = NSMenuItem()
        aboutItem.title = "关于小米笔记"
        aboutItem.action = #selector(AppDelegate.showAboutPanel(_:))
        aboutItem.target = appDelegate
        appMenu.addItem(aboutItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // 添加设置菜单项
        let settingsItem = NSMenuItem()
        settingsItem.title = "设置..."
        settingsItem.action = #selector(AppDelegate.showSettings(_:))
        settingsItem.target = appDelegate
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(settingsItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // 添加退出菜单项（系统会自动添加，但我们也可以手动添加）
        let quitItem = NSMenuItem()
        quitItem.title = "退出笔记"
        quitItem.action = #selector(NSApplication.terminate(_:))
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)
    }
    
    /// 设置文件菜单
    private func setupFileMenu(in mainMenu: NSMenu) {
        // 查找或创建文件菜单
        let fileMenu: NSMenu
        if let existingFileMenu = mainMenu.items.first(where: { $0.title == "文件" })?.submenu {
            fileMenu = existingFileMenu
        } else {
            let fileMenuItem = NSMenuItem()
            fileMenuItem.title = "文件"
            fileMenu = NSMenu(title: "文件")
            fileMenuItem.submenu = fileMenu
            mainMenu.addItem(fileMenuItem)
        }
        
        // 清空现有菜单项（保留系统默认项）
        // 这里我们只添加自定义项，系统会自动添加其他项
        
        // 添加新建笔记菜单项（⌘N）
        let newNoteItem = NSMenuItem()
        newNoteItem.title = "新建笔记"
        newNoteItem.action = #selector(AppDelegate.createNewNote(_:))
        newNoteItem.target = appDelegate
        newNoteItem.keyEquivalent = "n"
        newNoteItem.keyEquivalentModifierMask = [.command]
        fileMenu.insertItem(newNoteItem, at: 0)
        
        // 添加新建文件夹菜单项（⇧⌘N）
        let newFolderItem = NSMenuItem()
        newFolderItem.title = "新建文件夹"
        newFolderItem.action = #selector(AppDelegate.createNewFolder(_:))
        newFolderItem.target = appDelegate
        newFolderItem.keyEquivalent = "n"
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(newFolderItem, at: 1)
        
        // 添加新建窗口菜单项
        let newWindowItem = NSMenuItem()
        newWindowItem.title = "新建窗口"
        newWindowItem.action = #selector(AppDelegate.createNewWindow(_:))
        newWindowItem.target = appDelegate
        newWindowItem.keyEquivalent = "n"
        newWindowItem.keyEquivalentModifierMask = [.command, .option]
        fileMenu.insertItem(newWindowItem, at: 2)
        
        fileMenu.insertItem(NSMenuItem.separator(), at: 3)
        
        // 添加共享菜单项（⇧⌘S）
        let shareItem = NSMenuItem()
        shareItem.title = "共享"
        shareItem.action = #selector(AppDelegate.shareNote(_:))
        shareItem.target = appDelegate
        shareItem.keyEquivalent = "s"
        shareItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(shareItem, at: 4)
        
        fileMenu.insertItem(NSMenuItem.separator(), at: 5)
        
        // 添加导入菜单项（⇧⌘I）
        let importItem = NSMenuItem()
        importItem.title = "导入"
        importItem.action = #selector(AppDelegate.importNotes(_:))
        importItem.target = appDelegate
        importItem.keyEquivalent = "i"
        importItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(importItem, at: 6)
        
        // 添加导出为...菜单项（⇧⌘E）
        let exportItem = NSMenuItem()
        exportItem.title = "导出为..."
        exportItem.action = #selector(AppDelegate.exportNote(_:))
        exportItem.target = appDelegate
        exportItem.keyEquivalent = "e"
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(exportItem, at: 7)
        
        fileMenu.insertItem(NSMenuItem.separator(), at: 8)
        
        // 添加置顶笔记菜单项（⇧⌘P）
        let toggleStarItem = NSMenuItem()
        toggleStarItem.title = "置顶笔记"
        toggleStarItem.action = #selector(AppDelegate.toggleStarNote(_:))
        toggleStarItem.target = appDelegate
        toggleStarItem.keyEquivalent = "p"
        toggleStarItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(toggleStarItem, at: 9)
        
        // 添加复制笔记菜单项（⇧⌘C）
        let copyNoteItem = NSMenuItem()
        copyNoteItem.title = "复制笔记"
        copyNoteItem.action = #selector(AppDelegate.copyNote(_:))
        copyNoteItem.target = appDelegate
        copyNoteItem.keyEquivalent = "c"
        copyNoteItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(copyNoteItem, at: 10)
    }
    
    /// 设置编辑菜单
    private func setupEditMenu(in mainMenu: NSMenu) {
        // 查找或创建编辑菜单
        let editMenu: NSMenu
        if let existingEditMenu = mainMenu.items.first(where: { $0.title == "编辑" })?.submenu {
            editMenu = existingEditMenu
        } else {
            let editMenuItem = NSMenuItem()
            editMenuItem.title = "编辑"
            editMenu = NSMenu(title: "编辑")
            editMenuItem.submenu = editMenu
            mainMenu.addItem(editMenuItem)
        }
        
        // 添加撤销菜单项
        let undoItem = NSMenuItem()
        undoItem.title = "撤销"
        undoItem.action = #selector(AppDelegate.undo(_:))
        undoItem.target = appDelegate
        undoItem.keyEquivalent = "z"
        undoItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(undoItem, at: 0)
        
        // 添加重做菜单项
        let redoItem = NSMenuItem()
        redoItem.title = "重做"
        redoItem.action = #selector(AppDelegate.redo(_:))
        redoItem.target = appDelegate
        redoItem.keyEquivalent = "z"
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.insertItem(redoItem, at: 1)
        
        editMenu.insertItem(NSMenuItem.separator(), at: 2)
        
        // 添加剪切菜单项
        let cutItem = NSMenuItem()
        cutItem.title = "剪切"
        cutItem.action = #selector(AppDelegate.cut(_:))
        cutItem.target = appDelegate
        cutItem.keyEquivalent = "x"
        cutItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(cutItem, at: 3)
        
        // 添加复制菜单项
        let copyItem = NSMenuItem()
        copyItem.title = "复制"
        copyItem.action = #selector(AppDelegate.copy(_:))
        copyItem.target = appDelegate
        copyItem.keyEquivalent = "c"
        copyItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(copyItem, at: 4)
        
        // 添加粘贴菜单项
        let pasteItem = NSMenuItem()
        pasteItem.title = "粘贴"
        pasteItem.action = #selector(AppDelegate.paste(_:))
        pasteItem.target = appDelegate
        pasteItem.keyEquivalent = "v"
        pasteItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(pasteItem, at: 5)
        
        editMenu.insertItem(NSMenuItem.separator(), at: 6)
        
        // 添加全选菜单项
        let selectAllItem = NSMenuItem()
        selectAllItem.title = "全选"
        selectAllItem.action = #selector(AppDelegate.selectAll(_:))
        selectAllItem.target = appDelegate
        selectAllItem.keyEquivalent = "a"
        selectAllItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(selectAllItem, at: 7)

        editMenu.insertItem(NSMenuItem.separator(), at: 8)

        // 添加查找菜单项（⌘F）
        let findItem = NSMenuItem()
        findItem.title = "查找"
        findItem.action = #selector(AppDelegate.showFindPanel(_:))
        findItem.target = appDelegate
        findItem.keyEquivalent = "f"
        findItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(findItem, at: 9)

        // 添加查找和替换菜单项（⌥⌘F）
        let findAndReplaceItem = NSMenuItem()
        findAndReplaceItem.title = "查找和替换"
        findAndReplaceItem.action = #selector(AppDelegate.showFindAndReplacePanel(_:))
        findAndReplaceItem.target = appDelegate
        findAndReplaceItem.keyEquivalent = "f"
        findAndReplaceItem.keyEquivalentModifierMask = [.command, .option]
        editMenu.insertItem(findAndReplaceItem, at: 10)

        // 添加查找下一个菜单项（⌘G）
        let findNextItem = NSMenuItem()
        findNextItem.title = "查找下一个"
        findNextItem.action = #selector(AppDelegate.findNext(_:))
        findNextItem.target = appDelegate
        findNextItem.keyEquivalent = "g"
        findNextItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(findNextItem, at: 11)

        // 添加查找上一个菜单项（⇧⌘G）
        let findPreviousItem = NSMenuItem()
        findPreviousItem.title = "查找上一个"
        findPreviousItem.action = #selector(AppDelegate.findPrevious(_:))
        findPreviousItem.target = appDelegate
        findPreviousItem.keyEquivalent = "g"
        findPreviousItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.insertItem(findPreviousItem, at: 12)
    }
    
    /// 设置格式菜单
    private func setupFormatMenu(in mainMenu: NSMenu) {
        // 创建格式菜单
        let formatMenuItem = NSMenuItem()
        formatMenuItem.title = "格式"
        let formatMenu = NSMenu(title: "格式")
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)
        
        // 字体子菜单
        let fontMenuItem = NSMenuItem()
        fontMenuItem.title = "字体"
        let fontMenu = NSMenu(title: "字体")
        fontMenuItem.submenu = fontMenu
        formatMenu.addItem(fontMenuItem)
        
        // 粗体
        let boldItem = NSMenuItem()
        boldItem.title = "粗体"
        boldItem.action = #selector(AppDelegate.toggleBold(_:))
        boldItem.target = appDelegate
        boldItem.keyEquivalent = "b"
        boldItem.keyEquivalentModifierMask = [.command]
        fontMenu.addItem(boldItem)
        
        // 斜体
        let italicItem = NSMenuItem()
        italicItem.title = "斜体"
        italicItem.action = #selector(AppDelegate.toggleItalic(_:))
        italicItem.target = appDelegate
        italicItem.keyEquivalent = "i"
        italicItem.keyEquivalentModifierMask = [.command]
        fontMenu.addItem(italicItem)
        
        // 下划线
        let underlineItem = NSMenuItem()
        underlineItem.title = "下划线"
        underlineItem.action = #selector(AppDelegate.toggleUnderline(_:))
        underlineItem.target = appDelegate
        underlineItem.keyEquivalent = "u"
        underlineItem.keyEquivalentModifierMask = [.command]
        fontMenu.addItem(underlineItem)
        
        // 删除线
        let strikethroughItem = NSMenuItem()
        strikethroughItem.title = "删除线"
        strikethroughItem.action = #selector(AppDelegate.toggleStrikethrough(_:))
        strikethroughItem.target = appDelegate
        fontMenu.addItem(strikethroughItem)
        
        fontMenu.addItem(NSMenuItem.separator())
        
        // 增大字体
        let biggerItem = NSMenuItem()
        biggerItem.title = "增大字体"
        biggerItem.action = #selector(AppDelegate.increaseFontSize(_:))
        biggerItem.target = appDelegate
        biggerItem.keyEquivalent = "+"
        biggerItem.keyEquivalentModifierMask = [.command]
        fontMenu.addItem(biggerItem)
        
        // 减小字体
        let smallerItem = NSMenuItem()
        smallerItem.title = "减小字体"
        smallerItem.action = #selector(AppDelegate.decreaseFontSize(_:))
        smallerItem.target = appDelegate
        smallerItem.keyEquivalent = "-"
        smallerItem.keyEquivalentModifierMask = [.command]
        fontMenu.addItem(smallerItem)
        
        formatMenu.addItem(NSMenuItem.separator())
        
        // 段落子菜单
        let paragraphMenuItem = NSMenuItem()
        paragraphMenuItem.title = "段落"
        let paragraphMenu = NSMenu(title: "段落")
        paragraphMenuItem.submenu = paragraphMenu
        formatMenu.addItem(paragraphMenuItem)
        
        // 增加缩进
        let increaseIndentItem = NSMenuItem()
        increaseIndentItem.title = "增加缩进"
        increaseIndentItem.action = #selector(AppDelegate.increaseIndent(_:))
        increaseIndentItem.target = appDelegate
        increaseIndentItem.keyEquivalent = "]"
        increaseIndentItem.keyEquivalentModifierMask = [.command]
        paragraphMenu.addItem(increaseIndentItem)
        
        // 减少缩进
        let decreaseIndentItem = NSMenuItem()
        decreaseIndentItem.title = "减少缩进"
        decreaseIndentItem.action = #selector(AppDelegate.decreaseIndent(_:))
        decreaseIndentItem.target = appDelegate
        decreaseIndentItem.keyEquivalent = "["
        decreaseIndentItem.keyEquivalentModifierMask = [.command]
        paragraphMenu.addItem(decreaseIndentItem)
        
        paragraphMenu.addItem(NSMenuItem.separator())
        
        // 居左对齐
        let alignLeftItem = NSMenuItem()
        alignLeftItem.title = "居左对齐"
        alignLeftItem.action = #selector(AppDelegate.alignLeft(_:))
        alignLeftItem.target = appDelegate
        paragraphMenu.addItem(alignLeftItem)
        
        // 居中对齐
        let alignCenterItem = NSMenuItem()
        alignCenterItem.title = "居中对齐"
        alignCenterItem.action = #selector(AppDelegate.alignCenter(_:))
        alignCenterItem.target = appDelegate
        paragraphMenu.addItem(alignCenterItem)
        
        // 居右对齐
        let alignRightItem = NSMenuItem()
        alignRightItem.title = "居右对齐"
        alignRightItem.action = #selector(AppDelegate.alignRight(_:))
        alignRightItem.target = appDelegate
        paragraphMenu.addItem(alignRightItem)
        
        formatMenu.addItem(NSMenuItem.separator())
        
        // 列表子菜单
        let listMenuItem = NSMenuItem()
        listMenuItem.title = "列表"
        let listMenu = NSMenu(title: "列表")
        listMenuItem.submenu = listMenu
        formatMenu.addItem(listMenuItem)
        
        // 无序列表
        let bulletListItem = NSMenuItem()
        bulletListItem.title = "无序列表"
        bulletListItem.action = #selector(AppDelegate.toggleBulletList(_:))
        bulletListItem.target = appDelegate
        listMenu.addItem(bulletListItem)
        
        // 有序列表
        let numberedListItem = NSMenuItem()
        numberedListItem.title = "有序列表"
        numberedListItem.action = #selector(AppDelegate.toggleNumberedList(_:))
        numberedListItem.target = appDelegate
        listMenu.addItem(numberedListItem)
        
        // 复选框列表
        let checkboxListItem = NSMenuItem()
        checkboxListItem.title = "复选框列表"
        checkboxListItem.action = #selector(AppDelegate.toggleCheckboxList(_:))
        checkboxListItem.target = appDelegate
        listMenu.addItem(checkboxListItem)
        
        formatMenu.addItem(NSMenuItem.separator())
        
        // 标题级别
        let headingMenuItem = NSMenuItem()
        headingMenuItem.title = "标题"
        let headingMenu = NSMenu(title: "标题")
        headingMenuItem.submenu = headingMenu
        formatMenu.addItem(headingMenuItem)
        
        // 大标题
        let heading1Item = NSMenuItem()
        heading1Item.title = "大标题"
        heading1Item.action = #selector(AppDelegate.setHeading1(_:))
        heading1Item.target = appDelegate
        headingMenu.addItem(heading1Item)
        
        // 二级标题
        let heading2Item = NSMenuItem()
        heading2Item.title = "二级标题"
        heading2Item.action = #selector(AppDelegate.setHeading2(_:))
        heading2Item.target = appDelegate
        headingMenu.addItem(heading2Item)
        
        // 三级标题
        let heading3Item = NSMenuItem()
        heading3Item.title = "三级标题"
        heading3Item.action = #selector(AppDelegate.setHeading3(_:))
        heading3Item.target = appDelegate
        headingMenu.addItem(heading3Item)
        
        // 正文
        let bodyTextItem = NSMenuItem()
        bodyTextItem.title = "正文"
        bodyTextItem.action = #selector(AppDelegate.setBodyText(_:))
        bodyTextItem.target = appDelegate
        headingMenu.addItem(bodyTextItem)
    }
    
    /// 设置视图菜单
    private func setupViewMenu(in mainMenu: NSMenu) {
        // 查找或创建视图菜单
        let viewMenu: NSMenu
        if let existingViewMenu = mainMenu.items.first(where: { $0.title == "显示" })?.submenu {
            viewMenu = existingViewMenu
        } else {
            let viewMenuItem = NSMenuItem()
            viewMenuItem.title = "显示"
            viewMenu = NSMenu(title: "显示")
            viewMenuItem.submenu = viewMenu
            mainMenu.addItem(viewMenuItem)
        }
        
        // 添加自定义工具栏菜单项
        // 注意：这个菜单项会在有工具栏的窗口激活时自动添加
        // 我们这里确保它存在
        
        // 添加"打开调试菜单"项
        let debugMenuItem = NSMenuItem()
        debugMenuItem.title = "打开调试菜单"
        debugMenuItem.action = #selector(AppDelegate.showDebugSettings(_:))
        debugMenuItem.target = appDelegate
        viewMenu.addItem(debugMenuItem)
    }
    
    /// 设置窗口菜单
    private func setupWindowMenu(in mainMenu: NSMenu) {
        // 窗口菜单通常由系统提供，我们不需要修改
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
        helpMenu.addItem(helpItem)
    }
    
    // MARK: - 清理
    
    deinit {
        print("菜单管理器释放")
    }
}
