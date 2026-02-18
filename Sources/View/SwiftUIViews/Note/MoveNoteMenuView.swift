import SwiftUI

/// 移动笔记菜单视图
/// 显示所有可用的文件夹，用户点击目标文件夹即可移动笔记
struct MoveNoteMenuView: View {
    let note: Note
    @ObservedObject var viewModel: NotesViewModel
    @State private var isMoving = false

    var body: some View {
        Menu {
            // 所有笔记文件夹
            if let allNotesFolder = viewModel.folders.first(where: { $0.id == "0" }) {
                folderMenuItem(folder: allNotesFolder)
            }

            // 未分类文件夹
            folderMenuItem(folder: viewModel.uncategorizedFolder)

            // 其他用户文件夹（排除系统文件夹）
            let userFolders = viewModel.folders.filter { folder in
                !folder.isSystem &&
                    folder.id != "0" &&
                    folder.id != "starred" &&
                    folder.id != "uncategorized" &&
                    folder.id != "new" &&
                    folder.id != "2" // 排除私密笔记文件夹（需要特殊处理）
            }.sorted { $0.name < $1.name }

            if !userFolders.isEmpty {
                Divider()

                ForEach(userFolders) { folder in
                    folderMenuItem(folder: folder)
                }
            }

            // 私密笔记文件夹（如果有）
            if let privateNotesFolder = viewModel.folders.first(where: { $0.id == "2" }) {
                Divider()
                folderMenuItem(folder: privateNotesFolder)
            }
        } label: {
            Label("移到", systemImage: "folder")
        }
        .disabled(isMoving || note.folderId == "2" && !viewModel.isPrivateNotesUnlocked)
    }

    /// 创建文件夹菜单项
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

    /// 获取文件夹图标
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

    /// 移动笔记到指定文件夹
    private func moveNoteToFolder(_ folder: Folder) {
        guard note.folderId != folder.id else { return }

        isMoving = true

        Task {
            do {
                // 创建更新后的笔记对象，保持原来的修改日期不变
                let updatedNote = Note(
                    id: note.id,
                    title: note.title,
                    content: note.content,
                    folderId: folder.id,
                    isStarred: note.isStarred,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt, // 保持原来的修改日期不变
                    tags: note.tags,
                    rawData: note.rawData
                )

                // 使用视图模型的updateNote方法（它会处理在线/离线逻辑）
                try await viewModel.updateNote(updatedNote)

                print("[MoveNoteMenuView] 笔记移动成功: \(note.id) -> \(folder.name)")
            } catch {
                print("[MoveNoteMenuView] 移动笔记失败: \(error.localizedDescription)")
                // 错误处理已经在viewModel中完成，这里不需要额外处理
            }

            isMoving = false
        }
    }
}

#Preview {
    let viewModel = PreviewHelper.shared.createPreviewViewModel()
    let sampleNote = Note(
        id: "sample-1",
        title: "测试笔记",
        content: "测试内容",
        folderId: "0",
        isStarred: false,
        createdAt: Date(),
        updatedAt: Date()
    )

    return MoveNoteMenuView(note: sampleNote, viewModel: viewModel)
}
