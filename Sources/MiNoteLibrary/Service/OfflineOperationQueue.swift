import Foundation

/// 离线操作类型
public enum OfflineOperationType: String, Codable, Sendable {
    case createNote
    case updateNote
    case deleteNote
    case uploadImage
    case createFolder
    case renameFolder
    case deleteFolder
}

/// 离线操作状态
public enum OfflineOperationStatus: String, Codable, Sendable {
    case pending = "pending"      // 待处理
    case processing = "processing" // 处理中
    case completed = "completed"  // 已完成
    case failed = "failed"        // 失败
}

/// 离线操作
public struct OfflineOperation: Codable, Identifiable, Sendable {
    public let id: String
    public let type: OfflineOperationType
    public let noteId: String // 对于文件夹操作，这个字段存储 folderId
    public let data: Data // JSON 编码的操作数据
    public let timestamp: Date
    public var priority: Int // 优先级（数字越大优先级越高）
    public var retryCount: Int // 重试次数
    public var lastError: String? // 最后错误信息
    public var status: OfflineOperationStatus // 操作状态
    
    init(
        id: String = UUID().uuidString,
        type: OfflineOperationType,
        noteId: String,
        data: Data,
        timestamp: Date = Date(),
        priority: Int = 0,
        retryCount: Int = 0,
        lastError: String? = nil,
        status: OfflineOperationStatus = .pending
    ) {
        self.id = id
        self.type = type
        self.noteId = noteId
        self.data = data
        self.timestamp = timestamp
        self.priority = priority
        self.retryCount = retryCount
        self.lastError = lastError
        self.status = status
    }
    
    /// 计算操作优先级（基于操作类型）
    public static func calculatePriority(for type: OfflineOperationType) -> Int {
        switch type {
        case .deleteNote, .deleteFolder:
            return 3 // 高优先级
        case .updateNote, .renameFolder:
            return 2 // 中优先级
        case .createNote, .createFolder, .uploadImage:
            return 1 // 低优先级
        }
    }
}

/// 离线操作队列管理器
/// 
/// 使用数据库存储离线操作，支持优先级、重试、状态管理等功能
final class OfflineOperationQueue: @unchecked Sendable {
    static let shared = OfflineOperationQueue()
    
    private let databaseService = DatabaseService.shared
    private let queue = DispatchQueue(label: "OfflineOperationQueue", attributes: .concurrent)
    private var hasMigrated = false // 标记是否已执行迁移
    
    private init() {
        // 在初始化时执行一次迁移（从 UserDefaults 到数据库）
        migrateFromUserDefaultsIfNeeded()
    }
    
    /// 添加离线操作
    /// 
    /// 在添加前会执行去重和合并逻辑，避免冗余操作
    /// 
    /// - Parameter operation: 要添加的操作
    /// - Throws: DatabaseError（数据库操作失败）
    func addOperation(_ operation: OfflineOperation) throws {
        try queue.sync(flags: .barrier) {
            // 确保优先级已设置（如果没有设置，使用默认优先级）
            var operationToAdd = operation
            if operationToAdd.priority == 0 {
                operationToAdd.priority = OfflineOperation.calculatePriority(for: operation.type)
            }
            
            // 执行去重和合并
            do {
                let deduplicated = try deduplicateAndMerge(operationToAdd)
                try databaseService.addOfflineOperation(deduplicated)
                print("[OfflineQueue] 添加离线操作: \(deduplicated.type.rawValue), noteId: \(deduplicated.noteId), priority: \(deduplicated.priority)")
            } catch let error as NSError where error.domain == "OfflineOperationQueue" && error.code == 0 {
                // 操作已合并，不需要添加
                print("[OfflineQueue] 操作已合并: \(operation.type.rawValue), noteId: \(operation.noteId)")
            }
        }
    }
    
    /// 去重和合并操作
    /// 
    /// 根据操作类型和笔记ID，合并或替换现有操作
    /// 
    /// - Parameter newOperation: 新操作
    /// - Returns: 去重和合并后的操作
    /// - Throws: DatabaseError（数据库操作失败）或合并错误
    private func deduplicateAndMerge(_ newOperation: OfflineOperation) throws -> OfflineOperation {
        let existingOperations = try databaseService.getAllOfflineOperations()
        
        // 查找同一笔记的现有待处理操作
        let sameNoteOps = existingOperations.filter { 
            $0.noteId == newOperation.noteId && 
            ($0.status == .pending || $0.status == .failed)
        }
        
        guard !sameNoteOps.isEmpty else {
            // 没有现有操作，直接返回新操作
            return newOperation
        }
        
        // 根据操作类型执行合并逻辑
        switch newOperation.type {
        case .createNote:
            // 如果已有创建或更新操作，合并为新操作（使用最新内容）
            if let existing = sameNoteOps.first(where: { $0.type == .createNote || $0.type == .updateNote }) {
                // 删除旧操作
                try databaseService.deleteOfflineOperation(operationId: existing.id)
                // 合并：使用新操作的数据（应该包含最新内容）
                return newOperation
            }
            // 如果有删除操作，删除两个操作（创建+删除 = 无操作）
            if sameNoteOps.contains(where: { $0.type == .deleteNote }) {
                for op in sameNoteOps {
                    try databaseService.deleteOfflineOperation(operationId: op.id)
                }
                throw NSError(domain: "OfflineOperationQueue", code: 0, userInfo: [NSLocalizedDescriptionKey: "操作已合并（创建+删除）"])
            }
            
        case .updateNote:
            // 如果已有创建操作，合并到创建操作中（更新创建操作的数据）
            if let existing = sameNoteOps.first(where: { $0.type == .createNote }) {
                // 删除旧操作
                try databaseService.deleteOfflineOperation(operationId: existing.id)
                // 合并为创建操作，但使用新操作的数据
                let merged = OfflineOperation(
                    id: newOperation.id,
                    type: .createNote,
                    noteId: newOperation.noteId,
                    data: newOperation.data,
                    timestamp: newOperation.timestamp,
                    priority: newOperation.priority,
                    retryCount: newOperation.retryCount,
                    lastError: newOperation.lastError,
                    status: newOperation.status
                )
                return merged
            }
            // 如果已有更新操作，只保留最新的
            if let existing = sameNoteOps.first(where: { $0.type == .updateNote }) {
                if newOperation.timestamp > existing.timestamp {
                    // 新操作更新，删除旧操作
                    try databaseService.deleteOfflineOperation(operationId: existing.id)
                    return newOperation
                } else {
                    // 旧操作更新，忽略新操作
                    throw NSError(domain: "OfflineOperationQueue", code: 0, userInfo: [NSLocalizedDescriptionKey: "操作已合并（保留更新的操作）"])
                }
            }
            // 如果有删除操作，只保留删除操作
            if sameNoteOps.contains(where: { $0.type == .deleteNote }) {
                throw NSError(domain: "OfflineOperationQueue", code: 0, userInfo: [NSLocalizedDescriptionKey: "操作已合并（更新+删除 = 删除）"])
            }
            
        case .deleteNote:
            // 删除操作会清除所有之前的操作
            for op in sameNoteOps {
                try databaseService.deleteOfflineOperation(operationId: op.id)
            }
            return newOperation
            
        case .createFolder, .renameFolder, .deleteFolder:
            // 文件夹操作的合并逻辑类似
            if newOperation.type == .deleteFolder {
                // 删除操作会清除所有之前的操作
                for op in sameNoteOps {
                    try databaseService.deleteOfflineOperation(operationId: op.id)
                }
                return newOperation
            }
            // 对于创建和重命名，只保留最新的
            if let existing = sameNoteOps.first(where: { $0.type == newOperation.type }) {
                if newOperation.timestamp > existing.timestamp {
                    try databaseService.deleteOfflineOperation(operationId: existing.id)
                    return newOperation
                } else {
                    throw NSError(domain: "OfflineOperationQueue", code: 0, userInfo: [NSLocalizedDescriptionKey: "操作已合并（保留更新的操作）"])
                }
            }
            
        case .uploadImage:
            // 图片上传操作通常不需要去重，可以多次上传
            break
        }
        
        return newOperation
    }
    
    /// 移除操作
    /// 
    /// - Parameter operationId: 要移除的操作ID
    /// - Throws: DatabaseError（数据库操作失败）
    func removeOperation(_ operationId: String) throws {
        try queue.sync(flags: .barrier) {
            try databaseService.deleteOfflineOperation(operationId: operationId)
            print("[OfflineQueue] 移除离线操作: \(operationId)")
        }
    }
    
    /// 获取所有待处理的操作
    /// 
    /// 返回状态为 pending 或 failed 的操作，按优先级和时间排序
    /// 
    /// - Returns: 待处理的操作数组
    func getPendingOperations() -> [OfflineOperation] {
        return queue.sync {
            do {
                let allOperations = try databaseService.getAllOfflineOperations()
                // 只返回待处理或失败的操作
                return allOperations.filter { $0.status == .pending || $0.status == .failed }
            } catch {
                print("[OfflineQueue] ❌ 获取待处理操作失败: \(error)")
                return []
            }
        }
    }
    
    /// 获取所有操作（包括已完成和失败的操作）
    /// 
    /// - Returns: 所有操作数组
    func getAllOperations() -> [OfflineOperation] {
        return queue.sync {
            do {
                return try databaseService.getAllOfflineOperations()
            } catch {
                print("[OfflineQueue] ❌ 获取所有操作失败: \(error)")
                return []
            }
        }
    }
    
    /// 清空所有操作
    /// 
    /// - Throws: DatabaseError（数据库操作失败）
    func clearAll() throws {
        try queue.sync(flags: .barrier) {
            try databaseService.clearAllOfflineOperations()
            print("[OfflineQueue] 清空所有离线操作")
        }
    }
    
    /// 更新操作状态
    /// 
    /// - Parameters:
    ///   - operationId: 操作ID
    ///   - status: 新状态
    ///   - error: 错误信息（如果状态为 failed）
    /// - Throws: DatabaseError（数据库操作失败）
    func updateOperationStatus(operationId: String, status: OfflineOperationStatus, error: String? = nil) throws {
        try queue.sync(flags: .barrier) {
            // 获取现有操作
            let allOperations = try databaseService.getAllOfflineOperations()
            guard var operation = allOperations.first(where: { $0.id == operationId }) else {
                throw NSError(domain: "OfflineOperationQueue", code: 404, userInfo: [NSLocalizedDescriptionKey: "操作不存在"])
            }
            
            // 更新状态和错误信息
            operation.status = status
            if let error = error {
                operation.lastError = error
            }
            if status == .failed {
                operation.retryCount += 1
            }
            
            // 保存回数据库
            try databaseService.addOfflineOperation(operation)
            print("[OfflineQueue] 更新操作状态: \(operationId), status: \(status.rawValue)")
        }
    }
    
    // MARK: - 数据迁移
    
    /// 从 UserDefaults 迁移数据到数据库（如果需要）
    /// 
    /// 只在首次启动时执行一次，迁移成功后清除 UserDefaults 数据
    private func migrateFromUserDefaultsIfNeeded() {
        queue.async(flags: .barrier) {
            // 检查是否已迁移
            let migrationKey = "offline_operations_migrated_to_database"
            if UserDefaults.standard.bool(forKey: migrationKey) {
                self.hasMigrated = true
                return
            }
            
            // 检查 UserDefaults 中是否有数据
            guard let data = UserDefaults.standard.data(forKey: "offline_operations"),
                  let operations = try? JSONDecoder().decode([OfflineOperation].self, from: data),
                  !operations.isEmpty else {
                // 没有旧数据，标记为已迁移
                UserDefaults.standard.set(true, forKey: migrationKey)
                self.hasMigrated = true
                print("[OfflineQueue] 没有需要迁移的数据")
                return
            }
            
            // 迁移数据到数据库
            print("[OfflineQueue] 开始迁移 \(operations.count) 个操作从 UserDefaults 到数据库")
            do {
                for operation in operations {
                    // 确保优先级已设置
                    var operationToMigrate = operation
                    if operationToMigrate.priority == 0 {
                        operationToMigrate.priority = OfflineOperation.calculatePriority(for: operation.type)
                    }
                    // 确保状态为 pending
                    if operationToMigrate.status != .pending && operationToMigrate.status != .failed {
                        operationToMigrate.status = .pending
                    }
                    
                    try self.databaseService.addOfflineOperation(operationToMigrate)
                }
                
                // 迁移成功，清除 UserDefaults 数据并标记
                UserDefaults.standard.removeObject(forKey: "offline_operations")
                UserDefaults.standard.set(true, forKey: migrationKey)
                self.hasMigrated = true
                print("[OfflineQueue] ✅ 成功迁移 \(operations.count) 个操作到数据库")
            } catch {
                print("[OfflineQueue] ❌ 迁移失败: \(error)")
                // 迁移失败时不标记，下次启动时重试
            }
        }
    }
}

