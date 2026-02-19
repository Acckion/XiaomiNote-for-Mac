//
//  NotesViewModelAdapter.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  NotesViewModel 适配器 - 将新架构适配到旧的 NotesViewModel 接口
//

import Combine
import Foundation

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

        LogService.shared.info(.viewmodel, "NotesViewModelAdapter 初始化完成")
    }

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

        // 同步同步状态（用于显示同步指示器）
        coordinator.syncCoordinator.$isSyncing
            .assign(to: &$isSyncing)

        // 6. 同步错误消息
        Publishers.Merge4(
            coordinator.noteListViewModel.$errorMessage.compactMap(\.self),
            coordinator.noteEditorViewModel.$errorMessage.compactMap(\.self),
            coordinator.syncCoordinator.$errorMessage.compactMap(\.self),
            coordinator.authViewModel.$errorMessage.compactMap(\.self)
        )
        .assign(to: &$errorMessage)

        // 7. 同步搜索文本
        coordinator.searchViewModel.$searchText
            .assign(to: &$searchText)

        // 8. 同步认证状态
        coordinator.authViewModel.$showLoginView
            .assign(to: &$showLoginView)

        coordinator.authViewModel.$isPrivateNotesUnlocked
            .assign(to: &$isPrivateNotesUnlocked)

        // 9. 同步 ViewOptionsManager 的排序设置到 NoteListViewModel
        // Bug 2.1 修复: 确保排序设置正确同步
        ViewOptionsManager.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }

                // 同步排序方式到 NoteListViewModel
                if coordinator.noteListViewModel.sortOrder != state.sortOrder {
                    LogService.shared.debug(.viewmodel, "从 ViewOptionsManager 同步排序方式: \(state.sortOrder.displayName)")
                    coordinator.noteListViewModel.sortOrder = state.sortOrder
                    notesListSortField = state.sortOrder
                }

                if coordinator.noteListViewModel.sortDirection != state.sortDirection {
                    LogService.shared.debug(.viewmodel, "从 ViewOptionsManager 同步排序方向: \(state.sortDirection.displayName)")
                    coordinator.noteListViewModel.sortDirection = state.sortDirection
                    notesListSortDirection = state.sortDirection
                }
            }
            .store(in: &cancellables)

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

        LogService.shared.debug(.viewmodel, "状态同步设置完成")
    }

    override public func loadFolders() {
        Task {
            await coordinator.folderViewModel.loadFolders()
        }
    }

    override public func selectFolderWithCoordinator(_ folder: Folder?) {
        coordinator.handleFolderSelection(folder)
    }

    override public func createFolder(name: String) async throws -> String {
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
        await coordinator.folderViewModel.toggleFolderPin(folder)
    }

    // MARK: - Note Operations

    override public func selectNoteWithCoordinator(_ note: Note?) {
        if let note {
            coordinator.handleNoteSelection(note)
        }
    }

    override public func createNote(_ note: Note) async throws {
        // NoteListViewModel 没有 createNote 方法,直接添加到列表
        coordinator.noteListViewModel.notes.append(note)

        // 保存到本地存储
        // TODO: 调用存储服务保存笔记
    }

    override func updateNote(_: Note) async throws {
        await coordinator.noteEditorViewModel.saveNote()
    }

    override public func updateNoteInPlace(_ note: Note) -> Bool {
        // 更新笔记列表中的笔记
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            return true
        }
        return false
    }

    override public func batchUpdateNotes(_ updates: [(noteId: String, update: (inout Note) -> Void)]) {
        for (noteId, update) in updates {
            if let index = notes.firstIndex(where: { $0.id == noteId }) {
                var note = notes[index]
                update(&note)
                notes[index] = note
            }
        }
    }

    override public func updateNoteTimestamp(_ noteId: String, timestamp: Date) -> Bool {
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

    override public func toggleStar(_ note: Note) {
        Task {
            await coordinator.noteListViewModel.toggleStar(note)
        }
    }

    override public func createNewNote() {
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

    override public func handleLoginSuccess() async {
        // 登录成功后启动同步
        await coordinator.syncCoordinator.startSync()

        // 加载用户信息
        await coordinator.authViewModel.fetchUserProfile()
    }

    override public func handleCookieRefreshSuccess() async {
        // Cookie 刷新成功后重新同步
        await coordinator.syncCoordinator.startSync()
    }

    override func verifyPrivateNotesPassword(_ password: String) -> Bool {
        // 使用 PrivateNotesPasswordManager 进行同步密码验证
        let isValid = PrivateNotesPasswordManager.shared.verifyPassword(password)
        if isValid {
            coordinator.authViewModel.isPrivateNotesUnlocked = true
        }
        return isValid
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
        folderSortOrders[folder.id]
    }

    // MARK: - Note History (TODO)

    override func getNoteHistoryTimes(noteId: String) async throws -> [NoteHistoryVersion] {
        // 笔记历史功能需要直接调用 MiNoteService
        // 因为 NoteServiceProtocol 中没有定义这些方法
        let response = try await MiNoteService.shared.getNoteHistoryTimes(noteId: noteId)

        guard let code = response["code"] as? Int, code == 0,
              let data = response["data"] as? [String: Any],
              let tvList = data["tvList"] as? [[String: Any]]
        else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])
        }

        var versions: [NoteHistoryVersion] = []
        for item in tvList {
            if let updateTime = item["updateTime"] as? Int64,
               let version = item["version"] as? Int64
            {
                versions.append(NoteHistoryVersion(version: version, updateTime: updateTime))
            }
        }

        return versions
    }

    override func getNoteHistory(noteId: String, version: Int64) async throws -> Note {
        // 笔记历史功能需要直接调用 MiNoteService
        let response = try await MiNoteService.shared.getNoteHistory(noteId: noteId, version: version)

        guard let code = response["code"] as? Int, code == 0,
              let data = response["data"] as? [String: Any],
              let entry = data["entry"] as? [String: Any]
        else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])
        }

        // 使用 Note.fromMinoteData 解析历史记录数据
        guard var note = Note.fromMinoteData(entry) else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法解析笔记数据"])
        }

        // 使用 updateContent 更新内容
        note.updateContent(from: response)

        return note
    }

    override func restoreNoteHistory(noteId: String, version: Int64) async throws {
        // 笔记历史功能需要直接调用 MiNoteService
        let response = try await MiNoteService.shared.restoreNoteHistory(noteId: noteId, version: version)

        guard let code = response["code"] as? Int, code == 0 else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "恢复历史记录失败"])
        }

        // 恢复成功后,重新同步笔记以获取最新数据
        await coordinator.syncCoordinator.forceFullSync()

        // 更新选中的笔记
        if let index = notes.firstIndex(where: { $0.id == noteId }) {
            selectedNote = notes[index]
        }
    }

    // MARK: - Deleted Notes (TODO)

    override func fetchDeletedNotes() async {
        // 回收站功能需要直接调用 MiNoteService
        do {
            let response = try await MiNoteService.shared.fetchDeletedNotes()

            guard let code = response["code"] as? Int, code == 0,
                  let data = response["data"] as? [String: Any],
                  let entries = data["entries"] as? [[String: Any]]
            else {
                LogService.shared.error(.viewmodel, "获取回收站笔记失败: 无效的响应")
                return
            }

            var deletedNotesList: [DeletedNote] = []
            for entry in entries {
                if let deletedNote = DeletedNote.fromAPIResponse(entry) {
                    deletedNotesList.append(deletedNote)
                }
            }

            deletedNotes = deletedNotesList
            LogService.shared.info(.viewmodel, "获取回收站笔记成功，共 \(deletedNotesList.count) 条")
        } catch {
            LogService.shared.error(.viewmodel, "获取回收站笔记失败: \(error.localizedDescription)")
            deletedNotes = []
        }
    }

    // MARK: - Image Upload (TODO)

    override func uploadImageAndInsertToNote(imageURL: URL) async throws -> String {
        // 图片上传功能需要直接调用 MiNoteService 和 LocalStorageService
        guard let note = selectedNote else {
            throw NSError(domain: "MiNote", code: 400, userInfo: [NSLocalizedDescriptionKey: "请先选择笔记"])
        }

        // 读取图片数据
        let imageData = try Data(contentsOf: imageURL)
        let fileName = imageURL.lastPathComponent

        // 根据文件扩展名推断 MIME 类型
        let fileExtension = (imageURL.pathExtension as NSString).lowercased
        let mimeType = switch fileExtension {
        case "jpg", "jpeg":
            "image/jpeg"
        case "png":
            "image/png"
        case "gif":
            "image/gif"
        case "webp":
            "image/webp"
        default:
            "image/jpeg"
        }

        // 上传图片
        let uploadResult = try await MiNoteService.shared.uploadImage(
            imageData: imageData,
            fileName: fileName,
            mimeType: mimeType
        )

        guard let fileId = uploadResult["fileId"] as? String,
              let digest = uploadResult["digest"] as? String
        else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "上传图片失败：服务器返回无效响应"])
        }

        LogService.shared.info(.viewmodel, "图片上传成功: fileId=\(fileId)")

        // 保存图片到本地
        let fileType = String(mimeType.dropFirst("image/".count))
        try LocalStorageService.shared.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)

        // 更新笔记的 setting.data，添加图片信息
        var updatedNote = note
        var rawData = updatedNote.rawData ?? [:]
        var setting = rawData["setting"] as? [String: Any] ?? [
            "themeId": 0,
            "stickyTime": 0,
            "version": 0,
        ]

        var settingData = setting["data"] as? [[String: Any]] ?? []
        let imageInfo: [String: Any] = [
            "fileId": fileId,
            "mimeType": mimeType,
            "digest": digest,
        ]
        settingData.append(imageInfo)
        setting["data"] = settingData
        rawData["setting"] = setting
        updatedNote.rawData = rawData

        // 更新笔记
        await coordinator.noteEditorViewModel.saveNote()

        LogService.shared.debug(.viewmodel, "图片已添加到笔记 setting.data: noteId=\(note.id), fileId=\(fileId)")

        return fileId
    }

    // MARK: - Cookie Management

    override func handleCookieExpiredRefresh() {
        // PassToken 重构后，Cookie 过期时提示重新登录
        showLoginView = true
    }

    override func handleCookieExpiredCancel() {
        showLoginView = true
    }

    override func handleCookieRefreshed() {
        // PassToken 重构后不再需要 CookieRefreshView
    }

    override func handleCookieExpiredSilently() async {
        // 静默刷新 Cookie
        await coordinator.authViewModel.refreshCookie()
    }

    // MARK: - Auto Refresh Cookie

    override func startAutoRefreshCookieIfNeeded() {
        // 自动刷新 Cookie 功能由 AuthenticationViewModel 管理
        // 这里只需要启动定时器
        coordinator.authViewModel.startAutoRefreshCookieIfNeeded()
    }

    override func stopAutoRefreshCookie() {
        // 停止自动刷新 Cookie 功能由 AuthenticationViewModel 管理
        coordinator.authViewModel.stopAutoRefreshCookie()
    }

    // MARK: - Sync Interval

    override func updateSyncInterval(_ newInterval: Double) {
        // 更新同步间隔由 SyncCoordinator 管理
        coordinator.syncCoordinator.updateSyncInterval(newInterval)
        syncInterval = newInterval
    }

    // MARK: - Pending Operations

    override func hasPendingUpload(for noteId: String) -> Bool {
        // 检查统一操作队列中是否有待上传的操作
        // 直接使用 UnifiedOperationQueue.shared
        UnifiedOperationQueue.shared.hasPendingUpload(for: noteId)
    }

    override func isTemporaryIdNote(_ noteId: String) -> Bool {
        NoteOperation.isTemporaryId(noteId)
    }

    // MARK: - Note Content

    override func ensureNoteHasFullContent(_ note: Note) async {
        // 确保笔记有完整内容
        if note.content.isEmpty {
            await coordinator.noteEditorViewModel.loadNote(note)
        }
    }
}
