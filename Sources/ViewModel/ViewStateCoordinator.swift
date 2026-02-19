import Combine
import Foundation
import SwiftUI

// MARK: - 视图状态协调器

/// 视图状态协调器
///
/// 负责协调侧边栏、笔记列表和编辑器之间的状态同步，作为单一数据源管理选择状态
///
/// - 4.1: 作为单一数据源管理 selectedFolder 和 selectedNote 的状态
/// - 4.2: selectedFolder 变化时按顺序更新 Notes_List_View 和 Editor
/// - 4.3: selectedNote 变化时验证该笔记是否属于当前 selectedFolder
/// - 4.4: 如果 selectedNote 不属于当前 selectedFolder，自动更新或清除
/// - 4.5: 提供状态变化的日志记录以便调试
/// - 1.4: 视图重建后恢复选择状态
@MainActor
public class ViewStateCoordinator: ObservableObject {

    // MARK: - UserDefaults Keys

    /// UserDefaults 存储键
    private enum StorageKeys {
        static let selectedFolderId = "ViewStateCoordinator.selectedFolderId"
        static let selectedNoteId = "ViewStateCoordinator.selectedNoteId"
        static let stateTimestamp = "ViewStateCoordinator.stateTimestamp"
    }

    // MARK: - Published Properties

    /// 当前选中的文件夹
    @Published public private(set) var selectedFolder: Folder? {
        didSet {
            // 状态变化时自动保存到 UserDefaults
            saveStateToUserDefaults()
        }
    }

    /// 当前选中的笔记
    @Published public private(set) var selectedNote: Note? {
        didSet {
            // 状态变化时自动保存到 UserDefaults
            saveStateToUserDefaults()
        }
    }

    /// 是否正在切换状态
    @Published public private(set) var isTransitioning = false

    /// 是否有未保存的内容
    @Published public var hasUnsavedContent = false

    /// 最近的状态转换记录（用于调试）
    @Published public private(set) var lastTransition: StateTransition?

    /// 是否已从持久化存储恢复状态
    @Published public private(set) var hasRestoredState = false

    // MARK: - Save Callback

    /// 保存内容回调闭包
    ///
    /// 由 NoteDetailView 注册，用于在文件夹切换前保存当前编辑的内容
    ///
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
    public var isDebugLoggingEnabled = true

    /// 是否启用状态持久化
    public var isStatePersistenceEnabled = true

    /// 内存缓存的状态（用于快速恢复）
    private var cachedState: ViewState?

    // MARK: - Initialization

    /// 初始化状态协调器
    /// - Parameter viewModel: 关联的 NotesViewModel
    public init(viewModel: NotesViewModel? = nil) {
        self.viewModel = viewModel

    }

    /// 设置关联的 ViewModel
    /// - Parameter viewModel: NotesViewModel 实例
    public func setViewModel(_ viewModel: NotesViewModel) {
        self.viewModel = viewModel

        // 关联 ViewModel 后，尝试恢复之前保存的状态
        if isStatePersistenceEnabled, !hasRestoredState {
            restoreStateFromUserDefaults()
        }
    }

    // MARK: - State Persistence

    /// 保存状态到 UserDefaults
    ///
    /// 在状态变化时自动调用，将当前选择状态持久化
    ///
    /// - 1.4: 视图重建后恢复选择状态
    private func saveStateToUserDefaults() {
        guard isStatePersistenceEnabled else { return }

        let defaults = UserDefaults.standard

        // 保存文件夹ID
        if let folderId = selectedFolder?.id {
            defaults.set(folderId, forKey: StorageKeys.selectedFolderId)
        } else {
            defaults.removeObject(forKey: StorageKeys.selectedFolderId)
        }

        // 保存笔记ID
        if let noteId = selectedNote?.id {
            defaults.set(noteId, forKey: StorageKeys.selectedNoteId)
        } else {
            defaults.removeObject(forKey: StorageKeys.selectedNoteId)
        }

        // 保存时间戳
        defaults.set(Date().timeIntervalSince1970, forKey: StorageKeys.stateTimestamp)

        // 同时更新内存缓存
        cachedState = currentState
    }

    /// 从 UserDefaults 恢复状态
    ///
    /// 在视图重建后调用，恢复之前保存的选择状态
    ///
    /// - 1.4: 视图重建后恢复选择状态
    private func restoreStateFromUserDefaults() {
        guard let viewModel else {
            log("警告: ViewModel 未设置，无法恢复状态")
            return
        }

        let defaults = UserDefaults.standard
        let previousState = currentState

        // 读取保存的状态
        let savedFolderId = defaults.string(forKey: StorageKeys.selectedFolderId)
        let savedNoteId = defaults.string(forKey: StorageKeys.selectedNoteId)
        let savedTimestamp = defaults.double(forKey: StorageKeys.stateTimestamp)

        // 检查保存的状态是否有效（24小时内）
        let maxAge: TimeInterval = 24 * 60 * 60 // 24小时
        let stateAge = Date().timeIntervalSince1970 - savedTimestamp

        if savedTimestamp > 0, stateAge > maxAge {
            log("保存的状态已过期（\(Int(stateAge / 3600))小时前），清除状态")
            clearPersistedState()
            hasRestoredState = true
            return
        }

        var stateRestored = false

        // 恢复文件夹选择
        if let folderId = savedFolderId {
            // 查找文件夹
            if let folder = viewModel.folders.first(where: { $0.id == folderId }) {
                selectedFolder = folder
                stateRestored = true
            } else if folderId == "0" {
                // "所有笔记"虚拟文件夹
                selectedFolder = Folder(id: "0", name: "所有笔记", count: viewModel.notes.count, isSystem: true)
                stateRestored = true
            } else if folderId == "starred" {
                // "置顶"虚拟文件夹
                let starredCount = viewModel.notes.count(where: { $0.isStarred })
                selectedFolder = Folder(id: "starred", name: "置顶", count: starredCount, isSystem: true)
                stateRestored = true
            }
        }

        // 恢复笔记选择
        if let noteId = savedNoteId {
            // 查找笔记
            if let note = viewModel.notes.first(where: { $0.id == noteId }) {
                // 验证笔记是否属于当前文件夹
                if let folderId = selectedFolder?.id {
                    if isNoteInFolder(note: note, folderId: folderId) {
                        selectedNote = note
                        stateRestored = true
                    }
                } else {
                    // 没有选中文件夹，直接恢复笔记
                    selectedNote = note
                    stateRestored = true
                }
            }
        }

        hasRestoredState = true

        // 记录状态转换
        if stateRestored {
            let newState = currentState
            recordTransition(from: previousState, to: newState, trigger: .viewRestore, additionalInfo: "从 UserDefaults 恢复")
            log("状态恢复完成")
        }
    }

    /// 从内存缓存恢复状态
    ///
    /// 用于快速恢复，优先于 UserDefaults
    ///
    /// - 1.4: 视图重建后恢复选择状态
    ///
    /// - Returns: 是否成功恢复
    @discardableResult
    public func restoreStateFromCache() -> Bool {
        guard let cachedState else {
            return false
        }

        restoreState(cachedState)
        return true
    }

    /// 清除持久化的状态
    ///
    /// 在用户登出或需要重置状态时调用
    public func clearPersistedState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: StorageKeys.selectedFolderId)
        defaults.removeObject(forKey: StorageKeys.selectedNoteId)
        defaults.removeObject(forKey: StorageKeys.stateTimestamp)

        cachedState = nil
    }

    /// 获取持久化的状态（不恢复）
    ///
    /// 用于检查是否有保存的状态
    ///
    /// - Returns: 保存的状态，如果没有则返回 nil
    public func getPersistedState() -> ViewState? {
        let defaults = UserDefaults.standard

        let savedFolderId = defaults.string(forKey: StorageKeys.selectedFolderId)
        let savedNoteId = defaults.string(forKey: StorageKeys.selectedNoteId)
        let savedTimestamp = defaults.double(forKey: StorageKeys.stateTimestamp)

        // 如果没有保存的状态，返回 nil
        if savedFolderId == nil, savedNoteId == nil {
            return nil
        }

        let timestamp = savedTimestamp > 0 ? Date(timeIntervalSince1970: savedTimestamp) : Date()

        return ViewState(
            selectedFolderId: savedFolderId,
            selectedNoteId: savedNoteId,
            timestamp: timestamp
        )
    }

    /// 手动触发状态恢复
    ///
    /// 在数据加载完成后调用，确保状态正确恢复
    ///
    /// - 1.4: 视图重建后恢复选择状态
    public func triggerStateRestoration() {
        guard isStatePersistenceEnabled else { return }

        // 如果已经恢复过，先检查内存缓存
        if hasRestoredState {
            if restoreStateFromCache() {
                return
            }
        }

        // 从 UserDefaults 恢复
        restoreStateFromUserDefaults()
    }

    // MARK: - Public Methods

    /// 选择文件夹
    ///
    /// 执行文件夹选择操作，包含以下步骤：
    /// 1. 检查是否有未保存内容，如果有则先保存
    /// 2. 更新 selectedFolder
    /// 3. 清除 selectedNote（或选择新文件夹的第一个笔记）
    ///
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
            return true
        }

        isTransitioning = true
        defer { isTransitioning = false }

        let previousState = currentState
        let previousFolderName = selectedFolder?.name ?? "nil"
        let newFolderName = folder?.name ?? "nil"

        // 保存当前选中的笔记，用于后续检查是否在新文件夹中
        let currentSelectedNote = selectedNote

        log("开始文件夹切换: \(previousFolderName) -> \(newFolderName)")

        // 步骤1: 检查并保存未保存的内容
        if hasUnsavedContent {
            let saved = await saveCurrentContent()
            if !saved {
                log("保存失败，但继续切换文件夹")
            }
        }

        // 步骤2: 更新 selectedFolder
        selectedFolder = folder

        // 步骤3: 智能选择笔记
        // 优先保持当前笔记选中（如果它在新文件夹中），否则选择第一个笔记
        if let currentNote = currentSelectedNote,
           let folderId = folder?.id,
           isNoteInFolder(note: currentNote, folderId: folderId)
        {
            if let noteInList = viewModel?.filteredNotes.first(where: { $0.id == currentNote.id }) {
                selectedNote = noteInList
            } else {
                selectedNote = viewModel?.filteredNotes.first
            }
        } else {
            selectedNote = viewModel?.filteredNotes.first
        }

        // 记录状态转换
        let newState = currentState
        recordTransition(from: previousState, to: newState, trigger: .folderSelection)

        log("文件夹切换完成: \(newFolderName)")
        return true
    }

    /// 选择笔记
    ///
    /// 执行笔记选择操作，包含归属验证逻辑
    ///
    /// - 4.3: 验证该笔记是否属于当前 selectedFolder
    /// - 4.4: 如果不属于，自动更新 selectedFolder 或清除 selectedNote
    ///
    /// - Parameter note: 要选择的笔记，nil 表示清除选择
    /// - Returns: 是否成功选择
    @discardableResult
    public func selectNote(_ note: Note?) async -> Bool {
        // 如果选择的是同一个笔记，不做任何操作
        if note?.id == selectedNote?.id {
            return true
        }

        isTransitioning = true
        defer { isTransitioning = false }

        let previousState = currentState

        // 如果 note 为 nil，直接清除选择
        guard let note else {
            selectedNote = nil
            let newState = currentState
            recordTransition(from: previousState, to: newState, trigger: .noteSelection)
            return true
        }

        // 验证笔记归属关系
        if let folderId = selectedFolder?.id {
            let belongsToFolder = isNoteInFolder(note: note, folderId: folderId)

            if !belongsToFolder, folderId != "0" {
                // 自动切换到笔记所属文件夹
                if let noteFolder = viewModel?.folders.first(where: { $0.id == note.folderId }) {
                    selectedFolder = noteFolder
                } else if note.folderId == "0" || note.folderId.isEmpty {
                    selectedFolder = viewModel?.uncategorizedFolder
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
    /// - 1.1: 编辑笔记内容时保持选中状态不变
    /// - 1.2: 笔记内容保存触发 notes 数组更新时不重置 selectedNote
    /// - 1.3: 笔记的 updatedAt 时间戳变化时保持选中笔记的高亮状态
    ///
    /// - Parameter note: 更新后的笔记
    public func updateNoteContent(_ note: Note) {
        let previousState = currentState

        if selectedNote?.id == note.id {
            selectedNote = note
        }

        let newState = currentState
        if previousState != newState {
            recordTransition(from: previousState, to: newState, trigger: .contentUpdate)
        }
    }

    /// 验证当前状态一致性
    ///
    /// 检查 selectedNote 是否属于 selectedFolder
    ///
    ///
    /// - Returns: 状态是否一致
    public func validateStateConsistency() -> Bool {
        guard let viewModel else {
            log("警告: ViewModel 未设置，无法验证状态一致性")
            return true
        }

        let state = currentState
        let isConsistent = state.isConsistent(with: viewModel.notes, folders: viewModel.folders)

        if !isConsistent, let inconsistency = detectInconsistency() {
            log("状态不一致: \(inconsistency.description)")
        }

        return isConsistent
    }

    /// 同步状态（修复不一致）
    ///
    /// 当检测到状态不一致时，自动修复
    ///
    public func synchronizeState() {
        guard !validateStateConsistency() else { return }

        let previousState = currentState

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
    ///
    /// - Parameter state: 要恢复的状态
    public func restoreState(_ state: ViewState) {
        guard let viewModel else {
            log("警告: ViewModel 未设置，无法恢复状态")
            return
        }

        let previousState = currentState

        if let folderId = state.selectedFolderId {
            selectedFolder = viewModel.folders.first(where: { $0.id == folderId })
        } else {
            selectedFolder = nil
        }

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
    /// - 3.5: 用户在 Editor 中编辑笔记时切换到另一个文件夹，先保存当前编辑内容再切换
    /// - 6.1: 切换文件夹且 Editor 有未保存内容时，先触发保存操作
    /// - 6.2: 保存操作完成后继续执行文件夹切换
    ///
    /// - Returns: 是否保存成功
    private func saveCurrentContent() async -> Bool {
        if let saveCallback = saveContentCallback {
            let success = await saveCallback()
            if success {
                hasUnsavedContent = false
            }
            return success
        } else {
            hasUnsavedContent = false
            return true
        }
    }

    /// 检查笔记是否属于指定文件夹
    private func isNoteInFolder(note: Note, folderId: String) -> Bool {
        switch folderId {
        case "0":
            // 所有笔记
            true
        case "starred":
            // 置顶笔记
            note.isStarred
        case "uncategorized":
            // 未分类笔记
            note.folderId == "0" || note.folderId.isEmpty
        default:
            // 普通文件夹
            note.folderId == folderId
        }
    }

    /// 检测状态不一致
    private func detectInconsistency() -> StateInconsistency? {
        guard let viewModel else { return nil }

        // 检查选中的笔记是否存在
        if let noteId = selectedNote?.id {
            if !viewModel.notes.contains(where: { $0.id == noteId }) {
                return .noteNotFound(noteId: noteId)
            }

            // 检查笔记是否属于当前文件夹
            if let folderId = selectedFolder?.id,
               let note = viewModel.notes.first(where: { $0.id == noteId })
            {
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
        case let .noteNotInFolder(_, folderId):
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
        case let .updateFolder(folderId):
            if let folder = viewModel?.folders.first(where: { $0.id == folderId }) {
                selectedFolder = folder
            } else if folderId == "0" {
                selectedFolder = Folder(id: "0", name: "所有笔记", count: viewModel?.notes.count ?? 0, isSystem: true)
            }
            log("应用解决策略: 切换到文件夹 \(folderId)")
        case .selectFirstNote:
            if let firstNote = viewModel?.filteredNotes.first {
                selectedNote = firstNote
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
            LogService.shared.debug(.viewmodel, transition.logDescription)
        }
    }

    /// 输出日志
    private func log(_ message: String) {
        if isDebugLoggingEnabled {
            LogService.shared.debug(.viewmodel, "[ViewStateCoordinator] \(message)")
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
