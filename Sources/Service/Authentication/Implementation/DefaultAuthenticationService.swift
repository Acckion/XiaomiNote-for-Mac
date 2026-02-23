import Combine
import Foundation

/// 默认认证服务实现
///
/// 注意：这是重构过渡期的实现，暂时不完全可用
/// 需要等待 NetworkClient 完整实现后才能正常工作
actor DefaultAuthenticationService: AuthenticationServiceProtocol {
    // MARK: - Properties

    private let networkClient: NetworkClient
    private nonisolated(unsafe) let userStateSubject = CurrentValueSubject<UserProfile?, Never>(nil)
    private nonisolated(unsafe) let isAuthenticatedSubject = CurrentValueSubject<Bool, Never>(false)
    private var currentAuthUser: AuthUser?
    private var currentCookie: String?

    /// Cookie 存储的 UserDefaults 键名
    private static let cookieKey = "minote_cookie"

    nonisolated var currentUser: AnyPublisher<UserProfile?, Never> {
        userStateSubject.eraseToAnyPublisher()
    }

    nonisolated var isAuthenticated: AnyPublisher<Bool, Never> {
        isAuthenticatedSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(networkClient: NetworkClient) {
        self.networkClient = networkClient

        // 从持久化存储恢复 Cookie，避免重启后误弹登录窗口
        if let savedCookie = UserDefaults.standard.string(forKey: Self.cookieKey),
           !savedCookie.isEmpty
        {
            self.currentCookie = savedCookie
            isAuthenticatedSubject.send(true)
        }
    }

    // MARK: - Public Methods

    func login(username: String, password: String) async throws -> UserProfile {
        let parameters: [String: Any] = [
            "username": username,
            "password": password,
        ]

        let response: LoginResponse = try await networkClient.request(
            "/auth/login",
            method: .post,
            parameters: parameters,
            headers: nil
        )

        let authUser = AuthUser(
            id: response.userId,
            username: username,
            email: response.email,
            token: response.token
        )

        currentAuthUser = authUser
        let userProfile = authUser.toUserProfile()
        userStateSubject.send(userProfile)
        isAuthenticatedSubject.send(true)

        return userProfile
    }

    func loginWithCookie(_ cookie: String) async throws -> UserProfile {
        let headers = ["Cookie": cookie]

        let response: LoginResponse = try await networkClient.request(
            "/auth/cookie-login",
            method: .post,
            parameters: nil,
            headers: headers
        )

        let authUser = AuthUser(
            id: response.userId,
            username: response.username ?? "User",
            email: response.email,
            token: response.token
        )

        currentAuthUser = authUser
        currentCookie = cookie
        UserDefaults.standard.set(cookie, forKey: Self.cookieKey)
        let userProfile = authUser.toUserProfile()
        userStateSubject.send(userProfile)
        isAuthenticatedSubject.send(true)

        return userProfile
    }

    func logout() async throws {
        if let token = currentAuthUser?.token {
            let headers = ["Authorization": "Bearer \(token)"]
            let _: EmptyResponse = try await networkClient.request(
                "/auth/logout",
                method: .post,
                parameters: nil,
                headers: headers
            )
        }

        currentAuthUser = nil
        currentCookie = nil
        UserDefaults.standard.removeObject(forKey: Self.cookieKey)
        userStateSubject.send(nil)
        isAuthenticatedSubject.send(false)
    }

    func getAccessToken() async -> String? {
        currentAuthUser?.token
    }

    func refreshAccessToken() async throws -> String {
        guard let user = currentAuthUser else {
            throw AuthError.notAuthenticated
        }

        let headers = ["Authorization": "Bearer \(user.token)"]

        let response: TokenResponse = try await networkClient.request(
            "/auth/refresh",
            method: .post,
            parameters: nil,
            headers: headers
        )

        let updatedUser = AuthUser(
            id: user.id,
            username: user.username,
            email: user.email,
            token: response.token
        )

        currentAuthUser = updatedUser
        userStateSubject.send(updatedUser.toUserProfile())

        return response.token
    }

    func validateToken() async throws -> Bool {
        // 优先检查持久化的 Cookie，避免重启后内存状态丢失导致误判
        guard let cookie = currentCookie, !cookie.isEmpty else {
            return false
        }
        return true
    }

    func fetchUserProfile() async throws -> UserProfile {
        guard let user = currentAuthUser else {
            throw AuthError.notAuthenticated
        }

        let headers = ["Authorization": "Bearer \(user.token)"]

        let response: UserProfileResponse = try await networkClient.request(
            "/user/profile",
            method: .get,
            parameters: nil,
            headers: headers
        )

        let updatedUser = AuthUser(
            id: response.userId,
            username: response.username,
            email: response.email,
            token: user.token
        )

        currentAuthUser = updatedUser
        let userProfile = updatedUser.toUserProfile()
        userStateSubject.send(userProfile)

        return userProfile
    }

    func updateUserProfile(_ profile: UserProfile) async throws {
        guard let user = currentAuthUser else {
            throw AuthError.notAuthenticated
        }

        let headers = ["Authorization": "Bearer \(user.token)"]
        let parameters: [String: Any] = [
            "username": profile.nickname,
            "email": "", // UserProfile 没有 email 字段
        ]

        let _: EmptyResponse = try await networkClient.request(
            "/user/profile",
            method: .put,
            parameters: parameters,
            headers: headers
        )

        // 注意：这里无法完全更新 AuthUser，因为 UserProfile 缺少必要字段
        // 这是模型不兼容的一个例子
        userStateSubject.send(profile)
    }

    func getCurrentCookie() async -> String? {
        currentCookie
    }

    func saveCookie(_ cookie: String) async throws {
        currentCookie = cookie
    }

    func clearCookie() async throws {
        currentCookie = nil
    }

    func getCurrentUser() async throws -> UserProfile? {
        currentAuthUser?.toUserProfile()
    }
}

// MARK: - Supporting Types

private struct LoginResponse: Decodable {
    let userId: String
    let username: String?
    let email: String?
    let token: String
}

private struct TokenResponse: Decodable {
    let token: String
}

private struct UserProfileResponse: Decodable {
    let userId: String
    let username: String
    let email: String?
}

private struct EmptyResponse: Decodable {}

enum AuthError: Error {
    case notAuthenticated
}
