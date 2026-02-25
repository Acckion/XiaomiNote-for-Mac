//
//  AuthUser.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  认证用户模型 - 用于认证服务层
//

import Foundation

/// 认证用户模型
///
/// 用于认证服务层的用户信息，包含认证相关的字段
/// 与 UserProfile 分离，避免混淆业务层和认证层的概念
public struct AuthUser: Codable, Identifiable, Sendable {
    /// 用户 ID
    public let id: String

    /// 用户名
    public let username: String

    /// 邮箱（可选）
    public let email: String?

    /// 访问令牌
    public let token: String

    /// 创建时间
    public let createdAt: Date

    /// 最后更新时间
    public let updatedAt: Date

    public init(
        id: String,
        username: String,
        email: String? = nil,
        token: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.token = token
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 转换为 UserProfile（用于业务层）
    public func toUserProfile() -> UserProfile {
        UserProfile(
            nickname: username,
            icon: "" // 默认空图标，实际使用时需要从其他地方获取
        )
    }
}
