import Foundation
import Combine

/// 默认认证服务实现
final class DefaultAuthenticationService: AuthenticationServiceProtocol {
    // MARK: - Properties
    private let networkClient: NetworkClient
    private let userStateSubject = CurrentValueSubject<UserProfile?, Never>(nil)
    private let isAuthenticatedSubject = CurrentValueSubject<Bool, Never>(false)
    private var currentUserProfile: UserProfile?
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
            "password": password
        ]

        let response: LoginResponse = try await networkClient.request(
            "/auth/login",
            method: .post,
            parameters: parameters
        )

        let user = UserProfile(
            id: response.userId,
            username: username,
            email: response.email,
            token: response.token
        )

        currentUserProfile = user
        userStateSubject.send(user)
        isAuthenticatedSubject.send(true)

        return user
    }

    func loginWithCookie(_ cookie: String) async throws -> UserProfile {
        let headers = ["Cookie": cookie]

        let response: LoginResponse = try await networkClient.request(
            "/auth/cookie-login",
            method: .post,
            headers: headers
        )

        let user = UserProfile(
            id: response.userId,
            username: response.username ?? "User",
            email: response.email,
            token: response.token
        )

        currentUserProfile = user
        currentCookie = cookie
        userStateSubject.send(user)
        isAuthenticatedSubject.send(true)

        return user
    }

    func logout() async throws {
        if let token = currentUserProfile?.token {
            let headers = ["Authorization": "Bearer \(token)"]
            try await networkClient.request(
                "/auth/logout",
                method: .post,
                headers: headers
            ) as EmptyResponse
        }

        currentUserProfile = nil
        currentCookie = nil
        userStateSubject.send(nil)
        isAuthenticatedSubject.send(false)
    }

    func getAccessToken() -> String? {
        return currentUserProfile?.token
    }

    func refreshAccessToken() async throws -> String {
        guard let user = currentUserProfile else {
            throw AuthError.notAuthenticated
        }

        let headers = ["Authorization": "Bearer \(user.token)"]

        let response: TokenResponse = try await networkClient.request(
            "/auth/refresh",
            method: .post,
            headers: headers
        )

        let updatedUser = UserProfile(
            id: user.id,
            username: user.username,
            email: user.email,
            token: response.token
        )

        currentUserProfile = updatedUser
        userStateSubject.send(updatedUser)
        
        return response.token
    }

    func validateToken() async throws -> Bool {
        guard let user = currentUserProfile else {
            return false
        }

        let headers = ["Authorization": "Bearer \(user.token)"]

        do {
            let _: EmptyResponse = try await networkClient.request(
                "/auth/validate",
                method: .get,
                headers: headers
            )
            return true
        } catch {
            return false
        }
    }

    func fetchUserProfile() async throws -> UserProfile {
        guard let user = currentUserProfile else {
            throw AuthError.notAuthenticated
        }

        let headers = ["Authorization": "Bearer \(user.token)"]

        let response: UserProfileResponse = try await networkClient.request(
            "/user/profile",
            method: .get,
            headers: headers
        )

        let updatedUser = UserProfile(
            id: response.userId,
            username: response.username,
            email: response.email,
            token: user.token
        )

        currentUserProfile = updatedUser
        userStateSubject.send(updatedUser)

        return updatedUser
    }

    func updateUserProfile(_ profile: UserProfile) async throws {
        guard let user = currentUserProfile else {
            throw AuthError.notAuthenticated
        }

        let headers = ["Authorization": "Bearer \(user.token)"]
        let parameters: [String: Any] = [
            "username": profile.username,
            "email": profile.email ?? ""
        ]

        let _: EmptyResponse = try await networkClient.request(
            "/user/profile",
            method: .put,
            parameters: parameters,
            headers: headers
        )

        currentUserProfile = profile
        userStateSubject.send(profile)
    }

    func getCurrentCookie() -> String? {
        return currentCookie
    }

    func saveCookie(_ cookie: String) throws {
        currentCookie = cookie
    }

    func clearCookie() throws {
        currentCookie = nil
    }

    func getCurrentUser() async throws -> UserProfile? {
        return currentUserProfile
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
