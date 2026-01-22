//
//  MockNetworkMonitor.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  Mock 网络监控 - 用于测试
//

import Foundation
import Combine
@testable import MiNoteMac

/// Mock 网络监控
///
/// 用于测试的网络监控实现，可以模拟各种网络状态
class MockNetworkMonitor: NetworkMonitorProtocol {
    // MARK: - Mock 数据

    private let isConnectedSubject = CurrentValueSubject<Bool, Never>(true)
    private let connectionTypeSubject = CurrentValueSubject<ConnectionType, Never>(.wifi)
    private let isExpensiveSubject = CurrentValueSubject<Bool, Never>(false)

    var mockError: Error?

    // MARK: - 调用计数

    var startMonitoringCallCount = 0
    var stopMonitoringCallCount = 0
    var getCurrentConnectionStatusCallCount = 0
    var getCurrentConnectionTypeCallCount = 0

    // MARK: - NetworkMonitorProtocol - 网络状态

    var isConnected: AnyPublisher<Bool, Never> {
        isConnectedSubject.eraseToAnyPublisher()
    }

    var connectionType: AnyPublisher<ConnectionType, Never> {
        connectionTypeSubject.eraseToAnyPublisher()
    }

    var isExpensive: AnyPublisher<Bool, Never> {
        isExpensiveSubject.eraseToAnyPublisher()
    }

    // MARK: - NetworkMonitorProtocol - 监控操作

    func startMonitoring() {
        startMonitoringCallCount += 1
        // 模拟开始监控
    }

    func stopMonitoring() {
        stopMonitoringCallCount += 1
        // 模拟停止监控
    }

    func getCurrentConnectionStatus() -> Bool {
        getCurrentConnectionStatusCallCount += 1
        return isConnectedSubject.value
    }

    func getCurrentConnectionType() -> ConnectionType {
        getCurrentConnectionTypeCallCount += 1
        return connectionTypeSubject.value
    }

    // MARK: - Helper Methods

    /// 设置网络连接状态
    func setConnected(_ connected: Bool) {
        isConnectedSubject.send(connected)
    }

    /// 设置网络连接类型
    func setConnectionType(_ type: ConnectionType) {
        connectionTypeSubject.send(type)

        // 自动设置是否为昂贵网络
        switch type {
        case .cellular:
            isExpensiveSubject.send(true)
        default:
            isExpensiveSubject.send(false)
        }
    }

    /// 设置是否为昂贵网络
    func setExpensive(_ expensive: Bool) {
        isExpensiveSubject.send(expensive)
    }

    /// 模拟网络断开
    func simulateDisconnect() {
        isConnectedSubject.send(false)
        connectionTypeSubject.send(.none)
    }

    /// 模拟网络连接
    func simulateConnect(type: ConnectionType = .wifi) {
        isConnectedSubject.send(true)
        setConnectionType(type)
    }

    /// 重置所有状态
    func reset() {
        isConnectedSubject.send(true)
        connectionTypeSubject.send(.wifi)
        isExpensiveSubject.send(false)
        mockError = nil
        resetCallCounts()
    }

    /// 重置调用计数
    func resetCallCounts() {
        startMonitoringCallCount = 0
        stopMonitoringCallCount = 0
        getCurrentConnectionStatusCallCount = 0
        getCurrentConnectionTypeCallCount = 0
    }
}
