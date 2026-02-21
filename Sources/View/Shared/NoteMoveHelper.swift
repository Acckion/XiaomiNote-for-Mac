import Foundation

/// 笔记移动助手
/// 统一处理笔记移动逻辑，避免代码重复
public class NoteMoveHelper {

    // MARK: - 新 API（使用 State 对象）

    /// 移动笔记到指定文件夹
    /// - Parameters:
    ///   - note: 要移动的笔记
    ///   - folder: 目标文件夹
    ///   - noteListState: 笔记列表状态
    ///   - completion: 完成回调，返回成功或失败
    @MainActor
    static func moveNote(
        _ note: Note,
        to folder: Folder,
        using noteListState: NoteListState,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard note.folderId != folder.id else {
            completion(.success(()))
            return
        }

        let noteId = note.id
        let folderId = folder.id
        let folderName = folder.name
        let capturedCompletion = completion

        Task {
            await noteListState.moveNote(note, toFolder: folderId)
            LogService.shared.debug(.viewmodel, "笔记移动成功: \(noteId) -> \(folderName)")
            capturedCompletion(.success(()))
        }
    }

    /// 获取可用的文件夹列表（用于移动笔记菜单）
    /// - Parameter folderState: 文件夹状态
    /// - Returns: 文件夹数组，已过滤掉不需要的文件夹
    @MainActor
    static func getAvailableFolders(from folderState: FolderState) -> [Folder] {
        filterFolders(folderState.folders)
    }

    /// 处理移动到未分类文件夹的逻辑
    /// - Parameters:
    ///   - note: 要移动的笔记
    ///   - noteListState: 笔记列表状态
    ///   - completion: 完成回调
    @MainActor
    static func moveToUncategorized(_ note: Note, using noteListState: NoteListState, completion: @escaping (Result<Void, Error>) -> Void) {
        let uncategorizedFolder = uncategorizedFolder()
        moveNote(note, to: uncategorizedFolder, using: noteListState, completion: completion)
    }

    // MARK: - 共享方法

    /// 创建未分类文件夹对象
    public static func uncategorizedFolder() -> Folder {
        Folder(
            id: "0",
            name: "未分类",
            count: 0,
            isSystem: true,
            isPinned: false,
            createdAt: Date()
        )
    }

    /// 过滤文件夹列表，排除不需要的文件夹
    private static func filterFolders(_ folders: [Folder]) -> [Folder] {
        folders.filter { folder in
            if folder.isSystem, folder.id != "2" {
                return false
            }
            if folder.id == "0" {
                return false
            }
            let excludedIds = ["starred", "new"]
            if excludedIds.contains(folder.id) {
                return false
            }
            return true
        }.sorted { $0.name < $1.name }
    }
}
