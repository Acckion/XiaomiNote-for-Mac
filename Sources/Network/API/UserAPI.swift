import Foundation

/// 用户 API
///
/// 负责用户信息获取、服务状态检查、Cookie 有效性验证
public struct UserAPI: Sendable {
    public static let shared = UserAPI()

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    // MARK: - 用户信息

    /// 获取用户信息
    ///
    /// 从小米云服务获取当前登录用户的基本信息
    ///
    /// - Returns: 用户信息字典，包含 nickname 和 icon
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchUserProfile() async throws -> [String: Any] {
        var urlComponents = URLComponents(string: "\(client.baseURL)/status/lite/profile")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        let json = try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )

        // 验证响应：检查 code 字段
        if let code = json["code"] as? Int, code != 0 {
            let message = json["description"] as? String ?? json["message"] as? String ?? "获取用户信息失败"
            throw MiNoteError.networkError(NSError(domain: "UserAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        // 返回 data 字段中的用户信息
        if let data = json["data"] as? [String: Any] {
            return data
        } else {
            return json
        }
    }

    // MARK: - 服务状态检查

    /// 检查服务状态
    ///
    /// 这是一个通用的健康检查 API，用于验证：
    /// - 服务器是否可访问
    /// - 认证是否有效
    /// - 连接是否正常
    ///
    /// - Returns: 检查结果字典，包含 result、code、description 等
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func checkServiceStatus() async throws -> [String: Any] {
        var urlComponents = URLComponents(string: "\(client.baseURL)/common/check")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        let json = try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )

        // 验证响应：检查 code 字段
        if let code = json["code"] as? Int, code != 0 {
            let message = json["description"] as? String ?? json["message"] as? String ?? "服务检查失败"
            throw MiNoteError.networkError(NSError(domain: "UserAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        return json
    }

    // MARK: - Cookie 有效性验证

    /// 检查 Cookie 在服务器端是否有效
    ///
    /// 通过调用 /common/check API 验证当前 Cookie 是否仍然有效
    ///
    /// - Returns: Cookie 是否有效
    /// - Throws: MiNoteError（网络错误等）
    func checkCookieValidity() async throws -> Bool {
        do {
            let response = try await checkServiceStatus()

            if let code = response["code"] as? Int, code == 0,
               let result = response["result"] as? String, result == "ok"
            {
                return true
            } else {
                return false
            }
        } catch {
            throw error
        }
    }

    /// 异步检查 Cookie 有效性
    ///
    /// 这个方法可以在后台调用，检查 Cookie 有效性
    /// 不会阻塞调用者，适合在定时任务中调用
    func updateCookieValidityCache() async {
        _ = try? await checkCookieValidity()
    }

    // MARK: - 加密信息

    /// 获取加密信息
    ///
    /// 用于检查端到端加密（E2EE）状态，通常在访问私密笔记或最近删除笔记时调用
    ///
    /// - Parameters:
    ///   - hsid: 硬件/服务ID，2 表示私密笔记相关服务
    ///   - appId: 应用ID，默认为 "micloud"
    /// - Returns: 加密信息字典，包含 e2eeStatus、nonce、appKeyVersion 等
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func getEncryptionInfo(hsid: Int = 2, appId: String = "micloud") async throws -> [String: Any] {
        var urlComponents = URLComponents(string: "\(client.baseURL)/mic/keybag/v1/getEncInfo")
        urlComponents?.queryItems = [
            URLQueryItem(name: "hsid", value: "\(hsid)"),
            URLQueryItem(name: "appId", value: appId),
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        let json = try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )

        if let code = json["code"] as? Int, code != 0 {
            let message = json["description"] as? String ?? json["message"] as? String ?? "获取加密信息失败"
            LogService.shared.error(.network, "获取加密信息失败，code: \(code), message: \(message)")
            throw MiNoteError.networkError(NSError(domain: "UserAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        if let data = json["data"] as? [String: Any] {
            return data
        } else {
            return json
        }
    }
}
