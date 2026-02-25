import Foundation

/// AppCoordinator 依赖装配器
///
/// 将应用根装配逻辑集中在此，避免协调器承担实例构建职责。
@MainActor
public enum AppCoordinatorAssembler {
    public static func assemble(windowManager: WindowManager) -> AppCoordinator {
        let dependencies = buildDependencies()
        return AppCoordinator(dependencies: dependencies, windowManager: windowManager)
    }

    static func buildDependencies() -> AppCoordinator.Dependencies {
        let networkModule = NetworkModule()
        let syncModule = SyncModule(networkModule: networkModule)

        // 跨模块依赖：NetworkRequestManager 需要感知在线状态
        networkModule.requestManager.setOnlineStateManager(syncModule.onlineStateManager)

        let editorModule = EditorModule(syncModule: syncModule, networkModule: networkModule)
        let audioModule = AudioModule(syncModule: syncModule, networkModule: networkModule)

        let eventBus = EventBus.shared
        let noteStore = NoteStore(
            db: DatabaseService.shared,
            eventBus: eventBus,
            operationQueue: syncModule.operationQueue,
            idMappingRegistry: syncModule.idMappingRegistry,
            localStorage: syncModule.localStorage,
            operationProcessor: syncModule.operationProcessor
        )
        let syncEngine = syncModule.createSyncEngine(noteStore: noteStore)

        let noteListState = NoteListState(
            eventBus: eventBus,
            noteStore: noteStore,
            apiClient: networkModule.apiClient,
            noteAPI: networkModule.noteAPI
        )
        let noteEditorState = NoteEditorState(
            eventBus: eventBus,
            noteStore: noteStore,
            noteAPI: networkModule.noteAPI,
            operationQueue: syncModule.operationQueue,
            localStorage: syncModule.localStorage,
            operationProcessor: syncModule.operationProcessor
        )
        let folderState = FolderState(eventBus: eventBus, noteStore: noteStore)
        let syncState = SyncState(eventBus: eventBus, operationQueue: syncModule.operationQueue)

        let passTokenManager = PassTokenManager(apiClient: networkModule.apiClient)
        let authState = AuthState(
            eventBus: eventBus,
            apiClient: networkModule.apiClient,
            userAPI: networkModule.userAPI,
            onlineStateManager: syncModule.onlineStateManager,
            passTokenManager: passTokenManager
        )
        let searchState = SearchState(noteStore: noteStore)

        let startupSequenceManager = StartupSequenceManager(
            localStorage: syncModule.localStorage,
            onlineStateManager: syncModule.onlineStateManager,
            operationProcessor: syncModule.operationProcessor,
            unifiedQueue: syncModule.operationQueue,
            eventBus: eventBus,
            apiClient: networkModule.apiClient
        )
        let errorRecoveryService = ErrorRecoveryService(
            unifiedQueue: syncModule.operationQueue,
            networkErrorHandler: NetworkErrorHandler.shared,
            onlineStateManager: syncModule.onlineStateManager
        )
        let networkRecoveryHandler = NetworkRecoveryHandler(
            networkMonitor: NetworkMonitor.shared,
            onlineStateManager: syncModule.onlineStateManager,
            operationProcessor: syncModule.operationProcessor,
            unifiedQueue: syncModule.operationQueue,
            eventBus: eventBus
        )

        networkModule.setPassTokenManager(passTokenManager)
        wireEditorContext(
            noteEditorState: noteEditorState,
            editorModule: editorModule,
            audioModule: audioModule
        )

        return AppCoordinator.Dependencies(
            eventBus: eventBus,
            noteStore: noteStore,
            syncEngine: syncEngine,
            noteListState: noteListState,
            noteEditorState: noteEditorState,
            folderState: folderState,
            syncState: syncState,
            authState: authState,
            searchState: searchState,
            networkModule: networkModule,
            syncModule: syncModule,
            editorModule: editorModule,
            audioModule: audioModule,
            startupSequenceManager: startupSequenceManager,
            errorRecoveryService: errorRecoveryService,
            networkRecoveryHandler: networkRecoveryHandler,
            onlineStateManager: syncModule.onlineStateManager,
            notePreviewService: NotePreviewService(localStorage: syncModule.localStorage),
            passTokenManager: passTokenManager,
            memoryCacheManager: MemoryCacheManager(),
            audioPanelViewModel: AudioPanelViewModel(
                audioService: DefaultAudioService(cacheService: DefaultCacheService()),
                noteService: DefaultNoteStorage()
            )
        )
    }

    private static func wireEditorContext(
        noteEditorState: NoteEditorState,
        editorModule: EditorModule,
        audioModule: AudioModule
    ) {
        let context = noteEditorState.nativeEditorContext
        context.customRenderer = editorModule.customRenderer
        context.imageStorageManager = editorModule.imageStorageManager
        context.formatStateManager = editorModule.formatStateManager
        context.unifiedFormatManager = editorModule.unifiedFormatManager
        context.formatConverter = editorModule.formatConverter
        context.attachmentSelectionManager = editorModule.attachmentSelectionManager
        context.xmlNormalizer = editorModule.xmlNormalizer
        context.cursorFormatManager = editorModule.cursorFormatManager
        context.specialElementFormatHandler = editorModule.specialElementFormatHandler
        context.performanceCache = editorModule.performanceCache
        context.typingOptimizer = editorModule.typingOptimizer
        context.attachmentKeyboardHandler = editorModule.attachmentKeyboardHandler
        context.editorConfigurationManager = editorModule.editorConfigurationManager
        context.audioPanelStateManager = audioModule.panelStateManager
    }
}
