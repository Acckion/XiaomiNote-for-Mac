//
//  NotesViewModelAdapter.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  NotesViewModel 适配器 - 将新架构适配到旧的 NotesViewModel 接口
//

import Foundation
import Combine

/// NotesViewModel 适配器
///
/// 将新的 AppCoordinator 架构适配到旧的 NotesViewModel 接口,
/// 使得现有的 UI 代码无需修改即可使用新架构。
///
/// **设计模式**: 适配器模式 (Adapter Pattern)
///
/// **工作原理**:
/// 1. 继承自 `NotesViewModel`,保持接口兼容
/// 2. 内部持有 `AppCoordinator` 实例
/// 3. 将所有操作委托给对应的 ViewModel
/// 4. 使用 Combine 同步状态
@MainActor
public final class NotesViewModelAdapter: NotesViewModel {
    // MARK: - Properties
    
    /// 应用协调器
    private let coordinator: AppCoordinator
    
    /// Cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// 初始化适配器
    /// - Parameter coordinator: 应用协调器
    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
        
        // 设置状态同步
        setupStateSync()
        
        print("[NotesViewModelAdapter] 初始化完成")
    }
    
    // MARK: - State Synchronization
    
    /// 设置状态同步
    ///
    /// 将 AppCoordinator 中各个 ViewModel 的状态同步到 NotesViewModel 的属性
    private func setupStateSync() {
        // 1. 同步笔记列表
        coordinator.noteListViewModel.$notes
            .assign(to: &$notes)
        
        // 2. 同步选中的笔记
        coordinator.noteListViewModel.$selectedNote
            .assign(to: &$selectedNote)
        
        // 3. 同步文件夹列表
        coordinator.folderViewModel.$folders
            .assign(to: &$folders)
        
        // 4. 同步选中的文件夹
        coordinator.folderViewModel.$selectedFolder
            .assign(to: &$selectedFolder)
        
        // 5. 同步加载状态
        Publishers.CombineLatest3(
            coordinator.noteListViewModel.$isLoading,
            coordinator.folderViewModel.$isLoading,
            coordinator.syncCoordinator.$isSyncing
        )
        .map { $0 || $1 || $2 }
        .assign(to: &$isLoading)
        
        // 6. 同步错误消息
        Publishers.Merge4(
            coordinator.noteListViewModel.$errorMessage.compactMap { $0 },
            coordinator.noteEditorViewModel.$errorMessage.compactMap { $0 },
            coordinator.syncCoordinator.$errorMessage.compactMap { $0 },
            coordinator.authViewModel.$errorMessage.compactMap { $0 }
        )
        .assign(to: &$errorMessage)
        
        // 7. 同步搜索文本
        coordinator.searchViewModel.$searchText
            .assign(to: &$searchText)
        
        // 8. 同步认证状态
        coordinator.authViewModel.$showLoginView
            .assign(to: &$showLoginView)
        
        coordinator.authViewModel.$showCookieRefreshView
            .assign(to: &$showCookieRefreshView)
        
        coordinator.authViewModel.$isPrivateNotesUnlocked
            .assign(to: &$isPrivateNotesUnlocked)
        
        coordinator.authViewModel.$userProfile
            .assign(to: &$userProfile)
        
        // 9. 同步搜索过滤器
        coordinator.searchViewModel.$filterHasTags
            .assign(to: &$searchFilterHasTags)
        
        coordinator.searchViewModel.$filterHasChecklist
            .assign(to: &$searchFilterHasChecklist)
        
        coordinator.searchViewModel.$filterHasImages
            .assign(to: &$searchFilterHasImages)
        
        coordinator.searchViewModel.$filterHasAudio
            .assign(to: &$searchFilterHasAudio)
        
        coordinator.searchViewModel.$filterIsPrivate
            .assign(to: &$searchFilterIsPrivate)
        
        print("[NotesViewModelAdapter] 状态同步设置完成")
    }
    
    // MARK: - Folder Operations
    
    public override func loadFolders() {
        Task {
            await coordinator.folderViewModel.loadFolders()
        }
    }
    
    public override func selectFolderWithCoordinator(_ folder: Folder?) {
        coordinator.handleFolderSelection(folder)
    }
    
    public override func createFolder(name: String) async throws -> String {
        // FolderViewModel.createFolder 不返回值,我们需要等待创建完成后从列表中找到新文件夹
        await coordinator.folderViewModel.createFolder(name: name)
        
        // 查找刚创建的文件夹
        if let newFolder = coordinator.folderViewModel.folders.first(where: { $0.name == name }) {
            return newFolder.id
        }
        
        // 如果找不到,返回临时 ID
        return UUID().uuidString
    }
    
    override func renameFolder(_ folder: Folder, newName: String) async throws {
        await coordinator.folderViewModel.renameFolder(folder, newName: newName)
    }
    
    override func deleteFolder(_ folder: Folder) async throws {
        await coordinator.folderViewModel.deleteFolder(folder)
    }
    
    override func toggleFolderPin(_ folder: Folder) async throws {
        // TODO: 实现文件夹置顶功能
        print("[NotesViewModelAdapter] toggleFolderPin 待实现")
    }
    
    // MARK: - Note Operations
    
    public override func selectNoteWithCoordinator(_ note: Note?) {
        if let note = note {
            coordinator.handleNoteSelection(note)
        }
    }
    
    public override func createNote(_ note: Note) async throws {
        // NoteListViewModel 没有 createNote 方法,直接添加到列表
        coordinator.noteListViewModel.notes.append(note)
        
        // 保存到本地存储
        // TODO: 调用存储服务保存笔记
    }
    
    override func updateNote(_ note: Note) async throws {
        await coordinator.noteEditorViewModel.saveNote()
    }
    
    public override func updateNoteInPlace(_ note: Note) -> Bool {
        // 更新笔记列表中的笔记
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            return true
        }
        return false
    }
    
    public override func batchUpdateNotes(_ updates: [(noteId: String, update: (inout Note) -> Void)]) {
        for (noteId, update) in updates {
            if let index = notes.firstIndex(where: { $0.id == noteId }) {
                var note = notes[index]
                update(&note)
                notes[index] = note
            }
        }
    }
    
    public override func updateNoteTimestamp(_ noteId: String, timestamp: Date) -> Bool {
        if let index = notes.firstIndex(where: { $0.id == noteId }) {
            var note = notes[index]
            note.updatedAt = timestamp
            notes[index] = note
            return true
        }
        return false
    }
    
    override func deleteNote(_ note: Note) {
        Task {
            await coordinator.noteListViewModel.deleteNote(note)
        }
    }
    
    public override func toggleStar(_ note: Note) {
        Task {
            await coordinator.noteListViewModel.toggleStar(note)
        }
    }
    
    public override func createNewNote() {
        Task {
            // 创建一个新的空笔记
            let newNote = Note(
                id: UUID().uuidString,
                title: "新笔记",
                content: "",
                folderId: coordinator.folderViewModel.selectedFolder?.id ?? "0",
                isStarred: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            // 添加到笔记列表
            coordinator.noteListViewModel.notes.insert(newNote, at: 0)
            
            // 选中新笔记
            coordinator.handleNoteSelection(newNote)
        }
    }
    
    // MARK: - Sync Operations
    
    override func performFullSync() async {
        await coordinator.syncCoordinator.forceFullSync()
    }
    
    override func performIncrementalSync() async {
        await coordinator.syncCoordinator.startSync()
    }
    
    override func cancelSync() {
        coordinator.syncCoordinator.stopSync()
    }
    
    override func loadNotesFromCloud() async {
        await coordinator.syncCoordinator.startSync()
    }
    
    // MARK: - Authentication Operations
    
    public override func handleLoginSuccess() async {
        // 登录成功后启动同步
        await coordinator.syncCoordinator.startSync()
        
        // 加载用户信息
        await coordinator.authViewModel.fetchUserProfile()
    }
    
    public override func handleCookieRefreshSuccess() async {
        // Cookie 刷新成功后重新同步
        await coordinator.syncCoordinator.startSync()
    }
    
    override func verifyPrivateNotesPassword(_ password: String) -> Bool {
        // AuthenticationViewModel.unlockPrivateNotes 是 async 方法,不返回值
        // 我们需要同步检查密码
        // TODO: 实现同步的密码验证
        return false
    }
    
    override func unlockPrivateNotes() {
        coordinator.authViewModel.isPrivateNotesUnlocked = true
    }
    
    override func handlePrivateNotesPasswordCancel() {
        coordinator.authViewModel.isPrivateNotesUnlocked = false
        showPrivateNotesPasswordDialog = false
    }
    
    // MARK: - Search Operations
    
    override func setNotesListSortField(_ field: NoteSortOrder) {
        coordinator.noteListViewModel.sortOrder = field
        notesListSortField = field
    }
    
    override func setNotesListSortDirection(_ direction: SortDirection) {
        coordinator.noteListViewModel.sortDirection = direction
        notesListSortDirection = direction
    }
    
    // MARK: - User Profile
    
    override func fetchUserProfile() async {
        await coordinator.authViewModel.fetchUserProfile()
    }
    
    // MARK: - Folder Sort Order
    
    override func setFolderSortOrder(_ folder: Folder, sortOrder: NoteSortOrder) {
        folderSortOrders[folder.id] = sortOrder
        // 保存到 UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(sortOrder.rawValue, forKey: "folderSortOrder_\(folder.id)")
    }
    
    override func getFolderSortOrder(_ folder: Folder) -> NoteSortOrder? {
        return folderSortOrders[folder.id]
    }
    
    // MARK: - Note History (TODO)
    
    override func getNoteHistoryTimes(noteId: String) async throws -> [NoteHistoryVersion] {
        // TODO: 实现笔记历史功能
        print("[NotesViewModelAdapter] getNoteHistoryTimes 待实现")
        return []
    }
    
    override func getNoteHistory(noteId: String, version: Int64) async throws -> Note {
        // TODO: 实现笔记历史功能
        print("[NotesViewModelAdapter] getNoteHistory 待实现")
        throw NSError(domain: "MiNote", code: 501, userInfo: [NSLocalizedDescriptionKey: "功能待实现"])
    }
    
    override func restoreNoteHistory(noteId: String, version: Int64) async throws {
        // TODO: 实现笔记历史功能
        print("[NotesViewModelAdapter] restoreNoteHistory 待实现")
    }
    
    // MARK: - Deleted Notes (TODO)
    
    override func fetchDeletedNotes() async {
        // TODO: 实现回收站功能
        print("[NotesViewModelAdapter] fetchDeletedNotes 待实现")
    }
    
    // MARK: - Image Upload (TODO)
    
    override func uploadImageAndInsertToNote(imageURL: URL) async throws -> String {
        // TODO: 实现图片上传功能
        print("[NotesViewModelAdapter] uploadImageAndInsertToNote 待实现")
        throw NSError(domain: "MiNote", code: 501, userInfo: [NSLocalizedDescriptionKey: "功能待实现"])
    }
    
    // MARK: - Cookie Management
    
    override func handleCookieExpiredRefresh() {
        showCookieRefreshView = true
    }
    
    override func handleCookieExpiredCancel() {
        showLoginView = true
    }
    
    override func handleCookieRefreshed() {
        showCookieRefreshView = false
    }
    
    override func handleCookieExpiredSilently() async {
        // 静默刷新 Cookie
        await coordinator.authViewModel.refreshCookie()
    }
    
    // MARK: - Auto Refresh Cookie
    
    override func startAutoRefreshCookieIfNeeded() {
        // TODO: 实现自动刷新 Cookie 功能
        print("[NotesViewModelAdapter] startAutoRefreshCookieIfNeeded 待实现")
    }
    
    override func stopAutoRefreshCookie() {
        // TODO: 实现停止自动刷新 Cookie 功能
        print("[NotesViewModelAdapter] stopAutoRefreshCookie 待实现")
    }
    
    // MARK: - Sync Interval
    
    override func updateSyncInterval(_ newInterval: Double) {
        // TODO: 实现更新同步间隔功能
        print("[NotesViewModelAdapter] updateSyncInterval 待实现")
    }
    
    // MARK: - Pending Operations
    
    override func hasPendingUpload(for noteId: String) -> Bool {
        // TODO: 实现检查待上传功能
        return false
    }
    
    override func isTemporaryIdNote(_ noteId: String) -> Bool {
        return NoteOperation.isTemporaryId(noteId)
    }
    
    // MARK: - Note Content
    
    override func ensureNoteHasFullContent(_ note: Note) async {
        // 确保笔记有完整内容
        if note.content.isEmpty {
            await coordinator.noteEditorViewModel.loadNote(note)
        }
    }
}
