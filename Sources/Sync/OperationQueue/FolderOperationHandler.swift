import Foundation

// MARK: - 文件夹操作处理器

/// 文件夹操作处理器
///
/// 负责处理文件夹相关的操作：folderCreate、folderRename、folderDelete。
/// 从 OperationProcessor 平移的文件夹操作逻辑，作为独立 actor 运行。
actor FolderOperationHandler: OperationHandler {

    // MARK: - 依赖

    private let folderAPI: FolderAPI
    private let databaseService: DatabaseService
    private let eventBus: EventBus
    private let responseParser: OperationResponseParser

    // MARK: - 初始化

    /// 初始化方法
    init(
        folderAPI: FolderAPI,
        databaseService: DatabaseService,
        eventBus: EventBus,
        responseParser: OperationResponseParser
    ) {
        self.folderAPI = folderAPI
        self.databaseService = databaseService
        self.eventBus = eventBus
        self.responseParser = responseParser
    }

    // MARK: - OperationHandler

    func handle(_ operation: NoteOperation) async throws {
        switch operation.type {
        case .folderCreate:
            try await processFolderCreate(operation)
        case .folderRename:
            try await processFolderRename(operation)
        case .folderDelete:
            try await processFolderDelete(operation)
        default:
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "FolderOperationHandler 不支持的操作类型: \(operation.type.rawValue)"]
            )
        }
    }
}

// MARK: - folderCreate

extension FolderOperationHandler {

    /// 处理创建文件夹操作
    private func processFolderCreate(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "FolderOperationHandler 处理 folderCreate: \(operation.noteId)")

        let createData: FolderCreateData
        do {
            createData = try FolderCreateData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }

        let folderName = createData.name

        // 调用 API 创建文件夹
        let response = try await folderAPI.createFolder(name: folderName)

        guard responseParser.isResponseSuccess(response),
              let entry = responseParser.extractEntry(from: response)
        else {
            let message = responseParser.extractErrorMessage(from: response, defaultMessage: "创建文件夹失败")
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        // 处理服务器返回的文件夹 ID（支持 String 和 Int 类型）
        var serverFolderId: String?
        if let idString = entry["id"] as? String {
            serverFolderId = idString
        } else if let idInt = entry["id"] as? Int {
            serverFolderId = String(idInt)
        }

        guard let folderId = serverFolderId,
              let subject = entry["subject"] as? String
        else {
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "服务器返回无效的文件夹信息"]
            )
        }

        // 构建 rawDataJson
        let tag = responseParser.extractTag(from: response, fallbackTag: entry["tag"] as? String ?? folderId)
        var folderRawData: [String: Any] = [:]
        for (key, value) in entry {
            folderRawData[key] = value
        }
        folderRawData["tag"] = tag

        let folderRawDataJson: String? = if let jsonData = try? JSONSerialization.data(withJSONObject: folderRawData, options: []) {
            String(data: jsonData, encoding: .utf8)
        } else {
            nil
        }

        let folder = Folder(
            id: folderId,
            name: subject,
            count: 0,
            isSystem: false,
            isPinned: false,
            createdAt: Date(),
            rawDataJson: folderRawDataJson
        )

        await eventBus.publish(FolderEvent.folderSaved(folder))

        // 如果服务器返回的 ID 与本地不同，发布 ID 迁移事件
        if operation.noteId != folderId {
            await eventBus.publish(FolderEvent.folderIdMigrated(oldId: operation.noteId, newId: folderId))
        }

        LogService.shared.info(.sync, "FolderOperationHandler 创建文件夹成功: \(operation.noteId) -> \(folderId)")
    }
}

// MARK: - folderRename

extension FolderOperationHandler {

    /// 处理重命名文件夹操作
    private func processFolderRename(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "FolderOperationHandler 处理 folderRename: \(operation.noteId)")

        let renameData: FolderRenameData
        do {
            renameData = try FolderRenameData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }

        let newName = renameData.name
        let existingTag = renameData.tag

        // 调用 API 重命名文件夹
        let response = try await folderAPI.renameFolder(
            folderId: operation.noteId,
            newName: newName,
            existingTag: existingTag,
            originalCreateDate: nil
        )

        guard responseParser.isResponseSuccess(response) else {
            let message = responseParser.extractErrorMessage(from: response, defaultMessage: "重命名文件夹失败")
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        // 更新本地文件夹
        if let entry = responseParser.extractEntry(from: response) {
            let folders = try? databaseService.loadFolders()
            if let folder = folders?.first(where: { $0.id == operation.noteId }) {
                var updatedRawData = folder.rawDataDict ?? [:]
                for (key, value) in entry {
                    updatedRawData[key] = value
                }
                updatedRawData["tag"] = responseParser.extractTag(from: response, fallbackTag: existingTag)
                updatedRawData["subject"] = newName

                let updatedRawDataJson: String? = if let jsonData = try? JSONSerialization.data(withJSONObject: updatedRawData, options: []) {
                    String(data: jsonData, encoding: .utf8)
                } else {
                    folder.rawDataJson
                }

                let updatedFolder = Folder(
                    id: folder.id,
                    name: newName,
                    count: folder.count,
                    isSystem: folder.isSystem,
                    isPinned: folder.isPinned,
                    createdAt: folder.createdAt,
                    rawDataJson: updatedRawDataJson
                )

                await eventBus.publish(FolderEvent.folderSaved(updatedFolder))
            }
        }

        LogService.shared.info(.sync, "FolderOperationHandler 重命名文件夹成功: \(operation.noteId)")
    }
}

// MARK: - folderDelete

extension FolderOperationHandler {

    /// 处理删除文件夹操作
    private func processFolderDelete(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "FolderOperationHandler 处理 folderDelete: \(operation.noteId)")

        let deleteData: FolderDeleteData
        do {
            deleteData = try FolderDeleteData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }

        // 调用 API 删除文件夹
        _ = try await folderAPI.deleteFolder(folderId: operation.noteId, tag: deleteData.tag, purge: false)

        LogService.shared.info(.sync, "FolderOperationHandler 删除文件夹成功: \(operation.noteId)")
    }
}
