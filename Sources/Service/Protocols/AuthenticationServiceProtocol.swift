//
//  AuthenticationServiceProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  认证服务协议 - 定义用户认证操作接口
//

import Foundation
import Combine

/// 认证服务协议
///
/// 定义了用户认证相关的操作接口，包括：
/// - 登录和登出
/// - Token 管理
/// - 用户信息管理
@preconcurrency
public protocol AuthenticationServiceProtocol: Sendable {
    // MARK: - 认证状态

    /// 是否已登录
    var isAuthenticated: AnyPublisher<Bool, Never> { get }

    /// 当前用户
    var currentUser: AnyPublisher<UserProfile?, Never> { get }

    // MARK: - 登录操作

    /// 使用用户名和密码登录
    /// - Parameters:
    ///   - username: 用户名
    ///   - password: 密码
    /// - Returns: 用户信息
    func login(username: String, password: String) async throws -> UserProfile

    /// 使用 Cookie 登录
    /// - Parameter cookie: Cookie 字符串
    /// - Returns: 用户信息
    func loginWithCookie(_ cookie: String) async throws -> UserProfile

    /// 登出
    func logout() async throws

    // MARK: - Token 管理

    /// 获取当前访问令牌
    /// - Returns: 访问令牌，如果未登录返回 nil
    func getAccessToken() -> String?

    /// 刷新访问令牌
    /// - Returns: 新的访问令牌
    func refreshAccessToken() async throws -> String

    /// 验证令牌是否有效
    /// - Returns: 令牌是否有效
    func validateToken() async throws -> Bool

    // MARK: - 用户信息

    /// 获取用户信息
    /// - Returns: 用户信息
    func fetchUserProfile() async throws -> UserProfile

    /// 更新用户信息
    /// - Parameter profile: 用户信息
    func updateUserProfile(_ profile: UserProfile) async throws

    // MARK: - Cookie 管理

    /// 获取当前 Cookie
    /// - Returns: Cookie 字符串，如果未登录返回 nil
    func getCurrentCookie() -> String?

    /// 保存 Cookie
    /// - Parameter cookie: Cookie 字符串
    func saveCookie(_ cookie: String) throws

    /// 清除 Cookie
    func clearCookie() throws
}
