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

    public let networkModule: NetworkModule
    public let syncModule: SyncModule
    public let editorModule: EditorModule
    public let audioModule: AudioModule

    // MARK: - 窗口管理

    private let windowManager: WindowManager

    // MARK: - 辅助服务

    private let startupSequenceManager: StartupSequenceManager
    public let errorRecoveryService: ErrorRecoveryService
    public let networkRecoveryHandler: NetworkRecoveryHandler
    public let onlineStateManager: OnlineStateManager
    public let notePreviewService: NotePreviewService
    let passTokenManager: PassTokenManager

    // MARK: - 缓存

    public let memoryCacheManager: MemoryCacheManager

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
            idMappingRegistry: syncModule.idMappingRegistry,
            localStorage: syncModule.localStorage,
            operationProcessor: syncModule.operationProcessor
        )
        self.noteStore = noteStoreInstance
        self.syncEngine = syncModule.createSyncEngine(noteStore: noteStoreInstance)
        self.noteListState = NoteListState(
            eventBus: EventBus.shared,
            noteStore: noteStoreInstance,
            apiClient: networkModule.apiClient,
            noteAPI: networkModule.noteAPI
        )
        self.noteEditorState = NoteEditorState(
            eventBus: EventBus.shared,
            noteStore: noteStoreInstance,
            noteAPI: networkModule.noteAPI,
            operationQueue: syncModule.operationQueue,
            localStorage: syncModule.localStorage,
            operationProcessor: syncModule.operationProcessor
        )
        self.folderState = FolderState(eventBus: EventBus.shared, noteStore: noteStoreInstance)
        self.syncState = SyncState(eventBus: EventBus.shared, operationQueue: syncModule.operationQueue)

        let ptm = PassTokenManager(apiClient: networkModule.apiClient)
        self.passTokenManager = ptm

        self.authState = AuthState(
            eventBus: EventBus.shared,
            apiClient: networkModule.apiClient,
            userAPI: networkModule.userAPI,
            onlineStateManager: syncModule.onlineStateManager,
            passTokenManager: ptm
        )
        self.searchState = SearchState(noteStore: noteStoreInstance)

        self.audioPanelViewModel = AudioPanelViewModel(
            audioService: DefaultAudioService(cacheService: DefaultCacheService()),
            noteService: DefaultNoteStorage()
        )

        self.memoryCacheManager = MemoryCacheManager()

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

        // 接线 PassTokenManager 到 NetworkModule（解决循环依赖）
        networkModule.setPassTokenManager(ptm)

        self.notePreviewService = NotePreviewService(localStorage: syncModule.localStorage)

        self.onlineStateManager = syncModule.onlineStateManager

        // 接线编辑器依赖到 NativeEditorContext
        noteEditorState.nativeEditorContext.customRenderer = editorModule.customRenderer
        noteEditorState.nativeEditorContext.imageStorageManager = editorModule.imageStorageManager
        noteEditorState.nativeEditorContext.formatStateManager = editorModule.formatStateManager
        noteEditorState.nativeEditorContext.unifiedFormatManager = editorModule.unifiedFormatManager
        noteEditorState.nativeEditorContext.formatConverter = editorModule.formatConverter
        noteEditorState.nativeEditorContext.attachmentSelectionManager = editorModule.attachmentSelectionManager

        // 接线编辑器监控和格式管理依赖
        noteEditorState.nativeEditorContext.performanceMonitor = editorModule.performanceMonitor
        noteEditorState.nativeEditorContext.xmlNormalizer = editorModule.xmlNormalizer
        noteEditorState.nativeEditorContext.cursorFormatManager = editorModule.cursorFormatManager

        // 接线编辑器辅助组件依赖
        noteEditorState.nativeEditorContext.specialElementFormatHandler = editorModule.specialElementFormatHandler
        noteEditorState.nativeEditorContext.performanceCache = editorModule.performanceCache
        noteEditorState.nativeEditorContext.typingOptimizer = editorModule.typingOptimizer
        noteEditorState.nativeEditorContext.attachmentKeyboardHandler = editorModule.attachmentKeyboardHandler
        noteEditorState.nativeEditorContext.editorConfigurationManager = editorModule.editorConfigurationManager

        // 接线音频面板状态管理器
        noteEditorState.nativeEditorContext.audioPanelStateManager = audioModule.panelStateManager

        LogService.shared.info(.app, "AppCoordinator 初始化完成")
    }

    /// Preview 和测试用的便利构造器
    convenience init() {
        let nm = NetworkModule()
        let sm = SyncModule(networkModule: nm)
        let em = EditorModule(syncModule: sm, networkModule: nm)
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

    // MARK: - 窗口管理代理

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
}
