//
//  AppCoordinator.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  应用协调器 - 管理 State 对象并协调它们之间的通信
//

import Foundation

/// 应用协调器
///
/// 负责：
/// - 管理所有 State 对象
/// - 处理跨 State 的协调逻辑
/// - 管理应用级别的状态
@MainActor
public final class AppCoordinator: ObservableObject {
    public struct Dependencies {
        public let eventBus: EventBus
        public let noteStore: NoteStore
        public let syncEngine: SyncEngine
        public let noteListState: NoteListState
        public let noteEditorState: NoteEditorState
        public let folderState: FolderState
        public let syncState: SyncState
        public let authState: AuthState
        public let searchState: SearchState
        public let networkModule: NetworkModule
        public let syncModule: SyncModule
        public let editorModule: EditorModule
        public let audioModule: AudioModule
        let startupSequenceManager: StartupSequenceManager
        public let errorRecoveryService: ErrorRecoveryService
        public let networkRecoveryHandler: NetworkRecoveryHandler
        public let onlineStateManager: OnlineStateManager
        public let notePreviewService: NotePreviewService
        let passTokenManager: PassTokenManager
        public let memoryCacheManager: MemoryCacheManager
        let audioPanelViewModel: AudioPanelViewModel
    }

    // MARK: - 核心基础设施

    public let eventBus: EventBus
    public let noteStore: NoteStore
    public let syncEngine: SyncEngine

    // MARK: - State 对象

    public let noteListState: NoteListState
    public let noteEditorState: NoteEditorState
    public let folderState: FolderState
    public let syncState: SyncState
    public let authState: AuthState
    public let searchState: SearchState

    // MARK: - 模块

    public let networkModule: NetworkModule
    public let syncModule: SyncModule
    public let editorModule: EditorModule
    public let audioModule: AudioModule

    // MARK: - 窗口管理

    private let windowManager: WindowManager

    /// 格式状态管理器（从 EditorModule 获取，供 Command 使用）
    public var formatStateManager: FormatStateManager? {
        editorModule.formatStateManager
    }

    /// 主窗口控制器（供 Command 使用）
    public var mainWindowController: MainWindowController? {
        windowManager.mainWindowController
    }

    // MARK: - 辅助服务

    private let startupSequenceManager: StartupSequenceManager
    public let errorRecoveryService: ErrorRecoveryService
    public let networkRecoveryHandler: NetworkRecoveryHandler
    public let onlineStateManager: OnlineStateManager
    public let notePreviewService: NotePreviewService
    let passTokenManager: PassTokenManager

    // MARK: - 缓存

    public let memoryCacheManager: MemoryCacheManager

    // MARK: - 命令调度

    public private(set) var commandDispatcher: CommandDispatcher!

    // MARK: - 音频面板（暂不重构）

    let audioPanelViewModel: AudioPanelViewModel

    // MARK: - 事件订阅

    private var authEventTask: Task<Void, Never>?

    // MARK: - 初始化

    public init(dependencies: Dependencies, windowManager: WindowManager) {
        self.eventBus = dependencies.eventBus
        self.noteStore = dependencies.noteStore
        self.syncEngine = dependencies.syncEngine
        self.noteListState = dependencies.noteListState
        self.noteEditorState = dependencies.noteEditorState
        self.folderState = dependencies.folderState
        self.syncState = dependencies.syncState
        self.authState = dependencies.authState
        self.searchState = dependencies.searchState
        self.networkModule = dependencies.networkModule
        self.syncModule = dependencies.syncModule
        self.editorModule = dependencies.editorModule
        self.audioModule = dependencies.audioModule
        self.windowManager = windowManager
        self.startupSequenceManager = dependencies.startupSequenceManager
        self.errorRecoveryService = dependencies.errorRecoveryService
        self.networkRecoveryHandler = dependencies.networkRecoveryHandler
        self.onlineStateManager = dependencies.onlineStateManager
        self.notePreviewService = dependencies.notePreviewService
        self.passTokenManager = dependencies.passTokenManager
        self.memoryCacheManager = dependencies.memoryCacheManager
        self.audioPanelViewModel = dependencies.audioPanelViewModel

        self.commandDispatcher = CommandDispatcher(coordinator: self)

        LogService.shared.info(.app, "AppCoordinator 初始化完成")
    }

    /// Preview 和测试用的便利构造器
    convenience init() {
        let wm = WindowManager()
        let dependencies = AppCoordinatorAssembler.buildDependencies()
        self.init(dependencies: dependencies, windowManager: wm)
    }

    // MARK: - 生命周期

    /// 启动应用
    public func start() async {
        LogService.shared.info(.app, "启动应用")

        await noteStore.start()
        await noteListState.start()
        noteEditorState.start()
        await folderState.start()
        syncState.start()
        await authState.start()

        if authState.isLoggedIn {
            await syncEngine.start()
        }

        subscribeAuthEvents()
    }

    /// 停止新架构组件，释放事件订阅
    public func stop() {
        authEventTask?.cancel()
        authEventTask = nil
        noteListState.stop()
        noteEditorState.stop()
        folderState.stop()
        syncState.stop()
        authState.stop()
        Task { await syncEngine.stop() }
    }

    // MARK: - 协调方法

    /// 处理笔记选择
    public func handleNoteSelection(_ note: Note) {
        noteListState.selectNote(note)
        noteEditorState.loadNote(note)
    }

    /// 处理文件夹选择
    public func handleFolderSelection(_ folder: Folder?) {
        folderState.selectFolder(folder)

        // 同步文件夹选择到 NoteListState，用于过滤
        noteListState.selectedFolder = folder
        noteListState.selectedFolderId = folder?.id

        if let folder, folder.id == "2" {
            if PrivateNotesPasswordManager.shared.hasPassword() {
                authState.isPrivateNotesUnlocked = false
            } else {
                authState.isPrivateNotesUnlocked = true
            }
        } else {
            authState.isPrivateNotesUnlocked = false
        }
    }

    /// 处理同步请求
    public func handleSyncRequest() async {
        syncState.requestSync(mode: .full(.normal))
    }

    /// 处理搜索请求
    public func handleSearchRequest(_ keyword: String) {
        Task {
            await searchState.search(keyword: keyword)
            // 同步搜索文本到 NoteListState，用于过滤和高亮
            noteListState.searchText = keyword
        }
    }

    /// 处理清除搜索
    public func handleClearSearch() {
        searchState.clearSearch()
        noteListState.searchText = ""
    }

    // MARK: - 窗口管理代理

    /// 创建新窗口
    @discardableResult
    public func createNewWindow() -> MainWindowController? {
        windowManager.createNewWindow()
    }

    /// 在新窗口中打开笔记
    public func openNoteEditorWindow(note: Note) {
        windowManager.openNoteEditorWindow(note: note)
    }

    /// 移除编辑器窗口
    public func removeEditorWindow(_ controller: NoteEditorWindowController) {
        windowManager.removeEditorWindow(controller)
    }

    /// 移除主窗口控制器
    public func removeWindowController(_ controller: MainWindowController) {
        windowManager.removeWindowController(controller)
    }

    // MARK: - 登录事件订阅

    /// 监听登录事件，登录成功后启动 SyncEngine
    private func subscribeAuthEvents() {
        authEventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: AuthEvent.self)
            for await event in stream {
                guard !Task.isCancelled else { break }
                if case .loggedIn = event {
                    LogService.shared.info(.app, "用户登录成功，启动 SyncEngine")
                    await syncEngine.start()
                }
            }
        }
    }
}
