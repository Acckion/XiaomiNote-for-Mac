import Foundation
import Combine

/// 默认认证服务实现
final class DefaultAuthenticationService: AuthenticationServiceProtocol {
    // MARK: - Properties
    private let networkClient: NetworkClient
    private let userStateSubject = CurrentValueSubject<User?, Never>(nil)
    private var currentUser: User?

    var userState: AnyPublisher<User?, Never> {
        userStateSubject.eraseToAnyPublisher()
    }

    var isAuthenticated: Bool {
        currentUser != nil
    }

    // MARK: - Initialization
    init(networkClient: NetworkClient) {
        self.networkClient = networkClient
    }

    // MARK: - Public Methods
    func login(username: String, password: String) async throws -> User {
        let parameters: [String: Any] = [
            "username": username,
            "password": password
        ]

        let response: LoginResponse = try await networkClient.request(
            "/auth/login",
            method: .post,
            parameters: parameters
        )

        let user = User(
            id: response.userId,
            username: username,
            token: response.token
        )

        currentUser = user
        userStateSubject.send(user)

        return user
    }

    func loginWithCookie(_ cookie: String) async throws -> User {
        let headers = ["Cookie": cookie]

        let response: LoginResponse = try await networkClient.request(
            "/auth/cookie-login",
            method: .post,
            headers: headers
        )

        let user = User(
            id: response.userId,
            username: response.username ?? "User",
            token: response.token
        )

        currentUser = user
        userStateSubject.send(user)

        return user
    }

    func logout() async throws {
        if let token = currentUser?.token {
            let headers = ["Authorization": "Bearer \(token)"]
            try await networkClient.request(
                "/auth/logout",
                method: .post,
                headers: headers
            ) as EmptyResponse
        }

        currentUser = nil
        userStateSubject.send(nil)
    }

    func refreshToken() async throws {
        guard let user = currentUser else {
            throw AuthError.notAuthenticated
        }

        let headers = ["Authorization": "Bearer \(user.token)"]

        let response: TokenResponse = try await networkClient.request(
            "/auth/refresh",
            method: .post,
            headers: headers
        )

        let updatedUser = User(
            id: user.id,
            username: user.username,
            token: response.token
        )

        currentUser = updatedUser
        userStateSubject.send(updatedUser)
    }

    func getCurrentUser() async throws -> User? {
        return currentUser
    }
}

// MARK: - Supporting Types
private struct LoginResponse: Decodable {
    let userId: String
    let username: String?
    let token: String
}

private struct TokenResponse: Decodable {
    let token: String
}

private struct EmptyResponse: Decodable {}

enum AuthError: Error {
    case notAuthenticated
}
