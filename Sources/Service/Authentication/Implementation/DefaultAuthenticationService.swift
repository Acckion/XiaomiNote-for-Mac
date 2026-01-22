import Foundation
import Combine

/// 默认认证服务实现
final class DefaultAuthenticationService: AuthenticationServiceProtocol {
    // MARK: - Properties
    private let networkClient: NetworkClient
    private let userStateSubject = CurrentValueSubject<UserProfile?, Never>(nil)
    private var currentUserProfile: UserProfile?

    var userState: AnyPublisher<UserProfile?, Never> {
        userStateSubject.eraseToAnyPublisher()
    }

    var isAuthenticated: Bool {
        currentUserProfile != nil
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
        userStateSubject.send(user)

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
        userStateSubject.send(nil)
    }

    func refreshToken() async throws {
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

private struct EmptyResponse: Decodable {}

enum AuthError: Error {
    case notAuthenticated
}
