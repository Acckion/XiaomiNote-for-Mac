import CryptoKit
import Foundation

/// 小米笔记服务
///
/// 负责与小米笔记API的所有网络交互，包括：
/// - 认证管理（Cookie和ServiceToken）
/// - 笔记CRUD操作
/// - 文件夹管理
/// - 文件上传/下载
/// - 错误处理和重试逻辑
public final class MiNoteService: @unchecked Sendable {
    public static let shared = MiNoteService()

    // MARK: - 配置常量

    /// 小米笔记API基础URL
    let baseURL = "https://i.mi.com"

    // MARK: - 网络请求管理器

    /// 网络请求管理器（可选，逐步迁移）
    private var requestManager: NetworkRequestManager?

    @MainActor
    private func getRequestManager() -> NetworkRequestManager {
        NetworkRequestManager.shared
    }

    /// 使用 NetworkRequestManager 执行请求（辅助方法）
    ///
    /// - Parameters:
    ///   - url: 请求URL
    ///   - method: HTTP方法
    ///   - headers: 请求头
    ///   - body: 请求体数据
    ///   - priority: 请求优先级
    ///   - cachePolicy: 缓存策略
    /// - Returns: API响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    @MainActor
    private func performRequest(
        url: String,
        method: String = "GET",
        headers: [String: String]? = nil,
        body: Data? = nil,
        priority: RequestPriority = .normal,
        cachePolicy: NetworkRequest.CachePolicy = .noCache
    ) async throws -> [String: Any] {
        // 记录请求
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
        NetworkLogger.shared.logRequest(
            url: url,
            method: method,
            headers: headers,
            body: bodyString
        )

        do {
            // 使用 NetworkRequestManager 执行请求
            let response = try await NetworkRequestManager.shared.request(
                url: url,
                method: method,
                headers: headers,
                body: body,
                priority: priority,
                cachePolicy: cachePolicy,
                retryOnFailure: true
            )

            let responseString = String(data: response.data, encoding: .utf8)

            // 记录响应
            NetworkLogger.shared.logResponse(
                url: url,
                method: method,
                statusCode: response.response.statusCode,
                headers: response.response.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            // 处理401未授权错误
            if response.response.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: url)
            }

            // 检查状态码
            if response.response.statusCode != 200 {
                let errorMessage = responseString ?? "未知错误"
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            // 解析JSON响应
            return try JSONSerialization.jsonObject(with: response.data) as? [String: Any] ?? [:]
        } catch {
            NetworkLogger.shared.logError(url: url, method: method, error: error)

            // 重新抛出错误，让 NetworkRequestManager 处理重试
            throw error
        }
    }

    // MARK: - 认证状态

    /// Cookie字符串，用于API认证
    private var cookie = ""

    /// ServiceToken，从Cookie中提取的认证令牌
    private var serviceToken = ""

    /// Cookie过期回调，当检测到Cookie过期时调用
    var onCookieExpired: (() -> Void)?

    /// Cookie是否已标记为失效（用于防止重复触发回调）
    private var cookieExpiredFlag = false
    private let cookieExpiredLock = NSLock()

    /// Cookie设置时间，用于判断是否在保护期内
    private var cookieSetTime: Date?

    /// Cookie保护期（秒），刚设置Cookie后的短时间内，401错误不视为过期
    /// 这是为了避免Cookie设置后立即请求时可能出现的临时认证失败
    private let cookieGracePeriod: TimeInterval = 10.0

    /// Cookie有效性检查结果缓存
    private var cookieValidityCache = false

    /// Cookie有效性检查时间戳
    private var cookieValidityCheckTime: Date?

    /// Cookie有效性检查间隔（秒）
    private let cookieValidityCheckInterval: TimeInterval = 30.0

    /// Cookie有效性检查队列（用于异步安全的锁）
    private let cookieValidityQueue = DispatchQueue(label: "com.minote.cookieValidityQueue")

    /// 是否正在检查Cookie有效性
    private var isCheckingCookieValidity = false

    private init() {
        // 从 UserDefaults 加载 cookie
        Task {
            await loadCredentials()
        }
    }

    @MainActor
    private func loadCredentials() {
        if let savedCookie = UserDefaults.standard.string(forKey: "minote_cookie") {
            cookie = savedCookie
            extractServiceToken()
        }
    }

    @MainActor
    private func saveCredentials() {
        UserDefaults.standard.set(cookie, forKey: "minote_cookie")
    }

    // MARK: - Cookie和Token管理

    /// 从Cookie字符串中提取ServiceToken
    /// ServiceToken是小米笔记API认证的关键参数，需要从Cookie中解析
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

    func setCookie(_ newCookie: String) {
        // 使用现有的锁来确保线程安全
        cookieExpiredLock.lock()
        cookie = newCookie
        extractServiceToken()
        cookieSetTime = Date()
        cookieExpiredFlag = false
        cookieExpiredLock.unlock()

        // 异步保存凭据
        Task {
            await saveCredentials()
        }

        // 强制更新Cookie有效性缓存为true，因为新设置的Cookie应该是有效的
        cookieValidityQueue.sync {
            cookieValidityCache = true
            cookieValidityCheckTime = Date()
            isCheckingCookieValidity = false
        }

    }

    public func isAuthenticated() -> Bool {
        !cookie.isEmpty && !serviceToken.isEmpty
    }

    func getHeaders() -> [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept-Encoding": "gzip, deflate, br",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Cookie": cookie,
        ]
    }

    /// 获取用于 POST 请求的请求头（包含 origin 和 referer）
    private func getPostHeaders() -> [String: String] {
        var headers = getHeaders()
        headers["origin"] = "https://i.mi.com"
        headers["referer"] = "https://i.mi.com/note/h5"
        return headers
    }

    // MARK: - 工具方法

    /// 模拟 JavaScript 的 encodeURIComponent 函数
    ///
    /// 小米笔记API使用URL编码，需要与JavaScript的encodeURIComponent行为一致
    /// 只编码除了字母、数字和 -_.!~*'() 之外的所有字符
    ///
    /// - Parameter string: 需要编码的字符串
    /// - Returns: URL编码后的字符串
    private func encodeURIComponent(_ string: String) -> String {
        // 定义不需要编码的字符集（字母、数字和 -_.!~*'()）
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
    }

    /// 处理HTTP 401未授权错误
    ///
    /// 根据响应内容判断是Cookie过期、未登录还是其他认证问题
    /// 考虑Cookie保护期，避免刚设置Cookie后的临时认证失败被误判为过期
    ///
    /// - Parameters:
    ///   - responseBody: HTTP响应体字符串
    ///   - urlString: 请求URL（用于日志）
    /// - Throws: MiNoteError（cookieExpired、notAuthenticated或networkError）
    func handle401Error(responseBody: String, urlString _: String) throws {
        // 检查响应中是否包含登录重定向URL（明确的认证失败标志）
        let hasLoginURL = responseBody.contains("serviceLogin") ||
            responseBody.contains("account.xiaomi.com") ||
            responseBody.contains("pass/serviceLogin")

        // 检查响应中是否包含认证错误关键词
        let hasAuthKeywords = responseBody.contains("unauthorized") ||
            responseBody.contains("未授权") ||
            responseBody.contains("登录") ||
            responseBody.contains("login") ||
            responseBody.contains("\"R\":401") ||
            responseBody.contains("\"S\":\"Err\"")

        let isAuthError = hasLoginURL || hasAuthKeywords

        // 检查是否有Cookie（无论是否有效）
        let hasCookie = !cookie.isEmpty && cookie.contains("serviceToken=")

        // 如果有Cookie（无论是否有效）且是认证错误：视为Cookie过期
        if hasCookie, isAuthError {
            if hasLoginURL {
            }
            // 使用锁确保只触发一次回调
            cookieExpiredLock.lock()
            let shouldTrigger = !cookieExpiredFlag
            if shouldTrigger {
                cookieExpiredFlag = true
            } else {
            }
            cookieExpiredLock.unlock()

            if shouldTrigger {
                DispatchQueue.main.async {
                    self.onCookieExpired?()
                }
            }
            throw MiNoteError.cookieExpired
        }
        // 如果有Cookie（无论是否有效）但不是明确的认证错误：仍然可能是Cookie问题，设置为离线状态
        else if hasCookie, !isAuthError {
            // 使用锁确保只触发一次回调
            cookieExpiredLock.lock()
            let shouldTrigger = !cookieExpiredFlag
            if shouldTrigger {
                cookieExpiredFlag = true
            } else {
            }
            cookieExpiredLock.unlock()

            if shouldTrigger {
                DispatchQueue.main.async {
                    self.onCookieExpired?()
                }
            }
            throw MiNoteError.cookieExpired // 统一作为cookieExpired处理，确保添加到离线队列
        }
        // 没有Cookie：说明尚未登录
        else {
            throw MiNoteError.notAuthenticated
        }
    }

    // MARK: - API Methods

    // MARK: 删除笔记

    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - tag: 笔记的tag（版本标识），用于并发控制
    ///   - purge: 是否永久删除（true）还是移到回收站（false）
    /// - Returns: API响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func deleteNote(noteId: String, tag: String, purge: Bool = false) async throws -> [String: Any] {
        // 构建请求体：tag={tag}&purge={purge}&serviceToken={serviceToken}
        let tagEncoded = encodeURIComponent(tag)
        let purgeString = purge ? "true" : "false"
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "tag=\(tagEncoded)&purge=\(purgeString)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(baseURL)/note/full/\(noteId)/delete"

        // 记录请求
        let postHeaders = getPostHeaders()
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: body
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                // 记录响应
                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "POST",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                // 处理401未授权错误
                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }

                if httpResponse.statusCode != 200 {
                    let errorMessage = responseString ?? "未知错误"
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }

            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }

    /// 恢复回收站笔记
    ///
    /// 从回收站恢复笔记到原文件夹
    /// API端点: POST https://i.mi.com/note/note/{noteId}/restore
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - tag: 笔记的tag（版本标识），用于并发控制
    /// - Returns: API响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func restoreDeletedNote(noteId: String, tag: String) async throws -> [String: Any] {
        // 构建请求体：tag={tag}&serviceToken={serviceToken}
        let tagEncoded = encodeURIComponent(tag)
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "tag=\(tagEncoded)&serviceToken=\(serviceTokenEncoded)"

        // 使用正确的恢复API端点
        let urlString = "\(baseURL)/note/note/\(noteId)/restore"

        // 记录请求
        let postHeaders = getPostHeaders()
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: body
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                // 记录响应
                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "POST",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                // 处理401未授权错误
                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }

                if httpResponse.statusCode != 200 {
                    let errorMessage = responseString ?? "未知错误"
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }

            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }

    // MARK: 获取私密笔记列表

    ///
    /// 获取指定文件夹（通常是私密笔记文件夹，folderId=2）的笔记列表
    ///
    /// - Parameters:
    ///   - folderId: 文件夹ID，默认为2（私密笔记）
    ///   - limit: 每页数量，默认200
    /// - Returns: 包含笔记列表的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchPrivateNotes(folderId: String = "2", limit: Int = 200) async throws -> [String: Any] {
        // 构建URL参数
        var urlComponents = URLComponents(string: "\(baseURL)/note/full/folder")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "folderId", value: folderId),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/full/folder", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        // 记录请求
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let responseString = String(data: data, encoding: .utf8)

            // 记录响应
            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "GET",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            // 处理401未授权错误
            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "获取私密笔记失败"
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
            }

            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    // MARK: 获取笔记列表（分页）

    ///
    /// 用于同步功能，支持完整同步和增量同步
    ///
    /// 注意：完整同步和增量同步都使用此方法，但syncTag参数仅用于内部逻辑，
    /// 不会作为查询参数发送到服务器。服务器无法解析syncTag查询参数。
    ///
    /// 使用示例：
    /// 1. 完整同步（第一次同步）：`fetchPage()` 不带syncTag参数
    /// 2. 增量同步（通过修改时间判断）：`fetchPage()` 然后比较笔记的modifyDate
    ///
    /// 响应格式：{"data": {"entries": [...], "folders": [...], "syncTag": "..."}}
    ///
    /// - Parameter syncTag: 同步标签，用于增量同步。空字符串表示获取第一页
    /// - Returns: 包含笔记和文件夹列表的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchPage(syncTag _: String = "") async throws -> [String: Any] {
        // 正确编码URL参数
        var urlComponents = URLComponents(string: "\(baseURL)/note/full/page")

        // 构建查询参数
        // 注意：完整同步和增量同步在任何情况下都不要syncTag查询参数
        // syncTag仅用于内部逻辑，不会发送到服务器
        let queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "limit", value: "200"),
        ]

        urlComponents?.queryItems = queryItems

        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/full/page", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        // 记录请求
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        guard let url = urlComponents?.url else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                // 记录响应
                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "GET",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                // 检查401未授权错误
                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }
            }

            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    // MARK: 获取笔记详情（完整内容）

    ///
    /// 笔记列表API只返回摘要（snippet），需要调用此方法获取完整内容
    ///
    /// - Parameter noteId: 笔记ID
    /// - Returns: 包含完整笔记内容的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchNoteDetails(noteId: String) async throws -> [String: Any] {
        // 正确编码URL参数
        var urlComponents = URLComponents(string: "\(baseURL)/note/note/\(noteId)/")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/note/\(noteId)/", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        // 记录请求
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        guard let url = urlComponents?.url else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                // 记录响应
                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "GET",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }
            }

            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    /// 创建新笔记
    ///
    /// - Parameters:
    ///   - title: 笔记标题（存储在extraInfo中）
    ///   - content: 笔记内容（XML格式）
    ///   - folderId: 文件夹ID，默认为"0"（所有笔记）
    /// - Returns: 包含新创建笔记信息的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func createNote(title: String, content: String, folderId: String = "0") async throws -> [String: Any] {
        // 移除 content 中的 <new-format/> 前缀（上传时不需要）
        var cleanedContent = content
        if cleanedContent.hasPrefix("<new-format/>") {
            cleanedContent = String(cleanedContent.dropFirst("<new-format/>".count))
        }

        // 构建 extraInfo，包含标题（参考 updateNote 的实现）
        let extraInfoDict: [String: Any] = [
            "note_content_type": "common",
            "web_images": "",
            "mind_content_plain_text": "",
            "title": title,
            "mind_content": "",
        ]

        guard let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfoDict),
              let extraInfoString = String(data: extraInfoData, encoding: .utf8)
        else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/note", method: "POST", error: URLError(.cannotParseResponse))
            throw URLError(.cannotParseResponse)
        }

        let entry: [String: Any] = [
            "content": cleanedContent,
            "colorId": 0,
            "folderId": folderId,
            "createDate": Int(Date().timeIntervalSince1970 * 1000),
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000),
            "extraInfo": extraInfoString, // 添加 extraInfo 包含标题
        ]

        // 使用 JSONSerialization 的 sortedKeys 选项确保字段顺序一致
        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8)
        else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/note", method: "POST", error: URLError(.cannotParseResponse))
            throw URLError(.cannotParseResponse)
        }

        // 参考 Obsidian 插件：使用 encodeURIComponent 进行 URL 编码
        let entryEncoded = encodeURIComponent(entryJson)
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "entry=\(entryEncoded)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(baseURL)/note/note"

        // 记录请求
        let postHeaders = getPostHeaders()
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: body
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let responseString = String(data: data, encoding: .utf8)

            // 记录响应
            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "POST",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "创建笔记失败"
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                }
            }

            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }

    /// 创建文件夹
    func createFolder(name: String) async throws -> [String: Any] {
        let entry: [String: Any] = [
            "subject": name,
            "createDate": Int(Date().timeIntervalSince1970 * 1000),
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000),
        ]

        // 使用 JSONSerialization 的 sortedKeys 选项确保字段顺序一致
        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8)
        else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/folder", method: "POST", error: URLError(.cannotParseResponse))
            throw URLError(.cannotParseResponse)
        }

        // 参考 Obsidian 插件：使用 encodeURIComponent 进行 URL 编码
        let entryEncoded = encodeURIComponent(entryJson)
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "entry=\(entryEncoded)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(baseURL)/note/folder"

        // 记录请求
        let postHeaders = getPostHeaders()
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: body
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let responseString = String(data: data, encoding: .utf8)

            // 记录响应
            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "POST",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "创建文件夹失败"
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                }
            }

            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }

    /// 获取文件夹详情
    func fetchFolderDetails(folderId: String) async throws -> [String: Any] {
        // 使用 /note/full/page API 获取文件夹信息，需要遍历所有分页以确保找到目标文件夹
        var syncTag = ""
        var foundFolder: [String: Any]?

        // 遍历所有分页，直到找到目标文件夹或没有更多数据
        while foundFolder == nil {
            let pageResponse = try await fetchPage(syncTag: syncTag)

            // 解析文件夹列表
            if let data = pageResponse["data"] as? [String: Any],
               let folderEntries = data["folders"] as? [[String: Any]]
            {

                // 查找目标文件夹
                for folderEntry in folderEntries {
                    // 处理 ID（可能是 String 或 Int）
                    var entryId: String?
                    if let idString = folderEntry["id"] as? String {
                        entryId = idString
                    } else if let idInt = folderEntry["id"] as? Int {
                        entryId = String(idInt)
                    }

                    if entryId == folderId {
                        foundFolder = folderEntry
                        break
                    }
                }

                // 如果已经找到文件夹，退出循环
                if foundFolder != nil {
                    break
                }

                // 检查是否有更多分页（syncTag 在响应顶层，不在 data 中）
                if let nextSyncTag = pageResponse["syncTag"] as? String, !nextSyncTag.isEmpty, nextSyncTag != syncTag {
                    syncTag = nextSyncTag
                    // 继续查找下一页
                } else {
                    // 没有更多分页，退出循环
                    break
                }
            } else {
                // 响应格式不正确或没有文件夹数据，退出循环
                break
            }
        }

        // 如果找到了文件夹，构造返回格式（与原来的 API 格式一致）
        if let folderEntry = foundFolder {
            // 返回格式: {"data": {"entry": {...}}}
            return [
                "code": 0,
                "data": [
                    "entry": folderEntry,
                ],
            ]
        } else {
            // 未找到文件夹
            throw NSError(domain: "MiNoteService", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在: \(folderId)"])
        }
    }

    /// 重命名文件夹
    func renameFolder(folderId: String, newName: String, existingTag: String, originalCreateDate: Int? = nil) async throws -> [String: Any] {
        let createDate = originalCreateDate ?? Int(Date().timeIntervalSince1970 * 1000)

        let entry: [String: Any] = [
            "id": folderId,
            "tag": existingTag,
            "createDate": createDate,
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000),
            "subject": newName,
            "type": "folder",
        ]

        // 使用 JSONSerialization 的 sortedKeys 选项确保字段顺序一致
        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8)
        else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/folder/\(folderId)", method: "POST", error: URLError(.cannotParseResponse))
            throw URLError(.cannotParseResponse)
        }

        // 参考 Obsidian 插件：使用 encodeURIComponent 进行 URL 编码
        let entryEncoded = encodeURIComponent(entryJson)
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "entry=\(entryEncoded)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(baseURL)/note/folder/\(folderId)"

        // 记录请求
        let postHeaders = getPostHeaders()
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: body
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let responseString = String(data: data, encoding: .utf8)

            // 记录响应
            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "POST",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 记录响应内容以便调试

            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "重命名文件夹失败"
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
            }

            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }

    /// 删除文件夹
    func deleteFolder(folderId: String, tag: String, purge: Bool = false) async throws -> [String: Any] {
        // 构建请求体：tag={tag}&purge={purge}&serviceToken={serviceToken}
        let tagEncoded = encodeURIComponent(tag)
        let purgeString = purge ? "true" : "false"
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "tag=\(tagEncoded)&purge=\(purgeString)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(baseURL)/note/full/\(folderId)/delete"

        // 记录请求
        let postHeaders = getPostHeaders()
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: body
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let responseString = String(data: data, encoding: .utf8)

            // 记录响应
            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "POST",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 记录响应内容以便调试

            // 验证响应：检查 code 字段
            // 如果响应中没有 code 字段，或者 code 为 0，则认为成功
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "删除文件夹失败"
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
            }

            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }

    /// 更新笔记
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - title: 笔记标题
    ///   - content: 笔记内容（XML格式）
    ///   - folderId: 文件夹ID
    ///   - existingTag: 现有tag（版本标识），用于并发控制。如果为空，会从服务器获取最新tag
    ///   - originalCreateDate: 原始创建时间戳（毫秒），用于保持创建时间不变
    ///   - imageData: 图片数据数组（setting.data），用于保存笔记中的图片引用
    /// - Returns: 更新后的笔记信息
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func updateNote(
        noteId: String,
        title: String,
        content: String,
        folderId: String = "0",
        existingTag: String = "",
        originalCreateDate: Int? = nil,
        imageData: [[String: Any]]? = nil
    ) async throws -> [String: Any] {
        let createDate = originalCreateDate ?? Int(Date().timeIntervalSince1970 * 1000)

        // 参考正确的请求示例：extraInfo 应该是包含字段的 JSON 字符串
        let extraInfoDict: [String: Any] = [
            "note_content_type": "common",
            "web_images": "",
            "mind_content_plain_text": "",
            "title": title,
            "mind_content": "",
        ]

        guard let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfoDict),
              let extraInfoString = String(data: extraInfoData, encoding: .utf8)
        else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/note/\(noteId)", method: "POST", error: URLError(.cannotParseResponse))
            throw URLError(.cannotParseResponse)
        }

        // 移除 content 中的 <new-format/> 前缀（上传时不需要）
        var cleanedContent = content
        if cleanedContent.hasPrefix("<new-format/>") {
            cleanedContent = String(cleanedContent.dropFirst("<new-format/>".count))
        }

        // 构建 setting 对象，如果提供了图片数据则包含
        var setting: [String: Any] = [
            "themeId": 0,
            "stickyTime": 0,
            "version": 0,
        ]
        if let imageData, !imageData.isEmpty {
            setting["data"] = imageData
        }

        let entry: [String: Any] = [
            "id": noteId,
            "tag": existingTag,
            "status": "normal",
            "createDate": createDate,
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000),
            "colorId": 0,
            "content": cleanedContent,
            "setting": setting,
            "folderId": folderId,
            "alertDate": 0,
            "extraInfo": extraInfoString,
        ]

        // 使用 JSONSerialization 的 sortedKeys 选项确保字段顺序一致
        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8)
        else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/note/\(noteId)", method: "POST", error: URLError(.cannotParseResponse))
            throw URLError(.cannotParseResponse)
        }

        // 参考 Obsidian 插件：使用 encodeURIComponent 进行 URL 编码
        // 在 Swift 中，我们需要模拟 encodeURIComponent 的行为
        // encodeURIComponent 会编码除了字母、数字和 -_.!~*'() 之外的所有字符
        let entryEncoded = encodeURIComponent(entryJson)
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "entry=\(entryEncoded)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(baseURL)/note/note/\(noteId)"

        // 记录请求
        let postHeaders = getPostHeaders()
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: body
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                // 记录响应
                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "POST",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }

    // MARK: - Cookie Management

    /// 刷新Cookie（通过 PassTokenManager 三步流程）
    ///
    /// 使用 PassToken 通过纯 HTTP 请求刷新 serviceToken，
    /// 替代旧的 WebView 模拟点击方式
    ///
    /// - Returns: 是否成功刷新
    func refreshCookie() async throws -> Bool {

        // 先检查Cookie是否仍然有效，避免不必要的刷新
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

    func clearCookie() {
        cookie = ""
        serviceToken = ""
        cookieSetTime = nil
        cookieExpiredLock.lock()
        cookieExpiredFlag = false
        cookieExpiredLock.unlock()
        UserDefaults.standard.removeObject(forKey: "minote_cookie")
    }

    /// 检查Cookie是否有效
    ///
    /// 用户要求：任何网络请求都不要使用缓存的cookie，从用户信息中获取当前最新的cookie。
    /// 因此，这个方法总是从UserDefaults获取最新的Cookie，并检查其格式和服务器端有效性。
    ///
    /// 注意：这个方法不缓存结果，每次调用都会检查最新的状态。
    @MainActor
    func hasValidCookie() -> Bool {
        // 首先检查是否有Cookie失效标志
        cookieExpiredLock.lock()
        let isExpired = cookieExpiredFlag
        cookieExpiredLock.unlock()

        if isExpired {
            return false
        }

        // 从UserDefaults获取最新的Cookie
        guard let cookie = UserDefaults.standard.string(forKey: "minote_cookie"),
              !cookie.isEmpty
        else {
            return false
        }

        // 检查Cookie是否包含必要的字段
        let hasUserId = cookie.contains("userId=")
        let hasServiceToken = cookie.contains("serviceToken=")

        if !hasUserId || !hasServiceToken {
            return false
        }

        // 使用 ScheduledTaskManager 的实时检查结果
        // ScheduledTaskManager 会定期检查Cookie在服务器端的有效性
        // 注意：isCookieValid 属性是实时更新的，由定时任务维护
        let isCookieValid = ScheduledTaskManager.shared.isCookieValid

        return isCookieValid
    }

    /// 检查是否在 cookie 设置后的保护期内
    private func checkIfInGracePeriod() -> Bool {
        guard let setTime = cookieSetTime else {
            return false
        }
        let elapsed = Date().timeIntervalSince(setTime)
        return elapsed < cookieGracePeriod
    }

    /// 检查Cookie在服务器端是否有效
    ///
    /// 发送实际的网络请求到 /common/check 来验证Cookie是否真的有效
    /// 用户要求：任何网络请求都不要使用缓存的cookie，所以这个方法总是进行实时检查
    ///
    /// - Returns: 如果Cookie在服务器端有效则返回true，否则返回false
    /// - Throws: 网络错误或其他错误
    func checkCookieValidity() async throws -> Bool {

        do {
            // 使用 /common/check API 检查Cookie有效性
            let response = try await checkServiceStatus()

            // 解析响应
            if let code = response["code"] as? Int, code == 0,
               let result = response["result"] as? String, result == "ok"
            {
                return true
            } else {
                return false
            }
        } catch {
            throw error // 抛出错误，让调用者处理
        }
    }

    /// 异步检查Cookie有效性
    ///
    /// 这个方法可以在后台调用，检查Cookie有效性
    /// 不会阻塞调用者，适合在定时任务中调用
    func updateCookieValidityCache() async {
        _ = try? await checkCookieValidity()
    }

    // MARK: - Helper Methods

    /// 从响应中提取syncTag
    ///
    /// 支持两种响应格式：
    /// 1. 完整/增量同步：response["syncTag"] 或 response["data"]["syncTag"]
    /// 2. 轻量级同步：response["data"]["note_view"]["data"]["syncTag"]
    ///
    /// - Parameter response: API响应字典
    /// - Returns: syncTag字符串，如果找不到则返回空字符串
    func extractSyncTag(from response: [String: Any]) -> String {
        // 首先尝试从响应顶层获取
        if let syncTag = response["syncTag"] as? String {
            return syncTag
        }

        // 尝试从data字段获取
        if let data = response["data"] as? [String: Any] {
            // 完整/增量同步格式：data.syncTag
            if let syncTag = data["syncTag"] as? String {
                return syncTag
            }

            // 轻量级同步格式：data.note_view.data.syncTag
            if let noteView = data["note_view"] as? [String: Any],
               let noteViewData = noteView["data"] as? [String: Any],
               let syncTag = noteViewData["syncTag"] as? String
            {
                return syncTag
            }
        }

        return ""
    }

    /// 解析笔记列表
    ///
    /// 支持两种响应格式：
    /// 1. 完整/增量同步：response["data"]["entries"]
    /// 2. 轻量级同步：response["data"]["note_view"]["data"]["entries"]
    ///
    /// - Parameter response: API响应字典
    /// - Returns: 笔记对象数组
    func parseNotes(from response: [String: Any]) -> [Note] {
        var notes: [Note] = []
        var entries: [[String: Any]] = []

        // 首先尝试完整/增量同步格式：data.entries
        if let data = response["data"] as? [String: Any],
           let dataEntries = data["entries"] as? [[String: Any]]
        {
            entries = dataEntries
        }
        // 尝试轻量级同步格式：data.note_view.data.entries
        else if let data = response["data"] as? [String: Any],
                let noteView = data["note_view"] as? [String: Any],
                let noteViewData = noteView["data"] as? [String: Any],
                let noteViewEntries = noteViewData["entries"] as? [[String: Any]]
        {
            entries = noteViewEntries
        }
        // 如果data字段没有，尝试直接从响应中获取（向后兼容）
        else if let responseEntries = response["entries"] as? [[String: Any]] {
            entries = responseEntries
        } else {
            if let data = response["data"] as? [String: Any] {
            }
        }

        for entry in entries {
            if let note = Note.fromMinoteData(entry) {
                notes.append(note)
            }
        }

        return notes
    }

    /// 解析文件夹列表
    ///
    /// 支持两种响应格式：
    /// 1. 完整/增量同步：response["data"]["folders"]
    /// 2. 轻量级同步：response["data"]["note_view"]["data"]["folders"]
    ///
    /// - Parameter response: API响应字典
    /// - Returns: 文件夹对象数组
    func parseFolders(from response: [String: Any]) -> [Folder] {
        var folders: [Folder] = []
        var folderEntries: [[String: Any]] = []

        // 首先尝试完整/增量同步格式：data.folders
        if let data = response["data"] as? [String: Any],
           let dataFolders = data["folders"] as? [[String: Any]]
        {
            folderEntries = dataFolders
        }
        // 尝试轻量级同步格式：data.note_view.data.folders
        else if let data = response["data"] as? [String: Any],
                let noteView = data["note_view"] as? [String: Any],
                let noteViewData = noteView["data"] as? [String: Any],
                let noteViewFolders = noteViewData["folders"] as? [[String: Any]]
        {
            folderEntries = noteViewFolders
        }
        // 如果data字段没有，尝试直接从响应中获取（向后兼容）
        else if let responseFolders = response["folders"] as? [[String: Any]] {
            folderEntries = responseFolders
        } else {
            // 打印响应结构以便调试
            if let data = response["data"] as? [String: Any] {
            }
        }

        for folderEntry in folderEntries {
            // 检查类型，只处理文件夹类型（参考 Obsidian 插件）
            if let type = folderEntry["type"] as? String, type == "folder" {
                if let folder = Folder.fromMinoteData(folderEntry) {
                    folders.append(folder)
                } else {
                }
            } else {
            }
        }

        // 添加系统文件夹（参考 Obsidian 插件：默认文件夹 id='0', name='未分类'）
        // 但为了与UI一致，我们使用"所有笔记"和"收藏"
        let hasAllNotes = folders.contains { $0.id == "0" }
        let hasStarred = folders.contains { $0.id == "starred" }

        if !hasAllNotes {
            folders.insert(Folder(id: "0", name: "所有笔记", count: 0, isSystem: true), at: 0)
        }
        if !hasStarred {
            let starredIndex = hasAllNotes ? 1 : 0
            folders.insert(Folder(id: "starred", name: "置顶", count: 0, isSystem: true), at: starredIndex)
        }


        return folders
    }

    // MARK: - File Upload

    /// 计算文件的SHA1哈希值
    private func sha1Hash(of data: Data) -> String {
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 计算文件的MD5哈希值
    private func md5Hash(of data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 上传图片到小米服务器（新API）
    /// - Parameters:
    ///   - imageData: 图片数据
    ///   - fileName: 文件名
    ///   - mimeType: MIME 类型（如 "image/jpeg", "image/png"）
    /// - Returns: 包含文件ID的响应字典
    func uploadImage(imageData: Data, fileName: String, mimeType: String) async throws -> [String: Any] {
        guard isAuthenticated() else {
            throw MiNoteError.notAuthenticated
        }

        // 计算文件哈希值
        let sha1 = sha1Hash(of: imageData)
        let md5 = md5Hash(of: imageData)
        let fileSize = imageData.count


        // 第一步：请求上传
        let requestUploadResponse = try await requestImageUpload(
            fileName: fileName,
            fileSize: fileSize,
            sha1: sha1,
            md5: md5,
            mimeType: mimeType
        )

        // 检查文件是否已存在
        var fileId: String?

        // 情况1：服务器有缓存（文件已存在）
        // 响应格式：{"data": {"fileId": "...", "digest": "...", "mimeType": "..."}}
        if let existingFileId = requestUploadResponse["fileId"] as? String {
            fileId = existingFileId
        }
        // 情况2：服务器无缓存（新文件）
        // 响应格式：{"data": {"storage": {"uploadId": "...", "exists": false, "kss": {...}}}}
        else if let storage = requestUploadResponse["storage"] as? [String: Any] {
            let exists = storage["exists"] as? Bool ?? false

            if exists {
                // 理论上不应该到这里，因为如果 exists: true，应该在上面就返回 fileId 了
                // 但为了安全起见，还是处理一下
                if let existingFileId = storage["fileId"] as? String {
                    fileId = existingFileId
                } else {
                    throw MiNoteError.invalidResponse
                }
            } else {
                // 情况2：新文件，需要实际上传
                // 新文件，需要实际上传
                guard let uploadId = storage["uploadId"] as? String,
                      let kss = storage["kss"] as? [String: Any],
                      let blockMetas = kss["block_metas"] as? [[String: Any]],
                      let firstBlockMeta = blockMetas.first,
                      let blockMeta = firstBlockMeta["block_meta"] as? String,
                      let fileMeta = kss["file_meta"] as? String,
                      let nodeUrls = kss["node_urls"] as? [String],
                      let nodeUrl = nodeUrls.first
                else {
                    throw MiNoteError.invalidResponse
                }


                // 第二步：实际上传文件数据，获取 commit_meta
                let commitMeta = try await uploadFileChunk(
                    fileData: imageData,
                    nodeUrl: nodeUrl,
                    fileMeta: fileMeta,
                    blockMeta: blockMeta,
                    chunkPos: 0
                )

                // 第三步：提交上传，获取 fileId
                fileId = try await commitImageUpload(
                    uploadId: uploadId,
                    fileSize: fileSize,
                    sha1: sha1,
                    fileMeta: fileMeta,
                    commitMeta: commitMeta
                )

            }
        }

        guard let finalFileId = fileId else {
            throw MiNoteError.invalidResponse
        }


        // 返回文件信息
        return [
            "fileId": finalFileId,
            "digest": sha1,
            "mimeType": mimeType,
        ]
    }

    // MARK: - 语音文件上传

    /// 上传语音文件到小米服务器
    ///
    /// 语音文件上传流程与图片相同，使用 `note_img` 类型。
    /// 完整流程分为三步：
    /// 1. 请求上传（request_upload_file）- 获取 uploadId 和 KSS 信息
    /// 2. 上传文件块（upload_block_chunk）- 上传实际文件数据
    /// 3. 提交上传（commit）- 确认上传完成，获取 fileId
    ///
    /// - Parameters:
    ///   - audioData: 语音文件数据
    ///   - fileName: 文件名（如 "recording.mp3"）
    ///   - mimeType: MIME 类型，推荐使用 "audio/mpeg"
    /// - Returns: 包含 fileId、digest、mimeType 的字典
    /// - Throws: MiNoteError（未认证、网络错误、响应无效等）
    public func uploadAudio(audioData: Data, fileName: String, mimeType: String = "audio/mpeg") async throws -> [String: Any] {
        guard isAuthenticated() else {
            throw MiNoteError.notAuthenticated
        }

        // 计算文件哈希值
        let sha1 = sha1Hash(of: audioData)
        let md5 = md5Hash(of: audioData)
        let fileSize = audioData.count


        // 第一步：请求上传
        // 注意：语音文件必须使用 note_img 类型（与图片相同）
        let requestUploadResponse = try await requestAudioUpload(
            fileName: fileName,
            fileSize: fileSize,
            sha1: sha1,
            md5: md5,
            mimeType: mimeType
        )

        // 检查文件是否已存在
        var fileId: String?

        // 情况1：服务器有缓存（文件已存在）
        if let existingFileId = requestUploadResponse["fileId"] as? String {
            fileId = existingFileId
        }
        // 情况2：服务器无缓存（需要实际上传）
        else if let storage = requestUploadResponse["storage"] as? [String: Any] {
            let exists = storage["exists"] as? Bool ?? false

            if exists {
                if let existingFileId = storage["fileId"] as? String {
                    fileId = existingFileId
                } else {
                    throw MiNoteError.invalidResponse
                }
            } else {
                // 新文件，需要实际上传

                guard let uploadId = storage["uploadId"] as? String,
                      let kss = storage["kss"] as? [String: Any],
                      let blockMetas = kss["block_metas"] as? [[String: Any]],
                      let firstBlockMeta = blockMetas.first,
                      let blockMeta = firstBlockMeta["block_meta"] as? String,
                      let fileMeta = kss["file_meta"] as? String,
                      let nodeUrls = kss["node_urls"] as? [String],
                      let nodeUrl = nodeUrls.first
                else {
                    throw MiNoteError.invalidResponse
                }


                // 第二步：上传文件块
                let commitMeta = try await uploadFileChunk(
                    fileData: audioData,
                    nodeUrl: nodeUrl,
                    fileMeta: fileMeta,
                    blockMeta: blockMeta,
                    chunkPos: 0
                )


                // 第三步：提交上传
                fileId = try await commitAudioUpload(
                    uploadId: uploadId,
                    fileSize: fileSize,
                    sha1: sha1,
                    fileMeta: fileMeta,
                    commitMeta: commitMeta
                )

            }
        }

        guard let finalFileId = fileId else {
            throw MiNoteError.invalidResponse
        }


        // 返回文件信息
        return [
            "fileId": finalFileId,
            "digest": sha1,
            "mimeType": mimeType,
        ]
    }

    /// 请求语音文件上传（第一步）
    ///
    /// 注意：语音文件必须使用 `note_img` 类型，与图片上传相同。
    /// `note_sound`、`note_audio`、`note_recording` 等类型都是无效的。
    private func requestAudioUpload(fileName: String, fileSize: Int, sha1: String, md5: String, mimeType: String) async throws -> [String: Any] {
        let urlString = "\(baseURL)/file/v2/user/request_upload_file"

        // 手动构建 JSON 字符串，确保字段顺序与图片上传完全一致
        // 字段顺序：type → storage → filename → size → sha1 → mimeType → kss → block_infos
        let dataString = """
        {"type":"note_img","storage":{"filename":"\(fileName)","size":\(fileSize),"sha1":"\(sha1)","mimeType":"\(
            mimeType
        )","kss":{"block_infos":[{"blob":{},"size":\(fileSize),"md5":"\(md5)","sha1":"\(sha1)"}]}}}
        """

        let dataEncoded = encodeURIComponent(dataString)
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "data=\(dataEncoded)&serviceToken=\(serviceTokenEncoded)"

        let postHeaders = getPostHeaders()

        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: "data=\(dataString.prefix(200))...&serviceToken=..."
        )

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            let responseString = String(data: data, encoding: .utf8)

            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "POST",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MiNoteError.invalidResponse
        }

        guard let code = json["code"] as? Int, code == 0,
              let dataDict = json["data"] as? [String: Any]
        else {
            let description = (json["description"] as? String) ?? "未知错误"
            throw MiNoteError.invalidResponse
        }

        return dataDict
    }

    /// 提交语音文件上传（第三步）
    private func commitAudioUpload(uploadId: String, fileSize: Int, sha1: String, fileMeta: String, commitMeta: String) async throws -> String {
        let urlString = "\(baseURL)/file/v2/user/commit"

        // 手动构建 JSON 字符串，确保字段顺序正确
        let commitDataString = """
        {"storage":{"uploadId":"\(uploadId)","size":\(fileSize),"sha1":"\(sha1)","kss":{"file_meta":"\(fileMeta)","commit_metas":[{"commit_meta":"\(
            commitMeta
        )"}]}}}
        """

        let commitEncoded = encodeURIComponent(commitDataString)
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "commit=\(commitEncoded)&serviceToken=\(serviceTokenEncoded)"

        let postHeaders = getPostHeaders()

        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: "commit=\(commitDataString.prefix(200))...&serviceToken=..."
        )

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            let responseString = String(data: data, encoding: .utf8)

            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "POST",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MiNoteError.invalidResponse
        }

        guard let code = json["code"] as? Int, code == 0,
              let dataDict = json["data"] as? [String: Any],
              let fileId = dataDict["fileId"] as? String
        else {
            let description = (json["description"] as? String) ?? "未知错误"
            throw MiNoteError.invalidResponse
        }

        return fileId
    }

    /// 请求图片上传（第一步）
    private func requestImageUpload(fileName: String, fileSize: Int, sha1: String, md5: String, mimeType: String) async throws -> [String: Any] {
        let urlString = "\(baseURL)/file/v2/user/request_upload_file"

        // 构建 data 参数
        let dataDict: [String: Any] = [
            "type": "note_img",
            "storage": [
                "filename": fileName,
                "size": fileSize,
                "sha1": sha1,
                "mimeType": mimeType,
                "kss": [
                    "block_infos": [
                        [
                            "blob": [:] as [String: Any],
                            "size": fileSize,
                            "md5": md5,
                            "sha1": sha1,
                        ],
                    ],
                ],
            ],
        ]

        guard let dataJson = try? JSONSerialization.data(withJSONObject: dataDict, options: [.sortedKeys]),
              let dataString = String(data: dataJson, encoding: .utf8)
        else {
            throw MiNoteError.invalidResponse
        }

        let dataEncoded = encodeURIComponent(dataString)
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "data=\(dataEncoded)&serviceToken=\(serviceTokenEncoded)"

        let postHeaders = getPostHeaders()

        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: "data=\(dataString.prefix(200))...&serviceToken=..."
        )

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            let responseString = String(data: data, encoding: .utf8)

            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "POST",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MiNoteError.invalidResponse
        }

        guard let code = json["code"] as? Int, code == 0,
              let dataDict = json["data"] as? [String: Any]
        else {
            throw MiNoteError.invalidResponse
        }

        return dataDict
    }

    /// 获取图片上传URL（第二步）
    private func getImageUploadURL(fileId: String, type: String) async throws -> [String: Any] {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let urlString = "\(baseURL)/file/full/v2?ts=\(ts)&type=\(type)&fileid=\(encodeURIComponent(fileId))"

        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            let responseString = String(data: data, encoding: .utf8)

            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "GET",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MiNoteError.invalidResponse
        }

        guard let code = json["code"] as? Int, code == 0,
              let dataDict = json["data"] as? [String: Any]
        else {
            throw MiNoteError.invalidResponse
        }

        return dataDict
    }

    /// 上传文件块到KSS（第二步）
    /// - Returns: commit_meta，用于后续提交上传
    private func uploadFileChunk(fileData: Data, nodeUrl: String, fileMeta: String, blockMeta: String, chunkPos: Int) async throws -> String {
        // 构建上传URL：{nodeUrl}/upload_block_chunk?chunk_pos={chunkPos}&&file_meta={fileMeta}&block_meta={blockMeta}
        var urlString = "\(nodeUrl)/upload_block_chunk"
        urlString += "?chunk_pos=\(chunkPos)"
        urlString += "&&file_meta=\(encodeURIComponent(fileMeta))"
        urlString += "&block_meta=\(encodeURIComponent(blockMeta))"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: ["Content-Type": "application/octet-stream"],
            body: "[文件数据: \(fileData.count) 字节]"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileData.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = fileData

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            let responseString = String(data: data, encoding: .utf8) ?? ""

            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "POST",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            // 尝试从响应中解析 commit_meta
            // 响应可能是 JSON 格式，包含 commit_meta 字段
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let commitMeta = json["commit_meta"] as? String
            {
                return commitMeta
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataDict = json["data"] as? [String: Any],
                      let commitMeta = dataDict["commit_meta"] as? String
            {
                return commitMeta
            } else {
                // 如果响应中没有 commit_meta，使用 blockMeta 作为 fallback
                // 或者可能需要从其他地方获取
                return blockMeta
            }
        }

        // 如果无法解析响应，使用 blockMeta 作为 fallback
        return blockMeta
    }

    /// 提交图片上传（第三步）
    private func commitImageUpload(uploadId: String, fileSize: Int, sha1: String, fileMeta: String, commitMeta: String) async throws -> String {
        let urlString = "\(baseURL)/file/v2/user/commit"

        // 构建 commit 数据
        let commitData: [String: Any] = [
            "storage": [
                "uploadId": uploadId,
                "size": fileSize,
                "sha1": sha1,
                "kss": [
                    "file_meta": fileMeta,
                    "commit_metas": [
                        [
                            "commit_meta": commitMeta,
                        ],
                    ],
                ],
            ],
        ]

        guard let commitJson = try? JSONSerialization.data(withJSONObject: commitData, options: [.sortedKeys]),
              let commitString = String(data: commitJson, encoding: .utf8)
        else {
            throw MiNoteError.invalidResponse
        }

        let commitEncoded = encodeURIComponent(commitString)
        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "commit=\(commitEncoded)&serviceToken=\(serviceTokenEncoded)"

        let postHeaders = getPostHeaders()

        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: "commit=\(commitString.prefix(200))...&serviceToken=..."
        )

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            let responseString = String(data: data, encoding: .utf8)

            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "POST",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MiNoteError.invalidResponse
        }

        guard let code = json["code"] as? Int, code == 0,
              let dataDict = json["data"] as? [String: Any],
              let fileId = dataDict["fileId"] as? String
        else {
            throw MiNoteError.invalidResponse
        }

        return fileId
    }

    /// 上传文件到小米服务器（旧方法，保留兼容性）
    /// - Parameters:
    ///   - fileData: 文件数据
    ///   - fileName: 文件名
    ///   - mimeType: MIME 类型（如 "image/jpeg", "image/png", "application/pdf" 等）
    /// - Returns: 包含文件ID的响应字典
    func uploadFile(fileData: Data, fileName: String, mimeType: String) async throws -> [String: Any] {
        // 构建 multipart/form-data 请求体
        let boundary = "----WebKitFormBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()

        // 添加文件数据
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let urlString = "\(baseURL)/file/upload"

        // 记录请求（不记录文件数据，只记录元信息）
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: getHeaders(),
            body: "[文件数据: \(fileData.count) 字节, 类型: \(mimeType)]"
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                // 记录响应
                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "POST",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                // 检查401未授权错误
                // 处理401未授权错误
                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }

                // 检查其他错误状态码
                guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                    let errorMessage = responseString ?? "未知错误"
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 检查响应是否成功
            if let code = json["code"] as? Int, code != 0 {
                let message = json["message"] as? String ?? "上传失败"
                throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
            }

            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }

    /// 从文件URL上传文件
    /// - Parameter fileURL: 文件URL
    /// - Returns: 包含文件ID的响应字典
    func uploadFile(from fileURL: URL) async throws -> [String: Any] {
        guard fileURL.isFileURL else {
            throw MiNoteError.networkError(URLError(.badURL))
        }

        // 读取文件数据
        let fileData = try Data(contentsOf: fileURL)

        // 获取文件名
        let fileName = fileURL.lastPathComponent

        // 根据文件扩展名推断 MIME 类型
        let fileExtension = (fileURL.pathExtension as NSString).lowercased
        let mimeType = mimeTypeForExtension(fileExtension)

        return try await uploadFile(fileData: fileData, fileName: fileName, mimeType: mimeType)
    }

    /// 根据文件扩展名获取MIME类型
    private func mimeTypeForExtension(_ ext: String) -> String {
        let mimeTypes: [String: String] = [
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "webp": "image/webp",
            "pdf": "application/pdf",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ppt": "application/vnd.ms-powerpoint",
            "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "txt": "text/plain",
            "md": "text/markdown",
            "zip": "application/zip",
            "rar": "application/x-rar-compressed",
            "mp3": "audio/mpeg",
            "mp4": "video/mp4",
            "mov": "video/quicktime",
        ]

        return mimeTypes[ext] ?? "application/octet-stream"
    }

    /// 下载文件
    /// - Parameter fileId: 文件ID
    /// - Returns: 文件数据
    func downloadFile(fileId: String, type: String = "note_img") async throws -> Data {
        var urlComponents = URLComponents(string: "\(baseURL)/file/full")
        urlComponents?.queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "fileid", value: fileId),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/file/full", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        // 记录请求
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        guard let url = urlComponents?.url else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                // 记录响应（不记录文件数据）
                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "GET",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: "[文件数据: \(data.count) 字节]",
                    error: nil
                )

                if httpResponse.statusCode == 401 {
                    let responseBody = String(data: data, encoding: .utf8) ?? ""
                    try handle401Error(responseBody: responseBody, urlString: urlString)
                }

                guard httpResponse.statusCode == 200 else {
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }

            return data
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    /// 获取笔记历史记录列表
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - timestamp: 时间戳（毫秒），可选，默认为当前时间
    /// - Returns: 包含历史记录列表的响应字典
    func fetchNoteHistoryVersions(noteId: String, timestamp: Int? = nil) async throws -> [String: Any] {
        let ts = timestamp ?? Int(Date().timeIntervalSince1970 * 1000)

        var urlComponents = URLComponents(string: "\(baseURL)/note/full/history/times")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(ts)"),
            URLQueryItem(name: "id", value: noteId),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/full/history/times", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        // 记录请求
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        guard let url = urlComponents?.url else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let responseString = String(data: data, encoding: .utf8)

            // 记录响应
            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "GET",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "获取笔记历史记录失败"
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
            }

            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }
}

// MARK: - Error Types

enum MiNoteError: Error {
    case cookieExpired
    case notAuthenticated
    case networkError(Error)
    case invalidResponse
}

// MARK: - 历史记录相关方法

extension MiNoteService {
    /// 获取笔记历史记录列表
    ///
    /// - Parameter noteId: 笔记ID
    /// - Returns: 包含历史记录列表的响应字典，其中 data.tvList 是版本数组
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func getNoteHistoryTimes(noteId: String) async throws -> [String: Any] {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        var urlComponents = URLComponents(string: "\(baseURL)/note/full/history/times")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(ts)"),
            URLQueryItem(name: "id", value: noteId),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/full/history/times", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "GET",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }

                if httpResponse.statusCode != 200 {
                    let errorMessage = responseString ?? "未知错误"
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }

            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    /// 获取笔记历史记录内容
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - version: 版本号（时间戳）
    /// - Returns: 包含历史记录笔记数据的响应字典，格式与普通笔记相同
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func getNoteHistory(noteId: String, version: Int64) async throws -> [String: Any] {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        var urlComponents = URLComponents(string: "\(baseURL)/note/full/history")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(ts)"),
            URLQueryItem(name: "id", value: noteId),
            URLQueryItem(name: "version", value: "\(version)"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/full/history", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "GET",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }

                if httpResponse.statusCode != 200 {
                    let errorMessage = responseString ?? "未知错误"
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }

            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    /// 恢复笔记历史记录
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - version: 要恢复的版本号（时间戳）
    /// - Returns: API响应字典，包含恢复后的笔记信息
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func restoreNoteHistory(noteId: String, version: Int64) async throws -> [String: Any] {
        let urlString = "\(baseURL)/note/note/\(noteId)/history"

        let serviceTokenEncoded = encodeURIComponent(serviceToken)
        let body = "id=\(noteId)&version=\(version)&serviceToken=\(serviceTokenEncoded)"

        let postHeaders = getPostHeaders()
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "POST",
            headers: postHeaders,
            body: body
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = postHeaders
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "POST",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }

                if httpResponse.statusCode != 200 {
                    let errorMessage = responseString ?? "未知错误"
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }

            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }
}

extension MiNoteError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cookieExpired:
            "Cookie已过期，请重新登录"
        case .notAuthenticated:
            "未登录，请先登录小米账号"
        case let .networkError(error):
            "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            "服务器返回无效响应"
        }
    }
}

// MARK: - 用户信息和状态检查相关方法

extension MiNoteService {
    /// 获取用户信息（用户名和头像）
    ///
    /// 从小米云服务获取当前登录用户的基本信息
    ///
    /// - Returns: 用户信息字典，包含 nickname 和 icon
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchUserProfile() async throws -> [String: Any] {
        // 构建URL参数
        var urlComponents = URLComponents(string: "\(baseURL)/status/lite/profile")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/status/lite/profile", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        // 记录请求
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let responseString = String(data: data, encoding: .utf8)

            // 记录响应
            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "GET",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            // 处理401未授权错误
            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "获取用户信息失败"
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
            }

            // 返回 data 字段中的用户信息
            if let data = json["data"] as? [String: Any] {
                return data
            } else {
                // 如果没有 data 字段，返回整个响应
                return json
            }
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    /// 检查服务状态
    ///
    /// 这是一个通用的健康检查 API，用于验证：
    /// - 服务器是否可访问
    /// - 认证是否有效
    /// - 连接是否正常
    ///
    /// 通常在以下场景调用：
    /// - 登录后验证连接
    /// - 同步前检查服务可用性
    /// - 定期心跳检测
    ///
    /// - Returns: 检查结果字典，包含 result、code、description 等
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func checkServiceStatus() async throws -> [String: Any] {
        // 构建URL参数
        var urlComponents = URLComponents(string: "\(baseURL)/common/check")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/common/check", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        // 记录请求
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let responseString = String(data: data, encoding: .utf8)

            // 记录响应
            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "GET",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            // 处理401未授权错误
            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "服务检查失败"
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
            }

            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    /// 获取回收站笔记列表
    ///
    /// 从服务器获取已删除的笔记列表
    ///
    /// - Parameters:
    ///   - limit: 每页返回的记录数，默认 200
    ///   - ts: 时间戳（可选，如果不提供则使用当前时间）
    /// - Returns: 包含 entries、folders、lastPage、expireInterval、syncTag 的字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    ///
    /// **注意**：`_dc` 参数与 `ts` 参数相同，都是时间戳，用于缓存控制
    func fetchDeletedNotes(limit: Int = 200, ts: Int64? = nil) async throws -> [String: Any] {
        let timestamp = ts ?? Int64(Date().timeIntervalSince1970 * 1000)

        // 构建URL参数
        var urlComponents = URLComponents(string: "\(baseURL)/note/deleted/page")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(timestamp)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "_dc", value: "\(timestamp)"), // _dc 与 ts 相同，用于缓存控制
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/deleted/page", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        // 记录请求
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let responseString = String(data: data, encoding: .utf8)

            // 记录响应
            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "GET",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )

            // 处理401未授权错误
            if httpResponse.statusCode == 401 {
                try handle401Error(responseBody: responseString ?? "", urlString: urlString)
            }

            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "获取回收站笔记失败"
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
            }

            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    // MARK: - 网页版增量同步API

    /// 执行增量同步（网页版API）
    ///
    /// 使用网页版的 `/note/sync/full/` API 进行增量同步
    /// 这个API比 `/note/full/page` 更高效，专门为增量同步设计
    ///
    /// 注意：第一次使用轻量级同步之前（即没有syncTag时），应该先使用一次完整同步来从响应中获取syncTag
    ///
    /// - Parameters:
    ///   - syncTag: 同步标签，用于增量同步。空字符串表示获取第一页
    ///   - inactiveTime: 用户不活跃时间（秒），用于优化同步频率
    /// - Returns: 包含笔记和文件夹列表的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func syncFull(syncTag: String = "", inactiveTime: Int = 10) async throws -> [String: Any] {
        // 构建data参数：{"note_view":{"syncTag":"..."}}
        // 当syncTag为空时，data参数应为{"note_view":{}}（空对象）
        var dataDict: [String: Any] = ["note_view": [:]]
        if !syncTag.isEmpty {
            dataDict["note_view"] = ["syncTag": syncTag]
        }

        guard let dataJson = try? JSONSerialization.data(withJSONObject: dataDict, options: []),
              let dataString = String(data: dataJson, encoding: .utf8)
        else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/sync/full/", method: "GET", error: URLError(.cannotParseResponse))
            throw URLError(.cannotParseResponse)
        }

        // 使用 encodeURIComponent 对 data 参数进行编码（模拟 JavaScript 的 encodeURIComponent）
        let dataEncoded = encodeURIComponent(dataString)
        let ts = Int(Date().timeIntervalSince1970 * 1000)

        // 手动构建 URL 字符串，避免 URLComponents 的双重编码
        // 格式：https://i.mi.com/note/sync/full/?ts=...&data=...&inactiveTime=...
        let urlString = "\(baseURL)/note/sync/full/?ts=\(ts)&data=\(dataEncoded)&inactiveTime=\(inactiveTime)"

        // 记录请求
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                // 记录响应
                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "GET",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                // 检查401未授权错误
                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }
            }

            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    // MARK: - 语音文件下载

    /// 音频下载信息（包含 URL 和解密密钥）
    struct AudioDownloadInfo {
        let url: URL
        let secureKey: String?
    }

    /// 获取语音文件下载 URL 和解密密钥
    ///
    /// 使用 `/file/full/v2` API 获取语音文件的下载 URL。
    /// 该 API 返回 KSS 格式的响应，包含分块下载 URL 和解密密钥。
    ///
    /// - Parameter fileId: 语音文件 ID（如 `1315204657.jgHyouv563iSF_XCE4jhAg`）
    /// - Returns: 下载信息（URL 和解密密钥）
    /// - Throws: MiNoteError（未认证、网络错误、响应无效等）
    func getAudioDownloadInfo(fileId: String) async throws -> AudioDownloadInfo {
        guard isAuthenticated() else {
            throw MiNoteError.notAuthenticated
        }

        let ts = Int(Date().timeIntervalSince1970 * 1000)
        // 使用 note_img 类型（与上传时相同）
        let urlString = "\(baseURL)/file/full/v2?ts=\(ts)&type=note_img&fileid=\(encodeURIComponent(fileId))"

        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: getHeaders(),
            body: nil
        )

        guard let url = URL(string: urlString) else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = getHeaders()
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseString = String(data: data, encoding: .utf8)

                NetworkLogger.shared.logResponse(
                    url: urlString,
                    method: "GET",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: responseString,
                    error: nil
                )

                // 处理 401 未授权错误
                if httpResponse.statusCode == 401 {
                    try handle401Error(responseBody: responseString ?? "", urlString: urlString)
                }

                guard httpResponse.statusCode == 200 else {
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }

            // 解析响应
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MiNoteError.invalidResponse
            }

            // 检查响应码
            guard let code = json["code"] as? Int, code == 0 else {
                let description = (json["description"] as? String) ?? "未知错误"
                throw MiNoteError.invalidResponse
            }

            // 提取下载 URL
            // 响应格式可能是两种：
            // 1. 简单格式：{"code": 0, "data": {"url": "https://..."}}
            // 2. KSS 格式：{"code": 0, "data": {"kss": {"blocks": [{"urls": ["http://..."]}], "secure_key": "..."}}}

            guard let dataDict = json["data"] as? [String: Any] else {
                throw MiNoteError.invalidResponse
            }

            // 尝试简单格式
            if let downloadURLString = dataDict["url"] as? String,
               let downloadURL = URL(string: downloadURLString)
            {
                return AudioDownloadInfo(url: downloadURL, secureKey: nil)
            }

            // 尝试 KSS 格式
            if let kss = dataDict["kss"] as? [String: Any],
               let blocks = kss["blocks"] as? [[String: Any]],
               let firstBlock = blocks.first,
               let urls = firstBlock["urls"] as? [String],
               let firstURLString = urls.first
            {
                // 将 http:// 转换为 https://，避免 ATS 安全策略阻止
                let secureURLString = firstURLString.hasPrefix("http://")
                    ? firstURLString.replacingOccurrences(of: "http://", with: "https://")
                    : firstURLString

                // 提取解密密钥
                let secureKey = kss["secure_key"] as? String
                if let key = secureKey {
                }

                if let downloadURL = URL(string: secureURLString) {
                    return AudioDownloadInfo(url: downloadURL, secureKey: secureKey)
                }
            }

            throw MiNoteError.invalidResponse
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }

    /// 获取语音文件下载 URL（兼容旧接口）
    ///
    /// - Parameter fileId: 语音文件 ID
    /// - Returns: 下载 URL
    /// - Throws: MiNoteError
    public func getAudioDownloadURL(fileId: String) async throws -> URL {
        let info = try await getAudioDownloadInfo(fileId: fileId)
        return info.url
    }

    /// 下载语音文件
    ///
    /// 下载指定 fileId 的语音文件数据。
    /// 该方法会先获取下载 URL 和解密密钥，然后下载实际的音频数据，
    /// 最后使用密钥解密数据。
    ///
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - progressHandler: 下载进度回调（可选），参数为已下载字节数和总字节数
    /// - Returns: 解密后的音频文件数据
    /// - Throws: MiNoteError（未认证、网络错误、下载失败等）
    public func downloadAudio(fileId: String, progressHandler: ((Int64, Int64) -> Void)? = nil) async throws -> Data {
        guard isAuthenticated() else {
            throw MiNoteError.notAuthenticated
        }


        // 第一步：获取下载 URL 和解密密钥
        let downloadInfo = try await getAudioDownloadInfo(fileId: fileId)

        // 第二步：下载音频数据

        var request = URLRequest(url: downloadInfo.url)
        request.httpMethod = "GET"
        // 下载请求不需要认证头，因为 URL 已经包含了认证信息

        NetworkLogger.shared.logRequest(
            url: downloadInfo.url.absoluteString,
            method: "GET",
            headers: nil,
            body: nil
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                NetworkLogger.shared.logResponse(
                    url: downloadInfo.url.absoluteString,
                    method: "GET",
                    statusCode: httpResponse.statusCode,
                    headers: httpResponse.allHeaderFields as? [String: String],
                    response: "[音频数据: \(data.count) 字节]",
                    error: nil
                )

                guard httpResponse.statusCode == 200 else {
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }

            // 验证数据
            guard !data.isEmpty else {
                throw MiNoteError.invalidResponse
            }


            // 第三步：解密数据（如果有密钥）
            var audioData = data
            if let secureKey = downloadInfo.secureKey, !secureKey.isEmpty {
                audioData = AudioDecryptService.shared.decrypt(data: data, secureKey: secureKey)
            } else {
            }

            // 验证下载的音频数据
            let format = AudioConverterService.shared.getAudioFormat(audioData)

            // 使用 ffprobe 检查下载的音频
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("downloaded_audio_check.mp3")
            try? audioData.write(to: tempURL)
            let probeResult = AudioConverterService.shared.probeAudioFileDetailed(tempURL)
            try? FileManager.default.removeItem(at: tempURL)

            // 调用进度回调（下载完成）
            progressHandler?(Int64(audioData.count), Int64(audioData.count))

            return audioData
        } catch {
            NetworkLogger.shared.logError(url: downloadInfo.url.absoluteString, method: "GET", error: error)
            throw error
        }
    }

    /// 下载语音文件并缓存
    ///
    /// 下载语音文件并自动缓存到本地。如果文件已缓存，直接返回缓存路径。
    ///
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - mimeType: MIME 类型（默认 "audio/mpeg"）
    ///   - progressHandler: 下载进度回调（可选）
    /// - Returns: 本地缓存文件 URL
    /// - Throws: MiNoteError（未认证、网络错误、缓存失败等）
    public func downloadAndCacheAudio(
        fileId: String,
        mimeType: String = "audio/mpeg",
        progressHandler: ((Int64, Int64) -> Void)? = nil
    ) async throws -> URL {
        // 检查缓存
        if let cachedURL = AudioCacheService.shared.getCachedFile(for: fileId) {
            return cachedURL
        }

        // 下载文件
        let audioData = try await downloadAudio(fileId: fileId, progressHandler: progressHandler)

        // 缓存文件
        let cachedURL = try AudioCacheService.shared.cacheFile(data: audioData, fileId: fileId, mimeType: mimeType)

        return cachedURL
    }
}
