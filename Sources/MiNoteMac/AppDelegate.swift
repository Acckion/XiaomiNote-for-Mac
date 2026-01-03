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
        // 当最后一个窗口关闭时终止应用程序
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("应用程序即将终止")
        
        // 保存应用程序状态
        saveApplicationState()
    }
    
    // MARK: - 窗口管理
    
    /// 创建主窗口
    private func createMainWindow() {
        print("创建主窗口...")
        
        // 创建视图模型
        let viewModel = NotesViewModel()
        
        // 创建主窗口控制器
        mainWindowController = MainWindowController(viewModel: viewModel)
        
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
        
        // 显示新窗口
        newWindowController.showWindow(nil)
        newWindowController.window?.makeKeyAndOrderFront(nil)
        
        print("新窗口创建完成")
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
        
        // 添加新建窗口菜单项
        let newWindowItem = NSMenuItem()
        newWindowItem.title = "新建窗口"
        newWindowItem.action = #selector(createNewWindow(_:))
        newWindowItem.target = self
        newWindowItem.keyEquivalent = "n"
        newWindowItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.insertItem(newWindowItem, at: 0)
        
        fileMenu.insertItem(NSMenuItem.separator(), at: 1)
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
        // 这里可以保存应用程序的偏好设置等
        print("保存应用程序状态...")
        
        // 示例：保存窗口位置和大小
        if let window = mainWindowController?.window {
            UserDefaults.standard.set(window.frame.origin.x, forKey: "LastWindowX")
            UserDefaults.standard.set(window.frame.origin.y, forKey: "LastWindowY")
            UserDefaults.standard.set(window.frame.width, forKey: "LastWindowWidth")
            UserDefaults.standard.set(window.frame.height, forKey: "LastWindowHeight")
        }
        
        print("应用程序状态保存完成")
    }
    
    /// 恢复应用程序状态
    private func restoreApplicationState() {
        // 这里可以恢复应用程序的偏好设置等
        print("恢复应用程序状态...")
        
        // 示例：恢复窗口位置和大小
        if let window = mainWindowController?.window {
            let x = UserDefaults.standard.float(forKey: "LastWindowX")
            let y = UserDefaults.standard.float(forKey: "LastWindowY")
            let width = UserDefaults.standard.float(forKey: "LastWindowWidth")
            let height = UserDefaults.standard.float(forKey: "LastWindowHeight")
            
            if x != 0 || y != 0 || width != 0 || height != 0 {
                let frame = NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
                window.setFrame(frame, display: true)
            }
        }
        
        print("应用程序状态恢复完成")
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
