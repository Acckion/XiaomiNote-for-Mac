//
//  MainWindowController+Delegates.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit

    // MARK: - NSWindowDelegate

    extension MainWindowController: NSWindowDelegate {

        public func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }

            // 如果是主窗口关闭，从 WindowManager 移除
            if window == self.window {
                LogService.shared.info(.window, "主窗口即将关闭，从 WindowManager 移除")
                WindowManager.shared.removeWindowController(self)
            }

            // 清理其他窗口控制器引用
            if window == loginWindowController?.window {
                LogService.shared.debug(.window, "登录窗口即将关闭，清理引用")
                loginWindowController = nil
            } else if window == settingsWindowController?.window {
                LogService.shared.debug(.window, "设置窗口即将关闭，清理引用")
                settingsWindowController = nil
            } else if window == historyWindowController?.window {
                LogService.shared.debug(.window, "历史记录窗口即将关闭，清理引用")
                historyWindowController = nil
            } else if window == trashWindowController?.window {
                LogService.shared.debug(.window, "回收站窗口即将关闭，清理引用")
                trashWindowController = nil
            } else if window == currentSheetWindow {
                LogService.shared.debug(.window, "离线操作进度sheet窗口即将关闭，清理引用")
                currentSheetWindow = nil
            }
        }
    }

    // MARK: - WindowState 验证和恢复

    extension MainWindowController {

        /// 验证 WindowState 有效性
        ///
        /// 检查 WindowState 是否正确初始化，如果发现问题则记录警告日志
        ///
        /// - Returns: WindowState 是否有效
        func validateWindowState() -> Bool {
            // 检查 windowId 是否有效
            if windowState.windowId.uuidString.isEmpty {
                logger.error("[MainWindowController] WindowState windowId 无效")
                return false
            }

            // 检查是否能访问共享数据（通过 AppCoordinator）
            // 如果 coordinator 为 nil，可能表示 AppCoordinator 未正确设置
            if windowState.coordinator == nil {
                logger.warning("[MainWindowController] WindowState coordinator 为空，可能正在加载")
            }

            return true
        }

        /// 恢复 WindowState（如果丢失）
        ///
        /// 当检测到 WindowState 丢失或无效时，尝试从 AppCoordinator 创建默认状态
        /// 这是一个防御性措施，正常情况下不应该被调用
        ///
        /// - Returns: 恢复是否成功
        @discardableResult
        func recoverWindowState() -> Bool {
            logger.warning("[MainWindowController] 尝试恢复 WindowState")

            // 在当前架构中，WindowState 是在初始化时传入的
            // 如果真的丢失了，我们无法重新创建它
            // 这里只能记录错误并返回失败
            logger.error("[MainWindowController] WindowState 丢失且无法恢复")

            // 显示错误提示
            showWindowStateRecoveryError()

            return false
        }

        /// 显示 WindowState 恢复错误提示
        func showWindowStateRecoveryError() {
            let alert = NSAlert()
            alert.messageText = "窗口状态异常"
            alert.informativeText = "窗口状态丢失，部分功能可能无法正常使用。\n\n建议关闭此窗口并重新打开。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")

            if let window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }

    // MARK: - NSMenuDelegate

    extension MainWindowController: NSMenuDelegate {

        public func menuNeedsUpdate(_ menu: NSMenu) {
            LogService.shared.debug(.window, "菜单需要更新: \(menu.title)")

            let optionsManager = ViewOptionsManager.shared

            // 更新菜单项状态
            for item in menu.items {
                // 在线状态菜单项
                if item.tag == 100 { // 在线状态项
                    item.attributedTitle = getOnlineStatusAttributedTitle()
                } else if item.tag == 200 { // 离线操作状态项
                    // 更新离线操作状态（使用新的 UnifiedOperationQueue）
                    let unifiedQueue = UnifiedOperationQueue.shared
                    let stats = unifiedQueue.getStatistics()
                    let pendingCount = stats["pending"] ?? 0
                    let failedCount = stats["failed"] ?? 0

                    if pendingCount > 0 {
                        if failedCount > 0 {
                            item.title = "离线操作：\(pendingCount)个待处理 (\(failedCount)个失败)"
                        } else {
                            item.title = "离线操作：\(pendingCount)个待处理"
                        }
                    } else {
                        if failedCount > 0 {
                            item.title = "离线操作：\(failedCount)个失败"
                        } else {
                            item.title = "离线操作：无待处理"
                        }
                    }
                }

                // 视图选项菜单的选中状态

                // 排序方式选中状态
                if item.tag == 1 { // 编辑时间
                    item.state = optionsManager.sortOrder == .editDate ? .on : .off
                } else if item.tag == 2 { // 创建时间
                    item.state = optionsManager.sortOrder == .createDate ? .on : .off
                } else if item.tag == 3 { // 标题
                    item.state = optionsManager.sortOrder == .title ? .on : .off
                }

                // 排序方向选中状态
                if item.tag == 10 { // 降序
                    item.state = optionsManager.sortDirection == .descending ? .on : .off
                } else if item.tag == 11 { // 升序
                    item.state = optionsManager.sortDirection == .ascending ? .on : .off
                }

                // 日期分组选中状态
                if item.tag == 20 { // 开
                    item.state = optionsManager.isDateGroupingEnabled ? .on : .off
                } else if item.tag == 21 { // 关
                    item.state = !optionsManager.isDateGroupingEnabled ? .on : .off
                }

                // 视图模式选中状态
                if item.tag == 30 { // 列表视图
                    item.state = optionsManager.viewMode == .list ? .on : .off
                } else if item.tag == 31 { // 画廊视图
                    item.state = optionsManager.viewMode == .gallery ? .on : .off
                }

                // 按日期分组菜单项：当排序方式为标题时隐藏
                // 因为按标题排序时，日期分组没有意义
                if item.title == "按日期分组" {
                    item.isHidden = optionsManager.sortOrder == .title
                }
            }
        }
    }

    // MARK: - NSUserInterfaceValidations

    extension MainWindowController: NSUserInterfaceValidations {

        public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {

            // 根据当前状态验证各个动作

            if item.action == #selector(createNewNote(_:)) {
                return true // 总是可以创建新笔记
            }

            if item.action == #selector(createNewFolder(_:)) {
                return true // 总是可以创建新文件夹
            }

            if item.action == #selector(performSync(_:)) {
                return coordinator.authState.isLoggedIn
            }

            if item.action == #selector(shareNote(_:)) {
                return coordinator.noteListState.selectedNote != nil
            }

            if item.action == #selector(toggleStarNote(_:)) {
                return coordinator.noteListState.selectedNote != nil
            }

            if item.action == #selector(deleteNote(_:)) {
                return coordinator.noteListState.selectedNote != nil
            }

            if item.action == #selector(restoreNote(_:)) {
                return coordinator.noteListState.selectedNote != nil
            }

            // 格式操作：只有在编辑模式下才可用
            let formatActions: [Selector] = [
                #selector(toggleBold(_:)),
                #selector(toggleItalic(_:)),
                #selector(toggleUnderline(_:)),
                #selector(toggleStrikethrough(_:)),
                #selector(toggleCode(_:)),
                #selector(insertLink(_:)),
                #selector(toggleCheckbox(_:)),
                #selector(insertHorizontalRule(_:)),
                #selector(insertAttachment(_:)),
                #selector(increaseIndent(_:)),
                #selector(decreaseIndent(_:)),
            ]

            if formatActions.contains(item.action!) {
                return coordinator.noteListState.selectedNote != nil
            }

            // 验证新的按钮
            if item.action == #selector(showSettings(_:)) {
                return true // 总是可以显示设置
            }

            if item.action == #selector(showLogin(_:)) {
                return !coordinator.authState.isLoggedIn
            }

            if item.action == #selector(showOfflineOperations(_:)) {
                let stats = UnifiedOperationQueue.shared.getStatistics()
                let pendingCount = (stats["pending"] ?? 0) + (stats["failed"] ?? 0)
                return pendingCount > 0
            }

            // 验证新增的工具栏按钮
            if item.action == #selector(toggleCheckbox(_:)) {
                return coordinator.noteListState.selectedNote != nil
            }

            if item.action == #selector(insertHorizontalRule(_:)) {
                return coordinator.noteListState.selectedNote != nil
            }

            if item.action == #selector(insertAttachment(_:)) {
                return coordinator.noteListState.selectedNote != nil
            }

            if item.action == #selector(showHistory(_:)) {
                return coordinator.noteListState.selectedNote != nil
            }

            if item.action == #selector(showTrash(_:)) {
                return true // 总是可以显示回收站
            }

            if item.action == #selector(performIncrementalSync(_:)) {
                return coordinator.authState.isLoggedIn
            }

            if item.action == #selector(resetSyncStatus(_:)) {
                return true // 总是可以重置同步状态
            }

            if item.action == #selector(showSyncStatus(_:)) {
                return true // 总是可以显示同步状态
            }

            // 验证切换侧边栏按钮
            if item.action == #selector(toggleSidebar(_:)) {
                return true // 总是可以切换侧边栏
            }

            // 验证撤销/重做按钮
            if item.action == #selector(undo(_:)) || item.action == #selector(redo(_:)) {
                return coordinator.noteListState.selectedNote != nil
            }

            // 验证搜索按钮
            if item.action == #selector(performSearch(_:)) {
                return true // 总是可以搜索
            }

            // 验证锁定私密笔记按钮
            if item.action == #selector(lockPrivateNotes(_:)) {
                let isPrivateFolder = coordinator.folderState.selectedFolder?.id == "2"
                let isUnlocked = coordinator.authState.isPrivateNotesUnlocked
                return isPrivateFolder && isUnlocked
            }

            // 默认返回true，确保所有按钮在溢出菜单中可用
            return true
        }
    }

    // MARK: - 窗口状态管理

    extension MainWindowController {

        /// 获取可保存的窗口状态
        /// - Returns: 窗口状态对象，如果无法获取则返回nil
        func savableWindowState() -> MainWindowState? {
            guard let window,
                  let splitViewController = window.contentViewController as? NSSplitViewController
            else {
                LogService.shared.error(.window, "无法获取窗口状态：窗口或分割视图控制器不存在")
                return nil
            }

            // 获取分割视图宽度
            let splitViewWidths = splitViewController.splitViewItems.map { item in
                Int(item.viewController.view.frame.width)
            }

            // 检查侧边栏是否隐藏
            let isSidebarHidden = splitViewController.splitViewItems.first?.isCollapsed ?? false

            // 获取各个视图控制器的状态
            var sidebarWindowState: SidebarWindowState?
            var notesListWindowState: NotesListWindowState?
            var noteDetailWindowState: NoteDetailWindowState?

            // 获取侧边栏状态
            if let sidebarViewController = splitViewController.splitViewItems.first?.viewController as? SidebarViewController {
                sidebarWindowState = sidebarViewController.savableWindowState()
            }

            // 获取笔记列表状态
            if splitViewController.splitViewItems.count > 1,
               let notesListViewController = splitViewController.splitViewItems[1].viewController as? NotesListViewController
            {
                notesListWindowState = notesListViewController.savableWindowState()
            }

            // 获取笔记详情状态
            if splitViewController.splitViewItems.count > 2,
               let noteDetailViewController = splitViewController.splitViewItems[2].viewController as? NoteDetailViewController
            {
                noteDetailWindowState = noteDetailViewController.savableWindowState()
            }

            // 获取窗口状态
            return MainWindowState(
                isFullScreen: window.styleMask.contains(.fullScreen),
                splitViewWidths: splitViewWidths,
                isSidebarHidden: isSidebarHidden,
                sidebarWindowState: sidebarWindowState,
                notesListWindowState: notesListWindowState,
                noteDetailWindowState: noteDetailWindowState
            )
        }

        /// 恢复窗口状态
        /// - Parameter state: 要恢复的窗口状态
        func restoreWindowState(_ state: MainWindowState) {
            guard let window,
                  let splitViewController = window.contentViewController as? NSSplitViewController
            else {
                LogService.shared.error(.window, "无法恢复窗口状态：窗口或分割视图控制器不存在")
                return
            }

            // 恢复分割视图宽度
            if state.splitViewWidths.count == splitViewController.splitViewItems.count {
                for (index, width) in state.splitViewWidths.enumerated() {
                    if index < splitViewController.splitViewItems.count {
                        let item = splitViewController.splitViewItems[index]
                        let cgWidth = CGFloat(width)
                        item.minimumThickness = cgWidth
                        item.maximumThickness = cgWidth

                        // 设置首选宽度
                        let totalWidth = splitViewController.splitView.frame.width
                        if totalWidth > 0 {
                            item.preferredThicknessFraction = cgWidth / totalWidth
                        }
                    }
                }
            }

            // 恢复侧边栏状态
            if let sidebarItem = splitViewController.splitViewItems.first {
                sidebarItem.isCollapsed = state.isSidebarHidden
            }

            // 恢复各个视图控制器的状态
            // 恢复侧边栏状态
            if let sidebarWindowState = state.sidebarWindowState,
               let sidebarViewController = splitViewController.splitViewItems.first?.viewController as? SidebarViewController
            {
                sidebarViewController.restoreWindowState(sidebarWindowState)
            }

            // 恢复笔记列表状态
            if let notesListWindowState = state.notesListWindowState,
               splitViewController.splitViewItems.count > 1,
               let notesListViewController = splitViewController.splitViewItems[1].viewController as? NotesListViewController
            {
                notesListViewController.restoreWindowState(notesListWindowState)
            }

            // 恢复笔记详情状态
            if let noteDetailWindowState = state.noteDetailWindowState,
               splitViewController.splitViewItems.count > 2,
               let noteDetailViewController = splitViewController.splitViewItems[2].viewController as? NoteDetailViewController
            {
                noteDetailViewController.restoreWindowState(noteDetailWindowState)
            }

        }
    }

#endif
