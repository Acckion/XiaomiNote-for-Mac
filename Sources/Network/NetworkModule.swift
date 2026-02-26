import Foundation

/// 网络层模块工厂
///
/// 集中构建网络层的完整依赖图，确保所有 API 类共享同一个 APIClient 实例。
/// 在 AppDelegate 中创建，通过构造器注入传递给 AppCoordinator。
@MainActor
public struct NetworkModule: Sendable {
    public let requestManager: NetworkRequestManager
    public let apiClient: APIClient
    let networkMonitor: NetworkMonitor
    let networkErrorHandler: NetworkErrorHandler
    public let noteAPI: NoteAPI
    public let folderAPI: FolderAPI
    public let fileAPI: FileAPI
    public let syncAPI: SyncAPI
    public let userAPI: UserAPI
    let audioCacheService: AudioCacheService
    let audioConverterService: AudioConverterService

    init(audioCacheService: AudioCacheService, audioConverterService: AudioConverterService) {
        self.audioCacheService = audioCacheService
        self.audioConverterService = audioConverterService
        self.networkMonitor = NetworkMonitor()
        self.networkErrorHandler = NetworkErrorHandler()
        let manager = NetworkRequestManager(errorHandler: networkErrorHandler)
        self.requestManager = manager

        let client = APIClient(requestManager: manager)
        self.apiClient = client

        // 回调设置，解决 NetworkRequestManager <-> APIClient 循环依赖
        manager.setAPIClient(client)

        self.noteAPI = NoteAPI(client: client)
        self.folderAPI = FolderAPI(client: client)
        self.fileAPI = FileAPI(
            client: client,
            requestManager: manager,
            audioCacheService: audioCacheService,
            audioConverterService: audioConverterService
        )
        self.syncAPI = SyncAPI(client: client)
        self.userAPI = UserAPI(client: client)
    }

    /// 接线 PassTokenManager（解决循环依赖：PassTokenManager 需要 APIClient，APIClient/NetworkRequestManager 需要 PassTokenManager）
    func setPassTokenManager(_ manager: PassTokenManager) {
        requestManager.setPassTokenManager(manager)
        Task { await apiClient.setPassTokenManager(manager) }
    }

    /// Preview 和测试用的便利构造器
    public init() {
        self.init(
            audioCacheService: AudioCacheService(),
            audioConverterService: AudioConverterService()
        )
    }
}
