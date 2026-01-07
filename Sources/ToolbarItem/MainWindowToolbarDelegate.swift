//
//  MainWindowToolbarDelegate.swift
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

/// 主窗口工具栏代理
/// 负责处理主窗口的所有工具栏相关逻辑
public class MainWindowToolbarDelegate: NSObject {
    
    // MARK: - 属性
    
    private let logger = Logger(subsystem: "com.minote.MiNoteMac", category: "MainWindowToolbarDelegate")
    
    /// 视图模型引用
    public weak var viewModel: NotesViewModel?
    
    /// 主窗口控制器引用
    public weak var windowController: MainWindowController?
    
    /// 当前搜索字段（用于工具栏搜索项）
    private var currentSearchField: CustomSearchField?
    
    /// 初始化工具栏代理
    /// - Parameters:
    ///   - viewModel: 笔记视图模型
    ///   - windowController: 主窗口控制器
    public init(viewModel: NotesViewModel?, windowController: MainWindowController?) {
        self.viewModel = viewModel
        self.windowController = windowController
        super.init()
    }
    
    // MARK: - 工具栏项构建方法
    
    /// 构建工具栏按钮
    private func buildToolbarButton(_ identifier: NSToolbarItem.Identifier, _ title: String, _ image: NSImage, _ selector: String) -> NSToolbarItem {
        let toolbarItem = MiNoteToolbarItem(itemIdentifier: identifier)
        toolbarItem.autovalidates = true
        
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.image = image
        button.imageScaling = .scaleProportionallyDown
        button.action = Selector((selector))
        button.target = windowController
        
        toolbarItem.view = button
        toolbarItem.toolTip = title
        toolbarItem.label = title
        return toolbarItem
    }
}

// MARK: - NSMenuDelegate

extension MainWindowToolbarDelegate: NSMenuDelegate {
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        logger.debug("menuNeedsUpdate被调用，菜单标题: \(menu.title)，菜单项数量: \(menu.items.count)")
        
        // 更新在线状态菜单项
        for item in menu.items {
            if item.tag == 100 { // 在线状态项
                item.attributedTitle = getOnlineStatusAttributedTitle()
            } else if item.tag == 200 { // 离线操作状态项
                // 更新离线操作状态
                let offlineQueue = OfflineOperationQueue.shared
                let pendingCount = offlineQueue.getPendingOperations().count
                let failedCount = OfflineOperationProcessor.shared.failedOperations.count
                
                if pendingCount > 0 {
                    if failedCount > 0 {
                        item.title = "离线操作：\(pendingCount)个待处理 (\(failedCount)个失败)"
                    } else {
                        item.title = "离线操作：\(pendingCount)个待处理"
                    }
                } else {
                    if failedCount > 0 {
                        item.title = "离线操作：\(failedCount)个失败"
                    } else {
                        item.title = "离线操作：无待处理"
                    }
                }
            }
        }
    }
    
    /// 获取在线状态标题（带颜色和大圆点）
    @MainActor
    private func getOnlineStatusAttributedTitle() -> NSAttributedString {
        let statusText: String
        let statusColor: NSColor
        
        if let viewModel = viewModel {
            if viewModel.isLoggedIn {
                if viewModel.isSyncing {
                    statusText = "同步中..."
                    statusColor = .systemYellow
                } else if viewModel.isCookieExpired {
                    statusText = "Cookie已过期"
                    statusColor = .systemRed
                } else {
                    statusText = "在线"
                    statusColor = .systemGreen
                }
            } else {
                statusText = "离线"
                statusColor = .systemGray
            }
        } else {
            statusText = "未知"
            statusColor = .gray
        }
        
        // 创建富文本字符串
        let attributedString = NSMutableAttributedString()
        
        // 添加大圆点（更大，调整垂直位置）
        let dotAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold), // 从16增加到20
            .foregroundColor: statusColor,
            .baselineOffset: -1 // 从-2改为0，让圆点居中
        ]
        attributedString.append(NSAttributedString(string: "• ", attributes: dotAttributes))
        
        // 添加状态文本（使用相同的颜色）
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: statusColor // 使用与圆点相同的颜色
        ]
        attributedString.append(NSAttributedString(string: statusText, attributes: textAttributes))
        
        return attributedString
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowToolbarDelegate: NSToolbarDelegate {
    
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        
        switch itemIdentifier {
            
        case .newNote:
            return buildToolbarButton(.newNote, "新建笔记", NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)!, "createNewNote:")
            
        case .newFolder:
            return buildToolbarButton(.newFolder, "新建文件夹", NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)!, "createNewFolder:")
            
        case .bold:
            return buildToolbarButton(.bold, "粗体", NSImage(systemSymbolName: "bold", accessibilityDescription: nil)!, "toggleBold:")
            
        case .italic:
            return buildToolbarButton(.italic, "斜体", NSImage(systemSymbolName: "italic", accessibilityDescription: nil)!, "toggleItalic:")
            
        case .underline:
            return buildToolbarButton(.underline, "下划线", NSImage(systemSymbolName: "underline", accessibilityDescription: nil)!, "toggleUnderline:")
            
        case .strikethrough:
            return buildToolbarButton(.strikethrough, "删除线", NSImage(systemSymbolName: "strikethrough", accessibilityDescription: nil)!, "toggleStrikethrough:")
            
        case .code:
            return buildToolbarButton(.code, "代码", NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)!, "toggleCode:")
            
        case .link:
            return buildToolbarButton(.link, "链接", NSImage(systemSymbolName: "link", accessibilityDescription: nil)!, "insertLink:")
            
        case .formatMenu:
            // 创建自定义工具栏项，使用popover显示格式菜单
            let toolbarItem = MiNoteToolbarItem(itemIdentifier: .formatMenu)
            toolbarItem.autovalidates = true
            
            let button = NSButton()
            button.bezelStyle = .texturedRounded
            button.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
            button.imageScaling = .scaleProportionallyDown
            button.action = #selector(MainWindowController.showFormatMenu(_:))
            button.target = windowController
            
            toolbarItem.view = button
            toolbarItem.toolTip = "格式"
            toolbarItem.label = "格式"
            return toolbarItem
            
        case .undo:
            return buildToolbarButton(.undo, "撤回", NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)!, "undo:")
            
        case .redo:
            return buildToolbarButton(.redo, "重做", NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: nil)!, "redo:")
            
        case .checkbox:
            return buildToolbarButton(.checkbox, "待办", NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: nil)!, "toggleCheckbox:")
            
        case .horizontalRule:
            return buildToolbarButton(.horizontalRule, "分割线", NSImage(systemSymbolName: "minus", accessibilityDescription: nil)!, "insertHorizontalRule:")
            
        case .attachment:
            return buildToolbarButton(.attachment, "附件", NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)!, "insertAttachment:")
            
        case .increaseIndent:
            return buildToolbarButton(.increaseIndent, "增加缩进", NSImage(systemSymbolName: "increase.indent", accessibilityDescription: nil)!, "increaseIndent:")
            
        case .decreaseIndent:
            return buildToolbarButton(.decreaseIndent, "减少缩进", NSImage(systemSymbolName: "decrease.indent", accessibilityDescription: nil)!, "decreaseIndent:")
            
        case .search:
            let toolbarItem = NSSearchToolbarItem(itemIdentifier: .search)
            toolbarItem.toolTip = "搜索"
            toolbarItem.label = "搜索"
            return toolbarItem
            
        case .sync:
            return buildToolbarButton(.sync, "同步", NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)!, "performSync:")
            
        case .onlineStatus:
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
            menu.delegate = self
            
            // 第一项：在线状态指示
            let statusItem = NSMenuItem()
            statusItem.title = "在线状态"
            statusItem.isEnabled = false
            statusItem.tag = 100
            menu.addItem(statusItem)

            // 离线操作状态
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
            refreshCookieItem.target = windowController
            menu.addItem(refreshCookieItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // 完整同步
            let fullSyncItem = NSMenuItem()
            fullSyncItem.title = "完整同步"
            fullSyncItem.action = #selector(MainWindowController.performSync(_:))
            fullSyncItem.target = windowController
            menu.addItem(fullSyncItem)
            
            // 增量同步
            let incrementalSyncItem = NSMenuItem()
            incrementalSyncItem.title = "增量同步"
            incrementalSyncItem.action = #selector(MainWindowController.performIncrementalSync(_:))
            incrementalSyncItem.target = windowController
            menu.addItem(incrementalSyncItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // 处理离线操作
            let processOfflineOperationsItem = NSMenuItem()
            processOfflineOperationsItem.title = "处理离线操作"
            processOfflineOperationsItem.action = #selector(MainWindowController.processOfflineOperations(_:))
            processOfflineOperationsItem.target = windowController
            menu.addItem(processOfflineOperationsItem)
            
            // 查看离线操作进度
            let showOfflineOperationsProgressItem = NSMenuItem()
            showOfflineOperationsProgressItem.title = "查看离线操作进度"
            showOfflineOperationsProgressItem.action = #selector(MainWindowController.showOfflineOperationsProgress(_:))
            showOfflineOperationsProgressItem.target = windowController
            menu.addItem(showOfflineOperationsProgressItem)
            
            // 重试失败的操作
            let retryFailedOperationsItem = NSMenuItem()
            retryFailedOperationsItem.title = "重试失败的操作"
            retryFailedOperationsItem.action = #selector(MainWindowController.retryFailedOperations(_:))
            retryFailedOperationsItem.target = windowController
            menu.addItem(retryFailedOperationsItem)
            
            // 设置菜单
            toolbarItem.menu = menu
            
            // 同时设置menuFormRepresentation以确保兼容性
            let menuItem = NSMenuItem()
            menuItem.title = "在线状态"
            menuItem.submenu = menu
            toolbarItem.menuFormRepresentation = menuItem
            
            return toolbarItem
            
        case .noteOperations:
            return buildToolbarButton(.noteOperations, "笔记操作", NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)!, "showNoteOperationsMenu:")
            
        case .toggleSidebar:
            return buildToolbarButton(.toggleSidebar, "隐藏/显示侧边栏", NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)!, "toggleSidebar:")
            
        case .share:
            return buildToolbarButton(.share, "分享", NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)!, "shareNote:")
            
        case .toggleStar:
            return buildToolbarButton(.toggleStar, "置顶", NSImage(systemSymbolName: "star", accessibilityDescription: nil)!, "toggleStarNote:")
            
        case .delete:
            return buildToolbarButton(.delete, "删除", NSImage(systemSymbolName: "trash", accessibilityDescription: nil)!, "deleteNote:")
            
        case .history:
            return buildToolbarButton(.history, "历史记录", NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)!, "showHistory:")
            
        case .trash:
            return buildToolbarButton(.trash, "回收站", NSImage(systemSymbolName: "trash", accessibilityDescription: nil)!, "showTrash:")
            
        case .cookieRefresh:
            return buildToolbarButton(.cookieRefresh, "刷新Cookie", NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)!, "showCookieRefresh:")
            
        case .offlineOperations:
            return buildToolbarButton(.offlineOperations, "离线操作", NSImage(systemSymbolName: "arrow.clockwise.circle", accessibilityDescription: nil)!, "showOfflineOperations:")
            
        case .lockPrivateNotes:
            return buildToolbarButton(.lockPrivateNotes, "锁定私密笔记", NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)!, "lockPrivateNotes:")
            
        case .settings:
            return buildToolbarButton(.settings, "设置", NSImage(systemSymbolName: "gear", accessibilityDescription: nil)!, "showSettings:")
            
        case .login:
            return buildToolbarButton(.login, "登录", NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)!, "showLogin:")
            
        case .restore:
            return buildToolbarButton(.restore, "恢复", NSImage(systemSymbolName: "arrow.uturn.backward.circle", accessibilityDescription: nil)!, "restoreNote:")
            
        case .sidebarTrackingSeparator:
            // 侧边栏跟踪分隔符 - 连接到分割视图的第一个分隔符
            if let window = windowController?.window,
               let splitViewController = window.contentViewController as? NSSplitViewController {
                return NSTrackingSeparatorToolbarItem(identifier: .sidebarTrackingSeparator, splitView: splitViewController.splitView, dividerIndex: 0)
            }
            return nil
            
        case .timelineTrackingSeparator:
            // 时间线跟踪分隔符 - 连接到分割视图的第二个分隔符
            if let window = windowController?.window,
               let splitViewController = window.contentViewController as? NSSplitViewController {
                return NSTrackingSeparatorToolbarItem(identifier: .timelineTrackingSeparator, splitView: splitViewController.splitView, dividerIndex: 1)
            }
            return nil
            
        default:
            // 处理系统标识符
            if itemIdentifier == .flexibleSpace {
                return NSToolbarItem(itemIdentifier: .flexibleSpace)
            } else if itemIdentifier == .space {
                return NSToolbarItem(itemIdentifier: .space)
            } else if itemIdentifier == .separator {
                return NSToolbarItem(itemIdentifier: .separator)
            }
        }
        
        return nil
    }
    
    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var identifiers = [
            NSToolbarItem.Identifier.toggleSidebar,
            NSToolbarItem.Identifier.sidebarTrackingSeparator,
            NSToolbarItem.Identifier.flexibleSpace,
            NSToolbarItem.Identifier.newNote,
            NSToolbarItem.Identifier.newFolder,
            NSToolbarItem.Identifier.undo,
            NSToolbarItem.Identifier.redo,
            NSToolbarItem.Identifier.bold,
            NSToolbarItem.Identifier.italic,
            NSToolbarItem.Identifier.underline,
            NSToolbarItem.Identifier.strikethrough,
            NSToolbarItem.Identifier.code,
            NSToolbarItem.Identifier.link,
            NSToolbarItem.Identifier.formatMenu,
            NSToolbarItem.Identifier.checkbox,
            NSToolbarItem.Identifier.horizontalRule,
            NSToolbarItem.Identifier.attachment,
            NSToolbarItem.Identifier.increaseIndent,
            NSToolbarItem.Identifier.decreaseIndent,
            NSToolbarItem.Identifier.flexibleSpace,
            NSToolbarItem.Identifier.search,
            NSToolbarItem.Identifier.sync,
            NSToolbarItem.Identifier.onlineStatus,
            NSToolbarItem.Identifier.settings,
            NSToolbarItem.Identifier.login,
            NSToolbarItem.Identifier.cookieRefresh,
            NSToolbarItem.Identifier.offlineOperations,
            NSToolbarItem.Identifier.timelineTrackingSeparator,
            NSToolbarItem.Identifier.share,
            NSToolbarItem.Identifier.toggleStar,
            NSToolbarItem.Identifier.delete,
            NSToolbarItem.Identifier.restore,
            NSToolbarItem.Identifier.history,
            NSToolbarItem.Identifier.trash,
            NSToolbarItem.Identifier.noteOperations,
            NSToolbarItem.Identifier.space,
            NSToolbarItem.Identifier.separator
        ]
        
        // 锁图标工具栏项始终在允许的标识符列表中，但通过验证逻辑控制可见性
        identifiers.append(NSToolbarItem.Identifier.lockPrivateNotes)
        
        return identifiers
    }
    
    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = [
            NSToolbarItem.Identifier.flexibleSpace,
            NSToolbarItem.Identifier.toggleSidebar,
            NSToolbarItem.Identifier.newFolder,

            NSToolbarItem.Identifier.sidebarTrackingSeparator,

            NSToolbarItem.Identifier.flexibleSpace,
            NSToolbarItem.Identifier.onlineStatus,

            NSToolbarItem.Identifier.timelineTrackingSeparator,

            NSToolbarItem.Identifier.newNote,
            NSToolbarItem.Identifier.flexibleSpace,
            NSToolbarItem.Identifier.undo,
            NSToolbarItem.Identifier.redo,
            NSToolbarItem.Identifier.space,
            NSToolbarItem.Identifier.formatMenu,
            NSToolbarItem.Identifier.checkbox,
            NSToolbarItem.Identifier.horizontalRule,
            NSToolbarItem.Identifier.attachment,
            NSToolbarItem.Identifier.space,
            NSToolbarItem.Identifier.increaseIndent,
            NSToolbarItem.Identifier.decreaseIndent,

            NSToolbarItem.Identifier.flexibleSpace,

            NSToolbarItem.Identifier.sync,

            NSToolbarItem.Identifier.settings,
            NSToolbarItem.Identifier.login,

            NSToolbarItem.Identifier.share,
            NSToolbarItem.Identifier.toggleStar,
            NSToolbarItem.Identifier.delete,
            NSToolbarItem.Identifier.history,
            NSToolbarItem.Identifier.trash,
            NSToolbarItem.Identifier.noteOperations,
            NSToolbarItem.Identifier.search,
        ]
        
        // 只有在选中私密笔记文件夹且已解锁时才添加锁图标
        let isPrivateFolder = viewModel?.selectedFolder?.id == "2"
        let isUnlocked = viewModel?.isPrivateNotesUnlocked ?? false
        if isPrivateFolder && isUnlocked {
            identifiers.append(NSToolbarItem.Identifier.lockPrivateNotes)
        }
        
        return identifiers
    }
    
    public func toolbarWillAddItem(_ notification: Notification) {
        guard let item = notification.userInfo?["item"] as? NSToolbarItem else {
            return
        }
        
        if item.itemIdentifier == .search, let searchItem = item as? NSSearchToolbarItem {
            // 创建自定义搜索字段
            let customSearchField = CustomSearchField(frame: searchItem.searchField.frame)
            customSearchField.delegate = windowController
            customSearchField.target = windowController
            customSearchField.action = #selector(MainWindowController.performSearch(_:))
            
            // 设置视图模型
            if let viewModel = viewModel {
                customSearchField.setViewModel(viewModel)
            }
            
            // 替换搜索项中的搜索字段
            searchItem.searchField = customSearchField
            currentSearchField = customSearchField
            
            // 为搜索框添加下拉菜单
            setupSearchFieldMenu(for: customSearchField)
            
            // 确保搜索框菜单正确显示
            customSearchField.sendsSearchStringImmediately = false
            customSearchField.sendsWholeSearchString = true
            customSearchField.maximumRecents = 10
        }
        
        if item.itemIdentifier == .share, let button = item.view as? NSButton {
            // 分享按钮应该在鼠标按下时发送动作，而不是鼠标抬起时
            button.sendAction(on: .leftMouseDown)
        }
    }
    
    public func toolbarDidRemoveItem(_ notification: Notification) {
        guard let item = notification.userInfo?["item"] as? NSToolbarItem else {
            return
        }
        
        if item.itemIdentifier == .search, let searchItem = item as? NSSearchToolbarItem {
            searchItem.searchField.delegate = nil
            searchItem.searchField.target = nil
            searchItem.searchField.action = nil
            currentSearchField = nil
        }
    }
    
    // MARK: - 搜索框菜单
    
    /// 为搜索框设置下拉菜单
    private func setupSearchFieldMenu(for searchField: NSSearchField) {
        logger.debug("设置搜索框菜单")
        
        // 设置搜索框属性以确保菜单正确工作
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = true
        
        // 移除旧的NSMenu设置
        searchField.menu = nil
        
        // 设置搜索框的点击事件处理
        searchField.target = windowController
        searchField.action = #selector(MainWindowController.performSearch(_:))
        
        // 重要：确保搜索框有正确的行为设置
        searchField.bezelStyle = .roundedBezel
        searchField.controlSize = .regular
        
        logger.debug("搜索框菜单已设置")
    }
}

#endif
