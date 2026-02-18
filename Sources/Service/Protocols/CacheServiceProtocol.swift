//
//  CacheServiceProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  缓存服务协议 - 定义通用缓存操作接口
//

import Foundation

/// 缓存服务协议
///
/// 定义了通用缓存相关的操作接口，包括：
/// - 缓存读写
/// - 缓存管理
/// - 缓存策略
protocol CacheServiceProtocol {
    // MARK: - 基本操作（异步版本）

    /// 获取缓存对象
    /// - Parameter key: 缓存键
    /// - Returns: 缓存对象，如果不存在返回 nil
    func get<T: Codable>(key: String) async throws -> T?

    /// 设置缓存对象
    /// - Parameters:
    ///   - key: 缓存键
    ///   - value: 缓存对象
    ///   - policy: 缓存策略
    func set(key: String, value: some Codable, policy: CachePolicy) async throws

    /// 删除缓存对象
    /// - Parameter key: 缓存键
    func remove(key: String) async throws

    /// 检查缓存是否存在
    /// - Parameter key: 缓存键
    /// - Returns: 是否存在
    func exists(key: String) async -> Bool

    // MARK: - 批量操作

    /// 批量获取缓存对象
    /// - Parameter keys: 缓存键数组
    /// - Returns: 缓存对象字典
    func getMultiple<T: Codable>(keys: [String]) async throws -> [String: T]

    /// 批量设置缓存对象
    /// - Parameters:
    ///   - values: 缓存对象字典
    ///   - policy: 缓存策略
    func setMultiple(values: [String: some Codable], policy: CachePolicy) async throws

    /// 批量删除缓存对象
    /// - Parameter keys: 缓存键数组
    func removeMultiple(keys: [String]) async throws

    // MARK: - 缓存管理

    /// 清空所有缓存
    func clear() async throws

    /// 清空过期缓存
    func clearExpired() async throws

    /// 获取缓存大小（字节）
    /// - Returns: 缓存大小
    func getCacheSize() async -> Int64

    /// 获取缓存对象数量
    /// - Returns: 缓存对象数量
    func getCacheCount() async -> Int

    // MARK: - 缓存策略

    /// 设置最大缓存大小（字节）
    /// - Parameter size: 最大缓存大小
    func setMaxCacheSize(_ size: Int64) async

    /// 设置最大缓存对象数量
    /// - Parameter count: 最大缓存对象数量
    func setMaxCacheCount(_ count: Int) async

    /// 设置默认过期时间
    /// - Parameter expiration: 默认过期时间
    func setDefaultExpiration(_ expiration: TimeInterval) async
}

// MARK: - Supporting Types

/// 缓存策略
enum CachePolicy {
    /// 默认策略（使用默认过期时间）
    case `default`

    /// 永不过期
    case never

    /// 自定义过期时间
    case expiration(TimeInterval)

    /// 仅使用缓存
    case cacheOnly

    /// 仅使用网络
    case networkOnly

    /// 优先使用缓存，缓存不存在时使用网络
    case cacheFirst

    /// 优先使用网络，网络失败时使用缓存
    case networkFirst

    /// 同时使用缓存和网络，先返回缓存，网络请求完成后更新
    case cacheAndNetwork
}
