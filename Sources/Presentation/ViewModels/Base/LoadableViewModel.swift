//
//  LoadableViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  支持加载状态的 ViewModel - 提供加载和错误处理功能
//

import Foundation

/// 支持加载状态的 ViewModel
///
/// 继承自 BaseViewModel，添加了：
/// - 加载状态管理
/// - 错误处理
/// - 加载包装器方法
@MainActor
class LoadableViewModel: BaseViewModel {
    // MARK: - Loading State

    /// 是否正在加载
    @Published var isLoading = false

    /// 错误信息
    @Published var error: Error?

    /// 错误消息（用于显示）
    var errorMessage: String? {
        error?.localizedDescription
    }

    // MARK: - Helpers

    /// 在加载状态下执行操作
    ///
    /// 自动管理 isLoading 状态和错误处理
    /// - Parameter operation: 要执行的异步操作
    /// - Returns: 操作结果
    func withLoading<T>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        error = nil

        defer {
            isLoading = false
        }

        do {
            return try await operation()
        } catch {
            self.error = error
            throw error
        }
    }

    /// 在加载状态下执行操作（不抛出错误）
    ///
    /// 自动管理 isLoading 状态和错误处理，捕获错误但不抛出
    /// - Parameter operation: 要执行的异步操作
    /// - Returns: 操作结果，失败时返回 nil
    func withLoadingSafe<T>(_ operation: () async throws -> T) async -> T? {
        isLoading = true
        error = nil

        defer {
            isLoading = false
        }

        do {
            return try await operation()
        } catch {
            self.error = error
            return nil
        }
    }

    /// 清除错误
    func clearError() {
        error = nil
    }
}
