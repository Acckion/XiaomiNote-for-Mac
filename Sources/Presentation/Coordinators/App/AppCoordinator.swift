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
        noteListViewModel = NoteListViewModel(
            noteStorage: noteStorage,
            noteService: noteService
        )

        noteEditorViewModel = NoteEditorViewModel(
            noteStorage: noteStorage,
            noteService: noteService
        )

        syncCoordinator = SyncCoordinator(
            syncService: syncService,
            noteStorage: noteStorage,
            networkMonitor: networkMonitor
        )

        authViewModel = AuthenticationViewModel(
            authService: authService,
            noteStorage: noteStorage
        )

        searchViewModel = SearchViewModel(
            noteStorage: noteStorage,
            noteService: noteService
        )

        folderViewModel = FolderViewModel(
            noteStorage: noteStorage,
            noteService: noteService
        )

        audioPanelViewModel = AudioPanelViewModel(
            audioService: audioService,
            noteService: noteStorage
        )

        // 设置 ViewModel 之间的通信
        setupCommunication()

        print("[AppCoordinator] 初始化完成")
    }

    // MARK: - Public Methods

    /// 启动应用
    public func start() async {
        print("[AppCoordinator] 启动应用")

        // 加载文件夹列表
        await folderViewModel.loadFolders()

        // 加载笔记列表
        await noteListViewModel.loadNotes()

        // 如果已登录，启动同步
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

                print("[AppCoordinator] 笔记选择: \(note.title)")

                // 加载笔记到编辑器
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
                    print("[AppCoordinator] 文件夹选择: \(folder.name)")
                } else {
                    print("[AppCoordinator] 清除文件夹选择")
                }

                // 更新笔记列表的选中文件夹
                noteListViewModel.selectedFolder = folder

                // 注意：不需要重新加载笔记列表，因为 filteredNotes 会自动根据 selectedFolder 过滤
                // 笔记列表已经在内存中，只需要过滤即可
                print("[AppCoordinator] 笔记列表将根据文件夹过滤，当前笔记总数: \(noteListViewModel.notes.count)")
            }
            .store(in: &cancellables)
    }

    /// 设置同步完成通信
    private func setupSyncCompletionCommunication() {
        // 监听同步状态变化
        syncCoordinator.$isSyncing
            .removeDuplicates()
            .sink { [weak self] isSyncing in
                guard let self else { return }

                // 当同步完成时（从 true 变为 false），刷新数据
                if !isSyncing {
                    print("[AppCoordinator] 同步完成，刷新笔记列表和文件夹")

                    // 刷新笔记列表和文件夹
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
            .filter(\.self) // 只在登录时触发
            .sink { [weak self] _ in
                guard let self else { return }

                print("[AppCoordinator] 用户已登录，启动同步")

                // 启动同步
                Task { @MainActor in
                    await self.syncCoordinator.startSync()
                }
            }
            .store(in: &cancellables)

        // 登出时停止同步
        authViewModel.$isLoggedIn
            .filter { !$0 } // 只在登出时触发
            .sink { [weak self] _ in
                guard let self else { return }

                print("[AppCoordinator] 用户已登出，停止同步")

                // 停止同步
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
                    print("[AppCoordinator] 搜索结果: \(results.count) 条笔记")

                    // 更新笔记列表显示搜索结果
                    noteListViewModel.notes = results
                }
            }
            .store(in: &cancellables)

        // 清除搜索时恢复笔记列表
        searchViewModel.$searchText
            .filter(\.isEmpty)
            .sink { [weak self] _ in
                guard let self else { return }

                print("[AppCoordinator] 清除搜索，恢复笔记列表")

                // 重新加载笔记列表
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

                // 更新笔记列表中的笔记
                if let index = noteListViewModel.notes.firstIndex(where: { $0.id == note.id }) {
                    noteListViewModel.notes[index] = note
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
            // 切换到私密笔记文件夹
            // 检查是否已设置密码
            if PrivateNotesPasswordManager.shared.hasPassword() {
                // 每次切换到私密笔记文件夹时，都需要重新验证
                // 重置解锁状态，强制用户重新验证
                authViewModel.isPrivateNotesUnlocked = false
                print("[AppCoordinator] 切换到私密笔记文件夹，重置解锁状态")
            } else {
                // 未设置密码，直接允许访问
                authViewModel.isPrivateNotesUnlocked = true
                print("[AppCoordinator] 私密笔记未设置密码，直接解锁")
            }
        } else {
            // 切换到其他文件夹，重置解锁状态
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
