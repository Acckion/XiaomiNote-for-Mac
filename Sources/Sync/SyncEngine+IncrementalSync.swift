import Foundation

// MARK: - SyncEngine 增量同步辅助方法

extension SyncEngine {

    // MARK: - 增量同步辅助方法

    /// 增量同步文件夹
    func syncFoldersIncremental(cloudFolders: [Folder], cloudFolderIds _: Set<String>) async throws {
        let pendingOps = operationQueue.getPendingOperations()
        let localFolders = try localStorage.loadFolders()

        for cloudFolder in cloudFolders {
            if cloudFolder.isSystem || cloudFolder.id == "0" || cloudFolder.id == "starred" {
                continue
            }

            if let localFolder = localFolders.first(where: { $0.id == cloudFolder.id }) {
                // 云端和本地都存在
                if cloudFolder.createdAt > localFolder.createdAt {
                    // 云端较新
                    await eventBus.publish(FolderEvent.folderSaved(cloudFolder))
                    LogService.shared.debug(.sync, "文件夹云端较新，已更新: \(cloudFolder.name)")
                } else if localFolder.createdAt > cloudFolder.createdAt {
                    // 本地较新，添加到上传队列
                    let hasRenameOp = pendingOps.contains { $0.type == .folderRename && $0.noteId == localFolder.id }
                    if !hasRenameOp {
                        _ = try operationQueue.enqueueFolderRename(
                            folderId: localFolder.id,
                            name: localFolder.name,
                            tag: localFolder.rawData?["tag"] as? String ?? localFolder.id
                        )
                        LogService.shared.debug(.sync, "文件夹本地较新，已添加到上传队列: \(localFolder.name)")
                    }
                } else {
                    // 时间一致但名称不同
                    if cloudFolder.name != localFolder.name {
                        await eventBus.publish(FolderEvent.folderSaved(cloudFolder))
                        LogService.shared.debug(.sync, "文件夹名称不同，已更新: \(cloudFolder.name)")
                    }
                }
            } else {
                // 只有云端存在
                let hasDeleteOp = pendingOps.contains { $0.type == .folderDelete && $0.noteId == cloudFolder.id }
                if hasDeleteOp {
                    if let tag = cloudFolder.rawData?["tag"] as? String {
                        // 删除操作已在队列中，由 OperationProcessor 统一处理
                        LogService.shared.debug(.sync, "文件夹在删除队列中，跳过: \(cloudFolder.name)")
                    }
                } else {
                    await eventBus.publish(FolderEvent.folderSaved(cloudFolder))
                    LogService.shared.debug(.sync, "新文件夹，已拉取到本地: \(cloudFolder.name)")
                }
            }
        }
    }

    /// 增量同步单个笔记
    func syncNoteIncremental(cloudNote: Note) async throws -> NoteSyncResult {
        var result = NoteSyncResult(noteId: cloudNote.id, noteTitle: cloudNote.title)
        let pendingOps = operationQueue.getPendingOperations()

        // 同步保护检查
        let shouldSkip = await syncGuard.shouldSkipSync(
            noteId: cloudNote.id,
            cloudTimestamp: cloudNote.updatedAt
        )
        if shouldSkip {
            if let skipReason = await syncGuard.getSkipReason(
                noteId: cloudNote.id,
                cloudTimestamp: cloudNote.updatedAt
            ) {
                LogService.shared.debug(.sync, "同步保护：跳过笔记 \(cloudNote.id.prefix(8)) - \(skipReason.description)")
            }
            result.status = .skipped
            result.message = "同步保护：笔记正在编辑、待上传或使用临时 ID"
            result.success = true
            return result
        }

        if let localNote = try localStorage.loadNote(noteId: cloudNote.id) {
            // 云端和本地都存在
            if localNote.updatedAt > cloudNote.updatedAt {
                // 本地较新，添加到上传队列
                let hasUpdateOp = pendingOps.contains { $0.type == .cloudUpload && $0.noteId == localNote.id }
                if !hasUpdateOp {
                    _ = try operationQueue.enqueueCloudUpload(
                        noteId: localNote.id,
                        title: localNote.title,
                        content: localNote.content,
                        folderId: localNote.folderId
                    )
                    LogService.shared.debug(.sync, "笔记本地较新，已添加到上传队列: \(localNote.title)")
                }
                result.status = .skipped
                result.message = "本地较新，等待上传"
                result.success = true
            } else if cloudNote.updatedAt > localNote.updatedAt {
                // 云端较新
                let noteDetails = try await noteAPI.fetchNoteDetails(noteId: cloudNote.id)
                var updatedNote = cloudNote
                NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                    NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                }

                await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                result.status = .updated
                result.message = "已从云端更新"
                result.success = true
                LogService.shared.debug(.sync, "笔记云端较新，已更新: \(cloudNote.title)")
            } else {
                // 时间一致，比较内容
                if localNote.primaryXMLContent != cloudNote.primaryXMLContent {
                    let noteDetails = try await noteAPI.fetchNoteDetails(noteId: cloudNote.id)
                    var updatedNote = cloudNote
                    NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                        NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                    }

                    await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                    result.status = .updated
                    result.message = "内容不同，已更新"
                    result.success = true
                } else {
                    result.status = .skipped
                    result.message = "内容相同，跳过"
                    result.success = true
                }
            }
        } else {
            // 只有云端存在
            let hasDeleteOp = pendingOps.contains { $0.type == .cloudDelete && $0.noteId == cloudNote.id }
            if hasDeleteOp {
                if let tag = cloudNote.serverTag {
                    // 删除操作已在队列中，由 OperationProcessor 统一处理
                    result.status = .skipped
                    result.message = "在删除队列中，等待处理"
                    result.success = true
                    LogService.shared.debug(.sync, "笔记在删除队列中，跳过: \(cloudNote.title)")
                }
            } else {
                // 再次检查本地是否存在（防止并发问题）
                if let existingNote = try? localStorage.loadNote(noteId: cloudNote.id) {
                    if existingNote.updatedAt < cloudNote.updatedAt {
                        let noteDetails = try await noteAPI.fetchNoteDetails(noteId: cloudNote.id)
                        var updatedNote = cloudNote
                        NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                        if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                            NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                        }

                        await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                        result.status = .updated
                        result.message = "已从云端更新"
                        result.success = true
                    } else {
                        result.status = .skipped
                        result.message = "本地已存在且较新或相同"
                        result.success = true
                    }
                } else {
                    // 新笔记，下载到本地
                    let noteDetails = try await noteAPI.fetchNoteDetails(noteId: cloudNote.id)
                    var updatedNote = cloudNote
                    NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                        NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                    }

                    await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                    result.status = .created
                    result.message = "已从云端拉取"
                    result.success = true
                    LogService.shared.debug(.sync, "新笔记，已拉取到本地: \(cloudNote.title)")
                }
            }
        }

        return result
    }

    /// 处理只有本地存在但云端不存在的笔记和文件夹
    func syncLocalOnlyItems(cloudNoteIds: Set<String>, cloudFolderIds: Set<String>) async throws {
        let pendingOps = operationQueue.getPendingOperations()
        let localNotes = try localStorage.getAllLocalNotes()
        let localFolders = try localStorage.loadFolders()

        // 处理本地独有的笔记
        for localNote in localNotes {
            if NoteOperation.isTemporaryId(localNote.id) { continue }
            if cloudNoteIds.contains(localNote.id) { continue }

            let hasCreateOp = pendingOps.contains { $0.type == .noteCreate && $0.noteId == localNote.id }
            if hasCreateOp {
                // 已有 noteCreate 操作在队列中，由 OperationProcessor 处理
                LogService.shared.debug(.sync, "笔记在创建队列中，跳过: \(localNote.title)")
                continue
            } else {
                let hasUpdateOp = pendingOps.contains { $0.type == .cloudUpload && $0.noteId == localNote.id }
                if !hasUpdateOp {
                    await eventBus.publish(NoteEvent.deleted(noteId: localNote.id, tag: nil))
                    LogService.shared.debug(.sync, "笔记不在新建队列，已删除本地: \(localNote.title)")
                }
            }
        }

        // 处理本地独有的文件夹
        for localFolder in localFolders {
            if localFolder.isSystem || localFolder.id == "0" || localFolder.id == "starred" { continue }
            if cloudFolderIds.contains(localFolder.id) { continue }

            let hasCreateOp = pendingOps.contains { $0.type == .folderCreate && $0.noteId == localFolder.id }
            if hasCreateOp {
                // 已有 folderCreate 操作在队列中，由 OperationProcessor 处理
                LogService.shared.debug(.sync, "文件夹在创建队列中，跳过: \(localFolder.name)")
            } else {
                await eventBus.publish(FolderEvent.deleted(folderId: localFolder.id))
                LogService.shared.debug(.sync, "文件夹不在新建队列，已删除本地: \(localFolder.name)")
            }
        }
    }

    // MARK: - 轻量级同步辅助方法

    /// 解析轻量级同步响应
    func parseLightweightSyncResponse(_ response: [String: Any]) throws -> (notes: [Note], folders: [Folder], syncTag: String) {
        var syncTag = ""
        if let data = response["data"] as? [String: Any],
           let noteView = data["note_view"] as? [String: Any],
           let noteViewData = noteView["data"] as? [String: Any],
           let newSyncTag = noteViewData["syncTag"] as? String
        {
            syncTag = newSyncTag
        }

        var modifiedNotes: [Note] = []
        var modifiedFolders: [Folder] = []

        if let data = response["data"] as? [String: Any],
           let noteView = data["note_view"] as? [String: Any],
           let noteViewData = noteView["data"] as? [String: Any]
        {
            if let entries = noteViewData["entries"] as? [[String: Any]] {
                for entry in entries {
                    if let note = NoteMapper.fromMinoteListData(entry) {
                        modifiedNotes.append(note)
                    }
                }
            }

            if let folders = noteViewData["folders"] as? [[String: Any]] {
                for folderEntry in folders {
                    if let folder = Folder.fromMinoteData(folderEntry) {
                        modifiedFolders.append(folder)
                    }
                }
            }
        }

        LogService.shared.debug(.sync, "解析轻量级同步响应: \(modifiedNotes.count) 个笔记, \(modifiedFolders.count) 个文件夹")
        return (modifiedNotes, modifiedFolders, syncTag)
    }

    /// 处理有修改的文件夹
    func processModifiedFolder(_ folder: Folder) async throws {
        if let rawData = folder.rawData,
           let status = rawData["status"] as? String,
           status == "deleted"
        {
            await eventBus.publish(FolderEvent.deleted(folderId: folder.id))
            LogService.shared.debug(.sync, "文件夹已删除: \(folder.id)")
        } else {
            await eventBus.publish(FolderEvent.folderSaved(folder))
            LogService.shared.debug(.sync, "文件夹已更新: \(folder.name)")
        }
    }

    /// 处理有修改的笔记
    func processModifiedNote(_ note: Note) async throws -> NoteSyncResult {
        var result = NoteSyncResult(noteId: note.id, noteTitle: note.title)

        let shouldSkip = await syncGuard.shouldSkipSync(
            noteId: note.id,
            cloudTimestamp: note.updatedAt
        )
        if shouldSkip {
            if let skipReason = await syncGuard.getSkipReason(
                noteId: note.id,
                cloudTimestamp: note.updatedAt
            ) {
                LogService.shared.debug(.sync, "同步保护：跳过笔记 \(note.id.prefix(8)) - \(skipReason.description)")
            }
            result.status = .skipped
            result.message = "同步保护：笔记正在编辑、待上传或使用临时 ID"
            result.success = true
            return result
        }

        // 已删除的笔记
        if note.status == "deleted" {
            await eventBus.publish(NoteEvent.deleted(noteId: note.id, tag: nil))
            result.status = .skipped
            result.message = "笔记已从云端删除"
            result.success = true
            return result
        }

        do {
            let noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
            var updatedNote = note
            NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

            if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
            }

            await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))

            let existsLocally = localStorage.noteExistsLocally(noteId: note.id)
            result.status = existsLocally ? .updated : .created
            result.message = existsLocally ? "笔记已更新" : "新笔记已下载"
            result.success = true
        } catch let error as MiNoteError {
            throw mapMiNoteError(error)
        } catch {
            LogService.shared.error(.sync, "获取笔记详情失败: \(error)")
            throw SyncError.networkError(error)
        }

        return result
    }

    // MARK: - 通用笔记处理

    /// 处理单个笔记（全量同步模式）
    func processNote(_ note: Note, isFullSync: Bool = false) async throws -> NoteSyncResult {
        var result = NoteSyncResult(noteId: note.id, noteTitle: note.title)

        do {
            if isFullSync {
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
                } catch let error as MiNoteError {
                    throw mapMiNoteError(error)
                }

                var updatedNote = note
                NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                }

                await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))

                let existsLocally = localStorage.noteExistsLocally(noteId: note.id)
                result.status = existsLocally ? .updated : .created
                result.message = result.status == .updated ? "笔记已替换" : "笔记已下载"
                result.success = true
                return result
            }

            let existsLocally = localStorage.noteExistsLocally(noteId: note.id)

            if existsLocally {
                if let localNote = try? localStorage.loadNote(noteId: note.id) {
                    let timeDifference = abs(note.updatedAt.timeIntervalSince(localNote.updatedAt))

                    if note.updatedAt < localNote.updatedAt, timeDifference > 2.0 {
                        result.status = .skipped
                        result.message = "本地版本较新，跳过同步"
                        result.success = true
                        return result
                    }

                    if timeDifference < 2.0 {
                        do {
                            let noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
                            var cloudNote = note
                            NoteMapper.updateFromServerDetails(&cloudNote, details: noteDetails)

                            if localNote.primaryXMLContent == cloudNote.primaryXMLContent {
                                result.status = .skipped
                                result.message = "笔记未修改"
                                result.success = true
                                return result
                            } else {
                                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                                    NoteMapper.updateSettingData(&cloudNote, settingData: updatedSettingData)
                                }

                                await eventBus.publish(SyncEvent.noteDownloaded(cloudNote))
                                result.status = .updated
                                result.message = "笔记已更新"
                                result.success = true
                                return result
                            }
                        } catch {
                            LogService.shared.warning(.sync, "获取笔记详情失败，继续使用原有逻辑: \(error)")
                        }
                    }
                }

                let noteDetails: [String: Any]
                do {
                    noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
                } catch let error as MiNoteError {
                    throw mapMiNoteError(error)
                }

                var updatedNote = note
                NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                }

                await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                result.status = .updated
                result.message = "笔记已更新"
            } else {
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
                } catch let error as MiNoteError {
                    throw mapMiNoteError(error)
                }

                var newNote = note
                NoteMapper.updateFromServerDetails(&newNote, details: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    NoteMapper.updateSettingData(&newNote, settingData: updatedSettingData)
                }

                await eventBus.publish(SyncEvent.noteDownloaded(newNote))
                result.status = .created
                result.message = "新笔记已下载"
            }

            result.success = true
        } catch let error as SyncError {
            throw error
        } catch {
            result.success = false
            result.status = .failed
            result.message = "处理失败: \(error.localizedDescription)"
        }

        return result
    }
}
