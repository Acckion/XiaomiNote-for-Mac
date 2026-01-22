//
//  AuthenticationViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  认证 ViewModel - 负责用户认证相关功能
//

import Foundation
import Combine

/// 认证 ViewModel
///
/// 负责管理用户认证相关的逻辑，包括：
/// - 登录和登出
/// - 认证状态管理
/// - Cookie 管理
/// - 用户信息管理
@MainActor
final class AuthenticationViewModel: LoadableViewModel {
    // MARK: - Dependencies

    private let authService: AuthenticationServiceProtocol

    // MARK: - Published Properties

    /// 是否已认证
    @Published var isAuthenticated: Bool = false

    /// 当前用户
    @Published var currentUser: UserProfile?

    /// 用户名（用于登录）
    @Published var username: String = ""

    /// 密码（用于登录）
    @Published var password: String = ""

    /// 是否显示登录视图
    @Published var showLoginView: Bool = false

    // MARK: - Initialization

    init(authService: AuthenticationServiceProtocol) {
        self.authService = authService
        super.init()
    }

    // MARK: - Setup

    override func setupBindings() {
        // 监听认证状态
        authService.isAuthenticated
            .assign(to: &$isAuthenticated)

        // 监听当前用户
        authService.currentUser
            .assign(to: &$currentUser)
    }

    // MARK: - Public Methods

    /// 使用用户名和密码登录
    func login() async {
        guard !username.isEmpty, !password.isEmpty else {
            error = NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Username and password are required"])
            return
        }

        await withLoadingSafe {
            let user = try await authService.login(username: username, password: password)
            self.currentUser = user
            self.showLoginView = false
            self.clearLoginForm()
        }
    }

    /// 使用 Cookie 登录
    /// - Parameter cookie: Cookie 字符串
    func loginWithCookie(_ cookie: String) async {
        await withLoadingSafe {
            let user = try await authService.loginWithCookie(cookie)
            self.currentUser = user
            self.showLoginView = false
        }
    }

    /// 登出
    func logout() async {
        await withLoadingSafe {
            try await authService.logout()
            self.currentUser = nil
            self.clearLoginForm()
        }
    }

    /// 刷新访问令牌
    func refreshAccessToken() async {
        await withLoadingSafe {
            _ = try await authService.refreshAccessToken()
        }
    }

    /// 验证令牌
    func validateToken() async -> Bool {
        do {
            return try await authService.validateToken()
        } catch {
            self.error = error
            return false
        }
    }

    /// 获取用户信息
    func fetchUserProfile() async {
        await withLoadingSafe {
            let profile = try await authService.fetchUserProfile()
            self.currentUser = profile
        }
    }

    /// 显示登录视图
    func showLogin() {
        showLoginView = true
    }

    /// 隐藏登录视图
    func hideLogin() {
        showLoginView = false
        clearLoginForm()
    }

    // MARK: - Private Methods

    /// 清除登录表单
    private func clearLoginForm() {
        username = ""
        password = ""
    }
}
