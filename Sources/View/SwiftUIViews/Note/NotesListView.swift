import SwiftUI
import AppKit

// MARK: - ListAnimationConfig

/// 列表动画配置
/// _Requirements: 1.2_
enum ListAnimationConfig {
    /// 列表项移动动画（300ms easeInOut）
    static let moveAnimation: Animation = .easeInOut(duration: 0.3)
}

// MARK: - NoteDisplayProperties

/// 笔记显示属性（用于 Equatable 比较）
/// 
/// 只包含影响 NoteRow 显示的属性，用于优化视图重建逻辑。
/// 当非显示属性（如 rawData 中的某些字段）变化时，不会触发 NoteRow 重建。
/// 
/// **包含的显示属性**：
/// - id: 笔记唯一标识符
/// - title: 笔记标题
/// - content: 笔记内容（用于预览文本提取）
/// - updatedAt: 更新时间（用于显示日期和排序）
/// - isStarred: 置顶状态
/// - folderId: 文件夹ID（用于显示文件夹名称）
/// - isLocked: 锁定状态（用于显示锁图标）
/// - imageInfoHash: 图片信息哈希（用于显示缩略图）
/// 
/// **不包含的非显示属性**：
/// - createdAt: 创建时间（不在列表中显示）
/// - tags: 标签（不在列表行中显示）
/// - rawData 中的其他字段（如 extraInfo、setting 中的非图片数据等）
/// 
/// _Requirements: 5.3, 5.4_
struct NoteDisplayProperties: Equatable, Hashable {
    let id: String
    let title: String
    let contentPreview: String  // 预览文本，而非完整内容
    let updatedAt: Date
    let isStarred: Bool
    let folderId: String
    let isLocked: Bool
    let imageInfoHash: String
    
    /// 从 Note 对象创建显示属性
    /// - Parameter note: 笔记对象
    init(from note: Note) {
        self.id = note.id
        self.title = note.title
        self.contentPreview = NoteDisplayProperties.extractPreviewText(from: note.content)
        self.updatedAt = note.updatedAt
        self.isStarred = note.isStarred
        self.folderId = note.folderId
        self.isLocked = note.rawData?["isLocked"] as? Bool ?? false
        self.imageInfoHash = NoteDisplayProperties.getImageInfoHash(from: note)
    }
    
    /// 从 XML 内容中提取预览文本
    /// - Parameter xmlContent: XML 格式的笔记内容
    /// - Returns: 纯文本预览（最多50个字符）
    private static func extractPreviewText(from xmlContent: String) -> String {
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
        
        // 限制长度
        let maxLength = 50
        if text.count > maxLength {
            text = String(text.prefix(maxLength)) + "..."
        }
        
        return text
    }
    
    /// 获取图片信息的哈希值
    /// - Parameter note: 笔记对象
    /// - Returns: 图片信息哈希字符串
    private static func getImageInfoHash(from note: Note) -> String {
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
}

// MARK: - PinnedNoteRowContent

/// 固定分组标题列表中的笔记行内容视图
/// 
/// 这是一个独立的子视图，用于正确追踪 `selectedNote` 的变化。
/// 通过将选择状态逻辑封装在独立视图中，确保 SwiftUI 能正确检测依赖变化并更新 UI。
/// 
/// **问题背景**：
/// 在 `LazyVStack` 中，闭包捕获的值可能不会随着 `@Published` 属性的变化而更新，
/// 导致选择状态（高亮）显示不正确。
/// 
/// **解决方案**：
/// 使用独立的 `@ObservedObject` 视图来观察 `viewModel`，确保当 `selectedNote` 变化时，
/// 视图能正确重新计算 `isSelected` 并更新高亮状态。
/// 
/// _Requirements: 2.1, 2.2, 2.3_
struct PinnedNoteRowContent<ContextMenu: View>: View {
    let note: Note
    let showDivider: Bool
    @ObservedObject var viewModel: NotesViewModel
    @Binding var isSelectingNote: Bool
    let contextMenuBuilder: () -> ContextMenu
    
    /// 计算当前笔记是否被选中
    /// 每次视图重新评估时都会重新计算
    private var isSelected: Bool {
        viewModel.selectedNote?.id == note.id
    }
    
    var body: some View {
        NoteRow(note: note, showDivider: showDivider, viewModel: viewModel)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected 
                          ? Color.accentColor.opacity(0.65) 
                          : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap()
            }
            .contextMenu {
                contextMenuBuilder()
            }
            // 使用 note.id 作为视图标识，确保视图稳定性
            // 选择状态通过 @ObservedObject 自动更新，不需要在 id 中包含 isSelected
            .id(note.id)
    }
    
    /// 处理点击事件
    private func handleTap() {
        let currentSelectedId = viewModel.selectedNote?.id
        Swift.print("[PinnedNoteRowContent] 点击笔记 - ID: \(note.id.prefix(8))..., 当前选中: \(currentSelectedId?.prefix(8) ?? "nil"), isSelected: \(isSelected)")
        
        // 如果点击的是已选中的笔记，不需要做任何事情
        // _Requirements: 2.3_
        if currentSelectedId == note.id {
            Swift.print("[PinnedNoteRowContent] 点击已选中的笔记，无需操作")
            return
        }
        
        // 设置选择标志，禁用选择期间的动画
        // _Requirements: 2.1, 2.2, 2.3_
        isSelectingNote = true
        viewModel.selectedNote = note
        Swift.print("[PinnedNoteRowContent] 设置 selectedNote 为 \(note.id.prefix(8))...")
        
        // 延迟重置选择标志，确保动画禁用生效
        // 延长到 1.5 秒以覆盖 ensureNoteHasFullContent 等异步操作
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSelectingNote = false
        }
    }
}

// MARK: - NotesListView

struct NotesListView: View {
    @ObservedObject var viewModel: NotesViewModel
    /// 视图选项管理器，用于控制日期分组开关
    /// _Requirements: 3.3, 3.4_
    @ObservedObject var optionsManager: ViewOptionsManager = .shared
    @State private var showingDeleteAlert = false
    @State private var noteToDelete: Note?
    @State private var showingMoveNoteSheet = false
    @State private var noteToMove: Note?
    /// 列表标识符，用于在文件夹切换时强制重建列表（避免动画）
    @State private var listId = UUID()
    /// 是否正在进行选择操作，用于禁用选择期间的动画
    /// _Requirements: 2.1, 2.2, 2.3_
    @State private var isSelectingNote = false
    
    var body: some View {
        Group {
            // 检查是否是私密笔记文件夹且未解锁
            if let folder = viewModel.selectedFolder, folder.id == "2", !viewModel.isPrivateNotesUnlocked {
                // 私密笔记未解锁，显示锁定状态
                List {
                    ContentUnavailableView(
                        "此笔记已锁定",
                        systemImage: "lock.fill",
                        description: Text("使用触控 ID 或输入密码查看此笔记")
                    )
                }
                .listStyle(.sidebar)
            } else if viewModel.filteredNotes.isEmpty {
                List {
                    emptyNotesView
                }
                .listStyle(.sidebar)
            } else if optionsManager.isDateGroupingEnabled {
                // 分组模式：使用 ScrollView + LazyVStack 实现固定分组标题
                // _Requirements: 3.3, 固定分组标题_
                pinnedHeadersListContent
            } else {
                // 平铺模式：使用标准 List
                standardListContent
            }
        }
        .scrollContentBackground(.hidden) // 隐藏默认的滚动内容背景
        .background(Color(NSColor.windowBackgroundColor)) // 设置不透明背景色
        // 使用 id 修饰符，在文件夹切换时强制重建列表（避免动画）
        .id(listId)
        // 监听 filteredNotes 变化，触发列表移动动画
        // 只有在非选择操作时才触发动画，避免选择笔记时的错误移动
        // _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3_
        .animation(isSelectingNote ? nil : ListAnimationConfig.moveAnimation, value: viewModel.filteredNotes.map(\.id))
        // 监听日期分组状态变化，触发过渡动画
        // _Requirements: 3.7_
        .animation(.easeInOut(duration: 0.3), value: optionsManager.isDateGroupingEnabled)
        // 监听文件夹切换，更新 listId 强制重建列表
        .onChange(of: viewModel.selectedFolder?.id) { oldValue, newValue in
            // 文件夹切换时，更新 listId 强制重建列表，避免动画
            listId = UUID()
        }
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
        // 监听笔记选择变化，通过 coordinator 进行状态管理
        // **Requirements: 1.1, 1.2**
        // - 1.1: 编辑笔记内容时保持选中状态不变
        // - 1.2: 笔记内容保存触发 notes 数组更新时不重置 selectedNote
        .onChange(of: viewModel.selectedNote) { oldValue, newValue in
            // 添加日志追踪选择状态变化
            let oldId = oldValue?.id.prefix(8) ?? "nil"
            let newId = newValue?.id.prefix(8) ?? "nil"
            Swift.print("[NotesListView] 📊 selectedNote 变化: \(oldId) -> \(newId)")
            
            // 只有当选择真正变化时才通知 coordinator
            if oldValue?.id != newValue?.id {
                Swift.print("[NotesListView] 🔄 选择 ID 变化，通知 coordinator")
                Task {
                    await viewModel.stateCoordinator.selectNote(newValue)
                }
            } else {
                Swift.print("[NotesListView] ⏭️ 选择 ID 未变化，跳过 coordinator 通知")
            }
        }
    }
    
    // MARK: - 固定分组标题的列表内容
    
    /// 使用 ScrollView + LazyVStack 实现固定分组标题
    /// 当开启日期分组时使用此视图，分组标题会在滚动时固定在顶部
    /// _Requirements: 3.3, 固定分组标题_
    private var pinnedHeadersListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                let groupedNotes = groupNotesByDate(viewModel.filteredNotes)
                
                // 定义分组显示顺序
                let sectionOrder = ["置顶", "今天", "昨天", "本周", "本月", "本年"]
                
                // 先显示固定顺序的分组
                ForEach(sectionOrder, id: \.self) { sectionKey in
                    if let notes = groupedNotes[sectionKey], !notes.isEmpty {
                        Section {
                            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                                pinnedNoteRow(note: note, showDivider: index < notes.count - 1)
                            }
                        } header: {
                            pinnedSectionHeader(title: sectionKey)
                        }
                    }
                }
                
                // 然后按年份分组其他笔记（降序排列）
                let yearGroups = groupedNotes.filter { !sectionOrder.contains($0.key) }
                ForEach(yearGroups.keys.sorted(by: >), id: \.self) { year in
                    if let notes = yearGroups[year], !notes.isEmpty {
                        Section {
                            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                                pinnedNoteRow(note: note, showDivider: index < notes.count - 1)
                            }
                        } header: {
                            pinnedSectionHeader(title: year)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8) // 增加底部边距，避免最后一个笔记与底部距离太近
        }
        .background(Color(NSColor.windowBackgroundColor))
        // 注意：不再使用 .id() 强制重建整个 ScrollView
        // 选择状态通过 PinnedNoteRowContent 子视图的 @ObservedObject 自动更新
        // 这样可以保持滚动位置，同时正确更新高亮状态
        // _Requirements: 2.2, 2.3_
    }
    
    /// 固定分组标题的笔记行
    /// _Requirements: 2.1, 2.2, 2.3_
    @ViewBuilder
    private func pinnedNoteRow(note: Note, showDivider: Bool) -> some View {
        // 使用独立的子视图来处理选择状态，确保 SwiftUI 能正确追踪依赖
        PinnedNoteRowContent(
            note: note,
            showDivider: showDivider,
            viewModel: viewModel,
            isSelectingNote: $isSelectingNote,
            contextMenuBuilder: { noteContextMenu(for: note) }
        )
    }
    
    /// 固定分组标题样式
    /// 使用不透明背景确保滚动时内容不会透过标题显示
    private func pinnedSectionHeader(title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.bottom, 10)
            
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, -10)  // 负的水平 padding，使分割线向左右两侧延伸到边缘
                .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor)) // 不透明背景，确保固定时遮挡下方内容
    }
    
    // MARK: - 标准列表内容（平铺模式）
    
    /// 标准 List 视图，用于平铺模式（不分组）
    /// _Requirements: 2.1, 2.2, 2.3_
    private var standardListContent: some View {
        List(selection: Binding(
            get: { viewModel.selectedNote },
            set: { newValue in
                // 设置选择标志，禁用选择期间的动画
                // _Requirements: 2.1, 2.2, 2.3_
                isSelectingNote = true
                viewModel.selectedNote = newValue
                // 延迟重置选择标志，确保动画禁用生效
                // 延长到 1.5 秒以覆盖 ensureNoteHasFullContent 等异步操作
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isSelectingNote = false
                }
            }
        )) {
            flatNotesContent
        }
        .listStyle(.sidebar)
    }
    
    private var emptyNotesView: some View {
        ContentUnavailableView(
            "没有笔记",
            systemImage: "note.text",
            description: Text(viewModel.searchText.isEmpty ? "点击 + 创建新笔记" : "尝试其他搜索词")
        )
    }
    
    /// 平铺显示的笔记内容（不带分组头）
    /// _Requirements: 3.4_
    private var flatNotesContent: some View {
        ForEach(Array(viewModel.filteredNotes.enumerated()), id: \.element.id) { index, note in
            NoteRow(note: note, showDivider: index < viewModel.filteredNotes.count - 1, viewModel: viewModel)
                .tag(note)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    swipeActions(for: note)
                }
                .contextMenu {
                    noteContextMenu(for: note)
                }
        }
    }
    
    private func groupNotesByDate(_ notes: [Note]) -> [String: [Note]] {
        var grouped: [String: [Note]] = [:]
        let calendar = Calendar.current
        let now = Date()
        
        // 根据排序方式决定使用哪个日期字段
        // _Requirements: 2.3, 3.3_
        let useCreateDate = optionsManager.sortOrder == .createDate
        
        // 先分离置顶笔记
        let pinnedNotes = notes.filter { $0.isStarred }
        let unpinnedNotes = notes.filter { !$0.isStarred }
        
        // 处理置顶笔记
        if !pinnedNotes.isEmpty {
            // 置顶笔记也按选定的日期字段排序（使用稳定排序）
            grouped["置顶"] = pinnedNotes.sorted { 
                let date1 = useCreateDate ? $0.createdAt : $0.updatedAt
                let date2 = useCreateDate ? $1.createdAt : $1.updatedAt
                if date1 == date2 {
                    return $0.id > $1.id  // 降序排列时，id 也降序
                }
                return date1 > date2
            }
        }
        
        // 处理非置顶笔记
        for note in unpinnedNotes {
            // 根据排序方式选择日期字段
            let date = useCreateDate ? note.createdAt : note.updatedAt
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
        
        // 对每个分组内的笔记按选定的日期字段降序排序（使用稳定排序）
        for key in grouped.keys {
            grouped[key] = grouped[key]?.sorted { 
                let date1 = useCreateDate ? $0.createdAt : $0.updatedAt
                let date2 = useCreateDate ? $1.createdAt : $1.updatedAt
                if date1 == date2 {
                    return $0.id > $1.id  // 降序排列时，id 也降序
                }
                return date1 > date2
            }
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
                Label(note.isStarred ? "取消置顶" : "置顶笔记", 
                      systemImage: note.isStarred ? "pin.slash" : "pin")
            }
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
        // 在新窗口打开笔记
        Button {
            openNoteInNewWindow(note)
        } label: {
            Label("在新窗口打开笔记", systemImage: "square.on.square")
        }
        
        Divider()
        
        // 置顶笔记
        Button {
            viewModel.toggleStar(note)
        } label: {
            Label(note.isStarred ? "取消置顶笔记" : "置顶笔记", 
                  systemImage: note.isStarred ? "pin.slash" : "pin")
        }
        
        // 移动笔记（使用菜单）
        Menu("移到") {
            // 未分类文件夹（folderId为"0"）
            Button {
                NoteMoveHelper.moveToUncategorized(note, using: viewModel) { result in
                    switch result {
                    case .success:
                        print("[NotesListView] 笔记移动到未分类成功: \(note.id)")
                    case .failure(let error):
                        print("[NotesListView] 移动到未分类失败: \(error.localizedDescription)")
                    }
                }
            } label: {
                Label("未分类", systemImage: "folder.badge.questionmark")
            }
            
            // 其他可用文件夹
            let availableFolders = NoteMoveHelper.getAvailableFolders(for: viewModel)
            
            if !availableFolders.isEmpty {
                Divider()
                
                ForEach(availableFolders, id: \.id) { folder in
                    Button {
                        moveNoteToFolder(note: note, folder: folder)
                    } label: {
                        Label(folder.name, systemImage: folder.isPinned ? "pin.fill" : "folder")
                    }
                }
            }
        }
        
        Divider()
        
        // 删除笔记
        Button(role: .destructive) {
            noteToDelete = note
            showingDeleteAlert = true
        } label: {
            Label("删除笔记", systemImage: "trash")
        }
        
        // 复制笔记
        Button {
            copyNote(note)
        } label: {
            Label("复制笔记", systemImage: "doc.on.doc")
        }
        
        // 新建笔记
        Button {
            viewModel.createNewNote()
        } label: {
            Label("新建笔记", systemImage: "square.and.pencil")
        }
        
        Divider()
        
        // 共享笔记
        Button {
            shareNote(note)
        } label: {
            Label("共享笔记", systemImage: "square.and.arrow.up")
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
    
    // MARK: - 移动笔记功能
    
    private func moveNoteToFolder(note: Note, folder: Folder) {
        NoteMoveHelper.moveNote(note, to: folder, using: viewModel) { result in
            switch result {
            case .success:
                print("[NotesListView] 笔记移动成功: \(note.id) -> \(folder.name)")
            case .failure(let error):
                print("[NotesListView] 移动笔记失败: \(error.localizedDescription)")
            }
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
    @ObservedObject var viewModel: NotesViewModel
    @ObservedObject var optionsManager: ViewOptionsManager = .shared
    @State private var thumbnailImage: NSImage? = nil
    @State private var currentImageFileId: String? = nil // 跟踪当前显示的图片ID
    
    /// 用于比较的显示属性
    /// 只有当这些属性变化时，才会触发视图重建
    /// _Requirements: 5.3, 5.4_
    private var displayProperties: NoteDisplayProperties {
        NoteDisplayProperties(from: note)
    }
    
    /// 根据排序方式获取要显示的日期
    /// _Requirements: 1.1, 1.2, 1.3_
    private var displayDate: Date {
        switch optionsManager.sortOrder {
        case .createDate:
            return note.createdAt
        case .editDate, .title:
            return note.updatedAt
        }
    }
    
    init(note: Note, showDivider: Bool = false, viewModel: NotesViewModel) {
        self.note = note
        self.showDivider = showDivider
        self.viewModel = viewModel
    }
    
    // MARK: - 同步状态
    
    /// 笔记是否有待处理上传
    /// _需求: 6.2_
    private var hasPendingUpload: Bool {
        viewModel.hasPendingUpload(for: note.id)
    }
    
    /// 笔记是否使用临时 ID（离线创建）
    /// _需求: 6.2_
    private var isTemporaryIdNote: Bool {
        viewModel.isTemporaryIdNote(note.id)
    }
    
    /// 同步状态指示器
    /// 显示"未同步"图标或"离线创建"标记
    /// _需求: 6.2_
    @ViewBuilder
    private var syncStatusIndicator: some View {
        if isTemporaryIdNote {
            // 临时 ID 笔记显示"离线创建"标记
            HStack(spacing: 2) {
                Image(systemName: "doc.badge.clock")
                    .font(.system(size: 10))
                Text("离线")
                    .font(.system(size: 9))
            }
            .foregroundColor(.purple)
            .help("离线创建的笔记，等待上传")
        } else if hasPendingUpload {
            // 有待处理上传显示"未同步"图标
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .help("笔记未同步，等待上传")
        }
    }

    /// 是否应该显示文件夹信息
    ///
    /// 显示场景：
    /// 1. 选中"所有笔记"文件夹（id = "0"）
    /// 2. 选中"置顶"文件夹（id = "starred"）
    /// 3. 有搜索文本或任意搜索筛选条件（搜索结果视图）
    ///
    /// 不显示场景：
    /// - 选中"未分类"文件夹（id = "uncategorized"）
    private var shouldShowFolderInfo: Bool {
        // 如果选中"未分类"文件夹，不显示文件夹信息
        if let folderId = viewModel.selectedFolder?.id, folderId == "uncategorized" {
            return false
        }
        
        // 有搜索文本
        if !viewModel.searchText.isEmpty {
            return true
        }
        
        // 有任意搜索筛选条件
        if viewModel.searchFilterHasTags ||
           viewModel.searchFilterHasChecklist ||
           viewModel.searchFilterHasImages ||
           viewModel.searchFilterHasAudio ||
           viewModel.searchFilterIsPrivate {
            return true
        }
        
        // 根据当前选中文件夹判断
        guard let folderId = viewModel.selectedFolder?.id else { return false }
        return folderId == "0" || folderId == "starred"
    }

    /// 获取文件夹名称
    private func getFolderName(for folderId: String) -> String {
        
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
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    // 标题（支持搜索高亮）- 加粗显示
                    highlightText(hasRealTitle() ? note.title : "无标题", searchText: viewModel.searchText)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(hasRealTitle() ? .primary : .secondary)
                    
                    HStack(spacing: 4) {
                        // 时间 - 加粗，与标题同色，根据排序方式显示创建时间或修改时间
                        // _Requirements: 1.1, 1.2, 1.3, 1.4_
                        Text(formatDate(displayDate))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        // 预览文本（支持搜索高亮）
                        highlightText(extractPreviewText(from: note.content), searchText: viewModel.searchText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // 文件夹信息（在特定条件下显示）- 调整大小与时间、正文预览一致，行距与其他行保持一致
                    if shouldShowFolderInfo {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(getFolderName(for: note.folderId))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
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
                    .onAppear {
                        // 首次加载或图片ID变化时，重新加载
                        if currentImageFileId != imageInfo.fileId {
                            loadThumbnail(imageInfo: imageInfo)
                            currentImageFileId = imageInfo.fileId
                        }
                    }
                    .onChange(of: imageInfo.fileId) { oldValue, newValue in
                        // 图片ID变化时，重新加载
                        if currentImageFileId != newValue {
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
                
                // 同步状态标记
                // _需求: 6.2_
                syncStatusIndicator
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            
            // 分割线：放在卡片内容之后，在卡片下方
            if showDivider {
                GeometryReader { geometry in
                    let leadingPadding: CGFloat = 8  // 左侧padding，与文字左对齐
                    let trailingPadding: CGFloat = 8  // 右侧padding，可以调整这个值来控制右侧空白
                    let lineWidth = geometry.size.width - leadingPadding - trailingPadding
                    
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 0.5)
                        .frame(width: lineWidth, alignment: .leading)
                        .padding(.leading, leadingPadding)
                        // #region agent log
                        .onAppear {
                            let logPath = "/Users/acckion/Desktop/SwiftUI-MiNote-for-Mac/.cursor/debug.log"
                            let logEntry = "{\"location\":\"NotesListView.swift:divider\",\"message\":\"分割线GeometryReader渲染\",\"data\":{\"noteId\":\"\(note.id.prefix(8))\",\"showDivider\":\(showDivider),\"method\":\"geometry_calculated_width\",\"totalWidth\":\(geometry.size.width),\"lineWidth\":\(lineWidth),\"leadingPadding\":\(leadingPadding),\"trailingPadding\":\(trailingPadding),\"hypothesisId\":\"H\"},\"timestamp\":\(Int(Date().timeIntervalSince1970 * 1000)),\"sessionId\":\"debug-session\",\"runId\":\"post-fix\"}\n"
                            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                                defer { try? fileHandle.close() }
                                try? fileHandle.seekToEnd()
                                try? fileHandle.write(contentsOf: logEntry.data(using: .utf8)!)
                            } else {
                                try? logEntry.write(toFile: logPath, atomically: true, encoding: .utf8)
                            }
                        }
                        // #endregion
                }
                .frame(height: 0.5)  // GeometryReader 需要明确的高度
            }
        }
        .onHover { hovering in
            if hovering {
                // 延迟100ms后预加载笔记
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    // 如果笔记内容为空，预加载完整内容
                    if note.content.isEmpty {
                        if let fullNote = try? LocalStorageService.shared.loadNote(noteId: note.id) {
                            await MemoryCacheManager.shared.cacheNote(fullNote)
                            Swift.print("[预加载] 悬停预加载完成 - ID: \(note.id.prefix(8))...")
                        }
                    } else {
                        await MemoryCacheManager.shared.cacheNote(note)
                    }
                }
            }
        }
        .onChange(of: note.content) { oldValue, newValue in
            // 笔记内容变化时，重新检查并更新图片
            updateThumbnail()
        }
        .onChange(of: note.updatedAt) { oldValue, newValue in
            // 更新时间变化时，重新检查并更新图片
            updateThumbnail()
        }
        .onChange(of: note.title) { oldValue, newValue in
            // 笔记标题变化时，强制视图刷新
            print("[NoteRow] onChange(title): 笔记标题变化: \(oldValue) -> \(newValue)")
        }
        .onChange(of: noteImageHash) { oldValue, newValue in
            // 图片信息哈希值变化时，强制更新缩略图
            // 这确保当图片插入/删除时能正确刷新
            print("[NoteRow] onChange(noteImageHash): 图片信息哈希值变化 (\(oldValue) -> \(newValue))，更新缩略图")
            updateThumbnail()
        }
        // 使用笔记 ID 作为视图标识符（而非 displayProperties）
        // 这样编辑笔记内容时不会改变视图标识，选择状态能够保持
        // displayProperties 的变化通过 onChange 监听器处理，不影响视图标识
        // _Requirements: 1.1, 1.2, 5.2_
        // - 1.1: 编辑笔记内容时保持选中状态不变
        // - 1.2: 笔记内容保存触发 notes 数组更新时不重置 selectedNote
        .id(note.id)
        // #region agent log
        .onAppear {
            let logPath = "/Users/acckion/Desktop/SwiftUI-MiNote-for-Mac/.cursor/debug.log"
            let logEntry = "{\"location\":\"NotesListView.swift:body\",\"message\":\"NoteRow渲染\",\"data\":{\"noteId\":\"\(note.id.prefix(8))\",\"showDivider\":\(showDivider),\"verticalPadding\":6,\"layoutMethod\":\"overlay\",\"hypothesisId\":\"B\"},\"timestamp\":\(Int(Date().timeIntervalSince1970 * 1000)),\"sessionId\":\"debug-session\",\"runId\":\"initial\"}\n"
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                defer { try? fileHandle.close() }
                try? fileHandle.seekToEnd()
                try? fileHandle.write(contentsOf: logEntry.data(using: .utf8)!)
            } else {
                try? logEntry.write(toFile: logPath, atomically: true, encoding: .utf8)
            }
        }
        // #endregion
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
    
    /// 高亮显示文本中的搜索关键词
    /// - Parameters:
    ///   - text: 要显示的文本
    ///   - searchText: 搜索关键词
    /// - Returns: 高亮后的 Text 视图
    @ViewBuilder
    private func highlightText(_ text: String, searchText: String) -> some View {
        // 如果搜索文本为空，直接返回普通文本（确保退出搜索时清除高亮）
        if searchText.isEmpty || text.isEmpty {
            Text(text)
        } else {
            // 只有当有搜索文本时才应用高亮
            let attributedString = buildHighlightedAttributedString(text: text, searchText: searchText)
            Text(attributedString)
        }
    }
    
    /// 构建高亮的 AttributedString
    private func buildHighlightedAttributedString(text: String, searchText: String) -> AttributedString {
        // 使用 NSMutableAttributedString 更可靠
        let nsAttributedString = NSMutableAttributedString(string: text)
        let searchTextLower = searchText.lowercased()
        let textLower = text.lowercased()
        
        // 使用 NSString 来确保正确的 NSRange 计算（支持多字节字符）
        let nsText = textLower as NSString
        let nsSearchText = searchTextLower as NSString
        
        var searchLocation = 0
        
        // 查找所有匹配并应用高亮
        while searchLocation < nsText.length {
            let searchRange = NSRange(location: searchLocation, length: nsText.length - searchLocation)
            let foundRange = nsText.range(of: nsSearchText as String, options: [], range: searchRange)
            
            if foundRange.location != NSNotFound {
                // 计算在原始字符串中的对应范围（使用原始文本的 NSString）
                let originalNSText = text as NSString
                let originalRange = NSRange(location: foundRange.location, length: foundRange.length)
                
                // 确保范围有效
                if originalRange.location + originalRange.length <= originalNSText.length {
                    // 应用高亮样式
                    nsAttributedString.addAttribute(.backgroundColor, value: NSColor.yellow.withAlphaComponent(0.4), range: originalRange)
                }
                
                // 继续搜索下一个匹配
                searchLocation = foundRange.location + foundRange.length
            } else {
                break
            }
        }
        
        // 转换为 AttributedString
        return AttributedString(nsAttributedString)
    }
    
    /// 将文本分割为高亮和非高亮部分
    private func splitTextWithHighlight(text: String, searchText: String) -> [(text: String, isHighlighted: Bool)] {
        guard !searchText.isEmpty && !text.isEmpty else {
            return [(text: text, isHighlighted: false)]
        }
        
        var parts: [(text: String, isHighlighted: Bool)] = []
        let searchTextLower = searchText.lowercased()
        let textLower = text.lowercased()
        
        var currentIndex = text.startIndex
        
        while let range = textLower.range(of: searchTextLower, range: currentIndex..<text.endIndex) {
            // 添加高亮前的文本
            if currentIndex < range.lowerBound {
                let beforeText = String(text[currentIndex..<range.lowerBound])
                parts.append((text: beforeText, isHighlighted: false))
            }
            
            // 添加高亮的文本（使用原始文本以保持大小写）
            let highlightedText = String(text[range])
            parts.append((text: highlightedText, isHighlighted: true))
            
            currentIndex = range.upperBound
        }
        
        // 添加剩余的文本
        if currentIndex < text.endIndex {
            let remainingText = String(text[currentIndex..<text.endIndex])
            parts.append((text: remainingText, isHighlighted: false))
        }
        
        return parts.isEmpty ? [(text: text, isHighlighted: false)] : parts
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
    
    /// 当前笔记的图片哈希值（计算属性）
    private var noteImageHash: String {
        getImageInfoHash(from: note)
    }
    
    /// 更新缩略图（根据当前笔记内容）
    private func updateThumbnail() {
        if let imageInfo = getFirstImageInfo(from: note) {
            // 如果图片ID变化了，重新加载
            if currentImageFileId != imageInfo.fileId {
                loadThumbnail(imageInfo: imageInfo)
                currentImageFileId = imageInfo.fileId
            }
        } else {
            // 如果没有图片了，清空缩略图
            if currentImageFileId != nil || thumbnailImage != nil {
                currentImageFileId = nil
                thumbnailImage = nil
            }
        }
    }
    
    /// 加载缩略图
    private func loadThumbnail(imageInfo: (fileId: String, fileType: String)) {
        // 在后台线程加载图片
        Task {
            if let imageData = LocalStorageService.shared.loadImage(fileId: imageInfo.fileId, fileType: imageInfo.fileType),
               let nsImage = NSImage(data: imageData) {
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
                    self.thumbnailImage = thumbnail
                }
            } else {
                // 如果加载失败，清空缩略图
                await MainActor.run {
                    self.thumbnailImage = nil
                }
            }
        }
    }
}

#Preview {
    NotesListView(viewModel: NotesViewModel())
}
