//
//  NetworkClient.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  网络客户端 - 符合 NetworkClientProtocol 的实现
//

import Foundation

/// 网络客户端实现
///
/// 符合 NetworkClientProtocol 的网络客户端实现
struct NetworkClient: NetworkClientProtocol, Sendable {

    // MARK: - Properties

    /// 基础 URL（暂时未使用，保留用于未来实现）
    private let baseURL: String

    // MARK: - Initialization

    init(baseURL: String = "https://i.mi.com/note") {
        self.baseURL = baseURL
    }

    // MARK: - NetworkClientProtocol

    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        // 构建完整的URL
        let baseURL = "https://minote.com"
        guard var urlComponents = URLComponents(string: baseURL + path) else {
            throw NetworkError.notAuthenticated
        }

        // 添加查询参数
        if let parameters {
            urlComponents.queryItems = parameters.map { key, value in
                URLQueryItem(name: key, value: "\(value)")
            }
        }

        guard let url = urlComponents.url else {
            throw NetworkError.notAuthenticated
        }

        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // 添加默认头部
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        // 添加自定义头部
        if let headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // 执行请求
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NetworkError.notAuthenticated
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.notAuthenticated
        }

        // 检查HTTP状态码
        switch httpResponse.statusCode {
        case 200 ... 299:
            // 解码响应数据
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw NetworkError.notAuthenticated
            }
        case 401:
            throw NetworkError.notAuthenticated
        case 404:
            throw NetworkError.notAuthenticated
        case 500 ... 599:
            throw NetworkError.notAuthenticated
        default:
            throw NetworkError.notAuthenticated
        }
    }
}

// MARK: - Convenience Methods

extension NetworkClient {
    /// 发送 GET 请求
    func get<T: Decodable>(
        _ path: String,
        headers: [String: String]? = nil
    ) async throws -> T {
        try await request(path, method: .get, parameters: nil, headers: headers)
    }

    /// 发送 POST 请求
    func post<T: Decodable>(
        _ path: String,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        try await request(path, method: .post, parameters: parameters, headers: headers)
    }

    /// 发送 PUT 请求
    func put<T: Decodable>(
        _ path: String,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        try await request(path, method: .put, parameters: parameters, headers: headers)
    }

    /// 发送 DELETE 请求
    func delete<T: Decodable>(
        _ path: String,
        headers: [String: String]? = nil
    ) async throws -> T {
        try await request(path, method: .delete, parameters: nil, headers: headers)
    }
}
