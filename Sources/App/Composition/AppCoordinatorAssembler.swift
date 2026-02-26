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
        // 模块工厂
        let networkModule = NetworkModule()
        let syncModule = SyncModule(networkModule: networkModule)
        networkModule.requestManager.setOnlineStateManager(syncModule.onlineStateManager)
        let editorModule = EditorModule(syncModule: syncModule, networkModule: networkModule)
        let audioModule = AudioModule(syncModule: syncModule, networkModule: networkModule)

        let eventBus = EventBus.shared

        // 域装配
        let notes = NotesAssembler.assemble(eventBus: eventBus, networkModule: networkModule, syncModule: syncModule)
        let sync = SyncAssembler.assemble(eventBus: eventBus, networkModule: networkModule, syncModule: syncModule, noteStore: notes.noteStore)
        let auth = AuthAssembler.assemble(eventBus: eventBus, networkModule: networkModule, syncModule: syncModule, noteStore: notes.noteStore)
        let audio = AudioAssembler.assemble()

        // 跨域接线
        networkModule.setPassTokenManager(auth.passTokenManager)
        EditorAssembler.wireContext(noteEditorState: notes.noteEditorState, editorModule: editorModule, audioModule: audioModule)

        return AppCoordinator.Dependencies(
            eventBus: eventBus,
            noteStore: notes.noteStore,
            syncEngine: sync.syncEngine,
            noteListState: notes.noteListState,
            noteEditorState: notes.noteEditorState,
            folderState: notes.folderState,
            syncState: sync.syncState,
            authState: auth.authState,
            searchState: auth.searchState,
            networkModule: networkModule,
            syncModule: syncModule,
            editorModule: editorModule,
            audioModule: audioModule,
            startupSequenceManager: sync.startupSequenceManager,
            errorRecoveryService: sync.errorRecoveryService,
            networkRecoveryHandler: sync.networkRecoveryHandler,
            onlineStateManager: syncModule.onlineStateManager,
            notePreviewService: notes.notePreviewService,
            passTokenManager: auth.passTokenManager,
            memoryCacheManager: audio.memoryCacheManager,
            audioPanelViewModel: audio.audioPanelViewModel
        )
    }
}
