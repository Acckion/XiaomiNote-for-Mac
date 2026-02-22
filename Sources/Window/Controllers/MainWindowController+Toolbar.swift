//
//  MainWindowController+Toolbar.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import SwiftUI

    // MARK: - NSToolbarDelegate

    extension MainWindowController: NSToolbarDelegate {

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
                button.action = #selector(showFormatMenu(_:))
                button.target = self

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
                menu.delegate = self // 设置菜单代理以动态更新

                // 第一项：在线状态指示（带颜色和大圆点）
                let statusItem = NSMenuItem()
                // 创建初始的富文本标题
                let initialAttributedString = NSMutableAttributedString()

                // 添加大圆点（灰色，表示加载中）
                let dotAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 20, weight: .bold), // 与getOnlineStatusAttributedTitle保持一致
                    .foregroundColor: NSColor.gray,
                    .baselineOffset: 0, // 与getOnlineStatusAttributedTitle保持一致
                ]
                initialAttributedString.append(NSAttributedString(string: "• ", attributes: dotAttributes))

                // 添加状态文本（使用相同的颜色）
                let textAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.gray, // 使用与圆点相同的颜色
                ]
                initialAttributedString.append(NSAttributedString(string: "加载中...", attributes: textAttributes))

                statusItem.attributedTitle = initialAttributedString
                statusItem.isEnabled = false // 不可点击，仅显示状态
                statusItem.tag = 100 // 设置标签以便识别
                menu.addItem(statusItem)

                // 离线操作状态（显示待处理操作数量）
                let offlineOperationsStatusItem = NSMenuItem()
                offlineOperationsStatusItem.title = "离线操作：0个待处理"
                offlineOperationsStatusItem.isEnabled = false // 不可点击，仅显示状态
                offlineOperationsStatusItem.tag = 200 // 设置标签以便识别
                menu.addItem(offlineOperationsStatusItem)

                menu.addItem(NSMenuItem.separator())

                // 完整同步
                let fullSyncItem = NSMenuItem()
                fullSyncItem.title = "完整同步"
                fullSyncItem.action = #selector(performSync(_:))
                fullSyncItem.target = self
                menu.addItem(fullSyncItem)

                // 增量同步
                let incrementalSyncItem = NSMenuItem()
                incrementalSyncItem.title = "增量同步"
                incrementalSyncItem.action = #selector(performIncrementalSync(_:))
                incrementalSyncItem.target = self
                menu.addItem(incrementalSyncItem)

                menu.addItem(NSMenuItem.separator())

                // 处理离线操作
                let processOfflineOperationsItem = NSMenuItem()
                processOfflineOperationsItem.title = "处理离线操作"
                processOfflineOperationsItem.action = #selector(processOfflineOperations(_:))
                processOfflineOperationsItem.target = self
                menu.addItem(processOfflineOperationsItem)

                // 查看离线操作进度
                let showOfflineOperationsProgressItem = NSMenuItem()
                showOfflineOperationsProgressItem.title = "查看离线操作进度"
                showOfflineOperationsProgressItem.action = #selector(showOfflineOperationsProgress(_:))
                showOfflineOperationsProgressItem.target = self
                menu.addItem(showOfflineOperationsProgressItem)

                // 重试失败的操作
                let retryFailedOperationsItem = NSMenuItem()
                retryFailedOperationsItem.title = "重试失败的操作"
                retryFailedOperationsItem.action = #selector(retryFailedOperations(_:))
                retryFailedOperationsItem.target = self
                menu.addItem(retryFailedOperationsItem)

                // 设置菜单
                toolbarItem.menu = menu

                // 同时设置menuFormRepresentation以确保兼容性
                let menuItem = NSMenuItem()
                menuItem.title = "在线状态"
                menuItem.submenu = menu
                toolbarItem.menuFormRepresentation = menuItem

                return toolbarItem

                // 笔记操作按钮现在由MainWindowToolbarDelegate处理，不在这里实现
                return nil

            case .lockPrivateNotes:
                // 锁定私密笔记工具栏项
                return buildToolbarButton(
                    .lockPrivateNotes,
                    "锁定私密笔记",
                    NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)!,
                    "lockPrivateNotes:"
                )

            case .toggleSidebar:
                // 创建自定义的切换侧边栏工具栏项
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

            case .sidebarTrackingSeparator:
                // 侧边栏跟踪分隔符 - 连接到分割视图的第一个分隔符
                if let splitViewController = window?.contentViewController as? NSSplitViewController {
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
                if let splitViewController = window?.contentViewController as? NSSplitViewController {
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
                NSToolbarItem.Identifier.separator,
            ]

            // 锁图标工具栏项始终在允许的标识符列表中，但通过验证逻辑控制可见性
            identifiers.append(NSToolbarItem.Identifier.lockPrivateNotes)

            return identifiers
        }

        public func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
            var identifiers: [NSToolbarItem.Identifier] = [
                NSToolbarItem.Identifier.toggleSidebar,
                NSToolbarItem.Identifier.sidebarTrackingSeparator,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.newNote,
                NSToolbarItem.Identifier.newFolder,
                NSToolbarItem.Identifier.undo,
                NSToolbarItem.Identifier.redo,
                NSToolbarItem.Identifier.formatMenu,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.search,
                NSToolbarItem.Identifier.sync,
                NSToolbarItem.Identifier.onlineStatus,
                NSToolbarItem.Identifier.settings,
                NSToolbarItem.Identifier.login,
                NSToolbarItem.Identifier.timelineTrackingSeparator,
                NSToolbarItem.Identifier.share,
                NSToolbarItem.Identifier.toggleStar,
                NSToolbarItem.Identifier.delete,
                NSToolbarItem.Identifier.history,
                NSToolbarItem.Identifier.trash,
                NSToolbarItem.Identifier.noteOperations,
            ]

            // 只有在选中私密笔记文件夹且已解锁时才添加锁图标
            let isPrivateFolder = coordinator.folderState.selectedFolder?.id == "2"
            let isUnlocked = coordinator.authState.isPrivateNotesUnlocked
            if isPrivateFolder, isUnlocked {
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
                customSearchField.delegate = self
                customSearchField.target = self
                customSearchField.action = #selector(performSearch(_:))

                // 设置搜索状态
                customSearchField.setSearchState(coordinator.searchState)

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
    }

    // MARK: - 工具栏辅助方法

    extension MainWindowController {

        /// 构建工具栏按钮
        func buildToolbarButton(
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
            button.target = self

            toolbarItem.view = button
            toolbarItem.toolTip = title
            toolbarItem.label = title
            return toolbarItem
        }

        /// 构建格式菜单
        func buildFormatMenu() -> NSMenu {
            let menu = NSMenu()

            let boldItem = NSMenuItem()
            boldItem.title = "粗体"
            boldItem.action = #selector(toggleBold(_:))
            boldItem.keyEquivalent = "b"
            boldItem.keyEquivalentModifierMask = [.command]
            menu.addItem(boldItem)

            let italicItem = NSMenuItem()
            italicItem.title = "斜体"
            italicItem.action = #selector(toggleItalic(_:))
            italicItem.keyEquivalent = "i"
            italicItem.keyEquivalentModifierMask = [.command]
            menu.addItem(italicItem)

            let underlineItem = NSMenuItem()
            underlineItem.title = "下划线"
            underlineItem.action = #selector(toggleUnderline(_:))
            underlineItem.keyEquivalent = "u"
            underlineItem.keyEquivalentModifierMask = [.command]
            menu.addItem(underlineItem)

            menu.addItem(NSMenuItem.separator())

            let strikethroughItem = NSMenuItem()
            strikethroughItem.title = "删除线"
            strikethroughItem.action = #selector(toggleStrikethrough(_:))
            menu.addItem(strikethroughItem)

            let codeItem = NSMenuItem()
            codeItem.title = "代码"
            codeItem.action = #selector(toggleCode(_:))
            codeItem.keyEquivalent = "`"
            codeItem.keyEquivalentModifierMask = [.command]
            menu.addItem(codeItem)

            menu.addItem(NSMenuItem.separator())

            let linkItem = NSMenuItem()
            linkItem.title = "插入链接"
            linkItem.action = #selector(insertLink(_:))
            linkItem.keyEquivalent = "k"
            linkItem.keyEquivalentModifierMask = [.command]
            menu.addItem(linkItem)

            return menu
        }

        /// 获取在线状态标题（带颜色和大圆点）
        func getOnlineStatusAttributedTitle() -> NSAttributedString {
            let statusText: String
            let statusColor: NSColor

            let authState = coordinator.authState
            let syncState = coordinator.syncState

            if authState.isLoggedIn {
                if syncState.isSyncing {
                    statusText = "同步中..."
                    statusColor = .systemYellow
                } else if authState.isCookieExpired {
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

        /// 更新在线状态菜单
        func updateOnlineStatusMenu() {
            // 如果需要动态更新菜单，可以在这里实现
        }
    }

#endif
