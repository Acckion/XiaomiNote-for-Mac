import Foundation

/// 保存结果
public enum SaveResult: Sendable {
    /// 保存成功
    case success
    /// 保存失败
    case failure(Error)
}

/// 冲突解决结果
public enum ConflictResolution: Sendable {
    /// 保留本地内容，触发上传
    case keepLocal
    /// 使用云端内容更新本地
    case useCloud
    /// 跳过（不做任何操作）
    case skip
}

/// 操作协调器错误
public enum NoteOperationError: Error, Sendable {
    /// 保存失败
    case saveFailed(String)
    /// 上传失败
    case uploadFailed(String)
    /// 网络不可用
    case networkUnavailable
    /// 笔记不存在
    case noteNotFound(noteId: String)
    /// 持久化失败
    case persistenceFailed(String)
    /// 临时 ID 笔记创建失败
    case temporaryNoteCreationFailed(String)
}

/// 笔记操作协调器
/// 
/// 协调保存、上传、同步操作的中央控制器
/// 使用 Actor 确保线程安全，防止数据竞争
/// 
/// **设计理念**：
/// - Local-First：本地写入立即生效，网络操作异步执行
/// - Actor Isolation：使用 Swift Actor 确保线程安全
/// - UnifiedOperationQueue：统一操作队列，追踪待上传笔记，阻止同步覆盖本地修改
public actor NoteOperationCoordinator {
    
    // MARK: - 单例
    
    public static let shared = NoteOperationCoordinator()
    
    // MARK: - 依赖
    
    /// 统一操作队列（替代 PendingUploadRegistry）
    private let operationQueue: UnifiedOperationQueue
    
    /// 数据库服务
    private let databaseService: DatabaseService
    
    /// 本地存储服务
    private let localStorage: LocalStorageService
    
    /// ID 映射注册表
    private let idMappingRegistry: IdMappingRegistry
    
    // MARK: - 状态
    
    /// 当前活跃编辑的笔记 ID
    private var activeEditingNoteId: String?
    
    // MARK: - 初始化
    
    private init(
        operationQueue: UnifiedOperationQueue = .shared,
        databaseService: DatabaseService = .shared,
        localStorage: LocalStorageService = .shared,
        idMappingRegistry: IdMappingRegistry = .shared
    ) {
        self.operationQueue = operationQueue
        self.databaseService = databaseService
        self.localStorage = localStorage
        self.idMappingRegistry = idMappingRegistry
        print("[NoteOperationCoordinator] ✅ 初始化完成（使用 UnifiedOperationQueue）")
    }
    
    // MARK: - 保存操作

    
    /// 保存笔记（本地 + 触发上传）
    /// 
    /// 执行流程：
    /// 1. 本地保存到数据库（同步执行）
    /// 2. 创建 cloudUpload 操作
    /// 3. 网络可用时立即处理
    /// 
    /// - Parameter note: 要保存的笔记
    /// - Returns: 保存结果
    /// 
    /// **需求覆盖**：
    /// - 需求 1.2: 本地保存后创建 cloudUpload 操作
    /// - 需求 2.1: 网络可用时立即处理
    public func saveNote(_ note: Note) async -> SaveResult {
        let timestamp = Date()
        
        // 调试：打印传入的笔记字段
        print("[NoteOperationCoordinator] 📝 准备保存笔记:")
        print("[NoteOperationCoordinator]   - id: \(note.id)")
        print("[NoteOperationCoordinator]   - serverTag: \(note.serverTag ?? "nil")")
        print("[NoteOperationCoordinator]   - subject: \(note.subject ?? "nil")")
        print("[NoteOperationCoordinator]   - settingJson: \(note.settingJson != nil ? "有值(\(note.settingJson!.count)字符)" : "nil")")
        print("[NoteOperationCoordinator]   - extraInfoJson: \(note.extraInfoJson != nil ? "有值(\(note.extraInfoJson!.count)字符)" : "nil")")
        
        // 1. 本地保存到数据库（同步执行）
        do {
            try databaseService.saveNote(note)
            print("[NoteOperationCoordinator] 💾 本地保存成功: \(note.id.prefix(8))...")
        } catch {
            print("[NoteOperationCoordinator] ❌ 本地保存失败: \(error)")
            return .failure(NoteOperationError.saveFailed(error.localizedDescription))
        }
        
        // 2. 创建 cloudUpload 操作
        do {
            let noteData = try JSONEncoder().encode(note)
            let operation = NoteOperation(
                type: .cloudUpload,
                noteId: note.id,
                data: noteData,
                localSaveTimestamp: timestamp,
                isLocalId: NoteOperation.isTemporaryId(note.id)
            )
            try operationQueue.enqueue(operation)
            print("[NoteOperationCoordinator] 📤 已创建 cloudUpload 操作: \(note.id.prefix(8))...")
        } catch {
            print("[NoteOperationCoordinator] ❌ 创建 cloudUpload 操作失败: \(error)")
            // 本地保存成功，但操作入队失败，不影响返回结果
        }
        
        // 3. 网络可用时立即处理
        await triggerImmediateUploadIfOnline(note: note)
        
        return .success
    }
    
    /// 立即保存（切换笔记时调用）
    /// 
    /// 立即执行本地保存和上传，不使用防抖
    /// 
    /// - Parameter note: 要保存的笔记
    /// 
    /// **需求覆盖**：
    /// - 需求 2.1: 立即保存和上传
    public func saveNoteImmediately(_ note: Note) async throws {
        let timestamp = Date()
        
        // 1. 本地保存到数据库
        do {
            try databaseService.saveNote(note)
            print("[NoteOperationCoordinator] 💾 立即保存成功: \(note.id.prefix(8))...")
        } catch {
            print("[NoteOperationCoordinator] ❌ 立即保存失败: \(error)")
            throw NoteOperationError.saveFailed(error.localizedDescription)
        }
        
        // 2. 创建 cloudUpload 操作
        do {
            let noteData = try JSONEncoder().encode(note)
            let operation = NoteOperation(
                type: .cloudUpload,
                noteId: note.id,
                data: noteData,
                localSaveTimestamp: timestamp,
                isLocalId: NoteOperation.isTemporaryId(note.id)
            )
            try operationQueue.enqueue(operation)
            print("[NoteOperationCoordinator] 📤 已创建 cloudUpload 操作（立即）: \(note.id.prefix(8))...")
        } catch {
            print("[NoteOperationCoordinator] ❌ 创建 cloudUpload 操作失败: \(error)")
        }
        
        // 3. 立即触发上传
        await triggerImmediateUploadIfOnline(note: note)
    }
    
    /// 网络可用时立即触发上传
    ///
    /// - Parameter note: 要上传的笔记
    private func triggerImmediateUploadIfOnline(note: Note) async {
        // 检查网络状态
        let isOnline = await MainActor.run { NetworkMonitor.shared.isConnected }
        
        if isOnline {
            // 网络可用，获取待处理的操作并立即处理
            if let operation = operationQueue.getPendingUpload(for: note.id) {
                print("[NoteOperationCoordinator] 🚀 网络可用，立即处理上传: \(note.id.prefix(8))...")
                Task { @MainActor in
                    await OperationProcessor.shared.processImmediately(operation)
                }
            }
        } else {
            print("[NoteOperationCoordinator] 📴 网络不可用，操作已加入队列等待: \(note.id.prefix(8))...")
        }
    }
    
    // MARK: - 活跃编辑管理
    
    /// 设置活跃编辑笔记
    /// 
    /// 当用户在编辑器中打开笔记时调用
    /// 
    /// - Parameter noteId: 笔记 ID，传 nil 表示清除活跃编辑状态
    /// 
    /// **需求覆盖**：
    /// - 需求 3.1: 标记活跃编辑笔记
    /// - 需求 3.3: 切换笔记时清除原笔记标记
    public func setActiveEditingNote(_ noteId: String?) {
        if let oldNoteId = activeEditingNoteId, oldNoteId != noteId {
            print("[NoteOperationCoordinator] 🔄 切换活跃编辑笔记: \(oldNoteId.prefix(8))... -> \(noteId?.prefix(8) ?? "nil")")
        } else if let newNoteId = noteId {
            print("[NoteOperationCoordinator] ✏️ 设置活跃编辑笔记: \(newNoteId.prefix(8))...")
        } else {
            print("[NoteOperationCoordinator] 🔓 清除活跃编辑状态")
        }
        activeEditingNoteId = noteId
    }
    
    /// 检查笔记是否正在编辑
    /// 
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 是否正在编辑
    /// 
    /// **需求覆盖**：
    /// - 需求 3.2: 检查活跃编辑状态
    public func isNoteActivelyEditing(_ noteId: String) -> Bool {
        return activeEditingNoteId == noteId
    }
    
    /// 获取当前活跃编辑的笔记 ID
    /// 
    /// - Returns: 活跃编辑的笔记 ID，如果没有则返回 nil
    public func getActiveEditingNoteId() -> String? {
        return activeEditingNoteId
    }
    
    // MARK: - 同步保护
    
    /// 检查笔记是否可以被同步更新
    /// 
    /// 同步服务在更新笔记前调用此方法检查
    /// 使用 SyncGuard 进行统一的同步保护检查
    /// 
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - cloudTimestamp: 云端时间戳
    /// - Returns: 是否可以更新
    /// 
    /// **需求覆盖**：
    /// - 需求 4.1: 使用 SyncGuard 进行同步保护
    /// - 需求 4.2: 待上传笔记跳过同步
    /// - 需求 4.3: 活跃编辑笔记跳过同步
    /// - 需求 8.3: 临时 ID 笔记跳过同步
    public func canSyncUpdateNote(_ noteId: String, cloudTimestamp: Date) async -> Bool {
        let syncGuard = SyncGuard(operationQueue: operationQueue, coordinator: self)
        let shouldSkip = await syncGuard.shouldSkipSync(noteId: noteId, cloudTimestamp: cloudTimestamp)
        
        if shouldSkip {
            if let reason = await syncGuard.getSkipReason(noteId: noteId, cloudTimestamp: cloudTimestamp) {
                print("[NoteOperationCoordinator] 🛡️ 同步保护: \(reason.description) \(noteId.prefix(8))...")
            }
            return false
        }
        
        return true
    }

    
    // MARK: - 冲突解决
    
    /// 处理同步冲突
    /// 
    /// 当同步获取到笔记更新时，决定如何处理冲突
    /// 
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - cloudTimestamp: 云端时间戳
    /// - Returns: 冲突解决结果
    /// 
    /// **需求覆盖**：
    /// - 需求 5.1: 比较时间戳
    /// - 需求 5.2: 本地较新时保留本地
    /// - 需求 5.3: 云端较新且不在待上传列表时使用云端
    /// - 需求 5.4: 云端较新但在待上传列表时保留本地
    public func resolveConflict(noteId: String, cloudTimestamp: Date) -> ConflictResolution {
        // 1. 检查是否为临时 ID（离线创建的笔记）
        if NoteOperation.isTemporaryId(noteId) {
            print("[NoteOperationCoordinator] ⚔️ 冲突解决: 临时 ID 笔记，保留本地 \(noteId.prefix(8))...")
            return .keepLocal
        }
        
        // 2. 检查是否正在编辑
        if isNoteActivelyEditing(noteId) {
            print("[NoteOperationCoordinator] ⚔️ 冲突解决: 正在编辑，保留本地 \(noteId.prefix(8))...")
            return .keepLocal
        }
        
        // 3. 检查是否有待处理上传
        if operationQueue.hasPendingUpload(for: noteId) {
            if let localTimestamp = operationQueue.getLocalSaveTimestamp(for: noteId) {
                if localTimestamp >= cloudTimestamp {
                    // 本地较新，保留本地并触发上传
                    print("[NoteOperationCoordinator] ⚔️ 冲突解决: 本地较新，保留本地 \(noteId.prefix(8))...")
                    return .keepLocal
                } else {
                    // 云端较新，但在待上传列表中，用户优先策略
                    print("[NoteOperationCoordinator] ⚔️ 冲突解决: 云端较新但待上传中，保留本地 \(noteId.prefix(8))...")
                    return .keepLocal
                }
            }
            // 无法获取本地时间戳，保守策略：保留本地
            print("[NoteOperationCoordinator] ⚔️ 冲突解决: 待上传中（无时间戳），保留本地 \(noteId.prefix(8))...")
            return .keepLocal
        }
        
        // 4. 不在待上传列表中，使用云端内容
        print("[NoteOperationCoordinator] ⚔️ 冲突解决: 使用云端 \(noteId.prefix(8))...")
        return .useCloud
    }
    
    // MARK: - 上传完成回调
    
    /// 上传成功回调
    /// 
    /// 由 OperationProcessor 在上传成功后调用
    /// 
    /// - Parameter noteId: 笔记 ID
    /// 
    /// **需求覆盖**：
    /// - 需求 2.2: 上传成功后更新 UnifiedOperationQueue 状态
    public func onUploadSuccess(noteId: String) {
        // 操作状态由 OperationProcessor 直接更新 UnifiedOperationQueue
        // 这里只做日志记录
        print("[NoteOperationCoordinator] ✅ 上传成功: \(noteId.prefix(8))...")
    }
    
    /// 上传失败回调
    /// 
    /// 由 OperationProcessor 在上传失败后调用
    /// 
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - error: 错误信息
    /// 
    /// **需求覆盖**：
    /// - 需求 2.3: 上传失败时操作保留在队列中等待重试
    public func onUploadFailure(noteId: String, error: Error) {
        // 操作状态由 OperationProcessor 直接更新 UnifiedOperationQueue
        // 这里只做日志记录
        print("[NoteOperationCoordinator] ❌ 上传失败: \(noteId.prefix(8))..., 错误: \(error)")
    }
    
    // MARK: - 离线创建笔记
    
    /// 离线创建笔记
    ///
    /// 在离线状态下创建新笔记：
    /// 1. 生成临时 ID（格式：local_xxx）
    /// 2. 保存到本地数据库
    /// 3. 创建 noteCreate 操作（isLocalId=true）
    ///
    /// - Parameters:
    ///   - title: 笔记标题
    ///   - content: 笔记内容
    ///   - folderId: 文件夹 ID
    /// - Returns: 创建的笔记（使用临时 ID）
    /// - Throws: NoteOperationError
    ///
    /// **需求覆盖**：
    /// - 需求 8.1: 生成临时 ID 并立即保存到本地
    /// - 需求 8.2: 创建 noteCreate 操作并标记 isLocalId = true
    public func createNoteOffline(title: String, content: String, folderId: String) async throws -> Note {
        // 1. 生成临时 ID
        let temporaryId = NoteOperation.generateTemporaryId()
        print("[NoteOperationCoordinator] 📝 离线创建笔记，临时 ID: \(temporaryId.prefix(16))...")
        
        // 2. 创建笔记对象
        let now = Date()
        let note = Note(
            id: temporaryId,
            title: title,
            content: content,
            folderId: folderId,
            isStarred: false,
            createdAt: now,
            updatedAt: now,
            tags: [],
            rawData: nil
        )
        
        // 3. 保存到本地数据库
        do {
            try databaseService.saveNote(note)
            print("[NoteOperationCoordinator] 💾 离线笔记本地保存成功: \(temporaryId.prefix(16))...")
        } catch {
            print("[NoteOperationCoordinator] ❌ 离线笔记本地保存失败: \(error)")
            throw NoteOperationError.temporaryNoteCreationFailed(error.localizedDescription)
        }
        
        // 4. 创建 noteCreate 操作
        do {
            let noteData = try JSONEncoder().encode(note)
            let operation = NoteOperation(
                type: .noteCreate,
                noteId: temporaryId,
                data: noteData,
                localSaveTimestamp: now,
                isLocalId: true
            )
            try operationQueue.enqueue(operation)
            print("[NoteOperationCoordinator] 📤 已创建 noteCreate 操作: \(temporaryId.prefix(16))...")
        } catch {
            print("[NoteOperationCoordinator] ❌ 创建 noteCreate 操作失败: \(error)")
            // 本地保存成功，但操作入队失败，不影响返回结果
        }
        
        return note
    }
    
    // MARK: - ID 更新处理
    
    /// 处理笔记创建成功
    ///
    /// 当 noteCreate 操作成功后，获取云端下发的正式 ID，
    /// 然后更新所有引用临时 ID 的地方。
    ///
    /// - Parameters:
    ///   - temporaryId: 临时 ID
    ///   - serverId: 云端下发的正式 ID
    ///
    /// **需求覆盖**：
    /// - 需求 8.4: 获取云端下发的正式 ID
    /// - 需求 8.5: 更新本地数据库中的笔记 ID
    /// - 需求 8.6: 更新操作队列中的 noteId
    /// - 需求 8.7: 更新 UI 中的笔记引用
    public func handleNoteCreateSuccess(temporaryId: String, serverId: String) async throws {
        print("[NoteOperationCoordinator] 🔄 处理笔记创建成功: \(temporaryId.prefix(16))... -> \(serverId.prefix(8))...")
        
        // 1. 调用 IdMappingRegistry 更新所有引用
        try await idMappingRegistry.updateAllReferences(localId: temporaryId, serverId: serverId)
        
        // 2. 更新 activeEditingNoteId（如果正在编辑该笔记）
        if activeEditingNoteId == temporaryId {
            activeEditingNoteId = serverId
            print("[NoteOperationCoordinator] ✏️ 更新活跃编辑笔记 ID: \(temporaryId.prefix(16))... -> \(serverId.prefix(8))...")
        }
        
        // 3. 标记映射完成
        try idMappingRegistry.markCompleted(localId: temporaryId)
        
        print("[NoteOperationCoordinator] ✅ 笔记创建成功处理完成: \(serverId.prefix(8))...")
    }
    
    // MARK: - 临时 ID 笔记删除
    
    /// 删除临时 ID 笔记
    ///
    /// 当用户删除离线创建的笔记（在上传前）时：
    /// 1. 取消 noteCreate 操作
    /// 2. 删除本地笔记
    ///
    /// - Parameter noteId: 笔记 ID（临时 ID）
    /// - Throws: NoteOperationError
    ///
    /// **需求覆盖**：
    /// - 需求 8.8: 临时 ID 笔记被删除时取消 noteCreate 操作
    public func deleteTemporaryNote(_ noteId: String) async throws {
        // 验证是否为临时 ID
        guard NoteOperation.isTemporaryId(noteId) else {
            print("[NoteOperationCoordinator] ⚠️ 不是临时 ID 笔记: \(noteId.prefix(8))...")
            return
        }
        
        print("[NoteOperationCoordinator] 🗑️ 删除临时 ID 笔记: \(noteId.prefix(16))...")
        
        // 1. 取消该笔记的所有待处理操作（包括 noteCreate）
        do {
            try operationQueue.cancelOperations(for: noteId)
            print("[NoteOperationCoordinator] ✅ 已取消待处理操作: \(noteId.prefix(16))...")
        } catch {
            print("[NoteOperationCoordinator] ❌ 取消操作失败: \(error)")
        }
        
        // 2. 删除本地笔记
        do {
            try databaseService.deleteNote(noteId: noteId)
            print("[NoteOperationCoordinator] ✅ 已删除本地笔记: \(noteId.prefix(16))...")
        } catch {
            print("[NoteOperationCoordinator] ❌ 删除本地笔记失败: \(error)")
            throw NoteOperationError.saveFailed(error.localizedDescription)
        }
        
        // 3. 如果正在编辑该笔记，清除活跃编辑状态
        if activeEditingNoteId == noteId {
            activeEditingNoteId = nil
            print("[NoteOperationCoordinator] 🔓 清除活跃编辑状态")
        }
    }
    
    /// 检查笔记是否为临时 ID
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 是否为临时 ID
    public func isTemporaryNoteId(_ noteId: String) -> Bool {
        return NoteOperation.isTemporaryId(noteId)
    }
    
    // MARK: - 查询方法
    
    /// 获取待上传笔记数量
    ///
    /// - Returns: 待上传笔记数量
    public func getPendingUploadCount() -> Int {
        return operationQueue.getPendingUploadCount()
    }
    
    /// 获取所有待上传笔记 ID
    ///
    /// - Returns: 笔记 ID 数组
    public func getAllPendingNoteIds() -> [String] {
        return operationQueue.getAllPendingNoteIds()
    }
    
    /// 检查笔记是否有待处理上传
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 是否有待处理上传
    public func hasPendingUpload(for noteId: String) -> Bool {
        return operationQueue.hasPendingUpload(for: noteId)
    }
    
    /// 获取本地保存时间戳
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 本地保存时间戳
    public func getLocalSaveTimestamp(for noteId: String) -> Date? {
        return operationQueue.getLocalSaveTimestamp(for: noteId)
    }
    
    // MARK: - 测试辅助方法
    
    /// 重置状态（仅用于测试）
    public func resetForTesting() {
        activeEditingNoteId = nil
        print("[NoteOperationCoordinator] 🧪 测试重置完成")
    }
}
