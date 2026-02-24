//
//  MainWindowController.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import AppKit
    import Combine
    import os
    import SwiftUI

    /// 主窗口控制器
    /// 负责管理主窗口和工具栏
    public class MainWindowController: NSWindowController {

        // MARK: - 属性

        let logger = Logger(subsystem: "com.minote.MiNoteMac", category: "MainWindowController")

        /// AppCoordinator 引用
        public private(set) var coordinator: AppCoordinator

        /// 统一操作队列
        let operationQueue: UnifiedOperationQueue

        /// 操作处理器
        let operationProcessor: OperationProcessor

        /// 窗口状态
        let windowState: WindowState

        /// 当前搜索字段（用于工具栏搜索项）
        var currentSearchField: CustomSearchField?

        /// 窗口控制器引用（防止被释放）
        var loginWindowController: LoginWindowController?
        var settingsWindowController: SettingsWindowController?
        var historyWindowController: HistoryWindowController?
        var trashWindowController: TrashWindowController?

        /// Combine订阅集合
        var cancellables = Set<AnyCancellable>()

        /// 设置事件订阅 Task
        nonisolated(unsafe) var settingsEventTask: Task<Void, Never>?

        /// 格式菜单popover
        var formatMenuPopover: NSPopover?

        /// 搜索筛选菜单popover
        var searchFilterMenuPopover: NSPopover?

        /// 视图选项菜单popover
        var viewOptionsMenuPopover: NSPopover?

        /// 在线状态菜单工具栏项
        private var onlineStatusMenuToolbarItem: NSToolbarItem?

        /// 当前显示的sheet窗口引用
        var currentSheetWindow: NSWindow?

        /// 当前sheet窗口的工具栏代理引用
        weak var currentSheetToolbarDelegate: BaseSheetToolbarDelegate?

        /// 回收站sheet的工具栏代理引用
        weak var trashSheetToolbarDelegate: BaseSheetToolbarDelegate?

        /// 登录sheet的工具栏代理引用
        weak var loginSheetToolbarDelegate: BaseSheetToolbarDelegate?

        /// 历史记录sheet的工具栏代理引用
        weak var historySheetToolbarDelegate: BaseSheetToolbarDelegate?

        /// 工具栏代理
        var toolbarDelegate: MainWindowToolbarDelegate?

        /// 工具栏可见性管理器
        /// 负责根据应用状态动态更新工具栏项的可见性
        private var visibilityManager: ToolbarVisibilityManager?

        /// 保存的笔记列表宽度（用于视图模式切换时恢复）
        private var savedNotesListWidth: CGFloat?

        /// 笔记列表宽度的 UserDefaults 键
        private let notesListWidthKey = "NotesListWidth"

        // MARK: - 音频面板属性

        /// 音频面板状态管理器
        /// 负责管理音频面板的显示状态、模式和与其他组件的协调
        let audioPanelStateManager = AudioPanelStateManager.shared

        /// 音频面板托管控制器
        /// 用于将 AudioPanelView 嵌入 NSSplitViewController 作为第四栏
        var audioPanelHostingController: AudioPanelHostingController?

        // MARK: - 初始化

        /// 使用 AppCoordinator 和 WindowState 初始化窗口控制器
        /// - Parameters:
        ///   - coordinator: 应用协调器（共享数据层）
        ///   - windowState: 窗口状态（独立 UI 状态）
        public init(
            coordinator: AppCoordinator,
            windowState: WindowState,
            operationQueue: UnifiedOperationQueue,
            operationProcessor: OperationProcessor
        ) {
            self.coordinator = coordinator
            self.windowState = windowState
            self.operationQueue = operationQueue
            self.operationProcessor = operationProcessor

            // 创建窗口
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            super.init(window: window)

            // 验证 WindowState 有效性
            if !validateWindowState() {
                logger.warning("[MainWindowController] WindowState 验证失败，使用默认状态")
            }

            // 设置窗口
            window.title = "笔记"
            window.titleVisibility = .visible
            window.setFrameAutosaveName("MainWindow")

            // 强制禁用透明标题栏，避免系统自动融合行为
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .none

            // 设置窗口内容
            setupWindowContent()

            // 设置工具栏
            setupToolbar()

            // 设置窗口最小尺寸
            window.minSize = NSSize(width: 600, height: 400)

            // 设置状态监听
            setupStateObservers()

            LogService.shared.info(.window, "初始化完成，窗口ID: \(windowState.windowId)")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - 窗口生命周期

        override public func windowDidLoad() {
            super.windowDidLoad()

            // 激活应用程序
            NSApp.activate(ignoringOtherApps: true)

            LogService.shared.info(.window, "主窗口控制器已加载")
        }

        // MARK: - 设置方法

        /// 设置窗口内容
        ///
        /// 使用三栏布局：侧边栏 + 笔记列表 + 编辑器
        /// 在画廊模式下，笔记列表和编辑器区域会被 ContentAreaView 替换
        private func setupWindowContent() {
            guard let window else { return }

            // 创建分割视图控制器（三栏布局）
            let splitViewController = NSSplitViewController()

            // 设置分割视图的自动保存名称，用于记住分割位置
            splitViewController.splitView.autosaveName = "MainWindowSplitView"

            // 第一栏：侧边栏（使用SwiftUI视图）
            let sidebarSplitViewItem = NSSplitViewItem(sidebarWithViewController: SidebarHostingController(coordinator: coordinator))
            sidebarSplitViewItem.minimumThickness = 180
            sidebarSplitViewItem.maximumThickness = 300
            sidebarSplitViewItem.canCollapse = true
            splitViewController.addSplitViewItem(sidebarSplitViewItem)

            // 第二栏：笔记列表（使用SwiftUI视图）
            let notesListSplitViewItem = NSSplitViewItem(viewController: NotesListHostingController(
                coordinator: coordinator,
                windowState: windowState
            ))
            notesListSplitViewItem.minimumThickness = 200
            notesListSplitViewItem.maximumThickness = 350
            notesListSplitViewItem.canCollapse = false
            // 设置较高的 holdingPriority，窗口缩小时优先压缩编辑器
            notesListSplitViewItem.holdingPriority = NSLayoutConstraint.Priority(251)
            splitViewController.addSplitViewItem(notesListSplitViewItem)

            // 第三栏：笔记详情编辑器（使用SwiftUI视图）
            let noteDetailSplitViewItem = NSSplitViewItem(viewController: NoteDetailHostingController(
                coordinator: coordinator,
                windowState: windowState
            ))
            noteDetailSplitViewItem.minimumThickness = 400
            // 编辑器 holdingPriority 较低，窗口缩小时先压缩编辑器
            noteDetailSplitViewItem.holdingPriority = NSLayoutConstraint.Priority(250)
            splitViewController.addSplitViewItem(noteDetailSplitViewItem)

            // 设置窗口内容
            window.contentViewController = splitViewController

            // 监听视图模式变化，动态切换布局
            setupViewModeObserver(splitViewController: splitViewController)
        }

        // 设置视图模式监听
        // 在列表模式和画廊模式之间切换时，动态调整分割视图布局

        private func setupViewModeObserver(splitViewController: NSSplitViewController) {
            ViewOptionsManager.shared.$state
                .map(\.viewMode)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak splitViewController] viewMode in
                    guard let self, let splitViewController else { return }
                    updateLayoutForViewMode(viewMode, splitViewController: splitViewController)
                }
                .store(in: &cancellables)

            // 初始化时根据当前视图模式设置布局
            updateLayoutForViewMode(ViewOptionsManager.shared.viewMode, splitViewController: splitViewController)
        }

        /// 根据视图模式更新布局
        private func updateLayoutForViewMode(_ viewMode: ViewMode, splitViewController: NSSplitViewController) {
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
                    let notesListSplitViewItem = NSSplitViewItem(viewController: NotesListHostingController(
                        coordinator: coordinator,
                        windowState: windowState
                    ))
                    notesListSplitViewItem.minimumThickness = 200
                    notesListSplitViewItem.maximumThickness = 350
                    notesListSplitViewItem.canCollapse = false
                    // 设置较高的 holdingPriority，窗口缩小时优先压缩编辑器
                    notesListSplitViewItem.holdingPriority = NSLayoutConstraint.Priority(251)
                    splitViewController.insertSplitViewItem(notesListSplitViewItem, at: 1)

                    // 添加笔记详情编辑器
                    let noteDetailSplitViewItem = NSSplitViewItem(viewController: NoteDetailHostingController(
                        coordinator: coordinator,
                        windowState: windowState
                    ))
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
                    let galleryHostingController = GalleryHostingController(coordinator: coordinator, windowState: windowState)
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
            guard let window else { return }

            // 创建工具栏代理
            toolbarDelegate = MainWindowToolbarDelegate(
                folderState: coordinator.folderState,
                authState: coordinator.authState,
                syncState: coordinator.syncState,
                windowController: self,
                operationQueue: operationQueue
            )

            let toolbar = NSToolbar(identifier: "MainWindowToolbar")
            toolbar.allowsUserCustomization = true
            toolbar.autosavesConfiguration = true
            toolbar.displayMode = .iconOnly
            toolbar.delegate = toolbarDelegate

            window.toolbar = toolbar
            window.toolbarStyle = .unified

            // 创建工具栏可见性管理器
            visibilityManager = ToolbarVisibilityManager(
                toolbar: toolbar,
                noteListState: coordinator.noteListState,
                folderState: coordinator.folderState,
                authState: coordinator.authState
            )

            // 将可见性管理器传递给工具栏代理
            toolbarDelegate?.visibilityManager = visibilityManager
        }

        // MARK: - 工具栏验证

        /// 验证工具栏项
        @objc func makeToolbarValidate() {
            window?.toolbar?.validateVisibleItems()
        }

        // MARK: - 清理

        deinit {
            NotificationCenter.default.removeObserver(self)
            settingsEventTask?.cancel()
            // 由于 deinit 是 nonisolated 的，不能访问 @MainActor 隔离的属性
            // 这些属性会在对象释放时自动清理
            LogService.shared.debug(.window, "主窗口控制器已释放")
        }
    }

#endif
