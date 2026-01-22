//
//  BaseViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  ViewModel 基类 - 提供通用的 ViewModel 功能
//

import Foundation
import Combine

/// ViewModel 基类
///
/// 提供所有 ViewModel 的通用功能，包括：
/// - Combine 订阅管理
/// - 生命周期管理
/// - 绑定设置
@MainActor
class BaseViewModel: ObservableObject {
    // MARK: - Properties

    /// Combine 订阅集合
    var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    init() {
        setupBindings()
    }

    // deinit 会自动清理 cancellables，不需要手动调用 removeAll()

    // MARK: - Setup

    /// 设置绑定
    ///
    /// 子类重写此方法来设置 Combine 绑定和订阅
    /// 在 init() 中自动调用
    func setupBindings() {
        // 子类实现
    }

    // MARK: - Helpers

    /// 添加订阅到集合
    /// - Parameter cancellable: 要添加的订阅
    func addCancellable(_ cancellable: AnyCancellable) {
        cancellables.insert(cancellable)
    }

    /// 存储订阅
    /// - Parameter cancellable: 要存储的订阅
    /// - Returns: 订阅本身（用于链式调用）
    @discardableResult
    func store(_ cancellable: AnyCancellable) -> AnyCancellable {
        cancellables.insert(cancellable)
        return cancellable
    }
}
