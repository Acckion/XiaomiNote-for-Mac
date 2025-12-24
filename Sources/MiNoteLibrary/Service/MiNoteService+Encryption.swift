import Foundation

extension MiNoteService {
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
        // 构建URL参数
        var urlComponents = URLComponents(string: "\(baseURL)/mic/keybag/v1/getEncInfo")
        urlComponents?.queryItems = [
            URLQueryItem(name: "hsid", value: "\(hsid)"),
            URLQueryItem(name: "appId", value: appId),
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
        ]
        
        guard let urlString = urlComponents?.url?.absoluteString else {
            NetworkLogger.shared.logError(url: "\(baseURL)/mic/keybag/v1/getEncInfo", method: "GET", error: URLError(.badURL))
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
                    let message = json["description"] as? String ?? json["message"] as? String ?? "获取加密信息失败"
                    print("[MiNoteService] 获取加密信息失败，code: \(code), message: \(message)")
                    throw MiNoteError.networkError(NSError(domain: "MiNoteService", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                    print("[MiNoteService] ✅ 获取加密信息成功，code: \(code)")
                }
            } else {
                // 如果没有 code 字段，但状态码是 200，也认为成功
                print("[MiNoteService] ✅ 获取加密信息成功（响应中没有 code 字段，但状态码为 200）")
            }
            
            // 返回 data 字段中的加密信息
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
}

/// 加密信息数据模型
public struct EncryptionInfo: Codable {
    /// 区域标识
    public let zone: Int?
    
    /// 应用密钥信息
    public let maxAppkey: AppKeyInfo?
    
    /// 端到端加密状态（"open" 表示启用，"close" 表示关闭）
    public let e2eeStatus: String?
    
    /// 服务器签名区域
    public let serverSignZone: Int?
    
    /// 随机数，用于加密操作
    public let nonce: String?
    
    enum CodingKeys: String, CodingKey {
        case zone
        case maxAppkey
        case e2eeStatus
        case serverSignZone
        case nonce
    }
    
    public init(zone: Int? = nil, maxAppkey: AppKeyInfo? = nil, e2eeStatus: String? = nil, serverSignZone: Int? = nil, nonce: String? = nil) {
        self.zone = zone
        self.maxAppkey = maxAppkey
        self.e2eeStatus = e2eeStatus
        self.serverSignZone = serverSignZone
        self.nonce = nonce
    }
}

/// 应用密钥信息
public struct AppKeyInfo: Codable {
    /// 应用密钥版本
    public let appKeyVersion: Int64?
    
    /// 是否设置了加密应用密钥
    public let setEncryptAppKeys: Bool?
    
    /// 加密应用密钥大小
    public let encryptAppKeysSize: Int?
    
    /// 是否设置了应用密钥版本
    public let setAppKeyVersion: Bool?
    
    enum CodingKeys: String, CodingKey {
        case appKeyVersion
        case setEncryptAppKeys
        case encryptAppKeysSize
        case setAppKeyVersion
    }
    
    public init(appKeyVersion: Int64? = nil, setEncryptAppKeys: Bool? = nil, encryptAppKeysSize: Int? = nil, setAppKeyVersion: Bool? = nil) {
        self.appKeyVersion = appKeyVersion
        self.setEncryptAppKeys = setEncryptAppKeys
        self.encryptAppKeysSize = encryptAppKeysSize
        self.setAppKeyVersion = setAppKeyVersion
    }
}

