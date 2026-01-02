import AppKit
import Combine

/// 时间线容器视图控制器
/// 显示笔记列表
class TimelineContainerViewController: NSViewController {
    
    private var viewModel: NotesViewModel
    private var tableView: NSTableView!
    
    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        // 创建滚动视图和TableView
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        
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
        self.view = scrollView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 监听数据变化
        viewModel.$filteredNotes
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
    }
    
    private func updateSelection() {
        guard let selectedNote = viewModel.selectedNote,
              let index = viewModel.filteredNotes.firstIndex(where: { $0.id == selectedNote.id }) else {
            tableView.deselectAll(nil)
            return
        }
        
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - NSTableViewDataSource

extension TimelineContainerViewController: NSTableViewDataSource {
    
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

extension TimelineContainerViewController: NSTableViewDelegate {
    
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
                textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
            ])
        }
        
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("TitleColumn") {
            cell?.textField?.stringValue = note.title
            // 如果是星标笔记，显示星标图标
            if note.isStarred {
                let attachment = NSTextAttachment()
                attachment.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
                let attributedString = NSMutableAttributedString(string: "★ \(note.title)")
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: NSRange(location: 0, length: 2))
                cell?.textField?.attributedStringValue = attributedString
            }
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            cell?.textField?.stringValue = formatter.string(from: note.updatedAt)
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
}
