import Foundation

/// API 客户端
///
/// 负责管理认证状态和执行网络请求的基础设施类。
/// 所有 API 类（NoteAPI、FolderAPI 等）都通过此类执行网络请求。
/// 使用 actor 隔离保证认证状态的线程安全。
public actor APIClient {
    public static let shared = APIClient()

    // MARK: - 配置常量

    /// 小米笔记 API 基础 URL
    nonisolated let baseURL = "https://i.mi.com"

    // MARK: - 认证状态

    /// Cookie 字符串，用于 API 认证
    private var cookie = ""

    /// ServiceToken，从 Cookie 中提取的认证令牌
    private(set) var serviceToken = ""

    /// Cookie 设置时间，用于判断是否在保护期内
    private var cookieSetTime: Date?

    /// Cookie 保护期（秒），刚设置 Cookie 后的短时间内，401 错误不视为过期
    /// 这是为了避免 Cookie 设置后立即请求时可能出现的临时认证失败
    private let cookieGracePeriod: TimeInterval = 10.0

    /// Cookie 有效性检查结果缓存
    private var cookieValidityCache = false

    /// Cookie 有效性检查时间戳
    private var cookieValidityCheckTime: Date?

    /// Cookie 有效性检查间隔（秒）
    private let cookieValidityCheckInterval: TimeInterval = 30.0

    /// 是否正在检查 Cookie 有效性
    private var isCheckingCookieValidity = false

    // MARK: - 网络请求管理器

    /// 注入的网络请求管理器（NetworkModule 创建时传入）
    private let requestManager: NetworkRequestManager?

    @MainActor
    private func getRequestManager() -> NetworkRequestManager {
        if let manager = requestManager {
            return manager
        }
        return NetworkRequestManager.shared
    }

    // MARK: - 初始化

    /// NetworkModule 使用的构造器
    init(requestManager: NetworkRequestManager) {
        self.requestManager = requestManager
        Task {
            await loadCredentials()
        }
    }

    private init() {
        self.requestManager = nil
        Task {
            await loadCredentials()
        }
    }

    @MainActor
    private func loadCredentials() {
        if let savedCookie = UserDefaults.standard.string(forKey: "minote_cookie") {
            // loadCredentials 在 @MainActor 上下文中，不能直接访问 actor 隔离属性
            // 通过 Task 回到 actor 上下文
            let cookieValue = savedCookie
            Task {
                await self.setInitialCookie(cookieValue)
            }
        }
    }

    /// 初始化时设置 Cookie（仅供 loadCredentials 使用）
    private func setInitialCookie(_ cookieValue: String) {
        cookie = cookieValue
        extractServiceToken()
    }

    @MainActor
    private func saveCredentials(_ cookieValue: String) {
        UserDefaults.standard.set(cookieValue, forKey: "minote_cookie")
    }

    // MARK: - 请求执行

    /// 使用 NetworkRequestManager 执行请求
    ///
    /// - Parameters:
    ///   - url: 请求 URL
    ///   - method: HTTP 方法
    ///   - headers: 请求头
    ///   - body: 请求体数据
    ///   - priority: 请求优先级
    ///   - cachePolicy: 缓存策略
    /// - Returns: API 响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func performRequest(
        url: String,
        method: String = "GET",
        headers: [String: String]? = nil,
        body: Data? = nil,
        priority: RequestPriority = .normal,
        cachePolicy: NetworkRequest.CachePolicy = .noCache
    ) async throws -> sending [String: Any] {
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
        await NetworkLogger.shared.logRequest(
            url: url,
            method: method,
            headers: headers,
            body: bodyString
        )

        do {
            let manager = await getRequestManager()
            let response = try await manager.request(
                url: url,
                method: method,
                headers: headers,
                body: body,
                priority: priority,
                cachePolicy: cachePolicy,
                retryOnFailure: true
            )

            let responseString = String(data: response.data, encoding: .utf8)

            await NetworkLogger.shared.logResponse(
                url: url,
                method: method,
                statusCode: response.response.statusCode,
                headers: response.response.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            if response.response.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: url)
            }

            if response.response.statusCode != 200 {
                let errorMessage = responseString ?? "未知错误"
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            return try JSONSerialization.jsonObject(with: response.data) as? [String: Any] ?? [:]
        } catch {
            await NetworkLogger.shared.logError(url: url, method: method, error: error)
            throw error
        }
    }

    // MARK: - Cookie 和 Token 管理

    /// 从 Cookie 字符串中提取 ServiceToken
    private func extractServiceToken() {
        let pattern = "serviceToken=([^;]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let range = NSRange(location: 0, length: cookie.utf16.count)
        if let match = regex.firstMatch(in: cookie, options: [], range: range),
           let tokenRange = Range(match.range(at: 1), in: cookie)
        {
            serviceToken = String(cookie[tokenRange])
        }
    }

    /// 设置 Cookie 并提取 ServiceToken
    func setCookie(_ newCookie: String) {
        cookie = newCookie
        extractServiceToken()
        cookieSetTime = Date()

        let cookieValue = cookie
        Task {
            await saveCredentials(cookieValue)
        }

        cookieValidityCache = true
        cookieValidityCheckTime = Date()
        isCheckingCookieValidity = false
    }

    /// 清除 Cookie
    func clearCookie() {
        cookie = ""
        serviceToken = ""
        cookieSetTime = nil
        UserDefaults.standard.removeObject(forKey: "minote_cookie")
    }

    /// 检查是否已认证
    public func isAuthenticated() -> Bool {
        !cookie.isEmpty && !serviceToken.isEmpty
    }

    /// 检查 Cookie 是否有效
    @MainActor
    func hasValidCookie() -> Bool {
        guard let cookie = UserDefaults.standard.string(forKey: "minote_cookie"),
              !cookie.isEmpty
        else {
            return false
        }

        let hasUserId = cookie.contains("userId=")
        let hasServiceToken = cookie.contains("serviceToken=")

        if !hasUserId || !hasServiceToken {
            return false
        }

        return true
    }

    /// 刷新 Cookie（通过 PassTokenManager 三步流程）
    func refreshCookie() async throws -> Bool {
        let isValid = await MainActor.run {
            hasValidCookie()
        }

        if isValid {
            return true
        }

        do {
            let _ = try await PassTokenManager.shared.refreshServiceToken()
            return true
        } catch {
            throw error
        }
    }

    // MARK: - 请求头

    /// 获取通用请求头
    func getHeaders() -> [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept-Encoding": "gzip, deflate, br",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Cookie": cookie,
        ]
    }

    /// 获取 POST 请求头（包含 origin 和 referer）
    func getPostHeaders() -> [String: String] {
        var headers = getHeaders()
        headers["origin"] = "https://i.mi.com"
        headers["referer"] = "https://i.mi.com/note/h5"
        return headers
    }

    // MARK: - 工具方法

    /// 模拟 JavaScript 的 encodeURIComponent 函数
    ///
    /// 只编码除了字母、数字和 -_.!~*'() 之外的所有字符
    nonisolated func encodeURIComponent(_ string: String) -> String {
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
    }

    /// 处理 HTTP 401 未授权错误
    func handle401Error(responseBody _: String, urlString _: String) throws {
        let hasCookie = !cookie.isEmpty && cookie.contains("serviceToken=")

        if hasCookie {
            throw MiNoteError.cookieExpired
        } else {
            throw MiNoteError.notAuthenticated
        }
    }

    // MARK: - 内部方法

    /// 检查是否在 Cookie 设置后的保护期内
    private func checkIfInGracePeriod() -> Bool {
        guard let setTime = cookieSetTime else {
            return false
        }
        let elapsed = Date().timeIntervalSince(setTime)
        return elapsed < cookieGracePeriod
    }
}
