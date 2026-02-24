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
/// - 创建和管理所有 State 对象
/// - 处理跨 State 的协调逻辑
/// - 管理应用级别的状态
@MainActor
public final class AppCoordinator: ObservableObject {
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

    private let networkModule: NetworkModule
    private let syncModule: SyncModule
    private let editorModule: EditorModule
    private let audioModule: AudioModule

    // MARK: - 窗口管理

    private let windowManager: WindowManager

    // MARK: - 辅助服务

    private let startupSequenceManager: StartupSequenceManager
    public let errorRecoveryService: ErrorRecoveryService
    public let networkRecoveryHandler: NetworkRecoveryHandler
    public let onlineStateManager: OnlineStateManager
    private let passTokenManager: PassTokenManager

    // MARK: - 音频面板（暂不重构）

    let audioPanelViewModel: AudioPanelViewModel

    // MARK: - 初始化

    public init(
        networkModule: NetworkModule,
        syncModule: SyncModule,
        editorModule: EditorModule,
        audioModule: AudioModule,
        windowManager: WindowManager
    ) {
        self.networkModule = networkModule
        self.syncModule = syncModule
        self.editorModule = editorModule
        self.audioModule = audioModule
        self.windowManager = windowManager
        self.eventBus = EventBus.shared
        let noteStoreInstance = NoteStore(
            db: DatabaseService.shared,
            eventBus: EventBus.shared,
            operationQueue: syncModule.operationQueue,
            idMappingRegistry: syncModule.idMappingRegistry
        )
        self.noteStore = noteStoreInstance
        self.syncEngine = syncModule.createSyncEngine(noteStore: noteStoreInstance)
        self.noteListState = NoteListState(eventBus: EventBus.shared, noteStore: noteStoreInstance)
        self.noteEditorState = NoteEditorState(eventBus: EventBus.shared, noteStore: noteStoreInstance)
        self.folderState = FolderState(eventBus: EventBus.shared, noteStore: noteStoreInstance)
        self.syncState = SyncState(eventBus: EventBus.shared)
        self.authState = AuthState(eventBus: EventBus.shared, apiClient: networkModule.apiClient, userAPI: networkModule.userAPI)
        self.searchState = SearchState(noteStore: noteStoreInstance)

        self.audioPanelViewModel = AudioPanelViewModel(
            audioService: DefaultAudioService(cacheService: DefaultCacheService()),
            noteService: DefaultNoteStorage()
        )

        // 创建辅助服务（这些类型在 MiNoteLibrary 内部可访问）
        self.startupSequenceManager = StartupSequenceManager(
            localStorage: syncModule.localStorage,
            onlineStateManager: syncModule.onlineStateManager,
            operationProcessor: syncModule.operationProcessor,
            unifiedQueue: syncModule.operationQueue,
            eventBus: EventBus.shared,
            apiClient: networkModule.apiClient
        )

        self.errorRecoveryService = ErrorRecoveryService(
            unifiedQueue: syncModule.operationQueue,
            networkErrorHandler: NetworkErrorHandler.shared,
            onlineStateManager: syncModule.onlineStateManager
        )

        self.networkRecoveryHandler = NetworkRecoveryHandler(
            networkMonitor: NetworkMonitor.shared,
            onlineStateManager: syncModule.onlineStateManager,
            operationProcessor: syncModule.operationProcessor,
            unifiedQueue: syncModule.operationQueue,
            eventBus: EventBus.shared
        )

        self.passTokenManager = PassTokenManager(apiClient: networkModule.apiClient)

        self.onlineStateManager = syncModule.onlineStateManager

        LogService.shared.info(.app, "AppCoordinator 初始化完成")
    }

    /// Preview 和测试用的便利构造器
    convenience init() {
        let nm = NetworkModule()
        let sm = SyncModule(networkModule: nm)
        let em = EditorModule(syncModule: sm)
        let am = AudioModule(syncModule: sm, networkModule: nm)
        let wm = WindowManager()
        self.init(
            networkModule: nm,
            syncModule: sm,
            editorModule: em,
            audioModule: am,
            windowManager: wm
        )
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
        authState.start()

        if authState.isLoggedIn {
            await syncEngine.start()
        }
    }

    /// 停止新架构组件，释放事件订阅
    public func stop() {
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
}
