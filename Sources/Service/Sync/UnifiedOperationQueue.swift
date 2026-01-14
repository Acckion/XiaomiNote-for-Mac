import Foundation

// MARK: - 统一操作队列

/// 统一操作队列
///
/// 合并 SaveQueueManager、PendingUploadRegistry、OfflineOperationQueue 的功能，
/// 提供统一的操作管理接口。
///
/// 主要功能：
/// - 操作入队和去重合并
/// - 状态管理（pending、processing、completed、failed）
/// - 重试调度
/// - 查询和统计
///
/// 线程安全：使用 NSLock 确保所有操作的线程安全
///
/// 需求: 1.1
public final class UnifiedOperationQueue: @unchecked Sendable {
    
    // MARK: - 单例
    
    /// 共享实例
    public static let shared = UnifiedOperationQueue()
    
    // MARK: - 依赖
    
    /// 数据库服务
    private let databaseService: DatabaseService
    
    // MARK: - 线程安全
    
    /// 操作锁，确保线程安全
    private let lock = NSLock()
    
    // MARK: - 内存缓存
    
    /// 操作缓存（按 ID 索引）
    private var operationsById: [String: NoteOperation] = [:]
    
    /// 操作缓存（按笔记 ID 索引）
    private var operationsByNoteId: [String: [NoteOperation]] = [:]
    
    // MARK: - 初始化
    
    /// 私有初始化方法（单例模式）
    private init() {
        self.databaseService = DatabaseService.shared
        loadFromDatabase()
    }
    
    /// 用于测试的初始化方法
    ///
    /// - Parameter databaseService: 数据库服务实例
    internal init(databaseService: DatabaseService) {
        self.databaseService = databaseService
        loadFromDatabase()
    }
    
    // MARK: - 数据库加载
    
    /// 从数据库加载所有待处理操作
    ///
    /// 需求: 1.1 - 系统初始化时从数据库恢复所有待处理操作
    private func loadFromDatabase() {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            let operations = try databaseService.getAllUnifiedOperations()
            
            // 重建内存缓存
            operationsById.removeAll()
            operationsByNoteId.removeAll()
            
            for operation in operations {
                operationsById[operation.id] = operation
                
                if operationsByNoteId[operation.noteId] == nil {
                    operationsByNoteId[operation.noteId] = []
                }
                operationsByNoteId[operation.noteId]?.append(operation)
            }
            
            print("[UnifiedOperationQueue] 从数据库加载了 \(operations.count) 个操作")
        } catch {
            print("[UnifiedOperationQueue] 从数据库加载操作失败: \(error)")
        }
    }
    
    // MARK: - 缓存管理
    
    /// 添加操作到缓存
    private func addToCache(_ operation: NoteOperation) {
        operationsById[operation.id] = operation
        
        if operationsByNoteId[operation.noteId] == nil {
            operationsByNoteId[operation.noteId] = []
        }
        operationsByNoteId[operation.noteId]?.append(operation)
    }
    
    /// 从缓存移除操作
    private func removeFromCache(_ operationId: String) {
        guard let operation = operationsById[operationId] else { return }
        
        operationsById.removeValue(forKey: operationId)
        operationsByNoteId[operation.noteId]?.removeAll { $0.id == operationId }
        
        // 如果该笔记没有操作了，移除整个条目
        if operationsByNoteId[operation.noteId]?.isEmpty == true {
            operationsByNoteId.removeValue(forKey: operation.noteId)
        }
    }
    
    /// 更新缓存中的操作
    private func updateInCache(_ operation: NoteOperation) {
        let oldOperation = operationsById[operation.id]
        operationsById[operation.id] = operation
        
        // 如果笔记 ID 变了，需要更新 operationsByNoteId
        if let old = oldOperation, old.noteId != operation.noteId {
            operationsByNoteId[old.noteId]?.removeAll { $0.id == operation.id }
            if operationsByNoteId[old.noteId]?.isEmpty == true {
                operationsByNoteId.removeValue(forKey: old.noteId)
            }
            
            if operationsByNoteId[operation.noteId] == nil {
                operationsByNoteId[operation.noteId] = []
            }
            operationsByNoteId[operation.noteId]?.append(operation)
        } else {
            // 笔记 ID 没变，只更新操作
            if let index = operationsByNoteId[operation.noteId]?.firstIndex(where: { $0.id == operation.id }) {
                operationsByNoteId[operation.noteId]?[index] = operation
            }
        }
    }
}


// MARK: - 操作入队

extension UnifiedOperationQueue {
    
    /// 添加操作到队列
    ///
    /// 自动执行去重合并逻辑，并持久化到数据库。
    ///
    /// - Parameter operation: 要添加的操作
    /// - Returns: 实际添加的操作（可能经过合并处理），如果操作被忽略则返回 nil
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    /// 需求: 1.2, 3.1
    @discardableResult
    public func enqueue(_ operation: NoteOperation) throws -> NoteOperation? {
        lock.lock()
        defer { lock.unlock() }
        
        // 执行去重合并逻辑
        guard let finalOperation = try deduplicateAndMerge(operation) else {
            print("[UnifiedOperationQueue] 操作被忽略: \(operation.type.rawValue) for \(operation.noteId)")
            return nil
        }
        
        // 持久化到数据库
        try databaseService.saveUnifiedOperation(finalOperation)
        
        // 更新内存缓存
        addToCache(finalOperation)
        
        print("[UnifiedOperationQueue] 入队操作: \(finalOperation.type.rawValue) for \(finalOperation.noteId), id: \(finalOperation.id)")
        
        return finalOperation
    }
    
    /// 批量添加操作到队列
    ///
    /// - Parameter operations: 要添加的操作数组
    /// - Returns: 实际添加的操作数组
    /// - Throws: DatabaseError（数据库操作失败）
    public func enqueueBatch(_ operations: [NoteOperation]) throws -> [NoteOperation] {
        var results: [NoteOperation] = []
        
        for operation in operations {
            if let result = try enqueue(operation) {
                results.append(result)
            }
        }
        
        return results
    }
}


// MARK: - 去重合并逻辑

extension UnifiedOperationQueue {
    
    /// 去重合并逻辑
    ///
    /// 根据操作类型执行不同的合并策略：
    /// - noteCreate: 最高优先级，不合并
    /// - cloudUpload: 合并为最新的操作
    /// - cloudDelete: 清除该笔记的所有其他待处理操作
    /// - imageUpload: 不去重
    /// - 文件夹操作: 只保留最新的同类型操作
    ///
    /// - Parameter newOperation: 新操作
    /// - Returns: 处理后的操作，如果应该忽略则返回 nil
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    /// 需求: 3.2, 3.3, 3.4
    private func deduplicateAndMerge(_ newOperation: NoteOperation) throws -> NoteOperation? {
        // 获取该笔记的所有待处理操作
        let existingOperations = operationsByNoteId[newOperation.noteId]?.filter { 
            $0.status == .pending || $0.status == .failed 
        } ?? []
        
        switch newOperation.type {
        case .noteCreate:
            // noteCreate 优先级最高，不合并
            // 如果已有 noteCreate，忽略新的
            if existingOperations.contains(where: { $0.type == .noteCreate }) {
                print("[UnifiedOperationQueue] 已存在 noteCreate 操作，忽略新的")
                return nil
            }
            return newOperation
            
        case .cloudUpload:
            // 如果已有上传操作，合并为最新的
            if let existingUpload = existingOperations.first(where: { $0.type == .cloudUpload }) {
                // 删除旧操作
                try removeOperation(existingUpload.id)
                print("[UnifiedOperationQueue] 合并 cloudUpload 操作: 删除旧操作 \(existingUpload.id)")
            }
            
            // 如果有删除操作，忽略上传
            if existingOperations.contains(where: { $0.type == .cloudDelete }) {
                print("[UnifiedOperationQueue] 存在 cloudDelete 操作，忽略 cloudUpload")
                return nil
            }
            
            return newOperation
            
        case .cloudDelete:
            // 删除操作清除所有其他操作
            for op in existingOperations {
                // 如果有 noteCreate 操作，说明是离线创建后又删除
                // 两个操作都删除（需求 3.4）
                if op.type == .noteCreate {
                    try removeOperation(op.id)
                    print("[UnifiedOperationQueue] 离线创建后删除，取消 noteCreate 操作: \(op.id)")
                    // 返回 nil，不需要 cloudDelete（因为云端没有这个笔记）
                    return nil
                }
                
                try removeOperation(op.id)
                print("[UnifiedOperationQueue] cloudDelete 清除操作: \(op.id)")
            }
            return newOperation
            
        case .imageUpload:
            // 图片上传不去重
            return newOperation
            
        case .folderCreate, .folderRename, .folderDelete:
            // 文件夹操作：只保留最新的同类型操作
            if let existingOp = existingOperations.first(where: { $0.type == newOperation.type }) {
                try removeOperation(existingOp.id)
                print("[UnifiedOperationQueue] 合并文件夹操作: 删除旧操作 \(existingOp.id)")
            }
            
            // 如果是删除操作，清除其他文件夹操作
            if newOperation.type == .folderDelete {
                for op in existingOperations where op.type != .folderDelete {
                    try removeOperation(op.id)
                    print("[UnifiedOperationQueue] folderDelete 清除操作: \(op.id)")
                }
            }
            
            return newOperation
        }
    }
    
    /// 移除操作（内部方法，不加锁）
    ///
    /// - Parameter operationId: 操作 ID
    /// - Throws: DatabaseError（数据库操作失败）
    private func removeOperation(_ operationId: String) throws {
        try databaseService.deleteUnifiedOperation(operationId: operationId)
        removeFromCache(operationId)
    }
}


// MARK: - 状态更新

extension UnifiedOperationQueue {
    
    /// 标记操作为处理中
    ///
    /// - Parameter operationId: 操作 ID
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    /// 需求: 1.3
    public func markProcessing(_ operationId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard var operation = operationsById[operationId] else {
            print("[UnifiedOperationQueue] 操作不存在: \(operationId)")
            return
        }
        
        operation.status = .processing
        
        try databaseService.saveUnifiedOperation(operation)
        updateInCache(operation)
        
        print("[UnifiedOperationQueue] 标记操作为处理中: \(operationId)")
    }
    
    /// 标记操作完成
    ///
    /// 完成的操作会从队列中移除。
    ///
    /// - Parameter operationId: 操作 ID
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    /// 需求: 1.3
    public func markCompleted(_ operationId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard let operation = operationsById[operationId] else {
            print("[UnifiedOperationQueue] 操作不存在: \(operationId)")
            return
        }
        
        // 从数据库和缓存中移除
        try databaseService.deleteUnifiedOperation(operationId: operationId)
        removeFromCache(operationId)
        
        print("[UnifiedOperationQueue] 标记操作完成并移除: \(operationId), type: \(operation.type.rawValue)")
    }
    
    /// 标记操作失败
    ///
    /// - Parameters:
    ///   - operationId: 操作 ID
    ///   - error: 错误信息
    ///   - errorType: 错误类型
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    /// 需求: 1.3
    public func markFailed(_ operationId: String, error: Error, errorType: OperationErrorType) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard var operation = operationsById[operationId] else {
            print("[UnifiedOperationQueue] 操作不存在: \(operationId)")
            return
        }
        
        operation.status = .failed
        operation.lastError = error.localizedDescription
        operation.errorType = errorType
        operation.retryCount += 1
        
        // 检查是否超过最大重试次数
        let maxRetryCount = 5
        if operation.retryCount >= maxRetryCount {
            operation.status = .maxRetryExceeded
            print("[UnifiedOperationQueue] 操作超过最大重试次数: \(operationId)")
        }
        
        // 如果是认证错误，标记为 authFailed
        if errorType == .authExpired {
            operation.status = .authFailed
            print("[UnifiedOperationQueue] 操作认证失败: \(operationId)")
        }
        
        try databaseService.saveUnifiedOperation(operation)
        updateInCache(operation)
        
        print("[UnifiedOperationQueue] 标记操作失败: \(operationId), error: \(error.localizedDescription), type: \(errorType.rawValue)")
    }
    
    /// 标记操作失败（简化版本）
    ///
    /// - Parameters:
    ///   - operationId: 操作 ID
    ///   - errorMessage: 错误信息
    ///   - errorType: 错误类型
    /// - Throws: DatabaseError（数据库操作失败）
    public func markFailed(_ operationId: String, errorMessage: String, errorType: OperationErrorType) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard var operation = operationsById[operationId] else {
            print("[UnifiedOperationQueue] 操作不存在: \(operationId)")
            return
        }
        
        operation.status = .failed
        operation.lastError = errorMessage
        operation.errorType = errorType
        operation.retryCount += 1
        
        // 检查是否超过最大重试次数
        let maxRetryCount = 5
        if operation.retryCount >= maxRetryCount {
            operation.status = .maxRetryExceeded
        }
        
        // 如果是认证错误，标记为 authFailed
        if errorType == .authExpired {
            operation.status = .authFailed
        }
        
        try databaseService.saveUnifiedOperation(operation)
        updateInCache(operation)
        
        print("[UnifiedOperationQueue] 标记操作失败: \(operationId), error: \(errorMessage)")
    }
}


// MARK: - 查询方法

extension UnifiedOperationQueue {
    
    /// 获取所有待处理操作
    ///
    /// 返回状态为 pending 或 failed 的操作，按优先级降序、创建时间升序排列。
    ///
    /// - Returns: 待处理操作数组
    ///
    /// 需求: 1.4
    public func getPendingOperations() -> [NoteOperation] {
        lock.lock()
        defer { lock.unlock() }
        
        return operationsById.values
            .filter { $0.status == .pending || $0.status == .failed }
            .sorted { 
                if $0.priority != $1.priority {
                    return $0.priority > $1.priority
                }
                return $0.createdAt < $1.createdAt
            }
    }
    
    /// 获取指定笔记的待处理上传操作
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 待处理的上传操作，如果没有则返回 nil
    ///
    /// 需求: 4.1
    public func getPendingUpload(for noteId: String) -> NoteOperation? {
        lock.lock()
        defer { lock.unlock() }
        
        return operationsByNoteId[noteId]?.first { 
            $0.type == .cloudUpload && ($0.status == .pending || $0.status == .failed)
        }
    }
    
    /// 检查笔记是否有待处理上传
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 如果有待处理上传返回 true
    ///
    /// 需求: 4.1
    public func hasPendingUpload(for noteId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return operationsByNoteId[noteId]?.contains { 
            ($0.type == .cloudUpload || $0.type == .noteCreate) && 
            ($0.status == .pending || $0.status == .failed || $0.status == .processing)
        } ?? false
    }
    
    /// 获取本地保存时间戳
    ///
    /// 返回该笔记最新的本地保存时间戳。
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 本地保存时间戳，如果没有则返回 nil
    ///
    /// 需求: 4.1
    public func getLocalSaveTimestamp(for noteId: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        
        // 获取该笔记的所有待处理操作中最新的本地保存时间戳
        return operationsByNoteId[noteId]?
            .filter { $0.status == .pending || $0.status == .failed || $0.status == .processing }
            .compactMap { $0.localSaveTimestamp }
            .max()
    }
    
    /// 获取指定笔记的所有待处理操作
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 该笔记的待处理操作数组
    public func getOperations(for noteId: String) -> [NoteOperation] {
        lock.lock()
        defer { lock.unlock() }
        
        return operationsByNoteId[noteId]?.filter { 
            $0.status == .pending || $0.status == .failed 
        } ?? []
    }
    
    /// 获取指定操作
    ///
    /// - Parameter operationId: 操作 ID
    /// - Returns: 操作，如果不存在则返回 nil
    public func getOperation(_ operationId: String) -> NoteOperation? {
        lock.lock()
        defer { lock.unlock() }
        
        return operationsById[operationId]
    }
    
    /// 检查笔记是否有待处理的 noteCreate 操作
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 如果有待处理的 noteCreate 操作返回 true
    public func hasPendingNoteCreate(for noteId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return operationsByNoteId[noteId]?.contains { 
            $0.type == .noteCreate && 
            ($0.status == .pending || $0.status == .failed || $0.status == .processing)
        } ?? false
    }
}


// MARK: - 重试调度

extension UnifiedOperationQueue {
    
    /// 重试配置
    private enum RetryConfig {
        /// 基础重试延迟（秒）
        static let baseDelay: TimeInterval = 1.0
        /// 最大重试延迟（秒）
        static let maxDelay: TimeInterval = 60.0
        /// 最大重试次数
        static let maxRetryCount = 5
    }
    
    /// 安排重试
    ///
    /// 使用指数退避策略计算下次重试时间：1s, 2s, 4s, 8s, 16s, 32s, 60s
    ///
    /// - Parameters:
    ///   - operationId: 操作 ID
    ///   - delay: 可选的自定义延迟时间，如果不提供则自动计算
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    /// 需求: 5.2
    public func scheduleRetry(_ operationId: String, delay: TimeInterval? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard var operation = operationsById[operationId] else {
            print("[UnifiedOperationQueue] 操作不存在: \(operationId)")
            return
        }
        
        // 计算重试延迟
        let retryDelay = delay ?? calculateRetryDelay(retryCount: operation.retryCount)
        
        // 设置下次重试时间
        operation.nextRetryAt = Date().addingTimeInterval(retryDelay)
        operation.status = .failed
        
        try databaseService.saveUnifiedOperation(operation)
        updateInCache(operation)
        
        print("[UnifiedOperationQueue] 安排重试: \(operationId), 延迟 \(retryDelay) 秒, 下次重试时间: \(operation.nextRetryAt!)")
    }
    
    /// 计算重试延迟（指数退避）
    ///
    /// 延迟序列：1s, 2s, 4s, 8s, 16s, 32s, 60s, 60s...
    ///
    /// - Parameter retryCount: 当前重试次数
    /// - Returns: 延迟时间（秒）
    public func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        // delay = min(baseDelay * 2^retryCount, maxDelay)
        let delay = RetryConfig.baseDelay * pow(2.0, Double(retryCount))
        return min(delay, RetryConfig.maxDelay)
    }
    
    /// 获取需要重试的操作
    ///
    /// 返回状态为 failed 且已到达重试时间的操作。
    ///
    /// - Returns: 需要重试的操作数组
    ///
    /// 需求: 5.2
    public func getOperationsReadyForRetry() -> [NoteOperation] {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        
        return operationsById.values
            .filter { operation in
                guard operation.status == .failed else { return false }
                
                // 如果没有设置下次重试时间，立即重试
                guard let nextRetryAt = operation.nextRetryAt else { return true }
                
                // 检查是否已到达重试时间
                return now >= nextRetryAt
            }
            .sorted { 
                if $0.priority != $1.priority {
                    return $0.priority > $1.priority
                }
                return $0.createdAt < $1.createdAt
            }
    }
    
    /// 重置操作状态为待处理
    ///
    /// 用于手动触发重试。
    ///
    /// - Parameter operationId: 操作 ID
    /// - Throws: DatabaseError（数据库操作失败）
    public func resetToPending(_ operationId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard var operation = operationsById[operationId] else {
            print("[UnifiedOperationQueue] 操作不存在: \(operationId)")
            return
        }
        
        operation.status = .pending
        operation.nextRetryAt = nil
        operation.lastError = nil
        operation.errorType = nil
        
        try databaseService.saveUnifiedOperation(operation)
        updateInCache(operation)
        
        print("[UnifiedOperationQueue] 重置操作状态为待处理: \(operationId)")
    }
}


// MARK: - 统计方法

extension UnifiedOperationQueue {
    
    /// 获取待上传笔记数量
    ///
    /// 统计所有待处理的 cloudUpload 和 noteCreate 操作数量。
    ///
    /// - Returns: 待上传笔记数量
    ///
    /// 需求: 6.1
    public func getPendingUploadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        return operationsById.values.filter { 
            ($0.type == .cloudUpload || $0.type == .noteCreate) &&
            ($0.status == .pending || $0.status == .failed || $0.status == .processing)
        }.count
    }
    
    /// 获取所有待上传笔记 ID
    ///
    /// 返回所有有待处理上传操作的笔记 ID。
    ///
    /// - Returns: 笔记 ID 数组
    ///
    /// 需求: 6.1
    public func getAllPendingNoteIds() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        
        var noteIds = Set<String>()
        
        for operation in operationsById.values {
            if (operation.type == .cloudUpload || operation.type == .noteCreate) &&
               (operation.status == .pending || operation.status == .failed || operation.status == .processing) {
                noteIds.insert(operation.noteId)
            }
        }
        
        return Array(noteIds)
    }
    
    /// 获取队列统计信息
    ///
    /// - Returns: 统计信息字典
    public func getStatistics() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        
        var stats: [String: Int] = [
            "total": operationsById.count,
            "pending": 0,
            "processing": 0,
            "failed": 0,
            "authFailed": 0,
            "maxRetryExceeded": 0,
            "completed": 0
        ]
        
        for operation in operationsById.values {
            switch operation.status {
            case .pending:
                stats["pending", default: 0] += 1
            case .processing:
                stats["processing", default: 0] += 1
            case .failed:
                stats["failed", default: 0] += 1
            case .authFailed:
                stats["authFailed", default: 0] += 1
            case .maxRetryExceeded:
                stats["maxRetryExceeded", default: 0] += 1
            case .completed:
                stats["completed", default: 0] += 1
            }
        }
        
        // 按类型统计
        for type in OperationType.allCases {
            let count = operationsById.values.filter { $0.type == type }.count
            stats[type.rawValue] = count
        }
        
        return stats
    }
    
    /// 获取临时 ID 笔记数量
    ///
    /// - Returns: 使用临时 ID 的笔记数量
    public func getTemporaryIdNoteCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        var noteIds = Set<String>()
        
        for operation in operationsById.values {
            if operation.isLocalId {
                noteIds.insert(operation.noteId)
            }
        }
        
        return noteIds.count
    }
    
    /// 获取所有临时 ID 笔记
    ///
    /// - Returns: 临时 ID 数组
    public func getAllTemporaryNoteIds() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        
        var noteIds = Set<String>()
        
        for operation in operationsById.values {
            if operation.isLocalId {
                noteIds.insert(operation.noteId)
            }
        }
        
        return Array(noteIds)
    }
}

// MARK: - ID 更新

extension UnifiedOperationQueue {
    
    /// 更新所有引用临时 ID 的操作
    ///
    /// 当离线创建的笔记上传成功后，需要将临时 ID 更新为云端下发的正式 ID。
    ///
    /// - Parameters:
    ///   - oldNoteId: 旧的笔记 ID（临时 ID）
    ///   - newNoteId: 新的笔记 ID（正式 ID）
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    /// 需求: 8.6
    public func updateNoteIdInPendingOperations(oldNoteId: String, newNoteId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        // 获取该笔记的所有操作
        guard let operations = operationsByNoteId[oldNoteId] else {
            print("[UnifiedOperationQueue] 没有找到笔记 \(oldNoteId) 的操作")
            return
        }
        
        var updatedCount = 0
        
        for var operation in operations {
            // 更新笔记 ID
            operation.noteId = newNoteId
            operation.isLocalId = false
            
            // 更新数据库
            try databaseService.saveUnifiedOperation(operation)
            
            // 更新缓存
            operationsById[operation.id] = operation
            
            updatedCount += 1
        }
        
        // 更新 operationsByNoteId 索引
        if let ops = operationsByNoteId.removeValue(forKey: oldNoteId) {
            let updatedOps = ops.map { op -> NoteOperation in
                var updated = op
                updated.noteId = newNoteId
                updated.isLocalId = false
                return updated
            }
            
            if operationsByNoteId[newNoteId] == nil {
                operationsByNoteId[newNoteId] = updatedOps
            } else {
                operationsByNoteId[newNoteId]?.append(contentsOf: updatedOps)
            }
        }
        
        print("[UnifiedOperationQueue] 更新笔记 ID: \(oldNoteId) -> \(newNoteId), 影响了 \(updatedCount) 个操作")
    }
    
    /// 取消指定笔记的所有待处理操作
    ///
    /// 用于删除临时 ID 笔记时取消相关操作。
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Throws: DatabaseError（数据库操作失败）
    ///
    /// 需求: 8.8
    public func cancelOperations(for noteId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard let operations = operationsByNoteId[noteId] else {
            print("[UnifiedOperationQueue] 没有找到笔记 \(noteId) 的操作")
            return
        }
        
        var cancelledCount = 0
        
        for operation in operations {
            try databaseService.deleteUnifiedOperation(operationId: operation.id)
            operationsById.removeValue(forKey: operation.id)
            cancelledCount += 1
        }
        
        operationsByNoteId.removeValue(forKey: noteId)
        
        print("[UnifiedOperationQueue] 取消笔记 \(noteId) 的所有操作，共 \(cancelledCount) 个")
    }
}

// MARK: - 清理方法

extension UnifiedOperationQueue {
    
    /// 清理已完成的操作
    ///
    /// 从数据库中删除所有已完成的操作。
    ///
    /// - Throws: DatabaseError（数据库操作失败）
    public func cleanupCompletedOperations() throws {
        lock.lock()
        defer { lock.unlock() }
        
        let completedIds = operationsById.values
            .filter { $0.status == .completed }
            .map { $0.id }
        
        for id in completedIds {
            try databaseService.deleteUnifiedOperation(operationId: id)
            removeFromCache(id)
        }
        
        print("[UnifiedOperationQueue] 清理了 \(completedIds.count) 个已完成的操作")
    }
    
    /// 清空所有操作
    ///
    /// - Throws: DatabaseError（数据库操作失败）
    public func clearAll() throws {
        lock.lock()
        defer { lock.unlock() }
        
        try databaseService.clearAllUnifiedOperations()
        
        operationsById.removeAll()
        operationsByNoteId.removeAll()
        
        print("[UnifiedOperationQueue] 清空所有操作")
    }
    
    /// 重新加载数据
    ///
    /// 从数据库重新加载所有操作。
    public func reload() {
        loadFromDatabase()
    }
}
