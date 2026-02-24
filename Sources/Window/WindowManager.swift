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

    /// 独立编辑器窗口控制器列表
    private var editorWindowControllers: [NoteEditorWindowController] = []

    /// 窗口状态管理器
    private let windowStateManager = WindowStateManager()

    /// AppCoordinator 引用（弱引用避免循环引用）
    private weak var appCoordinator: AppCoordinator?

    // MARK: - 初始化

    public init() {
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
    @discardableResult
    public func createMainWindow() -> MainWindowController? {
        LogService.shared.debug(.window, "创建主窗口")

        guard let coordinator = appCoordinator else {
            let errorMessage = "AppCoordinator 未设置，无法创建窗口"
            LogService.shared.error(.window, errorMessage)
            showWindowCreationError(message: errorMessage)
            return nil
        }

        let windowState = WindowState(coordinator: coordinator)
        let controller = MainWindowController(
            coordinator: coordinator,
            windowState: windowState,
            operationQueue: coordinator.syncModule.operationQueue,
            operationProcessor: coordinator.syncModule.operationProcessor
        )

        mainWindowController = controller
        windowControllers.append(controller)

        restoreApplicationState()

        if let window = controller.window {
            restoreWindowFrame(window)
        }

        LogService.shared.info(.window, "主窗口创建完成")
        return controller
    }

    /// 创建新窗口
    ///
    /// - Parameter note: 可选的笔记，如果指定则在新窗口中打开该笔记
    /// - Returns: 创建的窗口控制器，如果创建失败则返回 nil
    public func createNewWindow(withNote note: Note? = nil) -> MainWindowController? {
        LogService.shared.debug(.window, "创建新窗口")

        guard let coordinator = appCoordinator else {
            let errorMessage = "AppCoordinator 未设置，无法创建窗口"
            LogService.shared.error(.window, errorMessage)
            showWindowCreationError(message: errorMessage)
            return nil
        }

        let windowState = WindowState(coordinator: coordinator)

        if let note {
            windowState.selectNote(note)
            LogService.shared.debug(.window, "新窗口将打开笔记: \(note.title)")
        }

        let controller = MainWindowController(
            coordinator: coordinator,
            windowState: windowState,
            operationQueue: coordinator.syncModule.operationQueue,
            operationProcessor: coordinator.syncModule.operationProcessor
        )

        windowControllers.append(controller)
        LogService.shared.info(.window, "新窗口创建完成")
        return controller
    }

    /// 移除窗口控制器
    /// - Parameter windowController: 要移除的窗口控制器
    public func removeWindowController(_ windowController: MainWindowController) {
        if let index = windowControllers.firstIndex(where: { $0 === windowController }) {
            windowControllers.remove(at: index)
            LogService.shared.debug(.window, "窗口控制器已移除，剩余窗口数: \(windowControllers.count)")
        }
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

    /// 获取窗口数量
    public var windowCount: Int {
        windowControllers.count
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
    @discardableResult
    public func handleApplicationReopen(hasVisibleWindows: Bool) -> Bool {
        LogService.shared.debug(.window, "应用程序重新打开，是否有可见窗口: \(hasVisibleWindows)")

        let allWindows = getAllWindows()

        if allWindows.isEmpty {
            LogService.shared.debug(.window, "没有窗口，创建新主窗口")
            createMainWindow()
        } else if !hasVisibleWindows {
            LogService.shared.debug(.window, "有窗口但不可见，前置显示所有窗口")
            bringAllWindowsToFront()
        } else {
            LogService.shared.debug(.window, "已有可见窗口，激活应用程序")
            NSApp.activate(ignoringOtherApps: true)
        }

        return true
    }

    // MARK: - 应用程序状态管理

    /// 保存应用程序状态
    public func saveApplicationState() {
        LogService.shared.debug(.window, "保存应用程序状态")

        windowStateManager.migrateLegacyWindowState()

        for (index, windowController) in windowControllers.enumerated() {
            if let windowState = windowController.savableWindowState() {
                windowStateManager.saveWindowState(windowState, forWindowId: "window_\(index)")
            }
            if let window = windowController.window {
                windowStateManager.saveWindowFrame(window.frame, forWindowId: "window_\(index)")
            }
        }

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

        windowStateManager.migrateLegacyWindowState()

        if let mainWindowController,
           let savedState = windowStateManager.getWindowState(forWindowId: "main") as? MainWindowState
        {
            mainWindowController.restoreWindowState(savedState)
        }

        LogService.shared.info(.window, "应用程序状态恢复完成")
    }

    /// 恢复窗口 frame
    private func restoreWindowFrame(_ window: NSWindow, windowId: String = "main") {
        if let savedFrame = windowStateManager.getWindowFrame(forWindowId: windowId) {
            var newFrame = NSRect(origin: savedFrame.origin, size: savedFrame.size)

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame

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

    // MARK: - 独立编辑器窗口

    /// 在独立编辑器窗口中打开笔记
    ///
    /// 如果该笔记已在编辑器窗口中打开，则前置显示已有窗口
    ///
    /// - Parameter note: 要打开的笔记
    public func openNoteEditorWindow(note: Note) {
        if let existing = editorWindowControllers.first(where: { $0.noteId == note.id }) {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            LogService.shared.debug(.window, "编辑器窗口已存在，前置显示: \(note.title)")
            return
        }

        guard let coordinator = appCoordinator else {
            LogService.shared.error(.window, "AppCoordinator 未设置，无法创建编辑器窗口")
            return
        }

        let controller = NoteEditorWindowController(coordinator: coordinator, note: note)
        editorWindowControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        LogService.shared.info(.window, "打开编辑器窗口: \(note.title)")
    }

    /// 移除编辑器窗口控制器
    public func removeEditorWindow(_ controller: NoteEditorWindowController) {
        editorWindowControllers.removeAll { $0 === controller }
        LogService.shared.debug(.window, "编辑器窗口已移除，剩余: \(editorWindowControllers.count)")
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

    // MARK: - 错误处理

    /// 显示窗口创建错误提示
    private func showWindowCreationError(message: String) {
        let alert = NSAlert()
        alert.messageText = "无法创建窗口"
        alert.informativeText = "\(message)\n\n请尝试重启应用程序。如果问题持续存在，请联系技术支持。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
