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
            
            // 检查是否为私密笔记
            if note.folderId == "2" {
                // 私密笔记：需要验证密码
                let passwordManager = PrivateNotesPasswordManager.shared
                
                if passwordManager.hasPassword() {
                    // 已设置密码，需要验证
                    // 显示密码输入对话框
                    let passwordDialog = PrivateNotesPasswordInputDialogView(viewModel: newViewModel)
                    let hostingView = NSHostingView(rootView: passwordDialog)
                    
                    // 创建对话框窗口
                    let dialogWindow = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                        styleMask: [.titled, .closable],
                        backing: .buffered,
                        defer: false
                    )
                    dialogWindow.title = "访问私密笔记"
                    dialogWindow.contentView = hostingView
                    dialogWindow.center()
                    
                    // 显示对话框
                    NSApplication.shared.runModal(for: dialogWindow)
                    
                    // 检查是否已解锁
                    if !newViewModel.isPrivateNotesUnlocked {
                        // 用户取消或验证失败，不打开新窗口
                        dialogWindow.close()
                        return
                    }
                    
                    dialogWindow.close()
                } else {
                    // 未设置密码，直接允许访问
                    newViewModel.isPrivateNotesUnlocked = true
                }
            }
            
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
    @State private var currentImageFileId: String? = nil // 跟踪当前显示的图片ID
    @State private var imageRefreshTrigger = UUID() // 强制刷新触发器
    
    init(note: Note, showDivider: Bool = false, viewModel: NotesViewModel? = nil) {
        self.note = note
        self.showDivider = showDivider
        self.viewModel = viewModel
    }
    
    /// 是否应该显示文件夹信息
    /// 当满足以下条件之一时显示：
    /// 1. 菜单栏中选中的文件夹是"所有笔记"（id="0"）
    /// 2. 有搜索文本
    /// 3. 有搜索筛选选项
    private var shouldShowFolderInfo: Bool {
        guard let viewModel = viewModel else { return false }
        
        // 检查是否有搜索文本
        let hasSearchText = !viewModel.searchText.isEmpty
        
        // 检查是否有搜索筛选选项
        let hasSearchFilters = viewModel.searchFilterHasTags || 
                              viewModel.searchFilterHasChecklist || 
                              viewModel.searchFilterHasImages || 
                              viewModel.searchFilterHasAudio || 
                              viewModel.searchFilterIsPrivate
        
        // 检查菜单栏中选中的文件夹是否是"所有笔记"
        let isAllNotesFolder = viewModel.selectedFolder?.id == "0"
        
        return isAllNotesFolder || hasSearchText || hasSearchFilters
    }
    
    /// 获取文件夹名称
    private func getFolderName(for folderId: String) -> String {
        guard let viewModel = viewModel else { return folderId }
        
        // 系统文件夹的特殊处理
        if folderId == "0" {
            return "所有笔记"
        } else if folderId == "starred" {
            return "置顶"
        } else if folderId == "2" {
            return "私密笔记"
        } else if folderId == "uncategorized" {
            return "未分类"
        }
        
        // 从文件夹列表中查找
        if let folder = viewModel.folders.first(where: { $0.id == folderId }) {
            return folder.name
        }
        
        // 如果找不到，返回文件夹ID
        return folderId
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    // 标题 - 支持搜索高亮
                    if let viewModel = viewModel, !viewModel.searchText.isEmpty {
                        highlightText(hasRealTitle() ? note.title : "无标题", searchText: viewModel.searchText)
                            .font(.system(size: 14))
                            .lineLimit(1)
                    } else {
                        Text(hasRealTitle() ? note.title : "无标题")
                            .font(.system(size: 14))
                            .lineLimit(1)
                            .foregroundColor(hasRealTitle() ? .primary : .secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Text(formatDate(note.updatedAt))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        // 预览文本 - 支持搜索高亮
                        if let viewModel = viewModel, !viewModel.searchText.isEmpty {
                            highlightPreviewText(from: note.content, searchText: viewModel.searchText)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(extractPreviewText(from: note.content))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // 文件夹信息（在特定条件下显示）
                    if shouldShowFolderInfo {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(getFolderName(for: note.folderId))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.top, 2)
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
                    .clipped() // 确保超出部分被剪裁
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                    .id(imageRefreshTrigger) // 使用触发器强制视图重建
                    .onAppear {
                        // 首次加载或图片ID变化时，重新加载
                        if currentImageFileId != imageInfo.fileId {
                            print("[NoteRow] onAppear: 加载缩略图，fileId: \(imageInfo.fileId)")
                            loadThumbnail(imageInfo: imageInfo)
                            currentImageFileId = imageInfo.fileId
                        }
                    }
                    .onChange(of: imageInfo.fileId) { oldValue, newValue in
                        // 图片ID变化时，重新加载
                        if currentImageFileId != newValue {
                            print("[NoteRow] onChange(fileId): 图片ID变化，重新加载缩略图: \(oldValue ?? "nil") -> \(newValue)")
                            loadThumbnail(imageInfo: imageInfo)
                            currentImageFileId = newValue
                        }
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
            .onChange(of: note.content) { oldValue, newValue in
                // 笔记内容变化时，重新检查并更新图片
                print("[NoteRow] onChange(content): 笔记内容变化，更新缩略图")
                updateThumbnail()
            }
            .onChange(of: note.updatedAt) { oldValue, newValue in
                // 更新时间变化时，重新检查并更新图片
                print("[NoteRow] onChange(updatedAt): 更新时间变化，更新缩略图")
                updateThumbnail()
            }
            .onChange(of: noteImageHash) { oldValue, newValue in
                // 图片信息哈希值变化时，强制更新缩略图
                // 这确保当图片插入/删除时能正确刷新
                print("[NoteRow] onChange(noteImageHash): 图片信息哈希值变化 (\(oldValue) -> \(newValue))，更新缩略图")
                updateThumbnail()
            }
            // 注意：不能直接使用 onChange(of: note.rawData)，因为 [String: Any]? 不符合 Equatable
            // 我们使用 noteImageHash 来检测图片变化，它已经包含了 rawData 中的图片信息
            
            // 分割线：放在笔记项之间的中间位置，向下偏移一点以居中
            if showDivider {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)  // 与文字左对齐
                    .padding(.top, 10)  // 向下偏移，使分割线位于两个笔记项之间
            }
        }
    }
    
    /// 检查笔记是否有真正的标题（不是从内容中提取的）
    /// 判断逻辑：
    /// 1. 如果标题为空，返回 false
    /// 2. 如果标题是"未命名笔记_xxx"格式，返回 false
    /// 3. 检查 rawData 中的 extraInfo 是否有真正的标题
    /// 4. 如果标题与内容的第一行匹配（去除XML标签后），返回 false（处理旧数据）
    /// 5. 否则返回 true（有真正的标题）
    private func hasRealTitle() -> Bool {
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
    
    /// 获取图片信息的哈希值，用于检测变化
    private func getImageInfoHash(from note: Note) -> String {
        guard let rawData = note.rawData,
              let setting = rawData["setting"] as? [String: Any],
              let settingData = setting["data"] as? [[String: Any]] else {
            return "no_images"
        }
        
        // 提取所有图片信息并生成哈希
        var imageInfos: [String] = []
        for imgData in settingData {
            if let fileId = imgData["fileId"] as? String,
               let mimeType = imgData["mimeType"] as? String,
               mimeType.hasPrefix("image/") {
                imageInfos.append("\(fileId):\(mimeType)")
            }
        }
        
        if imageInfos.isEmpty {
            return "no_images"
        }
        
        // 排序以确保一致的哈希
        return imageInfos.sorted().joined(separator: "|")
    }
    
    /// 检查 rawData 变化并更新缩略图
    private func checkAndUpdateThumbnailForRawDataChange(oldValue: [String: Any]?, newValue: [String: Any]?) {
        let oldImageHash = getImageInfoHash(from: Note(id: "", title: "", content: "", folderId: "", createdAt: Date(), updatedAt: Date(), rawData: oldValue))
        let newImageHash = getImageInfoHash(from: Note(id: "", title: "", content: "", folderId: "", createdAt: Date(), updatedAt: Date(), rawData: newValue))
        
        if oldImageHash != newImageHash {
            print("[NoteRow] rawData变化检测到图片哈希变化: \(oldImageHash) -> \(newImageHash)")
            // 强制刷新触发器，确保视图重建
            imageRefreshTrigger = UUID()
            updateThumbnail()
        }
    }
    
    /// 当前笔记的图片哈希值（计算属性）
    private var noteImageHash: String {
        getImageInfoHash(from: note)
    }
    
    /// 更新缩略图（根据当前笔记内容）
    private func updateThumbnail() {
        print("[NoteRow] updateThumbnail: 开始更新缩略图")
        
        if let imageInfo = getFirstImageInfo(from: note) {
            print("[NoteRow] updateThumbnail: 找到图片信息，fileId: \(imageInfo.fileId), currentImageFileId: \(currentImageFileId ?? "nil")")
            
            // 如果图片ID变化了，重新加载
            if currentImageFileId != imageInfo.fileId {
                print("[NoteRow] updateThumbnail: 图片ID变化，重新加载缩略图")
                loadThumbnail(imageInfo: imageInfo)
                currentImageFileId = imageInfo.fileId
            } else {
                print("[NoteRow] updateThumbnail: 图片ID未变化，检查是否需要重新加载")
                // 即使ID相同，也检查图片文件是否存在
                Task {
                    if let imageData = LocalStorageService.shared.loadImage(fileId: imageInfo.fileId, fileType: imageInfo.fileType),
                       let nsImage = NSImage(data: imageData) {
                        await MainActor.run {
                            // 如果当前没有缩略图或需要更新，重新加载
                            if thumbnailImage == nil {
                                print("[NoteRow] updateThumbnail: 当前没有缩略图，重新加载")
                                loadThumbnail(imageInfo: imageInfo)
                            }
                        }
                    } else {
                        print("[NoteRow] updateThumbnail: 图片文件不存在，清空缩略图")
                        await MainActor.run {
                            thumbnailImage = nil
                        }
                    }
                }
            }
        } else {
            print("[NoteRow] updateThumbnail: 没有找到图片信息")
            // 如果没有图片了，清空缩略图
            if currentImageFileId != nil || thumbnailImage != nil {
                print("[NoteRow] updateThumbnail: 清空缩略图状态")
                currentImageFileId = nil
                thumbnailImage = nil
                // 强制刷新触发器，确保视图更新
                imageRefreshTrigger = UUID()
            }
        }
    }
    
    /// 加载缩略图
    private func loadThumbnail(imageInfo: (fileId: String, fileType: String)) {
        print("[NoteRow] loadThumbnail: 开始加载缩略图，fileId: \(imageInfo.fileId), fileType: \(imageInfo.fileType)")
        
        // 在后台线程加载图片
        Task {
            if let imageData = LocalStorageService.shared.loadImage(fileId: imageInfo.fileId, fileType: imageInfo.fileType) {
                print("[NoteRow] loadThumbnail: 成功加载图片数据，大小: \(imageData.count) 字节")
                
                if let nsImage = NSImage(data: imageData) {
                    print("[NoteRow] loadThumbnail: 成功创建NSImage，尺寸: \(nsImage.size)")
                    
                    // 创建缩略图（50x50），使用剪裁模式而不是拉伸
                    let thumbnailSize = NSSize(width: 50, height: 50)
                    let thumbnail = NSImage(size: thumbnailSize)
                    
                    thumbnail.lockFocus()
                    defer { thumbnail.unlockFocus() }
                    
                    // 计算缩放比例，保持宽高比
                    let imageSize = nsImage.size
                    let scaleX = thumbnailSize.width / imageSize.width
                    let scaleY = thumbnailSize.height / imageSize.height
                    let scale = max(scaleX, scaleY) // 使用较大的缩放比例，确保覆盖整个区域
                    
                    // 计算缩放后的尺寸
                    let scaledSize = NSSize(
                        width: imageSize.width * scale,
                        height: imageSize.height * scale
                    )
                    
                    // 计算居中位置
                    let offsetX = (thumbnailSize.width - scaledSize.width) / 2
                    let offsetY = (thumbnailSize.height - scaledSize.height) / 2
                    
                    // 填充背景色（可选）
                    NSColor.controlBackgroundColor.setFill()
                    NSRect(origin: .zero, size: thumbnailSize).fill()
                    
                    // 绘制图片（居中，可能会超出边界，但会被 clipShape 剪裁）
                    nsImage.draw(
                        in: NSRect(origin: NSPoint(x: offsetX, y: offsetY), size: scaledSize),
                        from: NSRect(origin: .zero, size: imageSize),
                        operation: .sourceOver,
                        fraction: 1.0
                    )
                    
                    await MainActor.run {
                        print("[NoteRow] loadThumbnail: 设置缩略图")
                        self.thumbnailImage = thumbnail
                        // 更新刷新触发器，确保视图更新
                        self.imageRefreshTrigger = UUID()
                    }
                } else {
                    print("[NoteRow] loadThumbnail: 无法从数据创建NSImage")
                    await MainActor.run {
                        self.thumbnailImage = nil
                    }
                }
            } else {
                print("[NoteRow] loadThumbnail: 无法加载图片数据，fileId: \(imageInfo.fileId)")
                await MainActor.run {
                    self.thumbnailImage = nil
                }
            }
        }
    }
    
    /// 高亮显示文本中的搜索关键词
    private func highlightText(_ text: String, searchText: String) -> Text {
        guard !searchText.isEmpty else {
            return Text(text)
        }
        
        let lowercasedText = text.lowercased()
        let lowercasedSearchText = searchText.lowercased()
        
        // 查找所有匹配的位置
        var ranges: [Range<String.Index>] = []
        var searchStartIndex = lowercasedText.startIndex
        
        while let range = lowercasedText.range(of: lowercasedSearchText, range: searchStartIndex..<lowercasedText.endIndex) {
            ranges.append(range)
            searchStartIndex = range.upperBound
        }
        
        // 如果没有匹配，返回普通文本
        if ranges.isEmpty {
            return Text(text)
                .foregroundColor(.primary)
        }
        
        // 构建高亮文本
        var resultText = Text(verbatim: "")
        var currentIndex = text.startIndex
        
        for range in ranges {
            // 添加匹配前的文本
            if currentIndex < range.lowerBound {
                let beforeMatch = String(text[currentIndex..<range.lowerBound])
                resultText = resultText + Text(verbatim: beforeMatch)
            }
            
            // 添加高亮的匹配文本
            let matchText = String(text[range])
            resultText = resultText + Text(verbatim: matchText)
                .foregroundColor(.yellow)  // 使用主题色黄色
                .fontWeight(.medium)
            
            currentIndex = range.upperBound
        }
        
        // 添加剩余的文本
        if currentIndex < text.endIndex {
            let remainingText = String(text[currentIndex..<text.endIndex])
            resultText = resultText + Text(verbatim: remainingText)
        }
        
        return resultText
    }
    
    /// 高亮显示预览文本中的搜索关键词
    private func highlightPreviewText(from xmlContent: String, searchText: String) -> Text {
        guard !searchText.isEmpty else {
            return Text(extractPreviewText(from: xmlContent))
                .foregroundColor(.secondary)
        }
        
        // 提取纯文本预览
        let previewText = extractPreviewText(from: xmlContent)
        
        // 如果预览文本是"无内容"，直接返回
        if previewText == "无内容" {
            return Text(previewText)
                .foregroundColor(.secondary)
        }
        
        let lowercasedText = previewText.lowercased()
        let lowercasedSearchText = searchText.lowercased()
        
        // 查找所有匹配的位置
        var ranges: [Range<String.Index>] = []
        var searchStartIndex = lowercasedText.startIndex
        
        while let range = lowercasedText.range(of: lowercasedSearchText, range: searchStartIndex..<lowercasedText.endIndex) {
            ranges.append(range)
            searchStartIndex = range.upperBound
        }
        
        // 如果没有匹配，返回普通文本
        if ranges.isEmpty {
            return Text(previewText)
                .foregroundColor(.secondary)
        }
        
        // 构建高亮文本
        var resultText = Text(verbatim: "")
        var currentIndex = previewText.startIndex
        
        for range in ranges {
            // 添加匹配前的文本
            if currentIndex < range.lowerBound {
                let beforeMatch = String(previewText[currentIndex..<range.lowerBound])
                resultText = resultText + Text(verbatim: beforeMatch)
                    .foregroundColor(.secondary)
            }
            
            // 添加高亮的匹配文本
            let matchText = String(previewText[range])
            resultText = resultText + Text(verbatim: matchText)
                .foregroundColor(.yellow)  // 使用主题色黄色
                .fontWeight(.medium)
            
            currentIndex = range.upperBound
        }
        
        // 添加剩余的文本
        if currentIndex < previewText.endIndex {
            let remainingText = String(previewText[currentIndex..<previewText.endIndex])
            resultText = resultText + Text(verbatim: remainingText)
                .foregroundColor(.secondary)
        }
        
        return resultText
    }
}

#Preview {
    NotesListView(viewModel: NotesViewModel())
}
