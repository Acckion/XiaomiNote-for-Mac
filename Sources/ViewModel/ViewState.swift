import Foundation

// MARK: - 视图状态快照

/// 视图状态快照
/// 
/// 记录当前选中的文件夹和笔记状态，用于状态一致性验证和状态恢复
/// 
/// - 4.1: 作为单一数据源管理 selectedFolder 和 selectedNote 的状态
/// - 4.3: 验证笔记是否属于当前文件夹
public struct ViewState: Equatable, Codable {
    /// 当前选中的文件夹ID
    public let selectedFolderId: String?
    
    /// 当前选中的笔记ID
    public let selectedNoteId: String?
    
    /// 状态创建时间戳
    public let timestamp: Date
    
    /// 初始化视图状态
    /// - Parameters:
    ///   - selectedFolderId: 选中的文件夹ID
    ///   - selectedNoteId: 选中的笔记ID
    ///   - timestamp: 状态时间戳，默认为当前时间
    public init(
        selectedFolderId: String? = nil,
        selectedNoteId: String? = nil,
        timestamp: Date = Date()
    ) {
        self.selectedFolderId = selectedFolderId
        self.selectedNoteId = selectedNoteId
        self.timestamp = timestamp
    }
    
    /// 检查状态是否一致
    /// 
    /// 验证选中的笔记是否属于选中的文件夹
    /// 
    /// - Parameters:
    ///   - notes: 笔记列表
    ///   - folders: 文件夹列表
    /// - Returns: 状态是否一致
    public func isConsistent(with notes: [Note], folders: [Folder]) -> Bool {
        // 如果没有选中笔记，状态一致
        guard let noteId = selectedNoteId else { return true }
        
        // 查找选中的笔记
        guard let note = notes.first(where: { $0.id == noteId }) else {
            // 笔记不存在，状态不一致
            return false
        }
        
        // 如果没有选中文件夹，检查笔记是否在"所有笔记"中（始终一致）
        guard let folderId = selectedFolderId else {
            return true
        }
        
        // 检查笔记是否属于选中的文件夹
        return isNoteInFolder(note: note, folderId: folderId)
    }
    
    /// 检查笔记是否属于指定文件夹
    /// 
    /// 处理特殊文件夹的逻辑：
    /// - "0": 所有笔记（始终返回 true）
    /// - "starred": 置顶笔记（检查 isStarred）
    /// - "uncategorized": 未分类笔记（检查 folderId 为 "0" 或空）
    /// - 其他: 普通文件夹（检查 folderId 匹配）
    /// 
    /// - Parameters:
    ///   - note: 要检查的笔记
    ///   - folderId: 文件夹ID
    /// - Returns: 笔记是否属于该文件夹
    private func isNoteInFolder(note: Note, folderId: String) -> Bool {
        switch folderId {
        case "0":
            // 所有笔记
            return true
        case "starred":
            // 置顶笔记
            return note.isStarred
        case "uncategorized":
            // 未分类笔记
            return note.folderId == "0" || note.folderId.isEmpty
        default:
            // 普通文件夹
            return note.folderId == folderId
        }
    }
    
    /// 创建空状态
    public static var empty: ViewState {
        ViewState(selectedFolderId: nil, selectedNoteId: nil)
    }
}

// MARK: - 状态转换触发器

/// 状态转换触发器
/// 
/// 记录导致状态转换的原因
public enum TransitionTrigger: String, Codable {
    /// 用户选择文件夹
    case folderSelection
    
    /// 用户选择笔记
    case noteSelection
    
    /// 笔记内容更新
    case contentUpdate
    
    /// 状态同步（自动修复不一致）
    case stateSync
    
    /// 视图重建后恢复
    case viewRestore
    
    /// 初始化
    case initialization
}

// MARK: - 状态转换记录

/// 状态转换记录
/// 
/// 记录从一个状态到另一个状态的转换，用于调试和日志
/// 
/// - 提供状态变化的日志记录以便调试
public struct StateTransition: Codable {
    /// 转换前的状态
    public let from: ViewState
    
    /// 转换后的状态
    public let to: ViewState
    
    /// 转换触发器
    public let trigger: TransitionTrigger
    
    /// 转换时间戳
    public let timestamp: Date
    
    /// 附加信息（用于调试）
    public let additionalInfo: String?
    
    /// 初始化状态转换记录
    /// - Parameters:
    ///   - from: 转换前的状态
    ///   - to: 转换后的状态
    ///   - trigger: 转换触发器
    ///   - timestamp: 转换时间戳，默认为当前时间
    ///   - additionalInfo: 附加信息
    public init(
        from: ViewState,
        to: ViewState,
        trigger: TransitionTrigger,
        timestamp: Date = Date(),
        additionalInfo: String? = nil
    ) {
        self.from = from
        self.to = to
        self.trigger = trigger
        self.timestamp = timestamp
        self.additionalInfo = additionalInfo
    }
    
    /// 生成日志描述
    public var logDescription: String {
        let fromFolder = from.selectedFolderId ?? "nil"
        let fromNote = from.selectedNoteId ?? "nil"
        let toFolder = to.selectedFolderId ?? "nil"
        let toNote = to.selectedNoteId ?? "nil"
        
        var description = "[StateTransition] \(trigger.rawValue): "
        description += "folder(\(fromFolder) -> \(toFolder)), "
        description += "note(\(fromNote) -> \(toNote))"
        
        if let info = additionalInfo {
            description += " | \(info)"
        }
        
        return description
    }
}

// MARK: - 状态不一致类型

/// 状态不一致类型
/// 
/// 描述检测到的状态不一致情况
public enum StateInconsistency: Equatable {
    /// 笔记不属于当前文件夹
    case noteNotInFolder(noteId: String, folderId: String)
    
    /// 笔记不存在
    case noteNotFound(noteId: String)
    
    /// 文件夹不存在
    case folderNotFound(folderId: String)
    
    /// 描述信息
    public var description: String {
        switch self {
        case .noteNotInFolder(let noteId, let folderId):
            return "笔记 \(noteId) 不属于文件夹 \(folderId)"
        case .noteNotFound(let noteId):
            return "笔记 \(noteId) 不存在"
        case .folderNotFound(let folderId):
            return "文件夹 \(folderId) 不存在"
        }
    }
}

// MARK: - 状态不一致处理策略

/// 状态不一致处理策略
/// 
/// 定义如何处理检测到的状态不一致
public enum InconsistencyResolution {
    /// 清除选择状态
    case clearSelection
    
    /// 更新到指定文件夹
    case updateFolder(folderId: String)
    
    /// 选择第一个笔记
    case selectFirstNote
    
    /// 记录日志但忽略
    case logAndIgnore
}
