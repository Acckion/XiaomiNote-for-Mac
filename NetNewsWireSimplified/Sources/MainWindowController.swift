import AppKit
import SwiftUI

/// 精简版主窗口控制器
/// 基于NetNewsWire的MainWindowController，但移除了所有Service依赖
class MainWindowController: NSWindowController {
    
    // MARK: - 属性
    
    private var viewModel: NotesViewModel
    
    private var currentSearchField: NSSearchField?
    private let windowAutosaveName = NSWindow.FrameAutosaveName("MainWindow")
    
    // 三栏视图控制器
    private var sidebarViewController: SidebarViewController?
    private var timelineContainerViewController: TimelineContainerViewController?
    private var detailViewController: DetailViewController?
    
    // MARK: - 初始化
    
    init(viewModel: NotesViewModel) {
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
        window.title = "NetNewsWire Simplified"
        window.titleVisibility = .visible
        window.setFrameAutosaveName(windowAutosaveName)
        
        // 设置内容
        setupWindowContent()
        
        // 设置工具栏
        setupToolbar()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 窗口生命周期
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        // 激活应用程序
        NSApp.activate(ignoringOtherApps: true)
        
        print("主窗口控制器已加载")
    }
    
    // MARK: - 设置方法
    
    private func setupWindowContent() {
        guard let window = window else { return }
        
        // 创建分割视图控制器（三栏布局）
        let splitViewController = NSSplitViewController()
        
        // 第一栏：侧边栏
        let sidebarSplitViewItem = NSSplitViewItem(sidebarWithViewController: SidebarViewController(viewModel: viewModel))
        sidebarSplitViewItem.minimumThickness = 180
        sidebarSplitViewItem.maximumThickness = 300
        sidebarSplitViewItem.canCollapse = true
        splitViewController.addSplitViewItem(sidebarSplitViewItem)
        sidebarViewController = sidebarSplitViewItem.viewController as? SidebarViewController
        
        // 第二栏：时间线
        let timelineSplitViewItem = NSSplitViewItem(contentListWithViewController: TimelineContainerViewController(viewModel: viewModel))
        timelineSplitViewItem.minimumThickness = 200
        timelineSplitViewItem.maximumThickness = 400
        splitViewController.addSplitViewItem(timelineSplitViewItem)
        timelineContainerViewController = timelineSplitViewItem.viewController as? TimelineContainerViewController
        
        // 第三栏：详情
        let detailSplitViewItem = NSSplitViewItem(viewController: DetailViewController(viewModel: viewModel))
        detailSplitViewItem.minimumThickness = 300
        splitViewController.addSplitViewItem(detailSplitViewItem)
        detailViewController = detailSplitViewItem.viewController as? DetailViewController
        
        // 设置窗口内容
        window.contentViewController = splitViewController
        
        // 设置窗口最小尺寸
        window.minSize = NSSize(width: 800, height: 600)
    }
    
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
    
    @objc func makeToolbarValidate() {
        window?.toolbar?.validateVisibleItems()
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        
        switch itemIdentifier {
            
        case .newNote:
            return buildToolbarButton(.newNote, "新建笔记", NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)!, "createNewNote:")
            
        case .newFolder:
            return buildToolbarButton(.newFolder, "新建文件夹", NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)!, "createNewFolder:")
            
        case .refresh:
            return buildToolbarButton(.refresh, "刷新", NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)!, "performSync:")
            
        case .markAllAsRead:
            return buildToolbarButton(.markAllAsRead, "全部标记已读", NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)!, "markAllAsRead:")
            
        case .nextUnread:
            return buildToolbarButton(.nextUnread, "下一篇未读", NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)!, "nextUnread:")
            
        case .markRead:
            return buildToolbarButton(.markRead, "标记已读", NSImage(systemSymbolName: "circle", accessibilityDescription: nil)!, "toggleRead:")
            
        case .markStar:
            return buildToolbarButton(.markStar, "星标", NSImage(systemSymbolName: "star", accessibilityDescription: nil)!, "toggleStarred:")
            
        case .openInBrowser:
            return buildToolbarButton(.openInBrowser, "在浏览器中打开", NSImage(systemSymbolName: "safari", accessibilityDescription: nil)!, "openInBrowser:")
            
        case .share:
            return buildToolbarButton(.share, "分享", NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)!, "shareNote:")
            
        case .search:
            let toolbarItem = NSSearchToolbarItem(itemIdentifier: .search)
            toolbarItem.toolTip = "搜索"
            toolbarItem.label = "搜索"
            return toolbarItem
            
        case .toggleSidebar:
            // 使用系统提供的切换侧边栏项
            return NSToolbarItem(itemIdentifier: .toggleSidebar)
            
        case .sidebarTrackingSeparator:
            // 侧边栏跟踪分隔符 - 连接到分割视图的第一个分隔符
            if let splitViewController = window?.contentViewController as? NSSplitViewController {
                return NSTrackingSeparatorToolbarItem(identifier: .sidebarTrackingSeparator, splitView: splitViewController.splitView, dividerIndex: 0)
            }
            return nil
            
        case .timelineTrackingSeparator:
            // 时间线跟踪分隔符 - 将工具栏分割为不同部分
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
            }
        }
        
        return nil
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .newNote,
            .newFolder,
            .refresh,
            .markAllAsRead,
            .nextUnread,
            .timelineTrackingSeparator,
            .markRead,
            .markStar,
            .openInBrowser,
            .share,
            .search,
            .space
        ]
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .newNote,
            .newFolder,
            .refresh,
            .markAllAsRead,
            .nextUnread,
            .timelineTrackingSeparator,
            .markRead,
            .markStar,
            .openInBrowser,
            .share,
            .flexibleSpace,
            .search
        ]
    }
    
    func toolbarWillAddItem(_ notification: Notification) {
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
            // 分享按钮应该在鼠标按下时发送动作
            button.sendAction(on: .leftMouseDown)
        }
    }
    
    func toolbarDidRemoveItem(_ notification: Notification) {
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
    
    private func buildToolbarButton(_ identifier: NSToolbarItem.Identifier, _ title: String, _ image: NSImage, _ selector: String) -> NSToolbarItem {
        let toolbarItem = NSToolbarItem(itemIdentifier: identifier)
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
}

// MARK: - NSSearchFieldDelegate

extension MainWindowController: NSSearchFieldDelegate {
    
    func searchFieldDidStartSearching(_ sender: NSSearchField) {
        // 搜索开始
        viewModel.searchText = sender.stringValue
    }
    
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        // 搜索结束
        viewModel.searchText = ""
    }
    
    @objc func performSearch(_ sender: NSSearchField) {
        if sender.stringValue.isEmpty {
            return
        }
        viewModel.searchText = sender.stringValue
    }
}

// MARK: - NSUserInterfaceValidations

extension MainWindowController: NSUserInterfaceValidations {
    
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        
        // 根据当前状态验证各个动作
        
        if item.action == #selector(createNewNote(_:)) {
            return true // 总是可以创建新笔记
        }
        
        if item.action == #selector(createNewFolder(_:)) {
            return true // 总是可以创建新文件夹
        }
        
        if item.action == #selector(performSync(_:)) {
            return true // 总是可以同步
        }
        
        if item.action == #selector(shareNote(_:)) {
            return viewModel.selectedNote != nil // 只有选中笔记后才能分享
        }
        
        if item.action == #selector(toggleStarred(_:)) {
            return viewModel.selectedNote != nil // 只有选中笔记后才能星标
        }
        
        if item.action == #selector(markAllAsRead(_:)) {
            return !viewModel.filteredNotes.isEmpty // 有笔记才能标记已读
        }
        
        if item.action == #selector(nextUnread(_:)) {
            return true // 总是可以跳转到下一篇
        }
        
        if item.action == #selector(toggleRead(_:)) {
            return viewModel.selectedNote != nil // 只有选中笔记后才能标记已读
        }
        
        if item.action == #selector(openInBrowser(_:)) {
            return viewModel.selectedNote != nil // 只有选中笔记才能在浏览器中打开
        }
        
        return true
    }
}

// MARK: - 动作方法

extension MainWindowController {
    
    @objc func createNewNote(_ sender: Any?) {
        viewModel.createNewNote()
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
                print("创建文件夹: \(folderName)")
                // 在实际应用中，这里会调用viewModel创建文件夹
            }
        }
    }
    
    @objc func performSync(_ sender: Any?) {
        viewModel.performFullSync()
    }
    
    @objc func shareNote(_ sender: Any?) {
        // 分享选中的笔记
        guard let note = viewModel.selectedNote else { return }
        
        let sharingService = NSSharingServicePicker(items: [
            note.title,
            note.content
        ])
        
        if let window = window,
           let contentView = window.contentView {
            sharingService.show(relativeTo: NSRect.zero, of: contentView, preferredEdge: .minY)
        }
    }
    
    @objc func toggleStarred(_ sender: Any?) {
        guard let note = viewModel.selectedNote else { return }
        viewModel.toggleStar(note)
    }
    
    @objc func markAllAsRead(_ sender: Any?) {
        print("标记所有笔记为已读")
        // 在实际应用中，这里会调用viewModel标记所有已读
    }
    
    @objc func nextUnread(_ sender: Any?) {
        print("跳转到下一篇未读笔记")
        // 在实际应用中，这里会实现跳转逻辑
    }
    
    @objc func toggleRead(_ sender: Any?) {
        guard let note = viewModel.selectedNote else { return }
        print("切换笔记已读状态: \(note.title)")
        // 在实际应用中，这里会调用viewModel切换已读状态
    }
    
    @objc func openInBrowser(_ sender: Any?) {
        guard let note = viewModel.selectedNote else { return }
        print("在浏览器中打开笔记: \(note.title)")
        // 在实际应用中，这里会打开浏览器
    }
}

// MARK: - 工具栏标识符扩展

extension NSToolbarItem.Identifier {
    static let newNote = NSToolbarItem.Identifier("newNote")
    static let newFolder = NSToolbarItem.Identifier("newFolder")
    static let refresh = NSToolbarItem.Identifier("refresh")
    static let markAllAsRead = NSToolbarItem.Identifier("markAllAsRead")
    static let nextUnread = NSToolbarItem.Identifier("nextUnread")
    static let markRead = NSToolbarItem.Identifier("markRead")
    static let markStar = NSToolbarItem.Identifier("markStar")
    static let openInBrowser = NSToolbarItem.Identifier("openInBrowser")
    static let share = NSToolbarItem.Identifier("share")
    static let search = NSToolbarItem.Identifier("search")
    static let sidebarTrackingSeparator = NSToolbarItem.Identifier("sidebarTrackingSeparator")
    static let timelineTrackingSeparator = NSToolbarItem.Identifier("timelineTrackingSeparator")
}
