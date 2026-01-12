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

/// 主窗口控制器
/// 负责管理主窗口和工具栏
public class MainWindowController: NSWindowController {
    
    // MARK: - 属性
    
    private let logger = Logger(subsystem: "com.minote.MiNoteMac", category: "MainWindowController")
    
    /// 内容视图模型
    public private(set) var viewModel: NotesViewModel?
    
    /// 当前搜索字段（用于工具栏搜索项）
    private var currentSearchField: CustomSearchField?
    
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
    
    /// 搜索筛选菜单popover
    private var searchFilterMenuPopover: NSPopover?
    
    /// 视图选项菜单popover
    /// _Requirements: 1.2, 1.3, 1.4_
    private var viewOptionsMenuPopover: NSPopover?
    
    /// 在线状态菜单工具栏项
    private var onlineStatusMenuToolbarItem: NSToolbarItem?
    
    
    /// 当前显示的sheet窗口引用
    private var currentSheetWindow: NSWindow?
    
    /// 当前sheet窗口的工具栏代理引用
    private var currentSheetToolbarDelegate: BaseSheetToolbarDelegate?
    
    /// 回收站sheet的工具栏代理引用
    private var trashSheetToolbarDelegate: BaseSheetToolbarDelegate?
    
    /// 登录sheet的工具栏代理引用
    private var loginSheetToolbarDelegate: BaseSheetToolbarDelegate?
    
    /// Cookie刷新sheet的工具栏代理引用
    private var cookieRefreshSheetToolbarDelegate: BaseSheetToolbarDelegate?
    
    /// 历史记录sheet的工具栏代理引用
    private var historySheetToolbarDelegate: BaseSheetToolbarDelegate?
    
    /// 工具栏代理
    private var toolbarDelegate: MainWindowToolbarDelegate?
    
    /// 工具栏可见性管理器
    /// 负责根据应用状态动态更新工具栏项的可见性
    /// **Requirements: 5.4**
    private var visibilityManager: ToolbarVisibilityManager?

    /// 查找面板控制器
    private var searchPanelController: SearchPanelController?
    
    /// 保存的笔记列表宽度（用于视图模式切换时恢复）
    private var savedNotesListWidth: CGFloat?
    
    /// 笔记列表宽度的 UserDefaults 键
    private let notesListWidthKey = "NotesListWidth"
    
    // MARK: - 音频面板属性
    // Requirements: 1.1
    
    /// 音频面板状态管理器
    /// 负责管理音频面板的显示状态、模式和与其他组件的协调
    private let audioPanelStateManager = AudioPanelStateManager.shared
    
    /// 音频面板托管控制器
    /// 用于将 AudioPanelView 嵌入 NSSplitViewController 作为第四栏
    private var audioPanelHostingController: AudioPanelHostingController?
    
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

        // 初始化查找面板控制器
        searchPanelController = SearchPanelController(mainWindowController: self)
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
    /// 
    /// 使用三栏布局：侧边栏 + 笔记列表 + 编辑器
    /// 在画廊模式下，笔记列表和编辑器区域会被 ContentAreaView 替换
    /// _Requirements: 4.3, 4.4, 4.5_
    private func setupWindowContent() {
        guard let window = window, let viewModel = viewModel else { return }
        
        // 创建分割视图控制器（三栏布局）
        let splitViewController = NSSplitViewController()
        
        // 设置分割视图的自动保存名称，用于记住分割位置
        splitViewController.splitView.autosaveName = "MainWindowSplitView"
        
        // 第一栏：侧边栏（使用SwiftUI视图）
        let sidebarSplitViewItem = NSSplitViewItem(sidebarWithViewController: SidebarHostingController(viewModel: viewModel))
        sidebarSplitViewItem.minimumThickness = 180
        sidebarSplitViewItem.maximumThickness = 300
        sidebarSplitViewItem.canCollapse = true
        splitViewController.addSplitViewItem(sidebarSplitViewItem)
        
        // 第二栏：笔记列表（使用SwiftUI视图）
        let notesListSplitViewItem = NSSplitViewItem(viewController: NotesListHostingController(viewModel: viewModel))
        notesListSplitViewItem.minimumThickness = 200
        notesListSplitViewItem.maximumThickness = 350
        notesListSplitViewItem.canCollapse = false
        // 设置较高的 holdingPriority，窗口缩小时优先压缩编辑器
        notesListSplitViewItem.holdingPriority = NSLayoutConstraint.Priority(251)
        splitViewController.addSplitViewItem(notesListSplitViewItem)
        
        // 第三栏：笔记详情编辑器（使用SwiftUI视图）
        let noteDetailSplitViewItem = NSSplitViewItem(viewController: NoteDetailHostingController(viewModel: viewModel))
        noteDetailSplitViewItem.minimumThickness = 400
        // 编辑器 holdingPriority 较低，窗口缩小时先压缩编辑器
        noteDetailSplitViewItem.holdingPriority = NSLayoutConstraint.Priority(250)
        splitViewController.addSplitViewItem(noteDetailSplitViewItem)
        
        // 设置窗口内容
        window.contentViewController = splitViewController
        
        // 监听视图模式变化，动态切换布局
        setupViewModeObserver(splitViewController: splitViewController)
    }
    
    /// 设置视图模式监听
    /// 在列表模式和画廊模式之间切换时，动态调整分割视图布局
    /// _Requirements: 4.3, 4.4, 4.5_
    private func setupViewModeObserver(splitViewController: NSSplitViewController) {
        guard let viewModel = viewModel else { return }
        
        ViewOptionsManager.shared.$state
            .map(\.viewMode)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak splitViewController] viewMode in
                guard let self = self, let splitViewController = splitViewController else { return }
                self.updateLayoutForViewMode(viewMode, splitViewController: splitViewController, viewModel: viewModel)
            }
            .store(in: &cancellables)
        
        // 初始化时根据当前视图模式设置布局
        updateLayoutForViewMode(ViewOptionsManager.shared.viewMode, splitViewController: splitViewController, viewModel: viewModel)
    }
    
    /// 根据视图模式更新布局
    /// _Requirements: 4.3, 4.4, 4.5_
    private func updateLayoutForViewMode(_ viewMode: ViewMode, splitViewController: NSSplitViewController, viewModel: NotesViewModel) {
        let splitViewItems = splitViewController.splitViewItems
        guard splitViewItems.count >= 2 else { return }
        
        switch viewMode {
        case .list:
            // 列表模式：显示三栏布局（侧边栏 + 笔记列表 + 编辑器）
            if splitViewItems.count == 2 {
                // 当前是两栏布局（画廊模式），需要恢复三栏布局
                // 移除画廊视图
                splitViewController.removeSplitViewItem(splitViewItems[1])
                
                // 添加笔记列表
                let notesListSplitViewItem = NSSplitViewItem(viewController: NotesListHostingController(viewModel: viewModel))
                notesListSplitViewItem.minimumThickness = 200
                notesListSplitViewItem.maximumThickness = 350
                notesListSplitViewItem.canCollapse = false
                // 设置较高的 holdingPriority，窗口缩小时优先压缩编辑器
                notesListSplitViewItem.holdingPriority = NSLayoutConstraint.Priority(251)
                splitViewController.insertSplitViewItem(notesListSplitViewItem, at: 1)
                
                // 添加笔记详情编辑器
                let noteDetailSplitViewItem = NSSplitViewItem(viewController: NoteDetailHostingController(viewModel: viewModel))
                noteDetailSplitViewItem.minimumThickness = 400
                // 编辑器 holdingPriority 较低，窗口缩小时先压缩编辑器
                noteDetailSplitViewItem.holdingPriority = NSLayoutConstraint.Priority(250)
                splitViewController.addSplitViewItem(noteDetailSplitViewItem)
                
                // 恢复保存的笔记列表宽度
                restoreNotesListWidth(splitViewController: splitViewController)
            }
            
        case .gallery:
            // 画廊模式：显示两栏布局（侧边栏 + 画廊视图）
            if splitViewItems.count == 3 {
                // 保存当前笔记列表宽度
                saveNotesListWidth(splitViewController: splitViewController)
                
                // 当前是三栏布局（列表模式），需要切换到两栏布局
                // 移除笔记列表和编辑器
                splitViewController.removeSplitViewItem(splitViewItems[2])
                splitViewController.removeSplitViewItem(splitViewItems[1])
                
                // 添加画廊视图
                let galleryHostingController = GalleryHostingController(viewModel: viewModel)
                let gallerySplitViewItem = NSSplitViewItem(viewController: galleryHostingController)
                gallerySplitViewItem.minimumThickness = 500
                // 画廊视图 holdingPriority 较低，窗口缩小时先压缩
                gallerySplitViewItem.holdingPriority = NSLayoutConstraint.Priority(250)
                splitViewController.addSplitViewItem(gallerySplitViewItem)
            }
        }
    }
    
    /// 保存笔记列表宽度
    private func saveNotesListWidth(splitViewController: NSSplitViewController) {
        guard splitViewController.splitViewItems.count >= 2 else { return }
        let notesListView = splitViewController.splitView.subviews[1]
        let width = notesListView.frame.width
        savedNotesListWidth = width
        UserDefaults.standard.set(width, forKey: notesListWidthKey)
    }
    
    /// 恢复笔记列表宽度
    private func restoreNotesListWidth(splitViewController: NSSplitViewController) {
        // 优先使用内存中保存的宽度，否则从 UserDefaults 读取
        let width = savedNotesListWidth ?? UserDefaults.standard.object(forKey: notesListWidthKey) as? CGFloat
        
        guard let targetWidth = width,
              splitViewController.splitViewItems.count >= 2 else { return }
        
        // 延迟执行以确保视图已经添加完成
        DispatchQueue.main.async {
            splitViewController.splitView.setPosition(
                splitViewController.splitView.subviews[0].frame.width + targetWidth,
                ofDividerAt: 1
            )
        }
    }
    
    /// 设置工具栏
    private func setupToolbar() {
        guard let window = window else { return }
        
        // 创建工具栏代理
        toolbarDelegate = MainWindowToolbarDelegate(viewModel: viewModel, windowController: self)
        
        let toolbar = NSToolbar(identifier: "MainWindowToolbar")
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        toolbar.delegate = toolbarDelegate
        
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        
        // 创建工具栏可见性管理器
        // **Requirements: 5.4**
        visibilityManager = ToolbarVisibilityManager(toolbar: toolbar, viewModel: viewModel)
        
        // 将可见性管理器传递给工具栏代理
        toolbarDelegate?.visibilityManager = visibilityManager
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
            
            // 第一项：在线状态指示（带颜色和大圆点）
            let statusItem = NSMenuItem()
            // 创建初始的富文本标题
            let initialAttributedString = NSMutableAttributedString()
            
            // 添加大圆点（灰色，表示加载中）
            let dotAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20, weight: .bold), // 与getOnlineStatusAttributedTitle保持一致
                .foregroundColor: NSColor.gray,
                .baselineOffset: 0 // 与getOnlineStatusAttributedTitle保持一致
            ]
            initialAttributedString.append(NSAttributedString(string: "• ", attributes: dotAttributes))
            
            // 添加状态文本（使用相同的颜色）
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.gray // 使用与圆点相同的颜色
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

            // 刷新Cookie
            let refreshCookieItem = NSMenuItem()
            refreshCookieItem.title = "刷新Cookie"
            refreshCookieItem.action = #selector(showCookieRefresh(_:))
            refreshCookieItem.target = self
            menu.addItem(refreshCookieItem)
            
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
            return buildToolbarButton(.lockPrivateNotes, "锁定私密笔记", NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)!, "lockPrivateNotes:")
            
        case .toggleSidebar:
            // 创建自定义的切换侧边栏工具栏项
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
            
        case .sidebarTrackingSeparator:
            // 侧边栏跟踪分隔符 - 连接到分割视图的第一个分隔符
            if let splitViewController = window?.contentViewController as? NSSplitViewController {
                return NSTrackingSeparatorToolbarItem(identifier: .sidebarTrackingSeparator, splitView: splitViewController.splitView, dividerIndex: 0)
            }
            return nil
            
        case .timelineTrackingSeparator:
            // 时间线跟踪分隔符
            // 注意：由于使用两栏布局（侧边栏 + 内容区域），只有一个分隔符
            // 如果分割视图只有一个分隔符，返回普通分隔符
            // _Requirements: 4.3, 4.4, 4.5_
            if let splitViewController = window?.contentViewController as? NSSplitViewController {
                let dividerCount = splitViewController.splitView.subviews.count - 1
                if dividerCount > 1 {
                    // 三栏布局：使用第二个分隔符
                    return NSTrackingSeparatorToolbarItem(identifier: .timelineTrackingSeparator, splitView: splitViewController.splitView, dividerIndex: 1)
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
            NSToolbarItem.Identifier.noteOperations
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
            customSearchField.delegate = self
            customSearchField.target = self
            customSearchField.action = #selector(performSearch(_:))
            
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
    
    /// 获取在线状态标题（带颜色和大圆点）
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
    
    /// 更新在线状态菜单
    private func updateOnlineStatusMenu() {
        // 如果需要动态更新菜单，可以在这里实现
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
        } else if window == currentSheetWindow {
            print("离线操作进度sheet窗口即将关闭，清理引用")
            currentSheetWindow = nil
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
        // 无论搜索内容是否为空，都更新搜索文本
        // 这样当用户清空搜索框并按Enter时，会结束搜索
        viewModel?.searchText = sender.stringValue
    }
    
    public func controlTextDidBeginEditing(_ obj: Notification) {
        print("[MainWindowController] controlTextDidBeginEditing被调用")
        
        // 当搜索框开始编辑（获得焦点）时，显示筛选菜单
        if let searchField = obj.object as? NSSearchField {
            print("[MainWindowController] 搜索框开始编辑: \(searchField)")
            
            if searchField == currentSearchField {
                // 检查popover是否已经显示
                if let popover = searchFilterMenuPopover, popover.isShown {
                    print("[MainWindowController] popover已经显示，跳过重复调用")
                    return
                }
                
                print("[MainWindowController] 是当前搜索框，立即显示筛选菜单")
                
                // 只要光标在搜索框中就弹出菜单，不需要检查搜索框内容
                print("[MainWindowController] 光标在搜索框中，立即显示筛选菜单")
                self.showSearchFilterMenu(searchField)
            } else {
                print("[MainWindowController] 不是当前搜索框，忽略")
            }
        } else {
            print("[MainWindowController] 通知对象不是搜索框: \(obj.object ?? "nil")")
        }
    }
    
    public func controlTextDidEndEditing(_ obj: Notification) {
        print("[MainWindowController] controlTextDidEndEditing被调用")
        
        // 当搜索框结束编辑（失去焦点）时，收回筛选菜单
        if let searchField = obj.object as? NSSearchField {
            print("[MainWindowController] 搜索框结束编辑: \(searchField)")
            
            if searchField == currentSearchField {
                print("[MainWindowController] 是当前搜索框，收回筛选菜单")
                
                // 如果popover正在显示，关闭它
                if let popover = searchFilterMenuPopover, popover.isShown {
                    print("[MainWindowController] popover正在显示，关闭它")
                    popover.performClose(nil)
                    searchFilterMenuPopover = nil
                }
            }
        }
    }
}

// MARK: - NSMenuDelegate

extension MainWindowController: NSMenuDelegate {
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        print("[MainWindowController] menuNeedsUpdate被调用，菜单标题: \(menu.title)，菜单项数量: \(menu.items.count)")
        
        let optionsManager = ViewOptionsManager.shared
        
        // 更新菜单项状态
        for item in menu.items {
            // 在线状态菜单项
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
            
            // 视图选项菜单的选中状态
            // _Requirements: 2.4, 2.8, 3.5, 4.6_
            
            // 排序方式选中状态
            if item.tag == 1 { // 编辑时间
                item.state = optionsManager.sortOrder == .editDate ? .on : .off
            } else if item.tag == 2 { // 创建时间
                item.state = optionsManager.sortOrder == .createDate ? .on : .off
            } else if item.tag == 3 { // 标题
                item.state = optionsManager.sortOrder == .title ? .on : .off
            }
            
            // 排序方向选中状态
            if item.tag == 10 { // 降序
                item.state = optionsManager.sortDirection == .descending ? .on : .off
            } else if item.tag == 11 { // 升序
                item.state = optionsManager.sortDirection == .ascending ? .on : .off
            }
            
            // 日期分组选中状态
            if item.tag == 20 { // 开
                item.state = optionsManager.isDateGroupingEnabled ? .on : .off
            } else if item.tag == 21 { // 关
                item.state = !optionsManager.isDateGroupingEnabled ? .on : .off
            }
            
            // 视图模式选中状态
            if item.tag == 30 { // 列表视图
                item.state = optionsManager.viewMode == .list ? .on : .off
            } else if item.tag == 31 { // 画廊视图
                item.state = optionsManager.viewMode == .gallery ? .on : .off
            }
            
            // 按日期分组菜单项：当排序方式为标题时隐藏
            // 因为按标题排序时，日期分组没有意义
            if item.title == "按日期分组" {
                item.isHidden = optionsManager.sortOrder == .title
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
        
        
        // 验证锁定私密笔记按钮
        if item.action == #selector(lockPrivateNotes(_:)) {
            // 只有在以下条件满足时才显示锁图标：
            // 1. 当前选中的文件夹是私密笔记文件夹 (folderId == "2")
            // 2. 私密笔记已解锁 (isPrivateNotesUnlocked == true)
            let isPrivateFolder = viewModel?.selectedFolder?.id == "2"
            let isUnlocked = viewModel?.isPrivateNotesUnlocked ?? false
            return isPrivateFolder && isUnlocked
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
        sheetWindow.titlebarAppearsTransparent = false // 显示标题栏
        sheetWindow.titleVisibility = .visible // 显示标题
        
        // 为sheet窗口添加工具栏
        let toolbarDelegate = BaseSheetToolbarDelegate()
        toolbarDelegate.onClose = { [weak window, weak sheetWindow] in
            // 关闭sheet - 使用弱引用捕获两个窗口
            if let window = window, let sheetWindow = sheetWindow {
                window.endSheet(sheetWindow)
            }
        }
        
        let toolbar = NSToolbar(identifier: "LoginSheetToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = toolbarDelegate
        sheetWindow.toolbar = toolbar
        sheetWindow.toolbarStyle = .unified
        
        // 存储工具栏代理引用，防止被ARC释放
        self.loginSheetToolbarDelegate = toolbarDelegate
        
        // 显示sheet
        window.beginSheet(sheetWindow) { response in
            print("登录sheet关闭，响应: \(response)")
            // 清理工具栏代理引用
            self.loginSheetToolbarDelegate = nil
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
        sheetWindow.titlebarAppearsTransparent = false // 显示标题栏
        sheetWindow.titleVisibility = .visible // 显示标题
        
        // 为sheet窗口添加工具栏
        let toolbarDelegate = BaseSheetToolbarDelegate()
        toolbarDelegate.onClose = { [weak window] in
            // 关闭sheet
            window?.endSheet(sheetWindow)
        }
        
        let toolbar = NSToolbar(identifier: "CookieRefreshSheetToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = toolbarDelegate
        sheetWindow.toolbar = toolbar
        sheetWindow.toolbarStyle = .unified
        
        // 存储工具栏代理引用，防止被ARC释放
        self.cookieRefreshSheetToolbarDelegate = toolbarDelegate
        
        // 显示sheet
        window.beginSheet(sheetWindow) { response in
            print("Cookie刷新sheet关闭，响应: \(response)")
            // 清理工具栏代理引用
            self.cookieRefreshSheetToolbarDelegate = nil
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
    
    /// 切换 XML 调试模式
    /// 
    /// 通过发送通知来切换调试模式，NoteDetailView 会监听此通知并切换显示模式
    /// 
    /// _Requirements: 1.1, 1.2, 5.2, 6.1_
    @objc func toggleDebugMode(_ sender: Any?) {
        print("[MainWindowController] 切换 XML 调试模式")
        
        // 检查是否有选中笔记
        guard viewModel?.selectedNote != nil else {
            print("[MainWindowController] 没有选中笔记，无法切换调试模式")
            return
        }
        
        // 发送通知切换调试模式
        NotificationCenter.default.post(name: .toggleDebugMode, object: nil)
    }
    
    // MARK: - 新增工具栏按钮动作方法
    
    /// 切换待办（插入复选框）
    /// 需求: 3.1, 3.2, 3.4 - 根据编辑器类型调用对应的 insertCheckbox 方法
    @objc func toggleCheckbox(_ sender: Any?) {
        print("[MainWindowController] 切换待办")
        
        // 需求 3.4: 检查是否有选中笔记
        guard viewModel?.selectedNote != nil else {
            print("[MainWindowController] 没有选中笔记，无法插入待办")
            return
        }
        
        // 需求 3.1, 3.2: 根据编辑器类型调用对应的方法
        if isUsingNativeEditor {
            // 需求 3.1: 原生编辑器模式
            print("[MainWindowController] 使用原生编辑器，调用 NativeEditorContext.insertCheckbox()")
            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.insertCheckbox()
            } else {
                print("[MainWindowController] 错误：无法获取 NativeEditorContext")
            }
        } else {
            // 需求 3.2: Web 编辑器模式
            print("[MainWindowController] 使用 Web 编辑器，调用 WebEditorContext.insertCheckbox()")
            if let webContext = getCurrentWebEditorContext() {
                webContext.insertCheckbox()
            } else {
                print("[MainWindowController] 错误：无法获取 WebEditorContext")
            }
        }
    }
    
    /// 插入分割线
    /// 需求: 4.1, 4.2, 4.4 - 根据编辑器类型调用对应的 insertHorizontalRule 方法
    @objc func insertHorizontalRule(_ sender: Any?) {
        print("[MainWindowController] 插入分割线")
        
        // 需求 4.4: 检查是否有选中笔记
        guard viewModel?.selectedNote != nil else {
            print("[MainWindowController] 没有选中笔记，无法插入分割线")
            return
        }
        
        // 需求 4.1, 4.2: 根据编辑器类型调用对应的方法
        if isUsingNativeEditor {
            // 需求 4.1: 原生编辑器模式
            print("[MainWindowController] 使用原生编辑器，调用 NativeEditorContext.insertHorizontalRule()")
            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.insertHorizontalRule()
            } else {
                print("[MainWindowController] 错误：无法获取 NativeEditorContext")
            }
        } else {
            // 需求 4.2: Web 编辑器模式
            print("[MainWindowController] 使用 Web 编辑器，调用 WebEditorContext.insertHorizontalRule()")
            if let webContext = getCurrentWebEditorContext() {
                webContext.insertHorizontalRule()
            } else {
                print("[MainWindowController] 错误：无法获取 WebEditorContext")
            }
        }
    }
    
    /// 插入附件（图片）
    /// 需求: 5.1, 5.2, 5.3, 5.5 - 显示文件选择对话框，根据编辑器类型调用对应的 insertImage 方法
    @objc public func insertAttachment(_ sender: Any?) {
        print("[MainWindowController] 插入附件")
        
        // 需求 5.5: 检查是否有选中笔记
        guard viewModel?.selectedNote != nil else {
            print("[MainWindowController] 没有选中笔记，无法插入附件")
            return
        }
        
        // 需求 5.1: 显示文件选择对话框
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image, .png, .jpeg, .gif]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.message = "选择要插入的图片"
        openPanel.prompt = "插入"
        
        openPanel.begin { [weak self] response in
            guard let self = self else { return }
            
            if response == .OK, let url = openPanel.url {
                // 需求 5.2, 5.3: 上传图片并插入到编辑器
                Task { @MainActor in
                    await self.insertImage(from: url)
                }
            }
        }
    }
    
    /// 从 URL 插入图片
    /// 需求: 5.2, 5.3 - 上传图片并根据编辑器类型插入
    @MainActor
    private func insertImage(from url: URL) async {
        guard let viewModel = viewModel else {
            print("[MainWindowController] 错误：viewModel 不存在")
            return
        }
        
        guard viewModel.selectedNote != nil else {
            print("[MainWindowController] 错误：没有选中笔记")
            return
        }
        
        do {
            // 上传图片并获取 fileId
            let fileId = try await viewModel.uploadImageAndInsertToNote(imageURL: url)
            print("[MainWindowController] 图片上传成功: fileId=\(fileId)")
            
            // 需求 5.2, 5.3: 根据编辑器类型调用对应的 insertImage 方法
            if isUsingNativeEditor {
                // 原生编辑器模式
                print("[MainWindowController] 使用原生编辑器，调用 NativeEditorContext.insertImage()")
                if let nativeContext = getCurrentNativeEditorContext() {
                    nativeContext.insertImage(fileId: fileId, src: "minote://image/\(fileId)")
                } else {
                    print("[MainWindowController] 错误：无法获取 NativeEditorContext")
                }
            } else {
                // Web 编辑器模式
                print("[MainWindowController] 使用 Web 编辑器，调用 WebEditorContext.insertImage()")
                if let webContext = getCurrentWebEditorContext() {
                    webContext.insertImage("minote://image/\(fileId)", altText: url.lastPathComponent)
                } else {
                    print("[MainWindowController] 错误：无法获取 WebEditorContext")
                }
            }
        } catch {
            print("[MainWindowController] 插入图片失败: \(error.localizedDescription)")
            // 显示错误提示
            let alert = NSAlert()
            alert.messageText = "插入图片失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    /// 插入语音录音
    /// 
    /// 点击工具栏录音按钮时调用，先在光标位置插入录音模板占位符，
    /// 然后显示音频面板进入录制模式。录制完成后，更新之前插入的模板。
    /// 
    /// Requirements: 2.1 - 点击工具栏录音按钮显示音频面板并进入录制准备状态
    @objc public func insertAudioRecording(_ sender: Any?) {
        print("[MainWindowController] 插入语音录音 - 先插入模板再显示音频面板")
        
        guard let viewModel = viewModel,
              let selectedNote = viewModel.selectedNote else {
            print("[MainWindowController] ❌ 无法插入录音：没有选中的笔记")
            return
        }
        
        // 生成唯一的模板 ID
        let templateId = "recording_template_\(UUID().uuidString)"
        
        // 1. 先在编辑器光标位置插入录音模板占位符
        // 关键修复：根据当前编辑器类型选择正确的上下文
        // _Requirements: 4.1, 4.2_
        if isUsingNativeEditor {
            // 原生编辑器：插入录音模板
            if let nativeEditorContext = getCurrentNativeEditorContext() {
                nativeEditorContext.insertRecordingTemplate(templateId: templateId)
                print("[MainWindowController] ✅ 已在原生编辑器中插入录音模板: \(templateId)")
            } else {
                print("[MainWindowController] ❌ 无法获取原生编辑器上下文")
                return
            }
        } else {
            // Web 编辑器：插入录音模板
            if let webEditorContext = getCurrentWebEditorContext() {
                webEditorContext.insertRecordingTemplate(templateId: templateId)
                print("[MainWindowController] ✅ 已在 Web 编辑器中插入录音模板: \(templateId)")
            } else {
                print("[MainWindowController] ❌ 无法获取 Web 编辑器上下文")
                return
            }
        }
        
        // 2. 保存模板 ID 到状态管理器，用于后续更新
        audioPanelStateManager.currentRecordingTemplateId = templateId
        
        // 3. 显示音频面板进入录制模式
        showAudioPanelForRecording()
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
        sheetWindow.titlebarAppearsTransparent = false // 显示标题栏
        sheetWindow.titleVisibility = .visible // 显示标题
        
        // 为sheet窗口添加工具栏
        let toolbarDelegate = BaseSheetToolbarDelegate()
        toolbarDelegate.onClose = { [weak window] in
            // 关闭sheet
            window?.endSheet(sheetWindow)
        }
        
        let toolbar = NSToolbar(identifier: "HistorySheetToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = toolbarDelegate
        sheetWindow.toolbar = toolbar
        sheetWindow.toolbarStyle = .unified
        
        // 存储工具栏代理引用，防止被ARC释放
        self.historySheetToolbarDelegate = toolbarDelegate
        
        // 显示sheet
        window.beginSheet(sheetWindow) { response in
            print("历史记录sheet关闭，响应: \(response)")
            // 清理工具栏代理引用
            self.historySheetToolbarDelegate = nil
        }
        
        print("显示历史记录sheet - 完成")
    }
    
    @objc public func showTrash(_ sender: Any?) {
        print("[MainWindowController] 显示回收站sheet - 开始")
        
        guard let window = window else {
            print("[MainWindowController] 错误：主窗口不存在，无法显示回收站sheet")
            return
        }
        
        // 创建回收站视图
        let trashView = TrashView(viewModel: viewModel ?? NotesViewModel())
        
        // 创建托管控制器
        let hostingController = NSHostingController(rootView: trashView)
        
        // 创建sheet窗口
        let sheetWindow = NSWindow(contentViewController: hostingController)
        sheetWindow.styleMask = [.titled, .fullSizeContentView] // 移除.closable，隐藏右上角关闭按钮
        sheetWindow.title = "回收站"
        sheetWindow.titlebarAppearsTransparent = false // 显示标题栏
        sheetWindow.titleVisibility = .visible // 显示标题
        
        print("[MainWindowController] sheet窗口已创建: \(sheetWindow)")
        
        // 为sheet窗口添加工具栏
        let toolbarDelegate = BaseSheetToolbarDelegate()
        toolbarDelegate.onClose = { [weak window] in
            print("[MainWindowController] 工具栏关闭按钮回调被调用")
            print("[MainWindowController] 主窗口: \(String(describing: window))")
            print("[MainWindowController] sheet窗口: \(sheetWindow)")
            // 关闭sheet - 使用弱引用捕获主窗口，直接使用sheetWindow变量
            window?.endSheet(sheetWindow)
        }
        
        let toolbar = NSToolbar(identifier: "TrashSheetToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = toolbarDelegate
        sheetWindow.toolbar = toolbar
        sheetWindow.toolbarStyle = .unified
        
        // 设置窗口代理，以便正确处理窗口事件
        sheetWindow.delegate = self
        
        // 存储工具栏代理引用，防止被ARC释放
        self.trashSheetToolbarDelegate = toolbarDelegate
        
        print("[MainWindowController] 工具栏已设置，显示模式: \(toolbar.displayMode)")
        
        // 显示sheet
        window.beginSheet(sheetWindow) { response in
            print("[MainWindowController] 回收站sheet关闭，响应: \(response)")
            // 清理工具栏代理引用
            self.trashSheetToolbarDelegate = nil
        }
        
        print("[MainWindowController] 显示回收站sheet - 完成")
    }
    
    // MARK: - 笔记操作菜单动作方法

    @objc func handleNoteOperationsClick(_ sender: Any) {
        // 获取菜单
        guard let toolbarDelegate = toolbarDelegate,
              let window = window else { return }

        // 在主线程上获取菜单（确保线程安全）
        Task { @MainActor in
            let menu = toolbarDelegate.actionMenu

            // 使用鼠标当前位置
            let mouseLocation = NSEvent.mouseLocation
            menu.popUp(positioning: nil, at: mouseLocation, in: nil)
            
        }
    }

    @objc func showNoteOperationsMenu(_ sender: Any?) {
        // 保留原方法以向后兼容，但重定向到新的方法
        handleNoteOperationsClick(sender ?? self)
    }

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
    
    // MARK: - 离线操作相关动作方法
    
    @objc func processOfflineOperations(_ sender: Any?) {
        print("处理离线操作")
        
        // 检查是否有待处理的离线操作
        let processor = OfflineOperationProcessor.shared
        let offlineQueue = OfflineOperationQueue.shared
        let pendingCount = processor.failedOperations.count + offlineQueue.getPendingOperations().count
        
        if pendingCount == 0 {
            let alert = NSAlert()
            alert.messageText = "离线操作"
            alert.informativeText = "没有待处理的离线操作。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        // 询问用户是否要处理离线操作
        let alert = NSAlert()
        alert.messageText = "处理离线操作"
        alert.informativeText = "确定要处理 \(pendingCount) 个待处理的离线操作吗？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "处理")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 开始处理离线操作
            Task {
                await processor.processOperations()
            }
        }
    }
    
    @objc func showOfflineOperationsProgress(_ sender: Any?) {
        print("显示离线操作进度")
        
        // 检查是否有离线操作处理器
        guard let viewModel = viewModel else {
            let alert = NSAlert()
            alert.messageText = "离线操作进度"
            alert.informativeText = "视图模型未初始化。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        // 创建sheet窗口
        guard let window = window else {
            print("错误：主窗口不存在，无法显示离线操作进度sheet")
            return
        }
        
        // 创建离线操作进度视图，传递关闭回调
        let progressView = OfflineOperationsProgressView(
            processor: OfflineOperationProcessor.shared,
            onClose: { [weak window, weak self] in
                // 关闭sheet
                if let sheetWindow = self?.currentSheetWindow {
                    window?.endSheet(sheetWindow)
                }
            }
        )
        
        // 创建托管控制器
        let hostingController = NSHostingController(rootView: progressView)
        
        let sheetWindow = NSWindow(contentViewController: hostingController)
        sheetWindow.styleMask = [.titled, .fullSizeContentView] // 移除.closable，隐藏右上角关闭按钮
        sheetWindow.title = "离线操作进度"
        sheetWindow.titlebarAppearsTransparent = false // 显示标题栏
        sheetWindow.titleVisibility = .visible // 显示标题
        
        // 设置窗口代理，以便在用户点击关闭按钮时正确处理
        sheetWindow.delegate = self
        
        // 为sheet窗口添加独立的工具栏代理
        let toolbarDelegate = BaseSheetToolbarDelegate()
        toolbarDelegate.onClose = { [weak window, weak self] in
            // 关闭sheet
            if let sheetWindow = self?.currentSheetWindow {
                window?.endSheet(sheetWindow)
            }
        }
        
        let toolbar = NSToolbar(identifier: "OfflineOperationsProgressToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = toolbarDelegate
        sheetWindow.toolbar = toolbar
        sheetWindow.toolbarStyle = .unified
        
        // 存储当前sheet窗口引用和工具栏代理引用
        self.currentSheetWindow = sheetWindow
        self.currentSheetToolbarDelegate = toolbarDelegate
        
        // 显示sheet
        window.beginSheet(sheetWindow) { response in
            print("离线操作进度sheet关闭，响应: \(response)")
            // 清理sheet窗口引用和工具栏代理引用
            self.currentSheetWindow = nil
            self.currentSheetToolbarDelegate = nil
        }
    }
    
    @objc func retryFailedOperations(_ sender: Any?) {
        print("重试失败的操作")
        
        // 检查是否有失败的离线操作
        let processor = OfflineOperationProcessor.shared
        let failedCount = processor.failedOperations.count
        
        if failedCount == 0 {
            let alert = NSAlert()
            alert.messageText = "重试失败的操作"
            alert.informativeText = "没有失败的操作需要重试。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        // 询问用户是否要重试失败的操作
        let alert = NSAlert()
        alert.messageText = "重试失败的操作"
        alert.informativeText = "确定要重试 \(failedCount) 个失败的操作吗？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "重试")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 重试失败的操作
            Task {
                await processor.retryFailedOperations()
            }
        }
    }
    
    // MARK: - 锁定私密笔记动作
    
    @objc func lockPrivateNotes(_ sender: Any?) {
        print("锁定私密笔记")
        
        // 锁定私密笔记
        viewModel?.isPrivateNotesUnlocked = false
        
        // 可选：清空选中的笔记
        viewModel?.selectedNote = nil
        
        // 显示提示信息
        let alert = NSAlert()
        alert.messageText = "私密笔记已锁定"
        alert.informativeText = "私密笔记已锁定，需要重新输入密码才能访问。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
        
        // 刷新工具栏验证
        makeToolbarValidate()
    }
    
    // MARK: - 侧边栏切换
    
    @objc func toggleSidebar(_ sender: Any?) {
        guard let window = window,
              let splitViewController = window.contentViewController as? NSSplitViewController,
              splitViewController.splitViewItems.count > 0 else {
            return
        }
        
        let sidebarItem = splitViewController.splitViewItems[0]
        let isCurrentlyCollapsed = sidebarItem.isCollapsed
        
        // 切换侧边栏状态
        sidebarItem.animator().isCollapsed = !isCurrentlyCollapsed
    }
    
    // MARK: - 格式菜单
    
    @objc func showFormatMenu(_ sender: Any?) {
        // 显示格式菜单popover
        print("显示格式菜单")
        print("  - isUsingNativeEditor: \(isUsingNativeEditor)")
        
        // 如果popover已经显示，则关闭它
        if let popover = formatMenuPopover, popover.isShown {
            popover.performClose(sender)
            formatMenuPopover = nil
            return
        }
        
        // 根据编辑器类型创建对应的格式菜单视图
        // 需求: 2.1, 2.2 - 根据编辑器类型创建 NativeFormatMenuView 或 WebFormatMenuView
        let hostingController: NSViewController
        let contentSize: NSSize
        
        if isUsingNativeEditor {
            // 使用原生编辑器时，显示 NativeFormatMenuView
            guard let nativeEditorContext = getCurrentNativeEditorContext() else {
                print("无法获取 NativeEditorContext")
                return
            }
            
            print("  - 使用原生编辑器格式菜单")
            
            // 请求内容同步并更新格式状态
            nativeEditorContext.requestContentSync()
            
            let formatMenuView = NativeFormatMenuView(context: nativeEditorContext) { [weak self] _ in
                // 格式操作完成后关闭popover
                self?.formatMenuPopover?.performClose(nil)
                self?.formatMenuPopover = nil
            }
            
            hostingController = NSHostingController(rootView: AnyView(formatMenuView))
            contentSize = NSSize(width: 280, height: 450)
        } else {
            // 使用 Web 编辑器时，显示 WebFormatMenuView
            guard let webEditorContext = getCurrentWebEditorContext() else {
                print("无法获取 WebEditorContext")
                return
            }
            
            print("  - 使用 Web 编辑器格式菜单")
            
            let formatMenuView = WebFormatMenuView(context: webEditorContext) { [weak self] _ in
                // 格式操作完成后关闭popover
                self?.formatMenuPopover?.performClose(nil)
                self?.formatMenuPopover = nil
            }
            
            hostingController = NSHostingController(rootView: AnyView(formatMenuView))
            contentSize = NSSize(width: 200, height: 400)
        }
        
        // 设置托管控制器的视图大小
        hostingController.view.frame = NSRect(origin: .zero, size: contentSize)
        
        // 创建popover
        let popover = NSPopover()
        popover.contentSize = contentSize
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
    
    // MARK: - 视图选项菜单
    
    /// 显示视图选项菜单（已弃用，改用原生 NSMenu）
    /// _Requirements: 1.2, 1.3, 1.4_
    @objc func showViewOptionsMenu(_ sender: Any?) {
        print("显示视图选项菜单（已弃用）")
        // 此方法已弃用，视图选项菜单现在使用原生 NSMenuToolbarItem
    }
    
    // MARK: - 视图选项菜单操作
    
    /// 设置排序方式为编辑时间
    /// _Requirements: 2.3_
    @objc func setSortOrderEditDate(_ sender: Any?) {
        ViewOptionsManager.shared.setSortOrder(.editDate)
        viewModel?.setNotesListSortField(.editDate)
    }
    
    /// 设置排序方式为创建时间
    /// _Requirements: 2.3_
    @objc func setSortOrderCreateDate(_ sender: Any?) {
        ViewOptionsManager.shared.setSortOrder(.createDate)
        viewModel?.setNotesListSortField(.createDate)
    }
    
    /// 设置排序方式为标题
    /// _Requirements: 2.3_
    @objc func setSortOrderTitle(_ sender: Any?) {
        ViewOptionsManager.shared.setSortOrder(.title)
        viewModel?.setNotesListSortField(.title)
        // 按标题排序时，自动关闭日期分组（因为日期分组对标题排序没有意义）
        if ViewOptionsManager.shared.isDateGroupingEnabled {
            ViewOptionsManager.shared.setDateGrouping(false)
        }
    }
    
    /// 设置排序方向为降序
    /// _Requirements: 2.7_
    @objc func setSortDirectionDescending(_ sender: Any?) {
        ViewOptionsManager.shared.setSortDirection(.descending)
        viewModel?.setNotesListSortDirection(.descending)
    }
    
    /// 设置排序方向为升序
    /// _Requirements: 2.7_
    @objc func setSortDirectionAscending(_ sender: Any?) {
        ViewOptionsManager.shared.setSortDirection(.ascending)
        viewModel?.setNotesListSortDirection(.ascending)
    }
    
    /// 切换日期分组（已弃用，改用 setDateGroupingOn/Off）
    /// _Requirements: 3.3, 3.4_
    @objc func toggleDateGrouping(_ sender: Any?) {
        ViewOptionsManager.shared.toggleDateGrouping()
    }
    
    /// 开启日期分组
    /// _Requirements: 3.3_
    @objc func setDateGroupingOn(_ sender: Any?) {
        // 如果当前是按标题排序，自动切换到按编辑时间排序
        // 因为按标题排序时日期分组没有意义
        if ViewOptionsManager.shared.sortOrder == .title {
            ViewOptionsManager.shared.setSortOrder(.editDate)
            viewModel?.setNotesListSortField(.editDate)
        }
        ViewOptionsManager.shared.setDateGrouping(true)
    }
    
    /// 关闭日期分组
    /// _Requirements: 3.4_
    @objc func setDateGroupingOff(_ sender: Any?) {
        ViewOptionsManager.shared.setDateGrouping(false)
    }
    
    /// 设置视图模式为列表视图
    /// _Requirements: 4.3_
    @objc func setViewModeList(_ sender: Any?) {
        ViewOptionsManager.shared.setViewMode(.list)
    }
    
    /// 设置视图模式为画廊视图
    /// _Requirements: 4.3_
    @objc func setViewModeGallery(_ sender: Any?) {
        ViewOptionsManager.shared.setViewMode(.gallery)
    }
    
    /// 返回画廊视图
    /// 从画廊视图的笔记编辑模式返回到画廊网格视图
    @objc func backToGallery(_ sender: Any?) {
        print("[MainWindowController] 返回画廊视图")
        // 发送通知让 SwiftUI 视图收起展开的笔记
        NotificationCenter.default.post(name: .backToGalleryRequested, object: nil)
    }
    
    /// 获取当前的WebEditorContext
    private func getCurrentWebEditorContext() -> WebEditorContext? {
        // 直接从viewModel获取共享的WebEditorContext
        return viewModel?.webEditorContext
    }
    
    // MARK: - 编辑器类型检测和路由
    
    /// 是否正在使用原生编辑器
    /// 需求: 7.1 - 通过 EditorPreferencesService.shared.selectedEditorType 判断
    public var isUsingNativeEditor: Bool {
        return EditorPreferencesService.shared.selectedEditorType == .native
    }
    
    /// 获取当前的 NativeEditorContext
    /// 需求: 1.3, 7.2 - 从 viewModel 获取 nativeEditorContext
    /// - Returns: 当前的 NativeEditorContext，如果 viewModel 不存在则返回 nil
    public func getCurrentNativeEditorContext() -> NativeEditorContext? {
        return viewModel?.nativeEditorContext
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
        print("[MainWindowController] 增加缩进")
        
        // 需求 6.5: 检查是否有选中笔记
        guard viewModel?.selectedNote != nil else {
            print("[MainWindowController] 没有选中笔记，无法增加缩进")
            return
        }
        
        // 需求 6.1, 6.3: 根据编辑器类型调用对应的方法
        if isUsingNativeEditor {
            // 需求 6.1: 原生编辑器模式
            print("[MainWindowController] 使用原生编辑器，调用 NativeEditorContext.increaseIndent()")
            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.increaseIndent()
            } else {
                print("[MainWindowController] 错误：无法获取 NativeEditorContext")
            }
        } else {
            // 需求 6.3: Web 编辑器模式
            print("[MainWindowController] 使用 Web 编辑器，调用 WebEditorContext.increaseIndent()")
            if let webContext = getCurrentWebEditorContext() {
                webContext.increaseIndent()
            } else {
                print("[MainWindowController] 错误：无法获取 WebEditorContext")
            }
        }
    }
    
    @objc public func decreaseIndent(_ sender: Any?) {
        print("[MainWindowController] 减少缩进")
        
        // 需求 6.5: 检查是否有选中笔记
        guard viewModel?.selectedNote != nil else {
            print("[MainWindowController] 没有选中笔记，无法减少缩进")
            return
        }
        
        // 需求 6.2, 6.4: 根据编辑器类型调用对应的方法
        if isUsingNativeEditor {
            // 需求 6.2: 原生编辑器模式
            print("[MainWindowController] 使用原生编辑器，调用 NativeEditorContext.decreaseIndent()")
            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.decreaseIndent()
            } else {
                print("[MainWindowController] 错误：无法获取 NativeEditorContext")
            }
        } else {
            // 需求 6.4: Web 编辑器模式
            print("[MainWindowController] 使用 Web 编辑器，调用 WebEditorContext.decreaseIndent()")
            if let webContext = getCurrentWebEditorContext() {
                webContext.decreaseIndent()
            } else {
                print("[MainWindowController] 错误：无法获取 WebEditorContext")
            }
        }
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
    
    // MARK: - 格式菜单动作（Apple Notes 风格）
    
    /// 切换块引用
    /// - Requirements: 4.9
    @objc public func toggleBlockQuote(_ sender: Any?) {
        print("切换块引用")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "块引用")
    }
    
    // MARK: - 核对清单动作
    
    /// 标记为已勾选
    /// - Requirements: 5.2
    @objc public func markAsChecked(_ sender: Any?) {
        print("标记为已勾选")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "标记为已勾选")
    }
    
    /// 全部勾选
    /// - Requirements: 5.4
    @objc public func checkAll(_ sender: Any?) {
        print("全部勾选")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "全部勾选")
    }
    
    /// 全部取消勾选
    /// - Requirements: 5.5
    @objc public func uncheckAll(_ sender: Any?) {
        print("全部取消勾选")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "全部取消勾选")
    }
    
    /// 将勾选的项目移到底部
    /// - Requirements: 5.6
    @objc public func moveCheckedToBottom(_ sender: Any?) {
        print("将勾选的项目移到底部")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "将勾选的项目移到底部")
    }
    
    /// 删除已勾选项目
    /// - Requirements: 5.7
    @objc public func deleteCheckedItems(_ sender: Any?) {
        print("删除已勾选项目")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "删除已勾选项目")
    }
    
    /// 向上移动项目
    /// - Requirements: 5.10
    @objc public func moveItemUp(_ sender: Any?) {
        print("向上移动项目")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "向上移动项目")
    }
    
    /// 向下移动项目
    /// - Requirements: 5.11
    @objc public func moveItemDown(_ sender: Any?) {
        print("向下移动项目")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "向下移动项目")
    }
    
    // MARK: - 外观动作
    
    /// 切换浅色背景
    /// - Requirements: 6.2
    @objc public func toggleLightBackground(_ sender: Any?) {
        print("切换浅色背景")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "浅色背景")
    }
    
    /// 切换高亮
    /// - Requirements: 6.9
    @objc public func toggleHighlight(_ sender: Any?) {
        print("切换高亮")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "高亮")
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

    // MARK: - 查找功能

    /// 显示查找面板
    @objc public func showFindPanel(_ sender: Any?) {
        searchPanelController?.showSearchPanel()
    }

    /// 查找下一个匹配项
    @objc public func findNext(_ sender: Any?) {
        searchPanelController?.findNext()
    }

    /// 查找上一个匹配项
    @objc public func findPrevious(_ sender: Any?) {
        searchPanelController?.findPrevious()
    }

    /// 显示查找和替换面板
    @objc public func showFindAndReplacePanel(_ sender: Any?) {
        searchPanelController?.showSearchPanel()
    }
    
    // MARK: - 附件操作
    
    /// 附加文件到当前笔记
    /// - Requirements: 3.12
    /// - Parameter url: 文件 URL
    @objc public func attachFile(_ url: URL) {
        print("[MainWindowController] 附加文件: \(url.path)")
        
        // 检查是否有选中笔记
        guard viewModel?.selectedNote != nil else {
            print("[MainWindowController] 没有选中笔记，无法附加文件")
            return
        }
        
        // 根据文件类型处理
        let fileExtension = url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        
        if imageExtensions.contains(fileExtension) {
            // 图片文件：使用现有的图片插入功能
            Task { @MainActor in
                await self.insertImage(from: url)
            }
        } else {
            // 其他文件：显示提示（功能待实现）
            let alert = NSAlert()
            alert.messageText = "功能开发中"
            alert.informativeText = "非图片文件的附件功能正在开发中，敬请期待。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    /// 添加链接到当前笔记
    /// - Requirements: 3.13
    /// - Parameter urlString: 链接地址
    @objc public func addLink(_ urlString: String) {
        print("[MainWindowController] 添加链接: \(urlString)")
        
        // 检查是否有选中笔记
        guard viewModel?.selectedNote != nil else {
            print("[MainWindowController] 没有选中笔记，无法添加链接")
            return
        }
        
        // 验证 URL 格式
        guard let url = URL(string: urlString), url.scheme != nil else {
            let alert = NSAlert()
            alert.messageText = "无效的链接"
            alert.informativeText = "请输入有效的链接地址（例如：https://example.com）"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        // 链接插入功能待实现
        // TODO: 根据编辑器类型插入链接
        print("[MainWindowController] 链接插入功能待实现: \(urlString)")
        
        let alert = NSAlert()
        alert.messageText = "功能开发中"
        alert.informativeText = "链接插入功能正在开发中，敬请期待。\n\n链接地址：\(urlString)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
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

        // 监听选中文件夹变化，更新工具栏
        viewModel.$selectedFolder
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // 当选中文件夹变化时，重新配置工具栏以显示/隐藏锁图标
                self?.reconfigureToolbar()
            }
            .store(in: &cancellables)

        // 监听私密笔记解锁状态变化，更新工具栏
        viewModel.$isPrivateNotesUnlocked
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // 当私密笔记解锁状态变化时，重新配置工具栏以显示/隐藏锁图标
                self?.reconfigureToolbar()
            }
            .store(in: &cancellables)

        // 监听搜索文本变化，同步到搜索框UI并更新窗口标题
        viewModel.$searchText
            .receive(on: RunLoop.main)
            .sink { [weak self] searchText in
                // 当ViewModel的searchText变化时，更新搜索框的UI
                if let searchField = self?.currentSearchField,
                   searchField.stringValue != searchText {
                    searchField.stringValue = searchText
                }

                // 更新窗口标题和副标题
                self?.updateWindowTitle(for: viewModel.selectedFolder)
            }
            .store(in: &cancellables)

        // 监听来自设置视图的通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowLoginView"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[MainWindowController] 收到ShowLoginView通知，显示登录窗口")
            self?.showLogin(nil)
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowCookieRefreshView"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[MainWindowController] 收到ShowCookieRefreshView通知，显示Cookie刷新窗口")
            self?.showCookieRefresh(nil)
        }
        
        // 监听音频面板可见性变化
        // Requirements: 1.1, 1.3
        NotificationCenter.default.addObserver(
            forName: AudioPanelStateManager.visibilityDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let visible = notification.userInfo?["visible"] as? Bool else { return }
            print("[MainWindowController] 收到音频面板可见性变化通知: \(visible)")
            if visible {
                self?.showAudioPanel()
            } else {
                self?.hideAudioPanel()
            }
        }
        
        // 监听音频面板需要确认对话框通知
        // Requirements: 2.5, 5.2
        NotificationCenter.default.addObserver(
            forName: AudioPanelStateManager.needsConfirmationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[MainWindowController] 收到音频面板需要确认通知")
            self?.showAudioPanelCloseConfirmation()
        }
        
        // 监听音频附件点击通知
        // Requirements: 2.2
        NotificationCenter.default.addObserver(
            forName: .audioAttachmentClicked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let fileId = NotificationCenter.extractAudioFileId(from: notification) else {
                print("[MainWindowController] ❌ 收到音频附件点击通知但缺少 fileId")
                return
            }
            print("[MainWindowController] 收到音频附件点击通知: fileId=\(fileId)")
            self?.showAudioPanelForPlayback(fileId: fileId)
        }
        
        print("[MainWindowController] 状态监听器已设置")
    }
    
    /// 重新配置工具栏
    private func reconfigureToolbar() {
        // 简单的方法：只验证工具栏项，让工具栏根据toolbarDefaultItemIdentifiers动态更新
        makeToolbarValidate()
    }
    
    /// 更新窗口标题和副标题
    private func updateWindowTitle(for folder: Folder?) {
        guard let window = window, let viewModel = viewModel else { return }
        
        // 检查是否有搜索文本
        if !viewModel.searchText.isEmpty {
            // 搜索状态：取消选中文件夹，标题改为"搜索"
            viewModel.selectedFolder = nil
            window.title = "搜索"
            
            // 副标题显示找到的笔记数量
            let foundCount = viewModel.filteredNotes.count
            window.subtitle = "找到\(foundCount)个笔记"
        } else {
            // 正常状态：设置主标题为选中的文件夹名称
            let folderName = folder?.name ?? "笔记"
            window.title = folderName
            
            // 计算当前文件夹中的笔记数量
            let noteCount = getNoteCount(for: folder)
            
            // 设置副标题为笔记数量
            window.subtitle = "\(noteCount)个笔记"
        }
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
    
    // MARK: - 搜索框菜单
    
    /// 为搜索框设置下拉菜单（使用SwiftUI popover）
    private func setupSearchFieldMenu(for searchField: NSSearchField) {
        print("[MainWindowController] 设置搜索框菜单（SwiftUI popover）")
        
        // 设置搜索框属性以确保菜单正确工作
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = true
        
        // 移除旧的NSMenu设置，因为我们使用popover
        searchField.menu = nil
        
        // 设置搜索框的点击事件处理 - 按Enter时执行搜索，而不是弹出菜单
        searchField.target = self
        searchField.action = #selector(performSearch(_:))
        
        // 重要：确保搜索框有正确的行为设置
        searchField.bezelStyle = .roundedBezel
        searchField.controlSize = .regular
        
        // 添加调试日志
        print("[MainWindowController] 搜索框菜单已设置为使用SwiftUI popover，搜索框: \(searchField)")
    }
    
    
    
    // MARK: - 搜索筛选菜单动作
    
    @objc func showSearchFilterMenu(_ sender: Any?) {
        print("[MainWindowController] 显示搜索筛选菜单 - 开始")
        
        // 如果popover已经显示，则关闭它
        if let popover = searchFilterMenuPopover, popover.isShown {
            print("[MainWindowController] popover已经显示，关闭它")
            popover.performClose(sender)
            searchFilterMenuPopover = nil
            return
        }
        
        // 确保有viewModel
        guard let viewModel = viewModel else {
            print("[MainWindowController] 错误：viewModel不存在")
            return
        }
        
        print("[MainWindowController] 创建SwiftUI搜索筛选菜单视图")
        
        // 创建SwiftUI搜索筛选菜单视图
        let searchFilterMenuView = SearchFilterMenuContent(viewModel: viewModel)
        
        // 创建托管控制器
        let hostingController = NSHostingController(rootView: searchFilterMenuView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 200, height: 190)
        
        print("[MainWindowController] 创建popover")
        
        // 创建popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 200, height: 190)
        // 使用.semitransient行为，这样用户与搜索框交互时不会自动关闭
        popover.behavior = .semitransient
        popover.animates = true
        popover.contentViewController = hostingController
        
        // 存储popover引用
        searchFilterMenuPopover = popover
        
        // 显示popover
        if let searchField = sender as? NSSearchField {
            print("[MainWindowController] 显示popover在搜索框: \(searchField)")
            
            // 方案三：参考格式菜单的实现，使用.maxY并调整positioningRect
            // 格式菜单使用.maxY显示在按钮上方，搜索框也应该类似
            
            // 获取搜索框的bounds
            let bounds = searchField.bounds
            print("[MainWindowController] 搜索框bounds: \(bounds)")
            
            // 创建一个positioningRect，使用搜索框的bounds
            let positioningRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            
            // 使用.maxY（显示在搜索框上方），与格式菜单保持一致
            popover.show(relativeTo: positioningRect, of: searchField, preferredEdge: .maxY)
            print("[MainWindowController] popover显示完成（使用.maxY边缘，与格式菜单一致）")
        } else if let window = window, let contentView = window.contentView {
            print("[MainWindowController] 显示popover在窗口中央")
            // 如果没有搜索框，显示在窗口中央
            popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxY)
        } else {
            print("[MainWindowController] 错误：无法显示popover，没有搜索框或窗口")
        }
    }
    
    /// 检查是否有任何筛选选项被启用
    private func hasAnySearchFilter() -> Bool {
        guard let viewModel = viewModel else { return false }
        
        return viewModel.searchFilterHasTags ||
               viewModel.searchFilterHasChecklist ||
               viewModel.searchFilterHasImages ||
               viewModel.searchFilterHasAudio ||
               viewModel.searchFilterIsPrivate
    }
    
    /// 清除所有筛选选项
    private func clearAllSearchFilters() {
        viewModel?.searchFilterHasTags = false
        viewModel?.searchFilterHasChecklist = false
        viewModel?.searchFilterHasImages = false
        viewModel?.searchFilterHasAudio = false
        viewModel?.searchFilterIsPrivate = false
    }
    
    // MARK: - 显示菜单动作（Requirements: 10.1-10.4, 11.1-11.5）
    
    /// 放大
    /// - Requirements: 10.2
    @objc public func zoomIn(_ sender: Any?) {
        print("[MainWindowController] 放大")
        
        // 根据编辑器类型调用对应的缩放方法
        if isUsingNativeEditor {
            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.zoomIn()
            } else {
                print("[MainWindowController] 错误：无法获取 NativeEditorContext")
            }
        } else {
            if let webContext = getCurrentWebEditorContext() {
                webContext.zoomIn()
            } else {
                print("[MainWindowController] 错误：无法获取 WebEditorContext")
            }
        }
    }
    
    /// 缩小
    /// - Requirements: 10.3
    @objc public func zoomOut(_ sender: Any?) {
        print("[MainWindowController] 缩小")
        
        // 根据编辑器类型调用对应的缩放方法
        if isUsingNativeEditor {
            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.zoomOut()
            } else {
                print("[MainWindowController] 错误：无法获取 NativeEditorContext")
            }
        } else {
            if let webContext = getCurrentWebEditorContext() {
                webContext.zoomOut()
            } else {
                print("[MainWindowController] 错误：无法获取 WebEditorContext")
            }
        }
    }
    
    /// 实际大小
    /// - Requirements: 10.4
    @objc public func actualSize(_ sender: Any?) {
        print("[MainWindowController] 实际大小")
        
        // 根据编辑器类型调用对应的重置缩放方法
        if isUsingNativeEditor {
            if let nativeContext = getCurrentNativeEditorContext() {
                nativeContext.resetZoom()
            } else {
                print("[MainWindowController] 错误：无法获取 NativeEditorContext")
            }
        } else {
            if let webContext = getCurrentWebEditorContext() {
                webContext.resetZoom()
            } else {
                print("[MainWindowController] 错误：无法获取 WebEditorContext")
            }
        }
    }
    
    /// 展开区域
    /// - Requirements: 11.2
    @objc public func expandSection(_ sender: Any?) {
        print("[MainWindowController] 展开区域")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "展开区域")
    }
    
    /// 展开所有区域
    /// - Requirements: 11.3
    @objc public func expandAllSections(_ sender: Any?) {
        print("[MainWindowController] 展开所有区域")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "展开所有区域")
    }
    
    /// 折叠区域
    /// - Requirements: 11.4
    @objc public func collapseSection(_ sender: Any?) {
        print("[MainWindowController] 折叠区域")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "折叠区域")
    }
    
    /// 折叠所有区域
    /// - Requirements: 11.5
    @objc public func collapseAllSections(_ sender: Any?) {
        print("[MainWindowController] 折叠所有区域")
        // 功能尚未实现，显示提示
        showFeatureNotImplementedAlert(featureName: "折叠所有区域")
    }
    
    // MARK: - 音频面板方法
    // Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.3, 2.5
    
    /// 显示音频面板
    ///
    /// 在主窗口右侧添加第四栏显示音频面板。
    /// 如果当前是画廊模式，则不显示音频面板。
    ///
    /// Requirements: 1.1, 1.2, 1.4, 1.5
    private func showAudioPanel() {
        guard let window = window,
              let splitViewController = window.contentViewController as? NSSplitViewController,
              let viewModel = viewModel else {
            print("[MainWindowController] ❌ 无法显示音频面板：窗口或分割视图控制器不存在")
            return
        }
        
        // 检查是否是画廊模式，画廊模式下不支持音频面板
        if ViewOptionsManager.shared.viewMode == .gallery {
            print("[MainWindowController] ⚠️ 画廊模式下不支持音频面板")
            return
        }
        
        // 检查是否已经显示了音频面板（四栏布局）
        if splitViewController.splitViewItems.count >= 4 {
            print("[MainWindowController] ⚠️ 音频面板已经显示")
            return
        }
        
        // 确保当前是三栏布局
        guard splitViewController.splitViewItems.count == 3 else {
            print("[MainWindowController] ❌ 当前不是三栏布局，无法添加音频面板")
            return
        }
        
        print("[MainWindowController] 显示音频面板")
        
        // 创建音频面板托管控制器
        let audioPanelController = AudioPanelHostingController(
            stateManager: audioPanelStateManager,
            viewModel: viewModel
        )
        
        // 设置录制完成回调
        audioPanelController.onRecordingComplete = { [weak self] url in
            self?.handleAudioRecordingComplete(url: url)
        }
        
        // 设置关闭回调
        audioPanelController.onClose = { [weak self] in
            self?.audioPanelStateManager.hide()
        }
        
        // 保存引用
        self.audioPanelHostingController = audioPanelController
        
        // 创建分割视图项
        // Requirements: 1.4 - 最小宽度 280 像素，最大宽度 400 像素
        let audioPanelSplitViewItem = NSSplitViewItem(viewController: audioPanelController)
        audioPanelSplitViewItem.minimumThickness = 280
        audioPanelSplitViewItem.maximumThickness = 400
        audioPanelSplitViewItem.canCollapse = false
        
        // Requirements: 1.5 - 设置 holdingPriority 确保优先压缩编辑器
        // 音频面板的 holdingPriority 设置为 252，高于编辑器的 250
        // 这样窗口缩小时会优先压缩编辑器而非音频面板
        audioPanelSplitViewItem.holdingPriority = NSLayoutConstraint.Priority(252)
        
        // 添加到分割视图控制器作为第四栏
        splitViewController.addSplitViewItem(audioPanelSplitViewItem)
        
        // 让音频面板成为第一响应者，以便接收键盘事件（如 Escape 键）
        // Requirements: 2.4
        DispatchQueue.main.async {
            window.makeFirstResponder(audioPanelController)
        }
        
        print("[MainWindowController] ✅ 音频面板已添加，当前栏数: \(splitViewController.splitViewItems.count)")
    }
    
    /// 隐藏音频面板
    ///
    /// 从主窗口移除第四栏，恢复三栏布局。
    ///
    /// Requirements: 1.3, 2.3
    private func hideAudioPanel() {
        guard let window = window,
              let splitViewController = window.contentViewController as? NSSplitViewController else {
            print("[MainWindowController] ❌ 无法隐藏音频面板：窗口或分割视图控制器不存在")
            return
        }
        
        // 检查是否有第四栏（音频面板）
        guard splitViewController.splitViewItems.count >= 4 else {
            print("[MainWindowController] ⚠️ 音频面板未显示，无需隐藏")
            return
        }
        
        print("[MainWindowController] 隐藏音频面板")
        
        // 移除第四栏（音频面板）
        let audioPanelItem = splitViewController.splitViewItems[3]
        splitViewController.removeSplitViewItem(audioPanelItem)
        
        // 清除引用
        audioPanelHostingController = nil
        
        print("[MainWindowController] ✅ 音频面板已移除，当前栏数: \(splitViewController.splitViewItems.count)")
    }
    
    /// 显示音频面板关闭确认对话框
    ///
    /// 当用户在录制过程中尝试关闭面板时显示确认对话框。
    ///
    /// Requirements: 2.5, 5.2
    private func showAudioPanelCloseConfirmation() {
        guard let window = window else { return }
        
        let alert = NSAlert()
        alert.messageText = "正在录制中"
        alert.informativeText = "您正在录制语音，是否要保存当前录制内容？"
        alert.alertStyle = .warning
        
        // 添加按钮
        alert.addButton(withTitle: "保存并关闭")
        alert.addButton(withTitle: "放弃录制")
        alert.addButton(withTitle: "取消")
        
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                // 保存并关闭
                print("[MainWindowController] 用户选择保存并关闭")
                // 停止录制并保存
                if let url = AudioRecorderService.shared.stopRecording() {
                    self?.handleAudioRecordingComplete(url: url)
                }
                self?.audioPanelStateManager.forceHide()
                
            case .alertSecondButtonReturn:
                // 放弃录制
                print("[MainWindowController] 用户选择放弃录制")
                AudioRecorderService.shared.cancelRecording()
                self?.audioPanelStateManager.forceHide()
                
            default:
                // 取消，不做任何操作
                print("[MainWindowController] 用户取消关闭操作")
            }
        }
    }
    
    /// 处理音频录制完成
    ///
    /// 上传音频文件并更新之前插入的录音模板为实际的音频附件。
    ///
    /// Requirements: 3.5, 5.3
    private func handleAudioRecordingComplete(url: URL) {
        print("[MainWindowController] 处理录制完成: \(url)")
        
        guard let viewModel = viewModel,
              let selectedNote = viewModel.selectedNote else {
            print("[MainWindowController] ❌ 无法处理录制完成：没有选中的笔记")
            return
        }
        
        // 获取模板 ID
        let templateId = audioPanelStateManager.currentRecordingTemplateId
        
        // 异步上传音频文件
        Task { @MainActor in
            do {
                print("[MainWindowController] 🎤 开始上传音频文件...")
                
                // 更新模板状态为上传中
                if let templateId = templateId {
                    audioPanelStateManager.setTemplateUploading(templateId: templateId)
                }
                
                // 1. 上传音频文件到服务器
                let uploadResult = try await AudioUploadService.shared.uploadAudio(fileURL: url)
                
                print("[MainWindowController] ✅ 音频上传成功: fileId=\(uploadResult.fileId), digest=\(uploadResult.digest ?? "nil"), mimeType=\(uploadResult.mimeType ?? "nil")")
                
                // 1.5. 更新笔记的 setting.data，添加音频信息
                // 这是小米笔记服务器识别音频文件的关键
                if var note = viewModel.selectedNote {
                    var rawData = note.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [
                        "themeId": 0,
                        "stickyTime": 0,
                        "version": 0
                    ]
                    
                    var settingData = setting["data"] as? [[String: Any]] ?? []
                    
                    // 构建音频元数据（与图片格式一致）
                    // digest 格式：{sha1}.mp3
                    let audioInfo: [String: Any] = [
                        "fileId": uploadResult.fileId,
                        "mimeType": uploadResult.mimeType ?? "audio/mpeg",
                        "digest": (uploadResult.digest ?? uploadResult.fileId) + ".mp3"
                    ]
                    settingData.append(audioInfo)
                    setting["data"] = settingData
                    rawData["setting"] = setting
                    note.rawData = rawData
                    
                    print("[MainWindowController] 已更新笔记 setting.data，添加音频: \(audioInfo)")
                    
                    // 更新 viewModel 中的笔记
                    viewModel.selectedNote = note
                    if let index = viewModel.notes.firstIndex(where: { $0.id == note.id }) {
                        viewModel.notes[index] = note
                    }
                }
                
                // 2. 检查是否有录音模板需要更新
                if let templateId = templateId {
                    // 更新模板状态为更新中
                    audioPanelStateManager.setTemplateUpdating(templateId: templateId, fileId: uploadResult.fileId)
                    
                    // 有录音模板：根据编辑器类型更新模板并强制保存
                    // 关键修复：根据当前编辑器类型选择正确的上下文
                    // _Requirements: 4.3_
                    if self.isUsingNativeEditor {
                        // 原生编辑器：使用强制保存方法
                        if let nativeEditorContext = self.getCurrentNativeEditorContext() {
                            try await nativeEditorContext.updateRecordingTemplateAndSave(
                                templateId: templateId,
                                fileId: uploadResult.fileId,
                                digest: uploadResult.digest,
                                mimeType: uploadResult.mimeType
                            )
                            print("[MainWindowController] ✅ 原生编辑器录音模板已更新并保存: \(templateId) -> \(uploadResult.fileId)")
                        } else {
                            print("[MainWindowController] ⚠️ 无法获取原生编辑器上下文，录音模板未更新")
                            self.audioPanelStateManager.setTemplateFailed(templateId: templateId, error: "无法获取原生编辑器上下文")
                        }
                    } else {
                        // Web 编辑器：使用强制保存方法
                        if let webEditorContext = self.getCurrentWebEditorContext() {
                            try await webEditorContext.updateRecordingTemplateAndSave(
                                templateId: templateId,
                                fileId: uploadResult.fileId,
                                digest: uploadResult.digest,
                                mimeType: uploadResult.mimeType
                            )
                            print("[MainWindowController] ✅ Web编辑器录音模板已更新并保存: \(templateId) -> \(uploadResult.fileId)")
                        } else {
                            print("[MainWindowController] ⚠️ 无法获取 Web 编辑器上下文，录音模板未更新")
                            self.audioPanelStateManager.setTemplateFailed(templateId: templateId, error: "无法获取 Web 编辑器上下文")
                        }
                    }
                    
                    // 更新模板状态为完成
                    audioPanelStateManager.setTemplateCompleted(templateId: templateId, fileId: uploadResult.fileId)
                } else {
                    // 没有录音模板：使用传统方式插入音频附件
                    // 关键修复：根据当前编辑器类型选择正确的上下文
                    if self.isUsingNativeEditor {
                        if let nativeEditorContext = self.getCurrentNativeEditorContext() {
                            nativeEditorContext.insertAudio(
                                fileId: uploadResult.fileId,
                                digest: uploadResult.digest,
                                mimeType: uploadResult.mimeType
                            )
                            print("[MainWindowController] ✅ 音频附件已插入到原生编辑器")
                        } else {
                            print("[MainWindowController] ⚠️ 无法获取原生编辑器上下文，音频附件未插入")
                        }
                    } else {
                        if let webEditorContext = self.getCurrentWebEditorContext() {
                            webEditorContext.insertAudio(
                                fileId: uploadResult.fileId,
                                digest: uploadResult.digest,
                                mimeType: uploadResult.mimeType
                            )
                            print("[MainWindowController] ✅ 音频附件已插入到Web编辑器")
                        } else {
                            print("[MainWindowController] ⚠️ 无法获取 Web 编辑器上下文，音频附件未插入")
                        }
                    }
                }
                
                // 3. 关闭音频面板
                audioPanelStateManager.forceHide()
                
                // 4. 删除临时文件
                try? FileManager.default.removeItem(at: url)
                print("[MainWindowController] 🗑️ 临时文件已删除")
                
            } catch {
                print("[MainWindowController] ❌ 音频上传失败: \(error.localizedDescription)")
                
                // 更新模板状态为失败
                if let templateId = templateId {
                    audioPanelStateManager.setTemplateFailed(templateId: templateId, error: error.localizedDescription)
                }
                
                // 显示错误提示
                await showAudioUploadErrorAlert(error: error)
            }
        }
    }
    
    /// 显示功能尚未实现的提示
    ///
    /// 用于未实现的菜单功能，向用户显示友好的提示信息
    ///
    /// - Parameter featureName: 功能名称
    private func showFeatureNotImplementedAlert(featureName: String) {
        guard let window = window else { return }
        
        let alert = NSAlert()
        alert.messageText = "功能尚未实现"
        alert.informativeText = "「\(featureName)」功能正在开发中，敬请期待。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        
        alert.beginSheetModal(for: window) { _ in }
    }
    
    /// 显示音频上传错误提示
    ///
    /// - Parameter error: 上传错误
    private func showAudioUploadErrorAlert(error: Error) async {
        guard let window = window else { return }
        
        let alert = NSAlert()
        alert.messageText = "音频上传失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        
        alert.beginSheetModal(for: window) { _ in }
    }
    
    /// 公开方法：显示音频面板进入录制模式
    ///
    /// 供工具栏按钮调用，显示音频面板并进入录制模式。
    ///
    /// Requirements: 2.1
    public func showAudioPanelForRecording() {
        guard let viewModel = viewModel,
              let selectedNote = viewModel.selectedNote else {
            print("[MainWindowController] ❌ 无法显示录制面板：没有选中的笔记")
            return
        }
        
        audioPanelStateManager.showForRecording(noteId: selectedNote.id)
    }
    
    /// 公开方法：显示音频面板进入播放模式
    ///
    /// 供音频附件点击调用，显示音频面板并播放指定音频。
    ///
    /// Requirements: 2.2
    public func showAudioPanelForPlayback(fileId: String) {
        guard let viewModel = viewModel,
              let selectedNote = viewModel.selectedNote else {
            print("[MainWindowController] ❌ 无法显示播放面板：没有选中的笔记")
            return
        }
        
        audioPanelStateManager.showForPlayback(fileId: fileId, noteId: selectedNote.id)
    }
    
    
}

#endif
