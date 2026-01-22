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
@preconcurrency
public protocol NetworkMonitorProtocol: Sendable {
    // MARK: - 网络状态

    /// 网络类型
    var connectionType: AnyPublisher<ConnectionType, Never> { get }

    /// 是否已连接网络
    var isConnected: Bool { get }

    // MARK: - 监控操作

    /// 开始监控网络状态
    func startMonitoring()

    /// 停止监控网络状态
    func stopMonitoring()
}

// MARK: - Supporting Types

/// 网络连接类型
public enum ConnectionType {
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
