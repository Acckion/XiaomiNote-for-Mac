import AppKit
import Combine

/// 侧边栏视图控制器
/// 显示文件夹列表
class SidebarViewController: NSViewController {
    
    private var viewModel: NotesViewModel
    private var outlineView: NSOutlineView!
    
    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        // 创建滚动视图和OutlineView
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.style = .plain
        outlineView.selectionHighlightStyle = .regular
        
        // 创建列
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FolderColumn"))
        column.width = 200
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        
        // 设置数据源和委托
        outlineView.dataSource = self
        outlineView.delegate = self
        
        scrollView.documentView = outlineView
        self.view = scrollView
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
    
    private var cancellables = Set<AnyCancellable>()
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
                imageView.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
            ])
        }
        
        cell?.textField?.stringValue = "\(folder.name) (\(folder.count))"
        
        // 设置图标
        let imageName: String
        if folder.id == "0" {
            imageName = "tray.full"
        } else if folder.id == "starred" {
            imageName = "pin.fill"
        } else if folder.id == "uncategorized" {
            imageName = "folder.badge.questionmark"
        } else {
            imageName = folder.isPinned ? "pin.fill" : "folder"
        }
        
        cell?.imageView?.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
        
        return cell
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = outlineView.selectedRow
        if selectedRow >= 0, let selectedFolder = outlineView.item(atRow: selectedRow) as? Folder {
            viewModel.selectFolder(selectedFolder)
        }
    }
}
