//
//  AppCoordinator.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  应用协调器 - 管理所有 ViewModel 并协调它们之间的通信
//

import Combine
import Foundation

/// 应用协调器
///
/// 负责：
/// - 创建和管理所有 ViewModel
/// - 处理 ViewModel 之间的通信
/// - 管理应用级别的状态
@MainActor
public final class AppCoordinator: ObservableObject {
    // MARK: - ViewModels

    /// 笔记列表视图模型
    public let noteListViewModel: NoteListViewModel

    /// 笔记编辑器视图模型
    public let noteEditorViewModel: NoteEditorViewModel

    /// 同步协调器
    public let syncCoordinator: SyncCoordinator

    /// 认证视图模型
    public let authViewModel: AuthenticationViewModel

    /// 搜索视图模型
    public let searchViewModel: SearchViewModel

    /// 文件夹视图模型
    public let folderViewModel: FolderViewModel

    /// 音频面板视图模型
    public let audioPanelViewModel: AudioPanelViewModel

    /// NotesViewModel 适配器（用于向后兼容）
    public private(set) lazy var notesViewModel: NotesViewModel = NotesViewModelAdapter(coordinator: self)

    // MARK: - Dependencies

    private let container: DIContainer

    // MARK: - Private Properties

    /// Cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// 初始化应用协调器
    /// - Parameter container: 依赖注入容器
    public init(container: DIContainer = .shared) {
        self.container = container

        // 解析服务
        let noteStorage = container.resolve(NoteStorageProtocol.self)
        let noteService = container.resolve(NoteServiceProtocol.self)
        let syncService = container.resolve(SyncServiceProtocol.self)
        let networkMonitor = container.resolve(NetworkMonitorProtocol.self)
        let authService = container.resolve(AuthenticationServiceProtocol.self)
        let audioService = container.resolve(AudioServiceProtocol.self)

        // 创建所有 ViewModel
        self.noteListViewModel = NoteListViewModel(
            noteStorage: noteStorage,
            noteService: noteService
        )

        self.noteEditorViewModel = NoteEditorViewModel(
            noteStorage: noteStorage,
            noteService: noteService
        )

        self.syncCoordinator = SyncCoordinator(
            syncService: syncService,
            noteStorage: noteStorage,
            networkMonitor: networkMonitor
        )

        self.authViewModel = AuthenticationViewModel(
            authService: authService,
            noteStorage: noteStorage
        )

        self.searchViewModel = SearchViewModel(
            noteStorage: noteStorage,
            noteService: noteService
        )

        self.folderViewModel = FolderViewModel(
            noteStorage: noteStorage,
            noteService: noteService
        )

        self.audioPanelViewModel = AudioPanelViewModel(
            audioService: audioService,
            noteService: noteStorage
        )

        // 设置 ViewModel 之间的通信
        setupCommunication()

        LogService.shared.info(.app, "AppCoordinator 初始化完成")
    }

    // MARK: - Public Methods

    /// 启动应用
    public func start() async {
        LogService.shared.info(.app, "启动应用")

        await folderViewModel.loadFolders()
        await noteListViewModel.loadNotes()

        if authViewModel.isLoggedIn {
            await syncCoordinator.startSync()
        }
    }

    // MARK: - Private Methods - Communication Setup

    /// 设置 ViewModel 之间的通信
    private func setupCommunication() {
        // 1. 笔记选择 → 编辑器加载
        setupNoteSelectionCommunication()

        // 2. 文件夹选择 → 笔记列表过滤
        setupFolderSelectionCommunication()

        // 3. 同步完成 → 刷新笔记列表
        setupSyncCompletionCommunication()

        // 4. 认证状态变化 → 启动同步
        setupAuthenticationCommunication()

        // 5. 搜索结果 → 笔记列表更新
        setupSearchCommunication()

        // 6. 笔记编辑 → 列表更新
        setupNoteEditCommunication()
    }

    /// 设置笔记选择通信
    private func setupNoteSelectionCommunication() {
        noteListViewModel.$selectedNote
            .compactMap(\.self)
            .sink { [weak self] note in
                guard let self else { return }
                LogService.shared.debug(.app, "笔记选择: \(note.title)")
                Task { @MainActor in
                    await self.noteEditorViewModel.loadNote(note)
                }
            }
            .store(in: &cancellables)
    }

    /// 设置文件夹选择通信
    private func setupFolderSelectionCommunication() {
        folderViewModel.$selectedFolder
            .sink { [weak self] folder in
                guard let self else { return }
                if let folder {
                    LogService.shared.debug(.app, "文件夹选择: \(folder.name)")
                }
                noteListViewModel.selectedFolder = folder
            }
            .store(in: &cancellables)
    }

    /// 设置同步完成通信
    private func setupSyncCompletionCommunication() {
        syncCoordinator.$isSyncing
            .removeDuplicates()
            .sink { [weak self] isSyncing in
                guard let self else { return }
                if !isSyncing {
                    LogService.shared.info(.app, "同步完成，刷新笔记列表和文件夹")
                    Task { @MainActor in
                        await self.folderViewModel.loadFolders()
                        await self.noteListViewModel.loadNotes()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// 设置认证状态通信
    private func setupAuthenticationCommunication() {
        authViewModel.$isLoggedIn
            .filter(\.self)
            .sink { [weak self] _ in
                guard let self else { return }
                LogService.shared.info(.app, "用户已登录，启动同步")
                Task { @MainActor in
                    await self.syncCoordinator.startSync()
                }
            }
            .store(in: &cancellables)

        authViewModel.$isLoggedIn
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self else { return }
                LogService.shared.info(.app, "用户已登出，停止同步")
                Task { @MainActor in
                    await self.syncCoordinator.stopSync()
                }
            }
            .store(in: &cancellables)
    }

    /// 设置搜索通信
    private func setupSearchCommunication() {
        searchViewModel.$searchResults
            .sink { [weak self] results in
                guard let self else { return }
                if !results.isEmpty {
                    LogService.shared.debug(.app, "搜索结果: \(results.count) 条笔记")
                    noteListViewModel.notes = results
                }
            }
            .store(in: &cancellables)

        searchViewModel.$searchText
            .filter(\.isEmpty)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.noteListViewModel.loadNotes()
                }
            }
            .store(in: &cancellables)
    }

    /// 设置笔记编辑通信
    private func setupNoteEditCommunication() {
        // 监听笔记保存事件
        noteEditorViewModel.$currentNote
            .compactMap(\.self)
            .sink { [weak self] note in
                guard let self else { return }

                // 延迟到下一个 RunLoop 周期，避免在视图更新周期内修改 @Published 属性
                DispatchQueue.main.async {
                    if let index = self.noteListViewModel.notes.firstIndex(where: { $0.id == note.id }) {
                        self.noteListViewModel.notes[index] = note
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods - Actions

    /// 处理笔记选择
    /// - Parameter note: 选中的笔记
    public func handleNoteSelection(_ note: Note) {
        noteListViewModel.selectNote(note)
    }

    /// 处理文件夹选择
    /// - Parameter folder: 选中的文件夹
    public func handleFolderSelection(_ folder: Folder?) {
        folderViewModel.selectFolder(folder)

        // 处理私密笔记文件夹的解锁状态
        if let folder, folder.id == "2" {
            if PrivateNotesPasswordManager.shared.hasPassword() {
                authViewModel.isPrivateNotesUnlocked = false
            } else {
                authViewModel.isPrivateNotesUnlocked = true
            }
        } else {
            authViewModel.isPrivateNotesUnlocked = false
        }
    }

    /// 处理同步请求
    public func handleSyncRequest() async {
        await syncCoordinator.startSync()
    }

    /// 处理搜索请求
    /// - Parameter keyword: 搜索关键词
    public func handleSearchRequest(_ keyword: String) {
        searchViewModel.search(keyword: keyword)
    }

    /// 处理清除搜索
    public func handleClearSearch() {
        searchViewModel.clearSearch()
    }
}
