//
//  ToolbarItemFactory.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/5.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
import AppKit
import SwiftUI
import Combine
import os

/// 工具栏项工厂
/// 负责创建和管理所有工具栏项
public class ToolbarItemFactory {
    private let logger = Logger(subsystem: "com.minote.MiNoteMac", category: "ToolbarItemFactory")
    
    /// 视图模型引用
    private weak var viewModel: NotesViewModel?
    
    /// 初始化工厂
    /// - Parameter viewModel: 笔记视图模型
    public init(viewModel: NotesViewModel?) {
        self.viewModel = viewModel
    }
    
    /// 创建工具栏项
    /// - Parameters:
    ///   - identifier: 工具栏项标识符
    ///   - target: 动作目标对象
    /// - Returns: 配置好的工具栏项
    public func createToolbarItem(for identifier: NSToolbarItem.Identifier, target: AnyObject?) -> NSToolbarItem? {
        switch identifier {
        // MARK: - 文件操作
        case .newNote:
            return createNewNoteToolbarItem(target: target)
        case .newFolder:
            return createNewFolderToolbarItem(target: target)
            
        // MARK: - 格式操作
        case .bold:
            return createBoldToolbarItem(target: target)
        case .italic:
            return createItalicToolbarItem(target: target)
        case .underline:
            return createUnderlineToolbarItem(target: target)
        case .strikethrough:
            return createStrikethroughToolbarItem(target: target)
        case .code:
            return createCodeToolbarItem(target: target)
        case .link:
            return createLinkToolbarItem(target: target)
        case .formatMenu:
            return createFormatMenuToolbarItem(target: target)
        case .undo:
            return createUndoToolbarItem(target: target)
        case .redo:
            return createRedoToolbarItem(target: target)
        case .checkbox:
            return createCheckboxToolbarItem(target: target)
        case .horizontalRule:
            return createHorizontalRuleToolbarItem(target: target)
        case .attachment:
            return createAttachmentToolbarItem(target: target)
        case .increaseIndent:
            return createIncreaseIndentToolbarItem(target: target)
        case .decreaseIndent:
            return createDecreaseIndentToolbarItem(target: target)
            
        // MARK: - 搜索
        case .search:
            return createSearchToolbarItem(target: target)
            
        // MARK: - 同步和状态
        case .sync:
            return createSyncToolbarItem(target: target)
        case .onlineStatus:
            return createOnlineStatusToolbarItem(target: target)
            
        // MARK: - 视图控制
        case .toggleSidebar:
            return createToggleSidebarToolbarItem(target: target)
        case .share:
            return createShareToolbarItem(target: target)
        case .toggleStar:
            return createToggleStarToolbarItem(target: target)
        case .delete:
            return createDeleteToolbarItem(target: target)
            
        // MARK: - 其他功能
        case .history:
            return createHistoryToolbarItem(target: target)
        case .trash:
            return createTrashToolbarItem(target: target)
        case .cookieRefresh:
            return createCookieRefreshToolbarItem(target: target)
        case .offlineOperations:
            return createOfflineOperationsToolbarItem(target: target)
        case .noteOperations:
            return createNoteOperationsToolbarItem(target: target)
        case .lockPrivateNotes:
            return createLockPrivateNotesToolbarItem(target: target)
        case .settings:
            return createSettingsToolbarItem(target: target)
        case .login:
            return createLoginToolbarItem(target: target)
        case .restore:
            return createRestoreToolbarItem(target: target)
            
        // MARK: - 跟踪分隔符
        case .sidebarTrackingSeparator:
            return createSidebarTrackingSeparatorToolbarItem(target: target)
        case .timelineTrackingSeparator:
            return createTimelineTrackingSeparatorToolbarItem(target: target)
            
        // MARK: - 系统标识符
        default:
            // 处理系统标识符
            if identifier == .flexibleSpace {
                return NSToolbarItem(itemIdentifier: .flexibleSpace)
            } else if identifier == .space {
                return NSToolbarItem(itemIdentifier: .space)
            } else if identifier == .separator {
                return NSToolbarItem(itemIdentifier: .separator)
            }
            
            logger.warning("未知的工具栏项标识符: \(identifier.rawValue)")
            return nil
        }
    }
    
    // MARK: - 工具栏项创建方法
    
    private func createNewNoteToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .newNote,
            title: "新建笔记",
            image: NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil),
            action: #selector(MainWindowController.createNewNote(_:)),
            toolTip: "新建笔记"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .newNote)
    }
    
    private func createNewFolderToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .newFolder,
            title: "新建文件夹",
            image: NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil),
            action: #selector(MainWindowController.createNewFolder(_:)),
            toolTip: "新建文件夹"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .newFolder)
    }
    
    private func createBoldToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .bold,
            title: "粗体",
            image: NSImage(systemSymbolName: "bold", accessibilityDescription: nil),
            action: #selector(MainWindowController.toggleBold(_:)),
            toolTip: "粗体"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .bold)
    }
    
    private func createItalicToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .italic,
            title: "斜体",
            image: NSImage(systemSymbolName: "italic", accessibilityDescription: nil),
            action: #selector(MainWindowController.toggleItalic(_:)),
            toolTip: "斜体"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .italic)
    }
    
    private func createUnderlineToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .underline,
            title: "下划线",
            image: NSImage(systemSymbolName: "underline", accessibilityDescription: nil),
            action: #selector(MainWindowController.toggleUnderline(_:)),
            toolTip: "下划线"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .underline)
    }
    
    private func createStrikethroughToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .strikethrough,
            title: "删除线",
            image: NSImage(systemSymbolName: "strikethrough", accessibilityDescription: nil),
            action: #selector(MainWindowController.toggleStrikethrough(_:)),
            toolTip: "删除线"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .strikethrough)
    }
    
    private func createCodeToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .code,
            title: "代码",
            image: NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil),
            action: #selector(MainWindowController.toggleCode(_:)),
            toolTip: "代码"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .code)
    }
    
    private func createLinkToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .link,
            title: "链接",
            image: NSImage(systemSymbolName: "link", accessibilityDescription: nil),
            action: #selector(MainWindowController.insertLink(_:)),
            toolTip: "链接"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .link)
    }
    
    private func createFormatMenuToolbarItem(target: AnyObject?) -> NSToolbarItem {
        // 创建自定义工具栏项，使用popover显示格式菜单
        let toolbarItem = MiNoteToolbarItem(itemIdentifier: .formatMenu)
        toolbarItem.autovalidates = true
        
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.action = #selector(MainWindowController.showFormatMenu(_:))
        button.target = target
        
        toolbarItem.view = button
        toolbarItem.toolTip = "格式"
        toolbarItem.label = "格式"
        
        return toolbarItem
    }
    
    private func createUndoToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .undo,
            title: "撤回",
            image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil),
            action: #selector(MainWindowController.undo(_:)),
            toolTip: "撤回"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .undo)
    }
    
    private func createRedoToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .redo,
            title: "重做",
            image: NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: nil),
            action: #selector(MainWindowController.redo(_:)),
            toolTip: "重做"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .redo)
    }
    
    private func createCheckboxToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .checkbox,
            title: "待办",
            image: NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: nil),
            action: #selector(MainWindowController.toggleCheckbox(_:)),
            toolTip: "待办"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .checkbox)
    }
    
    private func createHorizontalRuleToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .horizontalRule,
            title: "分割线",
            image: NSImage(systemSymbolName: "minus", accessibilityDescription: nil),
            action: #selector(MainWindowController.insertHorizontalRule(_:)),
            toolTip: "分割线"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .horizontalRule)
    }
    
    private func createAttachmentToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .attachment,
            title: "附件",
            image: NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil),
            action: #selector(MainWindowController.insertAttachment(_:)),
            toolTip: "附件"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .attachment)
    }
    
    private func createIncreaseIndentToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .increaseIndent,
            title: "增加缩进",
            image: NSImage(systemSymbolName: "increase.indent", accessibilityDescription: nil),
            action: #selector(MainWindowController.increaseIndent(_:)),
            toolTip: "增加缩进"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .increaseIndent)
    }
    
    private func createDecreaseIndentToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .decreaseIndent,
            title: "减少缩进",
            image: NSImage(systemSymbolName: "decrease.indent", accessibilityDescription: nil),
            action: #selector(MainWindowController.decreaseIndent(_:)),
            toolTip: "减少缩进"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .decreaseIndent)
    }
    
    private func createSearchToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let toolbarItem = NSSearchToolbarItem(itemIdentifier: .search)
        toolbarItem.toolTip = "搜索"
        toolbarItem.label = "搜索"
        return toolbarItem
    }
    
    private func createSyncToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .sync,
            title: "同步",
            image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil),
            action: #selector(MainWindowController.performSync(_:)),
            toolTip: "同步"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .sync)
    }
    
    private func createOnlineStatusToolbarItem(target: AnyObject?) -> NSToolbarItem {
        // 使用NSMenuToolbarItem创建带菜单的工具栏项
        let toolbarItem = NSMenuToolbarItem(itemIdentifier: .onlineStatus)
        toolbarItem.toolTip = "在线状态"
        toolbarItem.label = "状态"
        
        // 设置网络图标
        toolbarItem.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
        
        // 设置显示指示器（下拉箭头）
        toolbarItem.showsIndicator = true
        
        // 创建菜单
        let menu = NSMenu()
        menu.delegate = target as? NSMenuDelegate
        
        // 第一项：在线状态指示（带颜色和大圆点）
        let statusItem = NSMenuItem()
        // 创建初始的富文本标题
        let initialAttributedString = NSMutableAttributedString()
        
        // 添加大圆点（灰色，表示加载中）
        let dotAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor.gray,
            .baselineOffset: 0
        ]
        initialAttributedString.append(NSAttributedString(string: "• ", attributes: dotAttributes))
        
        // 添加状态文本（使用相同的颜色）
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.gray
        ]
        initialAttributedString.append(NSAttributedString(string: "加载中...", attributes: textAttributes))
        
        statusItem.attributedTitle = initialAttributedString
        statusItem.isEnabled = false
        statusItem.tag = 100
        menu.addItem(statusItem)

        // 离线操作状态（显示待处理操作数量）
        let offlineOperationsStatusItem = NSMenuItem()
        offlineOperationsStatusItem.title = "离线操作：0个待处理"
        offlineOperationsStatusItem.isEnabled = false
        offlineOperationsStatusItem.tag = 200
        menu.addItem(offlineOperationsStatusItem)
        
        menu.addItem(NSMenuItem.separator())

        // 刷新Cookie
        let refreshCookieItem = NSMenuItem()
        refreshCookieItem.title = "刷新Cookie"
        refreshCookieItem.action = #selector(MainWindowController.showCookieRefresh(_:))
        refreshCookieItem.target = target
        menu.addItem(refreshCookieItem)
        
        menu.addItem(NSMenuItem.separator())
        // 完整同步
        let fullSyncItem = NSMenuItem()
        fullSyncItem.title = "完整同步"
        fullSyncItem.action = #selector(MainWindowController.performSync(_:))
        fullSyncItem.target = target
        menu.addItem(fullSyncItem)
        
        // 增量同步
        let incrementalSyncItem = NSMenuItem()
        incrementalSyncItem.title = "增量同步"
        incrementalSyncItem.action = #selector(MainWindowController.performIncrementalSync(_:))
        incrementalSyncItem.target = target
        menu.addItem(incrementalSyncItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 处理离线操作
        let processOfflineOperationsItem = NSMenuItem()
        processOfflineOperationsItem.title = "处理离线操作"
        processOfflineOperationsItem.action = #selector(MainWindowController.processOfflineOperations(_:))
        processOfflineOperationsItem.target = target
        menu.addItem(processOfflineOperationsItem)
        
        // 查看离线操作进度
        let showOfflineOperationsProgressItem = NSMenuItem()
        showOfflineOperationsProgressItem.title = "查看离线操作进度"
        showOfflineOperationsProgressItem.action = #selector(MainWindowController.showOfflineOperationsProgress(_:))
        showOfflineOperationsProgressItem.target = target
        menu.addItem(showOfflineOperationsProgressItem)
        
        // 重试失败的操作
        let retryFailedOperationsItem = NSMenuItem()
        retryFailedOperationsItem.title = "重试失败的操作"
        retryFailedOperationsItem.action = #selector(MainWindowController.retryFailedOperations(_:))
        retryFailedOperationsItem.target = target
        menu.addItem(retryFailedOperationsItem)
        
        // 设置菜单
        toolbarItem.menu = menu
        
        // 同时设置menuFormRepresentation以确保兼容性
        let menuItem = NSMenuItem()
        menuItem.title = "在线状态"
        menuItem.submenu = menu
        toolbarItem.menuFormRepresentation = menuItem
        
        return toolbarItem
    }
    
    private func createToggleSidebarToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .toggleSidebar,
            title: "隐藏/显示侧边栏",
            image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil),
            action: #selector(MainWindowController.toggleSidebar(_:)),
            toolTip: "隐藏/显示侧边栏"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .toggleSidebar)
    }
    
    private func createShareToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .share,
            title: "分享",
            image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil),
            action: #selector(MainWindowController.shareNote(_:)),
            toolTip: "分享"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .share)
    }
    
    private func createToggleStarToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .toggleStar,
            title: "置顶",
            image: NSImage(systemSymbolName: "star", accessibilityDescription: nil),
            action: #selector(MainWindowController.toggleStarNote(_:)),
            toolTip: "置顶"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .toggleStar)
    }
    
    private func createDeleteToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .delete,
            title: "删除",
            image: NSImage(systemSymbolName: "trash", accessibilityDescription: nil),
            action: #selector(MainWindowController.deleteNote(_:)),
            toolTip: "删除"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .delete)
    }
    
    private func createHistoryToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .history,
            title: "历史记录",
            image: NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil),
            action: #selector(MainWindowController.showHistory(_:)),
            toolTip: "历史记录"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .history)
    }
    
    private func createTrashToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .trash,
            title: "回收站",
            image: NSImage(systemSymbolName: "trash", accessibilityDescription: nil),
            action: #selector(MainWindowController.showTrash(_:)),
            toolTip: "回收站"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .trash)
    }
    
    private func createCookieRefreshToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .cookieRefresh,
            title: "刷新Cookie",
            image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil),
            action: #selector(MainWindowController.showCookieRefresh(_:)),
            toolTip: "刷新Cookie"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .cookieRefresh)
    }
    
    private func createOfflineOperationsToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .offlineOperations,
            title: "离线操作",
            image: NSImage(systemSymbolName: "arrow.clockwise.circle", accessibilityDescription: nil),
            action: #selector(MainWindowController.showOfflineOperations(_:)),
            toolTip: "离线操作"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .offlineOperations)
    }
    
    private func createNoteOperationsToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .noteOperations,
            title: "笔记操作",
            image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil),
            action: #selector(MainWindowController.showNoteOperationsMenu(_:)),
            toolTip: "笔记操作"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .noteOperations)
    }
    
    private func createLockPrivateNotesToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .lockPrivateNotes,
            title: "锁定私密笔记",
            image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil),
            action: #selector(MainWindowController.lockPrivateNotes(_:)),
            toolTip: "锁定私密笔记"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .lockPrivateNotes)
    }
    
    private func createSettingsToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .settings,
            title: "设置",
            image: NSImage(systemSymbolName: "gear", accessibilityDescription: nil),
            action: #selector(MainWindowController.showSettings(_:)),
            toolTip: "设置"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .settings)
    }
    
    private func createLoginToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .login,
            title: "登录",
            image: NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil),
            action: #selector(MainWindowController.showLogin(_:)),
            toolTip: "登录"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .login)
    }
    
    private func createRestoreToolbarItem(target: AnyObject?) -> NSToolbarItem {
        let item = BaseToolbarItem(
            identifier: .restore,
            title: "恢复",
            image: NSImage(systemSymbolName: "arrow.uturn.backward.circle", accessibilityDescription: nil),
            action: #selector(MainWindowController.restoreNote(_:)),
            toolTip: "恢复"
        )
        return item.createToolbarItem(target: target) ?? NSToolbarItem(itemIdentifier: .restore)
    }
    
    private func createSidebarTrackingSeparatorToolbarItem(target: AnyObject?) -> NSToolbarItem? {
        // 侧边栏跟踪分隔符 - 连接到分割视图的第一个分隔符
        // 注意：这个方法需要访问窗口控制器，这里返回nil，由调用者处理
        return nil
    }
    
    private func createTimelineTrackingSeparatorToolbarItem(target: AnyObject?) -> NSToolbarItem? {
        // 时间线跟踪分隔符 - 连接到分割视图的第二个分隔符
        // 注意：这个方法需要访问窗口控制器，这里返回nil，由调用者处理
        return nil
    }
}

#endif
