import AppKit
import MiNoteLibrary

/// 窗口管理器
/// 负责应用程序窗口的创建、管理和状态恢复
@MainActor
class WindowManager {
    
    // MARK: - 属性
    
    /// 主窗口控制器
    var mainWindowController: MainWindowController?
    
    /// 活动窗口控制器列表
    private var windowControllers: [MainWindowController] = []
    
    /// 窗口状态管理器
    private let windowStateManager = WindowStateManager()
    
    // MARK: - 初始化
    
    init() {
        print("窗口管理器初始化")
    }
    
    // MARK: - 窗口管理
    
    /// 创建主窗口
    func createMainWindow() {
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
    
    /// 处理应用程序重新打开
    /// - Parameter hasVisibleWindows: 是否有可见窗口
    /// - Returns: 是否处理成功
    func handleApplicationReopen(hasVisibleWindows: Bool) -> Bool {
        print("应用程序重新打开，是否有可见窗口: \(hasVisibleWindows)")
        
        // 获取所有窗口（包括最小化的）
        let allWindows = getAllWindows()
        print("当前窗口总数: \(allWindows.count)")
        
        if allWindows.isEmpty {
            // 如果没有任何窗口（包括最小化的），创建新的主窗口
            print("没有窗口，创建新主窗口")
            createMainWindow()
        } else if !hasVisibleWindows {
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
    
    // MARK: - 应用程序状态管理
    
    /// 保存应用程序状态
    func saveApplicationState() {
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
    func restoreApplicationState() {
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
    
    // MARK: - 调试工具
    
    /// 段落管理器调试窗口控制器
    private var paragraphDebugWindowController: ParagraphDebugWindowController?
    
    /// 显示段落管理器调试窗口
    func showParagraphDebugWindow() {
        if paragraphDebugWindowController == nil {
            paragraphDebugWindowController = ParagraphDebugWindowController()
        }
        paragraphDebugWindowController?.show()
    }
    
    // MARK: - 清理
    
    deinit {
        print("窗口管理器释放")
    }
}
