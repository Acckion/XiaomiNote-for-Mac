import Foundation

/// 离线操作类型
enum OfflineOperationType: String, Codable {
    case createNote
    case updateNote
    case deleteNote
    case uploadImage
    case createFolder
    case renameFolder
    case deleteFolder
}

/// 离线操作
struct OfflineOperation: Codable, Identifiable {
    let id: String
    let type: OfflineOperationType
    let noteId: String // 对于文件夹操作，这个字段存储 folderId
    let data: Data // JSON 编码的操作数据
    let timestamp: Date
    
    init(id: String = UUID().uuidString, type: OfflineOperationType, noteId: String, data: Data, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.noteId = noteId
        self.data = data
        self.timestamp = timestamp
    }
}

/// 离线操作队列管理器
final class OfflineOperationQueue: @unchecked Sendable {
    static let shared = OfflineOperationQueue()
    
    private let localStorage = LocalStorageService.shared
    private let queue = DispatchQueue(label: "OfflineOperationQueue", attributes: .concurrent)
    
    private init() {}
    
    /// 添加离线操作
    func addOperation(_ operation: OfflineOperation) throws {
        try queue.sync(flags: .barrier) {
            var operations = loadOperations()
            operations.append(operation)
            try saveOperations(operations)
            print("[OfflineQueue] 添加离线操作: \(operation.type.rawValue), noteId: \(operation.noteId)")
        }
    }
    
    /// 移除操作
    func removeOperation(_ operationId: String) throws {
        try queue.sync(flags: .barrier) {
            var operations = loadOperations()
            operations.removeAll { $0.id == operationId }
            try saveOperations(operations)
            print("[OfflineQueue] 移除离线操作: \(operationId)")
        }
    }
    
    /// 获取所有待处理的操作
    func getPendingOperations() -> [OfflineOperation] {
        return queue.sync {
            return loadOperations()
        }
    }
    
    /// 清空所有操作
    func clearAll() throws {
        try queue.sync(flags: .barrier) {
            try saveOperations([])
            print("[OfflineQueue] 清空所有离线操作")
        }
    }
    
    // MARK: - 私有方法
    
    private func loadOperations() -> [OfflineOperation] {
        guard let data = UserDefaults.standard.data(forKey: "offline_operations"),
              let operations = try? JSONDecoder().decode([OfflineOperation].self, from: data) else {
            return []
        }
        return operations
    }
    
    private func saveOperations(_ operations: [OfflineOperation]) throws {
        let data = try JSONEncoder().encode(operations)
        UserDefaults.standard.set(data, forKey: "offline_operations")
    }
}

