//
//  NetworkClient.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  网络客户端基础类 - 提供HTTP请求功能
//

import Foundation

/// HTTP 方法
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// 网络客户端
///
/// 提供基础的 HTTP 请求功能，包括：
/// - GET/POST/PUT/DELETE 请求
/// - JSON 编解码
/// - 错误处理
class NetworkClient {
    // MARK: - Properties

    private let baseURL: String
    private let session: URLSession

    // MARK: - Initialization

    init(baseURL: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Public Methods

    /// 发送请求
    /// - Parameters:
    ///   - path: API 路径
    ///   - method: HTTP 方法
    ///   - parameters: 请求参数
    ///   - headers: 请求头
    /// - Returns: 解码后的响应对象
    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // 设置请求头
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 设置请求体
        if let parameters = parameters {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        }

        // 发送请求
        let (data, response) = try await session.data(for: request)

        // 检查响应
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }

        // 解码响应
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Network Error

enum NetworkError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
}
