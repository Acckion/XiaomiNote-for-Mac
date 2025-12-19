import SwiftUI
import AppKit

struct NotesListView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var showingDeleteAlert = false
    @State private var noteToDelete: Note?
    @State private var showingMoveNoteSheet = false
    @State private var noteToMove: Note?
    
    var body: some View {
        List(selection: $viewModel.selectedNote) {
            if viewModel.filteredNotes.isEmpty {
                emptyNotesView
            } else {
                notesListContent
            }
        }
        .listStyle(.sidebar)
        .accentColor(.yellow)  // 设置列表选择颜色为黄色
        .alert("删除笔记", isPresented: $showingDeleteAlert, presenting: noteToDelete) { note in
            deleteAlertButtons(for: note)
        } message: { note in
            deleteAlertMessage(for: note)
        }
        .sheet(isPresented: $showingMoveNoteSheet) {
            if let note = noteToMove {
                moveNoteSheetView(for: note)
            }
        }
        // 移除上传时的加载动画
        // .overlay {
        //     if viewModel.isLoading {
        //         loadingOverlay
        //     }
        // }
    }
    
    private var emptyNotesView: some View {
        ContentUnavailableView(
            "没有笔记",
            systemImage: "note.text",
            description: Text(viewModel.searchText.isEmpty ? "点击 + 创建新笔记" : "尝试其他搜索词")
        )
    }
    
    private var notesListContent: some View {
        Group {
            let groupedNotes = groupNotesByDate(viewModel.filteredNotes)
            
            // 定义分组显示顺序
            let sectionOrder = ["置顶", "今天", "昨天", "本周", "本月", "本年"]
            
            // 先显示固定顺序的分组
            ForEach(sectionOrder, id: \.self) { sectionKey in
                if let notes = groupedNotes[sectionKey], !notes.isEmpty {
                    // 所有时间分组都使用主要样式（大字体和长分割线）
                    let isMajor = true
                    
                    Section {
                        ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                            NoteRow(note: note, showDivider: index < notes.count - 1, viewModel: viewModel)
                                .tag(note)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    swipeActions(for: note)
                                }
                                .contextMenu {
                                    noteContextMenu(for: note)
                                }
                        }
                    } header: {
                        sectionHeader(title: sectionKey, isMajor: isMajor)
                    }
                }
            }
            
            // 然后按年份分组其他笔记（降序排列）
            let yearGroups = groupedNotes.filter { !sectionOrder.contains($0.key) }
            ForEach(yearGroups.keys.sorted(by: >), id: \.self) { year in
                if let notes = yearGroups[year], !notes.isEmpty {
                    // 年份分组也使用主要样式（大字体和长分割线）
                    let isMajor = true
                    
                    Section {
                        ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                            NoteRow(note: note, showDivider: index < notes.count - 1, viewModel: viewModel)
                                .tag(note)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    swipeActions(for: note)
                                }
                                .contextMenu {
                                    noteContextMenu(for: note)
                                }
                        }
                    } header: {
                        sectionHeader(title: year, isMajor: isMajor)
                    }
                }
            }
        }
    }
    
    /// 自定义 Section Header，支持大字体和分割线
    private func sectionHeader(title: String, isMajor: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: isMajor ? 16 : 14, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.bottom, isMajor ? 10 : 6)
            
            // 主要分组（置顶、今天等）使用延伸到边缘的长分割线
            if isMajor {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, -20)  // 负的 leading padding，使分割线延伸到列表窗口最左侧
                    .padding(.bottom, 8)  // 分割线下方留空白
            }
        }
        .padding(.top, isMajor ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    
    private func swipeActions(for note: Note) -> some View {
        Group {
            Button(role: .destructive) {
                noteToDelete = note
                showingDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            
            Button {
                viewModel.toggleStar(note)
            } label: {
                Label(note.isStarred ? "取消置顶" : "置顶备忘录", 
                      systemImage: note.isStarred ? "pin.slash" : "pin")
            }
            .tint(.yellow)
        }
    }
    
    private func deleteAlertButtons(for note: Note) -> some View {
        Group {
            Button("取消", role: .cancel) {
                noteToDelete = nil
            }
            Button("删除", role: .destructive) {
                viewModel.deleteNote(note)
                noteToDelete = nil
            }
        }
    }
    
    private func deleteAlertMessage(for note: Note) -> Text {
        Text("确定要删除 \"\(note.title)\" 吗？此操作无法撤销。")
    }
    
    private var loadingOverlay: some View {
        ProgressView()
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.1))
    }
    
    // MARK: - 右键菜单
    
    @ViewBuilder
    private func noteContextMenu(for note: Note) -> some View {
        // 在新窗口打开备忘录
        Button {
            openNoteInNewWindow(note)
        } label: {
            Label("在新窗口打开备忘录", systemImage: "square.on.square")
        }
        
        Divider()
        
        // 置顶备忘录
        Button {
            viewModel.toggleStar(note)
        } label: {
            Label(note.isStarred ? "取消置顶备忘录" : "置顶备忘录", 
                  systemImage: note.isStarred ? "pin.slash" : "pin")
        }
        
        // 移动备忘录
        Button {
            noteToMove = note
            showingMoveNoteSheet = true
        } label: {
            Label("移动备忘录", systemImage: "folder")
        }
        
        Divider()
        
        // 删除备忘录
        Button(role: .destructive) {
            noteToDelete = note
            showingDeleteAlert = true
        } label: {
            Label("删除备忘录", systemImage: "trash")
        }
        
        // 复制备忘录
        Button {
            copyNote(note)
        } label: {
            Label("复制备忘录", systemImage: "doc.on.doc")
        }
        
        // 新建备忘录
        Button {
            viewModel.createNewNote()
        } label: {
            Label("新建备忘录", systemImage: "square.and.pencil")
        }
        
        Divider()
        
        // 共享备忘录
        Button {
            shareNote(note)
        } label: {
            Label("共享备忘录", systemImage: "square.and.arrow.up")
        }
    }
    
    // MARK: - 菜单操作
    
    private func openNoteInNewWindow(_ note: Note) {
        // 在新窗口打开笔记
        // 使用 NSApplication 创建新窗口
        if NSApplication.shared.keyWindow != nil {
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
        }
    }
    
    private func copyNote(_ note: Note) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // 复制标题和内容
        let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
        pasteboard.setString(content, forType: .string)
    }
    
    private func shareNote(_ note: Note) {
        let sharingService = NSSharingServicePicker(items: [
            note.title,
            note.content
        ])
        
        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView {
            sharingService.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
    
    // MARK: - 移动笔记 Sheet
    
    @ViewBuilder
    private func moveNoteSheetView(for note: Note) -> some View {
        MoveNoteSheetView(note: note, viewModel: viewModel)
    }
}

struct NoteRow: View {
    let note: Note
    let showDivider: Bool
    let viewModel: NotesViewModel?
    @State private var thumbnailImage: NSImage? = nil
    
    init(note: Note, showDivider: Bool = false, viewModel: NotesViewModel? = nil) {
        self.note = note
        self.showDivider = showDivider
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title.isEmpty ? "无标题" : note.title)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Text(formatDate(note.updatedAt))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        Text(extractPreviewText(from: note.content))
                            .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // 图片预览（如果有图片）
                if let imageInfo = getFirstImageInfo(from: note) {
                    Group {
                        if let nsImage = thumbnailImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                    .onAppear {
                        loadThumbnail(imageInfo: imageInfo)
                    }
                }
                
                // 锁图标（如果有）
                if note.rawData?["isLocked"] as? Bool == true {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            
            // 分割线：放在笔记项之间的中间位置，向下偏移一点以居中
            if showDivider {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)  // 与文字左对齐
                    .padding(.top, 8)  // 向下偏移，使分割线位于两个笔记项之间
            }
        }
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
    
    /// 从 XML 内容中提取预览文本（去除 XML 标签，返回纯文本开头部分）
    private func extractPreviewText(from xmlContent: String) -> String {
        guard !xmlContent.isEmpty else {
            return ""
        }
        
        // 移除 XML 标签，提取纯文本
        var text = xmlContent
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)  // 移除所有 XML 标签
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
    
    /// 从笔记中提取第一张图片的信息
    private func getFirstImageInfo(from note: Note) -> (fileId: String, fileType: String)? {
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
    
    /// 加载缩略图
    private func loadThumbnail(imageInfo: (fileId: String, fileType: String)) {
        // 在后台线程加载图片
        Task {
            if let imageData = LocalStorageService.shared.loadImage(fileId: imageInfo.fileId, fileType: imageInfo.fileType),
               let nsImage = NSImage(data: imageData) {
                // 创建缩略图（50x50）
                let thumbnailSize = NSSize(width: 50, height: 50)
                let thumbnail = NSImage(size: thumbnailSize)
                thumbnail.lockFocus()
                nsImage.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                            from: NSRect(origin: .zero, size: nsImage.size),
                            operation: .sourceOver,
                            fraction: 1.0)
                thumbnail.unlockFocus()
                
                await MainActor.run {
                    self.thumbnailImage = thumbnail
                }
            }
        }
    }
}

#Preview {
    NotesListView(viewModel: NotesViewModel())
}
