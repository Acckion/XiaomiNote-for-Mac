import SwiftUI

/// 移动笔记视图（Sheet）
struct MoveNoteSheetView: View {
    let note: Note
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFolderId = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("移动笔记")
                .font(.headline)
                .padding(.top)

            Text("选择目标文件夹")
                .font(.subheadline)
                .foregroundColor(.secondary)

            List(selection: $selectedFolderId) {
                // 所有笔记
                if let allNotesFolder = viewModel.folders.first(where: { $0.id == "0" }) {
                    HStack {
                        Image(systemName: "tray.full")
                            .foregroundColor(.white)
                            .frame(width: 20)
                        Text(allNotesFolder.name)
                        Spacer()
                    }
                    .tag(allNotesFolder.id)
                }

                // 未分类
                HStack {
                    Image(systemName: "folder.badge.questionmark")
                        .foregroundColor(.white)
                        .frame(width: 20)
                    Text(viewModel.uncategorizedFolder.name)
                    Spacer()
                }
                .tag(viewModel.uncategorizedFolder.id)

                // 其他文件夹
                ForEach(viewModel.folders.filter { folder in
                    !folder.isSystem &&
                        folder.id != "0" &&
                        folder.id != "starred" &&
                        folder.id != "uncategorized" &&
                        folder.id != "new"
                }.sorted { $0.name < $1.name }) { folder in
                    HStack {
                        Image(systemName: folder.isPinned ? "pin.fill" : "folder")
                            .foregroundColor(.white)
                            .frame(width: 20)
                        Text(folder.name)
                        Spacer()
                    }
                    .tag(folder.id)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 300, height: 300)

            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("移动") {
                    moveNote()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedFolderId.isEmpty || selectedFolderId == note.folderId)
            }
            .padding()
        }
        .frame(width: 350, height: 450)
        .onAppear {
            selectedFolderId = note.folderId.isEmpty ? "0" : note.folderId
        }
    }

    private func moveNote() {
        Task {
            do {
                let updatedNote = Note(
                    id: note.id,
                    title: note.title,
                    content: note.content,
                    folderId: selectedFolderId,
                    isStarred: note.isStarred,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt // 保持原来的修改日期不变
                )
                try await viewModel.updateNote(updatedNote)
                dismiss()
            } catch {
                print("[MoveNoteView] 移动笔记失败: \(error.localizedDescription)")
            }
        }
    }
}
