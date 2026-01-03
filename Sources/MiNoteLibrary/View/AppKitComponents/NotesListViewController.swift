import AppKit
import Combine
import SwiftUI

/// 笔记列表视图控制器
/// 显示选中文件夹的笔记列表，复刻旧版SwiftUI的NotesListView功能
class NotesListViewController: NSViewController {
    
    // MARK: - 属性
    
    private var viewModel: NotesViewModel
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    
    private var cancellables = Set<AnyCancellable>()
    
    // 分组数据
    private var groupedNotes: [String: [Note]] = [:]
    private var sectionKeys: [String] = []
    
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
        scrollView.backgroundColor = NSColor.windowBackgroundColor
        scrollView.drawsBackground = true
        view.addSubview(scrollView)
        
        // 创建表格视图
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 60  // 增加行高以容纳更多内容
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = NSColor.windowBackgroundColor
        
        // 创建列
        let contentColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ContentColumn"))
        contentColumn.width = 400
        tableView.addTableColumn(contentColumn)
        
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
                self?.updateGroupedNotes()
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
        
        viewModel.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.updateSelection()
            }
            .store(in: &cancellables)
        
        viewModel.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateGroupedNotes()
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
        
        // 设置右键菜单
        tableView.menu = createContextMenu()
    }
    
    // MARK: - 私有方法
    
    private func updateGroupedNotes() {
        groupedNotes = groupNotesByDate(viewModel.filteredNotes)
        
        // 定义分组显示顺序
        let sectionOrder = ["置顶", "今天", "昨天", "本周", "本月", "本年"]
        
        // 先添加固定顺序的分组
        var keys: [String] = []
        for key in sectionOrder {
            if let notes = groupedNotes[key], !notes.isEmpty {
                keys.append(key)
            }
        }
        
        // 然后按年份分组其他笔记（降序排列）
        let yearGroups = groupedNotes.filter { !sectionOrder.contains($0.key) }
        let sortedYears = yearGroups.keys.sorted(by: >)
        keys.append(contentsOf: sortedYears)
        
        sectionKeys = keys
    }
    
    private func updateSelection() {
        guard let selectedNote = viewModel.selectedNote else {
            tableView.deselectAll(nil)
            return
        }
        
        // 查找笔记在分组中的位置
        var rowIndex = 0
        for sectionKey in sectionKeys {
            if let notes = groupedNotes[sectionKey] {
                if let index = notes.firstIndex(where: { $0.id == selectedNote.id }) {
                    tableView.selectRowIndexes(IndexSet(integer: rowIndex + index), byExtendingSelection: false)
                    tableView.scrollRowToVisible(rowIndex + index)
                    return
                }
                rowIndex += notes.count
            }
        }
        
        tableView.deselectAll(nil)
    }
    
    private func groupNotesByDate(_ notes: [Note]) -> [String: [Note]] {
        var grouped: [String: [Note]] = [:]
        let calendar = Calendar.current
        let now = Date()
        
        // 先分离置顶笔记
        let pinnedNotes = notes.filter { $0.isStarred }
        let unpinnedNotes = notes.filter { !$0.isStarred }
        
        // 处理置顶笔记
        if !pinnedNotes.isEmpty {
            grouped["置顶"] = pinnedNotes.sorted { $0.updatedAt > $1.updatedAt }
        }
        
        // 处理非置顶笔记
        for note in unpinnedNotes {
            let date = note.updatedAt
            let key: String
            
            if calendar.isDateInToday(date) {
                key = "今天"
            } else if calendar.isDateInYesterday(date) {
                key = "昨天"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                // 本周（但不包括今天和昨天）
                key = "本周"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
                // 本月（但不包括本周）
                key = "本月"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                // 本年（但不包括本月）
                key = "本年"
            } else {
                // 其他年份
                let year = calendar.component(.year, from: date)
                key = "\(year)年"
            }
            
            if grouped[key] == nil {
                grouped[key] = []
            }
            grouped[key]?.append(note)
        }
        
        // 对每个分组内的笔记按更新时间降序排序
        for key in grouped.keys {
            grouped[key] = grouped[key]?.sorted { $0.updatedAt > $1.updatedAt }
        }
        
        return grouped
    }
    
    private func createContextMenu() -> NSMenu {
        let menu = NSMenu()
        
        // 在新窗口打开备忘录
        let openInNewWindowItem = NSMenuItem(
            title: "在新窗口打开备忘录",
            action: #selector(openNoteInNewWindow(_:)),
            keyEquivalent: ""
        )
        openInNewWindowItem.target = self
        menu.addItem(openInNewWindowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 置顶备忘录
        let toggleStarItem = NSMenuItem(
            title: "置顶备忘录",
            action: #selector(toggleStarNote(_:)),
            keyEquivalent: ""
        )
        toggleStarItem.target = self
        menu.addItem(toggleStarItem)
        
        // 移动备忘录
        let moveNoteItem = NSMenuItem(
            title: "移动备忘录",
            action: #selector(moveNote(_:)),
            keyEquivalent: ""
        )
        moveNoteItem.target = self
        menu.addItem(moveNoteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 删除备忘录
        let deleteNoteItem = NSMenuItem(
            title: "删除备忘录",
            action: #selector(deleteNote(_:)),
            keyEquivalent: ""
        )
        deleteNoteItem.target = self
        menu.addItem(deleteNoteItem)
        
        // 复制备忘录
        let copyNoteItem = NSMenuItem(
            title: "复制备忘录",
            action: #selector(copyNote(_:)),
            keyEquivalent: ""
        )
        copyNoteItem.target = self
        menu.addItem(copyNoteItem)
        
        // 新建备忘录
        let newNoteItem = NSMenuItem(
            title: "新建备忘录",
            action: #selector(createNewNote(_:)),
            keyEquivalent: ""
        )
        newNoteItem.target = self
        menu.addItem(newNoteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 共享备忘录
        let shareNoteItem = NSMenuItem(
            title: "共享备忘录",
            action: #selector(shareNote(_:)),
            keyEquivalent: ""
        )
        shareNoteItem.target = self
        menu.addItem(shareNoteItem)
        
        return menu
    }
    
    // MARK: - 上下文菜单动作
    
    @objc private func openNoteInNewWindow(_ sender: Any?) {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0 else { return }
        
        // 查找点击的笔记
        var rowIndex = 0
        for sectionKey in sectionKeys {
            if let notes = groupedNotes[sectionKey] {
                if clickedRow >= rowIndex && clickedRow < rowIndex + notes.count {
                    let note = notes[clickedRow - rowIndex]
                    // 在新窗口打开笔记
                    let newWindow = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                        styleMask: [.titled, .closable, .miniaturizable, .resizable],
                        backing: .buffered,
                        defer: false
                    )
                    newWindow.title = note.title.isEmpty ? "无标题" : note.title
                    newWindow.center()
                    
                    // 创建新的视图模型和视图
                    let newViewModel = NotesViewModel()
                    newViewModel.selectedNote = note
                    newViewModel.selectedFolder = viewModel.folders.first { $0.id == note.folderId } ?? viewModel.folders.first { $0.id == "0" }
                    
                    let contentView = NoteDetailView(viewModel: newViewModel)
                    newWindow.contentView = NSHostingView(rootView: contentView)
                    newWindow.makeKeyAndOrderFront(nil)
                    return
                }
                rowIndex += notes.count
            }
        }
    }
    
    @objc private func toggleStarNote(_ sender: Any?) {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0 else { return }
        
        // 查找点击的笔记
        var rowIndex = 0
        for sectionKey in sectionKeys {
            if let notes = groupedNotes[sectionKey] {
                if clickedRow >= rowIndex && clickedRow < rowIndex + notes.count {
                    let note = notes[clickedRow - rowIndex]
                    viewModel.toggleStar(note)
                    return
                }
                rowIndex += notes.count
            }
        }
    }
    
    @objc private func moveNote(_ sender: Any?) {
        // TODO: 实现移动备忘录功能
        print("移动备忘录")
    }
    
    @objc private func deleteNote(_ sender: Any?) {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0 else { return }
        
        // 查找点击的笔记
        var rowIndex = 0
        for sectionKey in sectionKeys {
            if let notes = groupedNotes[sectionKey] {
                if clickedRow >= rowIndex && clickedRow < rowIndex + notes.count {
                    let note = notes[clickedRow - rowIndex]
                    
                    let alert = NSAlert()
                    alert.messageText = "删除备忘录"
                    alert.informativeText = "确定要删除备忘录 \"\(note.title)\" 吗？此操作无法撤销。"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "删除")
                    alert.addButton(withTitle: "取消")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        // 直接调用deleteNote方法，它内部会处理异步操作
                        viewModel.deleteNote(note)
                    }
                    return
                }
                rowIndex += notes.count
            }
        }
    }
    
    @objc private func copyNote(_ sender: Any?) {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0 else { return }
        
        // 查找点击的笔记
        var rowIndex = 0
        for sectionKey in sectionKeys {
            if let notes = groupedNotes[sectionKey] {
                if clickedRow >= rowIndex && clickedRow < rowIndex + notes.count {
                    let note = notes[clickedRow - rowIndex]
                    
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    
                    // 复制标题和内容
                    let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
                    pasteboard.setString(content, forType: .string)
                    return
                }
                rowIndex += notes.count
            }
        }
    }
    
    @objc private func createNewNote(_ sender: Any?) {
        viewModel.createNewNote()
    }
    
    @objc private func shareNote(_ sender: Any?) {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0 else { return }
        
        // 查找点击的笔记
        var rowIndex = 0
        for sectionKey in sectionKeys {
            if let notes = groupedNotes[sectionKey] {
                if clickedRow >= rowIndex && clickedRow < rowIndex + notes.count {
                    let note = notes[clickedRow - rowIndex]
                    
                    let sharingService = NSSharingServicePicker(items: [
                        note.title,
                        note.content
                    ])
                    
                    if let window = view.window,
                       let contentView = window.contentView {
                        sharingService.show(relativeTo: NSRect.zero, of: contentView, preferredEdge: .minY)
                    }
                    return
                }
                rowIndex += notes.count
            }
        }
    }
}

// MARK: - NSTableViewDataSource

extension NotesListViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        var totalRows = 0
        for sectionKey in sectionKeys {
            if let notes = groupedNotes[sectionKey] {
                totalRows += notes.count
            }
        }
        return totalRows
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return nil // 我们使用自定义视图，所以返回nil
    }
}

// MARK: - NSTableViewDelegate

extension NotesListViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // 查找对应的笔记
        var currentRow = 0
        for sectionKey in sectionKeys {
            if let notes = groupedNotes[sectionKey] {
                if row >= currentRow && row < currentRow + notes.count {
                    let note = notes[row - currentRow]
                    let isLastInSection = (row - currentRow) == notes.count - 1
                    
                    // 创建或重用单元格
                    let identifier = NSUserInterfaceItemIdentifier("NoteCell")
                    var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NoteTableCellView
                    
                    if cell == nil {
                        cell = NoteTableCellView()
                        cell?.identifier = identifier
                    }
                    
                    cell?.configure(with: note, viewModel: viewModel, showDivider: !isLastInSection)
                    return cell
                }
                currentRow += notes.count
            }
        }
        
        return nil
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return NotesListRowView()
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 60 // 固定行高
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        if selectedRow >= 0 {
            // 查找对应的笔记
            var currentRow = 0
            for sectionKey in sectionKeys {
                if let notes = groupedNotes[sectionKey] {
                    if selectedRow >= currentRow && selectedRow < currentRow + notes.count {
                        viewModel.selectedNote = notes[selectedRow - currentRow]
                        return
                    }
                    currentRow += notes.count
                }
            }
        } else {
            viewModel.selectedNote = nil
        }
    }
}

// MARK: - 自定义单元格视图

class NoteTableCellView: NSView {
    
    private var titleLabel: NSTextField!
    private var dateLabel: NSTextField!
    private var previewLabel: NSTextField!
    private var folderLabel: NSTextField!
    private var imageView: NSImageView!
    private var dividerView: NSView!
    
    private var note: Note?
    private var viewModel: NotesViewModel?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        // 创建标题标签
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 14)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        // 创建日期标签
        dateLabel = NSTextField(labelWithString: "")
        dateLabel.font = NSFont.systemFont(ofSize: 11)
        dateLabel.textColor = .secondaryLabelColor
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dateLabel)
        
        // 创建预览标签
        previewLabel = NSTextField(labelWithString: "")
        previewLabel.font = NSFont.systemFont(ofSize: 11)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewLabel)
        
        // 创建文件夹标签
        folderLabel = NSTextField(labelWithString: "")
        folderLabel.font = NSFont.systemFont(ofSize: 10)
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.lineBreakMode = .byTruncatingTail
        folderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(folderLabel)
        
        // 创建图片视图
        imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        
        // 创建分割线视图
        dividerView = NSView()
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor
        dividerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dividerView)
        
        // 设置约束
        NSLayoutConstraint.activate([
            // 标题标签
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: imageView.leadingAnchor, constant: -8),
            
            // 日期标签
            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            
            // 预览标签
            previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            previewLabel.leadingAnchor.constraint(equalTo: dateLabel.trailingAnchor, constant: 4),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: imageView.leadingAnchor, constant: -8),
            
            // 文件夹标签
            folderLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 2),
            folderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            folderLabel.trailingAnchor.constraint(lessThanOrEqualTo: imageView.leadingAnchor, constant: -8),
            
            // 图片视图
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            imageView.widthAnchor.constraint(equalToConstant: 50),
            imageView.heightAnchor.constraint(equalToConstant: 50),
            
            // 分割线
            dividerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dividerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            dividerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerView.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }
    
    func configure(with note: Note, viewModel: NotesViewModel, showDivider: Bool) {
        self.note = note
        self.viewModel = viewModel
        
        // 设置标题
        if note.isStarred {
            let attributedString = NSMutableAttributedString()
            
            // 添加星标图标
            if let starImage = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) {
                let attachment = NSTextAttachment()
                attachment.image = starImage
                let starString = NSAttributedString(attachment: attachment)
                attributedString.append(starString)
                attributedString.append(NSAttributedString(string: " "))
                
                // 设置星标颜色
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: NSRange(location: 0, length: 1))
            }
            
            // 添加笔记标题
            let title = hasRealTitle(note) ? note.title : "无标题"
            let titleString = NSAttributedString(string: title)
            attributedString.append(titleString)
            
            titleLabel.attributedStringValue = attributedString
        } else {
            let title = hasRealTitle(note) ? note.title : "无标题"
            titleLabel.stringValue = title
        }
        
        // 设置日期
        dateLabel.stringValue = formatDate(note.updatedAt)
        
        // 设置预览文本
        previewLabel.stringValue = extractPreviewText(from: note.content)
        
        // 设置文件夹信息
        if shouldShowFolderInfo(for: note, viewModel: viewModel) {
            folderLabel.stringValue = getFolderName(for: note.folderId, viewModel: viewModel)
            folderLabel.isHidden = false
        } else {
            folderLabel.isHidden = true
        }
        
        // 设置图片预览
        if let imageInfo = getFirstImageInfo(from: note) {
            loadThumbnail(imageInfo: imageInfo)
            imageView.isHidden = false
        } else {
            imageView.image = nil
            imageView.isHidden = true
        }
        
        // 设置分割线
        dividerView.isHidden = !showDivider
    }
    
    private func hasRealTitle(_ note: Note) -> Bool {
        // 如果标题为空，没有真正的标题
        if note.title.isEmpty {
            return false
        }
        
        // 如果标题是"未命名笔记_xxx"格式，没有真正的标题
        if note.title.hasPrefix("未命名笔记_") {
            return false
        }
        
        // 检查 rawData 中的 extraInfo 是否有真正的标题
        if let rawData = note.rawData,
           let extraInfo = rawData["extraInfo"] as? String,
           let extraData = extraInfo.data(using: .utf8),
           let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
           let realTitle = extraJson["title"] as? String,
           !realTitle.isEmpty {
            // 如果 extraInfo 中有标题，且与当前标题匹配，说明有真正的标题
            if realTitle == note.title {
                return true
            }
        }
        
        // 检查标题是否与内容的第一行匹配（去除XML标签后）
        // 如果匹配，说明标题可能是从内容中提取的（处理旧数据），没有真正的标题
        if !note.content.isEmpty {
            // 移除XML标签，提取纯文本
            let textContent = note.content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
             .replacingOccurrences(of: "&amp;", with: "&")
             .replacingOccurrences(of: "&lt;", with: "<")
             .replacingOccurrences(of: "&gt;", with: ">")
             .replacingOccurrences(of: "&quot;", with: "\"")
              .replacingOccurrences(of: "&apos;", with: "'")
             .trimmingCharacters(in: .whitespacesAndNewlines)

            // 获取第一行
            let firstLine = textContent.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            // 如果标题与第一行匹配，说明可能是从内容中提取的（处理旧数据）
            if !firstLine.isEmpty && note.title == firstLine {
                return false
            }
        }
        
        // 默认情况下，如果标题不为空且不是"未命名笔记_xxx"，认为有真正的标题
        return true
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            return "\(year)/\(month)/\(day)"
        }
    }
    
    private func extractPreviewText(from xmlContent: String) -> String {
        guard !xmlContent.isEmpty else {
            return ""
        }
        
        // 移除 XML 标签，提取纯文本
        var text = xmlContent
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
             .replacingOccurrences(of: "&lt;", with: "<")
              .replacingOccurrences(of: "&gt;", with: ">")
              .replacingOccurrences(of: "&quot;", with: "\"")
             .replacingOccurrences(of: "&apos;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 限制长度（比如前 50 个字符）
        let maxLength = 50
        if text.count > maxLength {
            text = String(text.prefix(maxLength)) + "..."
        }
        
        return text.isEmpty ? "无内容" : text
    }
    
    func shouldShowFolderInfo(for note: Note, viewModel: NotesViewModel) -> Bool {
        // 如果选中"未分类"文件夹，不显示文件夹信息
        if let folderId = viewModel.selectedFolder?.id, folderId == "uncategorized" {
            return false
        }
        
        // 有搜索文本
        if !viewModel.searchText.isEmpty {
            return true
        }
        
        // 根据当前选中文件夹判断
        guard let folderId = viewModel.selectedFolder?.id else { return false }
        return folderId == "0" || folderId == "starred"
    }
    
    func getFolderName(for folderId: String, viewModel: NotesViewModel) -> String {
        // 系统文件夹名称
        if folderId == "0" {
            return "未分类"
        } else if folderId == "starred" {
            return "置顶"
        } else if folderId == "2" {
            return "私密笔记"
        }
        
        // 用户自定义文件夹
        if let folder = viewModel.folders.first(where: { $0.id == folderId }) {
            return folder.name
        }
        
        // 找不到时，回退显示 ID（理论上很少出现）
        return folderId
    }
    
    func getFirstImageInfo(from note: Note) -> (fileId: String, fileType: String)? {
        guard let rawData = note.rawData,
              let setting = rawData["setting"] as? [String: Any],
              let settingData = setting["data"] as? [[String: Any]] else {
            return nil
        }
        
        // 查找第一张图片
        for imgData in settingData {
            if let fileId = imgData["fileId"] as? String,
               let mimeType = imgData["mimeType"] as? String,
               mimeType.hasPrefix("image/") {
                let fileType = String(mimeType.dropFirst("image/".count))
                return (fileId: fileId, fileType: fileType)
            }
        }
        
        return nil
    }
    
    func loadThumbnail(imageInfo: (fileId: String, fileType: String)) {
        Task {
            if let imageData = LocalStorageService.shared.loadImage(fileId: imageInfo.fileId, fileType: imageInfo.fileType),
               let nsImage = NSImage(data: imageData) {
                // 创建缩略图（50x50）
                let thumbnailSize = NSSize(width: 50, height: 50)
                let thumbnail = NSImage(size: thumbnailSize)
                
                thumbnail.lockFocus()
                defer { thumbnail.unlockFocus() }
                
                // 计算缩放比例，保持宽高比
                let imageSize = nsImage.size
                let scaleX = thumbnailSize.width / imageSize.width
                let scaleY = thumbnailSize.height / imageSize.height
                let scale = max(scaleX, scaleY)
                
                // 计算缩放后的尺寸
                let scaledSize = NSSize(
                    width: imageSize.width * scale,
                    height: imageSize.height * scale
                )
                
                // 计算居中位置
                let offsetX = (thumbnailSize.width - scaledSize.width) / 2
                let offsetY = (thumbnailSize.height - scaledSize.height) / 2
                
                // 填充背景色
                NSColor.controlBackgroundColor.setFill()
                NSRect(origin: .zero, size: thumbnailSize).fill()
                
                // 绘制图片
                nsImage.draw(
                    in: NSRect(origin: NSPoint(x: offsetX, y: offsetY), size: scaledSize),
                    from: NSRect(origin: .zero, size: imageSize),
                    operation: .sourceOver,
                    fraction: 1.0
                )
                
                await MainActor.run {
                    self.imageView.image = thumbnail
                }
            } else {
                // 如果加载失败，显示占位符
                await MainActor.run {
                    self.imageView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
                }
            }
        }
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
