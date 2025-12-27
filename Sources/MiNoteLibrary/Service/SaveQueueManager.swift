import Foundation

/// 保存优先级
public enum SavePriority: Int, Comparable {
    case background = 0  // 后台保存
    case normal = 1      // 普通保存
    case immediate = 2  // 立即保存（切换笔记时）
    
    public static func < (lhs: SavePriority, rhs: SavePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 保存任务
private class SaveTask {
    let noteId: String
    var note: Note  // 改为var，允许更新笔记内容（合并保存时）
    let priority: SavePriority
    let timestamp: Date
    
    init(note: Note, priority: SavePriority) {
        self.noteId = note.id
        self.note = note
        self.priority = priority
        self.timestamp = Date()
    }
}

/// 保存队列管理器
/// 
/// 管理笔记保存任务队列，合并相同笔记的多次保存，支持优先级
@MainActor
public final class SaveQueueManager {
    static let shared = SaveQueueManager()
    
    private var pendingSaves: [String: SaveTask] = [:]
    private var isProcessing = false
    private let database = DatabaseService.shared
    
    private init() {
        Swift.print("[SaveQueue] 初始化保存队列管理器")
    }
    
    /// 添加保存任务
    /// 
    /// - Parameters:
    ///   - note: 笔记对象
    ///   - priority: 保存优先级
    func enqueueSave(_ note: Note, priority: SavePriority = .normal) {
        let noteId = note.id
        
        // 如果已有相同笔记的保存任务，比较优先级
        if let existingTask = pendingSaves[noteId] {
            // 如果新任务优先级更高，替换旧任务
            if priority > existingTask.priority {
                pendingSaves[noteId] = SaveTask(note: note, priority: priority)
                Swift.print("[SaveQueue] 更新保存任务 - ID: \(noteId.prefix(8))..., 优先级: \(priority)")
            } else {
                // 否则更新笔记内容（合并保存）
                existingTask.note = note
                Swift.print("[SaveQueue] 合并保存任务 - ID: \(noteId.prefix(8))...")
            }
        } else {
            // 创建新任务
            pendingSaves[noteId] = SaveTask(note: note, priority: priority)
            Swift.print("[SaveQueue] 添加保存任务 - ID: \(noteId.prefix(8))..., 优先级: \(priority), 队列长度: \(pendingSaves.count)")
        }
        
        // 如果不在处理中，开始处理
        if !isProcessing {
            processQueue()
        }
    }
    
    /// 立即保存（高优先级）
    /// 
    /// - Parameter note: 笔记对象
    func saveImmediately(_ note: Note) {
        enqueueSave(note, priority: .immediate)
    }
    
    /// 取消保存任务
    /// 
    /// - Parameter noteId: 笔记ID
    func cancelSave(noteId: String) {
        if pendingSaves.removeValue(forKey: noteId) != nil {
            Swift.print("[SaveQueue] 取消保存任务 - ID: \(noteId.prefix(8))...")
        }
    }
    
    /// 处理保存队列
    private func processQueue() {
        guard !isProcessing else { return }
        guard !pendingSaves.isEmpty else { return }
        
        isProcessing = true
        
        // 按优先级排序
        let sortedTasks = pendingSaves.values.sorted { task1, task2 in
            if task1.priority != task2.priority {
                return task1.priority > task2.priority
            }
            return task1.timestamp < task2.timestamp
        }
        
        // 处理第一个任务（最高优先级）
        guard let firstTask = sortedTasks.first else {
            isProcessing = false
            return
        }
        
        let noteId = firstTask.noteId
        let note = firstTask.note
        
        // 从队列中移除
        pendingSaves.removeValue(forKey: noteId)
        
        // 异步保存
        database.saveNoteAsync(note) { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let error = error {
                    Swift.print("[SaveQueue] 保存失败 - ID: \(noteId.prefix(8))..., 错误: \(error)")
                } else {
                    Swift.print("[SaveQueue] 保存成功 - ID: \(noteId.prefix(8))..., 队列剩余: \(self.pendingSaves.count)")
                }
                
                // 继续处理队列
                self.isProcessing = false
                if !self.pendingSaves.isEmpty {
                    self.processQueue()
                }
            }
        }
    }
    
    /// 获取队列状态
    /// 
    /// - Returns: 队列中的任务数量
    func getQueueSize() -> Int {
        return pendingSaves.count
    }
    
    /// 清空队列
    func clearQueue() {
        pendingSaves.removeAll()
        isProcessing = false
        Swift.print("[SaveQueue] 清空保存队列")
    }
}

