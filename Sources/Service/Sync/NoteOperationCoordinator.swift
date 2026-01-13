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
}

/// 笔记操作协调器
/// 
/// 协调保存、上传、同步操作的中央控制器
/// 使用 Actor 确保线程安全，防止数据竞争
/// 
/// **设计理念**：
/// - Local-First：本地写入立即生效，网络操作异步执行
/// - Actor Isolation：使用 Swift Actor 确保线程安全
/// - Pending Upload Registry：追踪待上传笔记，阻止同步覆盖本地修改
/// 
/// **需求覆盖**：
/// - 需求 1.1: 本地保存后注册到 PendingUploadRegistry
/// - 需求 3.1: 活跃编辑笔记管理
/// - 需求 4.1: 上传调度
/// - 需求 5.1: 冲突解决
public actor NoteOperationCoordinator {
    
    // MARK: - 单例
    
    public static let shared = NoteOperationCoordinator()
    
    // MARK: - 依赖
    
    private let pendingUploadRegistry: PendingUploadRegistry
    private let databaseService: DatabaseService
    
    // MARK: - 状态
    
    /// 当前活跃编辑的笔记 ID
    private var activeEditingNoteId: String?
    
    /// 上传防抖任务
    private var uploadDebounceTask: Task<Void, Never>?
    
    /// 上传防抖间隔（秒）
    private let uploadDebounceInterval: TimeInterval = 1.0
    
    /// 待上传的笔记（防抖期间累积）
    private var pendingUploadNote: Note?
    
    // MARK: - 初始化
    
    private init(
        pendingUploadRegistry: PendingUploadRegistry = .shared,
        databaseService: DatabaseService = .shared
    ) {
        self.pendingUploadRegistry = pendingUploadRegistry
        self.databaseService = databaseService
        print("[NoteOperationCoordinator] ✅ 初始化完成")
    }
    
    // MARK: - 保存操作

    
    /// 保存笔记（本地 + 触发上传）
    /// 
    /// 执行流程：
    /// 1. 本地保存到数据库
    /// 2. 注册到 PendingUploadRegistry
    /// 3. 触发防抖上传
    /// 
    /// - Parameter note: 要保存的笔记
    /// - Returns: 保存结果
    /// 
    /// **需求覆盖**：
    /// - 需求 1.1: 本地保存后注册到 PendingUploadRegistry
    /// - 需求 4.1: 触发上传
    public func saveNote(_ note: Note) async -> SaveResult {
        let timestamp = Date()
        
        // 1. 本地保存到数据库
        do {
            try databaseService.saveNote(note)
            print("[NoteOperationCoordinator] 💾 本地保存成功: \(note.id.prefix(8))...")
        } catch {
            print("[NoteOperationCoordinator] ❌ 本地保存失败: \(error)")
            return .failure(NoteOperationError.saveFailed(error.localizedDescription))
        }
        
        // 2. 注册到 PendingUploadRegistry
        pendingUploadRegistry.register(noteId: note.id, timestamp: timestamp)
        
        // 3. 触发防抖上传
        scheduleUpload(note: note)
        
        return .success
    }
    
    /// 立即保存（切换笔记时调用）
    /// 
    /// 取消防抖，立即执行本地保存和上传
    /// 
    /// - Parameter note: 要保存的笔记
    /// 
    /// **需求覆盖**：
    /// - 需求 3.3: 切换笔记时立即保存
    public func saveNoteImmediately(_ note: Note) async throws {
        let timestamp = Date()
        
        // 取消防抖任务
        uploadDebounceTask?.cancel()
        uploadDebounceTask = nil
        pendingUploadNote = nil
        
        // 1. 本地保存到数据库
        do {
            try databaseService.saveNote(note)
            print("[NoteOperationCoordinator] 💾 立即保存成功: \(note.id.prefix(8))...")
        } catch {
            print("[NoteOperationCoordinator] ❌ 立即保存失败: \(error)")
            throw NoteOperationError.saveFailed(error.localizedDescription)
        }
        
        // 2. 注册到 PendingUploadRegistry
        pendingUploadRegistry.register(noteId: note.id, timestamp: timestamp)
        
        // 3. 立即触发上传（不等待防抖）
        await triggerUpload(note: note)
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
    /// 
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - cloudTimestamp: 云端时间戳
    /// - Returns: 是否可以更新
    /// 
    /// **需求覆盖**：
    /// - 需求 2.1: 检查是否在 PendingUploadRegistry 中
    /// - 需求 2.2: 检查是否正在编辑
    /// - 需求 2.3: 比较时间戳
    public func canSyncUpdateNote(_ noteId: String, cloudTimestamp: Date) -> Bool {
        // 1. 检查是否正在编辑
        if isNoteActivelyEditing(noteId) {
            print("[NoteOperationCoordinator] 🛡️ 同步保护: 笔记正在编辑 \(noteId.prefix(8))...")
            return false
        }
        
        // 2. 检查是否在待上传列表中
        if pendingUploadRegistry.isRegistered(noteId) {
            // 比较时间戳
            if let localTimestamp = pendingUploadRegistry.getLocalSaveTimestamp(noteId) {
                if localTimestamp >= cloudTimestamp {
                    print("[NoteOperationCoordinator] 🛡️ 同步保护: 本地较新 \(noteId.prefix(8))... (本地: \(localTimestamp), 云端: \(cloudTimestamp))")
                    return false
                }
            }
            // 即使云端较新，但笔记在待上传列表中，也应该跳过（用户优先策略）
            print("[NoteOperationCoordinator] 🛡️ 同步保护: 待上传中 \(noteId.prefix(8))...")
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
        // 1. 检查是否正在编辑
        if isNoteActivelyEditing(noteId) {
            print("[NoteOperationCoordinator] ⚔️ 冲突解决: 正在编辑，保留本地 \(noteId.prefix(8))...")
            return .keepLocal
        }
        
        // 2. 检查是否在待上传列表中
        if pendingUploadRegistry.isRegistered(noteId) {
            if let localTimestamp = pendingUploadRegistry.getLocalSaveTimestamp(noteId) {
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
        
        // 3. 不在待上传列表中，使用云端内容
        print("[NoteOperationCoordinator] ⚔️ 冲突解决: 使用云端 \(noteId.prefix(8))...")
        return .useCloud
    }
    
    // MARK: - 上传调度
    
    /// 调度上传（带防抖）
    /// 
    /// 使用防抖机制合并连续的保存操作
    /// 
    /// - Parameter note: 要上传的笔记
    /// 
    /// **需求覆盖**：
    /// - 需求 4.2: 1 秒内开始上传
    /// - 需求 4.3: 防抖机制合并上传请求
    private func scheduleUpload(note: Note) {
        // 更新待上传笔记
        pendingUploadNote = note
        
        // 取消之前的防抖任务
        uploadDebounceTask?.cancel()
        
        // 创建新的防抖任务
        uploadDebounceTask = Task { [weak self] in
            do {
                // 等待防抖间隔
                try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * (self?.uploadDebounceInterval ?? 1.0)))
                
                // 检查任务是否被取消
                guard !Task.isCancelled else { return }
                
                // 执行上传
                if let pendingNote = await self?.pendingUploadNote {
                    await self?.triggerUpload(note: pendingNote)
                }
            } catch {
                // Task.sleep 被取消，忽略
            }
        }
        
        print("[NoteOperationCoordinator] ⏱️ 调度上传（防抖）: \(note.id.prefix(8))...")
    }
    
    /// 触发上传
    /// 
    /// 实际执行上传操作
    /// 
    /// - Parameter note: 要上传的笔记
    private func triggerUpload(note: Note) async {
        print("[NoteOperationCoordinator] 🚀 触发上传: \(note.id.prefix(8))...")
        
        // 清除待上传笔记
        pendingUploadNote = nil
        
        // 检查网络状态
        let isOnline = await MainActor.run { NetworkMonitor.shared.isConnected }
        
        if isOnline {
            // 网络可用，添加到离线队列（由 OfflineOperationProcessor 处理上传）
            do {
                let noteData = try JSONEncoder().encode(note)
                let operation = OfflineOperation(
                    type: .updateNote,
                    noteId: note.id,
                    data: noteData,
                    priority: OfflineOperation.calculatePriority(for: .updateNote)
                )
                try OfflineOperationQueue.shared.addOperation(operation)
                print("[NoteOperationCoordinator] 📤 已添加到上传队列: \(note.id.prefix(8))...")
            } catch {
                print("[NoteOperationCoordinator] ❌ 添加到上传队列失败: \(error)")
            }
        } else {
            // 网络不可用，添加到离线队列等待网络恢复
            do {
                let noteData = try JSONEncoder().encode(note)
                let operation = OfflineOperation(
                    type: .updateNote,
                    noteId: note.id,
                    data: noteData,
                    priority: OfflineOperation.calculatePriority(for: .updateNote)
                )
                try OfflineOperationQueue.shared.addOperation(operation)
                print("[NoteOperationCoordinator] 📴 网络不可用，已添加到离线队列: \(note.id.prefix(8))...")
            } catch {
                print("[NoteOperationCoordinator] ❌ 添加到离线队列失败: \(error)")
            }
        }
    }
    
    // MARK: - 上传完成回调
    
    /// 上传成功回调
    /// 
    /// 由 OfflineOperationProcessor 在上传成功后调用
    /// 
    /// - Parameter noteId: 笔记 ID
    /// 
    /// **需求覆盖**：
    /// - 需求 1.2: 上传成功后从 PendingUploadRegistry 移除
    public func onUploadSuccess(noteId: String) {
        pendingUploadRegistry.unregister(noteId: noteId)
        print("[NoteOperationCoordinator] ✅ 上传成功，已注销: \(noteId.prefix(8))...")
    }
    
    /// 上传失败回调
    /// 
    /// 由 OfflineOperationProcessor 在上传失败后调用
    /// 
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - error: 错误信息
    /// 
    /// **需求覆盖**：
    /// - 需求 1.3: 上传失败时保留在 PendingUploadRegistry 中
    public func onUploadFailure(noteId: String, error: Error) {
        // 保留在 PendingUploadRegistry 中，等待重试
        print("[NoteOperationCoordinator] ❌ 上传失败，保留待上传状态: \(noteId.prefix(8))..., 错误: \(error)")
    }
    
    // MARK: - 测试辅助方法
    
    /// 重置状态（仅用于测试）
    public func resetForTesting() {
        activeEditingNoteId = nil
        uploadDebounceTask?.cancel()
        uploadDebounceTask = nil
        pendingUploadNote = nil
        print("[NoteOperationCoordinator] 🧪 测试重置完成")
    }
}
