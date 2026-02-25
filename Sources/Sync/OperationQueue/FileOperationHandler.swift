import Foundation

// MARK: - 文件操作处理器

/// 文件操作处理器
///
/// 负责处理文件相关的操作：imageUpload、audioUpload。
/// 从 OperationProcessor 平移的文件操作逻辑，作为独立 actor 运行。
actor FileOperationHandler: OperationHandler {

    // MARK: - 依赖

    private let fileAPI: FileAPI
    private let localStorage: LocalStorageService
    private let idMappingRegistry: IdMappingRegistry
    private let operationQueue: UnifiedOperationQueue
    private let eventBus: EventBus
    private let databaseService: DatabaseService
    private let responseParser: OperationResponseParser

    // MARK: - 初始化

    /// 初始化方法
    init(
        fileAPI: FileAPI,
        localStorage: LocalStorageService,
        idMappingRegistry: IdMappingRegistry,
        operationQueue: UnifiedOperationQueue,
        eventBus: EventBus,
        databaseService: DatabaseService,
        responseParser: OperationResponseParser
    ) {
        self.fileAPI = fileAPI
        self.localStorage = localStorage
        self.idMappingRegistry = idMappingRegistry
        self.operationQueue = operationQueue
        self.eventBus = eventBus
        self.databaseService = databaseService
        self.responseParser = responseParser
    }

    // MARK: - OperationHandler

    func handle(_ operation: NoteOperation) async throws {
        switch operation.type {
        case .imageUpload:
            try await processImageUpload(operation)
        case .audioUpload:
            try await processAudioUpload(operation)
        default:
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "FileOperationHandler 不支持的操作类型: \(operation.type.rawValue)"]
            )
        }
    }
}

// MARK: - imageUpload

extension FileOperationHandler {

    /// 处理图片上传操作
    private func processImageUpload(_ operation: NoteOperation) async throws {
        // noteCreate 成功后 pendingOperations 快照中的 noteId 可能仍是临时 ID
        let resolvedNoteId = idMappingRegistry.resolveId(operation.noteId)
        LogService.shared.debug(.sync, "FileOperationHandler 处理 imageUpload: \(resolvedNoteId)")

        let uploadData: FileUploadOperationData
        do {
            uploadData = try FileUploadOperationData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的图片上传操作数据"]
            )
        }

        // data JSON 内部的 noteId 也可能是临时 ID
        let resolvedUploadNoteId = idMappingRegistry.resolveId(uploadData.noteId)

        let ext = String(uploadData.mimeType.dropFirst("image/".count))
        guard let imageData = localStorage.loadPendingUpload(fileId: uploadData.temporaryFileId, extension: ext) else {
            // 本地文件丢失，无法重试
            LogService.shared.error(.sync, "图片本地文件丢失: \(uploadData.temporaryFileId)")
            try operationQueue.markFailed(operation.id, error: NSError(
                domain: "OperationProcessor", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "本地文件丢失"]
            ), errorType: .notFound)
            return
        }

        // 调用 API 上传
        let result = try await fileAPI.uploadImage(
            imageData: imageData,
            fileName: uploadData.fileName,
            mimeType: uploadData.mimeType
        )

        guard let serverFileId = result["fileId"] as? String else {
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "上传图片响应无效"]
            )
        }

        // 注册 ID 映射
        try idMappingRegistry.registerMapping(localId: uploadData.temporaryFileId, serverId: serverFileId, entityType: "file")

        // 使用解析后的 noteId 更新笔记内容中的 fileId 引用
        try await idMappingRegistry.updateAllFileReferences(
            localId: uploadData.temporaryFileId,
            serverId: serverFileId,
            noteId: resolvedUploadNoteId
        )

        // 移动 pending 文件到正式缓存（用正式 ID）
        let fileType = String(uploadData.mimeType.dropFirst("image/".count))
        try? localStorage.movePendingUploadToCache(fileId: uploadData.temporaryFileId, extension: fileType, newFileId: serverFileId)

        // 清理图片缓存中临时 ID 的旧文件（saveImage 在入队前用临时 ID 保存了一份）
        let oldCacheURL = localStorage.imagesDirectory.appendingPathComponent("\(uploadData.temporaryFileId).\(fileType)")
        try? FileManager.default.removeItem(at: oldCacheURL)

        // 清理 pending 临时文件
        try? localStorage.deletePendingUpload(fileId: uploadData.temporaryFileId, extension: ext)

        LogService.shared.info(.sync, "图片上传成功: \(uploadData.temporaryFileId.prefix(20))... -> \(serverFileId)")
    }
}

// MARK: - audioUpload

extension FileOperationHandler {

    /// 处理音频上传操作
    private func processAudioUpload(_ operation: NoteOperation) async throws {
        // noteCreate 成功后 pendingOperations 快照中的 noteId 可能仍是临时 ID
        let resolvedNoteId = idMappingRegistry.resolveId(operation.noteId)
        LogService.shared.debug(.sync, "FileOperationHandler 处理 audioUpload: \(resolvedNoteId)")

        let uploadData: FileUploadOperationData
        do {
            uploadData = try FileUploadOperationData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的音频上传操作数据"]
            )
        }

        // data JSON 内部的 noteId 也可能是临时 ID
        let resolvedUploadNoteId = idMappingRegistry.resolveId(uploadData.noteId)

        // 读取本地文件
        guard let audioData = localStorage.loadPendingUpload(fileId: uploadData.temporaryFileId, extension: "mp3") else {
            LogService.shared.error(.sync, "音频本地文件丢失: \(uploadData.temporaryFileId)")
            try operationQueue.markFailed(operation.id, error: NSError(
                domain: "OperationProcessor", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "本地文件丢失"]
            ), errorType: .notFound)
            return
        }

        // 调用 API 上传
        let result = try await fileAPI.uploadAudio(
            audioData: audioData,
            fileName: uploadData.fileName,
            mimeType: uploadData.mimeType
        )

        guard let serverFileId = result["fileId"] as? String else {
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "上传音频响应无效"]
            )
        }

        let digest = result["digest"] as? String

        // 注册 ID 映射
        try idMappingRegistry.registerMapping(localId: uploadData.temporaryFileId, serverId: serverFileId, entityType: "file")

        // 更新笔记内容中的 fileId 引用
        try await idMappingRegistry.updateAllFileReferences(
            localId: uploadData.temporaryFileId,
            serverId: serverFileId,
            noteId: resolvedUploadNoteId
        )

        // 更新笔记 settingJson 中的音频信息
        if var note = try? localStorage.loadNote(noteId: resolvedUploadNoteId) {
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

            // 替换临时 fileId 为正式 fileId
            var updated = false
            for i in 0 ..< settingData.count {
                if let existingFileId = settingData[i]["fileId"] as? String,
                   existingFileId == uploadData.temporaryFileId
                {
                    settingData[i]["fileId"] = serverFileId
                    if let digest {
                        settingData[i]["digest"] = digest + ".mp3"
                    }
                    updated = true
                }
            }

            // 如果没有找到临时 ID 的条目，添加新条目
            if !updated {
                let audioInfo: [String: Any] = [
                    "fileId": serverFileId,
                    "mimeType": uploadData.mimeType,
                    "digest": (digest ?? serverFileId) + ".mp3",
                ]
                settingData.append(audioInfo)
            }

            setting["data"] = settingData

            if let settingJsonData = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
               let settingString = String(data: settingJsonData, encoding: .utf8)
            {
                note.settingJson = settingString
                try? localStorage.saveNote(note)
            }

            // 入队 cloudUpload 触发笔记重新保存
            _ = try? operationQueue.enqueueCloudUpload(
                noteId: note.id,
                title: note.title,
                content: note.content,
                folderId: note.folderId
            )
        }

        // 移动文件到正式缓存
        try? localStorage.movePendingUploadToCache(fileId: uploadData.temporaryFileId, extension: "mp3", newFileId: serverFileId)

        // 清理临时文件
        try? localStorage.deletePendingUpload(fileId: uploadData.temporaryFileId, extension: "mp3")

        LogService.shared.info(.sync, "音频上传成功: \(uploadData.temporaryFileId.prefix(20))... -> \(serverFileId)")
    }
}
