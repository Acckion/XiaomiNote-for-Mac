//
//  DIContainer.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  依赖注入容器 - 用于管理应用中的服务依赖
//

import Foundation

/// 依赖注入容器
///
/// 用于注册和解析应用中的服务依赖，支持单例和工厂模式。
///
/// ## 线程安全
/// 保留 `@unchecked Sendable` + NSLock 而非改为 Actor 的原因：
/// `resolve()` 是同步方法，被大量同步上下文调用，改为 Actor 需要所有调用方加 `await`，影响面过大。
/// NSLock 保护 `services` 和 `factories` 两个字典，所有读写操作均在 lock/unlock 范围内完成。
public final class DIContainer: @unchecked Sendable {
    /// 单例在进程生命周期内只初始化一次，private init() 保证外部无法创建新实例
    public nonisolated(unsafe) static let shared = DIContainer()

    private var services: [String: Any] = [:] // 受 lock 保护
    private var factories: [String: () -> Any] = [:] // 受 lock 保护
    private let lock = NSLock()

    private nonisolated init() {}

    // MARK: - Registration

    /// 注册单例服务
    /// - Parameters:
    ///   - type: 服务类型
    ///   - instance: 服务实例
    public func register<T>(_ type: T.Type, instance: T) {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }
        services[key] = instance
    }

    /// 注册工厂方法
    /// - Parameters:
    ///   - type: 服务类型
    ///   - factory: 创建服务实例的工厂方法
    public func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }
        factories[key] = factory
    }

    // MARK: - Resolution

    /// 解析服务
    /// - Parameter type: 服务类型
    /// - Returns: 服务实例
    public func resolve<T>(_ type: T.Type) -> T {
        let key = String(describing: type)

        lock.lock()
        defer { lock.unlock() }

        // 先查找已注册的实例
        if let service = services[key] as? T {
            return service
        }

        // 再查找工厂方法
        if let factory = factories[key] {
            return factory() as! T
        }

        fatalError("Service \(key) not registered in DIContainer")
    }

    /// 尝试解析服务（不会崩溃）
    /// - Parameter type: 服务类型
    /// - Returns: 服务实例，如果未注册则返回 nil
    public func tryResolve<T>(_ type: T.Type) -> T? {
        let key = String(describing: type)

        lock.lock()
        defer { lock.unlock() }

        // 先查找已注册的实例
        if let service = services[key] as? T {
            return service
        }

        // 再查找工厂方法
        if let factory = factories[key] {
            return factory() as? T
        }

        return nil
    }

    // MARK: - Utilities

    /// 检查服务是否已注册
    /// - Parameter type: 服务类型
    /// - Returns: 是否已注册
    public func isRegistered(_ type: (some Any).Type) -> Bool {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }
        return services[key] != nil || factories[key] != nil
    }

    /// 移除已注册的服务（主要用于测试）
    /// - Parameter type: 服务类型
    public func unregister(_ type: (some Any).Type) {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }
        services.removeValue(forKey: key)
        factories.removeValue(forKey: key)
    }

    /// 清空所有注册（主要用于测试）
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        services.removeAll()
        factories.removeAll()
    }
}
