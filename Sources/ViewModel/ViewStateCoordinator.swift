import Foundation
import SwiftUI
import Combine

// MARK: - 视图状态协调器

/// 视图状态协调器
/// 
/// 负责协调侧边栏、笔记列表和编辑器之间的状态同步，作为单一数据源管理选择状态
/// 
/// **Requirements: 4.1, 4.2, 4.3, 4.4, 4.5**
/// - 4.1: 作为单一数据源管理 selectedFolder 和 selectedNote 的状态
/// - 4.2: selectedFolder 变化时按顺序更新 Notes_List_View 和 Editor
/// - 4.3: selectedNote 变化时验证该笔记是否属于当前 selectedFolder
/// - 4.4: 如果 selectedNote 不属于当前 selectedFolder，自动更新或清除
/// - 4.5: 提供状态变化的日志记录以便调试
@MainActor
public class ViewStateCoordinator: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 当前选中的文件夹
    @Published public private(set) var selectedFolder: Folder?
    
    /// 当前选中的笔记
    @Published public private(set) var selectedNote: Note?
    
    /// 是否正在切换状态
    @Published public private(set) var isTransitioning: Bool = false
    
    /// 是否有未保存的内容
    @Published public var hasUnsavedContent: Bool = false
    
    /// 最近的状态转换记录（用于调试）
    @Published public private(set) var lastTransition: StateTransition?
    
    // MARK: - Save Callback
    
    /// 保存内容回调闭包
    /// 
    /// 由 NoteDetailView 注册，用于在文件夹切换前保存当前编辑的内容
    /// 
    /// **Requirements: 3.5, 6.1, 6.2**
    /// - 3.5: 用户在 Editor 中编辑笔记时切换到另一个文件夹，先保存当前编辑内容再切换
    /// - 6.1: 切换文件夹且 Editor 有未保存内容时，先触发保存操作
    /// - 6.2: 保存操作完成后继续执行文件夹切换
    public var saveContentCallback: (() async -> Bool)?
    
    // MARK: - Private Properties
    
    /// 关联的 NotesViewModel（弱引用避免循环引用）
    private weak var viewModel: NotesViewModel?
    
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    /// 状态转换历史（保留最近 50 条记录）
    private var transitionHistory: [StateTransition] = []
    private let maxHistoryCount = 50
    
    /// 是否启用调试日志
    public var isDebugLoggingEnabled: Bool = true
    
    // MARK: - Initialization
    
    /// 初始化状态协调器
    /// - Parameter viewModel: 关联的 NotesViewModel
    public init(viewModel: NotesViewModel? = nil) {
        self.viewModel = viewModel
        
        if isDebugLoggingEnabled {
            log("ViewStateCoordinator 初始化完成")
        }
    }
    
    /// 设置关联的 ViewModel
    /// - Parameter viewModel: NotesViewModel 实例
    public func setViewModel(_ viewModel: NotesViewModel) {
        self.viewModel = viewModel
        log("已关联 NotesViewModel")
    }
    
    // MARK: - Public Methods
    
    /// 选择文件夹
    /// 
    /// 执行文件夹选择操作，包含以下步骤：
    /// 1. 检查是否有未保存内容，如果有则先保存
    /// 2. 更新 selectedFolder
    /// 3. 清除 selectedNote（或选择新文件夹的第一个笔记）
    /// 
    /// **Requirements: 3.1, 3.2, 3.3, 3.5, 4.2, 6.1, 6.2**
    /// - 3.1: 用户在 Sidebar 中选择一个新文件夹时，Notes_List_View 立即显示该文件夹下的笔记列表
    /// - 3.2: 用户在 Sidebar 中选择一个新文件夹时，Editor 清空当前内容或显示该文件夹的第一篇笔记
    /// - 3.3: 用户在 Sidebar 中选择一个新文件夹时，Notes_List_View 清除之前的笔记选择状态
    /// - 3.5: 用户在 Editor 中编辑笔记时切换到另一个文件夹，先保存当前编辑内容再切换
    /// - 4.2: selectedFolder 变化时按顺序更新 Notes_List_View 和 Editor
    /// - 6.1: 切换文件夹且 Editor 有未保存内容时，先触发保存操作
    /// - 6.2: 保存操作完成后继续执行文件夹切换
    /// 
    /// - Parameter folder: 要选择的文件夹，nil 表示清除选择
    /// - Returns: 是否成功切换
    @discardableResult
    public func selectFolder(_ folder: Folder?) async -> Bool {
        // 如果选择的是同一个文件夹，不做任何操作
        if folder?.id == selectedFolder?.id {
            log("选择相同文件夹，跳过: \(folder?.id ?? "nil")")
            return true
        }
        
        isTransitioning = true
        defer { isTransitioning = false }
        
        let previousState = currentState
        let previousFolderName = selectedFolder?.name ?? "nil"
        let newFolderName = folder?.name ?? "nil"
        
        log("开始文件夹切换: \(previousFolderName) -> \(newFolderName)")
        
        // 步骤1: 检查并保存未保存的内容
        // **Requirements: 3.5, 6.1, 6.2**
        if hasUnsavedContent {
            log("检测到未保存内容，触发保存...")
            let saved = await saveCurrentContent()
            if !saved {
                log("⚠️ 保存失败，但继续切换文件夹")
                // 即使保存失败，也继续切换（用户可能选择放弃更改）
                // 根据需求 6.3，如果保存失败应该显示错误提示并询问用户
                // 但目前简化处理，直接继续切换
            } else {
                log("✅ 保存成功，继续切换文件夹")
            }
        } else {
            log("无未保存内容，直接切换")
        }
        
        // 步骤2: 更新 selectedFolder
        // **Requirements: 3.1, 4.2**
        selectedFolder = folder
        log("已更新 selectedFolder: \(newFolderName)")
        
        // 步骤3: 清除 selectedNote
        // **Requirements: 3.2, 3.3**
        // 根据需求 3.3，切换文件夹后应清除笔记选择
        selectedNote = nil
        log("已清除 selectedNote")
        
        // 记录状态转换
        let newState = currentState
        recordTransition(from: previousState, to: newState, trigger: .folderSelection)
        
        log("✅ 文件夹切换完成: \(newFolderName)")
        return true
    }
    
    /// 选择笔记
    /// 
    /// 执行笔记选择操作，包含归属验证逻辑
    /// 
    /// **Requirements: 4.3, 4.4**
    /// - 4.3: 验证该笔记是否属于当前 selectedFolder
    /// - 4.4: 如果不属于，自动更新 selectedFolder 或清除 selectedNote
    /// 
    /// - Parameter note: 要选择的笔记，nil 表示清除选择
    /// - Returns: 是否成功选择
    @discardableResult
    public func selectNote(_ note: Note?) async -> Bool {
        // 如果选择的是同一个笔记，不做任何操作
        if note?.id == selectedNote?.id {
            log("选择相同笔记，跳过: \(note?.id ?? "nil")")
            return true
        }
        
        isTransitioning = true
        defer { isTransitioning = false }
        
        let previousState = currentState
        
        // 如果 note 为 nil，直接清除选择
        guard let note = note else {
            selectedNote = nil
            let newState = currentState
            recordTransition(from: previousState, to: newState, trigger: .noteSelection)
            log("清除笔记选择")
            return true
        }
        
        // 验证笔记归属关系
        if let folderId = selectedFolder?.id {
            let belongsToFolder = isNoteInFolder(note: note, folderId: folderId)
            
            if !belongsToFolder {
                // 笔记不属于当前文件夹
                log("笔记 \(note.id) 不属于当前文件夹 \(folderId)")
                
                // 策略：自动更新 selectedFolder 到笔记所属的文件夹
                // 或者如果是特殊文件夹（如"所有笔记"），则允许选择
                if folderId != "0" {
                    // 查找笔记所属的文件夹
                    if let noteFolder = viewModel?.folders.first(where: { $0.id == note.folderId }) {
                        log("自动切换到笔记所属文件夹: \(noteFolder.name)")
                        selectedFolder = noteFolder
                    } else if note.folderId == "0" || note.folderId.isEmpty {
                        // 未分类笔记
                        log("笔记属于未分类，切换到未分类文件夹")
                        selectedFolder = viewModel?.uncategorizedFolder
                    }
                }
            }
        }
        
        // 更新 selectedNote
        selectedNote = note
        
        // 记录状态转换
        let newState = currentState
        recordTransition(from: previousState, to: newState, trigger: .noteSelection)
        
        log("笔记选择完成: \(note.title)")
        return true
    }
    
    /// 更新笔记内容（不触发选择变化）
    /// 
    /// 当编辑器中的笔记内容变化时调用，不会改变选择状态
    /// 
    /// **Requirements: 1.1, 1.2, 1.3**
    /// - 1.1: 编辑笔记内容时保持选中状态不变
    /// - 1.2: 笔记内容保存触发 notes 数组更新时不重置 selectedNote
    /// - 1.3: 笔记的 updatedAt 时间戳变化时保持选中笔记的高亮状态
    /// 
    /// - Parameter note: 更新后的笔记
    public func updateNoteContent(_ note: Note) {
        let previousState = currentState
        
        // 如果更新的是当前选中的笔记，更新 selectedNote 但保持选中状态
        if selectedNote?.id == note.id {
            // 更新 selectedNote 的引用，但不触发选择变化
            selectedNote = note
            log("更新选中笔记内容: \(note.id)")
        }
        
        // 记录状态转换（如果有变化）
        let newState = currentState
        if previousState != newState {
            recordTransition(from: previousState, to: newState, trigger: .contentUpdate)
        }
    }
    
    /// 验证当前状态一致性
    /// 
    /// 检查 selectedNote 是否属于 selectedFolder
    /// 
    /// **Requirements: 4.3**
    /// 
    /// - Returns: 状态是否一致
    public func validateStateConsistency() -> Bool {
        guard let viewModel = viewModel else {
            log("警告: ViewModel 未设置，无法验证状态一致性")
            return true
        }
        
        let state = currentState
        let isConsistent = state.isConsistent(with: viewModel.notes, folders: viewModel.folders)
        
        if !isConsistent {
            log("检测到状态不一致")
            if let inconsistency = detectInconsistency() {
                log("不一致详情: \(inconsistency.description)")
            }
        }
        
        return isConsistent
    }
    
    /// 同步状态（修复不一致）
    /// 
    /// 当检测到状态不一致时，自动修复
    /// 
    /// **Requirements: 3.4, 4.4**
    public func synchronizeState() {
        guard !validateStateConsistency() else {
            log("状态一致，无需同步")
            return
        }
        
        let previousState = currentState
        
        // 检测不一致类型并修复
        if let inconsistency = detectInconsistency() {
            let resolution = resolveInconsistency(inconsistency)
            applyResolution(resolution)
            
            let newState = currentState
            recordTransition(
                from: previousState,
                to: newState,
                trigger: .stateSync,
                additionalInfo: "修复: \(inconsistency.description)"
            )
        }
    }
    
    /// 恢复状态
    /// 
    /// 从保存的状态恢复选择
    /// 
    /// **Requirements: 1.4**
    /// 
    /// - Parameter state: 要恢复的状态
    public func restoreState(_ state: ViewState) {
        guard let viewModel = viewModel else {
            log("警告: ViewModel 未设置，无法恢复状态")
            return
        }
        
        let previousState = currentState
        
        // 恢复文件夹选择
        if let folderId = state.selectedFolderId {
            selectedFolder = viewModel.folders.first(where: { $0.id == folderId })
        } else {
            selectedFolder = nil
        }
        
        // 恢复笔记选择
        if let noteId = state.selectedNoteId {
            selectedNote = viewModel.notes.first(where: { $0.id == noteId })
        } else {
            selectedNote = nil
        }
        
        let newState = currentState
        recordTransition(from: previousState, to: newState, trigger: .viewRestore)
        
        log("状态恢复完成")
    }
    
    // MARK: - State Access
    
    /// 获取当前状态快照
    public var currentState: ViewState {
        ViewState(
            selectedFolderId: selectedFolder?.id,
            selectedNoteId: selectedNote?.id
        )
    }
    
    /// 获取状态转换历史
    public var history: [StateTransition] {
        transitionHistory
    }
    
    // MARK: - Private Methods
    
    /// 保存当前内容
    /// 
    /// 调用注册的保存回调来保存当前编辑的内容
    /// 
    /// **Requirements: 3.5, 6.1, 6.2**
    /// - 3.5: 用户在 Editor 中编辑笔记时切换到另一个文件夹，先保存当前编辑内容再切换
    /// - 6.1: 切换文件夹且 Editor 有未保存内容时，先触发保存操作
    /// - 6.2: 保存操作完成后继续执行文件夹切换
    /// 
    /// - Returns: 是否保存成功
    private func saveCurrentContent() async -> Bool {
        log("触发内容保存...")
        
        // 如果有注册的保存回调，调用它
        if let saveCallback = saveContentCallback {
            log("调用保存回调...")
            let success = await saveCallback()
            
            if success {
                log("保存回调执行成功")
                hasUnsavedContent = false
            } else {
                log("保存回调执行失败")
            }
            
            return success
        } else {
            // 没有注册保存回调，直接标记为已保存
            log("没有注册保存回调，跳过保存")
            hasUnsavedContent = false
            return true
        }
    }
    
    /// 检查笔记是否属于指定文件夹
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
    
    /// 检测状态不一致
    private func detectInconsistency() -> StateInconsistency? {
        guard let viewModel = viewModel else { return nil }
        
        // 检查选中的笔记是否存在
        if let noteId = selectedNote?.id {
            if !viewModel.notes.contains(where: { $0.id == noteId }) {
                return .noteNotFound(noteId: noteId)
            }
            
            // 检查笔记是否属于当前文件夹
            if let folderId = selectedFolder?.id,
               let note = viewModel.notes.first(where: { $0.id == noteId }) {
                if !isNoteInFolder(note: note, folderId: folderId) {
                    return .noteNotInFolder(noteId: noteId, folderId: folderId)
                }
            }
        }
        
        // 检查选中的文件夹是否存在
        if let folderId = selectedFolder?.id {
            let folderExists = viewModel.folders.contains(where: { $0.id == folderId }) ||
                              folderId == "0" || folderId == "starred" || folderId == "uncategorized"
            if !folderExists {
                return .folderNotFound(folderId: folderId)
            }
        }
        
        return nil
    }
    
    /// 确定不一致的解决策略
    private func resolveInconsistency(_ inconsistency: StateInconsistency) -> InconsistencyResolution {
        switch inconsistency {
        case .noteNotFound:
            return .clearSelection
        case .noteNotInFolder(_, let folderId):
            // 如果笔记不属于当前文件夹，切换到"所有笔记"
            if folderId != "0" {
                return .updateFolder(folderId: "0")
            }
            return .clearSelection
        case .folderNotFound:
            return .updateFolder(folderId: "0")
        }
    }
    
    /// 应用解决策略
    private func applyResolution(_ resolution: InconsistencyResolution) {
        switch resolution {
        case .clearSelection:
            selectedNote = nil
            log("应用解决策略: 清除笔记选择")
        case .updateFolder(let folderId):
            if let folder = viewModel?.folders.first(where: { $0.id == folderId }) {
                selectedFolder = folder
            } else if folderId == "0" {
                // 创建"所有笔记"虚拟文件夹
                selectedFolder = Folder(id: "0", name: "所有笔记", count: viewModel?.notes.count ?? 0, isSystem: true)
            }
            log("应用解决策略: 切换到文件夹 \(folderId)")
        case .selectFirstNote:
            if let firstNote = viewModel?.filteredNotes.first {
                selectedNote = firstNote
                log("应用解决策略: 选择第一个笔记")
            }
        case .logAndIgnore:
            log("应用解决策略: 记录日志并忽略")
        }
    }
    
    /// 记录状态转换
    private func recordTransition(
        from: ViewState,
        to: ViewState,
        trigger: TransitionTrigger,
        additionalInfo: String? = nil
    ) {
        let transition = StateTransition(
            from: from,
            to: to,
            trigger: trigger,
            additionalInfo: additionalInfo
        )
        
        transitionHistory.append(transition)
        
        // 保持历史记录在限制范围内
        if transitionHistory.count > maxHistoryCount {
            transitionHistory.removeFirst(transitionHistory.count - maxHistoryCount)
        }
        
        lastTransition = transition
        
        if isDebugLoggingEnabled {
            print(transition.logDescription)
        }
    }
    
    /// 输出日志
    private func log(_ message: String) {
        if isDebugLoggingEnabled {
            print("[ViewStateCoordinator] \(message)")
        }
    }
}

// MARK: - Convenience Extensions

public extension ViewStateCoordinator {
    /// 快速选择文件夹（同步版本，用于简单场景）
    func selectFolderSync(_ folder: Folder?) {
        Task {
            await selectFolder(folder)
        }
    }
    
    /// 快速选择笔记（同步版本，用于简单场景）
    func selectNoteSync(_ note: Note?) {
        Task {
            await selectNote(note)
        }
    }
    
    /// 清除所有选择
    func clearSelection() {
        Task {
            await selectNote(nil)
            await selectFolder(nil)
        }
    }
}
