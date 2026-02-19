import AppKit

/// 窗口管理器
/// 负责应用程序窗口的创建、管理和状态恢复
@MainActor
public class WindowManager {

    // MARK: - 单例

    /// 共享实例
    public static let shared = WindowManager()

    // MARK: - 属性

    /// 主窗口控制器
    public var mainWindowController: MainWindowController?

    /// 活动窗口控制器列表
    private var windowControllers: [MainWindowController] = []

    // TODO: 任务 5 完成后启用这些属性
    /*
     /// 窗口状态字典（UUID -> WindowState）
     private var windowStates: [UUID: WindowState] = [:]

     /// 窗口控制器字典（UUID -> MainWindowController）
     private var windowControllerMap: [UUID: MainWindowController] = [:]
     */

    /// 窗口状态管理器
    private let windowStateManager = WindowStateManager()

    /// AppCoordinator 引用（弱引用避免循环引用）
    private weak var appCoordinator: AppCoordinator?

    // MARK: - 初始化

    private init() {
        LogService.shared.debug(.window, "窗口管理器初始化")
    }

    // MARK: - 配置

    /// 设置 AppCoordinator
    ///
    /// 必须在创建窗口之前调用此方法设置 AppCoordinator
    ///
    /// - Parameter coordinator: AppCoordinator 实例
    public func setAppCoordinator(_ coordinator: AppCoordinator) {
        appCoordinator = coordinator
        LogService.shared.debug(.window, "AppCoordinator 已设置")
    }

    // MARK: - 窗口管理

    /// 创建主窗口
    public func createMainWindow() -> MainWindowController? {
        LogService.shared.debug(.window, "创建主窗口")

        // TODO: 任务 5 完成后启用新实现
        // 当前使用旧实现保持向后兼容

        // 旧实现：使用 NotesViewModel
        guard let coordinator = appCoordinator else {
            let errorMessage = "AppCoordinator 未设置，无法创建窗口"
            LogService.shared.error(.window, errorMessage)
            showWindowCreationError(message: errorMessage)
            return nil
        }

        do {
            // 创建窗口状态
            let windowState = WindowState(coordinator: coordinator)

            // 创建主窗口控制器
            let controller = MainWindowController(
                coordinator: coordinator,
                windowState: windowState
            )

            mainWindowController = controller
            windowControllers.append(controller)

            // 恢复应用程序状态
            restoreApplicationState()

            // 恢复窗口 frame
            if let window = controller.window {
                restoreWindowFrame(window)
            }

            LogService.shared.info(.window, "主窗口创建完成")

            return controller
        } catch {
            let errorMessage = "创建主窗口失败: \(error.localizedDescription)"
            LogService.shared.error(.window, errorMessage)
            showWindowCreationError(message: errorMessage)
            return nil
        }

        /* 新实现（任务 5 完成后启用）:
         // 检查 AppCoordinator 是否已设置
         guard let coordinator = appCoordinator else {
             print("[WindowManager] 错误: AppCoordinator 未设置，无法创建窗口")
             return nil
         }

         // 创建窗口状态
         let windowState = WindowState(coordinator: coordinator)

         // 创建主窗口控制器
         let controller = MainWindowController(
             coordinator: coordinator,
             windowState: windowState
         )

         // 保存引用
         mainWindowController = controller
         windowStates[windowState.windowId] = windowState
         windowControllerMap[windowState.windowId] = controller
         windowControllers.append(controller)

         // 恢复应用程序状态
         restoreApplicationState()

         // 恢复窗口 frame
         if let window = controller.window {
             restoreWindowFrame(window)
         }

         print("[WindowManager] 主窗口创建完成，窗口 ID: \(windowState.windowId)")

         return controller
         */
    }

    /// 创建新窗口
    ///
    /// - Parameter note: 可选的笔记，如果指定则在新窗口中打开该笔记
    /// - Returns: 创建的窗口控制器，如果创建失败则返回 nil
    public func createNewWindow(withNote note: Note? = nil) -> MainWindowController? {
        LogService.shared.debug(.window, "创建新窗口")

        // TODO: 任务 5 完成后启用新实现
        // 当前使用旧实现保持向后兼容

        // 旧实现：使用 NotesViewModel
        guard let coordinator = appCoordinator else {
            let errorMessage = "AppCoordinator 未设置，无法创建窗口"
            LogService.shared.error(.window, errorMessage)
            showWindowCreationError(message: errorMessage)
            return nil
        }

        do {
            // 创建窗口状态
            let windowState = WindowState(coordinator: coordinator)

            // 如果指定了笔记，设置为选中状态
            if let note {
                windowState.selectedNote = note
                LogService.shared.debug(.window, "新窗口将打开笔记: \(note.title)")
            }

            // 创建窗口控制器
            let controller = MainWindowController(
                coordinator: coordinator,
                windowState: windowState
            )

            windowControllers.append(controller)

            LogService.shared.info(.window, "新窗口创建完成")

            return controller
        } catch {
            let errorMessage = "创建新窗口失败: \(error.localizedDescription)"
            LogService.shared.error(.window, errorMessage)
            showWindowCreationError(message: errorMessage)
            return nil
        }

        /* 新实现（任务 5 完成后启用）:
         // 检查 AppCoordinator 是否已设置
         guard let coordinator = appCoordinator else {
             print("[WindowManager] 错误: AppCoordinator 未设置，无法创建窗口")
             return nil
         }

         // 创建窗口状态
         let windowState = WindowState(coordinator: coordinator)

         // 如果指定了笔记，设置为选中状态
         if let note = note {
             windowState.selectedNote = note
             print("[WindowManager] 新窗口将打开笔记: \(note.title)")
         }

         // 创建窗口控制器
         let controller = MainWindowController(
             coordinator: coordinator,
             windowState: windowState
         )

         // 保存引用
         windowStates[windowState.windowId] = windowState
         windowControllerMap[windowState.windowId] = controller
         windowControllers.append(controller)

         print("[WindowManager] 新窗口创建完成，窗口 ID: \(windowState.windowId)")

         return controller
         */
    }

    /// 移除窗口控制器
    /// - Parameter windowController: 要移除的窗口控制器
    public func removeWindowController(_ windowController: MainWindowController) {
        if let index = windowControllers.firstIndex(where: { $0 === windowController }) {
            windowControllers.remove(at: index)
            LogService.shared.debug(.window, "窗口控制器已移除，剩余窗口数: \(windowControllers.count)")
        }
    }

    /// 移除窗口
    ///
    /// 根据窗口 ID 移除窗口状态和控制器
    ///
    /// - Parameter windowId: 窗口唯一标识符
    public func removeWindow(withId _: UUID) {
        // TODO: 任务 5 完成后启用新实现
        LogService.shared.debug(.window, "removeWindow(withId:) 将在任务 5 完成后实现")

        /* 新实现（任务 5 完成后启用）:
         // 移除窗口状态
         if let windowState = windowStates.removeValue(forKey: windowId) {
             print("[WindowManager] 移除窗口状态，ID: \(windowState.windowId)")
         }

         // 移除窗口控制器
         if let controller = windowControllerMap.removeValue(forKey: windowId) {
             // 从窗口控制器列表中移除
             if let index = windowControllers.firstIndex(where: { $0 === controller }) {
                 windowControllers.remove(at: index)
             }
             print("[WindowManager] 移除窗口控制器，剩余窗口数: \(windowControllers.count)")
         }
         */
    }

    /// 获取所有活动窗口
    /// - Returns: 活动窗口数组
    public func getAllWindows() -> [NSWindow] {
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

    /// 获取所有窗口状态
    ///
    /// - Returns: 所有窗口状态的数组
    public func getAllWindowStates() -> [Any] {
        // TODO: 任务 5 完成后返回 [WindowState]
        LogService.shared.debug(.window, "getAllWindowStates() 将在任务 5 完成后实现")
        return []

        /* 新实现（任务 5 完成后启用）:
         return Array(windowStates.values)
         */
    }

    /// 获取窗口数量
    public var windowCount: Int {
        windowControllers.count

        /* 新实现（任务 5 完成后启用）:
         return windowControllerMap.count
         */
    }

    /// 将所有窗口前置显示
    public func bringAllWindowsToFront() {
        for window in getAllWindows() {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// 处理应用程序重新打开
    /// - Parameter hasVisibleWindows: 是否有可见窗口
    /// - Returns: 是否处理成功
    public func handleApplicationReopen(hasVisibleWindows: Bool) -> Bool {
        LogService.shared.debug(.window, "应用程序重新打开，是否有可见窗口: \(hasVisibleWindows)")

        // 获取所有窗口（包括最小化的）
        let allWindows = getAllWindows()
        LogService.shared.debug(.window, "当前窗口总数: \(allWindows.count)")

        if allWindows.isEmpty {
            // 如果没有任何窗口（包括最小化的），创建新的主窗口
            LogService.shared.debug(.window, "没有窗口，创建新主窗口")
            createMainWindow()
        } else if !hasVisibleWindows {
            // 如果有窗口但不可见（可能被最小化），将它们前置显示
            LogService.shared.debug(.window, "有窗口但不可见，前置显示所有窗口")
            bringAllWindowsToFront()
        } else {
            // 如果有可见窗口，激活应用程序
            LogService.shared.debug(.window, "已有可见窗口，激活应用程序")
            NSApp.activate(ignoringOtherApps: true)
        }

        return true
    }

    // MARK: - 应用程序状态管理

    /// 保存应用程序状态
    public func saveApplicationState() {
        LogService.shared.debug(.window, "保存应用程序状态")

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
        if let mainWindowController {
            if let windowState = mainWindowController.savableWindowState() {
                windowStateManager.saveWindowState(windowState, forWindowId: "main")
            }

            if let window = mainWindowController.window {
                windowStateManager.saveWindowFrame(window.frame, forWindowId: "main")
            }
        }

        LogService.shared.info(.window, "应用程序状态保存完成")
    }

    /// 恢复应用程序状态
    public func restoreApplicationState() {
        LogService.shared.debug(.window, "恢复应用程序状态")

        // 迁移旧版窗口状态
        windowStateManager.migrateLegacyWindowState()

        // 恢复主窗口状态
        if let mainWindowController,
           let savedState = windowStateManager.getWindowState(forWindowId: "main") as? MainWindowState
        {
            mainWindowController.restoreWindowState(savedState)
        }

        LogService.shared.info(.window, "应用程序状态恢复完成")
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
    public func showParagraphDebugWindow() {
        if paragraphDebugWindowController == nil {
            paragraphDebugWindowController = ParagraphDebugWindowController()
        }
        paragraphDebugWindowController?.show()
    }

    // MARK: - 清理

    deinit {
        LogService.shared.debug(.window, "窗口管理器释放")
    }

    // MARK: - 错误处理

    /// 显示窗口创建错误提示
    ///
    /// 向用户显示友好的错误消息，并提供重启应用的建议
    ///
    /// - Parameter message: 错误消息
    private func showWindowCreationError(message: String) {
        let alert = NSAlert()
        alert.messageText = "无法创建窗口"
        alert.informativeText = "\(message)\n\n请尝试重启应用程序。如果问题持续存在，请联系技术支持。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
