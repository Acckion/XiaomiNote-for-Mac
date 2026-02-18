//
//  Notification+MenuState.swift
//  MiNoteMac
//
//  菜单状态同步相关的通知名称扩展
//  这些通知用于在不同组件之间同步菜单状态
//
//  _Requirements: 14.4, 14.5, 14.6, 14.7_
//

import Foundation

// MARK: - 菜单状态同步通知

public extension Notification.Name {
    /// 笔记选中状态变化通知
    ///
    /// userInfo:
    /// - "hasSelectedNote": Bool - 是否有选中的笔记
    /// - "noteId": String? - 选中笔记的 ID（可选）
    ///
    /// _Requirements: 14.4_
    static let noteSelectionDidChange = Notification.Name("NoteSelectionDidChange")

    /// 视图模式变化通知
    ///
    /// userInfo:
    /// - "viewMode": String - 当前视图模式的 rawValue（"list" 或 "gallery"）
    ///
    /// _Requirements: 14.7_
    static let viewModeDidChange = Notification.Name("ViewModeDidChange")

    /// 编辑器焦点变化通知
    ///
    /// userInfo:
    /// - "isEditorFocused": Bool - 编辑器是否有焦点
    ///
    /// _Requirements: 14.5_
    static let editorFocusDidChange = Notification.Name("EditorFocusDidChange")

    /// 段落样式变化通知
    ///
    /// userInfo:
    /// - "paragraphStyle": String - 当前段落样式的 rawValue
    ///
    /// _Requirements: 14.6_
    static let paragraphStyleDidChange = Notification.Name("ParagraphStyleDidChange")

    /// 文件夹可见性变化通知
    ///
    /// userInfo:
    /// - "isFolderHidden": Bool - 文件夹是否隐藏
    static let folderVisibilityDidChange = Notification.Name("FolderVisibilityDidChange")

    /// 笔记数量显示变化通知
    ///
    /// userInfo:
    /// - "isNoteCountVisible": Bool - 笔记数量是否显示
    ///
    /// _Requirements: 9.3_
    static let noteCountVisibilityDidChange = Notification.Name("NoteCountVisibilityDidChange")

    /// XML 调试模式切换通知
    ///
    /// 当用户点击工具栏的调试模式按钮或使用快捷键 Cmd+Shift+D 时发送此通知
    /// NoteDetailView 监听此通知并切换调试模式
    ///
    /// _Requirements: 1.1, 1.2, 5.2, 6.1_
    static let toggleDebugMode = Notification.Name("ToggleDebugMode")
}
