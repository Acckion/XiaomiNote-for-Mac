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
    nonisolated(unsafe) public static let shared = ServiceLocator()
    private let container = DIContainer.shared

    nonisolated private init() {}

    // MARK: - Configuration

    private var isConfigured = false

    /// 配置所有服务
    ///
    /// 在应用启动时调用，注册所有需要的服务
    @MainActor
    public func configure() {
        guard !isConfigured else {
            print("⚠️ ServiceLocator 已经配置过，跳过重复配置")
            return
        }

        print("🚀 开始配置 ServiceLocator...")

        // 创建基础服务
        print("  📦 创建基础服务...")
        let networkClient = NetworkClient()
        let cacheService = DefaultCacheService()
        
        // 使用现有的 DatabaseService.shared（过渡期）
        let noteStorage = DatabaseService.shared

        // 注册基础服务
        print("  ✅ 注册 CacheServiceProtocol")
        container.register(CacheServiceProtocol.self, instance: cacheService)
        
        print("  ✅ 注册 NoteStorageProtocol")
        container.register(NoteStorageProtocol.self, instance: noteStorage)

        // 创建并注册网络相关服务
        print("  📦 创建网络相关服务...")
        
        // 使用现有的 MiNoteService.shared（过渡期）
        let noteService = MiNoteService.shared
        
        // 使用现有的 SyncService.shared（过渡期）
        let syncService = SyncService.shared
        
        let authService = DefaultAuthenticationService(networkClient: networkClient)
        let imageService = DefaultImageService(networkClient: networkClient, cacheService: cacheService)
        let audioService = DefaultAudioService(cacheService: cacheService)
        
        // 使用现有的 NetworkMonitor.shared（过渡期）
        let networkMonitor = NetworkMonitor.shared

        print("  ✅ 注册 NoteServiceProtocol (使用现有单例)")
        container.register(NoteServiceProtocol.self, instance: noteService)
        
        print("  ✅ 注册 SyncServiceProtocol (使用现有单例)")
        container.register(SyncServiceProtocol.self, instance: syncService)
        
        print("  ✅ 注册 AuthenticationServiceProtocol")
        container.register(AuthenticationServiceProtocol.self, instance: authService)
        
        print("  ✅ 注册 ImageServiceProtocol")
        container.register(ImageServiceProtocol.self, instance: imageService)
        
        print("  ✅ 注册 AudioServiceProtocol")
        container.register(AudioServiceProtocol.self, instance: audioService)
        
        print("  ✅ 注册 NetworkMonitorProtocol (使用现有单例)")
        container.register(NetworkMonitorProtocol.self, instance: networkMonitor)

        // 网络监控已经在 NetworkMonitor.shared 初始化时启动
        print("  🌐 网络监控已启动（使用现有单例）")

        isConfigured = true
        print("✅ ServiceLocator 配置完成！")
        
        // 验证所有服务已注册
        verifyConfiguration()
    }

    /// 验证所有服务是否已正确注册
    private func verifyConfiguration() {
        print("🔍 验证服务注册...")
        
        let services: [(String, Any.Type)] = [
            ("CacheServiceProtocol", CacheServiceProtocol.self),
            ("NoteStorageProtocol", NoteStorageProtocol.self),
            ("NoteServiceProtocol", NoteServiceProtocol.self),
            ("SyncServiceProtocol", SyncServiceProtocol.self),
            ("AuthenticationServiceProtocol", AuthenticationServiceProtocol.self),
            ("ImageServiceProtocol", ImageServiceProtocol.self),
            ("AudioServiceProtocol", AudioServiceProtocol.self),
            ("NetworkMonitorProtocol", NetworkMonitorProtocol.self)
        ]
        
        var allRegistered = true
        for (name, type) in services {
            if container.isRegistered(type) {
                print("  ✅ \(name) 已注册")
            } else {
                print("  ❌ \(name) 未注册")
                allRegistered = false
            }
        }
        
        if allRegistered {
            print("✅ 所有服务验证通过！")
        } else {
            print("⚠️ 部分服务未注册，请检查配置")
        }
    }

    // MARK: - Service Access (Convenience Methods)

    /// 解析服务
    /// - Parameter type: 服务类型
    /// - Returns: 服务实例
    func resolve<T>(_ type: T.Type) -> T {
        return container.resolve(type)
    }

    /// 尝试解析服务
    /// - Parameter type: 服务类型
    /// - Returns: 服务实例，如果未注册则返回 nil
    func tryResolve<T>(_ type: T.Type) -> T? {
        return container.tryResolve(type)
    }

    /// 检查服务是否已注册
    /// - Parameter type: 服务类型
    /// - Returns: 是否已注册
    func isRegistered<T>(_ type: T.Type) -> Bool {
        return container.isRegistered(type)
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
    
    /// 同步服务
    var syncService: SyncServiceProtocol {
        resolve(SyncServiceProtocol.self)
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
        print("🔄 ServiceLocator 已重置")
    }
}
