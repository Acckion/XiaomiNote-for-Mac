//
//  MainWindowController+Actions.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import SwiftUI
    import UniformTypeIdentifiers

    // MARK: - 动作方法

    public extension MainWindowController {

        @objc func createNewNote(_: Any?) {
            Task {
                await coordinator.noteListState.createNewNote(inFolder: coordinator.folderState.selectedFolderId ?? "0")
            }
        }

        @objc func createNewFolder(_: Any?) {
            // 显示新建文件夹对话框
            let alert = NSAlert()
            alert.messageText = "新建文件夹"
            alert.informativeText = "请输入文件夹名称："
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")

            let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            inputField.placeholderString = "文件夹名称"
            alert.accessoryView = inputField

            alert.window.initialFirstResponder = inputField

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let folderName = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !folderName.isEmpty {
                    Task {
                        await coordinator.folderState.createFolder(name: folderName)
                    }
                }
            }
        }

        @objc func performSync(_: Any?) {
            coordinator.syncState.requestFullSync(mode: .normal)
        }

        @objc func shareNote(_: Any?) {
            guard let note = coordinator.noteListState.selectedNote else { return }

            let sharingService = NSSharingServicePicker(items: [
                note.title,
                note.content,
            ])

            if let window,
               let contentView = window.contentView
            {
                sharingService.show(relativeTo: NSRect.zero, of: contentView, preferredEdge: .minY)
            }
        }

        @objc internal func toggleStarNote(_: Any?) {
            guard let note = coordinator.noteListState.selectedNote else { return }
            Task {
                await coordinator.noteListState.toggleStar(note)
            }
        }

        @objc internal func deleteNote(_: Any?) {
            guard let note = coordinator.noteListState.selectedNote else { return }

            let alert = NSAlert()
            alert.messageText = "删除笔记"
            alert.informativeText = "确定要删除笔记 \"\(note.title)\" 吗？此操作无法撤销。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Task {
                    await coordinator.noteListState.deleteNote(note)
                }
            }
        }

        @objc internal func restoreNote(_: Any?) {
            // 恢复笔记功能
        }

        @objc func toggleBold(_: Any?) {
            // 切换粗体
            // 这里应该调用编辑器API
        }

        @objc func toggleItalic(_: Any?) {
            // 切换斜体
        }

        @objc func toggleUnderline(_: Any?) {
            // 切换下划线
        }

        @objc func toggleStrikethrough(_: Any?) {
            // 切换删除线
        }

        @objc internal func toggleCode(_: Any?) {
            // 切换代码格式
        }

        @objc internal func insertLink(_: Any?) {
            // 插入链接
        }

        @objc internal func showSettings(_: Any?) {
            // 显示设置窗口

            // 创建设置窗口控制器
            let settingsWindowController = SettingsWindowController(coordinator: coordinator)

            // 显示窗口
            settingsWindowController.showWindow(nil)
            settingsWindowController.window?.makeKeyAndOrderFront(nil)
        }

        @objc func showLogin(_: Any?) {
            guard let window else {
                LogService.shared.error(.window, "主窗口不存在，无法显示登录 sheet")
                return
            }

            // 创建登录视图
            let loginView = LoginView(authState: coordinator.authState, passTokenManager: coordinator.passTokenManager)

            // 创建托管控制器
            let hostingController = NSHostingController(rootView: loginView)

            // 创建sheet窗口
            let sheetWindow = NSWindow(contentViewController: hostingController)
            sheetWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            sheetWindow.title = "登录"
            sheetWindow.titlebarAppearsTransparent = false // 显示标题栏
            sheetWindow.titleVisibility = .visible // 显示标题

            // 为sheet窗口添加工具栏
            let toolbarDelegate = BaseSheetToolbarDelegate()
            toolbarDelegate.onClose = { [weak window, weak sheetWindow] in
                // 关闭sheet - 使用弱引用捕获两个窗口
                if let window, let sheetWindow {
                    window.endSheet(sheetWindow)
                }
            }

            let toolbar = NSToolbar(identifier: "LoginSheetToolbar")
            toolbar.displayMode = .iconOnly
            toolbar.delegate = toolbarDelegate
            sheetWindow.toolbar = toolbar
            sheetWindow.toolbarStyle = .unified

            // 存储工具栏代理引用，防止被ARC释放
            loginSheetToolbarDelegate = toolbarDelegate

            // 显示sheet
            window.beginSheet(sheetWindow) { response in
                LogService.shared.debug(.window, "登录sheet关闭，响应: \(response)")
                // 清理工具栏代理引用
                self.loginSheetToolbarDelegate = nil
            }

            LogService.shared.info(.window, "显示登录sheet完成")
        }

        @objc internal func showOfflineOperations(_: Any?) {
            // 显示离线操作处理窗口 - 使用简单的实现
            LogService.shared.debug(.window, "显示离线操作处理窗口")
            let alert = NSAlert()
            alert.messageText = "离线操作"
            alert.informativeText = "离线操作处理窗口功能正在开发中..."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }

        @objc internal func showDebugSettings(_: Any?) {
            // 显示调试设置窗口 - 使用简单的实现
            LogService.shared.debug(.window, "显示调试设置窗口")
            let alert = NSAlert()
            alert.messageText = "调试设置"
            alert.informativeText = "调试设置窗口功能正在开发中..."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }

        /// 切换 XML 调试模式
        /// 通过发送通知来切换调试模式，NoteDetailView 会监听此通知并切换显示模式
        @objc internal func toggleDebugMode(_: Any?) {
            LogService.shared.debug(.window, "切换 XML 调试模式")

            guard coordinator.noteListState.selectedNote != nil else {
                LogService.shared.debug(.window, "没有选中笔记，无法切换调试模式")
                return
            }

            // 发送通知切换调试模式
            NotificationCenter.default.post(name: .toggleDebugMode, object: nil)
        }

        // MARK: - 新增工具栏按钮动作方法

        /// 切换待办（插入复选框）
        @objc internal func toggleCheckbox(_: Any?) {
            LogService.shared.debug(.window, "切换待办")

            guard coordinator.noteListState.selectedNote != nil else {
                LogService.shared.debug(.window, "没有选中笔记，无法插入待办")
                return
            }

            LogService.shared.debug(.window, "使用原生编辑器，调用 NativeEditorContext.insertCheckbox()")
            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.insertCheckbox()
            } else {
                LogService.shared.error(.window, "无法获取 NativeEditorContext")
            }
        }

        /// 插入分割线
        @objc internal func insertHorizontalRule(_: Any?) {
            LogService.shared.debug(.window, "插入分割线")

            guard coordinator.noteListState.selectedNote != nil else {
                LogService.shared.debug(.window, "没有选中笔记，无法插入分割线")
                return
            }

            LogService.shared.debug(.window, "使用原生编辑器，调用 NativeEditorContext.insertHorizontalRule()")
            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.insertHorizontalRule()
            } else {
                LogService.shared.error(.window, "无法获取 NativeEditorContext")
            }
        }

        /// 插入附件（图片）
        @objc func insertAttachment(_: Any?) {
            LogService.shared.debug(.window, "插入附件")

            guard coordinator.noteListState.selectedNote != nil else {
                LogService.shared.debug(.window, "没有选中笔记，无法插入附件")
                return
            }

            let openPanel = NSOpenPanel()
            openPanel.allowedContentTypes = [.image, .png, .jpeg, .gif]
            openPanel.allowsMultipleSelection = false
            openPanel.canChooseDirectories = false
            openPanel.canChooseFiles = true
            openPanel.message = "选择要插入的图片"
            openPanel.prompt = "插入"

            openPanel.begin { [weak self] response in
                guard let self else { return }

                if response == .OK, let url = openPanel.url {
                    Task { @MainActor in
                        await self.insertImage(from: url)
                    }
                }
            }
        }

        /// 从 URL 插入图片
        @MainActor
        private func insertImage(from url: URL) async {
            guard coordinator.noteListState.selectedNote != nil else {
                LogService.shared.error(.window, "没有选中笔记，无法插入图片")
                return
            }

            do {
                let fileId = try await coordinator.noteEditorState.uploadImageAndInsertToNote(imageURL: url)
                LogService.shared.info(.window, "图片上传成功: fileId=\(fileId)")

                LogService.shared.debug(.window, "使用原生编辑器，调用 NativeEditorContext.insertImage()")
                if let nativeContext = getCurrentNativeEditorContext() {
                    nativeContext.insertImage(fileId: fileId, src: "minote://image/\(fileId)")
                } else {
                    LogService.shared.error(.window, "无法获取 NativeEditorContext")
                }
            } catch {
                LogService.shared.error(.window, "插入图片失败: \(error.localizedDescription)")
                let alert = NSAlert()
                alert.messageText = "插入图片失败"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        }

        /// 插入语音录音
        ///
        /// 点击工具栏录音按钮时调用，先在光标位置插入录音模板占位符，
        /// 然后显示音频面板进入录制模式。录制完成后，更新之前插入的模板。
        ///
        @objc func insertAudioRecording(_: Any?) {

            guard let selectedNote = coordinator.noteListState.selectedNote
            else {
                LogService.shared.error(.window, "无法插入录音：没有选中的笔记")
                return
            }

            // 生成唯一的模板 ID
            let templateId = "recording_template_\(UUID().uuidString)"

            // 1. 在原生编辑器光标位置插入录音模板占位符
            if let nativeEditorContext = getCurrentNativeEditorContext() {
                nativeEditorContext.insertRecordingTemplate(templateId: templateId)
                LogService.shared.debug(.window, "已在原生编辑器中插入录音模板: \(templateId)")
            } else {
                LogService.shared.error(.window, "无法获取原生编辑器上下文")
                return
            }

            // 2. 保存模板 ID 到状态管理器，用于后续更新
            audioPanelStateManager.currentRecordingTemplateId = templateId

            // 3. 显示音频面板进入录制模式
            showAudioPanelForRecording()
        }

        @objc func showHistory(_: Any?) {

            guard let note = coordinator.noteListState.selectedNote else {
                let alert = NSAlert()
                alert.messageText = "历史记录"
                alert.informativeText = "请先选择要查看历史记录的笔记"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
                return
            }

            guard let window else {
                LogService.shared.error(.window, "主窗口不存在，无法显示历史记录 sheet")
                return
            }

            // 创建历史记录视图
            let historyView = NoteHistoryView(
                noteEditorState: coordinator.noteEditorState,
                noteId: note.id,
                formatConverter: coordinator.editorModule.formatConverter
            )

            // 创建托管控制器
            let hostingController = NSHostingController(rootView: historyView)

            // 创建sheet窗口
            let sheetWindow = NSWindow(contentViewController: hostingController)
            sheetWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            sheetWindow.title = "历史记录"
            sheetWindow.titlebarAppearsTransparent = false // 显示标题栏
            sheetWindow.titleVisibility = .visible // 显示标题

            // 为sheet窗口添加工具栏
            let toolbarDelegate = BaseSheetToolbarDelegate()
            toolbarDelegate.onClose = { [weak window] in
                // 关闭sheet
                window?.endSheet(sheetWindow)
            }

            let toolbar = NSToolbar(identifier: "HistorySheetToolbar")
            toolbar.displayMode = .iconOnly
            toolbar.delegate = toolbarDelegate
            sheetWindow.toolbar = toolbar
            sheetWindow.toolbarStyle = .unified

            // 存储工具栏代理引用，防止被ARC释放
            historySheetToolbarDelegate = toolbarDelegate

            // 显示sheet
            window.beginSheet(sheetWindow) { _ in
                // 清理工具栏代理引用
                self.historySheetToolbarDelegate = nil
            }

        }

        @objc func showTrash(_: Any?) {

            guard let window else {
                LogService.shared.error(.window, "主窗口不存在，无法显示回收站 sheet")
                return
            }

            // 创建回收站视图
            let trashView = TrashView(noteListState: coordinator.noteListState, formatConverter: coordinator.editorModule.formatConverter)

            // 创建托管控制器
            let hostingController = NSHostingController(rootView: trashView)

            // 创建sheet窗口
            let sheetWindow = NSWindow(contentViewController: hostingController)
            sheetWindow.styleMask = [.titled, .fullSizeContentView] // 移除.closable，隐藏右上角关闭按钮
            sheetWindow.title = "回收站"
            sheetWindow.titlebarAppearsTransparent = false // 显示标题栏
            sheetWindow.titleVisibility = .visible // 显示标题

            // 为sheet窗口添加工具栏
            let toolbarDelegate = BaseSheetToolbarDelegate()
            toolbarDelegate.onClose = { [weak window] in
                // 关闭sheet - 使用弱引用捕获主窗口，直接使用sheetWindow变量
                window?.endSheet(sheetWindow)
            }

            let toolbar = NSToolbar(identifier: "TrashSheetToolbar")
            toolbar.displayMode = .iconOnly
            toolbar.delegate = toolbarDelegate
            sheetWindow.toolbar = toolbar
            sheetWindow.toolbarStyle = .unified

            // 设置窗口代理，以便正确处理窗口事件
            sheetWindow.delegate = self

            // 存储工具栏代理引用，防止被ARC释放
            trashSheetToolbarDelegate = toolbarDelegate

            // 显示sheet
            window.beginSheet(sheetWindow) { _ in
                // 清理工具栏代理引用
                self.trashSheetToolbarDelegate = nil
            }

        }

        // MARK: - 笔记操作菜单动作方法

        @objc internal func handleNoteOperationsClick(_: Any) {
            // 获取菜单
            guard let toolbarDelegate,
                  let window else { return }

            // 在主线程上获取菜单（确保线程安全）
            Task { @MainActor in
                let menu = toolbarDelegate.actionMenu

                // 使用鼠标当前位置
                let mouseLocation = NSEvent.mouseLocation
                menu.popUp(positioning: nil, at: mouseLocation, in: nil)
            }
        }

        @objc internal func showNoteOperationsMenu(_ sender: Any?) {
            // 保留原方法以向后兼容，但重定向到新的方法
            handleNoteOperationsClick(sender ?? self)
        }

        @objc internal func addToPrivateNotes(_: Any?) {
            guard let note = coordinator.noteListState.selectedNote else { return }

            let alert = NSAlert()
            alert.messageText = "添加到私密笔记"
            alert.informativeText = "确定要将笔记 \"\(note.title)\" 添加到私密笔记吗？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 简化实现：显示成功消息
                let successAlert = NSAlert()
                successAlert.messageText = "操作成功"
                successAlert.informativeText = "笔记已添加到私密笔记（功能正在开发中）"
                successAlert.alertStyle = .informational
                successAlert.addButton(withTitle: "确定")
                successAlert.runModal()
            }
        }

        @objc internal func moveNote(_ sender: Any?) {
            guard let note = coordinator.noteListState.selectedNote else { return }

            // 创建菜单
            let menu = NSMenu()

            // 未分类文件夹（folderId为"0"）
            let uncategorizedMenuItem = NSMenuItem(title: "未分类", action: #selector(moveToUncategorized(_:)), keyEquivalent: "")
            uncategorizedMenuItem.image = NSImage(systemSymbolName: "folder.badge.questionmark", accessibilityDescription: nil)
            uncategorizedMenuItem.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(uncategorizedMenuItem)

            // 其他可用文件夹
            let availableFolders = NoteMoveHelper.getAvailableFolders(from: coordinator.folderState)

            if !availableFolders.isEmpty {
                menu.addItem(NSMenuItem.separator())

                for folder in availableFolders {
                    let menuItem = NSMenuItem(title: folder.name, action: #selector(moveNoteToFolder(_:)), keyEquivalent: "")
                    menuItem.representedObject = folder
                    menuItem.image = NSImage(systemSymbolName: folder.isPinned ? "pin.fill" : "folder", accessibilityDescription: nil)
                    menuItem.image?.size = NSSize(width: 16, height: 16)
                    menu.addItem(menuItem)
                }
            }

            // 显示菜单
            if let button = sender as? NSView {
                let location = NSPoint(x: 0, y: button.bounds.height)
                menu.popUp(positioning: nil, at: location, in: button)
            } else if let window {
                let location = NSPoint(x: window.frame.midX, y: window.frame.midY)
                menu.popUp(positioning: nil, at: location, in: nil)
            }
        }

        @objc internal func moveToUncategorized(_: NSMenuItem) {
            guard let note = coordinator.noteListState.selectedNote else { return }

            NoteMoveHelper.moveToUncategorized(note, using: coordinator.noteListState) { result in
                switch result {
                case .success:
                    LogService.shared.info(.window, "笔记移动到未分类成功: \(note.id)")
                case let .failure(error):
                    LogService.shared.error(.window, "移动到未分类失败: \(error.localizedDescription)")
                }
            }
        }

        @objc internal func moveNoteToFolder(_ sender: NSMenuItem) {
            guard let folder = sender.representedObject as? Folder,
                  let note = coordinator.noteListState.selectedNote else { return }

            NoteMoveHelper.moveNote(note, to: folder, using: coordinator.noteListState) { result in
                switch result {
                case .success:
                    LogService.shared.info(.window, "笔记移动成功: \(note.id) -> \(folder.name)")
                case let .failure(error):
                    LogService.shared.error(.window, "移动笔记失败: \(error.localizedDescription)")
                }
            }
        }

        @objc internal func showOnlineStatusMenu(_: Any?) {
            // 在线状态菜单按钮点击
        }

        @objc internal func performIncrementalSync(_: Any?) {
            coordinator.syncState.requestSync(mode: .incremental)
        }

        @objc internal func resetSyncStatus(_: Any?) {
            coordinator.syncState.lastSyncTime = nil
            coordinator.syncState.syncStatusMessage = ""
            coordinator.syncState.lastSyncedNotesCount = 0
        }

        @objc internal func showSyncStatus(_: Any?) {
            let syncState = coordinator.syncState
            if let lastSync = syncState.lastSyncTime {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short

                let alert = NSAlert()
                alert.messageText = "同步状态"
                var infoText = "上次同步时间: \(formatter.string(from: lastSync))"
                let stats = operationQueue.getStatistics()
                let pendingCount = (stats["pending"] ?? 0) + (stats["failed"] ?? 0)
                if pendingCount > 0 {
                    infoText += "\n待处理操作: \(pendingCount) 个"
                }
                alert.informativeText = infoText
                alert.addButton(withTitle: "确定")
                alert.runModal()
            } else {
                let alert = NSAlert()
                alert.messageText = "同步状态"
                var infoText = "从未同步"
                let stats = operationQueue.getStatistics()
                let pendingCount = (stats["pending"] ?? 0) + (stats["failed"] ?? 0)
                if pendingCount > 0 {
                    infoText += "\n待处理操作: \(pendingCount) 个"
                }
                alert.informativeText = infoText
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        }

        // MARK: - 离线操作相关动作方法

        @objc internal func processOfflineOperations(_: Any?) {

            // 检查是否有待处理的离线操作（使用新的 UnifiedOperationQueue）
            let unifiedQueue = operationQueue
            let stats = unifiedQueue.getStatistics()
            let pendingCount = (stats["pending"] ?? 0) + (stats["failed"] ?? 0)

            if pendingCount == 0 {
                let alert = NSAlert()
                alert.messageText = "离线操作"
                alert.informativeText = "没有待处理的离线操作。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                alert.runModal()
                return
            }

            // 询问用户是否要处理离线操作
            let alert = NSAlert()
            alert.messageText = "处理离线操作"
            alert.informativeText = "确定要处理 \(pendingCount) 个待处理的离线操作吗？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "处理")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 开始处理离线操作（使用新的 OperationProcessor）
                Task {
                    await self.operationProcessor.processQueue()
                }
            }
        }

        @objc internal func showOfflineOperationsProgress(_: Any?) {

            guard let window else {
                return
            }

            // 创建离线操作进度视图，传递关闭回调
            let progressView = OfflineOperationsProgressView(
                processor: operationProcessor,
                operationQueue: operationQueue,
                onClose: { [weak window, weak self] in
                    // 关闭sheet
                    if let sheetWindow = self?.currentSheetWindow {
                        window?.endSheet(sheetWindow)
                    }
                }
            )

            // 创建托管控制器
            let hostingController = NSHostingController(rootView: progressView)

            let sheetWindow = NSWindow(contentViewController: hostingController)
            sheetWindow.styleMask = [.titled, .fullSizeContentView] // 移除.closable，隐藏右上角关闭按钮
            sheetWindow.title = "离线操作进度"
            sheetWindow.titlebarAppearsTransparent = false // 显示标题栏
            sheetWindow.titleVisibility = .visible // 显示标题

            // 设置窗口代理，以便在用户点击关闭按钮时正确处理
            sheetWindow.delegate = self

            // 为sheet窗口添加独立的工具栏代理
            let toolbarDelegate = BaseSheetToolbarDelegate()
            toolbarDelegate.onClose = { [weak window, weak self] in
                // 关闭sheet
                if let sheetWindow = self?.currentSheetWindow {
                    window?.endSheet(sheetWindow)
                }
            }

            let toolbar = NSToolbar(identifier: "OfflineOperationsProgressToolbar")
            toolbar.displayMode = .iconOnly
            toolbar.delegate = toolbarDelegate
            sheetWindow.toolbar = toolbar
            sheetWindow.toolbarStyle = .unified

            // 存储当前sheet窗口引用和工具栏代理引用
            currentSheetWindow = sheetWindow
            currentSheetToolbarDelegate = toolbarDelegate

            // 显示sheet
            window.beginSheet(sheetWindow) { _ in
                // 清理sheet窗口引用和工具栏代理引用
                self.currentSheetWindow = nil
                self.currentSheetToolbarDelegate = nil
            }
        }

        @objc internal func retryFailedOperations(_: Any?) {

            // 检查是否有失败的离线操作（使用新的 UnifiedOperationQueue）
            let unifiedQueue = operationQueue
            let stats = unifiedQueue.getStatistics()
            let failedCount = stats["failed"] ?? 0

            if failedCount == 0 {
                let alert = NSAlert()
                alert.messageText = "重试失败的操作"
                alert.informativeText = "没有失败的操作需要重试。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                alert.runModal()
                return
            }

            // 询问用户是否要重试失败的操作
            let alert = NSAlert()
            alert.messageText = "重试失败的操作"
            alert.informativeText = "确定要重试 \(failedCount) 个失败的操作吗？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "重试")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 重试失败的操作（使用新的 OperationProcessor）
                Task {
                    await self.operationProcessor.processRetries()
                }
            }
        }

        // MARK: - 锁定私密笔记动作

        @objc internal func lockPrivateNotes(_: Any?) {

            coordinator.authState.isPrivateNotesUnlocked = false

            coordinator.noteListState.selectedNote = nil

            // 显示提示信息
            let alert = NSAlert()
            alert.messageText = "私密笔记已锁定"
            alert.informativeText = "私密笔记已锁定，需要重新输入密码才能访问。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()

            // 刷新工具栏验证
            makeToolbarValidate()
        }

        // MARK: - 侧边栏切换

        @objc internal func toggleSidebar(_: Any?) {
            guard let window,
                  let splitViewController = window.contentViewController as? NSSplitViewController,
                  !splitViewController.splitViewItems.isEmpty
            else {
                return
            }

            let sidebarItem = splitViewController.splitViewItems[0]
            let isCurrentlyCollapsed = sidebarItem.isCollapsed

            // 切换侧边栏状态
            sidebarItem.animator().isCollapsed = !isCurrentlyCollapsed
        }

        // MARK: - 格式菜单

        @objc internal func showFormatMenu(_ sender: Any?) {
            // 显示格式菜单popover

            // 如果popover已经显示，则关闭它
            if let popover = formatMenuPopover, popover.isShown {
                popover.performClose(sender)
                formatMenuPopover = nil
                return
            }

            // 获取原生编辑器上下文
            guard let nativeEditorContext = getCurrentNativeEditorContext() else {
                return
            }

            // 请求内容同步并更新格式状态
            nativeEditorContext.requestContentSync()

            // 创建原生编辑器格式菜单视图
            let formatMenuView = NativeFormatMenuView(context: nativeEditorContext) { [weak self] _ in
                // 格式操作完成后关闭popover
                self?.formatMenuPopover?.performClose(nil)
                self?.formatMenuPopover = nil
            }
            .environmentObject(coordinator.editorModule.formatStateManager)

            let hostingController = NSHostingController(rootView: AnyView(formatMenuView))
            let contentSize = NSSize(width: 280, height: 450)

            // 设置托管控制器的视图大小
            hostingController.view.frame = NSRect(origin: .zero, size: contentSize)

            // 创建popover
            let popover = NSPopover()
            popover.contentSize = contentSize
            popover.behavior = .transient
            popover.animates = true
            popover.contentViewController = hostingController

            // 存储popover引用
            formatMenuPopover = popover

            // 显示popover
            if let button = sender as? NSButton {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            } else if let window, let contentView = window.contentView {
                // 如果没有按钮，显示在窗口中央
                popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxY)
            }
        }

        // MARK: - 视图选项菜单

        /// 显示视图选项菜单（已弃用，改用原生 NSMenu）
        @objc internal func showViewOptionsMenu(_: Any?) {
            // 此方法已弃用，视图选项菜单现在使用原生 NSMenuToolbarItem
        }

        // MARK: - 视图选项菜单操作

        /// 设置排序方式为编辑时间
        @objc internal func setSortOrderEditDate(_: Any?) {
            ViewOptionsManager.shared.setSortOrder(.editDate)
            coordinator.noteListState.notesListSortField = .editDate
        }

        /// 设置排序方式为创建时间
        @objc internal func setSortOrderCreateDate(_: Any?) {
            ViewOptionsManager.shared.setSortOrder(.createDate)
            coordinator.noteListState.notesListSortField = .createDate
        }

        /// 设置排序方式为标题
        @objc internal func setSortOrderTitle(_: Any?) {
            ViewOptionsManager.shared.setSortOrder(.title)
            coordinator.noteListState.notesListSortField = .title
            // 按标题排序时，自动关闭日期分组（因为日期分组对标题排序没有意义）
            if ViewOptionsManager.shared.isDateGroupingEnabled {
                ViewOptionsManager.shared.setDateGrouping(false)
            }
        }

        /// 设置排序方向为降序
        @objc internal func setSortDirectionDescending(_: Any?) {
            ViewOptionsManager.shared.setSortDirection(.descending)
            coordinator.noteListState.notesListSortDirection = .descending
        }

        /// 设置排序方向为升序
        @objc internal func setSortDirectionAscending(_: Any?) {
            ViewOptionsManager.shared.setSortDirection(.ascending)
            coordinator.noteListState.notesListSortDirection = .ascending
        }

        /// 切换日期分组（已弃用，改用 setDateGroupingOn/Off）
        @objc internal func toggleDateGrouping(_: Any?) {
            ViewOptionsManager.shared.toggleDateGrouping()
        }

        /// 开启日期分组
        @objc internal func setDateGroupingOn(_: Any?) {
            // 如果当前是按标题排序，自动切换到按编辑时间排序
            // 因为按标题排序时日期分组没有意义
            if ViewOptionsManager.shared.sortOrder == .title {
                ViewOptionsManager.shared.setSortOrder(.editDate)
                coordinator.noteListState.notesListSortField = .editDate
            }
            ViewOptionsManager.shared.setDateGrouping(true)
        }

        /// 关闭日期分组
        @objc internal func setDateGroupingOff(_: Any?) {
            ViewOptionsManager.shared.setDateGrouping(false)
        }

        /// 设置视图模式为列表视图
        @objc internal func setViewModeList(_: Any?) {
            ViewOptionsManager.shared.setViewMode(.list)
        }

        /// 设置视图模式为画廊视图
        @objc internal func setViewModeGallery(_: Any?) {
            ViewOptionsManager.shared.setViewMode(.gallery)
        }

        /// 返回画廊视图
        /// 从画廊视图的笔记编辑模式返回到画廊网格视图
        @objc internal func backToGallery(_: Any?) {
            // 发送通知让 SwiftUI 视图收起展开的笔记
            NotificationCenter.default.post(name: .backToGalleryRequested, object: nil)
        }

        // MARK: - 编辑器上下文

        /// 获取当前的 NativeEditorContext
        func getCurrentNativeEditorContext() -> NativeEditorContext? {
            coordinator.noteEditorState.nativeEditorContext
        }

        // MARK: - 编辑菜单动作

        @objc func undo(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func redo(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func cut(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func copy(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func paste(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc override func selectAll(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        // MARK: - 格式菜单动作

        @objc func increaseFontSize(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func decreaseFontSize(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func increaseIndent(_: Any?) {

            guard coordinator.noteListState.selectedNote != nil else {
                return
            }

            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.increaseIndent()
            } else {
                LogService.shared.error(.window, "无法获取 NativeEditorContext")
            }
        }

        @objc func decreaseIndent(_: Any?) {

            guard coordinator.noteListState.selectedNote != nil else {
                return
            }

            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.decreaseIndent()
            } else {
                LogService.shared.error(.window, "无法获取 NativeEditorContext")
            }
        }

        @objc func alignLeft(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func alignCenter(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func alignRight(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func toggleBulletList(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func toggleNumberedList(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func toggleCheckboxList(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func setHeading1(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func setHeading2(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func setHeading3(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        @objc func setBodyText(_: Any?) {
            // 这里应该调用编辑器API
            // 暂时使用控制台输出
        }

        // MARK: - 格式菜单动作（Apple Notes 风格）

        /// 切换块引用
        @objc func toggleBlockQuote(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "块引用")
        }

        // MARK: - 核对清单动作

        /// 标记为已勾选
        @objc func markAsChecked(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "标记为已勾选")
        }

        /// 全部勾选
        @objc func checkAll(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "全部勾选")
        }

        /// 全部取消勾选
        @objc func uncheckAll(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "全部取消勾选")
        }

        /// 将勾选的项目移到底部
        @objc func moveCheckedToBottom(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "将勾选的项目移到底部")
        }

        /// 删除已勾选项目
        @objc func deleteCheckedItems(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "删除已勾选项目")
        }

        /// 向上移动项目
        @objc func moveItemUp(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "向上移动项目")
        }

        /// 向下移动项目
        @objc func moveItemDown(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "向下移动项目")
        }

        // MARK: - 外观动作

        /// 切换浅色背景
        @objc func toggleLightBackground(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "浅色背景")
        }

        /// 切换高亮
        @objc func toggleHighlight(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "高亮")
        }

        // MARK: - 新增的菜单动作方法

        @objc func copyNote(_: Any?) {
            guard let note = coordinator.noteListState.selectedNote else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            // 复制标题和内容
            let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
            pasteboard.setString(content, forType: .string)
        }

        // MARK: - 查找功能

        /// 通过 NSTextFinder 原生查找面板执行查找操作
        private func performFindAction(_ action: NSTextFinder.Action) {
            let menuItem = NSMenuItem()
            menuItem.tag = Int(action.rawValue)
            NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: menuItem)
        }

        /// 显示查找面板
        @objc func showFindPanel(_: Any?) {
            performFindAction(.showFindInterface)
        }

        /// 查找下一个匹配项
        @objc func findNext(_: Any?) {
            performFindAction(.nextMatch)
        }

        /// 查找上一个匹配项
        @objc func findPrevious(_: Any?) {
            performFindAction(.previousMatch)
        }

        /// 显示查找和替换面板
        @objc func showFindAndReplacePanel(_: Any?) {
            performFindAction(.showReplaceInterface)
        }

        // MARK: - 附件操作

        /// 附加文件到当前笔记
        /// - Parameter url: 文件 URL
        @objc func attachFile(_ url: URL) {

            guard coordinator.noteListState.selectedNote != nil else {
                return
            }

            // 根据文件类型处理
            let fileExtension = url.pathExtension.lowercased()
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]

            if imageExtensions.contains(fileExtension) {
                // 图片文件：使用现有的图片插入功能
                Task { @MainActor in
                    await self.insertImage(from: url)
                }
            } else {
                // 其他文件：显示提示（功能待实现）
                let alert = NSAlert()
                alert.messageText = "功能开发中"
                alert.informativeText = "非图片文件的附件功能正在开发中，敬请期待。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        }

        /// 添加链接到当前笔记
        /// - Parameter urlString: 链接地址
        @objc func addLink(_ urlString: String) {

            guard coordinator.noteListState.selectedNote != nil else {
                return
            }

            // 验证 URL 格式
            guard let url = URL(string: urlString), url.scheme != nil else {
                let alert = NSAlert()
                alert.messageText = "无效的链接"
                alert.informativeText = "请输入有效的链接地址（例如：https://example.com）"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
                return
            }

            // 链接插入功能待实现
            // TODO: 根据编辑器类型插入链接

            let alert = NSAlert()
            alert.messageText = "功能开发中"
            alert.informativeText = "链接插入功能正在开发中，敬请期待。\n\n链接地址：\(urlString)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }

        /// 放大
        @objc func zoomIn(_: Any?) {

            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.zoomIn()
            } else {
                LogService.shared.error(.window, "无法获取 NativeEditorContext")
            }
        }

        /// 缩小
        @objc func zoomOut(_: Any?) {

            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.zoomOut()
            } else {
                LogService.shared.error(.window, "无法获取 NativeEditorContext")
            }
        }

        /// 实际大小
        @objc func actualSize(_: Any?) {

            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.resetZoom()
            } else {
                LogService.shared.error(.window, "无法获取 NativeEditorContext")
            }
        }

        /// 展开区域
        @objc func expandSection(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "展开区域")
        }

        /// 展开所有区域
        @objc func expandAllSections(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "展开所有区域")
        }

        /// 折叠区域
        @objc func collapseSection(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "折叠区域")
        }

        /// 折叠所有区域
        @objc func collapseAllSections(_: Any?) {
            // 功能尚未实现，显示提示
            showFeatureNotImplementedAlert(featureName: "折叠所有区域")
        }

        /// 显示功能尚未实现的提示
        ///
        /// 用于未实现的菜单功能，向用户显示友好的提示信息
        ///
        /// - Parameter featureName: 功能名称
        private func showFeatureNotImplementedAlert(featureName: String) {
            guard let window else { return }

            let alert = NSAlert()
            alert.messageText = "功能尚未实现"
            alert.informativeText = "「\(featureName)」功能正在开发中，敬请期待。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")

            alert.beginSheetModal(for: window) { _ in }
        }

    }

#endif
