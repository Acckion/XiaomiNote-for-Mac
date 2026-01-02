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
        
        // 设置应用程序菜单项
        setupAppMenu(in: mainMenu)
        setupFileMenu(in: mainMenu)
        setupEditMenu(in: mainMenu)
        setupViewMenu(in: mainMenu)
        setupWindowMenu(in: mainMenu)
        setupHelpMenu(in: mainMenu)
        
        print("应用程序菜单设置完成")
    }
    
    /// 设置应用程序菜单
    private func setupAppMenu(in mainMenu: NSMenu) {
        // 应用程序菜单通常是第一个菜单项
        guard mainMenu.items.count > 0 else { return }
        
        let appMenu = mainMenu.items[0].submenu
        
        // 添加关于菜单项
        appMenu?.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem()
        aboutItem.title = "关于备忘录"
        aboutItem.action = #selector(showAboutPanel(_:))
        aboutItem.target = self
        appMenu?.addItem(aboutItem)
        
        // 添加设置菜单项
        let settingsItem = NSMenuItem()
        settingsItem.title = "设置..."
        settingsItem.action = #selector(showSettings(_:))
        settingsItem.target = self
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]
        appMenu?.addItem(settingsItem)
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
        // 编辑菜单通常由系统提供，我们不需要修改
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
        print("显示设置")
        // 这里可以打开设置窗口
        // 暂时使用控制台输出
    }
    
    @objc func createNewWindow(_ sender: Any?) {
        createNewWindow()
    }
    
    @objc func showHelp(_ sender: Any?) {
        print("显示帮助")
        // 这里可以打开帮助文档
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
