import AppKit

/// 应用程序委托
/// 替代SwiftUI的App结构，采用纯AppKit架构
/// 使用模块化设计，将功能分解到专门的类中
@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    // MARK: - 属性

    /// 窗口管理器
    private let windowManager: WindowManager

    /// 菜单管理器
    private let menuManager: MenuManager

    /// 应用程序状态管理器
    private let appStateManager: AppStateManager

    /// 命令调度器（coordinator 就绪后初始化）
    private var commandDispatcher: CommandDispatcher?

    /// 菜单状态管理器（coordinator 就绪后初始化）
    private var menuStateManager: MenuStateManager?

    // MARK: - 架构

    /// 应用协调器（对外只读访问）
    private(set) var appCoordinator: AppCoordinator?

    // MARK: - 初始化

    override init() {
        let shell = AppLaunchAssembler.buildShell()
        self.windowManager = shell.windowManager
        self.menuManager = shell.menuManager
        self.appStateManager = shell.appStateManager

        super.init()

        AppLaunchAssembler.bindShell(shell, appDelegate: self)

        LogService.shared.info(.app, "应用程序委托初始化完成")
    }

    // MARK: - NSApplicationDelegate

    public func applicationDidFinishLaunching(_: Notification) {
        LogService.shared.info(.app, "应用启动")

        let shell = AppLaunchAssembler.Shell(
            windowManager: windowManager,
            menuManager: menuManager,
            appStateManager: appStateManager
        )
        let coordinator = AppLaunchAssembler.buildRuntime(shell: shell)
        appCoordinator = coordinator

        // 初始化命令调度器和菜单状态管理器
        commandDispatcher = coordinator.commandDispatcher
        menuStateManager = MenuStateManager(mainWindowController: windowManager.mainWindowController)

        Task { @MainActor in
            await coordinator.start()
        }

        appStateManager.handleApplicationDidFinishLaunching()
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
        _ = windowManager.createNewWindow()
        menuStateManager?.updateMainWindowController(windowManager.mainWindowController)
    }

    /// 创建新窗口并打开指定笔记
    /// - Parameter note: 要在新窗口中打开的笔记
    public func createNewWindow(withNote note: Note?) {
        if let controller = windowManager.createNewWindow(withNote: note) {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// 移除窗口控制器
    /// - Parameter windowController: 要移除的窗口控制器
    func removeWindowController(_ windowController: MainWindowController) {
        windowManager.removeWindowController(windowController)
    }

    // MARK: - 统一命令分发

    /// 统一菜单命令入口
    /// 所有注册表驱动的菜单项通过此方法分发命令
    @objc func performCommand(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem,
              let tag = MenuItemTag(rawValue: menuItem.tag),
              let entry = CommandRegistry.shared.entry(for: tag)
        else {
            LogService.shared.warning(.app, "未找到菜单命令映射")
            return
        }
        let command = entry.commandType.init()
        commandDispatcher?.dispatch(command)
    }

    // MARK: - NSMenuItemValidation

    /// 验证菜单项是否应该启用
    /// 将验证委托给 MenuStateManager
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuStateManager?.validateMenuItem(menuItem) ?? true
    }

}

// MARK: - 应用程序启动器

class ApplicationLauncher {
    @MainActor
    static func launch() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
