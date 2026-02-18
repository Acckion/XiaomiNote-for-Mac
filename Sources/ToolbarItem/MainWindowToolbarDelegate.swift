//
//  MainWindowToolbarDelegate.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/5.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import Combine
    import os
    import SwiftUI

    /// 主窗口工具栏代理
    /// 负责处理主窗口的所有工具栏相关逻辑
    public class MainWindowToolbarDelegate: NSObject {

        // MARK: - 属性

        private let logger = Logger(subsystem: "com.minote.MiNoteMac", category: "MainWindowToolbarDelegate")

        /// 视图模型引用
        public weak var viewModel: NotesViewModel?

        /// 主窗口控制器引用
        public weak var windowController: MainWindowController?

        /// 工具栏可见性管理器引用
        /// 用于在工具栏项添加时设置初始可见性
        public var visibilityManager: ToolbarVisibilityManager?

        /// 当前搜索字段（用于工具栏搜索项）
        private var currentSearchField: CustomSearchField?

        // MARK: - 笔记操作菜单

        /// 笔记操作菜单（用于双轨配置）
        @MainActor
        var actionMenu: NSMenu {
            let menu = NSMenu()
            menu.addItem(withTitle: "置顶笔记", action: #selector(MainWindowController.toggleStarNote(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "添加到私密笔记", action: #selector(MainWindowController.addToPrivateNotes(_:)), keyEquivalent: "")
            menu.addItem(.separator())

            // 移到（子菜单）
            let moveNoteMenu = NSMenu()
            moveNoteMenu.title = "移到"

            // 未分类文件夹（folderId为"0"）
            let uncategorizedMenuItem = NSMenuItem(title: "未分类", action: #selector(MainWindowController.moveToUncategorized(_:)), keyEquivalent: "")
            uncategorizedMenuItem.image = NSImage(systemSymbolName: "folder.badge.questionmark", accessibilityDescription: nil)
            uncategorizedMenuItem.image?.size = NSSize(width: 16, height: 16)
            moveNoteMenu.addItem(uncategorizedMenuItem)

            // 其他可用文件夹（安全解包viewModel）
            if let viewModel {
                // 告诉编译器假设当前环境已经是 MainActor
                let availableFolders = MainActor.assumeIsolated {
                    NoteMoveHelper.getAvailableFolders(for: viewModel)
                }

                if !availableFolders.isEmpty {
                    moveNoteMenu.addItem(NSMenuItem.separator())

                    for folder in availableFolders {
                        let menuItem = NSMenuItem(title: folder.name, action: #selector(MainWindowController.moveNoteToFolder(_:)), keyEquivalent: "")
                        menuItem.representedObject = folder
                        menuItem.image = NSImage(systemSymbolName: folder.isPinned ? "pin.fill" : "folder", accessibilityDescription: nil)
                        menuItem.image?.size = NSSize(width: 16, height: 16)
                        moveNoteMenu.addItem(menuItem)
                    }
                }
            }

            let moveNoteItem = NSMenuItem()
            moveNoteItem.title = "移到"
            moveNoteItem.submenu = moveNoteMenu
            menu.addItem(moveNoteItem)

            menu.addItem(NSMenuItem.separator())

            // 在笔记中查找（等待实现）
            let findInNoteItem = NSMenuItem()
            findInNoteItem.title = "在笔记中查找（等待实现）"
            findInNoteItem.isEnabled = false
            menu.addItem(findInNoteItem)

            // 最近笔记（等待实现）
            let recentNotesItem = NSMenuItem()
            recentNotesItem.title = "最近笔记（等待实现）"
            recentNotesItem.isEnabled = false
            menu.addItem(recentNotesItem)

            menu.addItem(NSMenuItem.separator())

            // 删除笔记
            let deleteNoteItem = NSMenuItem()
            deleteNoteItem.title = "删除笔记"
            deleteNoteItem.action = #selector(MainWindowController.deleteNote(_:))
            deleteNoteItem.target = windowController
            menu.addItem(deleteNoteItem)

            // 历史记录
            let historyItem = NSMenuItem()
            historyItem.title = "历史记录"
            historyItem.action = #selector(MainWindowController.showHistory(_:))
            historyItem.target = windowController
            menu.addItem(historyItem)

            // 设置所有菜单项的目标为windowController
            for item in menu.items {
                if item.target == nil {
                    item.target = windowController
                }
                // 为子菜单项也设置目标
                if let submenu = item.submenu {
                    for subItem in submenu.items {
                        if subItem.target == nil {
                            subItem.target = windowController
                        }
                    }
                }
            }

            return menu
        }

        /// 创建笔记操作菜单的折叠表示
        @MainActor
        private func createNoteOperationsMenuFormRepresentation() -> NSMenuItem {
            let overflowItem = NSMenuItem(title: "笔记操作", action: nil, keyEquivalent: "")
            overflowItem.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "笔记操作")
            overflowItem.image?.size = NSSize(width: 16, height: 16)
            overflowItem.submenu = actionMenu
            return overflowItem
        }

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
        private func buildToolbarButton(
            _ identifier: NSToolbarItem.Identifier,
            _ title: String,
            _ image: NSImage,
            _ selector: String
        ) -> NSToolbarItem {
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
                    // 更新离线操作状态（使用新的 UnifiedOperationQueue）
                    let unifiedQueue = UnifiedOperationQueue.shared
                    let stats = unifiedQueue.getStatistics()
                    let pendingCount = stats["pending"] ?? 0
                    let failedCount = stats["failed"] ?? 0

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

            if let viewModel {
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
                .baselineOffset: -1, // 从-2改为0，让圆点居中
            ]
            attributedString.append(NSAttributedString(string: "• ", attributes: dotAttributes))

            // 添加状态文本（使用相同的颜色）
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: statusColor, // 使用与圆点相同的颜色
            ]
            attributedString.append(NSAttributedString(string: statusText, attributes: textAttributes))

            return attributedString
        }
    }

    // MARK: - NSToolbarDelegate

    extension MainWindowToolbarDelegate: NSToolbarDelegate {

        public func toolbar(
            _: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar _: Bool
        ) -> NSToolbarItem? {

            switch itemIdentifier {

            case .newNote:
                return buildToolbarButton(
                    .newNote,
                    "新建笔记",
                    NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)!,
                    "createNewNote:"
                )

            case .newFolder:
                return buildToolbarButton(
                    .newFolder,
                    "新建文件夹",
                    NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)!,
                    "createNewFolder:"
                )

            case .bold:
                return buildToolbarButton(.bold, "粗体", NSImage(systemSymbolName: "bold", accessibilityDescription: nil)!, "toggleBold:")

            case .italic:
                return buildToolbarButton(.italic, "斜体", NSImage(systemSymbolName: "italic", accessibilityDescription: nil)!, "toggleItalic:")

            case .underline:
                return buildToolbarButton(
                    .underline,
                    "下划线",
                    NSImage(systemSymbolName: "underline", accessibilityDescription: nil)!,
                    "toggleUnderline:"
                )

            case .strikethrough:
                return buildToolbarButton(
                    .strikethrough,
                    "删除线",
                    NSImage(systemSymbolName: "strikethrough", accessibilityDescription: nil)!,
                    "toggleStrikethrough:"
                )

            case .code:
                return buildToolbarButton(
                    .code,
                    "代码",
                    NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)!,
                    "toggleCode:"
                )

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
                return buildToolbarButton(
                    .checkbox,
                    "待办",
                    NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: nil)!,
                    "toggleCheckbox:"
                )

            case .horizontalRule:
                return buildToolbarButton(
                    .horizontalRule,
                    "分割线",
                    NSImage(systemSymbolName: "minus", accessibilityDescription: nil)!,
                    "insertHorizontalRule:"
                )

            case .attachment:
                return buildToolbarButton(
                    .attachment,
                    "附件",
                    NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)!,
                    "insertAttachment:"
                )

            case .audioRecording:
                return buildToolbarButton(
                    .audioRecording,
                    "录音",
                    NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)!,
                    "insertAudioRecording:"
                )

            case .increaseIndent:
                return buildToolbarButton(
                    .increaseIndent,
                    "增加缩进",
                    NSImage(systemSymbolName: "increase.indent", accessibilityDescription: nil)!,
                    "increaseIndent:"
                )

            case .decreaseIndent:
                return buildToolbarButton(
                    .decreaseIndent,
                    "减少缩进",
                    NSImage(systemSymbolName: "decrease.indent", accessibilityDescription: nil)!,
                    "decreaseIndent:"
                )

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

            case .viewOptions:
                // 创建视图选项工具栏按钮（使用原生 NSMenu）
                // _Requirements: 1.1, 1.2_
                let toolbarItem = NSMenuToolbarItem(itemIdentifier: .viewOptions)
                toolbarItem.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "视图选项")
                toolbarItem.toolTip = "视图选项"
                toolbarItem.label = "视图选项"
                toolbarItem.showsIndicator = true

                // 创建视图选项菜单
                let menu = createViewOptionsMenu()
                toolbarItem.menu = menu

                // 设置菜单代理以动态更新选中状态
                menu.delegate = windowController

                // 设置 menuFormRepresentation 以确保兼容性
                let menuFormItem = NSMenuItem()
                menuFormItem.title = "视图选项"
                menuFormItem.submenu = menu
                toolbarItem.menuFormRepresentation = menuFormItem

                return toolbarItem

            case .noteOperations:
                // 创建自定义工具栏项，实现双轨配置
                let toolbarItem = MiNoteToolbarItem(itemIdentifier: .noteOperations)
                toolbarItem.autovalidates = true

                // --- 修改这里：不要使用 button，直接设置 image 和 action ---
                toolbarItem.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "笔记操作")
                toolbarItem.label = "笔记操作"
                toolbarItem.toolTip = "笔记操作"

                // 确保 action 指向弹出逻辑
                toolbarItem.target = windowController
                toolbarItem.action = #selector(MainWindowController.handleNoteOperationsClick(_:))

                // --- 折叠配置：延迟创建以避免线程问题 ---
                toolbarItem.menuFormRepresentation = createNoteOperationsMenuFormRepresentation()

                return toolbarItem

            case .toggleSidebar:
                return buildToolbarButton(
                    .toggleSidebar,
                    "隐藏/显示侧边栏",
                    NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)!,
                    "toggleSidebar:"
                )

            case .share:
                return buildToolbarButton(
                    .share,
                    "分享",
                    NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)!,
                    "shareNote:"
                )

            case .toggleStar:
                return buildToolbarButton(.toggleStar, "置顶", NSImage(systemSymbolName: "star", accessibilityDescription: nil)!, "toggleStarNote:")

            case .delete:
                return buildToolbarButton(.delete, "删除", NSImage(systemSymbolName: "trash", accessibilityDescription: nil)!, "deleteNote:")

            case .history:
                return buildToolbarButton(
                    .history,
                    "历史记录",
                    NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)!,
                    "showHistory:"
                )

            case .trash:
                return buildToolbarButton(.trash, "回收站", NSImage(systemSymbolName: "trash", accessibilityDescription: nil)!, "showTrash:")

            case .offlineOperations:
                return buildToolbarButton(
                    .offlineOperations,
                    "离线操作",
                    NSImage(systemSymbolName: "arrow.clockwise.circle", accessibilityDescription: nil)!,
                    "showOfflineOperations:"
                )

            case .lockPrivateNotes:
                return buildToolbarButton(
                    .lockPrivateNotes,
                    "锁定私密笔记",
                    NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)!,
                    "lockPrivateNotes:"
                )

            case .settings:
                return buildToolbarButton(.settings, "设置", NSImage(systemSymbolName: "gear", accessibilityDescription: nil)!, "showSettings:")

            case .login:
                return buildToolbarButton(.login, "登录", NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)!, "showLogin:")

            case .restore:
                return buildToolbarButton(
                    .restore,
                    "恢复",
                    NSImage(systemSymbolName: "arrow.uturn.backward.circle", accessibilityDescription: nil)!,
                    "restoreNote:"
                )

            case .backToGallery:
                // 返回画廊按钮 - 使用导航样式，不可自定义
                // 仅在画廊视图展开编辑笔记时显示
                let toolbarItem = NSToolbarItem(itemIdentifier: .backToGallery)
                toolbarItem.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "返回画廊")
                toolbarItem.label = "返回"
                toolbarItem.toolTip = "返回画廊视图"
                toolbarItem.action = #selector(MainWindowController.backToGallery(_:))
                toolbarItem.target = windowController
                // 设置为导航样式，不可自定义
                toolbarItem.isNavigational = true
                return toolbarItem

            case .debugMode:
                // XML 调试模式按钮
                // _Requirements: 1.1, 1.2, 5.2, 6.1_
                return buildToolbarButton(
                    .debugMode,
                    "调试模式",
                    NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)!,
                    "toggleDebugMode:"
                )

            case .sidebarTrackingSeparator:
                // 侧边栏跟踪分隔符 - 连接到分割视图的第一个分隔符
                if let window = windowController?.window,
                   let splitViewController = window.contentViewController as? NSSplitViewController
                {
                    return NSTrackingSeparatorToolbarItem(
                        identifier: .sidebarTrackingSeparator,
                        splitView: splitViewController.splitView,
                        dividerIndex: 0
                    )
                }
                return nil

            case .timelineTrackingSeparator:
                // 时间线跟踪分隔符
                // 注意：由于使用两栏布局（侧边栏 + 内容区域），只有一个分隔符
                // 如果分割视图只有一个分隔符，返回普通分隔符
                // _Requirements: 4.3, 4.4, 4.5_
                if let window = windowController?.window,
                   let splitViewController = window.contentViewController as? NSSplitViewController
                {
                    let dividerCount = splitViewController.splitView.subviews.count - 1
                    if dividerCount > 1 {
                        // 三栏布局：使用第二个分隔符
                        return NSTrackingSeparatorToolbarItem(
                            identifier: .timelineTrackingSeparator,
                            splitView: splitViewController.splitView,
                            dividerIndex: 1
                        )
                    } else {
                        // 两栏布局：返回普通分隔符
                        return NSToolbarItem(itemIdentifier: .separator)
                    }
                }
                return nil

            case .editorSpace1, .editorSpace2:
                // 编辑器区域的自定义间距项
                // 使用固定间距，在画廊视图中随编辑器项一起隐藏
                // 注意：必须设置 view 属性，否则 isHidden 不会生效
                let spaceItem = NSToolbarItem(itemIdentifier: itemIdentifier)
                spaceItem.label = ""
                spaceItem.paletteLabel = "间距"

                // 创建一个空的 NSView 作为间距
                // 这样 isHidden 属性才能正确工作
                let spaceView = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 1))
                spaceItem.view = spaceView

                // 设置为固定宽度的间距
                spaceItem.minSize = NSSize(width: 8, height: 1)
                spaceItem.maxSize = NSSize(width: 8, height: 1)
                return spaceItem

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

        public func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
            var identifiers = [
                NSToolbarItem.Identifier.toggleSidebar,
                NSToolbarItem.Identifier.sidebarTrackingSeparator,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.newNote,
                NSToolbarItem.Identifier.newFolder,
                // 编辑器项
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
                NSToolbarItem.Identifier.audioRecording,
                NSToolbarItem.Identifier.increaseIndent,
                NSToolbarItem.Identifier.decreaseIndent,
                // 编辑器区域间距（可随编辑器项一起隐藏）
                NSToolbarItem.Identifier.editorSpace1,
                NSToolbarItem.Identifier.editorSpace2,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.search,
                NSToolbarItem.Identifier.sync,
                NSToolbarItem.Identifier.onlineStatus,
                NSToolbarItem.Identifier.viewOptions,
                NSToolbarItem.Identifier.settings,
                NSToolbarItem.Identifier.login,
                NSToolbarItem.Identifier.offlineOperations,
                NSToolbarItem.Identifier.timelineTrackingSeparator,
                NSToolbarItem.Identifier.share,
                NSToolbarItem.Identifier.toggleStar,
                NSToolbarItem.Identifier.delete,
                NSToolbarItem.Identifier.restore,
                NSToolbarItem.Identifier.history,
                NSToolbarItem.Identifier.trash,
                NSToolbarItem.Identifier.noteOperations,
                NSToolbarItem.Identifier.backToGallery,
                NSToolbarItem.Identifier.debugMode,
                NSToolbarItem.Identifier.space,
                NSToolbarItem.Identifier.separator,
            ]

            // 锁图标工具栏项始终在允许的标识符列表中，但通过验证逻辑控制可见性
            identifiers.append(NSToolbarItem.Identifier.lockPrivateNotes)

            return identifiers
        }

        public func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
            var identifiers: [NSToolbarItem.Identifier] = [
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.toggleSidebar,
                NSToolbarItem.Identifier.newFolder,

                NSToolbarItem.Identifier.sidebarTrackingSeparator,

                // 返回画廊按钮（导航样式，仅在画廊视图展开编辑时显示）
                NSToolbarItem.Identifier.backToGallery,

                NSToolbarItem.Identifier.viewOptions,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.onlineStatus,

                NSToolbarItem.Identifier.timelineTrackingSeparator,

                NSToolbarItem.Identifier.newNote,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.undo,
                NSToolbarItem.Identifier.redo,
                NSToolbarItem.Identifier.editorSpace1, // 自定义间距，可随编辑器项隐藏
                NSToolbarItem.Identifier.formatMenu,
                NSToolbarItem.Identifier.checkbox,
                NSToolbarItem.Identifier.horizontalRule,
                NSToolbarItem.Identifier.attachment,
                NSToolbarItem.Identifier.audioRecording,
                NSToolbarItem.Identifier.editorSpace2, // 自定义间距，可随编辑器项隐藏
                NSToolbarItem.Identifier.increaseIndent,
                NSToolbarItem.Identifier.decreaseIndent,

                NSToolbarItem.Identifier.flexibleSpace,

                NSToolbarItem.Identifier.debugMode,
                NSToolbarItem.Identifier.share,
                NSToolbarItem.Identifier.noteOperations,
                NSToolbarItem.Identifier.search,
            ]

            // 只有在选中私密笔记文件夹且已解锁时才添加锁图标
            let isPrivateFolder = viewModel?.selectedFolder?.id == "2"
            let isUnlocked = viewModel?.isPrivateNotesUnlocked ?? false
            if isPrivateFolder, isUnlocked {
                identifiers.append(NSToolbarItem.Identifier.lockPrivateNotes)
            }

            return identifiers
        }

        public func toolbarWillAddItem(_ notification: Notification) {
            guard let item = notification.userInfo?["item"] as? NSToolbarItem else {
                return
            }

            // 设置新添加工具栏项的初始可见性
            visibilityManager?.updateItemVisibility(item)

            if item.itemIdentifier == .search, let searchItem = item as? NSSearchToolbarItem {
                // 创建自定义搜索字段
                let customSearchField = CustomSearchField(frame: searchItem.searchField.frame)
                customSearchField.delegate = windowController
                customSearchField.target = windowController
                customSearchField.action = #selector(MainWindowController.performSearch(_:))

                // 设置视图模型
                if let viewModel {
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
        @MainActor
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

        // MARK: - 视图选项菜单

        /// 创建视图选项菜单
        /// _Requirements: 1.2, 2.1, 2.2, 2.6, 3.2, 4.2_
        private func createViewOptionsMenu() -> NSMenu {
            let menu = NSMenu()

            // 排序方式子菜单
            let sortMenuItem = NSMenuItem()
            sortMenuItem.title = "排序方式"
            let sortSubmenu = NSMenu()
            sortSubmenu.delegate = windowController

            // 排序字段选项
            let editDateItem = NSMenuItem()
            editDateItem.title = "编辑时间"
            editDateItem.action = #selector(MainWindowController.setSortOrderEditDate(_:))
            editDateItem.target = windowController
            editDateItem.tag = 1
            sortSubmenu.addItem(editDateItem)

            let createDateItem = NSMenuItem()
            createDateItem.title = "创建时间"
            createDateItem.action = #selector(MainWindowController.setSortOrderCreateDate(_:))
            createDateItem.target = windowController
            createDateItem.tag = 2
            sortSubmenu.addItem(createDateItem)

            let titleItem = NSMenuItem()
            titleItem.title = "标题"
            titleItem.action = #selector(MainWindowController.setSortOrderTitle(_:))
            titleItem.target = windowController
            titleItem.tag = 3
            sortSubmenu.addItem(titleItem)

            sortSubmenu.addItem(NSMenuItem.separator())

            // 排序方向选项
            let descendingItem = NSMenuItem()
            descendingItem.title = "降序"
            descendingItem.action = #selector(MainWindowController.setSortDirectionDescending(_:))
            descendingItem.target = windowController
            descendingItem.tag = 10
            sortSubmenu.addItem(descendingItem)

            let ascendingItem = NSMenuItem()
            ascendingItem.title = "升序"
            ascendingItem.action = #selector(MainWindowController.setSortDirectionAscending(_:))
            ascendingItem.target = windowController
            ascendingItem.tag = 11
            sortSubmenu.addItem(ascendingItem)

            sortMenuItem.submenu = sortSubmenu
            menu.addItem(sortMenuItem)

            // 按日期分组子菜单
            let dateGroupingMenuItem = NSMenuItem()
            dateGroupingMenuItem.title = "按日期分组"
            let dateGroupingSubmenu = NSMenu()
            dateGroupingSubmenu.delegate = windowController

            let dateGroupingOnItem = NSMenuItem()
            dateGroupingOnItem.title = "开"
            dateGroupingOnItem.action = #selector(MainWindowController.setDateGroupingOn(_:))
            dateGroupingOnItem.target = windowController
            dateGroupingOnItem.tag = 20
            dateGroupingSubmenu.addItem(dateGroupingOnItem)

            let dateGroupingOffItem = NSMenuItem()
            dateGroupingOffItem.title = "关"
            dateGroupingOffItem.action = #selector(MainWindowController.setDateGroupingOff(_:))
            dateGroupingOffItem.target = windowController
            dateGroupingOffItem.tag = 21
            dateGroupingSubmenu.addItem(dateGroupingOffItem)

            dateGroupingMenuItem.submenu = dateGroupingSubmenu
            menu.addItem(dateGroupingMenuItem)

            menu.addItem(NSMenuItem.separator())

            // 视图模式选项
            let listViewItem = NSMenuItem()
            listViewItem.title = "列表视图"
            listViewItem.action = #selector(MainWindowController.setViewModeList(_:))
            listViewItem.target = windowController
            listViewItem.tag = 30
            menu.addItem(listViewItem)

            let galleryViewItem = NSMenuItem()
            galleryViewItem.title = "画廊视图"
            galleryViewItem.action = #selector(MainWindowController.setViewModeGallery(_:))
            galleryViewItem.target = windowController
            galleryViewItem.tag = 31
            menu.addItem(galleryViewItem)

            return menu
        }
    }

#endif
