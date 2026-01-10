//
//  Notification+FormatState.swift
//  MiNoteMac
//
//  格式状态相关的通知名称扩展
//  这些通知用于在不同组件之间同步格式状态
//
//  _Requirements: 4.1, 4.2_
//

import Foundation

// MARK: - 格式状态同步通知

public extension Notification.Name {
    
    /// 格式状态变化通知
    /// 
    /// 当格式状态发生变化时发送此通知，用于同步工具栏和菜单栏的格式显示
    /// 
    /// userInfo:
    /// - "state": FormatState - 新的格式状态
    /// 
    /// _Requirements: 4.1_
    static let formatStateDidChange = Notification.Name("FormatStateDidChange")
    
    /// 请求格式状态更新通知
    /// 
    /// 当需要强制刷新格式状态时发送此通知
    /// FormatStateManager 会响应此通知并重新获取当前格式状态
    /// 
    /// userInfo: 无
    /// 
    /// _Requirements: 4.2_
    static let requestFormatStateUpdate = Notification.Name("RequestFormatStateUpdate")
    
    // 注意：nativeEditorRequestContentSync 已在 NativeEditorView.swift 中定义
}

// MARK: - 格式状态通知辅助方法

public extension NotificationCenter {
    
    /// 发送格式状态变化通知
    /// - Parameter state: 新的格式状态
    @MainActor
    func postFormatStateDidChange(_ state: FormatState) {
        post(
            name: .formatStateDidChange,
            object: nil,
            userInfo: ["state": state]
        )
    }
    
    /// 发送请求格式状态更新通知
    @MainActor
    func postRequestFormatStateUpdate() {
        post(
            name: .requestFormatStateUpdate,
            object: nil,
            userInfo: nil
        )
    }
    
    /// 从通知中提取格式状态
    /// - Parameter notification: 通知对象
    /// - Returns: 格式状态，如果无法提取则返回 nil
    static func extractFormatState(from notification: Notification) -> FormatState? {
        return notification.userInfo?["state"] as? FormatState
    }
}
