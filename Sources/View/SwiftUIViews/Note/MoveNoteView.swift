import SwiftUI

/// 移动笔记视图（Sheet）
struct MoveNoteSheetView: View {
    let note: Note
    @ObservedObject var folderState: FolderState
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
                if let allNotesFolder = folderState.folders.first(where: { $0.id == "0" }) {
                    HStack {
                        Image(systemName: "tray.full")
                            .foregroundColor(.white)
                            .frame(width: 20)
                        Text(allNotesFolder.name)
                        Spacer()
                    }
                    .tag(allNotesFolder.id)
                }

                HStack {
                    Image(systemName: "folder.badge.questionmark")
                        .foregroundColor(.white)
                        .frame(width: 20)
                    Text(folderState.uncategorizedFolder.name)
                    Spacer()
                }
                .tag(folderState.uncategorizedFolder.id)

                ForEach(folderState.folders.filter { folder in
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
            await EventBus.shared.publish(
                NoteEvent.moved(noteId: note.id, fromFolder: note.folderId, toFolder: selectedFolderId)
            )
            dismiss()
        }
    }
}
