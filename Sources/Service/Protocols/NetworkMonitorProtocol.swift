//
//  NetworkMonitorProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  网络监控协议 - 定义网络状态监控接口
//

import Foundation
import Combine

/// 网络监控协议
///
/// 定义了网络状态监控相关的操作接口，包括：
/// - 网络连接状态
/// - 网络类型检测
protocol NetworkMonitorProtocol {
    // MARK: - 网络状态

    /// 是否已连接网络
    var isConnected: AnyPublisher<Bool, Never> { get }

    /// 网络类型
    var connectionType: AnyPublisher<ConnectionType, Never> { get }

    /// 是否为昂贵网络（如移动数据）
    var isExpensive: AnyPublisher<Bool, Never> { get }

    // MARK: - 监控操作

    /// 开始监控网络状态
    func startMonitoring()

    /// 停止监控网络状态
    func stopMonitoring()

    /// 获取当前网络状态
    /// - Returns: 是否已连接
    func getCurrentConnectionStatus() -> Bool

    /// 获取当前网络类型
    /// - Returns: 网络类型
    func getCurrentConnectionType() -> ConnectionType
}

// MARK: - Supporting Types

/// 网络连接类型
enum ConnectionType {
    /// 无连接
    case none

    /// WiFi
    case wifi

    /// 以太网
    case ethernet

    /// 移动数据
    case cellular

    /// 其他
    case other
}
