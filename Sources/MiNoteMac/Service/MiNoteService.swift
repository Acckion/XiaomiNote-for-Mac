import Foundation
import CryptoKit

class MiNoteService {
    static let shared = MiNoteService()
    
    private let baseURL = "https://i.mi.com"
    private var cookie: String = ""
    private var serviceToken: String = ""
    
    // 用于通知cookie过期
    var onCookieExpired: (() -> Void)?
    
    // 记录 cookie 设置的时间，用于判断是否刚登录
    private var cookieSetTime: Date?
    // 刚登录后的保护期（秒），在此期间内的 401 不视为 cookie 过期
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
    
    /// 模拟 JavaScript 的 encodeURIComponent 函数
    /// encodeURIComponent 会编码除了字母、数字和 -_.!~*'() 之外的所有字符
    private func encodeURIComponent(_ string: String) -> String {
        // 定义不需要编码的字符集（字母、数字和 -_.!~*'()）
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
    }
    
    // MARK: - API Methods
    
    /// 删除笔记
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
                
                if httpResponse.statusCode == 401 {
                    let responseBody = responseString ?? ""
                    
                    // 更全面的认证错误判断
                    let hasLoginURL = responseBody.contains("serviceLogin") || 
                                     responseBody.contains("account.xiaomi.com") ||
                                     responseBody.contains("pass/serviceLogin")
                    let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                         responseBody.contains("未授权") ||
                                         responseBody.contains("登录") ||
                                         responseBody.contains("login") ||
                                         responseBody.contains("\"R\":401") ||
                                         responseBody.contains("\"S\":\"Err\"")
                    let isAuthError = hasLoginURL || hasAuthKeywords
                    let isInGracePeriod = checkIfInGracePeriod()
                    
                    if isInGracePeriod {
                        print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，不视为过期")
                        throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                    }
                    
                    if self.hasValidCookie() && isAuthError {
                        print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                        if hasLoginURL {
                            print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                        }
                        DispatchQueue.main.async {
                            self.onCookieExpired?()
                        }
                        throw MiNoteError.cookieExpired
                    } else if self.hasValidCookie() && !isAuthError {
                        print("[MiNoteService] 401 错误但不是明确的认证失败")
                        print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                        throw MiNoteError.networkError(URLError(.badServerResponse))
                    } else {
                        throw MiNoteError.notAuthenticated
                    }
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
    
    func fetchPage(syncTag: String = "") async throws -> [String: Any] {
        print("123")
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
                    // 检查响应内容，判断是否真的是认证失败
                    let responseBody = responseString ?? ""
                    
                    // 更全面的认证错误判断
                    // 1. 检查响应中的登录URL（小米笔记API返回的登录重定向）
                    let hasLoginURL = responseBody.contains("serviceLogin") || 
                                     responseBody.contains("account.xiaomi.com") ||
                                     responseBody.contains("pass/serviceLogin")
                    
                    // 2. 检查常见的认证错误关键词
                    let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                         responseBody.contains("未授权") ||
                                         responseBody.contains("登录") ||
                                         responseBody.contains("login") ||
                                         responseBody.contains("\"R\":401") ||
                                         responseBody.contains("\"S\":\"Err\"")
                    
                    let isAuthError = hasLoginURL || hasAuthKeywords
                    
                    // 检查是否在刚登录后的保护期内
                    let isInGracePeriod = checkIfInGracePeriod()
                    
                    if isInGracePeriod {
                        print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，可能是 cookie 尚未完全生效，不视为过期")
                        // 在保护期内，即使有 cookie 也不视为过期，可能是 cookie 还在生效中
                        throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                    }
                    
                    // 根据当前是否有有效cookie来区分：未登录 vs Cookie过期
                    if self.hasValidCookie() && isAuthError {
                        // 已经有cookie且确实是认证错误，则视为cookie过期
                        print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                        if hasLoginURL {
                            print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                        }
                    DispatchQueue.main.async {
                        self.onCookieExpired?()
                    }
                    throw MiNoteError.cookieExpired
                    } else if self.hasValidCookie() && !isAuthError {
                        // 有 cookie 但不是明确的认证错误，可能是其他原因，不视为过期
                        print("[MiNoteService] 401 错误但不是明确的认证失败，可能是其他原因")
                        print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                        throw MiNoteError.networkError(URLError(.badServerResponse))
                    } else {
                        // 没有cookie，说明尚未登录
                        print("[MiNoteService] 401 错误且没有有效cookie，需要登录")
                        throw MiNoteError.notAuthenticated
                    }
                }
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }
    
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
                    let responseBody = responseString ?? ""
                    
                    // 更全面的认证错误判断
                    let hasLoginURL = responseBody.contains("serviceLogin") || 
                                     responseBody.contains("account.xiaomi.com") ||
                                     responseBody.contains("pass/serviceLogin")
                    let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                         responseBody.contains("未授权") ||
                                         responseBody.contains("登录") ||
                                         responseBody.contains("login") ||
                                         responseBody.contains("\"R\":401") ||
                                         responseBody.contains("\"S\":\"Err\"")
                    let isAuthError = hasLoginURL || hasAuthKeywords
                    let isInGracePeriod = checkIfInGracePeriod()
                    
                    if isInGracePeriod {
                        print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，不视为过期")
                        throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                    }
                    
                    if self.hasValidCookie() && isAuthError {
                        print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                        if hasLoginURL {
                            print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                        }
                    DispatchQueue.main.async {
                        self.onCookieExpired?()
                    }
                    throw MiNoteError.cookieExpired
                    } else if self.hasValidCookie() && !isAuthError {
                        print("[MiNoteService] 401 错误但不是明确的认证失败")
                        print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                        throw MiNoteError.networkError(URLError(.badServerResponse))
                    } else {
                        throw MiNoteError.notAuthenticated
                    }
                }
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
        }
    }
    
    func createNote(title: String, content: String, folderId: String = "0") async throws -> [String: Any] {
        // 移除 content 中的 <new-format/> 前缀（上传时不需要）
        var cleanedContent = content
        if cleanedContent.hasPrefix("<new-format/>") {
            cleanedContent = String(cleanedContent.dropFirst("<new-format/>".count))
        }
        
        let entry: [String: Any] = [
            "content": cleanedContent,
            "colorId": 0,
            "folderId": folderId,
            "createDate": Int(Date().timeIntervalSince1970 * 1000),
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000)
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
                let responseBody = responseString ?? ""
                
                // 更全面的认证错误判断
                let hasLoginURL = responseBody.contains("serviceLogin") || 
                                 responseBody.contains("account.xiaomi.com") ||
                                 responseBody.contains("pass/serviceLogin")
                let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                     responseBody.contains("未授权") ||
                                     responseBody.contains("登录") ||
                                     responseBody.contains("login") ||
                                     responseBody.contains("\"R\":401") ||
                                     responseBody.contains("\"S\":\"Err\"")
                let isAuthError = hasLoginURL || hasAuthKeywords
                let isInGracePeriod = checkIfInGracePeriod()
                
                if isInGracePeriod {
                    print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，不视为过期")
                    throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                }
                
                if self.hasValidCookie() && isAuthError {
                    print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                    if hasLoginURL {
                        print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                    }
                    DispatchQueue.main.async {
                        self.onCookieExpired?()
                    }
                    throw MiNoteError.cookieExpired
                } else if self.hasValidCookie() && !isAuthError {
                    print("[MiNoteService] 401 错误但不是明确的认证失败")
                    print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                } else {
                    throw MiNoteError.notAuthenticated
                }
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
                let responseBody = responseString ?? ""
                
                // 更全面的认证错误判断
                let hasLoginURL = responseBody.contains("serviceLogin") || 
                                 responseBody.contains("account.xiaomi.com") ||
                                 responseBody.contains("pass/serviceLogin")
                let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                     responseBody.contains("未授权") ||
                                     responseBody.contains("登录") ||
                                     responseBody.contains("login") ||
                                     responseBody.contains("\"R\":401") ||
                                     responseBody.contains("\"S\":\"Err\"")
                let isAuthError = hasLoginURL || hasAuthKeywords
                let isInGracePeriod = checkIfInGracePeriod()
                
                if isInGracePeriod {
                    print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，不视为过期")
                    throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                }
                
                if self.hasValidCookie() && isAuthError {
                    print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                    if hasLoginURL {
                        print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                    }
                    DispatchQueue.main.async {
                        self.onCookieExpired?()
                    }
                    throw MiNoteError.cookieExpired
                } else if self.hasValidCookie() && !isAuthError {
                    print("[MiNoteService] 401 错误但不是明确的认证失败")
                    print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                } else {
                    throw MiNoteError.notAuthenticated
                }
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
        var urlComponents = URLComponents(string: "\(baseURL)/note/folder/\(folderId)")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
        ]
        
        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/note/folder/\(folderId)", method: "GET", error: URLError(.badURL))
            throw URLError(.badURL)
        }
        
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
            
            NetworkLogger.shared.logResponse(
                url: urlString,
                method: "GET",
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String],
                response: responseString,
                error: nil
            )
            
            if httpResponse.statusCode == 401 {
                let responseBody = responseString ?? ""
                let hasLoginURL = responseBody.contains("serviceLogin") ||
                                 responseBody.contains("account.xiaomi.com") ||
                                 responseBody.contains("pass/serviceLogin")
                let hasAuthKeywords = responseBody.contains("unauthorized") ||
                                     responseBody.contains("未授权") ||
                                     responseBody.contains("登录") ||
                                     responseBody.contains("login") ||
                                     responseBody.contains("\"R\":401") ||
                                     responseBody.contains("\"S\":\"Err\"")
                let isAuthError = hasLoginURL || hasAuthKeywords
                let isInGracePeriod = checkIfInGracePeriod()
                
                if isInGracePeriod {
                    print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，不视为过期")
                    throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                }
                
                if self.hasValidCookie() && isAuthError {
                    print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                    if hasLoginURL {
                        print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                    }
                    DispatchQueue.main.async {
                        self.onCookieExpired?()
                    }
                    throw MiNoteError.cookieExpired
                } else if self.hasValidCookie() && !isAuthError {
                    print("[MiNoteService] 401 错误但不是明确的认证失败")
                    print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                } else {
                    throw MiNoteError.notAuthenticated
                }
            }
            
            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "GET", error: error)
            throw error
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
                let responseBody = responseString ?? ""
                
                // 更全面的认证错误判断
                let hasLoginURL = responseBody.contains("serviceLogin") || 
                                 responseBody.contains("account.xiaomi.com") ||
                                 responseBody.contains("pass/serviceLogin")
                let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                     responseBody.contains("未授权") ||
                                     responseBody.contains("登录") ||
                                     responseBody.contains("login") ||
                                     responseBody.contains("\"R\":401") ||
                                     responseBody.contains("\"S\":\"Err\"")
                let isAuthError = hasLoginURL || hasAuthKeywords
                let isInGracePeriod = checkIfInGracePeriod()
                
                if isInGracePeriod {
                    print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，不视为过期")
                    throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                }
                
                if self.hasValidCookie() && isAuthError {
                    print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                    if hasLoginURL {
                        print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                    }
                    DispatchQueue.main.async {
                        self.onCookieExpired?()
                    }
                    throw MiNoteError.cookieExpired
                } else if self.hasValidCookie() && !isAuthError {
                    print("[MiNoteService] 401 错误但不是明确的认证失败")
                    print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                } else {
                    throw MiNoteError.notAuthenticated
                }
            }
            
            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "重命名文件夹失败"
                    print("[MiNoteService] 重命名文件夹失败，code: \(code), message: \(message)")
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                }
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
                let responseBody = responseString ?? ""
                
                // 更全面的认证错误判断
                let hasLoginURL = responseBody.contains("serviceLogin") || 
                                 responseBody.contains("account.xiaomi.com") ||
                                 responseBody.contains("pass/serviceLogin")
                let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                     responseBody.contains("未授权") ||
                                     responseBody.contains("登录") ||
                                     responseBody.contains("login") ||
                                     responseBody.contains("\"R\":401") ||
                                     responseBody.contains("\"S\":\"Err\"")
                let isAuthError = hasLoginURL || hasAuthKeywords
                let isInGracePeriod = checkIfInGracePeriod()
                
                if isInGracePeriod {
                    print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，不视为过期")
                    throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                }
                
                if self.hasValidCookie() && isAuthError {
                    print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                    if hasLoginURL {
                        print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                    }
                    DispatchQueue.main.async {
                        self.onCookieExpired?()
                    }
                    throw MiNoteError.cookieExpired
                } else if self.hasValidCookie() && !isAuthError {
                    print("[MiNoteService] 401 错误但不是明确的认证失败")
                    print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                    throw MiNoteError.networkError(URLError(.badServerResponse))
                } else {
                    throw MiNoteError.notAuthenticated
                }
            }
            
            guard httpResponse.statusCode == 200 else {
                throw MiNoteError.networkError(URLError(.badServerResponse))
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            // 验证响应：检查 code 字段
            if let code = json["code"] as? Int {
                if code != 0 {
                    let message = json["description"] as? String ?? json["message"] as? String ?? "删除文件夹失败"
                    print("[MiNoteService] 删除文件夹失败，code: \(code), message: \(message)")
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                }
            }
            
            return json
        } catch {
            NetworkLogger.shared.logError(url: urlString, method: "POST", error: error)
            throw error
        }
    }
    
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
                    let responseBody = responseString ?? ""
                    
                    // 更全面的认证错误判断
                    let hasLoginURL = responseBody.contains("serviceLogin") || 
                                     responseBody.contains("account.xiaomi.com") ||
                                     responseBody.contains("pass/serviceLogin")
                    let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                         responseBody.contains("未授权") ||
                                         responseBody.contains("登录") ||
                                         responseBody.contains("login") ||
                                         responseBody.contains("\"R\":401") ||
                                         responseBody.contains("\"S\":\"Err\"")
                    let isAuthError = hasLoginURL || hasAuthKeywords
                    let isInGracePeriod = checkIfInGracePeriod()
                    
                    if isInGracePeriod {
                        print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，不视为过期")
                        throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                    }
                    
                    if self.hasValidCookie() && isAuthError {
                        print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                        if hasLoginURL {
                            print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                        }
                    DispatchQueue.main.async {
                        self.onCookieExpired?()
                    }
                    throw MiNoteError.cookieExpired
                    } else if self.hasValidCookie() && !isAuthError {
                        print("[MiNoteService] 401 错误但不是明确的认证失败")
                        print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                        throw MiNoteError.networkError(URLError(.badServerResponse))
                    } else {
                        throw MiNoteError.notAuthenticated
                    }
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
    
    func refreshCookie() async throws -> Bool {
        print("开始刷新Cookie...")
        
        // 清除现有cookie
        clearCookie()
        
        // 打开登录页面获取新cookie
        // 这里我们返回false，表示需要用户手动登录
        // 在实际应用中，可以尝试自动刷新，但小米笔记可能需要用户交互
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
            folders.insert(Folder(id: "starred", name: "收藏", count: 0, isSystem: true), at: starredIndex)
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
                // 处理401错误（与之前相同的逻辑）
                let responseBody = responseString ?? ""
                let hasLoginURL = responseBody.contains("serviceLogin") || 
                                 responseBody.contains("account.xiaomi.com") ||
                                 responseBody.contains("pass/serviceLogin")
                let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                     responseBody.contains("未授权") ||
                                     responseBody.contains("登录") ||
                                     responseBody.contains("login") ||
                                     responseBody.contains("\"R\":401") ||
                                     responseBody.contains("\"S\":\"Err\"")
                let isAuthError = hasLoginURL || hasAuthKeywords
                
                if hasValidCookie() && isAuthError {
                    DispatchQueue.main.async {
                        self.onCookieExpired?()
                    }
                    throw MiNoteError.cookieExpired
                } else {
                    throw MiNoteError.notAuthenticated
                }
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
                if httpResponse.statusCode == 401 {
                    let responseBody = responseString ?? ""
                    
                    // 更全面的认证错误判断
                    let hasLoginURL = responseBody.contains("serviceLogin") || 
                                     responseBody.contains("account.xiaomi.com") ||
                                     responseBody.contains("pass/serviceLogin")
                    let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                         responseBody.contains("未授权") ||
                                         responseBody.contains("登录") ||
                                         responseBody.contains("login") ||
                                         responseBody.contains("\"R\":401") ||
                                         responseBody.contains("\"S\":\"Err\"")
                    let isAuthError = hasLoginURL || hasAuthKeywords
                    let isInGracePeriod = checkIfInGracePeriod()
                    
                    if isInGracePeriod {
                        print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，不视为过期")
                        throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                    }
                    
                    if self.hasValidCookie() && isAuthError {
                        print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                        if hasLoginURL {
                            print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                        }
                        DispatchQueue.main.async {
                            self.onCookieExpired?()
                        }
                        throw MiNoteError.cookieExpired
                    } else if self.hasValidCookie() && !isAuthError {
                        print("[MiNoteService] 401 错误但不是明确的认证失败")
                        print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                        throw MiNoteError.networkError(URLError(.badServerResponse))
                    } else {
                        throw MiNoteError.notAuthenticated
                    }
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
                    
                    // 更全面的认证错误判断
                    let hasLoginURL = responseBody.contains("serviceLogin") || 
                                     responseBody.contains("account.xiaomi.com") ||
                                     responseBody.contains("pass/serviceLogin")
                    let hasAuthKeywords = responseBody.contains("unauthorized") || 
                                         responseBody.contains("未授权") ||
                                         responseBody.contains("登录") ||
                                         responseBody.contains("login") ||
                                         responseBody.contains("\"R\":401") ||
                                         responseBody.contains("\"S\":\"Err\"")
                    let isAuthError = hasLoginURL || hasAuthKeywords
                    let isInGracePeriod = checkIfInGracePeriod()
                    
                    if isInGracePeriod {
                        print("[MiNoteService] 401 错误发生在 cookie 设置后的保护期内，不视为过期")
                        throw MiNoteError.networkError(URLError(.userAuthenticationRequired))
                    }
                    
                    if self.hasValidCookie() && isAuthError {
                        print("[MiNoteService] 检测到 cookie 过期（401 + 认证错误）")
                        if hasLoginURL {
                            print("[MiNoteService] 响应包含登录重定向URL，确认需要重新登录")
                        }
                        DispatchQueue.main.async {
                            self.onCookieExpired?()
                        }
                        throw MiNoteError.cookieExpired
                    } else if self.hasValidCookie() && !isAuthError {
                        print("[MiNoteService] 401 错误但不是明确的认证失败")
                        print("[MiNoteService] 响应体: \(responseBody.prefix(200))")
                        throw MiNoteError.networkError(URLError(.badServerResponse))
                    } else {
                        throw MiNoteError.notAuthenticated
                    }
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
