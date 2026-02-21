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
/// 这个类用于在重构过渡期间提供一个集中的地方来配置所有服务
/// 随着重构的进行，应该逐步将依赖注入直接传递到需要的地方
/// 最终目标是完全移除这个类，使用纯粹的依赖注入
public final class ServiceLocator: @unchecked Sendable {
    public nonisolated(unsafe) static let shared = ServiceLocator()
    private let container = DIContainer.shared

    private nonisolated init() {}

    // MARK: - Configuration

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

        let noteService = MiNoteService.shared

        let authService = DefaultAuthenticationService(networkClient: networkClient)
        let imageService = DefaultImageService(networkClient: networkClient, cacheService: cacheService)
        let audioService = DefaultAudioService(cacheService: cacheService)

        let networkMonitor = NetworkMonitor.shared

        container.register(NoteServiceProtocol.self, instance: noteService)
        container.register(AuthenticationServiceProtocol.self, instance: authService)
        container.register(ImageServiceProtocol.self, instance: imageService)
        container.register(AudioServiceProtocol.self, instance: audioService)
        container.register(NetworkMonitorProtocol.self, instance: networkMonitor)

        isConfigured = true
        LogService.shared.info(.core, "ServiceLocator 配置完成")

        verifyConfiguration()
    }

    private func verifyConfiguration() {
        let services: [(String, Any.Type)] = [
            ("CacheServiceProtocol", CacheServiceProtocol.self),
            ("NoteStorageProtocol", NoteStorageProtocol.self),
            ("NoteServiceProtocol", NoteServiceProtocol.self),
            ("AuthenticationServiceProtocol", AuthenticationServiceProtocol.self),
            ("ImageServiceProtocol", ImageServiceProtocol.self),
            ("AudioServiceProtocol", AudioServiceProtocol.self),
            ("NetworkMonitorProtocol", NetworkMonitorProtocol.self),
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

    /// 笔记服务
    var noteService: NoteServiceProtocol {
        resolve(NoteServiceProtocol.self)
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

    // MARK: - Testing Support

    /// 重置所有服务（仅用于测试）
    func reset() {
        container.reset()
        isConfigured = false
    }
}
