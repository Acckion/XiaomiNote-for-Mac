//
//  ToolbarIdentifiers.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
import AppKit

/// 工具栏项标识符扩展
/// 定义 MiNote 应用的所有工具栏项标识符
extension NSToolbarItem.Identifier {
    
    // MARK: - 文件操作
    
    /// 新建笔记
    static let newNote = NSToolbarItem.Identifier("newNote")
    
    /// 新建文件夹
    static let newFolder = NSToolbarItem.Identifier("newFolder")
    
    // MARK: - 格式操作
    
    /// 粗体
    static let bold = NSToolbarItem.Identifier("bold")
    
    /// 斜体
    static let italic = NSToolbarItem.Identifier("italic")
    
    /// 下划线
    static let underline = NSToolbarItem.Identifier("underline")
    
    /// 删除线
    static let strikethrough = NSToolbarItem.Identifier("strikethrough")
    
    /// 代码
    static let code = NSToolbarItem.Identifier("code")
    
    /// 链接
    static let link = NSToolbarItem.Identifier("link")
    
    /// 格式菜单
    static let formatMenu = NSToolbarItem.Identifier("formatMenu")
    
    /// 撤回
    static let undo = NSToolbarItem.Identifier("undo")
    
    /// 重做
    static let redo = NSToolbarItem.Identifier("redo")
    
    /// 勾选框（待办）
    static let checkbox = NSToolbarItem.Identifier("checkbox")
    
    /// 插入分割线
    static let horizontalRule = NSToolbarItem.Identifier("horizontalRule")
    
    /// 插入附件
    static let attachment = NSToolbarItem.Identifier("attachment")
    
    /// 增加缩进
    static let increaseIndent = NSToolbarItem.Identifier("increaseIndent")
    
    /// 减少缩进
    static let decreaseIndent = NSToolbarItem.Identifier("decreaseIndent")
    
    // MARK: - 搜索
    
    /// 搜索
    static let search = NSToolbarItem.Identifier("search")
    
    // MARK: - 同步和状态
    
    /// 同步
    static let sync = NSToolbarItem.Identifier("sync")
    
    /// 在线状态指示器
    static let onlineStatus = NSToolbarItem.Identifier("onlineStatus")
    
    // MARK: - 视图控制
    
    /// 切换侧边栏
    static let toggleSidebar = NSToolbarItem.Identifier("toggleSidebar")
    
    /// 分享
    static let share = NSToolbarItem.Identifier("share")
    
    /// 置顶/取消置顶
    static let toggleStar = NSToolbarItem.Identifier("toggleStar")
    
    /// 删除
    static let delete = NSToolbarItem.Identifier("delete")
    
    
    /// 历史记录
    static let history = NSToolbarItem.Identifier("history")
    
    /// 回收站
    static let trash = NSToolbarItem.Identifier("trash")
    
    /// Cookie刷新
    static let cookieRefresh = NSToolbarItem.Identifier("cookieRefresh")
    
    /// 离线操作处理
    static let offlineOperations = NSToolbarItem.Identifier("offlineOperations")
    
    /// 笔记操作菜单
    static let noteOperations = NSToolbarItem.Identifier("noteOperations")
    
    /// 锁定私密笔记
    static let lockPrivateNotes = NSToolbarItem.Identifier("lockPrivateNotes")
    
    /// 视图选项
    static let viewOptions = NSToolbarItem.Identifier("viewOptions")
    
    /// 返回画廊视图
    static let backToGallery = NSToolbarItem.Identifier("backToGallery")

    // MARK: - 其他功能

    /// 设置
    static let settings = NSToolbarItem.Identifier("settings")

    /// 登录
    static let login = NSToolbarItem.Identifier("login")

    /// 恢复
    static let restore = NSToolbarItem.Identifier("restore")
    
    // MARK: - 跟踪分隔符
    
    /// 侧边栏跟踪分隔符 - 连接到分割视图的第一个分隔符
    static let sidebarTrackingSeparator = NSToolbarItem.Identifier("sidebarTrackingSeparator")
    
    /// 时间线跟踪分隔符 - 连接到分割视图的第二个分隔符
    static let timelineTrackingSeparator = NSToolbarItem.Identifier("timelineTrackingSeparator")
    
    // MARK: - 系统标识符
    
    // 注意：不要重新定义系统标识符，直接使用系统提供的：
    // - .flexibleSpace
    // - .space
    // - .separator
    // 这些标识符已经由系统提供，不需要重新定义
}
#endif
