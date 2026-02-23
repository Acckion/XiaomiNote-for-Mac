//
//  ServiceLocator.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  服务定位器 - 过渡期使用，用于配置和访问依赖注入容器
//

import Foundation

/// 服务定位器（过渡期使用，最终应该移除）
///
/// 在重构过渡期间提供集中的服务配置和访问入口。
/// 随着重构的进行，应逐步将依赖注入直接传递到需要的地方。
///
/// ## 线程安全
/// 与 DIContainer 保持一致的策略：保留 `@unchecked Sendable`，
/// 所有服务解析操作委托给 DIContainer（由其 NSLock 保护）。
public final class ServiceLocator: @unchecked Sendable {
    // 单例在进程生命周期内只初始化一次，private init() 保证外部无法创建新实例
    public nonisolated(unsafe) static let shared = ServiceLocator()
    private let container = DIContainer.shared

    private nonisolated init() {}

    // MARK: - Configuration

    /// 仅在 @MainActor configure() 中写入，启动时单次调用
    private var isConfigured = false

    /// 配置所有服务
    ///
    /// 在应用启动时调用，注册所有需要的服务
    @MainActor
    public func configure() {
        guard !isConfigured else {
            LogService.shared.warning(.core, "ServiceLocator 已经配置过，跳过重复配置")
            return
        }

        // 创建基础服务
        let networkClient = NetworkClient()
        let cacheService = DefaultCacheService()

        let noteStorage = DatabaseService.shared

        container.register(CacheServiceProtocol.self, instance: cacheService)
        container.register(NoteStorageProtocol.self, instance: noteStorage)

        let authService = DefaultAuthenticationService(networkClient: networkClient)
        let imageService = DefaultImageService(networkClient: networkClient, cacheService: cacheService)
        let audioService = DefaultAudioService(cacheService: cacheService)

        let networkMonitor = NetworkMonitor.shared

        container.register(AuthenticationServiceProtocol.self, instance: authService)
        container.register(ImageServiceProtocol.self, instance: imageService)
        container.register(AudioServiceProtocol.self, instance: audioService)
        container.register(NetworkMonitorProtocol.self, instance: networkMonitor)

        // 注册新 API 层服务
        container.register(APIClient.self, instance: APIClient.shared)
        container.register(NoteAPI.self, instance: NoteAPI.shared)
        container.register(FolderAPI.self, instance: FolderAPI.shared)
        container.register(FileAPI.self, instance: FileAPI.shared)
        container.register(SyncAPI.self, instance: SyncAPI.shared)
        container.register(UserAPI.self, instance: UserAPI.shared)

        isConfigured = true
        LogService.shared.info(.core, "ServiceLocator 配置完成")

        verifyConfiguration()
    }

    private func verifyConfiguration() {
        let services: [(String, Any.Type)] = [
            ("CacheServiceProtocol", CacheServiceProtocol.self),
            ("NoteStorageProtocol", NoteStorageProtocol.self),
            ("AuthenticationServiceProtocol", AuthenticationServiceProtocol.self),
            ("ImageServiceProtocol", ImageServiceProtocol.self),
            ("AudioServiceProtocol", AudioServiceProtocol.self),
            ("NetworkMonitorProtocol", NetworkMonitorProtocol.self),
            ("APIClient", APIClient.self),
            ("NoteAPI", NoteAPI.self),
            ("FolderAPI", FolderAPI.self),
            ("FileAPI", FileAPI.self),
            ("SyncAPI", SyncAPI.self),
            ("UserAPI", UserAPI.self),
        ]

        let allRegistered = services.allSatisfy { _, type in container.isRegistered(type) }
        if !allRegistered {
            LogService.shared.warning(.core, "部分服务未注册，请检查配置")
        }
    }

    // MARK: - Service Access (Convenience Methods)

    /// 解析服务
    /// - Parameter type: 服务类型
    /// - Returns: 服务实例
    func resolve<T>(_ type: T.Type) -> T {
        container.resolve(type)
    }

    /// 尝试解析服务
    /// - Parameter type: 服务类型
    /// - Returns: 服务实例，如果未注册则返回 nil
    func tryResolve<T>(_ type: T.Type) -> T? {
        container.tryResolve(type)
    }

    /// 检查服务是否已注册
    /// - Parameter type: 服务类型
    /// - Returns: 是否已注册
    func isRegistered(_ type: (some Any).Type) -> Bool {
        container.isRegistered(type)
    }

    // MARK: - Convenience Accessors

    /// 网络监控服务
    var networkMonitor: NetworkMonitorProtocol {
        resolve(NetworkMonitorProtocol.self)
    }

    /// 认证服务
    var authService: AuthenticationServiceProtocol {
        resolve(AuthenticationServiceProtocol.self)
    }

    /// 笔记存储
    var noteStorage: NoteStorageProtocol {
        resolve(NoteStorageProtocol.self)
    }

    /// 缓存服务
    var cacheService: CacheServiceProtocol {
        resolve(CacheServiceProtocol.self)
    }

    /// 图片服务
    var imageService: ImageServiceProtocol {
        resolve(ImageServiceProtocol.self)
    }

    /// 音频服务
    var audioService: AudioServiceProtocol {
        resolve(AudioServiceProtocol.self)
    }

    /// API 客户端
    var apiClient: APIClient {
        resolve(APIClient.self)
    }

    /// 笔记 API
    var noteAPI: NoteAPI {
        resolve(NoteAPI.self)
    }

    /// 文件夹 API
    var folderAPI: FolderAPI {
        resolve(FolderAPI.self)
    }

    /// 文件 API
    var fileAPI: FileAPI {
        resolve(FileAPI.self)
    }

    /// 同步 API
    var syncAPI: SyncAPI {
        resolve(SyncAPI.self)
    }

    /// 用户 API
    var userAPI: UserAPI {
        resolve(UserAPI.self)
    }

    // MARK: - Testing Support

    /// 重置所有服务（仅用于测试）
    func reset() {
        container.reset()
        isConfigured = false
    }
}
