import Combine
import Foundation

/// 默认认证服务实现
///
/// 注意：这是重构过渡期的实现，暂时不完全可用
/// 需要等待 NetworkClient 完整实现后才能正常工作
final class DefaultAuthenticationService: AuthenticationServiceProtocol, @unchecked Sendable {
    // MARK: - Properties

    private let networkClient: NetworkClient
    private let userStateSubject = CurrentValueSubject<UserProfile?, Never>(nil)
    private let isAuthenticatedSubject = CurrentValueSubject<Bool, Never>(false)
    private var currentAuthUser: AuthUser?
    private var currentCookie: String?

    var currentUser: AnyPublisher<UserProfile?, Never> {
        userStateSubject.eraseToAnyPublisher()
    }

    var isAuthenticated: AnyPublisher<Bool, Never> {
        isAuthenticatedSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(networkClient: NetworkClient) {
        self.networkClient = networkClient
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
        userStateSubject.send(nil)
        isAuthenticatedSubject.send(false)
    }

    func getAccessToken() -> String? {
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
        guard let user = currentAuthUser else {
            return false
        }

        let headers = ["Authorization": "Bearer \(user.token)"]

        do {
            let _: EmptyResponse = try await networkClient.request(
                "/auth/validate",
                method: .get,
                parameters: nil,
                headers: headers
            )
            return true
        } catch {
            return false
        }
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

    func getCurrentCookie() -> String? {
        currentCookie
    }

    func saveCookie(_ cookie: String) throws {
        currentCookie = cookie
    }

    func clearCookie() throws {
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
