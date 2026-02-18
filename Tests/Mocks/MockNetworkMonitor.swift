//
//  MockNetworkMonitor.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  Mock 网络监控 - 用于测试
//

import Combine
import Foundation
@testable import MiNoteLibrary

/// Mock 网络监控
///
/// 用于测试的网络监控实现，可以模拟各种网络状态
final class MockNetworkMonitor: NetworkMonitorProtocol, @unchecked Sendable {
    // MARK: - Mock 数据

    private let isConnectedSubject = CurrentValueSubject<Bool, Never>(true)
    private let connectionTypeSubject = CurrentValueSubject<ConnectionType, Never>(.wifi)

    var mockError: Error?

    // MARK: - 调用计数

    var startMonitoringCallCount = 0
    var stopMonitoringCallCount = 0

    // MARK: - NetworkMonitorProtocol - 网络状态

    var isConnected: Bool {
        isConnectedSubject.value
    }

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        isConnectedSubject.eraseToAnyPublisher()
    }

    var connectionType: AnyPublisher<ConnectionType, Never> {
        connectionTypeSubject.eraseToAnyPublisher()
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

    // MARK: - Helper Methods

    /// 设置网络连接状态
    func setConnected(_ connected: Bool) {
        isConnectedSubject.send(connected)
    }

    /// 设置网络连接类型
    func setConnectionType(_ type: ConnectionType) {
        connectionTypeSubject.send(type)
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
        mockError = nil
        resetCallCounts()
    }

    /// 重置调用计数
    func resetCallCounts() {
        startMonitoringCallCount = 0
        stopMonitoringCallCount = 0
    }
}
