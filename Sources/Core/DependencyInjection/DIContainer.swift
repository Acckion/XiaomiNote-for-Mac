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
/// 用于注册和解析应用中的服务依赖，支持单例和工厂模式
/// 这是重构的第一步，用于逐步替代现有的单例模式
final class DIContainer: @unchecked Sendable {
    nonisolated(unsafe) static let shared = DIContainer()

    private var services: [String: Any] = [:]
    private var factories: [String: () -> Any] = [:]
    private let lock = NSLock()

    nonisolated private init() {}

    // MARK: - Registration

    /// 注册单例服务
    /// - Parameters:
    ///   - type: 服务类型
    ///   - instance: 服务实例
    func register<T>(_ type: T.Type, instance: T) {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }
        services[key] = instance
    }

    /// 注册工厂方法
    /// - Parameters:
    ///   - type: 服务类型
    ///   - factory: 创建服务实例的工厂方法
    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }
        factories[key] = factory
    }

    // MARK: - Resolution

    /// 解析服务
    /// - Parameter type: 服务类型
    /// - Returns: 服务实例
    func resolve<T>(_ type: T.Type) -> T {
        let key = String(describing: type)

        lock.lock()
        defer { lock.unlock() }

        // 先查找已注册的实例
        if let service = services[key] as? T {
            return service
        }

        // 再查找工厂方法
        if let factory = factories[key] {
            let instance = factory() as! T
            return instance
        }

        fatalError("Service \(key) not registered in DIContainer")
    }

    /// 尝试解析服务（不会崩溃）
    /// - Parameter type: 服务类型
    /// - Returns: 服务实例，如果未注册则返回 nil
    func tryResolve<T>(_ type: T.Type) -> T? {
        let key = String(describing: type)

        lock.lock()
        defer { lock.unlock() }

        // 先查找已注册的实例
        if let service = services[key] as? T {
            return service
        }

        // 再查找工厂方法
        if let factory = factories[key] {
            let instance = factory() as? T
            return instance
        }

        return nil
    }

    // MARK: - Utilities

    /// 检查服务是否已注册
    /// - Parameter type: 服务类型
    /// - Returns: 是否已注册
    func isRegistered<T>(_ type: T.Type) -> Bool {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }
        return services[key] != nil || factories[key] != nil
    }

    /// 移除已注册的服务（主要用于测试）
    /// - Parameter type: 服务类型
    func unregister<T>(_ type: T.Type) {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }
        services.removeValue(forKey: key)
        factories.removeValue(forKey: key)
    }

    /// 清空所有注册（主要用于测试）
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        services.removeAll()
        factories.removeAll()
    }
}
