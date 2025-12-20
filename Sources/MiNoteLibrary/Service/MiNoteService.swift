import Foundation
import CryptoKit

/// 小米笔记服务
/// 
/// 负责与小米笔记API的所有网络交互，包括：
/// - 认证管理（Cookie和ServiceToken）
/// - 笔记CRUD操作
/// - 文件夹管理
/// - 文件上传/下载
/// - 错误处理和重试逻辑
final class MiNoteService: @unchecked Sendable {
    static let shared = MiNoteService()
    
    // MARK: - 配置常量
    
    /// 小米笔记API基础URL
    private let baseURL = "https://i.mi.com"
    
    // MARK: - 认证状态
    
    /// Cookie字符串，用于API认证
    private var cookie: String = ""
    
    /// ServiceToken，从Cookie中提取的认证令牌
    private var serviceToken: String = ""
    
    /// Cookie过期回调，当检测到Cookie过期时调用
    var onCookieExpired: (() -> Void)?
    
    /// Cookie设置时间，用于判断是否在保护期内
    private var cookieSetTime: Date?
    
    /// Cookie保护期（秒），刚设置Cookie后的短时间内，401错误不视为过期
    /// 这是为了避免Cookie设置后立即请求时可能出现的临时认证失败
    private let cookieGracePeriod: TimeInterval = 10.0
    
    private init() {
        // 从 UserDefaults 加载 cookie
        loadCredentials()
    }
    
    private func loadCredentials() {
        if let savedCookie = UserDefaults.standard.string(forKey: "minote_cookie") {
            cookie = savedCookie
            extractServiceToken()
        }
    }
    
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
           let tokenRange = Range(match.range(at: 1), in: cookie) {
            serviceToken = String(cookie[tokenRange])
        }
    }
    
    func setCookie(_ newCookie: String) {
        cookie = newCookie
        extractServiceToken()
        saveCredentials()
        // 记录 cookie 设置时间
        cookieSetTime = Date()
        print("[MiNoteService] Cookie 已设置，时间: \(cookieSetTime?.description ?? "未知")")
    }
    
    func isAuthenticated() -> Bool {
        return !cookie.isEmpty && !serviceToken.isEmpty
    }
    
    private func getHeaders() -> [String: String] {
        return [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept-Encoding": "gzip, deflate, br",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Cookie": cookie
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
    private func handle401Error(responseBody: String, urlString: String) throws {
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
        let isInGracePeriod = checkIfInGracePeriod()
        
        // 保护期内：可能是Cookie刚设置，尚未完全生效，不视为过期
        if isInGracePeriod {
            print("[MiNoteService] 401错误发生在Cookie设置后的保护期内，不视为过期")
            throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
        }
        
        // 已有Cookie且确实是认证错误：视为Cookie过期
        if self.hasValidCookie() && isAuthError {
            print("[MiNoteService] 检测到Cookie过期（401 + 认证错误）")
            if hasLoginURL {
                print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
            }
            DispatchQueue.main.async {
                self.onCookieExpired?()
            }
            throw MiNoteError.cookieExpired
        }
        // 已有Cookie但不是明确的认证错误：可能是其他原因
        else if self.hasValidCookie() && !isAuthError {
            print("[MiNoteService] 401错误但不是明确的认证失败")
            print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
            throw MiNoteError.networkError(URLError(.badServerResponse))
        }
        // 没有Cookie：说明尚未登录
        else {
            throw MiNoteError.notAuthenticated
        }
    }
    
    // MARK: - API Methods
    
    /// 删除笔记
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
                    print("[MiNoteService] 删除笔记失败，状态码: \(httpResponse.statusCode), 响应: \(errorMessage)")
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }
    
    /// 获取笔记列表（分页）
    /// 
    /// 用于同步功能，支持增量同步（通过syncTag）
    /// 
    /// - Parameter syncTag: 同步标签，用于增量同步。空字符串表示获取第一页
    /// - Returns: 包含笔记和文件夹列表的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchPage(syncTag: String = "") async throws -> [String: Any] {
        // 正确编码URL参数
        var urlComponents = URLComponents(string: "\(baseURL)/note/full/page")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "syncTag", value: syncTag.isEmpty ? nil : syncTag),
            URLQueryItem(name: "limit", value: "200")
        ]
        
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
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }
    
    /// 获取笔记详情（完整内容）
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
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
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
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return json
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
            "mind_content": ""
        ]
        
        guard let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfoDict),
              let extraInfoString = String(data: extraInfoData, encoding: .utf8) else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/note", method: "POST", error: URLError(.cannotParseResponse))
            throw URLError(.cannotParseResponse)
        }
        
        let entry: [String: Any] = [
            "content": cleanedContent,
            "colorId": 0,
            "folderId": folderId,
            "createDate": Int(Date().timeIntervalSince1970 * 1000),
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000),
            "extraInfo": extraInfoString  // 添加 extraInfo 包含标题
        ]
        
        // 使用 JSONSerialization 的 sortedKeys 选项确保字段顺序一致
        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8) else {
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
                    print("[MiNoteService] 创建笔记失败，code: \(code), message: \(message)")
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
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        // 使用 JSONSerialization 的 sortedKeys 选项确保字段顺序一致
        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8) else {
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
                    print("[MiNoteService] 创建文件夹失败，code: \(code), message: \(message)")
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
        var foundFolder: [String: Any]? = nil
        
        // 遍历所有分页，直到找到目标文件夹或没有更多数据
        while foundFolder == nil {
            let pageResponse = try await fetchPage(syncTag: syncTag)
            
            // 解析文件夹列表
            if let data = pageResponse["data"] as? [String: Any],
               let folderEntries = data["folders"] as? [[String: Any]] {
                
                // 查找目标文件夹
                for folderEntry in folderEntries {
                    // 处理 ID（可能是 String 或 Int）
                    var entryId: String? = nil
                    if let idString = folderEntry["id"] as? String {
                        entryId = idString
                    } else if let idInt = folderEntry["id"] as? Int {
                        entryId = String(idInt)
                    }
                    
                    if entryId == folderId {
                        foundFolder = folderEntry
                        print("[MiNoteService] ✅ 找到目标文件夹: \(folderId), tag: \(folderEntry["tag"] as? String ?? "nil")")
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
                    "entry": folderEntry
                ]
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
            "type": "folder"
        ]
        
        // 使用 JSONSerialization 的 sortedKeys 选项确保字段顺序一致
        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8) else {
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
            print("[MiNoteService] 重命名文件夹响应: \(json)")
            
            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "重命名文件夹失败"
                    print("[MiNoteService] 重命名文件夹失败，code: \(code), message: \(message)")
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                    print("[MiNoteService] ✅ 重命名文件夹成功，code: \(code)")
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
                print("[MiNoteService] ✅ 重命名文件夹成功（响应中没有 code 字段，但状态码为 200）")
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
            print("[MiNoteService] 删除文件夹响应: \(json)")
            
            // 验证响应：检查 code 字段
            // 如果响应中没有 code 字段，或者 code 为 0，则认为成功
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "删除文件夹失败"
                    print("[MiNoteService] 删除文件夹失败，code: \(code), message: \(message)")
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                    print("[MiNoteService] ✅ 删除文件夹成功，code: \(code)")
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
                print("[MiNoteService] ✅ 删除文件夹成功（响应中没有 code 字段，但状态码为 200）")
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
    func updateNote(noteId: String, title: String, content: String, folderId: String = "0", existingTag: String = "", originalCreateDate: Int? = nil, imageData: [[String: Any]]? = nil) async throws -> [String: Any] {
        let createDate = originalCreateDate ?? Int(Date().timeIntervalSince1970 * 1000)
        
        // 参考正确的请求示例：extraInfo 应该是包含字段的 JSON 字符串
        let extraInfoDict: [String: Any] = [
            "note_content_type": "common",
            "web_images": "",
            "mind_content_plain_text": "",
            "title": title,
            "mind_content": ""
        ]
        
        guard let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfoDict),
              let extraInfoString = String(data: extraInfoData, encoding: .utf8) else {
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
            "version": 0
        ]
        if let imageData = imageData, !imageData.isEmpty {
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
            "extraInfo": extraInfoString
        ]
        
        // 使用 JSONSerialization 的 sortedKeys 选项确保字段顺序一致
        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8) else {
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
    
    /// 刷新Cookie
    /// 
    /// 参考 Obsidian 插件的实现：
    /// 1. 打开浏览器窗口加载 https://i.mi.com
    /// 2. 监听 https://i.mi.com/status/lite/profile?ts=* 的请求头
    /// 3. 从请求头的Cookie中提取cookie并保存
    /// 
    /// - Returns: 是否成功刷新（当前实现返回false，表示需要用户手动操作）
    func refreshCookie() async throws -> Bool {
        print("[MiNoteService] 开始刷新Cookie...")
        
        // 注意：实际的cookie刷新逻辑在 CookieRefreshView 中实现
        // 这里只负责清除旧cookie，返回false表示需要用户手动操作
        // 清除现有cookie（可选，根据Obsidian插件逻辑，可能不需要清除）
        // clearCookie()
        
        // 返回false，表示需要用户手动打开Cookie刷新窗口
        // 实际的刷新逻辑在 CookieRefreshView 中实现
        return false
    }
    
    func clearCookie() {
        cookie = ""
        serviceToken = ""
        cookieSetTime = nil
        UserDefaults.standard.removeObject(forKey: "minote_cookie")
        print("Cookie已清除")
    }
    
    func hasValidCookie() -> Bool {
        return !cookie.isEmpty && !serviceToken.isEmpty
    }
    
    /// 检查是否在 cookie 设置后的保护期内
    private func checkIfInGracePeriod() -> Bool {
        guard let setTime = cookieSetTime else {
            return false
        }
        let elapsed = Date().timeIntervalSince(setTime)
        return elapsed < cookieGracePeriod
    }
    
    // MARK: - Helper Methods
    
    func parseNotes(from response: [String: Any]) -> [Note] {
        var notes: [Note] = []
        
        // 小米笔记API返回格式: {"result":"ok","code":0,"data":{"entries":[...]}}
        // 首先尝试从data字段获取entries
        if let data = response["data"] as? [String: Any],
           let entries = data["entries"] as? [[String: Any]] {
            print("[MiNoteService] 从data字段找到 \(entries.count) 条笔记")
            for entry in entries {
                if let note = Note.fromMinoteData(entry) {
                    notes.append(note)
                }
            }
        }
        // 如果data字段没有，尝试直接从响应中获取（向后兼容）
        else if let entries = response["entries"] as? [[String: Any]] {
            print("[MiNoteService] 从响应顶层找到 \(entries.count) 条笔记")
            for entry in entries {
                if let note = Note.fromMinoteData(entry) {
                    notes.append(note)
                }
            }
        } else {
            print("[MiNoteService] 警告：未找到entries字段")
            print("[MiNoteService] 响应结构: \(response.keys)")
            if let data = response["data"] as? [String: Any] {
                print("[MiNoteService] data字段包含: \(data.keys)")
            }
        }
        
        return notes
    }
    
    func parseFolders(from response: [String: Any]) -> [Folder] {
        var folders: [Folder] = []
        
        // 小米笔记API返回格式: {"result":"ok","code":0,"data":{"folders":[...]}}
        // 参考 Obsidian 插件：文件夹在 page.data.folders 中，使用 subject 字段作为名称
        if let data = response["data"] as? [String: Any],
           let folderEntries = data["folders"] as? [[String: Any]] {
            print("[MiNoteService] 从data字段找到 \(folderEntries.count) 个文件夹条目")
            for folderEntry in folderEntries {
                // 检查类型，只处理文件夹类型（参考 Obsidian 插件）
                if let type = folderEntry["type"] as? String, type == "folder" {
                if let folder = Folder.fromMinoteData(folderEntry) {
                    folders.append(folder)
                        print("[MiNoteService] 解析文件夹: id=\(folder.id), name=\(folder.name)")
                    } else {
                        print("[MiNoteService] 警告：无法解析文件夹条目: \(folderEntry)")
                    }
                } else {
                    print("[MiNoteService] 跳过非文件夹条目，type=\(folderEntry["type"] ?? "未知")")
                }
            }
        }
        // 如果data字段没有，尝试直接从响应中获取（向后兼容）
        else if let folderEntries = response["folders"] as? [[String: Any]] {
            print("[MiNoteService] 从响应顶层找到 \(folderEntries.count) 个文件夹")
            for folderEntry in folderEntries {
                if let type = folderEntry["type"] as? String, type == "folder" {
                if let folder = Folder.fromMinoteData(folderEntry) {
                    folders.append(folder)
                    }
                }
            }
        } else {
            print("[MiNoteService] 警告：未找到folders字段")
            // 打印响应结构以便调试
            if let data = response["data"] as? [String: Any] {
                print("[MiNoteService] data字段包含: \(data.keys)")
            }
        }
        
        // 添加系统文件夹（参考 Obsidian 插件：默认文件夹 id='0', name='未分类'）
        // 但为了与UI一致，我们使用"所有笔记"和"收藏"
        var hasAllNotes = folders.contains { $0.id == "0" }
        var hasStarred = folders.contains { $0.id == "starred" }
        
        if !hasAllNotes {
            folders.insert(Folder(id: "0", name: "所有笔记", count: 0, isSystem: true), at: 0)
        }
        if !hasStarred {
            let starredIndex = hasAllNotes ? 1 : 0
            folders.insert(Folder(id: "starred", name: "置顶", count: 0, isSystem: true), at: starredIndex)
        }
        
        print("[MiNoteService] 最终文件夹列表: \(folders.map { "\($0.name)(\($0.id))" }.joined(separator: ", "))")
        
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
        
        print("[MiNoteService] 开始上传图片: \(fileName), 大小: \(fileSize) 字节, SHA1: \(sha1)")
        
        // 第一步：请求上传
        let requestUploadResponse = try await requestImageUpload(
            fileName: fileName,
            fileSize: fileSize,
            sha1: sha1,
            md5: md5,
            mimeType: mimeType
        )
        
        guard let fileId = requestUploadResponse["fileId"] as? String else {
            throw MiNoteError.invalidResponse
        }
        
        print("[MiNoteService] 获取到 fileId: \(fileId)")
        
        // 第二步：获取上传URL
        let uploadURLResponse = try await getImageUploadURL(fileId: fileId, type: "note_img")
        
        guard let kssData = uploadURLResponse["kss"] as? [String: Any],
              let blocks = kssData["blocks"] as? [[String: Any]],
              let firstBlock = blocks.first,
              let urls = firstBlock["urls"] as? [String],
              let uploadURLString = urls.first,
              let uploadURL = URL(string: uploadURLString) else {
            throw MiNoteError.invalidResponse
        }
        
        print("[MiNoteService] 获取到上传URL: \(uploadURLString)")
        
        // 第三步：实际上传文件到KSS
        try await uploadFileToKSS(fileData: imageData, uploadURL: uploadURL)
        
        print("[MiNoteService] 图片上传成功: \(fileId)")
        
        // 返回文件信息
        return [
            "fileId": fileId,
            "digest": sha1,
            "mimeType": mimeType
        ]
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
                            "sha1": sha1
                        ]
                    ]
                ]
            ]
        ]
        
        guard let dataJson = try? JSONSerialization.data(withJSONObject: dataDict, options: [.sortedKeys]),
              let dataString = String(data: dataJson, encoding: .utf8) else {
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
              let dataDict = json["data"] as? [String: Any] else {
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
              let dataDict = json["data"] as? [String: Any] else {
            throw MiNoteError.invalidResponse
        }
        
        return dataDict
    }
    
    /// 上传文件到KSS（第三步）
    private func uploadFileToKSS(fileData: Data, uploadURL: URL) async throws {
        NetworkLogger.shared.logRequest(
            url: uploadURL.absoluteString,
            method: "PUT",
            headers: [:],
            body: "[文件数据: \(fileData.count) 字节]"
        )
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("\(fileData.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = fileData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            NetworkLogger.shared.logResponse(
                url: uploadURL.absoluteString,
                method: "PUT",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: "[响应数据: \(data.count) 字节]",
                error: nil
            )
            
            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }
        }
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
                    print("[MiNoteService] 文件上传失败，状态码: \(httpResponse.statusCode), 响应: \(errorMessage)")
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                }
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            // 检查响应是否成功
            if let code = json["code"] as? Int, code != 0 {
                let message = json["message"] as? String ?? "上传失败"
                print("[MiNoteService] 文件上传失败: \(message)")
                throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
            }
            
            print("[MiNoteService] 文件上传成功")
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
            "mov": "video/quicktime"
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
            URLQueryItem(name: "fileid", value: fileId)
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
    
    /// 获取笔记历史版本列表
    /// 
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - timestamp: 时间戳（毫秒），可选，默认为当前时间
    /// - Returns: 包含历史版本列表的响应字典
    func fetchNoteHistoryVersions(noteId: String, timestamp: Int? = nil) async throws -> [String: Any] {
        let ts = timestamp ?? Int(Date().timeIntervalSince1970 * 1000)
        
        var urlComponents = URLComponents(string: "\(self.baseURL)/note/full/history/times")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(ts)"),
            URLQueryItem(name: "id", value: noteId)
        ]
        
        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(self.baseURL)/note/full/history/times", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }
        
        // 记录请求
        NetworkLogger.shared.logRequest(
            url: urlString,
            method: "GET",
            headers: self.getHeaders(),
            body: nil
        )
        
        guard let url = urlComponents?.url else {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = self.getHeaders()
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
                    let message = json["description"] as? String ?? json["message"] as? String ?? "获取笔记历史版本失败"
                    print("[MiNoteService] 获取笔记历史版本失败，code: \(code), message: \(message)")
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                    print("[MiNoteService] ✅ 获取笔记历史版本成功，code: \(code)")
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
                print("[MiNoteService] ✅ 获取笔记历史版本成功（响应中没有 code 字段，但状态码为 200）")
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

extension MiNoteError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cookieExpired:
            return "Cookie已过期，请重新登录"
        case .notAuthenticated:
            return "未登录，请先登录小米账号"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "服务器返回无效响应"
        }
    }
}
