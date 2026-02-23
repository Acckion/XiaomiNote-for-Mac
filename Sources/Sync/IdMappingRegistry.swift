import Foundation

// MARK: - ID 映射注册表

/// ID 映射注册表
///
/// 管理临时 ID（离线创建）和正式 ID（云端下发）的映射关系。
/// 当用户离线创建笔记时，系统会生成临时 ID（格式：local_xxx），
/// 网络恢复后上传成功会获取云端下发的正式 ID，此时需要更新所有引用。
///
/// **主要功能**：
/// - 注册临时 ID 到正式 ID 的映射
/// - 解析 ID（如果有映射则返回正式 ID）
/// - 更新所有引用临时 ID 的地方（数据库、操作队列、UI）
/// - 清理已完成的映射
/// - 应用启动时恢复未完成的映射
///
/// **线程安全设计**：
/// 使用 NSLock 而非 Actor 的原因：
/// 1. 同步访问需求：resolveId()、hasMapping() 等方法需要同步返回结果，
///    如果使用 Actor 则所有调用都需要 await，会传染到整个调用链
/// 2. 性能考虑：NSLock 的开销远小于 Actor 的上下文切换
/// 3. 操作粒度：每个操作都是短暂的内存读写，不涉及 I/O，
///    NSLock 的持有时间极短，不会造成阻塞
/// 4. 与 OperationProcessor（Actor）的交互：OperationProcessor 是 Actor，
///    如果 IdMappingRegistry 也是 Actor，两者交互时可能产生死锁风险
///    （spec 104 已验证双 Actor 方案存在死锁问题）
///
/// **锁保护的可变状态**：
/// - `mappingsCache`: 映射缓存（临时 ID -> 映射记录）
///
public final class IdMappingRegistry: @unchecked Sendable {

    // MARK: - 单例

    /// 共享实例
    public static let shared = IdMappingRegistry()

    // MARK: - 依赖

    /// 数据库服务
    private let databaseService: DatabaseService

    /// 统一操作队列
    private let operationQueue: UnifiedOperationQueue

    /// EventBus 实例
    private let eventBus: EventBus

    // MARK: - 线程安全

    /// 操作锁，确保线程安全
    private let lock = NSLock()

    // MARK: - 内存缓存

    /// 映射缓存（临时 ID -> 映射记录）
    /// 受 lock 保护
    private var mappingsCache: [String: IdMapping] = [:]

    // MARK: - 初始化

    /// 私有初始化方法（单例模式）
    private init() {
        self.databaseService = DatabaseService.shared
        self.operationQueue = UnifiedOperationQueue.shared
        self.eventBus = EventBus.shared

        // 从数据库恢复未完成的映射
        loadFromDatabase()

        LogService.shared.info(.sync, "IdMappingRegistry 初始化完成，加载了 \(mappingsCache.count) 个未完成的映射")
    }

    /// 用于测试的初始化方法
    ///
    /// - Parameters:
    ///   - databaseService: 数据库服务实例
    ///   - operationQueue: 统一操作队列实例
    init(databaseService: DatabaseService, operationQueue: UnifiedOperationQueue, eventBus: EventBus = EventBus.shared) {
        self.databaseService = databaseService
        self.operationQueue = operationQueue
        self.eventBus = eventBus

        // 从数据库恢复未完成的映射
        loadFromDatabase()
    }

    // MARK: - 数据库加载

    /// 从数据库加载未完成的映射
    ///
    private func loadFromDatabase() {
        lock.lock()
        defer { lock.unlock() }

        do {
            let mappings = try databaseService.getIncompleteIdMappings()

            // 重建内存缓存
            mappingsCache.removeAll()

            for mapping in mappings {
                mappingsCache[mapping.localId] = mapping
            }

            LogService.shared.debug(.sync, "IdMappingRegistry 从数据库加载了 \(mappings.count) 个未完成的映射")
        } catch {
            LogService.shared.error(.sync, "IdMappingRegistry 从数据库加载映射失败: \(error)")
        }
    }
}

// MARK: - 映射注册

public extension IdMappingRegistry {

    /// 注册 ID 映射
    ///
    /// 记录临时 ID 到正式 ID 的映射关系，并持久化到数据库。
    ///
    /// - Parameters:
    ///   - localId: 临时 ID（格式：local_xxx）
    ///   - serverId: 云端下发的正式 ID
    ///   - entityType: 实体类型（"note" 或 "folder"）
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    func registerMapping(localId: String, serverId: String, entityType: String) throws {
        lock.lock()
        defer { lock.unlock() }

        // 创建映射记录
        let mapping = IdMapping(
            localId: localId,
            serverId: serverId,
            entityType: entityType,
            createdAt: Date(),
            completed: false
        )

        // 持久化到数据库
        try databaseService.saveIdMapping(mapping)

        // 更新内存缓存
        mappingsCache[localId] = mapping

        LogService.shared.debug(.sync, "注册映射: \(localId) -> \(serverId) (\(entityType))")
    }

    /// 检查是否存在映射
    ///
    /// - Parameter localId: 临时 ID
    /// - Returns: 如果存在映射返回 true
    func hasMapping(for localId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return mappingsCache[localId] != nil
    }

    /// 获取映射记录
    ///
    /// - Parameter localId: 临时 ID
    /// - Returns: 映射记录，如果不存在则返回 nil
    func getMapping(for localId: String) -> IdMapping? {
        lock.lock()
        defer { lock.unlock() }

        return mappingsCache[localId]
    }

    /// 检查是否为临时 ID
    ///
    /// - Parameter id: 要检查的 ID
    /// - Returns: 如果是临时 ID 返回 true
    func isTemporaryId(_ id: String) -> Bool {
        NoteOperation.isTemporaryId(id)
    }
}

// MARK: - ID 解析

public extension IdMappingRegistry {

    /// 解析 ID
    ///
    /// 如果传入的是临时 ID 且存在映射，则返回正式 ID；
    /// 否则返回原 ID。
    ///
    /// - Parameter id: 要解析的 ID
    /// - Returns: 解析后的 ID（正式 ID 或原 ID）
    ///
    func resolveId(_ id: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        // 如果不是临时 ID，直接返回
        guard NoteOperation.isTemporaryId(id) else {
            return id
        }

        // 查找映射
        if let mapping = mappingsCache[id] {
            return mapping.serverId
        }

        // 没有映射，返回原 ID
        return id
    }

    /// 批量解析 ID
    ///
    /// - Parameter ids: 要解析的 ID 数组
    /// - Returns: 解析后的 ID 数组
    func resolveIds(_ ids: [String]) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        return ids.map { id in
            if NoteOperation.isTemporaryId(id), let mapping = mappingsCache[id] {
                return mapping.serverId
            }
            return id
        }
    }

    /// 获取正式 ID（如果存在映射）
    ///
    /// - Parameter localId: 临时 ID
    /// - Returns: 正式 ID，如果没有映射则返回 nil
    func getServerId(for localId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        return mappingsCache[localId]?.serverId
    }
}

// MARK: - 批量更新引用

public extension IdMappingRegistry {

    /// 更新所有引用临时 ID 的地方
    ///
    /// 当离线创建的笔记上传成功后，需要将临时 ID 更新为正式 ID。
    /// 此方法会更新：
    /// 1. 本地数据库中的笔记 ID
    /// 2. 操作队列中的 noteId
    /// 3. 发送通知给 UI
    ///
    /// - Parameters:
    ///   - localId: 临时 ID
    ///   - serverId: 正式 ID
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    func updateAllReferences(localId: String, serverId: String) async throws {
        LogService.shared.debug(.sync, "开始更新所有引用: \(localId) -> \(serverId)")

        // 1. 注册映射（如果还没有注册）
        if !hasMapping(for: localId) {
            try registerMapping(localId: localId, serverId: serverId, entityType: "note")
        }

        // 2. 更新数据库中的笔记 ID
        do {
            try databaseService.updateNoteId(oldId: localId, newId: serverId)
            LogService.shared.debug(.sync, "数据库笔记 ID 更新成功")
        } catch {
            LogService.shared.error(.sync, "数据库笔记 ID 更新失败: \(error)")
            throw error
        }

        // 3. 更新操作队列中的 noteId
        do {
            try operationQueue.updateNoteIdInPendingOperations(oldNoteId: localId, newNoteId: serverId)
            LogService.shared.debug(.sync, "操作队列 noteId 更新成功")
        } catch {
            LogService.shared.error(.sync, "操作队列 noteId 更新失败: \(error)")
            throw error
        }

        // 4. 发布事件通知 UI
        await eventBus.publish(IdMappingEvent.mappingCompleted(localId: localId, serverId: serverId, entityType: "note"))

        LogService.shared.info(.sync, "所有引用更新完成: \(localId) -> \(serverId)")
    }

    /// 更新文件夹的所有引用
    ///
    /// - Parameters:
    ///   - localId: 临时 ID
    ///   - serverId: 正式 ID
    /// - Throws: DatabaseError（数据库操作失败）
    func updateAllFolderReferences(localId: String, serverId: String) async throws {
        LogService.shared.debug(.sync, "开始更新文件夹引用: \(localId) -> \(serverId)")

        // 1. 注册映射（如果还没有注册）
        if !hasMapping(for: localId) {
            try registerMapping(localId: localId, serverId: serverId, entityType: "folder")
        }

        // 2. 更新操作队列中的 noteId（文件夹操作也使用 noteId 字段）
        do {
            try operationQueue.updateNoteIdInPendingOperations(oldNoteId: localId, newNoteId: serverId)
            LogService.shared.debug(.sync, "操作队列 folderId 更新成功")
        } catch {
            LogService.shared.error(.sync, "操作队列 folderId 更新失败: \(error)")
            throw error
        }

        // 3. 发布事件通知 UI
        await eventBus.publish(IdMappingEvent.mappingCompleted(localId: localId, serverId: serverId, entityType: "folder"))

        LogService.shared.info(.sync, "文件夹引用更新完成: \(localId) -> \(serverId)")
    }

    /// 更新文件引用（图片/音频上传成功后替换临时 fileId）
    ///
    /// 上传完成后，编辑器可能还未将包含临时 fileId 的 XML 保存到数据库，
    /// 因此需要重试等待，确保数据库中的 XML 已包含临时 fileId 后再替换。
    ///
    /// - Parameters:
    ///   - localId: 临时文件 ID
    ///   - serverId: 云端下发的正式文件 ID
    ///   - noteId: 所属笔记 ID
    /// - Throws: DatabaseError（数据库操作失败）
    func updateAllFileReferences(localId: String, serverId: String, noteId: String) async throws {
        LogService.shared.debug(.sync, "开始更新文件引用: \(localId) -> \(serverId), 笔记: \(noteId.prefix(8))...")

        // 1. 注册映射
        if !hasMapping(for: localId) {
            try registerMapping(localId: localId, serverId: serverId, entityType: "file")
        }

        // 2. 带重试的 fileId 替换
        // 上传和编辑器保存是并发的，上传可能先完成，此时 DB 中的 XML 还不包含临时 ID
        let maxAttempts = 10
        let retryInterval: UInt64 = 500_000_000 // 0.5 秒

        for attempt in 1 ... maxAttempts {
            do {
                if var note = try databaseService.loadNote(noteId: noteId) {
                    let oldContent = note.content
                    note.content = oldContent.replacingOccurrences(of: localId, with: serverId)

                    if note.content != oldContent {
                        try databaseService.saveNote(note)
                        LogService.shared.debug(.sync, "笔记 XML 内容 fileId 替换成功")

                        let eventBus = EventBus.shared
                        await eventBus.publish(NoteEvent.saved(note))

                        try operationQueue.enqueueCloudUpload(
                            noteId: noteId,
                            title: note.title,
                            content: note.content,
                            folderId: note.folderId,
                            localSaveTimestamp: Date()
                        )
                        LogService.shared.debug(.sync, "已入队 cloudUpload 操作（文件引用更新）")

                        LogService.shared.info(.sync, "文件引用更新完成: \(localId) -> \(serverId)")
                        return
                    }

                    // XML 中未找到临时 ID，等待编辑器保存完成后重试
                    if attempt < maxAttempts {
                        LogService.shared.debug(.sync, "笔记内容中未找到临时 fileId，等待重试 (\(attempt)/\(maxAttempts)): \(localId)")
                        try? await Task.sleep(nanoseconds: retryInterval)
                    } else {
                        LogService.shared.warning(.sync, "笔记内容中始终未找到临时 fileId: \(localId)")
                    }
                } else {
                    LogService.shared.warning(.sync, "未找到笔记: \(noteId.prefix(8))..., 跳过文件引用更新")
                    return
                }
            } catch {
                LogService.shared.error(.sync, "更新文件引用失败: \(error)")
                throw error
            }
        }

        LogService.shared.info(.sync, "文件引用更新完成（未替换）: \(localId) -> \(serverId)")
    }
}

// MARK: - 清理方法

public extension IdMappingRegistry {

    /// 标记映射完成
    ///
    /// 当所有引用都已更新后，标记映射为已完成。
    /// 已完成的映射可以在稍后被清理。
    ///
    /// - Parameter localId: 临时 ID
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    func markCompleted(localId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        // 更新数据库
        try databaseService.markIdMappingCompleted(localId: localId)

        // 更新内存缓存
        if var mapping = mappingsCache[localId] {
            mapping.completed = true
            mappingsCache[localId] = mapping
        }

        LogService.shared.debug(.sync, "标记映射完成: \(localId)")
    }

    /// 清理已完成的映射
    ///
    /// 从数据库和内存缓存中删除所有已完成的映射记录。
    /// 建议在应用空闲时或定期执行此操作。
    ///
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    func cleanupCompletedMappings() throws {
        lock.lock()
        defer { lock.unlock() }

        // 从数据库删除
        try databaseService.deleteCompletedIdMappings()

        // 从内存缓存中移除已完成的映射
        let completedIds = mappingsCache.filter(\.value.completed).map(\.key)
        for id in completedIds {
            mappingsCache.removeValue(forKey: id)
        }

        LogService.shared.debug(.sync, "清理了 \(completedIds.count) 个已完成的映射")
    }

    /// 获取所有未完成的映射
    ///
    /// - Returns: 未完成的映射数组
    func getIncompleteMappings() -> [IdMapping] {
        lock.lock()
        defer { lock.unlock() }

        return Array(mappingsCache.values.filter { !$0.completed })
    }

    /// 获取所有映射
    ///
    /// - Returns: 所有映射数组
    func getAllMappings() -> [IdMapping] {
        lock.lock()
        defer { lock.unlock() }

        return Array(mappingsCache.values)
    }

    /// 获取映射数量
    ///
    /// - Returns: 映射数量
    func getMappingCount() -> Int {
        lock.lock()
        defer { lock.unlock() }

        return mappingsCache.count
    }

    /// 获取未完成映射数量
    ///
    /// - Returns: 未完成映射数量
    func getIncompleteMappingCount() -> Int {
        lock.lock()
        defer { lock.unlock() }

        return mappingsCache.values.count(where: { !$0.completed })
    }
}

// MARK: - 应用启动恢复

public extension IdMappingRegistry {

    /// 重新加载映射
    ///
    /// 从数据库重新加载所有未完成的映射。
    /// 通常在应用启动时自动调用，也可以手动调用以刷新缓存。
    ///
    func reload() {
        loadFromDatabase()
        LogService.shared.debug(.sync, "IdMappingRegistry 重新加载完成，当前有 \(mappingsCache.count) 个映射")
    }

    /// 处理未完成的映射
    ///
    /// 检查是否有未完成的映射需要处理。
    /// 这些映射可能是由于应用崩溃或意外退出导致的。
    ///
    /// - Returns: 需要处理的映射数组
    func getPendingMappings() -> [IdMapping] {
        lock.lock()
        defer { lock.unlock() }

        return mappingsCache.values.filter { !$0.completed }
    }

    /// 恢复未完成的映射
    ///
    /// 尝试完成所有未完成的映射。
    /// 这个方法会检查每个映射的状态，并尝试完成更新。
    ///
    /// - Returns: 成功恢复的映射数量
    func recoverIncompleteMappings() async -> Int {
        let pendingMappings = getPendingMappings()

        if pendingMappings.isEmpty {
            LogService.shared.debug(.sync, "没有需要恢复的映射")
            return 0
        }

        LogService.shared.info(.sync, "开始恢复 \(pendingMappings.count) 个未完成的映射")

        var recoveredCount = 0

        for mapping in pendingMappings {
            do {
                // 尝试更新所有引用
                if mapping.entityType == "note" {
                    try await updateAllReferences(localId: mapping.localId, serverId: mapping.serverId)
                } else if mapping.entityType == "folder" {
                    try await updateAllFolderReferences(localId: mapping.localId, serverId: mapping.serverId)
                }

                // 标记为完成
                try markCompleted(localId: mapping.localId)
                recoveredCount += 1

                LogService.shared.debug(.sync, "恢复映射成功: \(mapping.localId) -> \(mapping.serverId)")
            } catch {
                LogService.shared.error(.sync, "恢复映射失败: \(mapping.localId), 错误: \(error)")
            }
        }

        LogService.shared.info(.sync, "恢复完成，成功 \(recoveredCount)/\(pendingMappings.count)")
        return recoveredCount
    }
}

// MARK: - 测试辅助方法

public extension IdMappingRegistry {

    /// 清空所有映射（仅用于测试）
    ///
    /// - Throws: DatabaseError（数据库操作失败）
    func clearAllForTesting() throws {
        lock.lock()
        defer { lock.unlock() }

        // 清空内存缓存
        mappingsCache.removeAll()

        // 清空数据库（先清理已完成的，再清理未完成的）
        try databaseService.deleteCompletedIdMappings()

        LogService.shared.debug(.sync, "IdMappingRegistry 测试清空完成")
    }

    /// 重置状态（仅用于测试）
    func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }

        mappingsCache.removeAll()
        LogService.shared.debug(.sync, "IdMappingRegistry 测试重置完成")
    }
}

// MARK: - 统计信息

public extension IdMappingRegistry {

    /// 获取统计信息
    ///
    /// - Returns: 统计信息字典
    func getStatistics() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }

        let total = mappingsCache.count
        let completed = mappingsCache.values.count(where: { $0.completed })
        let incomplete = total - completed
        let notes = mappingsCache.values.count(where: { $0.entityType == "note" })
        let folders = mappingsCache.values.count(where: { $0.entityType == "folder" })

        return [
            "total": total,
            "completed": completed,
            "incomplete": incomplete,
            "notes": notes,
            "folders": folders,
        ]
    }
}
