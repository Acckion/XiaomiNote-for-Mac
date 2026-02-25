import Foundation

// MARK: - 笔记操作处理器

/// 笔记操作处理器
///
/// 负责处理笔记相关的操作：noteCreate、cloudUpload、cloudDelete。
/// 从 OperationProcessor 平移的笔记操作逻辑，作为独立 actor 运行。
public actor NoteOperationHandler: OperationHandler {

    // MARK: - 依赖

    private let noteAPI: NoteAPI
    private let localStorage: LocalStorageService
    private let idMappingRegistry: IdMappingRegistry
    private let operationQueue: UnifiedOperationQueue
    private let eventBus: EventBus
    private let responseParser: OperationResponseParser

    // MARK: - 回调

    /// ID 更新回调（临时 ID -> 正式 ID）
    public var onIdMappingCreated: ((String, String) async -> Void)?

    // MARK: - 初始化

    /// 初始化方法
    init(
        noteAPI: NoteAPI,
        localStorage: LocalStorageService,
        idMappingRegistry: IdMappingRegistry,
        operationQueue: UnifiedOperationQueue,
        eventBus: EventBus,
        responseParser: OperationResponseParser
    ) {
        self.noteAPI = noteAPI
        self.localStorage = localStorage
        self.idMappingRegistry = idMappingRegistry
        self.operationQueue = operationQueue
        self.eventBus = eventBus
        self.responseParser = responseParser
    }

    // MARK: - OperationHandler

    func handle(_ operation: NoteOperation) async throws {
        switch operation.type {
        case .noteCreate:
            try await processNoteCreate(operation)
        case .cloudUpload:
            try await processCloudUpload(operation)
        case .cloudDelete:
            try await processCloudDelete(operation)
        default:
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "NoteOperationHandler 不支持的操作类型: \(operation.type.rawValue)"]
            )
        }
    }
}

// MARK: - noteCreate

extension NoteOperationHandler {

    /// 处理离线创建笔记操作
    private func processNoteCreate(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "NoteOperationHandler 处理 noteCreate: \(operation.noteId)")

        // 1. 从本地加载笔记
        guard let note = try? localStorage.loadNote(noteId: operation.noteId) else {
            throw NSError(
                domain: "OperationProcessor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "笔记不存在: \(operation.noteId)"]
            )
        }

        // 2. 调用 API 创建笔记
        let response = try await noteAPI.createNote(
            title: note.title,
            content: note.content,
            folderId: note.folderId
        )

        // 3. 解析响应，获取云端下发的正式 ID
        guard responseParser.isResponseSuccess(response),
              let entry = responseParser.extractEntry(from: response),
              let serverNoteId = entry["id"] as? String
        else {
            let message = responseParser.extractErrorMessage(from: response, defaultMessage: "服务器响应格式不正确")
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        let tag = responseParser.extractTag(from: response, fallbackTag: entry["tag"] as? String ?? serverNoteId)

        // 获取服务器返回的 folderId
        let serverFolderId: String = if let folderIdValue = entry["folderId"] {
            if let folderIdInt = folderIdValue as? Int {
                String(folderIdInt)
            } else if let folderIdStr = folderIdValue as? String {
                folderIdStr
            } else {
                note.folderId
            }
        } else {
            note.folderId
        }

        LogService.shared.info(.sync, "NoteOperationHandler 云端创建成功: \(operation.noteId) -> \(serverNoteId)")

        // 4. 更新本地笔记
        let serverTag = tag

        // 在保存新笔记前，用已有的文件 ID 映射替换 content 中残留的临时 fileId
        var resolvedContent = note.content
        let fileMappings = idMappingRegistry.getAllMappings().filter { $0.entityType == "file" }
        for mapping in fileMappings {
            resolvedContent = resolvedContent.replacingOccurrences(of: mapping.localId, with: mapping.serverId)
        }
        if resolvedContent != note.content {
            LogService.shared.info(.sync, "noteCreate 保存前替换了 content 中的临时 fileId")
        }

        // 如果服务器返回的 ID 与本地不同，需要更新
        if note.id != serverNoteId {
            let updatedNote = Note(
                id: serverNoteId,
                title: note.title,
                content: resolvedContent,
                folderId: serverFolderId,
                isStarred: note.isStarred,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                tags: note.tags,
                serverTag: serverTag,
                settingJson: note.settingJson,
                extraInfoJson: note.extraInfoJson
            )

            // 保存新笔记
            await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))

            // 删除旧笔记（临时 ID）
            await eventBus.publish(NoteEvent.deleted(noteId: note.id, tag: nil))

            // 5. 更新操作队列中的 noteId
            try operationQueue.updateNoteIdInPendingOperations(
                oldNoteId: note.id,
                newNoteId: serverNoteId
            )

            // 6. 注册 ID 映射
            try idMappingRegistry.registerMapping(localId: note.id, serverId: serverNoteId, entityType: "note")

            // 7. 触发 ID 更新回调
            await onIdMappingCreated?(note.id, serverNoteId)

            // 8. 发送 ID 变更事件
            await eventBus.publish(NoteEvent.saved(updatedNote))

            // 9. 发布 ID 迁移事件
            await eventBus.publish(NoteEvent.idMigrated(oldId: note.id, newId: serverNoteId, note: updatedNote))

            LogService.shared.info(.sync, "NoteOperationHandler ID 更新完成: \(note.id) -> \(serverNoteId)")
        } else {
            var updatedNote = note
            updatedNote.content = resolvedContent
            updatedNote.serverTag = serverTag
            updatedNote.folderId = serverFolderId
            await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
        }
    }
}

// MARK: - cloudUpload

extension NoteOperationHandler {

    /// 处理云端上传操作
    private func processCloudUpload(_ operation: NoteOperation) async throws {
        let resolvedNoteId = idMappingRegistry.resolveId(operation.noteId)

        guard let note = try? localStorage.loadNote(noteId: resolvedNoteId) else {
            throw NSError(
                domain: "OperationProcessor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "笔记不存在: \(resolvedNoteId)"]
            )
        }

        let existingTag = note.serverTag ?? note.id

        let response = try await noteAPI.updateNote(
            noteId: note.id,
            title: note.title,
            content: note.content,
            folderId: note.folderId,
            existingTag: existingTag
        )

        guard responseParser.isResponseSuccess(response) else {
            let message = responseParser.extractErrorMessage(from: response, defaultMessage: "更新笔记失败")
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        let isConflict: Bool = if let data = response["data"] as? [String: Any],
                                  let conflict = data["conflict"] as? Bool
        {
            conflict
        } else {
            false
        }

        let newTag: String = if let data = response["data"] as? [String: Any],
                                let tag = data["tag"] as? String
        {
            tag
        } else {
            existingTag
        }

        if isConflict {
            LogService.shared.warning(.sync, "云端上传冲突，使用服务器最新 tag 重试: \(operation.noteId.prefix(8))...")

            await propagateServerTag(newTag, forNoteId: note.id)

            let retryNote = (try? localStorage.loadNote(noteId: note.id)) ?? note

            let retryResponse = try await noteAPI.updateNote(
                noteId: retryNote.id,
                title: retryNote.title,
                content: retryNote.content,
                folderId: retryNote.folderId,
                existingTag: newTag
            )

            guard responseParser.isResponseSuccess(retryResponse) else {
                let message = responseParser.extractErrorMessage(from: retryResponse, defaultMessage: "重试上传失败")
                throw NSError(
                    domain: "OperationProcessor",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            let retryConflict: Bool = if let data = retryResponse["data"] as? [String: Any],
                                         let conflict = data["conflict"] as? Bool
            {
                conflict
            } else {
                false
            }

            let retryTag: String = if let data = retryResponse["data"] as? [String: Any],
                                      let tag = data["tag"] as? String
            {
                tag
            } else {
                newTag
            }

            if retryConflict {
                await propagateServerTag(retryTag, forNoteId: note.id)
                LogService.shared.error(.sync, "云端上传冲突重试后仍然冲突: \(operation.noteId.prefix(8))...")
                throw NSError(
                    domain: "OperationProcessor",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "云端上传冲突重试后仍然冲突"]
                )
            }

            await propagateServerTag(retryTag, forNoteId: note.id)

            LogService.shared.info(.sync, "云端上传冲突重试成功: \(operation.noteId.prefix(8))...")
            return
        }

        await propagateServerTag(newTag, forNoteId: note.id)

        LogService.shared.info(.sync, "云端上传成功: \(operation.noteId.prefix(8))...")
    }

    /// 将服务器返回的新 tag 传播到内存
    private func propagateServerTag(_ newTag: String, forNoteId noteId: String) async {
        await eventBus.publish(SyncEvent.tagUpdated(noteId: noteId, newTag: newTag))
    }
}

// MARK: - cloudDelete

extension NoteOperationHandler {

    /// 处理云端删除操作
    private func processCloudDelete(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "NoteOperationHandler 处理 cloudDelete: \(operation.noteId)")

        let deleteData: CloudDeleteData
        do {
            deleteData = try CloudDeleteData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的删除操作数据"]
            )
        }

        _ = try await noteAPI.deleteNote(noteId: operation.noteId, tag: deleteData.tag, purge: false)

        LogService.shared.info(.sync, "NoteOperationHandler 删除成功: \(operation.noteId)")
    }
}
