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

/// 主窗口控制器
/// 负责管理主窗口和工具栏
public class MainWindowController: NSWindowController {
    
    // MARK: - 属性
    
    /// 内容视图模型
    public private(set) var viewModel: NotesViewModel?
    
    /// 当前搜索字段（用于工具栏搜索项）
    private var currentSearchField: NSSearchField?
    
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
        window.title = "备忘录"
        window.titleVisibility = .visible
        window.setFrameAutosaveName("MainWindow")
        
        // 设置窗口内容
        setupWindowContent()
        
        // 设置工具栏
        setupToolbar()
        
        // 设置窗口最小尺寸
        window.minSize = NSSize(width: 800, height: 600)
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
        
        // 第一栏：侧边栏
        let sidebarSplitViewItem = NSSplitViewItem(sidebarWithViewController: SidebarViewController(viewModel: viewModel))
        sidebarSplitViewItem.minimumThickness = 180
        sidebarSplitViewItem.maximumThickness = 300
        sidebarSplitViewItem.canCollapse = true
        splitViewController.addSplitViewItem(sidebarSplitViewItem)
        
        // 第二栏：笔记列表
        let notesListSplitViewItem = NSSplitViewItem(contentListWithViewController: NotesListViewController(viewModel: viewModel))
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
            let toolbarItem = NSMenuToolbarItem(itemIdentifier: .formatMenu)
            toolbarItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
            toolbarItem.toolTip = "格式"
            toolbarItem.label = "格式"
            toolbarItem.menu = buildFormatMenu()
            return toolbarItem
            
        case .search:
            let toolbarItem = NSSearchToolbarItem(itemIdentifier: .search)
            toolbarItem.toolTip = "搜索"
            toolbarItem.label = "搜索"
            return toolbarItem
            
        case .sync:
            return buildToolbarButton(.sync, "同步", NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)!, "performSync:")
            
        case .onlineStatus:
            let toolbarItem = MiNoteToolbarItem(itemIdentifier: .onlineStatus)
            toolbarItem.autovalidates = true
            toolbarItem.toolTip = "在线状态"
            toolbarItem.label = "状态"
            
            // 创建一个自定义视图来显示状态
            if let viewModel = viewModel {
                let statusView = NSHostingView(rootView: OnlineStatusIndicator(viewModel: viewModel))
                statusView.frame = NSRect(x: 0, y: 0, width: 80, height: 24)
                toolbarItem.view = statusView
            }
            
            return toolbarItem
            
        case .toggleSidebar:
            // 使用系统提供的切换侧边栏项
            return NSToolbarItem(itemIdentifier: .toggleSidebar)
            
        case .share:
            return buildToolbarButton(.share, "分享", NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)!, "shareNote:")
            
        case .toggleStar:
            return buildToolbarButton(.toggleStar, "置顶", NSImage(systemSymbolName: "star", accessibilityDescription: nil)!, "toggleStarNote:")
            
        case .delete:
            return buildToolbarButton(.delete, "删除", NSImage(systemSymbolName: "trash", accessibilityDescription: nil)!, "deleteNote:")
            
        case .restore:
            return buildToolbarButton(.restore, "恢复", NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)!, "restoreNote:")
            
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
            .bold,
            .italic,
            .underline,
            .strikethrough,
            .code,
            .link,
            .formatMenu,
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
            .formatMenu,
            .flexibleSpace,
            .search,
            .sync,
            .onlineStatus,
            .settings,
            .login,
            .timelineTrackingSeparator,
            .share,
            .toggleStar
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
            return viewModel?.isLoggedIn ?? false // 只有登录后才能同步
        }
        
        if item.action == #selector(shareNote(_:)) {
            return viewModel?.selectedNote != nil // 只有选中笔记后才能分享
        }
        
        if item.action == #selector(toggleStarNote(_:)) {
            return viewModel?.selectedNote != nil // 只有选中笔记后才能置顶
        }
        
        if item.action == #selector(deleteNote(_:)) {
            return viewModel?.selectedNote != nil // 只有选中笔记后才能删除
        }
        
        if item.action == #selector(restoreNote(_:)) {
            return false // 暂时不支持恢复
        }
        
        // 格式操作：只有在编辑模式下才可用
        let formatActions: [Selector] = [
            #selector(toggleBold(_:)),
            #selector(toggleItalic(_:)),
            #selector(toggleUnderline(_:)),
            #selector(toggleStrikethrough(_:)),
            #selector(toggleCode(_:)),
            #selector(insertLink(_:))
        ]
        
        if formatActions.contains(item.action!) {
            // 这里应该检查是否在编辑模式下
            // 暂时返回 true，后续需要根据实际编辑状态调整
            return true
        }
        
        // 验证新的按钮
        if item.action == #selector(showSettings(_:)) {
            return true // 总是可以显示设置
        }
        
        if item.action == #selector(showLogin(_:)) {
            return !(viewModel?.isLoggedIn ?? false) // 只有未登录时才显示登录按钮
        }
        
        if item.action == #selector(showCookieRefresh(_:)) {
            return viewModel?.isCookieExpired ?? false // 只有Cookie失效时才显示刷新按钮
        }
        
        if item.action == #selector(showOfflineOperations(_:)) {
            return (viewModel?.pendingOperationsCount ?? 0) > 0 // 只有有待处理操作时才显示
        }
        
        return true
    }
}

// MARK: - 动作方法

extension MainWindowController {
    
    @objc func createNewNote(_ sender: Any?) {
        viewModel?.createNewNote()
    }
    
    @objc func createNewFolder(_ sender: Any?) {
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
    
    @objc func performSync(_ sender: Any?) {
        Task {
            await viewModel?.performFullSync()
        }
    }
    
    @objc func shareNote(_ sender: Any?) {
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
        alert.messageText = "删除备忘录"
        alert.informativeText = "确定要删除备忘录 \"\(note.title)\" 吗？此操作无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task {
                do {
                    try await viewModel?.deleteNote(note)
                } catch {
                    print("删除备忘录失败: \(error)")
                }
            }
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
    
    @objc func showLogin(_ sender: Any?) {
        // 显示登录窗口
        print("显示登录窗口")
        
        // 创建登录窗口控制器
        let loginWindowController = LoginWindowController(viewModel: viewModel)
        
        // 显示窗口
        loginWindowController.showWindow(nil)
        loginWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc func showCookieRefresh(_ sender: Any?) {
        // 显示Cookie刷新窗口
        print("显示Cookie刷新窗口")
        
        // 创建Cookie刷新窗口控制器
        let cookieRefreshWindowController = CookieRefreshWindowController(viewModel: viewModel)
        
        // 显示窗口
        cookieRefreshWindowController.showWindow(sender)
        cookieRefreshWindowController.window?.makeKeyAndOrderFront(sender)
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
}

#endif
