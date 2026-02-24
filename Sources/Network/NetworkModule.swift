import Foundation

/// 网络层模块工厂
///
/// 集中构建网络层的完整依赖图，确保所有 API 类共享同一个 APIClient 实例。
/// 在 AppDelegate 中创建，通过构造器注入传递给 AppCoordinator。
@MainActor
public struct NetworkModule: Sendable {
    let requestManager: NetworkRequestManager
    public let apiClient: APIClient
    public let noteAPI: NoteAPI
    public let folderAPI: FolderAPI
    public let fileAPI: FileAPI
    public let syncAPI: SyncAPI
    public let userAPI: UserAPI

    public init() {
        let manager = NetworkRequestManager()
        self.requestManager = manager

        let client = APIClient(requestManager: manager)
        self.apiClient = client

        self.noteAPI = NoteAPI(client: client)
        self.folderAPI = FolderAPI(client: client)
        self.fileAPI = FileAPI(client: client)
        self.syncAPI = SyncAPI(client: client)
        self.userAPI = UserAPI(client: client)
    }
}
