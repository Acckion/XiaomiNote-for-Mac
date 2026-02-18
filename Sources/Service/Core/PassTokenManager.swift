import Foundation

// MARK: - 错误类型

/// PassToken 相关错误
enum PassTokenError: Error, LocalizedError {
    /// 未存储 passToken
    case noPassToken
    /// 未存储 userId
    case noUserId
    /// 步骤1：未获取到 loginUrl
    case loginUrlNotFound
    /// 步骤2：未获取到 Location 重定向 URL
    case redirectUrlNotFound
    /// 步骤3：未从 Set-Cookie 提取到 serviceToken
    case serviceTokenNotFound
    /// 网络请求错误
    case networkError(Error)
    /// 正在刷新中
    case alreadyRefreshing
    /// 响应格式异常
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noPassToken:
            "未存储 passToken"
        case .noUserId:
            "未存储 userId"
        case .loginUrlNotFound:
            "未获取到 loginUrl"
        case .redirectUrlNotFound:
            "未获取到重定向 URL"
        case .serviceTokenNotFound:
            "未从 Set-Cookie 提取到 serviceToken"
        case let .networkError(error):
            "网络请求错误: \(error.localizedDescription)"
        case .alreadyRefreshing:
            "正在刷新中"
        case .invalidResponse:
            "响应格式异常"
        }
    }
}

// MARK: - PassTokenManager

/// PassToken 认证管理器
///
/// 使用 passToken 通过三步 HTTP 流程获取 serviceToken，
/// Actor 保证并发安全
actor PassTokenManager {
    static let shared = PassTokenManager()

    // MARK: - 常量

    private let passTokenKey = "minote_pass_token"
    private let userIdKey = "minote_user_id"

    // MARK: - 缓存状态

    private var cachedServiceToken: String?
    private var lastRefreshTime: Date?
    private let tokenExpiry: TimeInterval = 600 // 10 分钟

    // MARK: - 刷新状态

    private var isRefreshing = false
    /// 等待当前刷新完成的 continuation 队列
    private var waitingContinuations: [CheckedContinuation<String, Error>] = []

    // MARK: - 设备标识

    /// 生成设备标识符，格式为 wb_ 加 UUID
    private var deviceId: String {
        "wb_\(UUID().uuidString)"
    }

    // MARK: - 凭据管理

    /// 存储 passToken 和 userId 到 UserDefaults
    func storeCredentials(passToken: String, userId: String) {
        UserDefaults.standard.set(passToken, forKey: passTokenKey)
        UserDefaults.standard.set(userId, forKey: userIdKey)
        print("[[调试]] PassToken 凭据已存储")
    }

    /// 清除存储的凭据和缓存
    func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: passTokenKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        cachedServiceToken = nil
        lastRefreshTime = nil
        isRefreshing = false
        print("[[调试]] PassToken 凭据已清除")
    }

    /// 检查是否有存储的 passToken
    func hasStoredPassToken() -> Bool {
        guard let token = UserDefaults.standard.string(forKey: passTokenKey) else {
            return false
        }
        return !token.isEmpty
    }

    /// 获取存储的 passToken
    private func getPassToken() -> String? {
        UserDefaults.standard.string(forKey: passTokenKey)
    }

    /// 获取存储的 userId
    private func getUserId() -> String? {
        UserDefaults.standard.string(forKey: userIdKey)
    }

    // MARK: - Cookie 构建

    /// 构建请求 Cookie，包含 userId、deviceId 和 passToken
    func buildRequestCookie(userId: String, deviceId: String, passToken: String) -> String {
        "userId=\(userId); deviceId=\(deviceId); passToken=\(passToken)"
    }

    /// 构建完整 Cookie，包含 userId、deviceId、passToken 和 serviceToken
    func buildFullCookie(userId: String, deviceId: String, passToken: String, serviceToken: String) -> String {
        "userId=\(userId); deviceId=\(deviceId); passToken=\(passToken); serviceToken=\(serviceToken)"
    }

    // MARK: - 解析方法

    /// 从 JSON 响应中解析 loginUrl
    ///
    /// 期望格式：`{ "data": { "loginUrl": "https://..." } }`
    func parseLoginUrl(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let loginUrl = dataDict["loginUrl"] as? String,
              !loginUrl.isEmpty
        else {
            throw PassTokenError.loginUrlNotFound
        }
        return loginUrl
    }

    /// 从 Set-Cookie 字符串中提取 serviceToken
    ///
    /// 期望格式：`serviceToken=xxx; Path=/; ...`
    func extractServiceToken(from setCookieHeader: String) throws -> String {
        // 按分号分割，查找 serviceToken 字段
        let components = setCookieHeader.components(separatedBy: ";")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("serviceToken=") {
                let value = String(trimmed.dropFirst("serviceToken=".count))
                if !value.isEmpty {
                    return value
                }
            }
        }
        throw PassTokenError.serviceTokenNotFound
    }

    /// 从多个 Set-Cookie 头中提取 serviceToken
    func extractServiceToken(from setCookieHeaders: [String]) throws -> String {
        for header in setCookieHeaders {
            if let token = try? extractServiceToken(from: header) {
                return token
            }
        }
        throw PassTokenError.serviceTokenNotFound
    }

    // MARK: - 公开接口（Task 1.3 实现）

    /// 获取 serviceToken（自动判断缓存是否过期）
    func getServiceToken() async throws -> String {
        // 缓存有效，直接返回
        if let cached = cachedServiceToken, !isCacheExpired() {
            print("[[调试]] PassToken 缓存有效，直接返回 serviceToken")
            return cached
        }

        // 缓存过期或不存在，执行刷新
        return try await performRefresh()
    }

    /// 强制刷新 serviceToken（忽略缓存）
    @discardableResult
    func refreshServiceToken() async throws -> String {
        try await performRefresh()
    }

    // MARK: - 内部刷新逻辑

    /// 执行刷新，带防重入机制
    ///
    /// 如果已有刷新正在进行，等待其完成并复用结果
    private func performRefresh() async throws -> String {
        // 防重入：如果正在刷新，等待当前刷新完成
        if isRefreshing {
            print("[[调试]] PassToken 正在刷新中，等待当前刷新完成")
            return try await withCheckedThrowingContinuation { continuation in
                waitingContinuations.append(continuation)
            }
        }

        isRefreshing = true
        print("[[调试]] PassToken 开始刷新 serviceToken")

        do {
            let serviceToken = try await performThreeStepFlow()

            // 更新缓存
            cachedServiceToken = serviceToken
            lastRefreshTime = Date()
            isRefreshing = false

            // 构建完整 Cookie 并更新 MiNoteService
            if let passToken = getPassToken(), let userId = getUserId() {
                let fullCookie = buildFullCookie(
                    userId: userId,
                    deviceId: deviceId,
                    passToken: passToken,
                    serviceToken: serviceToken
                )
                MiNoteService.shared.setCookie(fullCookie)
                print("[[调试]] PassToken 刷新成功，已更新 MiNoteService Cookie")
            }

            // 通知所有等待的调用方
            let continuations = waitingContinuations
            waitingContinuations.removeAll()
            for continuation in continuations {
                continuation.resume(returning: serviceToken)
            }

            return serviceToken
        } catch {
            isRefreshing = false

            // 通知所有等待的调用方刷新失败
            let continuations = waitingContinuations
            waitingContinuations.removeAll()
            for continuation in continuations {
                continuation.resume(throwing: error)
            }

            throw error
        }
    }

    // MARK: - 三步 HTTP 流程（Task 1.2 实现）

    /// 执行三步 HTTP 流程获取 serviceToken
    private func performThreeStepFlow() async throws -> String {
        guard let passToken = getPassToken(), !passToken.isEmpty else {
            throw PassTokenError.noPassToken
        }
        guard let userId = getUserId(), !userId.isEmpty else {
            throw PassTokenError.noUserId
        }

        let currentDeviceId = deviceId
        let cookie = buildRequestCookie(userId: userId, deviceId: currentDeviceId, passToken: passToken)

        // 步骤1：GET /api/user/login 获取 loginUrl
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        guard let step1Url = URL(string: "https://i.mi.com/api/user/login?ts=\(timestamp)&followUp=https%3A%2F%2Fi.mi.com%2F&_locale=zh_CN") else {
            throw PassTokenError.invalidResponse
        }

        var step1Request = URLRequest(url: step1Url)
        step1Request.setValue(cookie, forHTTPHeaderField: "Cookie")
        print("[[调试]] PassToken 三步流程 - 步骤1: 请求 loginUrl")

        let (step1Data, step1Response) = try await URLSession.shared.data(for: step1Request)
        guard let httpResponse1 = step1Response as? HTTPURLResponse, httpResponse1.statusCode == 200 else {
            throw PassTokenError.invalidResponse
        }

        let loginUrl = try parseLoginUrl(from: step1Data)
        print("[[调试]] PassToken 三步流程 - 步骤1: 获取到 loginUrl")

        // 步骤2：GET loginUrl 获取 Location 重定向 URL（禁用自动重定向）
        guard let step2Url = URL(string: loginUrl) else {
            throw PassTokenError.loginUrlNotFound
        }

        var step2Request = URLRequest(url: step2Url)
        step2Request.setValue(cookie, forHTTPHeaderField: "Cookie")
        print("[[调试]] PassToken 三步流程 - 步骤2: 请求重定向 URL")

        let noRedirectDelegate = NoRedirectDelegate()
        let noRedirectSession = URLSession(configuration: .default, delegate: noRedirectDelegate, delegateQueue: nil)
        defer { noRedirectSession.invalidateAndCancel() }

        let (_, step2Response) = try await noRedirectSession.data(for: step2Request)
        guard let httpResponse2 = step2Response as? HTTPURLResponse else {
            throw PassTokenError.invalidResponse
        }

        guard let redirectUrl = httpResponse2.value(forHTTPHeaderField: "Location"), !redirectUrl.isEmpty else {
            throw PassTokenError.redirectUrlNotFound
        }
        print("[[调试]] PassToken 三步流程 - 步骤2: 获取到重定向 URL")

        // 步骤3：GET redirectUrl 从 Set-Cookie 提取 serviceToken（禁用自动重定向）
        guard let step3Url = URL(string: redirectUrl) else {
            throw PassTokenError.redirectUrlNotFound
        }

        var step3Request = URLRequest(url: step3Url)
        step3Request.setValue(cookie, forHTTPHeaderField: "Cookie")
        print("[[调试]] PassToken 三步流程 - 步骤3: 请求 serviceToken")

        let noRedirectDelegate3 = NoRedirectDelegate()
        let noRedirectSession3 = URLSession(configuration: .default, delegate: noRedirectDelegate3, delegateQueue: nil)
        defer { noRedirectSession3.invalidateAndCancel() }

        let (_, step3Response) = try await noRedirectSession3.data(for: step3Request)
        guard let httpResponse3 = step3Response as? HTTPURLResponse else {
            throw PassTokenError.invalidResponse
        }

        // 从 allHeaderFields 中获取 Set-Cookie
        let allHeaders = httpResponse3.allHeaderFields
        var serviceToken: String?

        // 尝试从多个 Set-Cookie 头中提取
        if let setCookieHeaders = allHeaders["Set-Cookie"] as? String {
            serviceToken = try? extractServiceToken(from: setCookieHeaders)
        }

        // 如果上面没找到，遍历所有头查找
        if serviceToken == nil {
            for (key, value) in allHeaders {
                let keyStr = "\(key)"
                if keyStr.lowercased() == "set-cookie", let valueStr = value as? String {
                    serviceToken = try? extractServiceToken(from: valueStr)
                    if serviceToken != nil { break }
                }
            }
        }

        guard let token = serviceToken, !token.isEmpty else {
            throw PassTokenError.serviceTokenNotFound
        }

        print("[[调试]] PassToken 三步流程 - 步骤3: 成功提取 serviceToken")
        return token
    }

    // MARK: - 缓存管理

    /// 判断缓存是否过期
    func isCacheExpired() -> Bool {
        guard let lastRefresh = lastRefreshTime else {
            return true
        }
        return Date().timeIntervalSince(lastRefresh) >= tokenExpiry
    }

    /// 判断指定时间点的缓存是否过期
    func isCacheExpired(at date: Date, since lastRefresh: Date) -> Bool {
        date.timeIntervalSince(lastRefresh) >= tokenExpiry
    }
}

// MARK: - NoRedirectDelegate

/// 禁用自动重定向的 URLSession 代理
/// 用于三步流程中步骤2和步骤3，需要手动处理 302 重定向
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // 返回 nil 阻止自动重定向，以便手动获取 Location 头和 Set-Cookie
        completionHandler(nil)
    }
}
