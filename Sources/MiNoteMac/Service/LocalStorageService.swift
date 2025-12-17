import Foundation

class LocalStorageService {
    static let shared = LocalStorageService()
    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    
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
    
    /// 保存笔记到本地（使用小米笔记原生格式）
    func saveNote(_ note: Note) throws {
        let noteData = note.toMinoteData()
        
        // 将数据转换为JSON
        let jsonData = try JSONSerialization.data(withJSONObject: noteData, options: .prettyPrinted)
        
        // 创建文件名：使用笔记ID作为文件名
        let fileName = "\(note.id).json"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        // 写入文件
        try jsonData.write(to: fileURL)
        
        print("保存笔记到本地: \(fileURL.path)")
    }
    
    /// 从本地加载笔记
    func loadNote(noteId: String) throws -> Note? {
        let fileName = "\(noteId).json"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        // 读取文件
        let jsonData = try Data(contentsOf: fileURL)
        let noteData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        
        // 转换为Note对象
        if let noteData = noteData, let note = Note.fromMinoteData(noteData) {
            return note
        }
        
        return nil
    }
    
    /// 删除本地笔记
    func deleteNote(noteId: String) throws {
        let fileName = "\(noteId).json"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
            print("删除本地笔记: \(fileURL.path)")
        }
    }
    
    /// 获取所有本地笔记
    func getAllLocalNotes() throws -> [Note] {
        var notes: [Note] = []
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            
            for fileURL in fileURLs {
                if fileURL.pathExtension == "json" {
                    do {
                        let jsonData = try Data(contentsOf: fileURL)
                        let noteData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                        
                        if let noteData = noteData, let note = Note.fromMinoteData(noteData) {
                            notes.append(note)
                        }
                    } catch {
                        print("读取笔记文件失败 \(fileURL.lastPathComponent): \(error)")
                    }
                }
            }
        } catch {
            print("获取目录内容失败: \(error)")
        }
        
        return notes
    }
    
    /// 检查笔记是否存在本地副本
    func noteExistsLocally(noteId: String) -> Bool {
        let fileName = "\(noteId).json"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    /// 获取笔记的本地修改时间
    func getNoteLocalModificationDate(noteId: String) -> Date? {
        let fileName = "\(noteId).json"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }
    
    // MARK: - 同步状态管理
    
    /// 保存同步状态
    func saveSyncStatus(_ status: SyncStatus) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(status)
        let fileURL = documentsDirectory.appendingPathComponent("sync_status.json")
        
        try jsonData.write(to: fileURL)
    }
    
    /// 加载同步状态
    func loadSyncStatus() -> SyncStatus? {
        let fileURL = documentsDirectory.appendingPathComponent("sync_status.json")
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let jsonData = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            return try decoder.decode(SyncStatus.self, from: jsonData)
        } catch {
            print("加载同步状态失败: \(error)")
            return nil
        }
    }
    
    /// 清除同步状态
    func clearSyncStatus() throws {
        let fileURL = documentsDirectory.appendingPathComponent("sync_status.json")
        
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    
    // MARK: - 文件夹管理
    
    /// 保存文件夹列表到本地
    func saveFolders(_ folders: [Folder]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(folders)
        let fileURL = documentsDirectory.appendingPathComponent("folders.json")
        
        try jsonData.write(to: fileURL)
        print("保存文件夹列表到本地: \(folders.count) 个文件夹")
    }
    
    /// 从本地加载文件夹列表
    func loadFolders() throws -> [Folder] {
        let fileURL = documentsDirectory.appendingPathComponent("folders.json")
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("文件夹列表文件不存在")
            return []
        }
        
        do {
            let jsonData = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let folders = try decoder.decode([Folder].self, from: jsonData)
            print("从本地加载文件夹列表: \(folders.count) 个文件夹")
            return folders
        } catch {
            print("加载文件夹列表失败: \(error)")
            return []
        }
    }
    
    /// 创建文件夹（文件系统目录）
    func createFolder(_ folderName: String) throws -> URL {
        let folderURL = documentsDirectory.appendingPathComponent(folderName)
        
        if !fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        return folderURL
    }
    
    /// 获取所有文件夹（文件系统目录名称，已废弃，使用loadFolders代替）
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(deletions)
        let fileURL = documentsDirectory.appendingPathComponent("pending_deletions.json")
        try jsonData.write(to: fileURL)
        print("保存 \(deletions.count) 个待删除笔记")
    }
    
    /// 加载待删除的笔记列表
    func loadPendingDeletions() -> [PendingDeletion] {
        let fileURL = documentsDirectory.appendingPathComponent("pending_deletions.json")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let jsonData = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let deletions = try decoder.decode([PendingDeletion].self, from: jsonData)
            print("加载了 \(deletions.count) 个待删除笔记")
            return deletions
        } catch {
            print("加载待删除笔记列表失败: \(error)")
            return []
        }
    }
    
    /// 移除待删除的笔记（删除成功后调用）
    func removePendingDeletion(noteId: String) throws {
        var deletions = loadPendingDeletions()
        deletions.removeAll { $0.noteId == noteId }
        try savePendingDeletions(deletions)
        print("移除待删除笔记: \(noteId)")
    }
    
    
    /// 添加待删除的笔记（删除失败时调用）
    func addPendingDeletion(_ deletion: PendingDeletion) throws {
        var deletions = loadPendingDeletions()
        // 如果已存在，先移除旧的
        deletions.removeAll { $0.noteId == deletion.noteId }
        deletions.append(deletion)
        try savePendingDeletions(deletions)
        print("添加待删除笔记: \(deletion.noteId)")
    }
}

// MARK: - 同步状态模型

struct SyncStatus: Codable {
    var lastSyncTime: Date?
    var syncTag: String?
    var syncedNoteIds: [String]
    var lastPageSyncTime: Date?
    
    init(lastSyncTime: Date? = nil, syncTag: String? = nil, syncedNoteIds: [String] = [], lastPageSyncTime: Date? = nil) {
        self.lastSyncTime = lastSyncTime
        self.syncTag = syncTag
        self.syncedNoteIds = syncedNoteIds
        self.lastPageSyncTime = lastPageSyncTime
    }
    
    mutating func addSyncedNote(_ noteId: String) {
        if !syncedNoteIds.contains(noteId) {
            syncedNoteIds.append(noteId)
        }
    }
    
    mutating func removeSyncedNote(_ noteId: String) {
        syncedNoteIds.removeAll { $0 == noteId }
    }
    
    func isNoteSynced(_ noteId: String) -> Bool {
        return syncedNoteIds.contains(noteId)
    }
}

// MARK: - 待删除笔记模型

struct PendingDeletion: Codable {
    let noteId: String
    let tag: String
    let purge: Bool
    let createdAt: Date
    
    init(noteId: String, tag: String, purge: Bool = false) {
        self.noteId = noteId
        self.tag = tag
        self.purge = purge
        self.createdAt = Date()
    }
}
