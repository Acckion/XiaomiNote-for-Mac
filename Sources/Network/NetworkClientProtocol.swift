//
//  NetworkClientProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  网络客户端协议 - 定义网络请求接口
//

import Foundation

/// HTTP 方法
public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

/// 网络客户端协议
///
/// 定义了网络请求的基本接口，用于抽象底层网络实现
protocol NetworkClientProtocol {
    /// 发送网络请求
    /// - Parameters:
    ///   - path: 请求路径
    ///   - method: HTTP 方法
    ///   - parameters: 请求参数（可选）
    ///   - headers: 请求头（可选）
    /// - Returns: 解码后的响应对象
    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod,
        parameters: [String: Any]?,
        headers: [String: String]?
    ) async throws -> T
}

/// 网络错误
public enum NetworkError: Error {
    case invalidURL
    case invalidResponse
    case decodingError(Error)
    case serverError(Int, String)
    case notAuthenticated
    case unknown(Error)
}
