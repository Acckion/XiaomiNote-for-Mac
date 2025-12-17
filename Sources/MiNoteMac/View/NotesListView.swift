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
        .listStyle(.plain)
        .alert("删除笔记", isPresented: $showingDeleteAlert, presenting: noteToDelete) { note in
            deleteAlertButtons(for: note)
        } message: { note in
            deleteAlertMessage(for: note)
        }
        .overlay {
            if viewModel.isLoading {
                loadingOverlay
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
        ForEach(viewModel.filteredNotes) { note in
            NoteRow(note: note)
                .tag(note)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    swipeActions(for: note)
                }
        }
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
                Label(note.isStarred ? "取消收藏" : "收藏", 
                      systemImage: note.isStarred ? "star.slash" : "star")
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title.isEmpty ? "无标题" : note.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                if note.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }
            
            if !note.content.isEmpty {
                Text(note.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                Text(formatDate(note.updatedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if note.tags.count > 0 {
                    ForEach(note.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            return "昨天"
        } else {
            formatter.dateFormat = "MM/dd"
        }
        return formatter.string(from: date)
    }
}

#Preview {
    NotesListView(viewModel: NotesViewModel())
}
