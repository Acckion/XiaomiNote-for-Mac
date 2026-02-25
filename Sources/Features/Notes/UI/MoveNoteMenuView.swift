import SwiftUI

/// 移动笔记菜单视图
/// 显示所有可用的文件夹，用户点击目标文件夹即可移动笔记
struct MoveNoteMenuView: View {
    let note: Note
    @ObservedObject var folderState: FolderState
    @ObservedObject var authState: AuthState
    @State private var isMoving = false

    var body: some View {
        Menu {
            if let allNotesFolder = folderState.folders.first(where: { $0.id == "0" }) {
                folderMenuItem(folder: allNotesFolder)
            }

            folderMenuItem(folder: folderState.uncategorizedFolder)

            let userFolders = folderState.folders.filter { folder in
                !folder.isSystem &&
                    folder.id != "0" &&
                    folder.id != "starred" &&
                    folder.id != "uncategorized" &&
                    folder.id != "new" &&
                    folder.id != "2"
            }.sorted { $0.name < $1.name }

            if !userFolders.isEmpty {
                Divider()

                ForEach(userFolders) { folder in
                    folderMenuItem(folder: folder)
                }
            }

            if let privateNotesFolder = folderState.folders.first(where: { $0.id == "2" }) {
                Divider()
                folderMenuItem(folder: privateNotesFolder)
            }
        } label: {
            Label("移到", systemImage: "folder")
        }
        .disabled(isMoving || note.folderId == "2" && !authState.isPrivateNotesUnlocked)
    }

    private func folderMenuItem(folder: Folder) -> some View {
        Button {
            moveNoteToFolder(folder)
        } label: {
            HStack {
                folderIcon(for: folder)
                Text(folder.name)
                Spacer()
                if note.folderId == folder.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .disabled(note.folderId == folder.id || isMoving)
    }

    private func folderIcon(for folder: Folder) -> some View {
        let iconName: String
        let color: Color

        if folder.id == "0" {
            iconName = "tray.full"
            color = .blue
        } else if folder.id == "uncategorized" {
            iconName = "folder.badge.questionmark"
            color = .gray
        } else if folder.id == "2" {
            iconName = "lock.fill"
            color = .red
        } else if folder.isPinned {
            iconName = "pin.fill"
            color = .yellow
        } else {
            iconName = "folder"
            color = .blue
        }

        return Image(systemName: iconName)
            .foregroundColor(color)
            .frame(width: 20)
    }

    private func moveNoteToFolder(_ folder: Folder) {
        guard note.folderId != folder.id else { return }

        isMoving = true

        Task {
            await EventBus.shared.publish(
                NoteEvent.moved(noteId: note.id, fromFolder: note.folderId, toFolder: folder.id)
            )

            LogService.shared.info(.viewmodel, "笔记移动成功: \(note.id) -> \(folder.name)")
            isMoving = false
        }
    }
}
