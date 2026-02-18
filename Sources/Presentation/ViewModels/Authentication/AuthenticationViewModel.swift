//
//  AuthenticationViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  认证视图模型 - 管理用户认证状态
//

import Combine
import Foundation
import SwiftUI

/// 认证视图模型
///
/// 负责管理用户认证状态，包括：
/// - 登录和登出
/// - Cookie 刷新
/// - 用户信息管理
/// - 私密笔记密码管理
///
/// **设计原则**:
/// - 单一职责：只负责认证相关的功能
/// - 依赖注入：通过构造函数注入依赖，而不是使用单例
/// - 可测试性：所有依赖都可以被 Mock，便于单元测试
///
/// **线程安全**：使用 @MainActor 确保所有 UI 更新在主线程执行
@MainActor
public final class AuthenticationViewModel: ObservableObject {
    // MARK: - Published Properties

    /// 是否已登录
    @Published public var isLoggedIn = false

    /// 用户信息
    @Published public var userProfile: UserProfile?

    /// 是否显示登录视图
    @Published public var showLoginView = false

    /// Cookie 是否过期
    @Published public var isCookieExpired = false

    /// 私密笔记是否已解锁
    @Published public var isPrivateNotesUnlocked = false

    /// 是否正在加载
    @Published public var isLoading = false

    /// 错误消息
    @Published public var errorMessage: String?

    // MARK: - Dependencies

    /// 认证服务
    private let authService: AuthenticationServiceProtocol

    /// 笔记存储服务（用于私密笔记密码管理）
    private let noteStorage: NoteStorageProtocol

    // MARK: - Private Properties

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 私密笔记密码（内存中临时存储）
    private var privateNotesPassword: String?

    // MARK: - Initialization

    /// 初始化认证视图模型
    ///
    /// - Parameters:
    ///   - authService: 认证服务
    ///   - noteStorage: 笔记存储服务
    public init(
        authService: AuthenticationServiceProtocol,
        noteStorage: NoteStorageProtocol
    ) {
        self.authService = authService
        self.noteStorage = noteStorage

        setupObservers()
        checkAuthenticationStatus()

        print("[AuthenticationViewModel] 初始化完成")
    }

    // MARK: - Public Methods

    /// 登录
    ///
    /// - Parameters:
    ///   - username: 用户名
    ///   - password: 密码
    public func login(username: String, password: String) async {
        guard !isLoading else {
            print("[AuthenticationViewModel] 正在登录中")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            print("[AuthenticationViewModel] 开始登录: \(username)")

            let profile = try await authService.login(username: username, password: password)

            userProfile = profile
            isLoggedIn = true
            showLoginView = false

            print("[AuthenticationViewModel] 登录成功: \(profile.nickname)")
        } catch {
            errorMessage = "登录失败: \(error.localizedDescription)"
            print("[AuthenticationViewModel] 登录失败: \(error)")
        }

        isLoading = false
    }

    /// 使用 Cookie 登录
    ///
    /// - Parameter cookie: Cookie 字符串
    public func loginWithCookie(_ cookie: String) async {
        guard !isLoading else {
            print("[AuthenticationViewModel] 正在登录中")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            print("[AuthenticationViewModel] 使用 Cookie 登录")

            let profile = try await authService.loginWithCookie(cookie)

            userProfile = profile
            isLoggedIn = true
            showLoginView = false

            print("[AuthenticationViewModel] Cookie 登录成功: \(profile.nickname)")
        } catch {
            errorMessage = "Cookie 登录失败: \(error.localizedDescription)"
            print("[AuthenticationViewModel] Cookie 登录失败: \(error)")
        }

        isLoading = false
    }

    /// 登出
    public func logout() async {
        guard !isLoading else {
            print("[AuthenticationViewModel] 正在处理中")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            print("[AuthenticationViewModel] 开始登出")

            try await authService.logout()

            userProfile = nil
            isLoggedIn = false
            isPrivateNotesUnlocked = false
            privateNotesPassword = nil

            print("[AuthenticationViewModel] 登出成功")
        } catch {
            errorMessage = "登出失败: \(error.localizedDescription)"
            print("[AuthenticationViewModel] 登出失败: \(error)")
        }

        isLoading = false
    }

    /// 刷新 Cookie
    public func refreshCookie() async {
        guard !isLoading else {
            print("[AuthenticationViewModel] 正在处理中")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            print("[AuthenticationViewModel] 开始刷新 Cookie")

            _ = try await authService.refreshAccessToken()

            isCookieExpired = false

            print("[AuthenticationViewModel] Cookie 刷新成功")
        } catch {
            errorMessage = "Cookie 刷新失败: \(error.localizedDescription)"
            isCookieExpired = true
            print("[AuthenticationViewModel] Cookie 刷新失败: \(error)")
        }

        isLoading = false
    }

    /// 解锁私密笔记
    ///
    /// - Parameter password: 私密笔记密码
    public func unlockPrivateNotes(password: String) async {
        guard !isLoading else {
            print("[AuthenticationViewModel] 正在处理中")
            return
        }

        isLoading = true
        errorMessage = nil

        print("[AuthenticationViewModel] 验证私密笔记密码")

        // 这里应该调用服务验证密码
        // 简化实现：直接存储密码
        privateNotesPassword = password
        isPrivateNotesUnlocked = true

        print("[AuthenticationViewModel] 私密笔记已解锁")

        isLoading = false
    }

    /// 锁定私密笔记
    public func lockPrivateNotes() {
        privateNotesPassword = nil
        isPrivateNotesUnlocked = false
        print("[AuthenticationViewModel] 私密笔记已锁定")
    }

    /// 获取用户信息
    public func fetchUserProfile() async {
        guard !isLoading else {
            print("[AuthenticationViewModel] 正在处理中")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            print("[AuthenticationViewModel] 获取用户信息")

            let profile = try await authService.fetchUserProfile()

            userProfile = profile

            print("[AuthenticationViewModel] 用户信息获取成功: \(profile.nickname)")
        } catch {
            errorMessage = "获取用户信息失败: \(error.localizedDescription)"
            print("[AuthenticationViewModel] 获取用户信息失败: \(error)")
        }

        isLoading = false
    }

    // MARK: - Private Methods

    /// 设置观察者
    private func setupObservers() {
        // 监听认证状态变化
        authService.isAuthenticated
            .sink { [weak self] isAuthenticated in
                guard let self else { return }
                isLoggedIn = isAuthenticated

                if !isAuthenticated {
                    userProfile = nil
                    isPrivateNotesUnlocked = false
                    privateNotesPassword = nil
                }
            }
            .store(in: &cancellables)

        // 监听用户信息变化
        authService.currentUser
            .sink { [weak self] user in
                guard let self else { return }
                userProfile = user
            }
            .store(in: &cancellables)
    }

    /// 检查认证状态
    private func checkAuthenticationStatus() {
        Task {
            do {
                let isValid = try await authService.validateToken()

                if isValid {
                    isLoggedIn = true
                    await fetchUserProfile()
                } else {
                    isLoggedIn = false
                    // 只有在未登录时才显示登录视图
                    if !isLoggedIn {
                        showLoginView = true
                    }
                }
            } catch {
                print("[AuthenticationViewModel] 检查认证状态失败: \(error)")
                isLoggedIn = false
                // 只有在未登录时才显示登录视图
                if !isLoggedIn {
                    showLoginView = true
                }
            }
        }
    }

    // MARK: - Auto Refresh Cookie

    /// 自动刷新 Cookie 定时器
    private var autoRefreshCookieTimer: Timer?

    /// 启动自动刷新 Cookie 定时器
    public func startAutoRefreshCookieIfNeeded() {
        // 检查是否已登录
        guard isLoggedIn else {
            print("[AuthenticationViewModel] 未登录，不启动自动刷新 Cookie 定时器")
            return
        }

        // 检查是否已有定时器在运行
        if autoRefreshCookieTimer != nil {
            print("[AuthenticationViewModel] 自动刷新 Cookie 定时器已在运行")
            return
        }

        // 从 UserDefaults 获取刷新间隔
        let defaults = UserDefaults.standard
        let autoRefreshCookie = defaults.bool(forKey: "autoRefreshCookie")
        let autoRefreshInterval = defaults.double(forKey: "autoRefreshInterval")

        guard autoRefreshCookie, autoRefreshInterval > 0 else {
            print("[AuthenticationViewModel] 自动刷新 Cookie 未启用或间隔为 0")
            return
        }

        print("[AuthenticationViewModel] 启动自动刷新 Cookie 定时器，间隔: \(autoRefreshInterval) 秒")

        // 创建定时器
        autoRefreshCookieTimer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                print("[AuthenticationViewModel] 自动刷新 Cookie 定时器触发")
                await self.refreshCookie()
            }
        }
    }

    /// 停止自动刷新 Cookie 定时器
    public func stopAutoRefreshCookie() {
        print("[AuthenticationViewModel] 停止自动刷新 Cookie 定时器")
        autoRefreshCookieTimer?.invalidate()
        autoRefreshCookieTimer = nil
    }
}
