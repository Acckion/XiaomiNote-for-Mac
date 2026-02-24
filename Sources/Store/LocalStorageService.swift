import Foundation

struct LocalStorageService: Sendable {
    static let shared = LocalStorageService()

    // FileManager.default 是线程安全的全局单例
    private nonisolated(unsafe) let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let database: DatabaseService

    private init() {
        self.database = DatabaseService.shared
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appBundleID = Bundle.main.bundleIdentifier ?? "com.mi.note.mac"
        self.documentsDirectory = appSupportURL.appendingPathComponent(appBundleID)
        createDirectoryIfNeeded()
    }

    /// SyncModule 使用的构造器
    init(database: DatabaseService) {
        self.database = database
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appBundleID = Bundle.main.bundleIdentifier ?? "com.mi.note.mac"
        self.documentsDirectory = appSupportURL.appendingPathComponent(appBundleID)
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: documentsDirectory.path) {
            do {
                try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
                LogService.shared.info(.storage, "创建应用程序支持目录: \(documentsDirectory.path)")
            } catch {
                LogService.shared.error(.storage, "创建目录失败: \(error)")
            }
        }
    }

    // MARK: - 笔记存储

    func saveNote(_ note: Note) throws {
        try database.saveNote(note)
    }

    func loadNote(noteId: String) throws -> Note? {
        try database.loadNote(noteId: noteId)
    }

    func deleteNote(noteId: String) throws {
        try database.deleteNote(noteId: noteId)
    }

    func getAllLocalNotes() throws -> [Note] {
        try database.getAllNotes()
    }

    func noteExistsLocally(noteId: String) -> Bool {
        database.noteExists(noteId: noteId)
    }

    func getNoteLocalModificationDate(noteId: String) -> Date? {
        if let note = try? database.loadNote(noteId: noteId) {
            return note.updatedAt
        }
        return nil
    }

    // MARK: - 同步状态管理

    func saveSyncStatus(_ status: SyncStatus) throws {
        do {
            try database.saveSyncStatus(status)
        } catch {
            LogService.shared.error(.storage, "同步状态保存失败: \(error)")
            throw error
        }
    }

    func loadSyncStatus() -> SyncStatus? {
        do {
            return try database.loadSyncStatus()
        } catch {
            LogService.shared.error(.storage, "加载同步状态失败: \(error)")
            return nil
        }
    }

    func clearSyncStatus() throws {
        try database.clearSyncStatus()
    }

    // MARK: - 文件夹管理

    func saveFolders(_ folders: [Folder]) throws {
        try database.saveFolders(folders)
    }

    func loadFolders() throws -> [Folder] {
        try database.loadFolders()
    }

    func createFolder(_ folderName: String) throws -> URL {
        let folderURL = documentsDirectory.appendingPathComponent(folderName)
        if !fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        }
        return folderURL
    }

    func getAllFolders() throws -> [String] {
        var folders: [String] = []
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: [.isDirectoryKey])
            for fileURL in fileURLs {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                   isDirectory.boolValue,
                   fileURL.lastPathComponent != "sync_status.json"
                {
                    folders.append(fileURL.lastPathComponent)
                }
            }
        } catch {
            LogService.shared.error(.storage, "获取文件夹列表失败: \(error)")
        }
        return folders
    }

    // MARK: - 图片存储

    func saveImage(_ imageData: Data, imageId: String, folderId: String) throws -> URL {
        let imagesDirectory = documentsDirectory.appendingPathComponent("images")
        if !fileManager.fileExists(atPath: imagesDirectory.path) {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        let folderDirectory = imagesDirectory.appendingPathComponent(folderId)
        if !fileManager.fileExists(atPath: folderDirectory.path) {
            try fileManager.createDirectory(at: folderDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        let fileURL = folderDirectory.appendingPathComponent("\(imageId).jpg")
        try imageData.write(to: fileURL)
        return fileURL
    }

    func renameFolderImageDirectory(oldFolderId: String, newFolderId: String) throws {
        let imagesDirectory = documentsDirectory.appendingPathComponent("images")
        let oldFolderDirectory = imagesDirectory.appendingPathComponent(oldFolderId)
        let newFolderDirectory = imagesDirectory.appendingPathComponent(newFolderId)

        if fileManager.fileExists(atPath: oldFolderDirectory.path),
           !fileManager.fileExists(atPath: newFolderDirectory.path)
        {
            try fileManager.moveItem(at: oldFolderDirectory, to: newFolderDirectory)
        } else if fileManager.fileExists(atPath: oldFolderDirectory.path),
                  fileManager.fileExists(atPath: newFolderDirectory.path)
        {
            let oldContents = try? fileManager.contentsOfDirectory(at: oldFolderDirectory, includingPropertiesForKeys: nil)
            if let contents = oldContents {
                for item in contents {
                    let destination = newFolderDirectory.appendingPathComponent(item.lastPathComponent)
                    if !fileManager.fileExists(atPath: destination.path) {
                        try fileManager.moveItem(at: item, to: destination)
                    } else {
                        try? fileManager.removeItem(at: item)
                    }
                }
                try? fileManager.removeItem(at: oldFolderDirectory)
            }
        }
    }

    func deleteFolderImageDirectory(folderId: String) throws {
        let imagesDirectory = documentsDirectory.appendingPathComponent("images")
        let folderDirectory = imagesDirectory.appendingPathComponent(folderId)
        if fileManager.fileExists(atPath: folderDirectory.path) {
            try fileManager.removeItem(at: folderDirectory)
        }
    }

    func getImage(imageId: String, folderId: String) -> Data? {
        let fileURL = documentsDirectory
            .appendingPathComponent("images")
            .appendingPathComponent(folderId)
            .appendingPathComponent("\(imageId).jpg")
        return try? Data(contentsOf: fileURL)
    }

    func imageExists(imageId: String, folderId: String) -> Bool {
        let fileURL = documentsDirectory
            .appendingPathComponent("images")
            .appendingPathComponent(folderId)
            .appendingPathComponent("\(imageId).jpg")
        return fileManager.fileExists(atPath: fileURL.path)
    }

    // MARK: - 图片文件管理

    var imagesDirectory: URL {
        documentsDirectory.appendingPathComponent("images")
    }

    // MARK: - 待上传文件管理

    /// 待上传文件暂存目录
    var pendingUploadsDirectory: URL {
        documentsDirectory.appendingPathComponent("pending_uploads")
    }

    private func ensurePendingUploadsDirectory() throws {
        let dir = pendingUploadsDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            LogService.shared.debug(.storage, "创建待上传文件目录: \(dir.path)")
        }
    }

    /// 保存待上传文件
    func savePendingUpload(data: Data, fileId: String, extension ext: String) throws {
        try ensurePendingUploadsDirectory()
        let fileURL = pendingUploadsDirectory.appendingPathComponent("\(fileId).\(ext)")
        try data.write(to: fileURL)
        LogService.shared.debug(.storage, "保存待上传文件: \(fileId).\(ext)")
    }

    /// 读取待上传文件
    func loadPendingUpload(fileId: String, extension ext: String) -> Data? {
        let fileURL = pendingUploadsDirectory.appendingPathComponent("\(fileId).\(ext)")
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    /// 上传成功后移动到正式缓存目录
    func movePendingUploadToCache(fileId: String, extension ext: String, newFileId: String) throws {
        let sourceURL = pendingUploadsDirectory.appendingPathComponent("\(fileId).\(ext)")
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        try ensureImagesDirectory()
        let destURL = imagesDirectory.appendingPathComponent("\(newFileId).\(ext)")
        try fileManager.moveItem(at: sourceURL, to: destURL)
        LogService.shared.debug(.storage, "移动待上传文件到缓存: \(fileId).\(ext) -> \(newFileId).\(ext)")
    }

    /// 删除待上传文件
    func deletePendingUpload(fileId: String, extension ext: String) throws {
        let fileURL = pendingUploadsDirectory.appendingPathComponent("\(fileId).\(ext)")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
            LogService.shared.debug(.storage, "删除待上传文件: \(fileId).\(ext)")
        }
    }

    private func ensureImagesDirectory() throws {
        let imgDir = imagesDirectory
        if !fileManager.fileExists(atPath: imgDir.path) {
            try fileManager.createDirectory(at: imgDir, withIntermediateDirectories: true, attributes: nil)
        }
    }

    func saveImage(imageData: Data, fileId: String, fileType: String) throws {
        try ensureImagesDirectory()
        let fileName = "\(fileId).\(fileType)"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        try imageData.write(to: fileURL)
    }

    func imageExists(fileId: String, fileType: String) -> Bool {
        let fileName = "\(fileId).\(fileType)"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return false
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                return fileSize > 0
            }
        } catch {
            LogService.shared.error(.storage, "检查图片文件失败: \(fileName), 错误: \(error)")
        }

        return false
    }

    func getImageURL(fileId: String, fileType: String) -> URL? {
        let fileName = "\(fileId).\(fileType)"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func loadImage(fileId: String, fileType: String) -> Data? {
        guard let fileURL = getImageURL(fileId: fileId, fileType: fileType) else {
            return nil
        }

        do {
            return try Data(contentsOf: fileURL)
        } catch {
            LogService.shared.error(.storage, "加载图片失败: \(fileId).\(fileType), 错误: \(error)")
            return nil
        }
    }

    func loadImageWithFullFormat(fullFileId: String, fileType: String) -> Data? {
        loadImage(fileId: fullFileId, fileType: fileType)
    }

    func loadImageWithFullFormatAllFormats(fullFileId: String) -> (data: Data, fileType: String)? {
        let imageFormats = ["jpg", "jpeg", "png", "gif"]
        for format in imageFormats {
            if let data = loadImageWithFullFormat(fullFileId: fullFileId, fileType: format) {
                return (data, format)
            }
        }
        return nil
    }

    func validateImage(fileId: String, fileType: String) -> Bool {
        imageExists(fileId: fileId, fileType: fileType)
    }

    func cleanupInvalidImages() {
        do {
            try ensureImagesDirectory()
            let fileURLs = try fileManager.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: [.fileSizeKey])

            var cleanedCount = 0
            for fileURL in fileURLs {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    if let fileSize = attributes[.size] as? Int64, fileSize == 0 {
                        try fileManager.removeItem(at: fileURL)
                        cleanedCount += 1
                    }
                } catch {
                    try? fileManager.removeItem(at: fileURL)
                    cleanedCount += 1
                }
            }

            if cleanedCount > 0 {
                LogService.shared.info(.storage, "清理完成，删除了 \(cleanedCount) 个无效图片文件")
            }
        } catch {
            LogService.shared.error(.storage, "清理图片时出错: \(error)")
        }
    }

    func getImageInfo(fileId: String, fileType: String) -> (exists: Bool, size: Int64?, modifiedDate: Date?)? {
        guard let fileURL = getImageURL(fileId: fileId, fileType: fileType) else {
            return nil
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let exists = fileManager.fileExists(atPath: fileURL.path)
            let size = attributes[.size] as? Int64
            let modifiedDate = attributes[.modificationDate] as? Date
            return (exists: exists, size: size, modifiedDate: modifiedDate)
        } catch {
            LogService.shared.error(.storage, "获取图片信息失败: \(fileId).\(fileType), 错误: \(error)")
            return nil
        }
    }

    // MARK: - 文件夹排序信息

    func saveFolderSortInfo(eTag: String, orders: [String]) throws {
        try database.saveFolderSortInfo(eTag: eTag, orders: orders)
    }

    func loadFolderSortInfo() throws -> (eTag: String, orders: [String])? {
        try database.loadFolderSortInfo()
    }

    func clearFolderSortInfo() throws {
        try database.clearFolderSortInfo()
    }

    // MARK: - 应用重置

    func clearAllData() async throws {
        LogService.shared.info(.storage, "开始清除所有本地数据")

        let notes = try getAllLocalNotes()
        for note in notes {
            try deleteNote(noteId: note.id)
        }

        let folders = try loadFolders()
        for folder in folders {
            if !folder.isSystem, folder.id != "0", folder.id != "starred" {
                try DatabaseService.shared.deleteFolder(folderId: folder.id)
            }
        }

        try clearSyncStatus()
        try clearFolderSortInfo()

        let imagesDir = documentsDirectory.appendingPathComponent("images")
        if fileManager.fileExists(atPath: imagesDir.path) {
            try fileManager.removeItem(at: imagesDir)
        }

        await AudioCacheService.shared.clearCache()

        LogService.shared.info(.storage, "所有本地数据已清除")
    }
}

// MARK: - 同步状态模型

struct SyncStatus: Codable {
    var lastSyncTime: Date?
    var syncTag: String?

    init(lastSyncTime: Date? = nil, syncTag: String? = nil) {
        self.lastSyncTime = lastSyncTime
        self.syncTag = syncTag
    }
}
