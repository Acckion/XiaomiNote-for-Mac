//
//  MockAuthenticationService.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  Mock 认证服务 - 用于测试
//

import Foundation
import Combine
@testable import MiNoteMac

/// Mock 认证服务
///
/// 用于测试的认证服务实现，可以模拟各种认证场景
class MockAuthenticationService: AuthenticationServiceProtocol {
    // MARK: - Mock 数据

    private let isAuthenticatedSubject = CurrentValueSubject<Bool, Never>(false)
    private let currentUserSubject = CurrentValueSubject<UserProfile?, Never>(nil)

    var mockAccessToken: String?
    var mockCookie: String?
    var mockError: Error?
    var mockUserProfile: UserProfile?

    // MARK: - 调用计数

    var loginCallCount = 0
    var loginWithCookieCallCount = 0
    var logoutCallCount = 0
    var getAccessTokenCallCount = 0
    var refreshAccessTokenCallCount = 0
    var validateTokenCallCount = 0
    var fetchUserProfileCallCount = 0
    var updateUserProfileCallCount = 0
    var getCurrentCookieCallCount = 0
    var saveCookieCallCount = 0
    var clearCookieCallCount = 0

    // MARK: - AuthenticationServiceProtocol - 认证状态

    var isAuthenticated: AnyPublisher<Bool, Never> {
        isAuthenticatedSubject.eraseToAnyPublisher()
    }

    var currentUser: AnyPublisher<UserProfile?, Never> {
        currentUserSubject.eraseToAnyPublisher()
    }

    // MARK: - AuthenticationServiceProtocol - 登录操作

    func login(username: String, password: String) async throws -> UserProfile {
        loginCallCount += 1

        if let error = mockError {
            throw error
        }

        let profile = mockUserProfile ?? UserProfile(
            id: "test-user-id",
            username: username,
            email: "\(username)@test.com"
        )

        isAuthenticatedSubject.send(true)
        currentUserSubject.send(profile)
        mockAccessToken = "mock-access-token"

        return profile
    }

    func loginWithCookie(_ cookie: String) async throws -> UserProfile {
        loginWithCookieCallCount += 1

        if let error = mockError {
            throw error
        }

        mockCookie = cookie

        let profile = mockUserProfile ?? UserProfile(
            id: "test-user-id",
            username: "testuser",
            email: "testuser@test.com"
        )

        isAuthenticatedSubject.send(true)
        currentUserSubject.send(profile)
        mockAccessToken = "mock-access-token"

        return profile
    }

    func logout() async throws {
        logoutCallCount += 1

        if let error = mockError {
            throw error
        }

        isAuthenticatedSubject.send(false)
        currentUserSubject.send(nil)
        mockAccessToken = nil
        mockCookie = nil
    }

    // MARK: - AuthenticationServiceProtocol - Token 管理

    func getAccessToken() -> String? {
        getAccessTokenCallCount += 1
        return mockAccessToken
    }

    func refreshAccessToken() async throws -> String {
        refreshAccessTokenCallCount += 1

        if let error = mockError {
            throw error
        }

        let newToken = "mock-refreshed-token-\(UUID().uuidString)"
        mockAccessToken = newToken
        return newToken
    }

    func validateToken() async throws -> Bool {
        validateTokenCallCount += 1

        if let error = mockError {
            throw error
        }

        return mockAccessToken != nil
    }

    // MARK: - AuthenticationServiceProtocol - 用户信息

    func fetchUserProfile() async throws -> UserProfile {
        fetchUserProfileCallCount += 1

        if let error = mockError {
            throw error
        }

        guard let profile = mockUserProfile ?? currentUserSubject.value else {
            throw NSError(domain: "MockError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        return profile
    }

    func updateUserProfile(_ profile: UserProfile) async throws {
        updateUserProfileCallCount += 1

        if let error = mockError {
            throw error
        }

        mockUserProfile = profile
        currentUserSubject.send(profile)
    }

    // MARK: - AuthenticationServiceProtocol - Cookie 管理

    func getCurrentCookie() -> String? {
        getCurrentCookieCallCount += 1
        return mockCookie
    }

    func saveCookie(_ cookie: String) throws {
        saveCookieCallCount += 1

        if let error = mockError {
            throw error
        }

        mockCookie = cookie
    }

    func clearCookie() throws {
        clearCookieCallCount += 1

        if let error = mockError {
            throw error
        }

        mockCookie = nil
    }

    // MARK: - Helper Methods

    /// 设置认证状态
    func setAuthenticated(_ authenticated: Bool, user: UserProfile? = nil) {
        isAuthenticatedSubject.send(authenticated)
        currentUserSubject.send(user)
    }

    /// 重置所有状态
    func reset() {
        isAuthenticatedSubject.send(false)
        currentUserSubject.send(nil)
        mockAccessToken = nil
        mockCookie = nil
        mockError = nil
        mockUserProfile = nil
        resetCallCounts()
    }

    /// 重置调用计数
    func resetCallCounts() {
        loginCallCount = 0
        loginWithCookieCallCount = 0
        logoutCallCount = 0
        getAccessTokenCallCount = 0
        refreshAccessTokenCallCount = 0
        validateTokenCallCount = 0
        fetchUserProfileCallCount = 0
        updateUserProfileCallCount = 0
        getCurrentCookieCallCount = 0
        saveCookieCallCount = 0
        clearCookieCallCount = 0
    }
}
