import Foundation

// MARK: - ⚠️ 废弃警告
// 此文件中的组件已被废弃，请使用新的统一操作队列系统
// 迁移指南：
// - PendingUploadRegistry -> UnifiedOperationQueue
// - 待上传追踪现在由 UnifiedOperationQueue 统一管理
// - 使用 UnifiedOperationQueue.hasPendingUpload(for:) 检查待上传状态
// - 使用 UnifiedOperationQueue.getLocalSaveTimestamp(for:) 获取时间戳

/// 待上传注册表
/// 
/// 记录有本地修改等待上传的笔记 ID 和时间戳
/// 支持持久化到数据库，应用重启后可恢复
/// 
/// - Important: 此类已废弃，请使用 `UnifiedOperationQueue` 替代
/// 
/// ## 迁移指南
/// 
/// ### 旧代码
/// ```swift
/// PendingUploadRegistry.shared.register(noteId: noteId, timestamp: Date())
/// PendingUploadRegistry.shared.isRegistered(noteId)
/// PendingUploadRegistry.shared.getLocalSaveTimestamp(noteId)
/// PendingUploadRegistry.shared.unregister(noteId: noteId)
/// ```
/// 
/// ### 新代码
/// ```swift
/// // 注册待上传（通过 NoteOperationCoordinator.saveNote() 自动处理）
/// await NoteOperationCoordinator.shared.saveNote(note)
/// 
/// // 检查待上传状态
/// UnifiedOperationQueue.shared.hasPendingUpload(for: noteId)
/// UnifiedOperationQueue.shared.getLocalSaveTimestamp(for: noteId)
/// 
/// // 上传完成后自动清理（由 OperationProcessor 处理）
/// ```
/// 
/// 新的实现特点：
/// - 统一的操作队列管理所有类型的操作
/// - 支持操作合并和去重
/// - 自动重试和错误处理
/// - 更好的状态可观察性
/// 
/// **线程安全**：使用 NSLock 确保线程安全
/// 
/// **需求覆盖**：
/// - 需求 1.1: 注册待上传笔记
/// - 需求 1.2: 上传成功后注销
/// - 需求 1.4: 应用启动时恢复
/// - 需求 6.1: 持久化到数据库
@available(*, deprecated, message: "请使用 UnifiedOperationQueue 替代，待上传追踪功能已统一管理")
public final class PendingUploadRegistry: @unchecked Sendable {
    
    // MARK: - 单例
    
    public static let shared = PendingUploadRegistry()
    
    // MARK: - 状态
    
    /// 待上传条目字典（noteId -> PendingUploadEntry）
    private var entries: [String: PendingUploadEntry] = [:]
    
    /// 线程安全锁
    private let lock = NSLock()
    
    /// 数据库服务
    private let databaseService = DatabaseService.shared
    
    // MARK: - 初始化
    
    private init() {
        // 从数据库恢复状态
        do {
            try restoreFromDatabase()
            print("[PendingUploadRegistry] ✅ 从数据库恢复 \(entries.count) 个待上传条目")
        } catch {
            print("[PendingUploadRegistry] ⚠️ 从数据库恢复失败: \(error)")
        }
    }
    
    // MARK: - 注册/注销
    
    /// 注册待上传笔记
    /// 
    /// 当用户编辑笔记并触发本地保存时调用
    /// 
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - timestamp: 本地保存时间戳
    public func register(noteId: String, timestamp: Date) {
        lock.lock()
        defer { lock.unlock() }
        
        let entry = PendingUploadEntry(
            noteId: noteId,
            localSaveTimestamp: timestamp
        )
        entries[noteId] = entry
        
        print("[PendingUploadRegistry] 📝 注册待上传: \(noteId.prefix(8))..., 时间戳: \(timestamp)")
        
        // 持久化到数据库
        do {
            try persistEntryToDatabase(entry)
        } catch {
            print("[PendingUploadRegistry] ⚠️ 持久化失败: \(error)")
        }
    }
    
    /// 注销待上传笔记（上传成功后调用）
    /// 
    /// - Parameter noteId: 笔记 ID
    public func unregister(noteId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        guard entries.removeValue(forKey: noteId) != nil else {
            return
        }
        
        print("[PendingUploadRegistry] ✅ 注销待上传: \(noteId.prefix(8))...")
        
        // 从数据库删除
        do {
            try removeEntryFromDatabase(noteId: noteId)
        } catch {
            print("[PendingUploadRegistry] ⚠️ 从数据库删除失败: \(error)")
        }
    }
    
    // MARK: - 查询
    
    /// 检查笔记是否在待上传列表中
    /// 
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 是否在列表中
    public func isRegistered(_ noteId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[noteId] != nil
    }
    
    /// 获取笔记的本地保存时间戳
    /// 
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 本地保存时间戳，如果不在列表中返回 nil
    public func getLocalSaveTimestamp(_ noteId: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return entries[noteId]?.localSaveTimestamp
    }
    
    /// 获取待上传条目
    /// 
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 待上传条目，如果不在列表中返回 nil
    public func getEntry(_ noteId: String) -> PendingUploadEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[noteId]
    }
    
    /// 获取所有待上传笔记 ID
    /// 
    /// - Returns: 笔记 ID 数组
    public func getAllPendingNoteIds() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.keys)
    }
    
    /// 获取所有待上传条目
    /// 
    /// - Returns: 待上传条目数组
    public func getAllEntries() -> [PendingUploadEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.values)
    }
    
    /// 获取待上传笔记数量
    /// 
    /// - Returns: 待上传笔记数量
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
    
    // MARK: - 持久化
    
    /// 持久化单个条目到数据库
    private func persistEntryToDatabase(_ entry: PendingUploadEntry) throws {
        try databaseService.savePendingUpload(entry)
    }
    
    /// 从数据库删除条目
    private func removeEntryFromDatabase(noteId: String) throws {
        try databaseService.deletePendingUpload(noteId: noteId)
    }
    
    /// 持久化所有条目到数据库
    public func persistToDatabase() throws {
        lock.lock()
        let entriesToPersist = Array(entries.values)
        lock.unlock()
        
        for entry in entriesToPersist {
            try databaseService.savePendingUpload(entry)
        }
        print("[PendingUploadRegistry] 💾 持久化 \(entriesToPersist.count) 个条目到数据库")
    }
    
    /// 从数据库恢复
    public func restoreFromDatabase() throws {
        let restoredEntries = try databaseService.getAllPendingUploads()
        
        lock.lock()
        entries.removeAll()
        for entry in restoredEntries {
            entries[entry.noteId] = entry
        }
        lock.unlock()
    }
    
    /// 清空所有条目（仅用于测试）
    public func clearAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        
        do {
            try databaseService.clearAllPendingUploads()
            print("[PendingUploadRegistry] 🗑️ 清空所有待上传条目")
        } catch {
            print("[PendingUploadRegistry] ⚠️ 清空数据库失败: \(error)")
        }
    }
}
