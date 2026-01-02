import AppKit
import Combine

/// 侧边栏视图控制器
/// 显示文件夹列表
class SidebarViewController: NSViewController {
    
    // MARK: - 属性
    
    private var viewModel: NotesViewModel
    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!
    
    private var cancellables = Set<AnyCancellable>()
    
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
        
        // 监听数据变化
        viewModel.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
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
    }
    
    // MARK: - 私有方法
    
    private func updateSelection() {
        guard let selectedFolder = viewModel.selectedFolder else {
            outlineView.deselectAll(nil)
            return
        }
        
        let row = outlineView.row(forItem: selectedFolder)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarViewController: NSOutlineViewDataSource {
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // 根项：显示所有文件夹
            return viewModel.folders.count
        }
        return 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return viewModel.folders[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let folder = item as? Folder else { return nil }
        
        let identifier = NSUserInterfaceItemIdentifier("FolderCell")
        var cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        
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
            
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 8),
                imageView.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
            ])
        }
        
        // 设置文件夹名称和笔记数量
        cell?.textField?.stringValue = "\(folder.name) (\(folder.count))"
        
        // 设置字体
        cell?.textField?.font = NSFont.systemFont(ofSize: 13)
        
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
        }
        
        return cell
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = outlineView.selectedRow
        if selectedRow >= 0, let selectedFolder = outlineView.item(atRow: selectedRow) as? Folder {
            viewModel.selectFolder(selectedFolder)
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        return SidebarRowView()
    }
}

// MARK: - 自定义行视图

class SidebarRowView: NSTableRowView {
    
    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            let selectionRect = bounds.insetBy(dx: 4, dy: 2)
            NSColor.selectedContentBackgroundColor.setFill()
            let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
            selectionPath.fill()
        }
    }
    
    override var isEmphasized: Bool {
        get { return true }
        set { super.isEmphasized = newValue }
    }
}
