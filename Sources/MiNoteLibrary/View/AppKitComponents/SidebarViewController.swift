import AppKit
import Combine

/// 侧边栏视图控制器
/// 显示文件夹列表，包含两个Section：
/// 1. "小米笔记" - 系统文件夹（所有笔记、置顶、私密笔记）
/// 2. "我的文件夹" - 用户文件夹（未分类 + 数据库中的文件夹，置顶的在前）
class SidebarViewController: NSViewController {
    
    // MARK: - 属性
    
    private var viewModel: NotesViewModel
    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!
    
    private var cancellables = Set<AnyCancellable>()
    
    /// 侧边栏项数据
    private var sidebarItems: [SidebarItem] = []
    
    // MARK: - 侧边栏项类型
    
    /// 侧边栏项类型
    enum SidebarItem {
        case group(String)  // 分组："小米笔记" 或 "我的文件夹"
        case folder(Folder) // 文件夹
        
        /// 比较两个侧边栏项是否相等
        func isEqual(to other: SidebarItem) -> Bool {
            switch (self, other) {
            case (.group(let name1), .group(let name2)):
                return name1 == name2
            case (.folder(let folder1), .folder(let folder2)):
                return folder1.id == folder2.id
            default:
                return false
            }
        }
    }
    
    // MARK: - 计算属性
    
    /// 系统文件夹（小米笔记部分）
    private var systemFolders: [Folder] {
        viewModel.folders.filter { $0.isSystem || $0.id == "uncategorized" }
    }
    
    /// 用户文件夹（我的文件夹部分）
    private var userFolders: [Folder] {
        viewModel.folders.filter { !$0.isSystem && $0.id != "uncategorized" }
    }
    
    // MARK: - 初始化
    
    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 视图生命周期
    
    override func loadView() {
        // 创建主视图
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // 创建滚动视图
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        // 创建OutlineView
        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.style = .plain
        outlineView.selectionHighlightStyle = .regular
        outlineView.rowHeight = 32
        
        // 创建列
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FolderColumn"))
        column.width = 200
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        
        // 设置数据源和委托
        outlineView.dataSource = self
        outlineView.delegate = self
        
        scrollView.documentView = outlineView
        
        // 设置约束
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        self.view = view
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 构建初始侧边栏项
        rebuildSidebarItems()
        
        // 监听数据变化
        viewModel.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildSidebarItems()
                self?.outlineView.reloadData()
                // 展开所有项
                self?.outlineView.expandItem(nil, expandChildren: true)
            }
            .store(in: &cancellables)
        
        viewModel.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] folder in
                self?.updateSelection()
            }
            .store(in: &cancellables)
        
        // 注册右键菜单
        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu
    }
    
    // MARK: - 右键菜单动作
    
    @objc private func renameFolder(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0 else { return }
        let item = sidebarItems[clickedRow]
        
        if case .folder(let folder) = item {
            showRenameDialog(for: folder)
        }
    }
    
    @objc private func deleteFolder(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0 else { return }
        let item = sidebarItems[clickedRow]
        
        if case .folder(let folder) = item {
            showDeleteDialog(for: folder)
        }
    }
    
    @objc private func toggleFolderPin(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0 else { return }
        let item = sidebarItems[clickedRow]
        
        if case .folder(let folder) = item {
            Task {
                do {
                    try await viewModel.toggleFolderPin(folder)
                } catch {
                    print("切换文件夹置顶状态失败: \(error)")
                }
            }
        }
    }
    
    @objc private func createNewFolder(_ sender: Any?) {
        showCreateFolderDialog()
    }
    
    // MARK: - 对话框显示
    
    private func showRenameDialog(for folder: Folder) {
        // 检查是否是系统文件夹
        if folder.isSystem || folder.id == "uncategorized" {
            showSystemFolderAlert(folder: folder)
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "重命名文件夹"
        alert.informativeText = "请输入新的文件夹名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputField.stringValue = folder.name
        inputField.placeholderString = "文件夹名称"
        alert.accessoryView = inputField
        
        alert.window.initialFirstResponder = inputField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty && newName != folder.name {
                Task {
                    do {
                        try await viewModel.renameFolder(folder, newName: newName)
                    } catch {
                        print("重命名文件夹失败: \(error)")
                    }
                }
            }
        }
    }
    
    private func showDeleteDialog(for folder: Folder) {
        // 检查是否是系统文件夹
        if folder.isSystem || folder.id == "uncategorized" {
            showSystemFolderAlert(folder: folder)
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "删除文件夹"
        alert.informativeText = "确定要删除文件夹 \"\(folder.name)\" 吗？此操作无法撤销，并且文件夹内的所有笔记将移动到\"未分类\"。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task {
                do {
                    try await viewModel.deleteFolder(folder)
                } catch {
                    print("删除文件夹失败: \(error)")
                }
            }
        }
    }
    
    private func showCreateFolderDialog() {
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
                        try await viewModel.createFolder(name: folderName)
                    } catch {
                        print("创建文件夹失败: \(error)")
                    }
                }
            }
        }
    }
    
    private func showSystemFolderAlert(folder: Folder) {
        let alert = NSAlert()
        alert.messageText = "提示"
        alert.informativeText = "\"\(folder.name)\"是系统文件夹，不能重命名或删除。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // MARK: - 私有方法
    
    /// 重建侧边栏项
    private func rebuildSidebarItems() {
        sidebarItems.removeAll()
        
        // 添加"小米笔记"分组
        sidebarItems.append(.group("小米笔记"))
        
        // 添加系统文件夹（按照旧版顺序：所有笔记、置顶、私密笔记）
        if let allNotesFolder = viewModel.folders.first(where: { $0.id == "0" }) {
            sidebarItems.append(.folder(allNotesFolder))
        }
        
        if let starredFolder = viewModel.folders.first(where: { $0.id == "starred" }) {
            sidebarItems.append(.folder(starredFolder))
        }
        
        if let privateNotesFolder = viewModel.folders.first(where: { $0.id == "2" }) {
            sidebarItems.append(.folder(privateNotesFolder))
        }
        
        // 添加"我的文件夹"分组
        sidebarItems.append(.group("我的文件夹"))
        
        // 添加未分类文件夹
        sidebarItems.append(.folder(viewModel.uncategorizedFolder))
        
        // 添加用户文件夹（按置顶状态排序：置顶的在前）
        let userFoldersSorted = userFolders.sorted { folder1, folder2 in
            // 置顶的在前
            if folder1.isPinned != folder2.isPinned {
                return folder1.isPinned
            }
            // 否则按名称排序
            return folder1.name < folder2.name
        }
        
        for folder in userFoldersSorted {
            sidebarItems.append(.folder(folder))
        }
    }
    
    /// 获取文件夹对应的侧边栏项
    private func sidebarItem(for folder: Folder) -> SidebarItem? {
        return sidebarItems.first { item in
            if case .folder(let itemFolder) = item, itemFolder.id == folder.id {
                return true
            }
            return false
        }
    }
    
    /// 获取侧边栏项对应的行
    private func row(for sidebarItem: SidebarItem) -> Int? {
        for i in 0..<sidebarItems.count {
            if self.sidebarItems[i].isEqual(to: sidebarItem) {
                return i
            }
        }
        return nil
    }
    
    /// 获取文件夹对应的行
    private func row(for folder: Folder) -> Int? {
        if let item = sidebarItem(for: folder) {
            return row(for: item)
        }
        return nil
    }
    
    private func updateSelection() {
        guard let selectedFolder = viewModel.selectedFolder else {
            outlineView.deselectAll(nil)
            return
        }
        
        if let row = row(for: selectedFolder) {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarViewController: NSOutlineViewDataSource {
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // 根项：显示所有侧边栏项
            return sidebarItems.count
        }
        return 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return sidebarItems[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let identifier: NSUserInterfaceItemIdentifier
        var cell: NSTableCellView?
        
        switch item {
        case let sidebarItem as SidebarItem:
            switch sidebarItem {
            case .group(let groupName):
                identifier = NSUserInterfaceItemIdentifier("GroupCell")
                cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                
                if cell == nil {
                    cell = NSTableCellView()
                    cell?.identifier = identifier
                    
                    let textField = NSTextField()
                    textField.isEditable = false
                    textField.isBordered = false
                    textField.drawsBackground = false
                    textField.translatesAutoresizingMaskIntoConstraints = false
                    cell?.textField = textField
                    cell?.addSubview(textField)
                    
                    NSLayoutConstraint.activate([
                        textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 8),
                        textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -8),
                        textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
                    ])
                }
                
                // 设置分组名称（只有文字，没有图标）
                cell?.textField?.stringValue = groupName
                cell?.textField?.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
                cell?.textField?.textColor = .secondaryLabelColor
                
            case .folder(let folder):
                identifier = NSUserInterfaceItemIdentifier("FolderCell")
                cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                
                if cell == nil {
                    cell = NSTableCellView()
                    cell?.identifier = identifier
                    
                    let textField = NSTextField()
                    textField.isEditable = false
                    textField.isBordered = false
                    textField.drawsBackground = false
                    textField.translatesAutoresizingMaskIntoConstraints = false
                    cell?.textField = textField
                    cell?.addSubview(textField)
                    
                    let imageView = NSImageView()
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    cell?.imageView = imageView
                    cell?.addSubview(imageView)
                    
                    let countLabel = NSTextField()
                    countLabel.isEditable = false
                    countLabel.isBordered = false
                    countLabel.drawsBackground = false
                    countLabel.translatesAutoresizingMaskIntoConstraints = false
                    countLabel.font = NSFont.systemFont(ofSize: 11)
                    countLabel.textColor = .secondaryLabelColor
                    countLabel.alignment = .right
                    cell?.addSubview(countLabel)
                    
                    NSLayoutConstraint.activate([
                        imageView.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 16), // 文件夹缩进更多
                        imageView.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                        imageView.widthAnchor.constraint(equalToConstant: 16),
                        imageView.heightAnchor.constraint(equalToConstant: 16),
                        
                        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                        textField.trailingAnchor.constraint(equalTo: countLabel.leadingAnchor, constant: -8),
                        textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                        
                        countLabel.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -8),
                        countLabel.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                        countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20)
                    ])
                }
                
                // 设置文件夹名称
                cell?.textField?.stringValue = folder.name
                cell?.textField?.font = NSFont.systemFont(ofSize: 13)
                
                // 设置笔记数量（显示在最右侧，没有括号）
                if let countLabel = cell?.subviews.last as? NSTextField {
                    countLabel.stringValue = "\(folder.count)"
                }
                
                // 设置图标
                let imageName: String
                if folder.id == "0" {
                    imageName = "tray.full" // 所有笔记
                } else if folder.id == "starred" {
                    imageName = "pin.fill" // 置顶
                } else if folder.id == "uncategorized" {
                    imageName = "folder.badge.questionmark" // 未分类
                } else if folder.id == "2" {
                    imageName = "lock.fill" // 私密笔记
                } else {
                    imageName = folder.isPinned ? "pin.fill" : "folder" // 普通文件夹
                }
                
                if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil) {
                    cell?.imageView?.image = image
                    // 使用白色图标（匹配旧版）
                    cell?.imageView?.contentTintColor = .white
                }
            }
            
        default:
            return nil
        }
        
        return cell
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        // 分组项不能选择
        if let sidebarItem = item as? SidebarItem {
            switch sidebarItem {
            case .group:
                return false
            case .folder:
                return true
            }
        }
        return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        // 分组项显示为分组样式
        if let sidebarItem = item as? SidebarItem {
            switch sidebarItem {
            case .group:
                return true
            case .folder:
                return false
            }
        }
        return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        // 分组项高度较小
        if let sidebarItem = item as? SidebarItem {
            switch sidebarItem {
            case .group:
                return 28
            case .folder:
                return 32
            }
        }
        return 32
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0 && selectedRow < sidebarItems.count else { return }
        
        let item = sidebarItems[selectedRow]
        if case .folder(let folder) = item {
            viewModel.selectedFolder = folder
        }
    }
}

// MARK: - NSMenuDelegate

extension SidebarViewController: NSMenuDelegate {
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0 && clickedRow < sidebarItems.count else { return }
        
        let item = sidebarItems[clickedRow]
        
        switch item {
        case .group(let groupName):
            // 分组右键菜单
            if groupName == "我的文件夹" {
                let newFolderItem = NSMenuItem(
                    title: "新建文件夹",
                    action: #selector(createNewFolder(_:)),
                    keyEquivalent: ""
                )
                newFolderItem.target = self
                menu.addItem(newFolderItem)
            }
            
        case .folder(let folder):
            // 文件夹右键菜单
            if folder.isSystem || folder.id == "uncategorized" {
                // 系统文件夹：只有新建文件夹选项
                let newFolderItem = NSMenuItem(
                    title: "新建文件夹",
                    action: #selector(createNewFolder(_:)),
                    keyEquivalent: ""
                )
                newFolderItem.target = self
                menu.addItem(newFolderItem)
            } else {
                // 用户文件夹：完整菜单
                let renameItem = NSMenuItem(
                    title: "重命名文件夹",
                    action: #selector(renameFolder(_:)),
                    keyEquivalent: ""
                )
                renameItem.target = self
                menu.addItem(renameItem)
                
                let pinTitle = folder.isPinned ? "取消置顶" : "置顶"
                let pinItem = NSMenuItem(
                    title: pinTitle,
                    action: #selector(toggleFolderPin(_:)),
                    keyEquivalent: ""
                )
                pinItem.target = self
                menu.addItem(pinItem)
                
                menu.addItem(NSMenuItem.separator())
                
                let deleteItem = NSMenuItem(
                    title: "删除文件夹",
                    action: #selector(deleteFolder(_:)),
                    keyEquivalent: ""
                )
                deleteItem.target = self
                menu.addItem(deleteItem)
            }
        }
    }
}
