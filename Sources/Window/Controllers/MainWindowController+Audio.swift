//
//  MainWindowController+Audio.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import SwiftUI

    // MARK: - 音频面板管理

    extension MainWindowController {

        /// 显示音频面板
        ///
        /// 在主窗口右侧添加第四栏显示音频面板。
        /// 如果当前是画廊模式，则不显示音频面板。
        ///
        func showAudioPanel() {
            guard let window,
                  let splitViewController = window.contentViewController as? NSSplitViewController
            else {
                LogService.shared.error(.window, "无法显示音频面板：窗口或分割视图控制器不存在")
                return
            }

            // 检查是否是画廊模式，画廊模式下不支持音频面板
            if ViewOptionsManager.shared.viewMode == .gallery {
                return
            }

            // 检查是否已经显示了音频面板（四栏布局）
            if splitViewController.splitViewItems.count >= 4 {
                return
            }

            // 确保当前是三栏布局
            guard splitViewController.splitViewItems.count == 3 else {
                LogService.shared.error(.window, "当前不是三栏布局，无法添加音频面板")
                return
            }

            // 创建音频面板托管控制器
            let audioPanelController = AudioPanelHostingController(
                stateManager: audioPanelStateManager
            )

            // 设置录制完成回调
            audioPanelController.onRecordingComplete = { [weak self] url in
                self?.handleAudioRecordingComplete(url: url)
            }

            // 设置关闭回调
            audioPanelController.onClose = { [weak self] in
                self?.audioPanelStateManager.hide()
            }

            // 保存引用
            audioPanelHostingController = audioPanelController

            // 创建分割视图项
            let audioPanelSplitViewItem = NSSplitViewItem(viewController: audioPanelController)
            audioPanelSplitViewItem.minimumThickness = 280
            audioPanelSplitViewItem.maximumThickness = 400
            audioPanelSplitViewItem.canCollapse = false
            // 音频面板的 holdingPriority 设置为 252，高于编辑器的 250
            // 这样窗口缩小时会优先压缩编辑器而非音频面板
            audioPanelSplitViewItem.holdingPriority = NSLayoutConstraint.Priority(252)

            // 添加到分割视图控制器作为第四栏
            splitViewController.addSplitViewItem(audioPanelSplitViewItem)

            // 让音频面板成为第一响应者，以便接收键盘事件（如 Escape 键）
            DispatchQueue.main.async {
                window.makeFirstResponder(audioPanelController)
            }

        }

        /// 隐藏音频面板
        ///
        /// 从主窗口移除第四栏，恢复三栏布局。
        ///
        func hideAudioPanel() {
            guard let window,
                  let splitViewController = window.contentViewController as? NSSplitViewController
            else {
                LogService.shared.error(.window, "无法隐藏音频面板：窗口或分割视图控制器不存在")
                return
            }

            // 检查是否有第四栏（音频面板）
            guard splitViewController.splitViewItems.count >= 4 else {
                return
            }

            // 移除第四栏（音频面板）
            let audioPanelItem = splitViewController.splitViewItems[3]
            splitViewController.removeSplitViewItem(audioPanelItem)

            // 清除引用
            audioPanelHostingController = nil

        }

        /// 显示音频面板关闭确认对话框
        ///
        /// 当用户在录制过程中尝试关闭面板时显示确认对话框。
        ///
        func showAudioPanelCloseConfirmation() {
            guard let window else { return }

            let alert = NSAlert()
            alert.messageText = "正在录制中"
            alert.informativeText = "您正在录制语音，是否要保存当前录制内容？"
            alert.alertStyle = .warning

            // 添加按钮
            alert.addButton(withTitle: "保存并关闭")
            alert.addButton(withTitle: "放弃录制")
            alert.addButton(withTitle: "取消")

            alert.beginSheetModal(for: window) { [weak self] response in
                switch response {
                case .alertFirstButtonReturn:
                    // 保存并关闭
                    // 停止录制并保存
                    if let url = AudioRecorderService.shared.stopRecording() {
                        self?.handleAudioRecordingComplete(url: url)
                    }
                    self?.audioPanelStateManager.forceHide()

                case .alertSecondButtonReturn:
                    // 放弃录制
                    AudioRecorderService.shared.cancelRecording()
                    self?.audioPanelStateManager.forceHide()

                default:
                    break
                }
            }
        }

        /// 处理音频录制完成
        ///
        /// 生成临时 fileId，入队上传操作，立即更新编辑器。
        ///
        func handleAudioRecordingComplete(url: URL) {

            guard let selectedNote = coordinator.noteListState.selectedNote
            else {
                LogService.shared.error(.window, "无法处理录制完成：没有选中的笔记")
                return
            }

            // 获取模板 ID
            let templateId = audioPanelStateManager.currentRecordingTemplateId

            Task { @MainActor in
                do {

                    // 更新模板状态为上传中
                    if let templateId {
                        audioPanelStateManager.setTemplateUploading(templateId: templateId)
                    }

                    // 1. 格式转换 + 生成临时 fileId + 保存到 pending_uploads
                    let uploadResult = try await AudioUploadService.shared.uploadAudio(fileURL: url)
                    let temporaryFileId = uploadResult.fileId

                    LogService.shared.info(.window, "音频已准备入队: temporaryFileId=\(temporaryFileId.prefix(20))...")

                    // 1.5. 更新笔记的 setting.data，使用临时 fileId
                    if var note = coordinator.noteListState.selectedNote {
                        var setting: [String: Any] = [
                            "themeId": 0,
                            "stickyTime": 0,
                            "version": 0,
                        ]
                        if let existingSettingJson = note.settingJson,
                           let jsonData = existingSettingJson.data(using: .utf8),
                           let existingSetting = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                        {
                            setting = existingSetting
                        }

                        var settingData = setting["data"] as? [[String: Any]] ?? []

                        let audioInfo: [String: Any] = [
                            "fileId": temporaryFileId,
                            "mimeType": uploadResult.mimeType,
                            "digest": temporaryFileId + ".mp3",
                        ]
                        settingData.append(audioInfo)
                        setting["data"] = settingData

                        if let settingJsonData = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
                           let settingString = String(data: settingJsonData, encoding: .utf8)
                        {
                            note.settingJson = settingString
                        }

                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            coordinator.noteListState.selectedNote = note
                            coordinator.noteListState.updateNoteInPlace(note)
                        }
                    }

                    // 2. 入队音频上传操作
                    let actualFileName = (url.lastPathComponent as NSString).deletingPathExtension + ".mp3"
                    try AudioUploadService.shared.enqueueAudioUpload(
                        temporaryFileId: temporaryFileId,
                        fileName: actualFileName,
                        mimeType: uploadResult.mimeType,
                        noteId: selectedNote.id
                    )

                    // 网络可用时立即处理
                    let pendingOps = UnifiedOperationQueue.shared.getPendingOperations()
                    if let audioOp = pendingOps.first(where: {
                        $0.type == .audioUpload && $0.noteId == selectedNote.id
                    }) {
                        await OperationProcessor.shared.processImmediately(audioOp)
                    }

                    // 3. 检查是否有录音模板需要更新
                    if let templateId {
                        audioPanelStateManager.setTemplateUpdating(templateId: templateId, fileId: temporaryFileId)

                        if let nativeEditorContext = self.getCurrentNativeEditorContext() {
                            try await nativeEditorContext.updateRecordingTemplateAndSave(
                                templateId: templateId,
                                fileId: temporaryFileId,
                                digest: nil,
                                mimeType: uploadResult.mimeType
                            )
                            LogService.shared.info(.window, "原生编辑器录音模板已更新: \(templateId) -> \(temporaryFileId.prefix(20))...")
                        } else {
                            LogService.shared.error(.window, "无法获取原生编辑器上下文，录音模板未更新")
                            self.audioPanelStateManager.setTemplateFailed(templateId: templateId, error: "无法获取原生编辑器上下文")
                        }

                        audioPanelStateManager.setTemplateCompleted(templateId: templateId, fileId: temporaryFileId)
                    } else {
                        if let nativeEditorContext = self.getCurrentNativeEditorContext() {
                            nativeEditorContext.insertAudio(
                                fileId: temporaryFileId,
                                digest: nil,
                                mimeType: uploadResult.mimeType
                            )
                            LogService.shared.info(.window, "音频附件已插入到原生编辑器")
                        } else {
                            LogService.shared.error(.window, "无法获取原生编辑器上下文，音频附件未插入")
                        }
                    }

                    // 4. 关闭音频面板
                    audioPanelStateManager.forceHide()

                    // 5. 删除临时文件
                    try? FileManager.default.removeItem(at: url)
                    LogService.shared.debug(.window, "临时文件已删除")
                } catch {
                    LogService.shared.error(.window, "音频上传准备失败: \(error.localizedDescription)")

                    if let templateId {
                        audioPanelStateManager.setTemplateFailed(templateId: templateId, error: error.localizedDescription)
                    }

                    await showAudioUploadErrorAlert(error: error)
                }
            }
        }

        /// 显示音频上传错误提示
        ///
        /// - Parameter error: 上传错误
        func showAudioUploadErrorAlert(error: Error) async {
            guard let window else { return }

            let alert = NSAlert()
            alert.messageText = "音频上传失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")

            alert.beginSheetModal(for: window) { _ in }
        }

        /// 公开方法：显示音频面板进入录制模式
        ///
        /// 供工具栏按钮调用，显示音频面板并进入录制模式。
        ///
        func showAudioPanelForRecording() {
            guard let selectedNote = coordinator.noteListState.selectedNote
            else {
                LogService.shared.error(.window, "无法显示录制面板：没有选中的笔记")
                return
            }

            audioPanelStateManager.showForRecording(noteId: selectedNote.id)
        }

        /// 公开方法：显示音频面板进入播放模式
        ///
        /// 供音频附件点击调用，显示音频面板并播放指定音频。
        ///
        func showAudioPanelForPlayback(fileId: String) {
            guard let selectedNote = coordinator.noteListState.selectedNote
            else {
                LogService.shared.error(.window, "无法显示播放面板：没有选中的笔记")
                return
            }

            audioPanelStateManager.showForPlayback(fileId: fileId, noteId: selectedNote.id)
        }
    }

#endif
