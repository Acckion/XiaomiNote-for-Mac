import Foundation

final class LocalStorageService: @unchecked Sendable {
    static let shared = LocalStorageService()

    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let database = DatabaseService.shared

    private init() {
        // 获取应用程序支持目录
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appBundleID = Bundle.main.bundleIdentifier ?? "com.mi.note.mac"
        documentsDirectory = appSupportURL.appendingPathComponent(appBundleID)

        // 创建目录（如果不存在）
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: documentsDirectory.path) {
            do {
                try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
                print("创建应用程序支持目录: \(documentsDirectory.path)")
            } catch {
                print("创建目录失败: \(error)")
            }
        }
    }

    // MARK: - 笔记存储

    /// 保存笔记到本地（使用数据库）
    func saveNote(_ note: Note) throws {
        try database.saveNote(note)
    }

    /// 从本地加载笔记
    func loadNote(noteId: String) throws -> Note? {
        try database.loadNote(noteId: noteId)
    }

    /// 删除本地笔记
    func deleteNote(noteId: String) throws {
        try database.deleteNote(noteId: noteId)
    }

    /// 获取所有本地笔记
    func getAllLocalNotes() throws -> [Note] {
        try database.getAllNotes()
    }

    /// 检查笔记是否存在本地副本
    func noteExistsLocally(noteId: String) -> Bool {
        database.noteExists(noteId: noteId)
    }

    /// 获取笔记的本地修改时间
    func getNoteLocalModificationDate(noteId: String) -> Date? {
        // 从数据库加载笔记并返回 updatedAt
        if let note = try? database.loadNote(noteId: noteId) {
            return note.updatedAt
        }
        return nil
    }

    // MARK: - 同步状态管理

    /// 保存同步状态
    func saveSyncStatus(_ status: SyncStatus) throws {
        print("[LocalStorage] 💾 开始保存同步状态:")
        print("[LocalStorage]   - lastSyncTime: \(status.lastSyncTime?.description ?? "nil")")
        print("[LocalStorage]   - syncTag: \(status.syncTag ?? "nil")")

        do {
            try database.saveSyncStatus(status)
            print("[LocalStorage] ✅ 同步状态保存成功")
        } catch {
            print("[LocalStorage] ❌ 同步状态保存失败: \(error)")
            throw error
        }
    }

    /// 加载同步状态
    func loadSyncStatus() -> SyncStatus? {
        print("[LocalStorage] 🔍 开始加载同步状态")
        do {
            let status = try database.loadSyncStatus()
            if let status {
                print("[LocalStorage] ✅ 成功加载同步状态:")
                print("[LocalStorage]   - lastSyncTime: \(status.lastSyncTime?.description ?? "nil")")
                print("[LocalStorage]   - syncTag: \(status.syncTag ?? "nil")")
            } else {
                print("[LocalStorage] ⚠️ 数据库返回nil同步状态（表可能为空）")
            }
            return status
        } catch {
            print("[LocalStorage] ❌ 加载同步状态失败: \(error)")
            return nil
        }
    }

    /// 清除同步状态
    func clearSyncStatus() throws {
        try database.clearSyncStatus()
    }

    // MARK: - 文件夹管理

    /// 保存文件夹列表到本地
    func saveFolders(_ folders: [Folder]) throws {
        try database.saveFolders(folders)
        print("保存文件夹列表到本地: \(folders.count) 个文件夹")
    }

    /// 从本地加载文件夹列表
    func loadFolders() throws -> [Folder] {
        let folders = try database.loadFolders()
        print("从本地加载文件夹列表: \(folders.count) 个文件夹")
        return folders
    }

    /// 创建文件夹（文件系统目录）
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
            print("获取文件夹列表失败: \(error)")
        }

        return folders
    }

    // MARK: - 图片存储

    /// 保存图片
    func saveImage(_ imageData: Data, imageId: String, folderId: String) throws -> URL {
        // 创建图片目录
        let imagesDirectory = documentsDirectory.appendingPathComponent("images")
        if !fileManager.fileExists(atPath: imagesDirectory.path) {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        // 创建文件夹子目录
        let folderDirectory = imagesDirectory.appendingPathComponent(folderId)
        if !fileManager.fileExists(atPath: folderDirectory.path) {
            try fileManager.createDirectory(at: folderDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        // 保存图片文件
        let fileURL = folderDirectory.appendingPathComponent("\(imageId).jpg")
        try imageData.write(to: fileURL)

        return fileURL
    }

    /// 重命名文件夹的图片目录（当文件夹ID更新时）
    ///
    /// - Parameters:
    ///   - oldFolderId: 旧的文件夹ID
    ///   - newFolderId: 新的文件夹ID
    /// - Throws: 文件系统操作失败
    func renameFolderImageDirectory(oldFolderId: String, newFolderId: String) throws {
        let imagesDirectory = documentsDirectory.appendingPathComponent("images")
        let oldFolderDirectory = imagesDirectory.appendingPathComponent(oldFolderId)
        let newFolderDirectory = imagesDirectory.appendingPathComponent(newFolderId)

        // 如果旧目录存在且新目录不存在，则重命名
        if fileManager.fileExists(atPath: oldFolderDirectory.path),
           !fileManager.fileExists(atPath: newFolderDirectory.path)
        {
            try fileManager.moveItem(at: oldFolderDirectory, to: newFolderDirectory)
            print("[LocalStorage] 重命名图片目录: \(oldFolderId) -> \(newFolderId)")
        } else if fileManager.fileExists(atPath: oldFolderDirectory.path),
                  fileManager.fileExists(atPath: newFolderDirectory.path)
        {
            // 如果两个目录都存在，合并内容
            let oldContents = try? fileManager.contentsOfDirectory(at: oldFolderDirectory, includingPropertiesForKeys: nil)
            if let contents = oldContents {
                for item in contents {
                    let destination = newFolderDirectory.appendingPathComponent(item.lastPathComponent)
                    if !fileManager.fileExists(atPath: destination.path) {
                        try fileManager.moveItem(at: item, to: destination)
                    } else {
                        // 如果目标文件已存在，删除源文件
                        try? fileManager.removeItem(at: item)
                    }
                }
                // 删除旧目录
                try? fileManager.removeItem(at: oldFolderDirectory)
                print("[LocalStorage] 合并图片目录: \(oldFolderId) -> \(newFolderId)")
            }
        }
    }

    /// 删除文件夹的图片目录（当文件夹被删除时）
    ///
    /// - Parameter folderId: 要删除的文件夹ID
    /// - Throws: 文件系统操作失败
    func deleteFolderImageDirectory(folderId: String) throws {
        let imagesDirectory = documentsDirectory.appendingPathComponent("images")
        let folderDirectory = imagesDirectory.appendingPathComponent(folderId)

        // 如果目录存在，删除它及其所有内容
        if fileManager.fileExists(atPath: folderDirectory.path) {
            try fileManager.removeItem(at: folderDirectory)
            print("[LocalStorage] 删除图片目录: \(folderId)")
        }
    }

    /// 获取图片
    func getImage(imageId: String, folderId: String) -> Data? {
        let fileURL = documentsDirectory
            .appendingPathComponent("images")
            .appendingPathComponent(folderId)
            .appendingPathComponent("\(imageId).jpg")

        return try? Data(contentsOf: fileURL)
    }

    /// 检查图片是否存在
    func imageExists(imageId: String, folderId: String) -> Bool {
        let fileURL = documentsDirectory
            .appendingPathComponent("images")
            .appendingPathComponent(folderId)
            .appendingPathComponent("\(imageId).jpg")

        return fileManager.fileExists(atPath: fileURL.path)
    }

    // MARK: - 图片文件管理

    /// 获取图片存储目录
    private var imagesDirectory: URL {
        documentsDirectory.appendingPathComponent("images")
    }

    /// 确保图片目录存在
    private func ensureImagesDirectory() throws {
        let imgDir = imagesDirectory
        if !fileManager.fileExists(atPath: imgDir.path) {
            try fileManager.createDirectory(at: imgDir, withIntermediateDirectories: true, attributes: nil)
            print("创建图片目录: \(imgDir.path)")
        }
    }

    /// 保存图片文件
    /// - Parameters:
    ///   - imageData: 图片数据
    ///   - fileId: 文件ID（用于生成文件名）
    ///   - fileType: 文件类型（如 "jpeg", "png"）
    func saveImage(imageData: Data, fileId: String, fileType: String) throws {
        try ensureImagesDirectory()

        let fileName = "\(fileId).\(fileType)"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)

        try imageData.write(to: fileURL)
        print("保存图片到本地: \(fileURL.path)")
    }

    /// 检查图片文件是否存在且有效
    /// - Parameters:
    ///   - fileId: 文件ID
    ///   - fileType: 文件类型
    /// - Returns: 文件是否存在且有效(大小>0)
    func imageExists(fileId: String, fileType: String) -> Bool {
        let fileName = "\(fileId).\(fileType)"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)

        // 检查文件是否存在
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("[LocalStorage] 图片文件不存在: \(fileName)")
            return false
        }

        // 检查文件大小
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                if fileSize > 0 {
                    print("[LocalStorage] 图片文件有效: \(fileName), 大小: \(fileSize) 字节")
                    return true
                } else {
                    print("[LocalStorage] 图片文件大小为0: \(fileName)")
                    return false
                }
            }
        } catch {
            print("[LocalStorage] 检查图片文件失败: \(fileName), 错误: \(error)")
        }

        return false
    }

    /// 获取图片文件URL
    func getImageURL(fileId: String, fileType: String) -> URL? {
        let fileName = "\(fileId).\(fileType)"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        let exists = fileManager.fileExists(atPath: fileURL.path)
        print("[LocalStorage] 🖼️ getImageURL: \(fileURL.path) - \(exists ? "存在" : "不存在")")
        return exists ? fileURL : nil
    }

    /// 加载图片数据
    func loadImage(fileId: String, fileType: String) -> Data? {
        guard let fileURL = getImageURL(fileId: fileId, fileType: fileType) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            print("[LocalStorage] ✅ 加载图片成功: \(fileId).\(fileType), 大小: \(data.count) 字节")
            return data
        } catch {
            print("[LocalStorage] ❌ 加载图片失败: \(fileId).\(fileType), 错误: \(error)")
            return nil
        }
    }

    // MARK: - 统一图片加载（仅使用 images/{userId}.{fileId}.{format} 格式）

    /// 加载图片 - 仅使用 images/{userId}.{fileId}.{format} 格式
    /// - Parameters:
    ///   - fullFileId: 完整的 fileId，格式为 `{userId}.{fileId}`
    ///   - fileType: 文件类型（如 "jpg", "png"）
    /// - Returns: 图片数据，如果找不到则返回 nil
    func loadImageWithFullFormat(fullFileId: String, fileType: String) -> Data? {
        print("[LocalStorage] 🖼️ 加载图片（统一格式）:")
        print("[LocalStorage]   - fullFileId: \(fullFileId)")
        print("[LocalStorage]   - fileType: \(fileType)")

        // 直接使用完整的 fileId 作为文件名：images/{userId}.{fileId}.{extension}
        if let data = loadImage(fileId: fullFileId, fileType: fileType) {
            print("[LocalStorage] ✅ 加载成功: images/\(fullFileId).\(fileType)")
            return data
        }

        print("[LocalStorage] ❌ 加载失败: images/\(fullFileId).\(fileType)")
        return nil
    }

    /// 加载图片 - 自动尝试所有支持的图片格式
    /// - Parameter fullFileId: 完整的 fileId，格式为 `{userId}.{fileId}`
    /// - Returns: (图片数据, 文件类型) 元组，如果找不到则返回 nil
    func loadImageWithFullFormatAllFormats(fullFileId: String) -> (data: Data, fileType: String)? {
        let imageFormats = ["jpg", "jpeg", "png", "gif"]

        for format in imageFormats {
            if let data = loadImageWithFullFormat(fullFileId: fullFileId, fileType: format) {
                return (data, format)
            }
        }

        return nil
    }

    /// 验证图片文件是否有效
    /// - Parameters:
    ///   - fileId: 文件ID
    ///   - fileType: 文件类型
    /// - Returns: 文件是否有效(存在且大小>0)
    func validateImage(fileId: String, fileType: String) -> Bool {
        // 使用增强后的 imageExists 方法
        imageExists(fileId: fileId, fileType: fileType)
    }

    /// 清理无效的图片文件
    func cleanupInvalidImages() {
        do {
            try ensureImagesDirectory()
            let fileURLs = try fileManager.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: [.fileSizeKey])

            var cleanedCount = 0
            for fileURL in fileURLs {
                // 检查文件大小
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    if let fileSize = attributes[.size] as? Int64, fileSize == 0 {
                        // 删除大小为0的文件
                        try fileManager.removeItem(at: fileURL)
                        cleanedCount += 1
                        print("[LocalStorage] 清理无效图片: \(fileURL.lastPathComponent)")
                    }
                } catch {
                    // 如果无法获取属性，尝试删除文件
                    try? fileManager.removeItem(at: fileURL)
                    cleanedCount += 1
                    print("[LocalStorage] 清理无法访问的图片: \(fileURL.lastPathComponent)")
                }
            }

            if cleanedCount > 0 {
                print("[LocalStorage] 清理完成，删除了 \(cleanedCount) 个无效图片文件")
            }
        } catch {
            print("[LocalStorage] 清理图片时出错: \(error)")
        }
    }

    /// 获取图片文件信息
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
            print("[LocalStorage] 获取图片信息失败: \(fileId).\(fileType), 错误: \(error)")
            return nil
        }
    }

    // MARK: - 文件夹排序信息

    /// 保存文件夹排序信息
    ///
    /// - Parameters:
    ///   - eTag: 排序信息的ETag（用于增量同步）
    ///   - orders: 文件夹ID的顺序数组
    /// - Throws: 数据库操作失败
    func saveFolderSortInfo(eTag: String, orders: [String]) throws {
        try database.saveFolderSortInfo(eTag: eTag, orders: orders)
        print("[LocalStorage] 保存文件夹排序信息: eTag=\(eTag), orders数量=\(orders.count)")
    }

    /// 加载文件夹排序信息
    ///
    /// - Returns: 包含eTag和orders的元组，如果不存在则返回nil
    /// - Throws: 数据库操作失败
    func loadFolderSortInfo() throws -> (eTag: String, orders: [String])? {
        try database.loadFolderSortInfo()
    }

    /// 清除文件夹排序信息
    ///
    /// - Throws: 数据库操作失败
    func clearFolderSortInfo() throws {
        try database.clearFolderSortInfo()
        print("[LocalStorage] 清除文件夹排序信息")
    }

    // MARK: - 应用重置

    /// 清除所有本地数据(用于应用重置)
    /// - Throws: 文件系统或数据库操作失败
    func clearAllData() throws {
        print("[LocalStorage] 开始清除所有本地数据...")

        // 1. 清除所有笔记
        let notes = try getAllLocalNotes()
        for note in notes {
            try deleteNote(noteId: note.id)
        }
        print("[LocalStorage] 已清除 \(notes.count) 个笔记")

        // 2. 清除所有文件夹
        let folders = try loadFolders()
        for folder in folders {
            if !folder.isSystem, folder.id != "0", folder.id != "starred" {
                try DatabaseService.shared.deleteFolder(folderId: folder.id)
            }
        }
        print("[LocalStorage] 已清除 \(folders.count) 个文件夹")

        // 3. 清除同步状态
        try clearSyncStatus()
        print("[LocalStorage] 已清除同步状态")

        // 4. 清除文件夹排序信息
        try clearFolderSortInfo()
        print("[LocalStorage] 已清除文件夹排序信息")

        // 5. 清除所有图片文件
        let imagesDir = documentsDirectory.appendingPathComponent("images")
        if fileManager.fileExists(atPath: imagesDir.path) {
            try fileManager.removeItem(at: imagesDir)
            print("[LocalStorage] 已清除所有图片文件")
        }

        // 6. 清除音频缓存
        AudioCacheService.shared.clearCache()
        print("[LocalStorage] 已清除音频缓存")

        print("[LocalStorage] ✅ 所有本地数据已清除")
    }
}

// MARK: - 同步状态模型

struct SyncStatus: Codable {
    var lastSyncTime: Date?
    var syncTag: String? // 笔记同步的syncTag

    init(lastSyncTime: Date? = nil, syncTag: String? = nil) {
        self.lastSyncTime = lastSyncTime
        self.syncTag = syncTag
    }
}
