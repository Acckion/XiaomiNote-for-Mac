//
//  MainWindowController.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
import AppKit
import SwiftUI
import Combine
import os
import MiNoteLibrary

/// 主窗口控制器
/// 负责管理主窗口和工具栏
public class MainWindowController: NSWindowController {
    
    // MARK: - 属性
    
    private let logger = Logger(subsystem: "com.minote.MiNoteMac", category: "MainWindowController")
    
    /// 内容视图模型
    public private(set) var viewModel: NotesViewModel?
    
    /// 当前搜索字段（用于工具栏搜索项）
    private var currentSearchField: NSSearchField?
    
    /// 窗口控制器引用（防止被释放）
    private var loginWindowController: LoginWindowController?
    private var cookieRefreshWindowController: CookieRefreshWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    private var trashWindowController: TrashWindowController?
    
    /// Combine订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    /// 格式菜单popover
    private var formatMenuPopover: NSPopover?
    
    /// 在线状态菜单工具栏项
    private var onlineStatusMenuToolbarItem: NSToolbarItem?
    
    /// 笔记操作菜单工具栏项
    private let noteOperationsToolbarItem = NSMenuToolbarItem(itemIdentifier: .noteOperations)
    
    /// 测试菜单工具栏项（已弃用，保留以保持兼容性）
    private let testMenuToolbarItem = NSMenuToolbarItem(itemIdentifier: .testMenu)
    
    // MARK: - 初始化
    
    /// 使用指定的视图模型初始化窗口控制器
    /// - Parameter viewModel: 笔记视图模型
    public init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
        
        // 创建窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        // 设置窗口
        window.title = "笔记"
        window.titleVisibility = .visible
        window.setFrameAutosaveName("MainWindow")
        
        // 设置窗口内容
        setupWindowContent()
        
        // 设置工具栏
        setupToolbar()
        
        // 设置窗口最小尺寸
        window.minSize = NSSize(width: 600, height: 400)
        
        // 设置状态监听
        setupStateObservers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 窗口生命周期
    
    public override func windowDidLoad() {
        super.windowDidLoad()
        
        // 激活应用程序
        NSApp.activate(ignoringOtherApps: true)
        
        print("主窗口控制器已加载")
    }
    
    // MARK: - 设置方法
    
    /// 设置窗口内容
    private func setupWindowContent() {
        guard let window = window, let viewModel = viewModel else { return }
        
        // 创建分割视图控制器（三栏布局）
        let splitViewController = NSSplitViewController()
        
        // 第一栏：侧边栏（使用SwiftUI视图）
        let sidebarSplitViewItem = NSSplitViewItem(sidebarWithViewController: SidebarHostingController(viewModel: viewModel))
        sidebarSplitViewItem.minimumThickness = 180
        sidebarSplitViewItem.maximumThickness = 300
        sidebarSplitViewItem.canCollapse = true
        splitViewController.addSplitViewItem(sidebarSplitViewItem)
        
        // 第二栏：笔记列表（使用SwiftUI视图）
        let notesListSplitViewItem = NSSplitViewItem(contentListWithViewController: NotesListHostingController(viewModel: viewModel))
        notesListSplitViewItem.minimumThickness = 200
        notesListSplitViewItem.maximumThickness = 400
        splitViewController.addSplitViewItem(notesListSplitViewItem)
        
        // 第三栏：笔记详情
        let detailSplitViewItem = NSSplitViewItem(viewController: NoteDetailViewController(viewModel: viewModel))
        detailSplitViewItem.minimumThickness = 300
        splitViewController.addSplitViewItem(detailSplitViewItem)
        
        // 设置窗口内容
        window.contentViewController = splitViewController
    }
    
    /// 设置工具栏
    private func setupToolbar() {
        guard let window = window else { return }
        
        let toolbar = NSToolbar(identifier: "MainWindowToolbar")
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }
    
    // MARK: - 工具栏验证
    
    /// 验证工具栏项
    @objc func makeToolbarValidate() {
        window?.toolbar?.validateVisibleItems()
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    
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
            menu.delegate = self // 设置菜单代理以动态更新
            
            // 第一项：在线状态指示
            let statusItem = NSMenuItem()
            statusItem.title = "状态：加载中..."
            statusItem.isEnabled = false // 不可点击，仅显示状态
            statusItem.tag = 100 // 设置标签以便识别
            menu.addItem(statusItem)
            
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
            
            // 刷新Cookie
            let refreshCookieItem = NSMenuItem()
            refreshCookieItem.title = "刷新Cookie"
            refreshCookieItem.action = #selector(showCookieRefresh(_:))
            refreshCookieItem.target = self
            menu.addItem(refreshCookieItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // 重置同步状态
            let resetSyncItem = NSMenuItem()
            resetSyncItem.title = "重置同步状态"
            resetSyncItem.action = #selector(resetSyncStatus(_:))
            resetSyncItem.target = self
            menu.addItem(resetSyncItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // 同步状态
            let syncStatusItem = NSMenuItem()
            syncStatusItem.title = "同步状态"
            syncStatusItem.action = #selector(showSyncStatus(_:))
            syncStatusItem.target = self
            menu.addItem(syncStatusItem)
            
            // 设置菜单
            toolbarItem.menu = menu
            
            // 同时设置menuFormRepresentation以确保兼容性
            let menuItem = NSMenuItem()
            menuItem.title = "在线状态"
            menuItem.submenu = menu
            toolbarItem.menuFormRepresentation = menuItem
            
            return toolbarItem
            
        case .noteOperations:
            // 笔记操作菜单工具栏项 - 纯AppKit实现
            noteOperationsToolbarItem.toolTip = "笔记操作"
            noteOperationsToolbarItem.label = "操作"
            
            // 设置图像 - 使用文档图标
            noteOperationsToolbarItem.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            
            // 设置显示指示器（下拉箭头）
            noteOperationsToolbarItem.showsIndicator = true
            
            // 创建笔记操作菜单
            let noteOperationsMenu = NSMenu()
            
            // 置顶笔记
            let starNoteItem = NSMenuItem()
            starNoteItem.title = "置顶笔记"
            starNoteItem.action = #selector(toggleStarNote(_:))
            starNoteItem.target = self
            noteOperationsMenu.addItem(starNoteItem)
            
            // 添加到私密笔记
            let addToPrivateItem = NSMenuItem()
            addToPrivateItem.title = "添加到私密笔记"
            addToPrivateItem.action = #selector(addToPrivateNotes(_:))
            addToPrivateItem.target = self
            noteOperationsMenu.addItem(addToPrivateItem)
            
            // 移到
            let moveNoteItem = NSMenuItem()
            moveNoteItem.title = "移到"
            moveNoteItem.action = #selector(moveNote(_:))
            moveNoteItem.target = self
            noteOperationsMenu.addItem(moveNoteItem)
            
            noteOperationsMenu.addItem(NSMenuItem.separator())
            
            // 在笔记中查找（等待实现）
            let findInNoteItem = NSMenuItem()
            findInNoteItem.title = "在笔记中查找（等待实现）"
            findInNoteItem.isEnabled = false
            noteOperationsMenu.addItem(findInNoteItem)
            
            // 最近笔记（等待实现）
            let recentNotesItem = NSMenuItem()
            recentNotesItem.title = "最近笔记（等待实现）"
            recentNotesItem.isEnabled = false
            noteOperationsMenu.addItem(recentNotesItem)
            
            noteOperationsMenu.addItem(NSMenuItem.separator())
            
            // 删除笔记
            let deleteNoteItem = NSMenuItem()
            deleteNoteItem.title = "删除笔记"
            deleteNoteItem.action = #selector(deleteNote(_:))
            deleteNoteItem.target = self
            noteOperationsMenu.addItem(deleteNoteItem)
            
            // 历史修改
            let historyItem = NSMenuItem()
            historyItem.title = "历史修改"
            historyItem.action = #selector(showHistory(_:))
            historyItem.target = self
            noteOperationsMenu.addItem(historyItem)
            
            // 设置菜单
            noteOperationsToolbarItem.menu = noteOperationsMenu
            
            // 同时设置menuFormRepresentation以确保兼容性
            let menuItem = NSMenuItem()
            menuItem.title = "笔记操作"
            menuItem.submenu = noteOperationsMenu
            noteOperationsToolbarItem.menuFormRepresentation = menuItem
            
            return noteOperationsToolbarItem
            
        case .testMenu:
            // 测试菜单工具栏项 - 纯AppKit实现（已弃用）
            testMenuToolbarItem.toolTip = "测试菜单"
            testMenuToolbarItem.label = "测试"
            
            // 设置图像
            testMenuToolbarItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
            
            // 设置显示指示器（下拉箭头）
            testMenuToolbarItem.showsIndicator = true
            
            // 创建测试菜单
            let testMenu = NSMenu()
            
            let item1 = NSMenuItem()
            item1.title = "测试项1"
            item1.action = #selector(testMenuItem1(_:))
            item1.target = self
            testMenu.addItem(item1)
            
            let item2 = NSMenuItem()
            item2.title = "测试项2"
            item2.action = #selector(testMenuItem2(_:))
            item2.target = self
            testMenu.addItem(item2)
            
            testMenu.addItem(NSMenuItem.separator())
            
            let item3 = NSMenuItem()
            item3.title = "测试项3"
            item3.action = #selector(testMenuItem3(_:))
            item3.target = self
            testMenu.addItem(item3)
            
            // 设置菜单
            testMenuToolbarItem.menu = testMenu
            
            // 同时设置menuFormRepresentation以确保兼容性
            let menuItem = NSMenuItem()
            menuItem.title = "测试菜单"
            menuItem.submenu = testMenu
            testMenuToolbarItem.menuFormRepresentation = menuItem
            
            return testMenuToolbarItem
            
        case .toggleSidebar:
            // 创建自定义的切换侧边栏工具栏项
            return buildToolbarButton(.toggleSidebar, "隐藏/显示侧边栏", NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)!, "toggleSidebar:")
            
        case .share:
            return buildToolbarButton(.share, "分享", NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)!, "shareNote:")
            
        case .toggleStar:
            return buildToolbarButton(.toggleStar, "置顶", NSImage(systemSymbolName: "star", accessibilityDescription: nil)!, "toggleStarNote:")
            
        case .delete:
            return buildToolbarButton(.delete, "删除", NSImage(systemSymbolName: "trash", accessibilityDescription: nil)!, "deleteNote:")
            
        case .restore:
            return buildToolbarButton(.restore, "恢复", NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)!, "restoreNote:")
            
        case .history:
            return buildToolbarButton(.history, "历史记录", NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)!, "showHistory:")
            
        case .trash:
            return buildToolbarButton(.trash, "回收站", NSImage(systemSymbolName: "trash", accessibilityDescription: nil)!, "showTrash:")
            
        case .settings:
            return buildToolbarButton(.settings, "设置", NSImage(systemSymbolName: "gear", accessibilityDescription: nil)!, "showSettings:")
            
        case .login:
            return buildToolbarButton(.login, "登录", NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)!, "showLogin:")
            
        case .cookieRefresh:
            return buildToolbarButton(.cookieRefresh, "刷新Cookie", NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)!, "showCookieRefresh:")
            
        case .offlineOperations:
            return buildToolbarButton(.offlineOperations, "离线操作", NSImage(systemSymbolName: "arrow.clockwise.circle", accessibilityDescription: nil)!, "showOfflineOperations:")
            
        case .sidebarTrackingSeparator:
            // 侧边栏跟踪分隔符 - 连接到分割视图的第一个分隔符
            if let splitViewController = window?.contentViewController as? NSSplitViewController {
                return NSTrackingSeparatorToolbarItem(identifier: .sidebarTrackingSeparator, splitView: splitViewController.splitView, dividerIndex: 0)
            }
            return nil
            
        case .timelineTrackingSeparator:
            // 时间线跟踪分隔符 - 连接到分割视图的第二个分隔符
            if let splitViewController = window?.contentViewController as? NSSplitViewController {
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
        return [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .newNote,
            .newFolder,
            .undo,
            .redo,
            .bold,
            .italic,
            .underline,
            .strikethrough,
            .code,
            .link,
            .formatMenu,
            .checkbox,
            .horizontalRule,
            .attachment,
            .increaseIndent,
            .decreaseIndent,
            .flexibleSpace,
            .search,
            .sync,
            .onlineStatus,
            .settings,
            .login,
            .cookieRefresh,
            .offlineOperations,
            .timelineTrackingSeparator,
            .share,
            .toggleStar,
            .delete,
            .restore,
            .history,
            .trash,
            .noteOperations,
            .testMenu,
            .space,
            .separator
        ]
    }
    
    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .newNote,
            .newFolder,
            .undo,
            .redo,
            .formatMenu,
            .flexibleSpace,
            .search,
            .sync,
            .onlineStatus,
            .settings,
            .login,
            .timelineTrackingSeparator,
            .share,
            .toggleStar,
            .delete,
            .history,
            .trash,
            .noteOperations
        ]
    }
    
    public func toolbarWillAddItem(_ notification: Notification) {
        guard let item = notification.userInfo?["item"] as? NSToolbarItem else {
            return
        }
        
        if item.itemIdentifier == .search, let searchItem = item as? NSSearchToolbarItem {
            searchItem.searchField.delegate = self
            searchItem.searchField.target = self
            searchItem.searchField.action = #selector(performSearch(_:))
            currentSearchField = searchItem.searchField
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
        button.target = self
        
        toolbarItem.view = button
        toolbarItem.toolTip = title
        toolbarItem.label = title
        return toolbarItem
    }
    
    /// 构建格式菜单
    private func buildFormatMenu() -> NSMenu {
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
    
    /// 获取在线状态标题
    private func getOnlineStatusTitle() -> String {
        guard let viewModel = viewModel else {
            return "状态：未知"
        }
        
        if viewModel.isLoggedIn {
            if viewModel.isSyncing {
                return "状态：同步中..."
            } else if viewModel.isCookieExpired {
                return "状态：Cookie已过期"
            } else {
                return "状态：在线"
            }
        } else {
            return "状态：离线"
        }
    }
    
    /// 更新在线状态菜单
    private func updateOnlineStatusMenu() {
        // 如果需要动态更新菜单，可以在这里实现
    }
    
    // MARK: - 测试菜单动作
    
    @objc func testMenuItem1(_ sender: Any?) {
        print("测试菜单项1被点击")
        let alert = NSAlert()
        alert.messageText = "测试菜单"
        alert.informativeText = "测试菜单项1被点击"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    @objc func testMenuItem2(_ sender: Any?) {
        print("测试菜单项2被点击")
        let alert = NSAlert()
        alert.messageText = "测试菜单"
        alert.informativeText = "测试菜单项2被点击"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    @objc func testMenuItem3(_ sender: Any?) {
        print("测试菜单项3被点击")
        let alert = NSAlert()
        alert.messageText = "测试菜单"
        alert.informativeText = "测试菜单项3被点击"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
}

// MARK: - NSWindowDelegate

extension MainWindowController: NSWindowDelegate {
    
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // 清理窗口控制器引用
        if window == loginWindowController?.window {
            print("登录窗口即将关闭，清理引用")
            loginWindowController = nil
        } else if window == cookieRefreshWindowController?.window {
            print("Cookie刷新窗口即将关闭，清理引用")
            cookieRefreshWindowController = nil
        } else if window == settingsWindowController?.window {
            print("设置窗口即将关闭，清理引用")
            settingsWindowController = nil
        } else if window == historyWindowController?.window {
            print("历史记录窗口即将关闭，清理引用")
            historyWindowController = nil
        } else if window == trashWindowController?.window {
            print("回收站窗口即将关闭，清理引用")
            trashWindowController = nil
        }
    }
}

// MARK: - NSSearchFieldDelegate

extension MainWindowController: NSSearchFieldDelegate {
    
    public func searchFieldDidStartSearching(_ sender: NSSearchField) {
        // 搜索开始
        viewModel?.searchText = sender.stringValue
    }
    
    public func searchFieldDidEndSearching(_ sender: NSSearchField) {
        // 搜索结束
        viewModel?.searchText = ""
    }
    
    @objc func performSearch(_ sender: NSSearchField) {
        if sender.stringValue.isEmpty {
            return
        }
        viewModel?.searchText = sender.stringValue
    }
}

// MARK: - NSMenuDelegate

extension MainWindowController: NSMenuDelegate {
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        // 更新在线状态菜单项
        for item in menu.items {
            if item.tag == 100 { // 在线状态项
                item.title = getOnlineStatusTitle()
                break
            }
        }
    }
}

// MARK: - NSUserInterfaceValidations

extension MainWindowController: NSUserInterfaceValidations {
    
    public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        
        // 根据当前状态验证各个动作
        
        if item.action == #selector(createNewNote(_:)) {
            return true // 总是可以创建新笔记
        }
        
        if item.action == #selector(createNewFolder(_:)) {
            return true // 总是可以创建新文件夹
        }
        
        if item.action == #selector(performSync(_:)) {
            let isLoggedIn = viewModel?.isLoggedIn ?? false
            return isLoggedIn // 只有登录后才能同步
        }
        
        if item.action == #selector(shareNote(_:)) {
            let hasSelectedNote = viewModel?.selectedNote != nil
            return hasSelectedNote // 只有选中笔记后才能分享
        }
        
        if item.action == #selector(toggleStarNote(_:)) {
            let hasSelectedNote = viewModel?.selectedNote != nil
            return hasSelectedNote // 只有选中笔记后才能置顶
        }
        
        if item.action == #selector(deleteNote(_:)) {
            let hasSelectedNote = viewModel?.selectedNote != nil
            return hasSelectedNote // 只有选中笔记后才能删除
        }
        
        if item.action == #selector(restoreNote(_:)) {
            let hasSelectedNote = viewModel?.selectedNote != nil
            return hasSelectedNote // 只有选中笔记后才能恢复
        }
        
        // 格式操作：只有在编辑模式下才可用
        let formatActions: [Selector] = [
            #selector(toggleBold(_:)),
            #selector(toggleItalic(_:)),
            #selector(toggleUnderline(_:)),
            #selector(toggleStrikethrough(_:)),
            #selector(toggleCode(_:)),
            #selector(insertLink(_:)),
            #selector(toggleCheckbox(_:)),
            #selector(insertHorizontalRule(_:)),
            #selector(insertAttachment(_:)),
            #selector(increaseIndent(_:)),
            #selector(decreaseIndent(_:))
        ]
        
        if formatActions.contains(item.action!) {
            // 检查是否在编辑模式下（有选中的笔记）
            let hasSelectedNote = viewModel?.selectedNote != nil
            return hasSelectedNote
        }
        
        // 验证新的按钮
        if item.action == #selector(showSettings(_:)) {
            return true // 总是可以显示设置
        }
        
        if item.action == #selector(showLogin(_:)) {
            let isLoggedIn = viewModel?.isLoggedIn ?? false
            let shouldShow = !isLoggedIn
            return shouldShow // 只有未登录时才显示登录按钮
        }
        
        if item.action == #selector(showCookieRefresh(_:)) {
            let isCookieExpired = viewModel?.isCookieExpired ?? false
            return isCookieExpired // 只有Cookie失效时才显示刷新按钮
        }
        
        if item.action == #selector(showOfflineOperations(_:)) {
            let pendingCount = viewModel?.pendingOperationsCount ?? 0
            let shouldShow = pendingCount > 0
            return shouldShow // 只有有待处理操作时才显示
        }
        
        // 验证新增的工具栏按钮
        if item.action == #selector(toggleCheckbox(_:)) {
            let hasSelectedNote = viewModel?.selectedNote != nil
            return hasSelectedNote // 只有选中笔记后才能插入待办
        }
        
        if item.action == #selector(insertHorizontalRule(_:)) {
            let hasSelectedNote = viewModel?.selectedNote != nil
            return hasSelectedNote // 只有选中笔记后才能插入分割线
        }
        
        if item.action == #selector(insertAttachment(_:)) {
            let hasSelectedNote = viewModel?.selectedNote != nil
            return hasSelectedNote // 只有选中笔记后才能插入附件
        }
        
        if item.action == #selector(showHistory(_:)) {
            let hasSelectedNote = viewModel?.selectedNote != nil
            return hasSelectedNote // 只有选中笔记后才能查看历史记录
        }
        
        if item.action == #selector(showTrash(_:)) {
            return true // 总是可以显示回收站
        }
        
        if item.action == #selector(performIncrementalSync(_:)) {
            let isLoggedIn = viewModel?.isLoggedIn ?? false
            return isLoggedIn // 只有登录后才能增量同步
        }
        
        if item.action == #selector(resetSyncStatus(_:)) {
            return true // 总是可以重置同步状态
        }
        
        if item.action == #selector(showSyncStatus(_:)) {
            return true // 总是可以显示同步状态
        }
        
        // 验证切换侧边栏按钮
        if item.action == #selector(toggleSidebar(_:)) {
            return true // 总是可以切换侧边栏
        }
        
        // 验证撤销/重做按钮
        if item.action == #selector(undo(_:)) || item.action == #selector(redo(_:)) {
            let hasSelectedNote = viewModel?.selectedNote != nil
            return hasSelectedNote // 只有选中笔记后才能撤销/重做
        }
        
        // 验证搜索按钮
        if item.action == #selector(performSearch(_:)) {
            return true // 总是可以搜索
        }
        
        // 验证测试菜单项
        if item.action == #selector(testMenuItem1(_:)) ||
           item.action == #selector(testMenuItem2(_:)) ||
           item.action == #selector(testMenuItem3(_:)) {
            return true // 测试菜单项总是可用
        }
        
        // 默认返回true，确保所有按钮在溢出菜单中可用
        return true
    }
}

// MARK: - 动作方法

extension MainWindowController {
    
    @objc public func createNewNote(_ sender: Any?) {
        viewModel?.createNewNote()
    }
    
    @objc public func createNewFolder(_ sender: Any?) {
        // 显示新建文件夹对话框
        let alert = NSAlert()
        alert.messageText = "新建文件夹"
        alert.informativeText = "请输入文件夹名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputField.placeholderString = "文件夹名称"
        alert.accessoryView = inputField
        
        alert.window.initialFirstResponder = inputField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let folderName = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !folderName.isEmpty {
                Task {
                    do {
                        try await viewModel?.createFolder(name: folderName)
                    } catch {
                        print("创建文件夹失败: \(error)")
                    }
                }
            }
        }
    }
    
    @objc public func performSync(_ sender: Any?) {
        Task {
            await viewModel?.performFullSync()
        }
    }
    
    @objc public func shareNote(_ sender: Any?) {
        // 分享选中的笔记
        guard let note = viewModel?.selectedNote else { return }
        
        let sharingService = NSSharingServicePicker(items: [
            note.title,
            note.content
        ])
        
        if let window = window,
           let contentView = window.contentView {
            sharingService.show(relativeTo: NSRect.zero, of: contentView, preferredEdge: .minY)
        }
    }
    
    @objc func toggleStarNote(_ sender: Any?) {
        guard let note = viewModel?.selectedNote else { return }
        viewModel?.toggleStar(note)
    }
    
    @objc func deleteNote(_ sender: Any?) {
        guard let note = viewModel?.selectedNote else { return }
        
        let alert = NSAlert()
        alert.messageText = "删除笔记"
        alert.informativeText = "确定要删除笔记 \"\(note.title)\" 吗？此操作无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 直接调用deleteNote方法，它内部会处理异步操作
            viewModel?.deleteNote(note)
        }
    }
    
    @objc func restoreNote(_ sender: Any?) {
        // 恢复笔记功能
        print("恢复笔记")
    }
    
    @objc public func toggleBold(_ sender: Any?) {
        // 切换粗体
        print("切换粗体")
        // 这里应该调用编辑器API
    }
    
    @objc public func toggleItalic(_ sender: Any?) {
        // 切换斜体
        print("切换斜体")
    }
    
    @objc public func toggleUnderline(_ sender: Any?) {
        // 切换下划线
        print("切换下划线")
    }
    
    @objc public func toggleStrikethrough(_ sender: Any?) {
        // 切换删除线
        print("切换删除线")
    }
    
    @objc func toggleCode(_ sender: Any?) {
        // 切换代码格式
        print("切换代码格式")
    }
    
    @objc func insertLink(_ sender: Any?) {
        // 插入链接
        print("插入链接")
    }
    
    @objc func showSettings(_ sender: Any?) {
        // 显示设置窗口
        print("显示设置窗口")
        
        // 创建设置窗口控制器
        let settingsWindowController = SettingsWindowController(viewModel: viewModel)
        
        // 显示窗口
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc public func showLogin(_ sender: Any?) {
        // 显示登录sheet
        print("显示登录sheet - 开始")
        
        guard let window = window else {
            print("错误：主窗口不存在，无法显示登录sheet")
            return
        }
        
        // 创建登录视图
        let loginView = LoginView(viewModel: viewModel ?? NotesViewModel())
        
        // 创建托管控制器
        let hostingController = NSHostingController(rootView: loginView)
        
        // 创建sheet窗口
        let sheetWindow = NSWindow(contentViewController: hostingController)
        sheetWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        sheetWindow.title = "登录"
        sheetWindow.titlebarAppearsTransparent = true
        sheetWindow.titleVisibility = .hidden
        
        // 显示sheet
        window.beginSheet(sheetWindow) { response in
            print("登录sheet关闭，响应: \(response)")
        }
        
        print("显示登录sheet - 完成")
    }
    
    @objc public func showCookieRefresh(_ sender: Any?) {
        // 显示Cookie刷新sheet
        print("显示Cookie刷新sheet - 开始")
        
        guard let window = window else {
            print("错误：主窗口不存在，无法显示Cookie刷新sheet")
            return
        }
        
        // 创建Cookie刷新视图
        let cookieRefreshView = CookieRefreshView(viewModel: viewModel ?? NotesViewModel())
        
        // 创建托管控制器
        let hostingController = NSHostingController(rootView: cookieRefreshView)
        
        // 创建sheet窗口
        let sheetWindow = NSWindow(contentViewController: hostingController)
        sheetWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        sheetWindow.title = "刷新Cookie"
        sheetWindow.titlebarAppearsTransparent = true
        sheetWindow.titleVisibility = .hidden
        
        // 显示sheet
        window.beginSheet(sheetWindow) { response in
            print("Cookie刷新sheet关闭，响应: \(response)")
        }
        
        print("显示Cookie刷新sheet - 完成")
    }
    
    @objc func showOfflineOperations(_ sender: Any?) {
        // 显示离线操作处理窗口 - 使用简单的实现
        print("显示离线操作处理窗口")
        let alert = NSAlert()
        alert.messageText = "离线操作"
        alert.informativeText = "离线操作处理窗口功能正在开发中..."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    @objc func showDebugSettings(_ sender: Any?) {
        // 显示调试设置窗口 - 使用简单的实现
        print("显示调试设置窗口")
        let alert = NSAlert()
        alert.messageText = "调试设置"
        alert.informativeText = "调试设置窗口功能正在开发中..."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // MARK: - 新增工具栏按钮动作方法
    
    @objc func toggleCheckbox(_ sender: Any?) {
        print("切换待办")
        // 这里应该调用编辑器API
    }
    
    @objc func insertHorizontalRule(_ sender: Any?) {
        print("插入分割线")
        // 这里应该调用编辑器API
    }
    
    @objc func insertAttachment(_ sender: Any?) {
        print("插入附件")
        // 这里应该调用编辑器API
    }
    
    @objc public func showHistory(_ sender: Any?) {
        print("显示历史记录sheet - 开始")
        
        // 检查是否有选中的笔记
        guard let note = viewModel?.selectedNote else {
            let alert = NSAlert()
            alert.messageText = "历史记录"
            alert.informativeText = "请先选择要查看历史记录的笔记"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        guard let window = window else {
            print("错误：主窗口不存在，无法显示历史记录sheet")
            return
        }
        
        // 创建历史记录视图
        let historyView = NoteHistoryView(viewModel: viewModel ?? NotesViewModel(), noteId: note.id)
        
        // 创建托管控制器
        let hostingController = NSHostingController(rootView: historyView)
        
        // 创建sheet窗口
        let sheetWindow = NSWindow(contentViewController: hostingController)
        sheetWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        sheetWindow.title = "历史记录"
        sheetWindow.titlebarAppearsTransparent = true
        sheetWindow.titleVisibility = .hidden
        
        // 显示sheet
        window.beginSheet(sheetWindow) { response in
            print("历史记录sheet关闭，响应: \(response)")
        }
        
        print("显示历史记录sheet - 完成")
    }
    
    @objc public func showTrash(_ sender: Any?) {
        print("显示回收站sheet - 开始")
        
        guard let window = window else {
            print("错误：主窗口不存在，无法显示回收站sheet")
            return
        }
        
        // 创建回收站视图
        let trashView = TrashView(viewModel: viewModel ?? NotesViewModel())
        
        // 创建托管控制器
        let hostingController = NSHostingController(rootView: trashView)
        
        // 创建sheet窗口
        let sheetWindow = NSWindow(contentViewController: hostingController)
        sheetWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        sheetWindow.title = "回收站"
        sheetWindow.titlebarAppearsTransparent = true
        sheetWindow.titleVisibility = .hidden
        
        // 显示sheet
        window.beginSheet(sheetWindow) { response in
            print("回收站sheet关闭，响应: \(response)")
        }
        
        print("显示回收站sheet - 完成")
    }
    
    // MARK: - 笔记操作菜单动作方法
    
    @objc func addToPrivateNotes(_ sender: Any?) {
        print("添加到私密笔记")
        guard let note = viewModel?.selectedNote else { return }
        
        let alert = NSAlert()
        alert.messageText = "添加到私密笔记"
        alert.informativeText = "确定要将笔记 \"\(note.title)\" 添加到私密笔记吗？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 简化实现：显示成功消息
            print("笔记已添加到私密笔记（功能正在开发中）")
            let successAlert = NSAlert()
            successAlert.messageText = "操作成功"
            successAlert.informativeText = "笔记已添加到私密笔记（功能正在开发中）"
            successAlert.alertStyle = .informational
            successAlert.addButton(withTitle: "确定")
            successAlert.runModal()
        }
    }
    
    @objc func moveNote(_ sender: Any?) {
        print("移动笔记")
        guard let note = viewModel?.selectedNote,
              let viewModel = viewModel else { return }
        
        // 创建菜单
        let menu = NSMenu()
        
        // 未分类文件夹（folderId为"0"）
        let uncategorizedMenuItem = NSMenuItem(title: "未分类", action: #selector(moveToUncategorized(_:)), keyEquivalent: "")
        uncategorizedMenuItem.image = NSImage(systemSymbolName: "folder.badge.questionmark", accessibilityDescription: nil)
        uncategorizedMenuItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(uncategorizedMenuItem)
        
        // 其他可用文件夹
        let availableFolders = NoteMoveHelper.getAvailableFolders(for: viewModel)
        
        if !availableFolders.isEmpty {
            menu.addItem(NSMenuItem.separator())
            
            for folder in availableFolders {
                let menuItem = NSMenuItem(title: folder.name, action: #selector(moveNoteToFolder(_:)), keyEquivalent: "")
                menuItem.representedObject = folder
                menuItem.image = NSImage(systemSymbolName: folder.isPinned ? "pin.fill" : "folder", accessibilityDescription: nil)
                menuItem.image?.size = NSSize(width: 16, height: 16)
                menu.addItem(menuItem)
            }
        }
        
        // 显示菜单
        if let button = sender as? NSView {
            let location = NSPoint(x: 0, y: button.bounds.height)
            menu.popUp(positioning: nil, at: location, in: button)
        } else if let window = window {
            let location = NSPoint(x: window.frame.midX, y: window.frame.midY)
            menu.popUp(positioning: nil, at: location, in: nil)
        }
    }
    
    @objc func moveToUncategorized(_ sender: NSMenuItem) {
        guard let note = viewModel?.selectedNote,
              let viewModel = viewModel else { return }
        
        NoteMoveHelper.moveToUncategorized(note, using: viewModel) { result in
            switch result {
            case .success:
                print("[MainWindowController] 笔记移动到未分类成功: \(note.id)")
            case .failure(let error):
                print("[MainWindowController] 移动到未分类失败: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func moveNoteToFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? Folder,
              let note = viewModel?.selectedNote,
              let viewModel = viewModel else { return }
        
        NoteMoveHelper.moveNote(note, to: folder, using: viewModel) { result in
            switch result {
            case .success:
                print("[MainWindowController] 笔记移动成功: \(note.id) -> \(folder.name)")
            case .failure(let error):
                print("[MainWindowController] 移动笔记失败: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func showOnlineStatusMenu(_ sender: Any?) {
        // 在线状态菜单按钮点击
        print("显示在线状态菜单")
    }
    
    @objc func performIncrementalSync(_ sender: Any?) {
        print("执行增量同步")
        Task {
            await viewModel?.performIncrementalSync()
        }
    }
    
    @objc func resetSyncStatus(_ sender: Any?) {
        print("重置同步状态")
        viewModel?.resetSyncStatus()
    }
    
    @objc func showSyncStatus(_ sender: Any?) {
        print("显示同步状态")
        // 显示同步状态信息
        if let lastSync = viewModel?.lastSyncTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            
            let alert = NSAlert()
            alert.messageText = "同步状态"
            var infoText = "上次同步时间: \(formatter.string(from: lastSync))"
            if let pendingCount = viewModel?.pendingOperationsCount, pendingCount > 0 {
                infoText += "\n待处理操作: \(pendingCount) 个"
            }
            alert.informativeText = infoText
            alert.addButton(withTitle: "确定")
            alert.runModal()
        } else {
            let alert = NSAlert()
            alert.messageText = "同步状态"
            var infoText = "从未同步"
            if let pendingCount = viewModel?.pendingOperationsCount, pendingCount > 0 {
                infoText += "\n待处理操作: \(pendingCount) 个"
            }
            alert.informativeText = infoText
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    // MARK: - 侧边栏切换
    
    @objc func toggleSidebar(_ sender: Any?) {
        print("切换侧边栏显示/隐藏")
        
        guard let window = window,
              let splitViewController = window.contentViewController as? NSSplitViewController,
              splitViewController.splitViewItems.count > 0 else {
            print("无法获取分割视图控制器或侧边栏项")
            return
        }
        
        let sidebarItem = splitViewController.splitViewItems[0]
        let isCurrentlyCollapsed = sidebarItem.isCollapsed
        
        // 切换侧边栏状态
        sidebarItem.animator().isCollapsed = !isCurrentlyCollapsed
        
        print("侧边栏状态已切换: \(isCurrentlyCollapsed ? "显示" : "隐藏") -> \(!isCurrentlyCollapsed ? "显示" : "隐藏")")
    }
    
    // MARK: - 格式菜单
    
    @objc func showFormatMenu(_ sender: Any?) {
        // 显示格式菜单popover
        print("显示格式菜单")
        
        // 如果popover已经显示，则关闭它
        if let popover = formatMenuPopover, popover.isShown {
            popover.performClose(sender)
            formatMenuPopover = nil
            return
        }
        
        // 获取当前的WebEditorContext
        guard let webEditorContext = getCurrentWebEditorContext() else {
            print("无法获取WebEditorContext")
            return
        }
        
        // 创建SwiftUI格式菜单视图
        let formatMenuView = WebFormatMenuView(context: webEditorContext) { [weak self] _ in
            // 格式操作完成后关闭popover
            self?.formatMenuPopover?.performClose(nil)
            self?.formatMenuPopover = nil
        }
        
        // 创建托管控制器
        let hostingController = NSHostingController(rootView: formatMenuView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 200, height: 400)
        
        // 创建popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 200, height: 400)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
        
        // 存储popover引用
        formatMenuPopover = popover
        
        // 显示popover
        if let button = sender as? NSButton {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        } else if let window = window, let contentView = window.contentView {
            // 如果没有按钮，显示在窗口中央
            popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxY)
        }
    }
    
    /// 获取当前的WebEditorContext
    private func getCurrentWebEditorContext() -> WebEditorContext? {
        // 直接从viewModel获取共享的WebEditorContext
        return viewModel?.webEditorContext
    }
    
    // MARK: - 编辑菜单动作
    
    @objc public func undo(_ sender: Any?) {
        print("撤销")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func redo(_ sender: Any?) {
        print("重做")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func cut(_ sender: Any?) {
        print("剪切")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func copy(_ sender: Any?) {
        print("复制")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func paste(_ sender: Any?) {
        print("粘贴")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc override public func selectAll(_ sender: Any?) {
        print("全选")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    // MARK: - 格式菜单动作
    
    @objc public func increaseFontSize(_ sender: Any?) {
        print("增大字体")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func decreaseFontSize(_ sender: Any?) {
        print("减小字体")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func increaseIndent(_ sender: Any?) {
        print("增加缩进")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func decreaseIndent(_ sender: Any?) {
        print("减少缩进")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func alignLeft(_ sender: Any?) {
        print("居左对齐")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func alignCenter(_ sender: Any?) {
        print("居中对齐")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func alignRight(_ sender: Any?) {
        print("居右对齐")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func toggleBulletList(_ sender: Any?) {
        print("切换无序列表")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func toggleNumberedList(_ sender: Any?) {
        print("切换有序列表")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func toggleCheckboxList(_ sender: Any?) {
        print("切换复选框列表")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func setHeading1(_ sender: Any?) {
        print("设置大标题")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func setHeading2(_ sender: Any?) {
        print("设置二级标题")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func setHeading3(_ sender: Any?) {
        print("设置三级标题")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    @objc public func setBodyText(_ sender: Any?) {
        print("设置正文")
        // 这里应该调用编辑器API
        // 暂时使用控制台输出
    }
    
    // MARK: - 新增的菜单动作方法
    
    @objc public func copyNote(_ sender: Any?) {
        print("复制笔记（从菜单调用）")
        guard let note = viewModel?.selectedNote else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // 复制标题和内容
        let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
        pasteboard.setString(content, forType: .string)
    }
    
    // MARK: - 窗口状态管理
    
    /// 获取可保存的窗口状态
    /// - Returns: 窗口状态对象，如果无法获取则返回nil
    public func savableWindowState() -> MainWindowState? {
        guard let window = window,
              let splitViewController = window.contentViewController as? NSSplitViewController else {
            print("[MainWindowController] 无法获取窗口状态：窗口或分割视图控制器不存在")
            return nil
        }
        
        // 获取分割视图宽度
        let splitViewWidths = splitViewController.splitViewItems.map { item in
            return Int(item.viewController.view.frame.width)
        }
        
        // 检查侧边栏是否隐藏
        let isSidebarHidden = splitViewController.splitViewItems.first?.isCollapsed ?? false
        
        // 获取各个视图控制器的状态
        var sidebarWindowState: SidebarWindowState?
        var notesListWindowState: NotesListWindowState?
        var noteDetailWindowState: NoteDetailWindowState?
        
        // 获取侧边栏状态
        if let sidebarViewController = splitViewController.splitViewItems.first?.viewController as? SidebarViewController {
            sidebarWindowState = sidebarViewController.savableWindowState()
        }
        
        // 获取笔记列表状态
        if splitViewController.splitViewItems.count > 1,
           let notesListViewController = splitViewController.splitViewItems[1].viewController as? NotesListViewController {
            notesListWindowState = notesListViewController.savableWindowState()
        }
        
        // 获取笔记详情状态
        if splitViewController.splitViewItems.count > 2,
           let noteDetailViewController = splitViewController.splitViewItems[2].viewController as? NoteDetailViewController {
            noteDetailWindowState = noteDetailViewController.savableWindowState()
        }
        
        // 获取窗口状态
        let windowState = MainWindowState(
            isFullScreen: window.styleMask.contains(.fullScreen),
            splitViewWidths: splitViewWidths,
            isSidebarHidden: isSidebarHidden,
            sidebarWindowState: sidebarWindowState,
            notesListWindowState: notesListWindowState,
            noteDetailWindowState: noteDetailWindowState
        )
        
        print("[MainWindowController] 窗口状态已保存: \(windowState)")
        return windowState
    }
    
    /// 恢复窗口状态
    /// - Parameter state: 要恢复的窗口状态
    public func restoreWindowState(_ state: MainWindowState) {
        guard let window = window,
              let splitViewController = window.contentViewController as? NSSplitViewController else {
            print("[MainWindowController] 无法恢复窗口状态：窗口或分割视图控制器不存在")
            return
        }
        
        print("[MainWindowController] 恢复窗口状态: \(state)")
        
        // 恢复分割视图宽度
        if state.splitViewWidths.count == splitViewController.splitViewItems.count {
            for (index, width) in state.splitViewWidths.enumerated() {
                if index < splitViewController.splitViewItems.count {
                    let item = splitViewController.splitViewItems[index]
                    let cgWidth = CGFloat(width)
                    item.minimumThickness = cgWidth
                    item.maximumThickness = cgWidth
                    
                    // 设置首选宽度
                    let totalWidth = splitViewController.splitView.frame.width
                    if totalWidth > 0 {
                        item.preferredThicknessFraction = cgWidth / totalWidth
                    }
                }
            }
        }
        
        // 恢复侧边栏状态
        if let sidebarItem = splitViewController.splitViewItems.first {
            sidebarItem.isCollapsed = state.isSidebarHidden
        }
        
        // 恢复各个视图控制器的状态
        // 恢复侧边栏状态
        if let sidebarWindowState = state.sidebarWindowState,
           let sidebarViewController = splitViewController.splitViewItems.first?.viewController as? SidebarViewController {
            sidebarViewController.restoreWindowState(sidebarWindowState)
        }
        
        // 恢复笔记列表状态
        if let notesListWindowState = state.notesListWindowState,
           splitViewController.splitViewItems.count > 1,
           let notesListViewController = splitViewController.splitViewItems[1].viewController as? NotesListViewController {
            notesListViewController.restoreWindowState(notesListWindowState)
        }
        
        // 恢复笔记详情状态
        if let noteDetailWindowState = state.noteDetailWindowState,
           splitViewController.splitViewItems.count > 2,
           let noteDetailViewController = splitViewController.splitViewItems[2].viewController as? NoteDetailViewController {
            noteDetailViewController.restoreWindowState(noteDetailWindowState)
        }
        
        print("[MainWindowController] 窗口状态恢复完成")
    }
    
    // MARK: - 状态监听
    
    /// 设置状态监听器
    private func setupStateObservers() {
        guard let viewModel = viewModel else { return }
        
        // 监听登录视图显示状态
        viewModel.$showLoginView
            .receive(on: RunLoop.main)
            .sink { [weak self] showLoginView in
                if showLoginView {
                    print("[MainWindowController] 检测到showLoginView变为true，显示登录窗口")
                    self?.showLogin(nil)
                    // 重置状态，避免重复触发
                    viewModel.showLoginView = false
                }
            }
            .store(in: &cancellables)
        
        // 监听Cookie刷新视图显示状态
        viewModel.$showCookieRefreshView
            .receive(on: RunLoop.main)
            .sink { [weak self] showCookieRefreshView in
                if showCookieRefreshView {
                    print("[MainWindowController] 检测到showCookieRefreshView变为true，显示Cookie刷新窗口")
                    self?.showCookieRefresh(nil)
                    // 重置状态，避免重复触发
                    viewModel.showCookieRefreshView = false
                }
            }
            .store(in: &cancellables)
        
        // 监听选中的文件夹变化，更新窗口标题
        viewModel.$selectedFolder
            .receive(on: RunLoop.main)
            .sink { [weak self] selectedFolder in
                self?.updateWindowTitle(for: selectedFolder)
            }
            .store(in: &cancellables)
        
        // 监听笔记列表变化，更新窗口副标题
        viewModel.$notes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateWindowTitle(for: viewModel.selectedFolder)
            }
            .store(in: &cancellables)
        
        print("[MainWindowController] 状态监听器已设置")
    }
    
    /// 更新窗口标题和副标题
    private func updateWindowTitle(for folder: Folder?) {
        guard let window = window else { return }
        
        // 设置主标题为选中的文件夹名称
        let folderName = folder?.name ?? "笔记"
        window.title = folderName
        
        // 计算当前文件夹中的笔记数量
        let noteCount = getNoteCount(for: folder)
        
        // 设置副标题为笔记数量
        window.subtitle = "\(noteCount)个笔记"
    }
    
    /// 获取指定文件夹中的笔记数量
    private func getNoteCount(for folder: Folder?) -> Int {
        guard let viewModel = viewModel else { return 0 }
        
        if let folder = folder {
            if folder.id == "starred" {
                return viewModel.notes.filter { $0.isStarred }.count
            } else if folder.id == "0" {
                return viewModel.notes.count
            } else if folder.id == "2" {
                // 私密笔记文件夹：显示 folderId 为 "2" 的笔记
                return viewModel.notes.filter { $0.folderId == "2" }.count
            } else if folder.id == "uncategorized" {
                // 未分类文件夹：显示 folderId 为 "0" 或空的笔记
                return viewModel.notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }.count
            } else {
                return viewModel.notes.filter { $0.folderId == folder.id }.count
            }
        } else {
            return viewModel.notes.count
        }
    }
}

#endif
