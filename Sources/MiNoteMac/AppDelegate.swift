import AppKit
import MiNoteLibrary

/// 应用程序委托
/// 替代SwiftUI的App结构，采用纯AppKit架构
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - 属性
    
    /// 主窗口控制器
    var mainWindowController: MainWindowController?
    
    /// 应用程序启动完成时间戳
    private var launchTime: Date?
    
    /// 窗口状态管理器
    private let windowStateManager = MiNoteWindowStateManager()
    
    /// 活动窗口控制器列表
    private var windowControllers: [MainWindowController] = []
    
    // MARK: - NSApplicationDelegate
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        launchTime = Date()
        print("应用程序启动完成 - \(Date())")
        
        // 创建主窗口
        createMainWindow()
        
        // 激活应用程序
        NSApp.activate(ignoringOtherApps: true)
        
        // 设置应用程序菜单
        setupApplicationMenu()
        
        print("应用程序初始化完成，耗时: \(String(format: "%.2f", Date().timeIntervalSince(launchTime!)))秒")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 当最后一个窗口关闭时不终止应用程序，符合 macOS 标准行为
        // 用户可以通过菜单或 Dock 退出应用
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("应用程序即将终止")
        
        // 保存应用程序状态
        saveApplicationState()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        print("应用程序重新打开，是否有可见窗口: \(flag)")
        
        // 获取所有窗口（包括最小化的）
        let allWindows = getAllWindows()
        print("当前窗口总数: \(allWindows.count)")
        
        if allWindows.isEmpty {
            // 如果没有任何窗口（包括最小化的），创建新的主窗口
            print("没有窗口，创建新主窗口")
            createMainWindow()
        } else if !flag {
            // 如果有窗口但不可见（可能被最小化），将它们前置显示
            print("有窗口但不可见，前置显示所有窗口")
            bringAllWindowsToFront()
        } else {
            // 如果有可见窗口，激活应用程序
            print("已有可见窗口，激活应用程序")
            NSApp.activate(ignoringOtherApps: true)
        }
        
        return true
    }
    
    // MARK: - 窗口管理
    
    /// 创建主窗口
    private func createMainWindow() {
        print("创建主窗口...")
        
        // 创建视图模型
        let viewModel = NotesViewModel()
        
        // 创建主窗口控制器
        mainWindowController = MainWindowController(viewModel: viewModel)
        
        // 添加到窗口控制器列表
        if let controller = mainWindowController {
            windowControllers.append(controller)
        }
        
        // 恢复窗口状态
        restoreApplicationState()
        
        // 恢复窗口 frame
        if let window = mainWindowController?.window {
            restoreWindowFrame(window)
        }
        
        // 显示窗口
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        
        print("主窗口创建完成")
    }
    
    /// 创建新窗口
    func createNewWindow() {
        print("创建新窗口...")
        
        // 创建新的视图模型
        let viewModel = NotesViewModel()
        
        // 创建新的窗口控制器
        let newWindowController = MainWindowController(viewModel: viewModel)
        
        // 添加到窗口控制器列表
        windowControllers.append(newWindowController)
        
        // 为新窗口分配一个唯一的 ID
        let windowId = "window_\(windowControllers.count - 1)"
        
        // 恢复新窗口的 frame（如果有保存的状态）
        if let window = newWindowController.window {
            restoreWindowFrame(window, windowId: windowId)
        }
        
        // 显示新窗口
        newWindowController.showWindow(nil)
        newWindowController.window?.makeKeyAndOrderFront(nil)
        
        print("新窗口创建完成，窗口ID: \(windowId)")
    }
    
    /// 移除窗口控制器
    /// - Parameter windowController: 要移除的窗口控制器
    func removeWindowController(_ windowController: MainWindowController) {
        if let index = windowControllers.firstIndex(where: { $0 === windowController }) {
            windowControllers.remove(at: index)
            print("窗口控制器已移除，剩余窗口数: \(windowControllers.count)")
        }
    }
    
    /// 获取所有活动窗口
    /// - Returns: 活动窗口数组
    func getAllWindows() -> [NSWindow] {
        var windows: [NSWindow] = []
        
        if let mainWindow = mainWindowController?.window {
            windows.append(mainWindow)
        }
        
        for controller in windowControllers {
            if let window = controller.window {
                windows.append(window)
            }
        }
        
        return windows
    }
    
    /// 将所有窗口前置显示
    func bringAllWindowsToFront() {
        for window in getAllWindows() {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    // MARK: - 应用程序菜单设置
    
    /// 设置应用程序菜单
    private func setupApplicationMenu() {
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
    
    /// 设置应用程序菜单
    private func setupAppMenu(in mainMenu: NSMenu) {
        // 创建应用程序菜单项
        let appMenuItem = NSMenuItem()
        appMenuItem.title = "备忘录"
        let appMenu = NSMenu(title: "备忘录")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 添加关于菜单项
        let aboutItem = NSMenuItem()
        aboutItem.title = "关于备忘录"
        aboutItem.action = #selector(showAboutPanel(_:))
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // 添加设置菜单项
        let settingsItem = NSMenuItem()
        settingsItem.title = "设置..."
        settingsItem.action = #selector(showSettings(_:))
        settingsItem.target = self
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(settingsItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // 添加退出菜单项（系统会自动添加，但我们也可以手动添加）
        let quitItem = NSMenuItem()
        quitItem.title = "退出备忘录"
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
        
        // 添加新建备忘录菜单项（⌘N）
        let newNoteItem = NSMenuItem()
        newNoteItem.title = "新建备忘录"
        newNoteItem.action = #selector(createNewNote(_:))
        newNoteItem.target = self
        newNoteItem.keyEquivalent = "n"
        newNoteItem.keyEquivalentModifierMask = [.command]
        fileMenu.insertItem(newNoteItem, at: 0)
        
        // 添加新建文件夹菜单项（⇧⌘N）
        let newFolderItem = NSMenuItem()
        newFolderItem.title = "新建文件夹"
        newFolderItem.action = #selector(createNewFolder(_:))
        newFolderItem.target = self
        newFolderItem.keyEquivalent = "n"
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(newFolderItem, at: 1)
        
        // 添加新建窗口菜单项
        let newWindowItem = NSMenuItem()
        newWindowItem.title = "新建窗口"
        newWindowItem.action = #selector(createNewWindow(_:))
        newWindowItem.target = self
        newWindowItem.keyEquivalent = "n"
        newWindowItem.keyEquivalentModifierMask = [.command, .option]
        fileMenu.insertItem(newWindowItem, at: 2)
        
        fileMenu.insertItem(NSMenuItem.separator(), at: 3)
        
        // 添加共享菜单项（⇧⌘S）
        let shareItem = NSMenuItem()
        shareItem.title = "共享"
        shareItem.action = #selector(shareNote(_:))
        shareItem.target = self
        shareItem.keyEquivalent = "s"
        shareItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(shareItem, at: 4)
        
        fileMenu.insertItem(NSMenuItem.separator(), at: 5)
        
        // 添加导入菜单项（⇧⌘I）
        let importItem = NSMenuItem()
        importItem.title = "导入"
        importItem.action = #selector(importNotes(_:))
        importItem.target = self
        importItem.keyEquivalent = "i"
        importItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(importItem, at: 6)
        
        // 添加导出为...菜单项（⇧⌘E）
        let exportItem = NSMenuItem()
        exportItem.title = "导出为..."
        exportItem.action = #selector(exportNote(_:))
        exportItem.target = self
        exportItem.keyEquivalent = "e"
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(exportItem, at: 7)
        
        fileMenu.insertItem(NSMenuItem.separator(), at: 8)
        
        // 添加置顶备忘录菜单项（⇧⌘P）
        let toggleStarItem = NSMenuItem()
        toggleStarItem.title = "置顶备忘录"
        toggleStarItem.action = #selector(toggleStarNote(_:))
        toggleStarItem.target = self
        toggleStarItem.keyEquivalent = "p"
        toggleStarItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(toggleStarItem, at: 9)
        
        // 添加复制备忘录菜单项（⇧⌘C）
        let copyNoteItem = NSMenuItem()
        copyNoteItem.title = "复制备忘录"
        copyNoteItem.action = #selector(copyNote(_:))
        copyNoteItem.target = self
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
        undoItem.action = #selector(undo(_:))
        undoItem.target = self
        undoItem.keyEquivalent = "z"
        undoItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(undoItem, at: 0)
        
        // 添加重做菜单项
        let redoItem = NSMenuItem()
        redoItem.title = "重做"
        redoItem.action = #selector(redo(_:))
        redoItem.target = self
        redoItem.keyEquivalent = "z"
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.insertItem(redoItem, at: 1)
        
        editMenu.insertItem(NSMenuItem.separator(), at: 2)
        
        // 添加剪切菜单项
        let cutItem = NSMenuItem()
        cutItem.title = "剪切"
        cutItem.action = #selector(cut(_:))
        cutItem.target = self
        cutItem.keyEquivalent = "x"
        cutItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(cutItem, at: 3)
        
        // 添加复制菜单项
        let copyItem = NSMenuItem()
        copyItem.title = "复制"
        copyItem.action = #selector(copy(_:))
        copyItem.target = self
        copyItem.keyEquivalent = "c"
        copyItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(copyItem, at: 4)
        
        // 添加粘贴菜单项
        let pasteItem = NSMenuItem()
        pasteItem.title = "粘贴"
        pasteItem.action = #selector(paste(_:))
        pasteItem.target = self
        pasteItem.keyEquivalent = "v"
        pasteItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(pasteItem, at: 5)
        
        editMenu.insertItem(NSMenuItem.separator(), at: 6)
        
        // 添加全选菜单项
        let selectAllItem = NSMenuItem()
        selectAllItem.title = "全选"
        selectAllItem.action = #selector(selectAll(_:))
        selectAllItem.target = self
        selectAllItem.keyEquivalent = "a"
        selectAllItem.keyEquivalentModifierMask = [.command]
        editMenu.insertItem(selectAllItem, at: 7)
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
        boldItem.action = #selector(toggleBold(_:))
        boldItem.target = self
        boldItem.keyEquivalent = "b"
        boldItem.keyEquivalentModifierMask = [.command]
        fontMenu.addItem(boldItem)
        
        // 斜体
        let italicItem = NSMenuItem()
        italicItem.title = "斜体"
        italicItem.action = #selector(toggleItalic(_:))
        italicItem.target = self
        italicItem.keyEquivalent = "i"
        italicItem.keyEquivalentModifierMask = [.command]
        fontMenu.addItem(italicItem)
        
        // 下划线
        let underlineItem = NSMenuItem()
        underlineItem.title = "下划线"
        underlineItem.action = #selector(toggleUnderline(_:))
        underlineItem.target = self
        underlineItem.keyEquivalent = "u"
        underlineItem.keyEquivalentModifierMask = [.command]
        fontMenu.addItem(underlineItem)
        
        // 删除线
        let strikethroughItem = NSMenuItem()
        strikethroughItem.title = "删除线"
        strikethroughItem.action = #selector(toggleStrikethrough(_:))
        strikethroughItem.target = self
        fontMenu.addItem(strikethroughItem)
        
        fontMenu.addItem(NSMenuItem.separator())
        
        // 增大字体
        let biggerItem = NSMenuItem()
        biggerItem.title = "增大字体"
        biggerItem.action = #selector(increaseFontSize(_:))
        biggerItem.target = self
        biggerItem.keyEquivalent = "+"
        biggerItem.keyEquivalentModifierMask = [.command]
        fontMenu.addItem(biggerItem)
        
        // 减小字体
        let smallerItem = NSMenuItem()
        smallerItem.title = "减小字体"
        smallerItem.action = #selector(decreaseFontSize(_:))
        smallerItem.target = self
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
        increaseIndentItem.action = #selector(increaseIndent(_:))
        increaseIndentItem.target = self
        increaseIndentItem.keyEquivalent = "]"
        increaseIndentItem.keyEquivalentModifierMask = [.command]
        paragraphMenu.addItem(increaseIndentItem)
        
        // 减少缩进
        let decreaseIndentItem = NSMenuItem()
        decreaseIndentItem.title = "减少缩进"
        decreaseIndentItem.action = #selector(decreaseIndent(_:))
        decreaseIndentItem.target = self
        decreaseIndentItem.keyEquivalent = "["
        decreaseIndentItem.keyEquivalentModifierMask = [.command]
        paragraphMenu.addItem(decreaseIndentItem)
        
        paragraphMenu.addItem(NSMenuItem.separator())
        
        // 居左对齐
        let alignLeftItem = NSMenuItem()
        alignLeftItem.title = "居左对齐"
        alignLeftItem.action = #selector(alignLeft(_:))
        alignLeftItem.target = self
        paragraphMenu.addItem(alignLeftItem)
        
        // 居中对齐
        let alignCenterItem = NSMenuItem()
        alignCenterItem.title = "居中对齐"
        alignCenterItem.action = #selector(alignCenter(_:))
        alignCenterItem.target = self
        paragraphMenu.addItem(alignCenterItem)
        
        // 居右对齐
        let alignRightItem = NSMenuItem()
        alignRightItem.title = "居右对齐"
        alignRightItem.action = #selector(alignRight(_:))
        alignRightItem.target = self
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
        bulletListItem.action = #selector(toggleBulletList(_:))
        bulletListItem.target = self
        listMenu.addItem(bulletListItem)
        
        // 有序列表
        let numberedListItem = NSMenuItem()
        numberedListItem.title = "有序列表"
        numberedListItem.action = #selector(toggleNumberedList(_:))
        numberedListItem.target = self
        listMenu.addItem(numberedListItem)
        
        // 复选框列表
        let checkboxListItem = NSMenuItem()
        checkboxListItem.title = "复选框列表"
        checkboxListItem.action = #selector(toggleCheckboxList(_:))
        checkboxListItem.target = self
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
        heading1Item.action = #selector(setHeading1(_:))
        heading1Item.target = self
        headingMenu.addItem(heading1Item)
        
        // 二级标题
        let heading2Item = NSMenuItem()
        heading2Item.title = "二级标题"
        heading2Item.action = #selector(setHeading2(_:))
        heading2Item.target = self
        headingMenu.addItem(heading2Item)
        
        // 三级标题
        let heading3Item = NSMenuItem()
        heading3Item.title = "三级标题"
        heading3Item.action = #selector(setHeading3(_:))
        heading3Item.target = self
        headingMenu.addItem(heading3Item)
        
        // 正文
        let bodyTextItem = NSMenuItem()
        bodyTextItem.title = "正文"
        bodyTextItem.action = #selector(setBodyText(_:))
        bodyTextItem.target = self
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
        helpItem.title = "备忘录帮助"
        helpItem.action = #selector(showHelp(_:))
        helpItem.target = self
        helpMenu.addItem(helpItem)
    }
    
    // MARK: - 应用程序状态管理
    
    /// 保存应用程序状态
    private func saveApplicationState() {
        print("保存应用程序状态...")
        
        // 迁移旧版窗口状态
        windowStateManager.migrateLegacyWindowState()
        
        // 保存所有活动窗口的状态
        for (index, windowController) in windowControllers.enumerated() {
            if let windowState = windowController.savableWindowState() {
                windowStateManager.saveWindowState(windowState, forWindowId: "window_\(index)")
            }
            
            // 同时保存窗口 frame
            if let window = windowController.window {
                windowStateManager.saveWindowFrame(window.frame, forWindowId: "window_\(index)")
            }
        }
        
        // 保存主窗口状态
        if let mainWindowController = mainWindowController {
            if let windowState = mainWindowController.savableWindowState() {
                windowStateManager.saveWindowState(windowState, forWindowId: "main")
            }
            
            if let window = mainWindowController.window {
                windowStateManager.saveWindowFrame(window.frame, forWindowId: "main")
            }
        }
        
        print("应用程序状态保存完成")
    }
    
    /// 恢复应用程序状态
    private func restoreApplicationState() {
        print("恢复应用程序状态...")
        
        // 迁移旧版窗口状态
        windowStateManager.migrateLegacyWindowState()
        
        // 恢复主窗口状态
        if let mainWindowController = mainWindowController,
           let savedState = windowStateManager.getWindowState(forWindowId: "main") as? MainWindowState {
            mainWindowController.restoreWindowState(savedState)
        }
        
        print("应用程序状态恢复完成")
    }
    
    /// 恢复窗口 frame
    /// - Parameters:
    ///   - window: 要恢复的窗口
    ///   - windowId: 窗口标识符
    private func restoreWindowFrame(_ window: NSWindow, windowId: String = "main") {
        if let savedFrame = windowStateManager.getWindowFrame(forWindowId: windowId) {
            // 确保窗口在屏幕内
            var newFrame = NSRect(origin: savedFrame.origin, size: savedFrame.size)
            
            // 简单的屏幕边界检查
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                
                // 确保窗口不会超出屏幕
                if newFrame.maxX > screenFrame.maxX {
                    newFrame.origin.x = screenFrame.maxX - newFrame.width
                }
                if newFrame.minX < screenFrame.minX {
                    newFrame.origin.x = screenFrame.minX
                }
                if newFrame.maxY > screenFrame.maxY {
                    newFrame.origin.y = screenFrame.maxY - newFrame.height
                }
                if newFrame.minY < screenFrame.minY {
                    newFrame.origin.y = screenFrame.minY
                }
                
                // 确保窗口大小合适
                if newFrame.width > screenFrame.width {
                    newFrame.size.width = screenFrame.width
                }
                if newFrame.height > screenFrame.height {
                    newFrame.size.height = screenFrame.height
                }
                if newFrame.width < 800 {
                    newFrame.size.width = 800
                }
                if newFrame.height < 600 {
                    newFrame.size.height = 600
                }
            }
            
            window.setFrame(newFrame, display: true)
        } else {
            // 如果没有保存的状态，使用默认设置
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let defaultSize = NSSize(width: 1200, height: 800)
                let defaultOrigin = NSPoint(
                    x: screenFrame.midX - defaultSize.width / 2,
                    y: screenFrame.midY - defaultSize.height / 2
                )
                window.setFrame(NSRect(origin: defaultOrigin, size: defaultSize), display: true)
            }
        }
    }
    
    // MARK: - 菜单动作
    
    @objc func showAboutPanel(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "备忘录"
        alert.informativeText = "版本 1.0.0\n\n一个简洁的笔记应用程序，支持小米笔记同步。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    @objc func showSettings(_ sender: Any?) {
        print("显示设置窗口")
        
        // 创建设置窗口控制器
        let settingsWindowController = MiNoteLibrary.SettingsWindowController(viewModel: mainWindowController?.viewModel)
        
        // 显示窗口
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc func createNewWindow(_ sender: Any?) {
        createNewWindow()
    }
    
    @objc func showHelp(_ sender: Any?) {
        print("显示帮助")
        // 这里可以打开帮助文档
        // 暂时使用控制台输出
    }
    
    // MARK: - 编辑菜单动作
    
    @objc func undo(_ sender: Any?) {
        print("撤销")
        // 转发到主窗口控制器
        mainWindowController?.undo(sender)
    }
    
    @objc func redo(_ sender: Any?) {
        print("重做")
        // 转发到主窗口控制器
        mainWindowController?.redo(sender)
    }
    
    @objc func cut(_ sender: Any?) {
        print("剪切")
        // 转发到主窗口控制器
        mainWindowController?.cut(sender)
    }
    
    @objc func copy(_ sender: Any?) {
        print("复制")
        // 转发到主窗口控制器
        mainWindowController?.copy(sender)
    }
    
    @objc func paste(_ sender: Any?) {
        print("粘贴")
        // 转发到主窗口控制器
        mainWindowController?.paste(sender)
    }
    
    @objc func selectAll(_ sender: Any?) {
        print("全选")
        // 转发到主窗口控制器
        mainWindowController?.selectAll(sender)
    }
    
    // MARK: - 格式菜单动作
    
    @objc func toggleBold(_ sender: Any?) {
        print("切换粗体")
        // 转发到主窗口控制器
        mainWindowController?.toggleBold(sender)
    }
    
    @objc func toggleItalic(_ sender: Any?) {
        print("切换斜体")
        // 转发到主窗口控制器
        mainWindowController?.toggleItalic(sender)
    }
    
    @objc func toggleUnderline(_ sender: Any?) {
        print("切换下划线")
        // 转发到主窗口控制器
        mainWindowController?.toggleUnderline(sender)
    }
    
    @objc func toggleStrikethrough(_ sender: Any?) {
        print("切换删除线")
        // 转发到主窗口控制器
        mainWindowController?.toggleStrikethrough(sender)
    }
    
    @objc func increaseFontSize(_ sender: Any?) {
        print("增大字体")
        // 转发到主窗口控制器
        mainWindowController?.increaseFontSize(sender)
    }
    
    @objc func decreaseFontSize(_ sender: Any?) {
        print("减小字体")
        // 转发到主窗口控制器
        mainWindowController?.decreaseFontSize(sender)
    }
    
    @objc func increaseIndent(_ sender: Any?) {
        print("增加缩进")
        // 转发到主窗口控制器
        mainWindowController?.increaseIndent(sender)
    }
    
    @objc func decreaseIndent(_ sender: Any?) {
        print("减少缩进")
        // 转发到主窗口控制器
        mainWindowController?.decreaseIndent(sender)
    }
    
    @objc func alignLeft(_ sender: Any?) {
        print("居左对齐")
        // 转发到主窗口控制器
        mainWindowController?.alignLeft(sender)
    }
    
    @objc func alignCenter(_ sender: Any?) {
        print("居中对齐")
        // 转发到主窗口控制器
        mainWindowController?.alignCenter(sender)
    }
    
    @objc func alignRight(_ sender: Any?) {
        print("居右对齐")
        // 转发到主窗口控制器
        mainWindowController?.alignRight(sender)
    }
    
    @objc func toggleBulletList(_ sender: Any?) {
        print("切换无序列表")
        // 转发到主窗口控制器
        mainWindowController?.toggleBulletList(sender)
    }
    
    @objc func toggleNumberedList(_ sender: Any?) {
        print("切换有序列表")
        // 转发到主窗口控制器
        mainWindowController?.toggleNumberedList(sender)
    }
    
    @objc func toggleCheckboxList(_ sender: Any?) {
        print("切换复选框列表")
        // 转发到主窗口控制器
        mainWindowController?.toggleCheckboxList(sender)
    }
    
    @objc func setHeading1(_ sender: Any?) {
        print("设置大标题")
        // 转发到主窗口控制器
        mainWindowController?.setHeading1(sender)
    }
    
    @objc func setHeading2(_ sender: Any?) {
        print("设置二级标题")
        // 转发到主窗口控制器
        mainWindowController?.setHeading2(sender)
    }
    
    @objc func setHeading3(_ sender: Any?) {
        print("设置三级标题")
        // 转发到主窗口控制器
        mainWindowController?.setHeading3(sender)
    }
    
    @objc func setBodyText(_ sender: Any?) {
        print("设置正文")
        // 转发到主窗口控制器
        mainWindowController?.setBodyText(sender)
    }
    
    // MARK: - 其他菜单动作
    
    @objc func showDebugSettings(_ sender: Any?) {
        print("显示调试设置窗口")
        
        // 创建调试窗口控制器
        let debugWindowController = MiNoteLibrary.DebugWindowController(viewModel: mainWindowController?.viewModel)
        
        // 显示窗口
        debugWindowController.showWindow(nil)
        debugWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc func showLogin(_ sender: Any?) {
        print("显示登录窗口")
        
        // 创建登录窗口控制器
        let loginWindowController = MiNoteLibrary.LoginWindowController(viewModel: mainWindowController?.viewModel)
        
        // 显示窗口
        loginWindowController.showWindow(nil)
        loginWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc func showCookieRefresh(_ sender: Any?) {
        print("显示Cookie刷新窗口")
        
        // 创建Cookie刷新窗口控制器
        let cookieRefreshWindowController = MiNoteLibrary.CookieRefreshWindowController(viewModel: mainWindowController?.viewModel)
        
        // 显示窗口
        cookieRefreshWindowController.showWindow(nil)
        cookieRefreshWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc func showOfflineOperations(_ sender: Any?) {
        print("显示离线操作")
        // 这里可以打开离线操作窗口
        // 暂时使用控制台输出
    }
    
    // MARK: - 文件菜单新增动作
    
    @objc func createNewNote(_ sender: Any?) {
        print("创建新备忘录")
        // 转发到主窗口控制器
        mainWindowController?.createNewNote(sender)
    }
    
    @objc func createNewFolder(_ sender: Any?) {
        print("创建新文件夹")
        // 转发到主窗口控制器
        mainWindowController?.createNewFolder(sender)
    }
    
    @objc func shareNote(_ sender: Any?) {
        print("共享备忘录")
        // 转发到主窗口控制器
        mainWindowController?.shareNote(sender)
    }
    
    @objc func importNotes(_ sender: Any?) {
        print("导入笔记")
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
                            print("[AppDelegate] 导入笔记失败: \(error)")
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
    
    @objc func exportNote(_ sender: Any?) {
        print("导出笔记")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = "请先选择一个要导出的备忘录"
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
                    print("[AppDelegate] 导出笔记失败: \(error)")
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "导出失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    errorAlert.runModal()
                }
            }
        }
    }
    
    @objc func toggleStarNote(_ sender: Any?) {
        print("置顶/取消置顶备忘录")
        guard let note = mainWindowController?.viewModel?.selectedNote else { return }
        mainWindowController?.viewModel?.toggleStar(note)
    }
    
    @objc func copyNote(_ sender: Any?) {
        print("复制备忘录")
        guard let note = mainWindowController?.viewModel?.selectedNote else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // 复制标题和内容
        let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
        pasteboard.setString(content, forType: .string)
    }
}

// MARK: - 简单的窗口状态管理器

/// 简单的窗口状态管理器，用于在 AppDelegate 中管理窗口状态
class MiNoteWindowStateManager {
    
    private let userDefaults = UserDefaults.standard
    
    /// 保存窗口 frame
    func saveWindowFrame(_ frame: CGRect, forWindowId windowId: String = "main") {
        let frameDict: [String: CGFloat] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height
        ]
        
        var savedFrames = userDefaults.dictionary(forKey: "MiNoteWindowFrames") ?? [:]
        savedFrames[windowId] = frameDict
        
        userDefaults.set(savedFrames, forKey: "MiNoteWindowFrames")
        print("窗口 frame 保存成功: \(windowId)")
    }
    
    /// 获取保存的窗口 frame
    func getWindowFrame(forWindowId windowId: String = "main") -> CGRect? {
        guard let savedFrames = userDefaults.dictionary(forKey: "MiNoteWindowFrames"),
              let frameDict = savedFrames[windowId] as? [String: CGFloat],
              let x = frameDict["x"],
              let y = frameDict["y"],
              let width = frameDict["width"],
              let height = frameDict["height"] else {
            return nil
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    /// 迁移旧版窗口状态
    func migrateLegacyWindowState() {
        // 检查是否有旧版窗口状态
        let legacyX = userDefaults.float(forKey: "LastWindowX")
        let legacyY = userDefaults.float(forKey: "LastWindowY")
        let legacyWidth = userDefaults.float(forKey: "LastWindowWidth")
        let legacyHeight = userDefaults.float(forKey: "LastWindowHeight")
        
        if legacyX != 0 || legacyY != 0 || legacyWidth != 0 || legacyHeight != 0 {
            // 创建新的窗口状态
            let frame = CGRect(x: CGFloat(legacyX), y: CGFloat(legacyY), 
                             width: CGFloat(legacyWidth), height: CGFloat(legacyHeight))
            saveWindowFrame(frame)
            
            // 清除旧版数据
            userDefaults.removeObject(forKey: "LastWindowX")
            userDefaults.removeObject(forKey: "LastWindowY")
            userDefaults.removeObject(forKey: "LastWindowWidth")
            userDefaults.removeObject(forKey: "LastWindowHeight")
            
            print("旧版窗口状态迁移完成")
        }
    }
    
    // 为了兼容性，提供空的方法
    func saveWindowState(_ windowState: Any, forWindowId windowId: String = "main") {
        print("保存窗口状态（简化版）: \(windowId)")
    }
    
    func getWindowState(forWindowId windowId: String = "main") -> Any? {
        return nil
    }
}

// MARK: - 应用程序启动器

/// 应用程序启动器
/// 确保应用程序正确启动
class ApplicationLauncher {
    @MainActor
    static func launch() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
