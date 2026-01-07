import AppKit
import MiNoteLibrary

/// 应用程序委托
/// 替代SwiftUI的App结构，采用纯AppKit架构
/// 使用模块化设计，将功能分解到专门的类中
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - 属性
    
    /// 窗口管理器
    private let windowManager: WindowManager
    
    /// 菜单管理器
    private let menuManager: MenuManager
    
    /// 应用程序状态管理器
    private let appStateManager: AppStateManager
    
    /// 菜单动作处理器
    private let menuActionHandler: MenuActionHandler
    
    // MARK: - 初始化
    
    override init() {
        // 首先初始化窗口管理器
        windowManager = WindowManager()
        
        // 初始化菜单管理器（暂时使用 nil，稍后更新）
        menuManager = MenuManager(appDelegate: nil, mainWindowController: windowManager.mainWindowController)
        
        // 初始化应用程序状态管理器
        appStateManager = AppStateManager(windowManager: windowManager, menuManager: menuManager)
        
        // 初始化菜单动作处理器
        menuActionHandler = MenuActionHandler(mainWindowController: windowManager.mainWindowController, windowManager: windowManager)
        
        // 然后调用 super.init()
        super.init()
        
        // 现在可以更新菜单管理器的引用（因为 self 现在可用）
        menuManager.updateReferences(appDelegate: self, mainWindowController: windowManager.mainWindowController)
        
        print("应用程序委托初始化完成")
    }
    
    // MARK: - NSApplicationDelegate
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        appStateManager.handleApplicationDidFinishLaunching()

        // 应用程序启动完成后，更新MenuActionHandler的主窗口控制器引用
        menuActionHandler.updateMainWindowController(windowManager.mainWindowController)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return appStateManager.shouldTerminateAfterLastWindowClosed()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        appStateManager.handleApplicationWillTerminate()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return appStateManager.handleApplicationReopen(hasVisibleWindows: flag)
    }
    
    // MARK: - 公共属性
    
    /// 主窗口控制器（对外暴露）
    var mainWindowController: MainWindowController? {
        return windowManager.mainWindowController
    }
    
    // MARK: - 窗口管理方法（对外暴露）
    
    /// 创建新窗口
    func createNewWindow() {
        windowManager.createNewWindow()
        // 更新菜单动作处理器的引用
        menuActionHandler.updateMainWindowController(windowManager.mainWindowController)
    }
    
    /// 移除窗口控制器
    /// - Parameter windowController: 要移除的窗口控制器
    func removeWindowController(_ windowController: MainWindowController) {
        windowManager.removeWindowController(windowController)
    }
    
    // MARK: - 菜单动作（需要暴露给菜单管理器）
    
    @objc func showAboutPanel(_ sender: Any?) {
        menuActionHandler.showAboutPanel(sender)
    }
    
    @objc func showSettings(_ sender: Any?) {
        menuActionHandler.showSettings(sender)
    }
    
    @objc func createNewWindow(_ sender: Any?) {
        menuActionHandler.createNewWindow(sender)
    }
    
    @objc func showHelp(_ sender: Any?) {
        menuActionHandler.showHelp(sender)
    }
    
    @objc func undo(_ sender: Any?) {
        menuActionHandler.undo(sender)
    }
    
    @objc func redo(_ sender: Any?) {
        menuActionHandler.redo(sender)
    }
    
    @objc func cut(_ sender: Any?) {
        menuActionHandler.cut(sender)
    }
    
    @objc func copy(_ sender: Any?) {
        menuActionHandler.copy(sender)
    }
    
    @objc func paste(_ sender: Any?) {
        menuActionHandler.paste(sender)
    }
    
    @objc func selectAll(_ sender: Any?) {
        menuActionHandler.selectAll(sender)
    }
    
    @objc func toggleBold(_ sender: Any?) {
        menuActionHandler.toggleBold(sender)
    }
    
    @objc func toggleItalic(_ sender: Any?) {
        menuActionHandler.toggleItalic(sender)
    }
    
    @objc func toggleUnderline(_ sender: Any?) {
        menuActionHandler.toggleUnderline(sender)
    }
    
    @objc func toggleStrikethrough(_ sender: Any?) {
        menuActionHandler.toggleStrikethrough(sender)
    }
    
    @objc func increaseFontSize(_ sender: Any?) {
        menuActionHandler.increaseFontSize(sender)
    }
    
    @objc func decreaseFontSize(_ sender: Any?) {
        menuActionHandler.decreaseFontSize(sender)
    }
    
    @objc func increaseIndent(_ sender: Any?) {
        menuActionHandler.increaseIndent(sender)
    }
    
    @objc func decreaseIndent(_ sender: Any?) {
        menuActionHandler.decreaseIndent(sender)
    }
    
    @objc func alignLeft(_ sender: Any?) {
        menuActionHandler.alignLeft(sender)
    }
    
    @objc func alignCenter(_ sender: Any?) {
        menuActionHandler.alignCenter(sender)
    }
    
    @objc func alignRight(_ sender: Any?) {
        menuActionHandler.alignRight(sender)
    }
    
    @objc func toggleBulletList(_ sender: Any?) {
        menuActionHandler.toggleBulletList(sender)
    }
    
    @objc func toggleNumberedList(_ sender: Any?) {
        menuActionHandler.toggleNumberedList(sender)
    }
    
    @objc func toggleCheckboxList(_ sender: Any?) {
        menuActionHandler.toggleCheckboxList(sender)
    }
    
    @objc func setHeading1(_ sender: Any?) {
        menuActionHandler.setHeading1(sender)
    }
    
    @objc func setHeading2(_ sender: Any?) {
        menuActionHandler.setHeading2(sender)
    }
    
    @objc func setHeading3(_ sender: Any?) {
        menuActionHandler.setHeading3(sender)
    }
    
    @objc func setBodyText(_ sender: Any?) {
        menuActionHandler.setBodyText(sender)
    }
    
    @objc func showDebugSettings(_ sender: Any?) {
        menuActionHandler.showDebugSettings(sender)
    }
    
    @objc func showLogin(_ sender: Any?) {
        menuActionHandler.showLogin(sender)
    }
    
    @objc func showCookieRefresh(_ sender: Any?) {
        menuActionHandler.showCookieRefresh(sender)
    }
    
    @objc func showOfflineOperations(_ sender: Any?) {
        menuActionHandler.showOfflineOperations(sender)
    }
    
    @objc func createNewNote(_ sender: Any?) {
        menuActionHandler.createNewNote(sender)
    }
    
    @objc func createNewFolder(_ sender: Any?) {
        menuActionHandler.createNewFolder(sender)
    }
    
    @objc func shareNote(_ sender: Any?) {
        menuActionHandler.shareNote(sender)
    }
    
    @objc func importNotes(_ sender: Any?) {
        menuActionHandler.importNotes(sender)
    }
    
    @objc func exportNote(_ sender: Any?) {
        menuActionHandler.exportNote(sender)
    }
    
    @objc func toggleStarNote(_ sender: Any?) {
        menuActionHandler.toggleStarNote(sender)
    }
    
    @objc func copyNote(_ sender: Any?) {
        menuActionHandler.copyNote(sender)
    }

    // MARK: - 查找功能

    @objc func showFindPanel(_ sender: Any?) {
        menuActionHandler.showFindPanel(sender)
    }

    @objc func showFindAndReplacePanel(_ sender: Any?) {
        menuActionHandler.showFindAndReplacePanel(sender)
    }

    @objc func findNext(_ sender: Any?) {
        menuActionHandler.findNext(sender)
    }

    @objc func findPrevious(_ sender: Any?) {
        menuActionHandler.findPrevious(sender)
    }
    
    // MARK: - 清理
    
    deinit {
        print("应用程序委托释放")
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
