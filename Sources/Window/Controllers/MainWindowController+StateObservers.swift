//
//  MainWindowController+StateObservers.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import Combine

    // MARK: - 状态监听

    extension MainWindowController {

        /// 设置状态监听器
        func setupStateObservers() {
            // 监听登录视图显示状态（通过 AuthState）
            coordinator.authState.$showLoginView
                .receive(on: RunLoop.main)
                .sink { [weak self] showLoginView in
                    if showLoginView {
                        self?.showLogin(nil)
                        self?.coordinator.authState.showLoginView = false
                    }
                }
                .store(in: &cancellables)

            // 监听选中的文件夹变化，更新窗口标题（通过 FolderState）
            coordinator.folderState.$selectedFolder
                .receive(on: RunLoop.main)
                .sink { [weak self] selectedFolder in
                    self?.updateWindowTitle(for: selectedFolder)
                }
                .store(in: &cancellables)

            // 监听笔记列表变化，更新窗口副标题（通过 NoteListState）
            coordinator.noteListState.$notes
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.updateWindowTitle(for: self?.coordinator.folderState.selectedFolder)
                }
                .store(in: &cancellables)

            // 监听选中文件夹变化，更新工具栏（通过 FolderState）
            coordinator.folderState.$selectedFolder
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.reconfigureToolbar()
                }
                .store(in: &cancellables)

            // 监听私密笔记解锁状态变化，更新工具栏（通过 AuthState）
            coordinator.authState.$isPrivateNotesUnlocked
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.reconfigureToolbar()
                }
                .store(in: &cancellables)

            // 监听搜索文本变化，同步到搜索框UI并更新窗口标题（通过 NoteListState）
            coordinator.noteListState.$searchText
                .receive(on: RunLoop.main)
                .sink { [weak self] searchText in
                    guard let self else { return }
                    if let searchField = currentSearchField,
                       searchField.stringValue != searchText
                    {
                        searchField.stringValue = searchText
                    }
                    updateWindowTitle(for: coordinator.folderState.selectedFolder)
                }
                .store(in: &cancellables)

            // 监听来自设置视图的登录请求
            settingsEventTask = Task { [weak self] in
                let stream = await EventBus.shared.subscribe(to: SettingsEvent.self)
                for await event in stream {
                    guard let self else { break }
                    switch event {
                    case .showLoginRequested:
                        showLogin(nil)
                    case .editorSettingsChanged:
                        break
                    }
                }
            }

            // 监听音频面板可见性变化
            NotificationCenter.default.addObserver(
                forName: AudioPanelStateManager.visibilityDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let visible = notification.userInfo?["visible"] as? Bool else { return }
                if visible {
                    self?.showAudioPanel()
                } else {
                    self?.hideAudioPanel()
                }
            }

            // 监听音频面板需要确认对话框通知
            NotificationCenter.default.addObserver(
                forName: AudioPanelStateManager.needsConfirmationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.showAudioPanelCloseConfirmation()
            }

            // 监听音频附件点击通知
            NotificationCenter.default.addObserver(
                forName: .audioAttachmentClicked,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let fileId = NotificationCenter.extractAudioFileId(from: notification) else {
                    LogService.shared.error(.window, "收到音频附件点击通知但缺少 fileId")
                    return
                }
                self?.showAudioPanelForPlayback(fileId: fileId)
            }

        }

        /// 重新配置工具栏
        func reconfigureToolbar() {
            // 简单的方法：只验证工具栏项，让工具栏根据toolbarDefaultItemIdentifiers动态更新
            makeToolbarValidate()
        }

        /// 更新窗口标题和副标题
        func updateWindowTitle(for folder: Folder?) {
            guard let window else { return }

            let noteListState = coordinator.noteListState

            if !noteListState.searchText.isEmpty {
                coordinator.folderState.selectFolder(nil)
                window.title = "搜索"

                let foundCount = noteListState.filteredNotes.count
                window.subtitle = "找到\(foundCount)个笔记"
            } else {
                let folderName = folder?.name ?? "笔记"
                window.title = folderName

                let noteCount = getNoteCount(for: folder)
                window.subtitle = "\(noteCount)个笔记"
            }
        }

        /// 获取指定文件夹中的笔记数量
        func getNoteCount(for folder: Folder?) -> Int {
            let notes = coordinator.noteListState.notes

            if let folder {
                if folder.id == "starred" {
                    return notes.count(where: { $0.isStarred })
                } else if folder.id == "0" {
                    return notes.count
                } else if folder.id == "2" {
                    return notes.count(where: { $0.folderId == "2" })
                } else if folder.id == "uncategorized" {
                    return notes.count(where: { $0.folderId == "0" || $0.folderId.isEmpty })
                } else {
                    return notes.count(where: { $0.folderId == folder.id })
                }
            } else {
                return notes.count
            }
        }
    }

#endif
