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
final class ServiceLocator {
    static let shared = ServiceLocator()
    private let container = DIContainer.shared

    private init() {}

    // MARK: - Configuration

    /// 配置所有服务
    ///
    /// 在应用启动时调用，注册所有需要的服务
    /// 随着重构的进行，这里会逐步添加更多服务的注册
    func configure() {
        // TODO: 在后续步骤中逐步添加服务注册
        // 例如：
        // container.register(NoteServiceProtocol.self, instance: MiNoteService.shared)
        // container.register(NoteStorageProtocol.self, instance: DatabaseService.shared)
        // container.register(SyncServiceProtocol.self, instance: SyncService.shared)
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

    // MARK: - Testing Support

    /// 重置所有服务（仅用于测试）
    func reset() {
        container.reset()
    }
}
