import Foundation

/// 同步层模块工厂
///
/// 集中构建同步层的完整依赖图，接收 NetworkModule 作为输入。
/// SyncEngine 需要 NoteStore（不属于同步层），通过工厂方法延迟创建。
@MainActor
public struct SyncModule: Sendable {
    public let localStorage: LocalStorageService
    public let operationQueue: UnifiedOperationQueue
    public let idMappingRegistry: IdMappingRegistry
    let syncStateManager: SyncStateManager
    public let operationProcessor: OperationProcessor
    public let onlineStateManager: OnlineStateManager

    private let networkModule: NetworkModule
    private let eventBus: EventBus

    public init(networkModule: NetworkModule) {
        self.networkModule = networkModule
        self.eventBus = EventBus.shared

        let audioCacheService = networkModule.audioCacheService

        let db = DatabaseService.shared

        let storage = LocalStorageService(database: db, audioCacheService: audioCacheService)
        self.localStorage = storage

        let queue = UnifiedOperationQueue(databaseService: db)
        self.operationQueue = queue

        let registry = IdMappingRegistry(
            databaseService: db,
            operationQueue: queue,
            eventBus: EventBus.shared
        )
        self.idMappingRegistry = registry

        let stateManager = SyncStateManager(
            localStorage: storage,
            operationQueue: queue
        )
        self.syncStateManager = stateManager

        let processor = OperationProcessor(
            operationQueue: queue,
            apiClient: networkModule.apiClient,
            noteAPI: networkModule.noteAPI,
            folderAPI: networkModule.folderAPI,
            fileAPI: networkModule.fileAPI,
            localStorage: storage,
            databaseService: db,
            syncStateManager: stateManager,
            eventBus: EventBus.shared,
            idMappingRegistry: registry
        )
        self.operationProcessor = processor

        self.onlineStateManager = OnlineStateManager(
            networkMonitor: NetworkMonitor.shared,
            apiClient: networkModule.apiClient,
            eventBus: EventBus.shared
        )
    }

    /// 创建 SyncEngine（需要外部传入 NoteStore）
    public func createSyncEngine(noteStore: NoteStore) -> SyncEngine {
        let guard_ = SyncGuard(
            operationQueue: operationQueue,
            noteStore: noteStore
        )
        return SyncEngine(
            apiClient: networkModule.apiClient,
            noteAPI: networkModule.noteAPI,
            folderAPI: networkModule.folderAPI,
            syncAPI: networkModule.syncAPI,
            fileAPI: networkModule.fileAPI,
            eventBus: eventBus,
            operationQueue: operationQueue,
            localStorage: localStorage,
            syncStateManager: syncStateManager,
            syncGuard: guard_,
            noteStore: noteStore,
            operationProcessor: operationProcessor,
            audioCacheService: networkModule.audioCacheService
        )
    }

    /// Preview 和测试用的便利构造器
    public init() {
        self.init(networkModule: NetworkModule())
    }
}
