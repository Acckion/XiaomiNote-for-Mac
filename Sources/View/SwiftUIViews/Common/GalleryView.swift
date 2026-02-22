//
//  GalleryView.swift
//  MiNoteMac
//
//  画廊视图 - 以卡片网格形式展示笔记
//

import AppKit
import SwiftUI

// MARK: - GalleryView

/// 画廊视图
///
/// 以卡片网格形式展示笔记，支持响应式布局、日期分组和键盘导航
struct GalleryView: View {

    // MARK: - 属性

    /// 应用协调器（共享数据层）
    let coordinator: AppCoordinator

    /// 窗口状态（窗口独立状态）
    @ObservedObject var windowState: WindowState

    /// 笔记列表状态
    @ObservedObject var noteListState: NoteListState

    /// 文件夹状态
    @ObservedObject var folderState: FolderState

    /// 视图选项管理器
    @ObservedObject var optionsManager: ViewOptionsManager

    /// 动画命名空间（外部传入，用于与 ExpandedNoteView 共享）
    var animation: Namespace.ID

    // MARK: - 状态

    /// 当前聚焦的笔记索引（用于键盘导航）
    @State private var focusedNoteIndex = 0

    /// 是否显示删除确认对话框
    @State private var showingDeleteAlert = false

    /// 待删除的笔记
    @State private var noteToDelete: Note?

    // MARK: - 常量

    /// 网格列配置：自适应布局，最小宽度200，最大宽度300
    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16),
    ]

    // MARK: - 视图

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if optionsManager.isDateGroupingEnabled {
                    // 分组显示模式
                    groupedGalleryContent
                } else {
                    // 平铺显示模式
                    flatGalleryContent
                }
            }
            .onChange(of: windowState.selectedNote?.id) { _, newValue in
                // 滚动到选中的笔记
                if let noteId = newValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(noteId, anchor: .center)
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        // 键盘导航支持
        .onKeyPress(.leftArrow) {
            navigateToPreviousNote()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateToNextNote()
            return .handled
        }
        .onKeyPress(.upArrow) {
            navigateUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            navigateDown()
            return .handled
        }
        .onKeyPress(.return) {
            openFocusedNote()
            return .handled
        }
        .alert("删除笔记", isPresented: $showingDeleteAlert, presenting: noteToDelete) { note in
            deleteAlertButtons(for: note)
        } message: { note in
            deleteAlertMessage(for: note)
        }
    }

    // MARK: - 平铺显示内容

    /// 平铺显示的画廊内容（不分组）
    private var flatGalleryContent: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(noteListState.filteredNotes) { note in
                noteCardItem(note: note)
            }
        }
        .padding(16)
    }

    // MARK: - 分组显示内容

    /// 分组显示的画廊内容
    private var groupedGalleryContent: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            let groupedNotes = groupNotesByDate(noteListState.filteredNotes)

            // 定义分组显示顺序
            let sectionOrder = ["置顶", "今天", "昨天", "本周", "本月", "本年"]

            // 先显示固定顺序的分组
            ForEach(sectionOrder, id: \.self) { sectionKey in
                if let notes = groupedNotes[sectionKey], !notes.isEmpty {
                    sectionView(title: sectionKey, notes: notes)
                }
            }

            // 然后按年份分组其他笔记（降序排列）
            let yearGroups = groupedNotes.filter { !sectionOrder.contains($0.key) }
            ForEach(yearGroups.keys.sorted(by: >), id: \.self) { year in
                if let notes = yearGroups[year], !notes.isEmpty {
                    sectionView(title: year, notes: notes)
                }
            }
        }
        .padding(16)
    }

    // MARK: - 分组视图

    /// 单个分组的视图
    /// - Parameters:
    ///   - title: 分组标题
    ///   - notes: 分组内的笔记列表
    private func sectionView(title: String, notes: [Note]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分组标题
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            // 笔记卡片网格
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(notes) { note in
                    noteCardItem(note: note)
                }
            }
        }
    }

    // MARK: - 笔记卡片项

    /// 单个笔记卡片项
    /// - Parameter note: 笔记数据
    private func noteCardItem(note: Note) -> some View {
        NoteCardView(
            note: note,
            isSelected: windowState.selectedNote?.id == note.id,
            onTap: {
                withAnimation(.easeInOut(duration: 0.35)) {
                    windowState.expandNote(note)
                    windowState.selectNote(note)
                }
            }
        )
        .id(note.id)
        .matchedGeometryEffect(id: note.id, in: animation)
        .contextMenu {
            noteContextMenu(for: note)
        }
    }

    // MARK: - 日期分组逻辑

    /// 按日期分组笔记
    ///
    /// 与 NotesListView 中的实现保持一致
    private func groupNotesByDate(_ notes: [Note]) -> [String: [Note]] {
        var grouped: [String: [Note]] = [:]
        let calendar = Calendar.current
        let now = Date()

        // 根据排序方式决定使用哪个日期字段
        let useCreateDate = optionsManager.sortOrder == .createDate

        // 先分离置顶笔记
        let pinnedNotes = notes.filter(\.isStarred)
        let unpinnedNotes = notes.filter { !$0.isStarred }

        // 处理置顶笔记
        if !pinnedNotes.isEmpty {
            grouped["置顶"] = pinnedNotes.sorted {
                let date1 = useCreateDate ? $0.createdAt : $0.updatedAt
                let date2 = useCreateDate ? $1.createdAt : $1.updatedAt
                return date1 > date2
            }
        }

        // 处理非置顶笔记
        for note in unpinnedNotes {
            let date = useCreateDate ? note.createdAt : note.updatedAt
            let key: String

            if calendar.isDateInToday(date) {
                key = "今天"
            } else if calendar.isDateInYesterday(date) {
                key = "昨天"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                key = "本周"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
                key = "本月"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                key = "本年"
            } else {
                let year = calendar.component(.year, from: date)
                key = "\(year)年"
            }

            if grouped[key] == nil {
                grouped[key] = []
            }
            grouped[key]?.append(note)
        }

        // 对每个分组内的笔记排序
        for key in grouped.keys {
            grouped[key] = grouped[key]?.sorted {
                let date1 = useCreateDate ? $0.createdAt : $0.updatedAt
                let date2 = useCreateDate ? $1.createdAt : $1.updatedAt
                return date1 > date2
            }
        }

        return grouped
    }

    // MARK: - 键盘导航

    /// 导航到上一个笔记
    private func navigateToPreviousNote() {
        let notes = noteListState.filteredNotes
        guard !notes.isEmpty else { return }

        if let currentNote = windowState.selectedNote,
           let currentIndex = notes.firstIndex(where: { $0.id == currentNote.id })
        {
            let newIndex = max(0, currentIndex - 1)
            windowState.selectNote(notes[newIndex])
        } else {
            if let firstNote = notes.first {
                windowState.selectNote(firstNote)
            }
        }
    }

    /// 导航到下一个笔记
    private func navigateToNextNote() {
        let notes = noteListState.filteredNotes
        guard !notes.isEmpty else { return }

        if let currentNote = windowState.selectedNote,
           let currentIndex = notes.firstIndex(where: { $0.id == currentNote.id })
        {
            let newIndex = min(notes.count - 1, currentIndex + 1)
            windowState.selectNote(notes[newIndex])
        } else {
            if let firstNote = notes.first {
                windowState.selectNote(firstNote)
            }
        }
    }

    /// 向上导航（跳过一行）
    private func navigateUp() {
        let notes = noteListState.filteredNotes
        guard !notes.isEmpty else { return }

        let columnsPerRow = 4

        if let currentNote = windowState.selectedNote,
           let currentIndex = notes.firstIndex(where: { $0.id == currentNote.id })
        {
            let newIndex = max(0, currentIndex - columnsPerRow)
            windowState.selectNote(notes[newIndex])
        } else {
            if let firstNote = notes.first {
                windowState.selectNote(firstNote)
            }
        }
    }

    /// 向下导航（跳过一行）
    private func navigateDown() {
        let notes = noteListState.filteredNotes
        guard !notes.isEmpty else { return }

        let columnsPerRow = 4

        if let currentNote = windowState.selectedNote,
           let currentIndex = notes.firstIndex(where: { $0.id == currentNote.id })
        {
            let newIndex = min(notes.count - 1, currentIndex + columnsPerRow)
            windowState.selectNote(notes[newIndex])
        } else {
            if let firstNote = notes.first {
                windowState.selectNote(firstNote)
            }
        }
    }

    /// 打开当前聚焦的笔记
    private func openFocusedNote() {
        if let note = windowState.selectedNote {
            withAnimation(.easeInOut(duration: 0.35)) {
                windowState.expandNote(note)
            }
        }
    }

    // MARK: - 右键菜单

    /// 笔记右键菜单
    ///
    /// 与 NotesListView 中的实现保持一致
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
            Task { await noteListState.toggleStar(note) }
        } label: {
            Label(
                note.isStarred ? "取消置顶笔记" : "置顶笔记",
                systemImage: note.isStarred ? "pin.slash" : "pin"
            )
        }

        // 移动笔记
        Menu("移到") {
            // 未分类文件夹
            Button {
                NoteMoveHelper.moveToUncategorized(note, using: noteListState) { result in
                    if case let .failure(error) = result {
                        LogService.shared.error(.window, "移动到未分类失败: \(error.localizedDescription)")
                    }
                }
            } label: {
                Label("未分类", systemImage: "folder.badge.questionmark")
            }

            // 其他可用文件夹
            let availableFolders = NoteMoveHelper.getAvailableFolders(from: folderState)

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
            Task { await noteListState.createNewNote(inFolder: folderState.selectedFolder?.id ?? "0") }
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

    /// 在新窗口打开笔记
    private func openNoteInNewWindow(_ note: Note) {
        if let controller = WindowManager.shared.createNewWindow(withNote: note) {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// 复制笔记内容到剪贴板
    private func copyNote(_ note: Note) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
        pasteboard.setString(content, forType: .string)
    }

    /// 共享笔记
    private func shareNote(_ note: Note) {
        let sharingService = NSSharingServicePicker(items: [
            note.title,
            note.content,
        ])

        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView
        {
            sharingService.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    /// 移动笔记到指定文件夹
    private func moveNoteToFolder(note: Note, folder: Folder) {
        NoteMoveHelper.moveNote(note, to: folder, using: noteListState) { result in
            if case let .failure(error) = result {
                LogService.shared.error(.window, "移动笔记失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 删除确认对话框

    private func deleteAlertButtons(for note: Note) -> some View {
        Group {
            Button("取消", role: .cancel) {
                noteToDelete = nil
            }
            Button("删除", role: .destructive) {
                Task { await noteListState.deleteNote(note) }
                noteToDelete = nil
            }
        }
    }

    private func deleteAlertMessage(for note: Note) -> Text {
        Text("确定要删除 \"\(note.title)\" 吗？此操作无法撤销。")
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var animation

        var body: some View {
            let coordinator = AppCoordinator()
            let windowState = WindowState(coordinator: coordinator)

            GalleryView(
                coordinator: coordinator,
                windowState: windowState,
                noteListState: coordinator.noteListState,
                folderState: coordinator.folderState,
                optionsManager: .shared,
                animation: animation
            )
            .frame(width: 800, height: 600)
        }
    }

    return PreviewWrapper()
}
