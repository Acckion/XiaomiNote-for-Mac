import AppKit
import Combine

/// 笔记列表视图控制器
/// 显示选中文件夹的笔记列表
class NotesListViewController: NSViewController {
    
    // MARK: - 属性
    
    private var viewModel: NotesViewModel
    private var tableView: NSTableView!
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
        
        // 创建表格视图
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        
        // 创建列
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TitleColumn"))
        titleColumn.width = 300
        tableView.addTableColumn(titleColumn)
        
        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("DateColumn"))
        dateColumn.width = 150
        tableView.addTableColumn(dateColumn)
        
        // 设置数据源和委托
        tableView.dataSource = self
        tableView.delegate = self
        
        scrollView.documentView = tableView
        
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
        Publishers.CombineLatest(viewModel.$notes, viewModel.$searchText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
        
        viewModel.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.updateSelection()
            }
            .store(in: &cancellables)
        
        // 监听搜索文本变化
        viewModel.$searchText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] searchText in
                self?.updateTitle(with: searchText)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 私有方法
    
    private func updateSelection() {
        guard let selectedNote = viewModel.selectedNote,
              let index = viewModel.filteredNotes.firstIndex(where: { $0.id == selectedNote.id }) else {
            tableView.deselectAll(nil)
            return
        }
        
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }
    
    private func updateTitle(with searchText: String) {
        if searchText.isEmpty {
            self.title = viewModel.selectedFolder?.name ?? "所有笔记"
        } else {
            self.title = "搜索"
        }
    }
}

// MARK: - NSTableViewDataSource

extension NotesListViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return viewModel.filteredNotes.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < viewModel.filteredNotes.count else { return nil }
        let note = viewModel.filteredNotes[row]
        
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("TitleColumn") {
            return note.title
        } else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("DateColumn") {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: note.updatedAt)
        }
        
        return nil
    }
}

// MARK: - NSTableViewDelegate

extension NotesListViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < viewModel.filteredNotes.count else { return nil }
        let note = viewModel.filteredNotes[row]
        
        let identifier: NSUserInterfaceItemIdentifier
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("TitleColumn") {
            identifier = NSUserInterfaceItemIdentifier("TitleCell")
        } else {
            identifier = NSUserInterfaceItemIdentifier("DateCell")
        }
        
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        
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
        
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("TitleColumn") {
            // 设置笔记标题
            if note.isStarred {
                // 星标笔记：显示星标图标和黄色文本
                let attributedString = NSMutableAttributedString()
                
                // 添加星标图标
                let starAttachment = NSTextAttachment()
                if let starImage = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) {
                    starAttachment.image = starImage
                    let starString = NSAttributedString(attachment: starAttachment)
                    attributedString.append(starString)
                    attributedString.append(NSAttributedString(string: " "))
                }
                
                // 添加笔记标题
                let titleString = NSAttributedString(string: note.title)
                attributedString.append(titleString)
                
                // 设置星标颜色
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: NSRange(location: 0, length: 1))
                
                cell?.textField?.attributedStringValue = attributedString
            } else {
                cell?.textField?.stringValue = note.title
            }
            
            // 设置字体
            cell?.textField?.font = NSFont.systemFont(ofSize: 14)
            
        } else {
            // 设置日期
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            cell?.textField?.stringValue = formatter.string(from: note.updatedAt)
            cell?.textField?.font = NSFont.systemFont(ofSize: 12)
            cell?.textField?.textColor = .secondaryLabelColor
        }
        
        return cell
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        if selectedRow >= 0 && selectedRow < viewModel.filteredNotes.count {
            viewModel.selectedNote = viewModel.filteredNotes[selectedRow]
        } else {
            viewModel.selectedNote = nil
        }
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return NotesListRowView()
    }
}

// MARK: - 自定义行视图

class NotesListRowView: NSTableRowView {
    
    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            let selectionRect = bounds.insetBy(dx: 0, dy: 0)
            NSColor.selectedContentBackgroundColor.setFill()
            let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 4, yRadius: 4)
            selectionPath.fill()
        }
    }
    
    override var isEmphasized: Bool {
        get { return true }
        set { super.isEmphasized = newValue }
    }
}
