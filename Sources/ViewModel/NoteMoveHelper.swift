import Foundation

/// 笔记移动助手
/// 统一处理笔记移动逻辑，避免代码重复
public class NoteMoveHelper {

    /// 移动笔记到指定文件夹
    /// - Parameters:
    ///   - note: 要移动的笔记
    ///   - folder: 目标文件夹
    ///   - viewModel: 视图模型
    ///   - completion: 完成回调，返回成功或失败
    @MainActor
    public static func moveNote(
        _ note: Note,
        to folder: Folder,
        using viewModel: NotesViewModel,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard note.folderId != folder.id else {
            completion(.success(()))
            return
        }

        // 捕获参数为本地变量以避免并发问题
        let noteId = note.id
        let folderId = folder.id
        let folderName = folder.name
        let capturedCompletion = completion

        Task {
            do {
                // 创建更新后的笔记对象，保持原来的修改日期不变
                let updatedNote = Note(
                    id: note.id,
                    title: note.title,
                    content: note.content,
                    folderId: folderId,
                    isStarred: note.isStarred,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt, // 保持原来的修改日期不变
                    tags: note.tags,
                    rawData: note.rawData
                )

                // 使用视图模型的updateNote方法（它会处理在线/离线逻辑）
                try await viewModel.updateNote(updatedNote)

                print("[NoteMoveHelper] 笔记移动成功: \(noteId) -> \(folderName)")
                capturedCompletion(.success(()))
            } catch {
                print("[NoteMoveHelper] 移动笔记失败: \(error.localizedDescription)")
                capturedCompletion(.failure(error))
            }
        }
    }

    /// 获取可用的文件夹列表（用于移动笔记菜单）
    /// - Parameter viewModel: 视图模型
    /// - Returns: 文件夹数组，已过滤掉不需要的文件夹
    @MainActor
    public static func getAvailableFolders(for viewModel: NotesViewModel) -> [Folder] {
        // 在主线程访问viewModel.folders
        let folders = viewModel.folders

        // 过滤掉不需要的文件夹
        return folders.filter { folder in
            // 排除系统文件夹（除了私密笔记）
            if folder.isSystem, folder.id != "2" {
                return false
            }

            // 排除"所有笔记"文件夹（id = "0"）
            if folder.id == "0" {
                return false
            }

            // 排除其他不需要的文件夹
            let excludedIds = ["starred", "new"]
            if excludedIds.contains(folder.id) {
                return false
            }

            return true
        }.sorted { $0.name < $1.name }
    }

    /// 创建未分类文件夹对象
    /// - Returns: 表示未分类的文件夹对象
    public static func uncategorizedFolder() -> Folder {
        Folder(
            id: "0", // 未分类的folderId应该是"0"
            name: "未分类",
            count: 0,
            isSystem: true,
            isPinned: false,
            createdAt: Date()
        )
    }

    /// 处理移动到未分类文件夹的逻辑
    /// - Parameters:
    ///   - note: 要移动的笔记
    ///   - viewModel: 视图模型
    ///   - completion: 完成回调
    @MainActor
    public static func moveToUncategorized(_ note: Note, using viewModel: NotesViewModel, completion: @escaping (Result<Void, Error>) -> Void) {
        let uncategorizedFolder = uncategorizedFolder()
        moveNote(note, to: uncategorizedFolder, using: viewModel, completion: completion)
    }
}
