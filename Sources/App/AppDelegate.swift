import AppKit
import MiNoteLibrary

/// 应用程序委托
/// 替代SwiftUI的App结构，采用纯AppKit架构
/// 使用模块化设计，将功能分解到专门的类中
@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    // MARK: - 属性

    /// 窗口管理器（使用共享实例）
    private let windowManager = WindowManager.shared

    /// 菜单管理器
    private let menuManager: MenuManager

    /// 应用程序状态管理器
    private let appStateManager: AppStateManager

    /// 菜单动作处理器
    private let menuActionHandler: MenuActionHandler

    // MARK: - 架构

    /// 应用协调器（对外只读访问）
    private(set) var appCoordinator: AppCoordinator?

    // MARK: - 初始化

    override init() {
        // 获取窗口管理器共享实例
        let windowManager = WindowManager.shared

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

    public func applicationDidFinishLaunching(_: Notification) {
        // 配置依赖注入服务
        ServiceLocator.shared.configure()

        print("")
        print("========================================")
        print("🚀 应用启动")
        print("========================================")
        print("📦 架构: AppCoordinator + 7 个 ViewModel")
        print("")
        print("   组件列表:")
        print("   • NoteListViewModel      - 笔记列表管理")
        print("   • NoteEditorViewModel    - 笔记编辑器")
        print("   • SyncCoordinator        - 同步协调")
        print("   • AuthenticationViewModel - 认证管理")
        print("   • SearchViewModel        - 搜索功能")
        print("   • FolderViewModel        - 文件夹管理")
        print("   • AudioPanelViewModel    - 音频面板")
        print("")
        print("========================================")

        // 创建 AppCoordinator
        let coordinator = AppCoordinator()
        appCoordinator = coordinator

        // 配置 WindowManager（为未来的多窗口支持做准备）
        WindowManager.shared.setAppCoordinator(coordinator)

        // 启动应用
        Task { @MainActor in
            await coordinator.start()
        }

        appStateManager.handleApplicationDidFinishLaunching()

        // 应用程序启动完成后，更新MenuActionHandler的主窗口控制器引用
        menuActionHandler.updateMainWindowController(windowManager.mainWindowController)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        appStateManager.shouldTerminateAfterLastWindowClosed()
    }

    public func applicationWillTerminate(_: Notification) {
        appStateManager.handleApplicationWillTerminate()
    }

    public func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appStateManager.handleApplicationReopen(hasVisibleWindows: flag)
    }

    // MARK: - 公共属性

    /// 主窗口控制器（对外暴露）
    var mainWindowController: MainWindowController? {
        windowManager.mainWindowController
    }

    /// 应用协调器（对外暴露）
    var coordinator: AppCoordinator? {
        appCoordinator
    }

    // MARK: - 窗口管理方法（对外暴露）

    /// 创建新窗口
    func createNewWindow() {
        windowManager.createNewWindow()
        // 更新菜单动作处理器的引用
        menuActionHandler.updateMainWindowController(windowManager.mainWindowController)
    }

    /// 创建新窗口并打开指定笔记
    ///
    /// 注意：此方法为多窗口支持预留，当前实现将在任务 5 完成后启用
    ///
    /// - Parameter note: 要在新窗口中打开的笔记
    public func createNewWindow(withNote _: Note?) {
        // TODO: 任务 5 完成后，使用 WindowManager.shared.createNewWindow(withNote:)
        // 当前暂时使用旧的实现
        windowManager.createNewWindow()
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

    // 注意：撤销、重做、剪切、复制、粘贴、全选等基础编辑操作
    // 现在使用标准 NSText/NSResponder 选择器，由系统自动路由到响应链
    // 以下方法保留用于向后兼容和工具栏按钮

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

    // MARK: - 旧版格式菜单动作（向后兼容）

    // 注意：这些方法保留用于向后兼容，新的菜单系统使用 Apple Notes 风格的方法

    @objc func increaseFontSize(_ sender: Any?) {
        menuActionHandler.increaseFontSize(sender)
    }

    @objc func decreaseFontSize(_ sender: Any?) {
        menuActionHandler.decreaseFontSize(sender)
    }

    /// 注意：toggleBulletList 和 toggleNumberedList 现在映射到 toggleUnorderedList 和 toggleOrderedList
    @objc func toggleBulletList(_ sender: Any?) {
        menuActionHandler.toggleBulletList(sender)
    }

    @objc func toggleNumberedList(_ sender: Any?) {
        menuActionHandler.toggleNumberedList(sender)
    }

    @objc func toggleCheckboxList(_ sender: Any?) {
        menuActionHandler.toggleCheckboxList(sender)
    }

    /// 注意：setHeading1/2/3 现在映射到 setHeading/setSubheading/setSubtitle
    @objc func setHeading1(_ sender: Any?) {
        menuActionHandler.setHeading1(sender)
    }

    @objc func setHeading2(_ sender: Any?) {
        menuActionHandler.setHeading2(sender)
    }

    @objc func setHeading3(_ sender: Any?) {
        menuActionHandler.setHeading3(sender)
    }

    // MARK: - 格式菜单动作（Apple Notes 风格）

    // 这些是新的菜单系统使用的方法

    @objc func setHeading(_ sender: Any?) {
        menuActionHandler.setHeading(sender)
    }

    @objc func setSubheading(_ sender: Any?) {
        menuActionHandler.setSubheading(sender)
    }

    @objc func setSubtitle(_ sender: Any?) {
        menuActionHandler.setSubtitle(sender)
    }

    @objc func setBodyText(_ sender: Any?) {
        menuActionHandler.setBodyText(sender)
    }

    @objc func toggleOrderedList(_ sender: Any?) {
        menuActionHandler.toggleOrderedList(sender)
    }

    @objc func toggleUnorderedList(_ sender: Any?) {
        menuActionHandler.toggleUnorderedList(sender)
    }

    @objc func toggleBlockQuote(_ sender: Any?) {
        menuActionHandler.toggleBlockQuote(sender)
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

    // MARK: - 核对清单动作

    @objc func toggleChecklist(_ sender: Any?) {
        menuActionHandler.toggleChecklist(sender)
    }

    @objc func markAsChecked(_ sender: Any?) {
        menuActionHandler.markAsChecked(sender)
    }

    @objc func checkAll(_ sender: Any?) {
        menuActionHandler.checkAll(sender)
    }

    @objc func uncheckAll(_ sender: Any?) {
        menuActionHandler.uncheckAll(sender)
    }

    @objc func moveCheckedToBottom(_ sender: Any?) {
        menuActionHandler.moveCheckedToBottom(sender)
    }

    @objc func deleteCheckedItems(_ sender: Any?) {
        menuActionHandler.deleteCheckedItems(sender)
    }

    @objc func moveItemUp(_ sender: Any?) {
        menuActionHandler.moveItemUp(sender)
    }

    @objc func moveItemDown(_ sender: Any?) {
        menuActionHandler.moveItemDown(sender)
    }

    // MARK: - 外观动作

    @objc func toggleLightBackground(_ sender: Any?) {
        menuActionHandler.toggleLightBackground(sender)
    }

    @objc func toggleHighlight(_ sender: Any?) {
        menuActionHandler.toggleHighlight(sender)
    }

    // MARK: - 调试菜单动作

    // 这些方法用于调试功能，不在主菜单中显示

    @objc func showDebugSettings(_ sender: Any?) {
        menuActionHandler.showDebugSettings(sender)
    }

    @objc func showParagraphDebugWindow(_ sender: Any?) {
        menuActionHandler.showParagraphDebugWindow(sender)
    }

    @objc func testAudioFileAPI(_ sender: Any?) {
        menuActionHandler.testAudioFileAPI(sender)
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

    // MARK: - 旧版文件菜单动作（向后兼容）

    // 注意：exportNote 和 copyNote 保留用于向后兼容
    // 新的菜单系统使用 exportAsPDF/exportAsMarkdown/exportAsPlainText 和 duplicateNote

    @objc func exportNote(_ sender: Any?) {
        menuActionHandler.exportNote(sender)
    }

    @objc func copyNote(_ sender: Any?) {
        menuActionHandler.copyNote(sender)
    }

    // MARK: - 文件菜单动作

    @objc func createSmartFolder(_ sender: Any?) {
        menuActionHandler.createSmartFolder(sender)
    }

    @objc func importMarkdown(_ sender: Any?) {
        menuActionHandler.importMarkdown(sender)
    }

    @objc func exportAsPDF(_ sender: Any?) {
        menuActionHandler.exportAsPDF(sender)
    }

    @objc func exportAsMarkdown(_ sender: Any?) {
        menuActionHandler.exportAsMarkdown(sender)
    }

    @objc func exportAsPlainText(_ sender: Any?) {
        menuActionHandler.exportAsPlainText(sender)
    }

    @objc func addToPrivateNotes(_ sender: Any?) {
        menuActionHandler.addToPrivateNotes(sender)
    }

    @objc func duplicateNote(_ sender: Any?) {
        menuActionHandler.duplicateNote(sender)
    }

    @objc func toggleStarNote(_ sender: Any?) {
        menuActionHandler.toggleStarNote(sender)
    }

    // MARK: - 查找功能（向后兼容）

    // 注意：新的菜单系统使用标准 NSTextFinder 选择器
    // 这些方法保留用于工具栏按钮和向后兼容

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

    // MARK: - 显示菜单动作

    @objc func setListView(_ sender: Any?) {
        menuActionHandler.setListView(sender)
    }

    @objc func setGalleryView(_ sender: Any?) {
        menuActionHandler.setGalleryView(sender)
    }

    @objc func toggleFolderVisibility(_ sender: Any?) {
        menuActionHandler.toggleFolderVisibility(sender)
    }

    @objc func toggleNoteCount(_ sender: Any?) {
        menuActionHandler.toggleNoteCount(sender)
    }

    @objc func zoomIn(_ sender: Any?) {
        menuActionHandler.zoomIn(sender)
    }

    @objc func zoomOut(_ sender: Any?) {
        menuActionHandler.zoomOut(sender)
    }

    @objc func actualSize(_ sender: Any?) {
        menuActionHandler.actualSize(sender)
    }

    @objc func expandSection(_ sender: Any?) {
        menuActionHandler.expandSection(sender)
    }

    @objc func expandAllSections(_ sender: Any?) {
        menuActionHandler.expandAllSections(sender)
    }

    @objc func collapseSection(_ sender: Any?) {
        menuActionHandler.collapseSection(sender)
    }

    @objc func collapseAllSections(_ sender: Any?) {
        menuActionHandler.collapseAllSections(sender)
    }

    // MARK: - 窗口菜单动作

    /// 填充窗口到屏幕
    @objc func fillWindow(_ sender: Any?) {
        menuActionHandler.fillWindow(sender)
    }

    /// 居中窗口
    @objc func centerWindow(_ sender: Any?) {
        menuActionHandler.centerWindow(sender)
    }

    /// 移动窗口到屏幕左半边
    @objc func moveWindowToLeftHalf(_ sender: Any?) {
        menuActionHandler.moveWindowToLeftHalf(sender)
    }

    /// 移动窗口到屏幕右半边
    @objc func moveWindowToRightHalf(_ sender: Any?) {
        menuActionHandler.moveWindowToRightHalf(sender)
    }

    /// 移动窗口到屏幕上半边
    @objc func moveWindowToTopHalf(_ sender: Any?) {
        menuActionHandler.moveWindowToTopHalf(sender)
    }

    /// 移动窗口到屏幕下半边
    @objc func moveWindowToBottomHalf(_ sender: Any?) {
        menuActionHandler.moveWindowToBottomHalf(sender)
    }

    /// 最大化窗口
    @objc func maximizeWindow(_ sender: Any?) {
        menuActionHandler.maximizeWindow(sender)
    }

    /// 恢复窗口
    @objc func restoreWindow(_ sender: Any?) {
        menuActionHandler.restoreWindow(sender)
    }

    /// 平铺窗口到屏幕左侧（全屏幕平铺）
    @objc func tileWindowToLeft(_ sender: Any?) {
        menuActionHandler.tileWindowToLeft(sender)
    }

    /// 平铺窗口到屏幕右侧（全屏幕平铺）
    @objc func tileWindowToRight(_ sender: Any?) {
        menuActionHandler.tileWindowToRight(sender)
    }

    /// 在新窗口中打开笔记
    @objc func openNoteInNewWindow(_ sender: Any?) {
        menuActionHandler.openNoteInNewWindow(sender)
    }

    // MARK: - NSMenuItemValidation

    /// 验证菜单项是否应该启用
    /// 将验证委托给 MenuActionHandler
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuActionHandler.validateMenuItem(menuItem)
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
