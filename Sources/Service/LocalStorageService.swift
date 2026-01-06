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
        return try database.loadNote(noteId: noteId)
    }
    
    /// 删除本地笔记
    func deleteNote(noteId: String) throws {
        try database.deleteNote(noteId: noteId)
    }
    
    /// 获取所有本地笔记
    func getAllLocalNotes() throws -> [Note] {
        return try database.getAllNotes()
    }
    
    /// 检查笔记是否存在本地副本
    func noteExistsLocally(noteId: String) -> Bool {
        return database.noteExists(noteId: noteId)
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
        print("[LocalStorage]   - lastPageSyncTime: \(status.lastPageSyncTime?.description ?? "nil")")
        
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
            if let status = status {
                print("[LocalStorage] ✅ 成功加载同步状态:")
                print("[LocalStorage]   - lastSyncTime: \(status.lastSyncTime?.description ?? "nil")")
                print("[LocalStorage]   - syncTag: \(status.syncTag ?? "nil")")
                print("[LocalStorage]   - lastPageSyncTime: \(status.lastPageSyncTime?.description ?? "nil")")
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
                   fileURL.lastPathComponent != "sync_status.json" {
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
        if fileManager.fileExists(atPath: oldFolderDirectory.path) && 
           !fileManager.fileExists(atPath: newFolderDirectory.path) {
            try fileManager.moveItem(at: oldFolderDirectory, to: newFolderDirectory)
            print("[LocalStorage] 重命名图片目录: \(oldFolderId) -> \(newFolderId)")
        } else if fileManager.fileExists(atPath: oldFolderDirectory.path) && 
                  fileManager.fileExists(atPath: newFolderDirectory.path) {
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
    
    // MARK: - 待删除笔记管理
    
    /// 保存待删除的笔记（删除失败的笔记）
    func savePendingDeletions(_ deletions: [PendingDeletion]) throws {
        // 清空现有数据并重新保存
        let existing = try? database.getAllPendingDeletions()
        for existingDeletion in existing ?? [] {
            try? database.deletePendingDeletion(noteId: existingDeletion.noteId)
        }
        for deletion in deletions {
            try database.savePendingDeletion(deletion)
        }
        print("保存 \(deletions.count) 个待删除笔记")
    }
    
    /// 加载待删除的笔记列表
    func loadPendingDeletions() -> [PendingDeletion] {
        do {
            let deletions = try database.getAllPendingDeletions()
            print("加载了 \(deletions.count) 个待删除笔记")
            return deletions
        } catch {
            print("加载待删除笔记列表失败: \(error)")
            return []
        }
    }
    
    /// 移除待删除的笔记（删除成功后调用）
    func removePendingDeletion(noteId: String) throws {
        try database.deletePendingDeletion(noteId: noteId)
        print("移除待删除笔记: \(noteId)")
    }
    
    
    /// 添加待删除的笔记（删除失败时调用）
    func addPendingDeletion(_ deletion: PendingDeletion) throws {
        try database.savePendingDeletion(deletion)
        print("添加待删除笔记: \(deletion.noteId)")
    }
    
    // MARK: - 图片文件管理
    
    /// 获取图片存储目录
    private var imagesDirectory: URL {
        return documentsDirectory.appendingPathComponent("images")
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
    
    /// 检查图片文件是否存在
    func imageExists(fileId: String, fileType: String) -> Bool {
        let fileName = "\(fileId).\(fileType)"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    /// 获取图片文件URL
    func getImageURL(fileId: String, fileType: String) -> URL? {
        let fileName = "\(fileId).\(fileType)"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
    
    /// 加载图片数据
    func loadImage(fileId: String, fileType: String) -> Data? {
        guard let fileURL = getImageURL(fileId: fileId, fileType: fileType) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            print("[LocalStorage] 加载图片成功: \(fileId).\(fileType), 大小: \(data.count) 字节")
            return data
        } catch {
            print("[LocalStorage] 加载图片失败: \(fileId).\(fileType), 错误: \(error)")
            return nil
        }
    }
    
    /// 验证图片文件是否有效
    func validateImage(fileId: String, fileType: String) -> Bool {
        guard let fileURL = getImageURL(fileId: fileId, fileType: fileType) else {
            return false
        }
        
        // 检查文件是否存在
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return false
        }
        
        // 检查文件大小（至少1字节）
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? Int64, fileSize > 0 {
                return true
            }
        } catch {
            print("[LocalStorage] 验证图片失败: \(fileId).\(fileType), 错误: \(error)")
        }
        
        return false
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
        return try database.loadFolderSortInfo()
    }
    
    /// 清除文件夹排序信息
    /// 
    /// - Throws: 数据库操作失败
    func clearFolderSortInfo() throws {
        try database.clearFolderSortInfo()
        print("[LocalStorage] 清除文件夹排序信息")
    }
}

// MARK: - 同步状态模型

struct SyncStatus: Codable {
    var lastSyncTime: Date?
    var syncTag: String?  // 笔记同步的syncTag
    var lastPageSyncTime: Date?
    
    init(lastSyncTime: Date? = nil, syncTag: String? = nil, lastPageSyncTime: Date? = nil) {
        self.lastSyncTime = lastSyncTime
        self.syncTag = syncTag
        self.lastPageSyncTime = lastPageSyncTime
    }
}

// MARK: - 待删除笔记模型

struct PendingDeletion: Codable {
    let noteId: String
    let tag: String
    let purge: Bool
    let createdAt: Date
    
    init(noteId: String, tag: String, purge: Bool = false, createdAt: Date = Date()) {
        self.noteId = noteId
        self.tag = tag
        self.purge = purge
        self.createdAt = createdAt
    }
}
