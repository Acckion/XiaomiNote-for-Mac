import AppKit
import MiNoteLibrary

/// 应用程序状态管理器
/// 负责应用程序的生命周期状态管理
@MainActor
class AppStateManager {
    
    // MARK: - 属性
    
    /// 应用程序启动完成时间戳
    private var launchTime: Date?
    
    /// 窗口管理器
    private let windowManager: WindowManager
    
    /// 菜单管理器
    private let menuManager: MenuManager
    
    // MARK: - 初始化
    
    /// 初始化应用程序状态管理器
    /// - Parameters:
    ///   - windowManager: 窗口管理器
    ///   - menuManager: 菜单管理器
    init(windowManager: WindowManager, menuManager: MenuManager) {
        self.windowManager = windowManager
        self.menuManager = menuManager
        print("应用程序状态管理器初始化")
    }
    
    // MARK: - 公共方法
    
    /// 处理应用程序启动完成
    func handleApplicationDidFinishLaunching() {
        launchTime = Date()
        print("应用程序启动完成 - \(Date())")
        
        // 创建主窗口
        windowManager.createMainWindow()
        
        // 激活应用程序
        NSApp.activate(ignoringOtherApps: true)
        
        // 设置应用程序菜单
        menuManager.setupApplicationMenu()
        
        print("应用程序初始化完成，耗时: \(String(format: "%.2f", Date().timeIntervalSince(launchTime!)))秒")
    }
    
    /// 处理应用程序即将终止
    func handleApplicationWillTerminate() {
        print("应用程序即将终止")
        
        // 保存应用程序状态
        windowManager.saveApplicationState()
    }
    
    /// 处理应用程序重新打开
    /// - Parameters:
    ///   - hasVisibleWindows: 是否有可见窗口
    /// - Returns: 是否处理成功
    func handleApplicationReopen(hasVisibleWindows: Bool) -> Bool {
        return windowManager.handleApplicationReopen(hasVisibleWindows: hasVisibleWindows)
    }
    
    /// 判断当最后一个窗口关闭时是否终止应用程序
    /// - Returns: 是否终止应用程序
    func shouldTerminateAfterLastWindowClosed() -> Bool {
        // 当最后一个窗口关闭时不终止应用程序，符合 macOS 标准行为
        // 用户可以通过菜单或 Dock 退出应用
        return false
    }
    
    // MARK: - 清理
    
    deinit {
        print("应用程序状态管理器释放")
    }
}
