//
//  Notification+FormatState.swift
//  MiNoteMac
//
//  格式状态相关的通知名称扩展
//  这些通知用于在不同组件之间同步格式状态
//
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
    static let formatStateDidChange = Notification.Name("FormatStateDidChange")

    /// 请求格式状态更新通知
    ///
    /// 当需要强制刷新格式状态时发送此通知
    /// FormatStateManager 会响应此通知并重新获取当前格式状态
    ///
    /// userInfo: 无
    ///
    static let requestFormatStateUpdate = Notification.Name("RequestFormatStateUpdate")

    /// 音频附件点击通知
    ///
    /// 当用户点击音频附件时发送此通知，用于在音频面板中播放音频
    ///
    /// userInfo:
    /// - "fileId": String - 音频文件 ID
    ///
    static let audioAttachmentClicked = Notification.Name("AudioAttachmentClicked")

    /// 原生编辑器保存状态变化通知
    ///
    /// 当原生编辑器的保存状态发生变化时发送此通知
    /// 用于更新 UI 中的保存状态指示器
    ///
    /// userInfo:
    /// - "hasUnsavedChanges": Bool - 是否有未保存的更改
    ///
    static let nativeEditorSaveStatusDidChange = Notification.Name("NativeEditorSaveStatusDidChange")

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

    /// 发送音频附件点击通知
    /// - Parameter fileId: 音频文件 ID
    @MainActor
    func postAudioAttachmentClicked(fileId: String) {
        post(
            name: .audioAttachmentClicked,
            object: nil,
            userInfo: ["fileId": fileId]
        )
    }

    /// 从通知中提取格式状态
    /// - Parameter notification: 通知对象
    /// - Returns: 格式状态，如果无法提取则返回 nil
    static func extractFormatState(from notification: Notification) -> FormatState? {
        notification.userInfo?["state"] as? FormatState
    }

    /// 从通知中提取音频文件 ID
    /// - Parameter notification: 通知对象
    /// - Returns: 音频文件 ID，如果无法提取则返回 nil
    static func extractAudioFileId(from notification: Notification) -> String? {
        notification.userInfo?["fileId"] as? String
    }
}
