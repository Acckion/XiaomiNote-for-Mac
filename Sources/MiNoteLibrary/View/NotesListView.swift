import SwiftUI

struct NotesListView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var showingDeleteAlert = false
    @State private var noteToDelete: Note?
    
    var body: some View {
        List(selection: $viewModel.selectedNote) {
            if viewModel.filteredNotes.isEmpty {
                emptyNotesView
            } else {
                notesListContent
            }
        }
        .listStyle(.sidebar)
        .alert("删除笔记", isPresented: $showingDeleteAlert, presenting: noteToDelete) { note in
            deleteAlertButtons(for: note)
        } message: { note in
            deleteAlertMessage(for: note)
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
                    Section(sectionKey) {
                        ForEach(notes) { note in
                            NoteRow(note: note)
                                .tag(note)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    swipeActions(for: note)
                                }
                        }
                    }
                }
            }
            
            // 然后按年份分组其他笔记（降序排列）
            let yearGroups = groupedNotes.filter { !sectionOrder.contains($0.key) }
            ForEach(yearGroups.keys.sorted(by: >), id: \.self) { year in
                if let notes = yearGroups[year], !notes.isEmpty {
                    Section(year) {
                        ForEach(notes) { note in
                            NoteRow(note: note)
                                .tag(note)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    swipeActions(for: note)
                                }
                        }
                    }
                }
            }
        }
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
}

struct NoteRow: View {
    let note: Note
    
    var body: some View {
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
                    
                    if !note.id.isEmpty {
                        Text(note.id)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 锁图标（如果有）
            if note.rawData?["isLocked"] as? Bool == true {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
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
}

#Preview {
    NotesListView(viewModel: NotesViewModel())
}
