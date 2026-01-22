//
//  NetworkClient.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  网络客户端 - 包装现有 MiNoteService 的网络功能
//

import Foundation

/// 网络客户端实现
///
/// 这是一个适配器，将现有的 MiNoteService 包装成符合 NetworkClientProtocol 的实现
/// 在重构过渡期使用，最终应该实现独立的网络层
final class NetworkClient: NetworkClientProtocol, @unchecked Sendable {
    
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
        // 注意：这是一个简化的实现
        // 在实际使用中，应该调用 MiNoteService 的相应方法
        // 或者实现完整的网络请求逻辑
        
        // 暂时抛出未实现错误
        // 在后续步骤中，我们会将服务实现改为使用现有的 MiNoteService
        throw NetworkError.notAuthenticated
    }
}

// MARK: - Convenience Methods

extension NetworkClient {
    /// 发送 GET 请求
    func get<T: Decodable>(
        _ path: String,
        headers: [String: String]? = nil
    ) async throws -> T {
        return try await request(path, method: .get, parameters: nil, headers: headers)
    }
    
    /// 发送 POST 请求
    func post<T: Decodable>(
        _ path: String,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        return try await request(path, method: .post, parameters: parameters, headers: headers)
    }
    
    /// 发送 PUT 请求
    func put<T: Decodable>(
        _ path: String,
        parameters: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        return try await request(path, method: .put, parameters: parameters, headers: headers)
    }
    
    /// 发送 DELETE 请求
    func delete<T: Decodable>(
        _ path: String,
        headers: [String: String]? = nil
    ) async throws -> T {
        return try await request(path, method: .delete, parameters: nil, headers: headers)
    }
}
