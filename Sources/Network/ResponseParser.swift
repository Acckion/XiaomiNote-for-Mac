import Foundation

/// API 响应解析器
///
/// 负责解析小米笔记 API 返回的 JSON 响应，提取笔记、文件夹和同步标记。
/// 支持多种响应格式路径，兼容完整同步、增量同步和轻量级同步。
public enum ResponseParser {

    /// 从响应中提取 syncTag
    ///
    /// 支持三种响应格式路径：
    /// 1. response["syncTag"]
    /// 2. response["data"]["syncTag"]
    /// 3. response["data"]["note_view"]["data"]["syncTag"]
    ///
    /// - Parameter response: API 响应字典
    /// - Returns: syncTag 字符串，找不到则返回空字符串
    public static func extractSyncTag(from response: [String: Any]) -> String {
        if let syncTag = response["syncTag"] as? String {
            return syncTag
        }

        if let data = response["data"] as? [String: Any] {
            if let syncTag = data["syncTag"] as? String {
                return syncTag
            }

            if let noteView = data["note_view"] as? [String: Any],
               let noteViewData = noteView["data"] as? [String: Any],
               let syncTag = noteViewData["syncTag"] as? String
            {
                return syncTag
            }
        }

        return ""
    }

    /// 解析笔记列表
    ///
    /// 支持三种响应格式路径：
    /// 1. response["data"]["entries"]
    /// 2. response["data"]["note_view"]["data"]["entries"]
    /// 3. response["entries"]
    ///
    /// - Parameter response: API 响应字典
    /// - Returns: 笔记对象数组
    public static func parseNotes(from response: [String: Any]) -> [Note] {
        var entries: [[String: Any]] = []

        if let data = response["data"] as? [String: Any],
           let dataEntries = data["entries"] as? [[String: Any]]
        {
            entries = dataEntries
        } else if let data = response["data"] as? [String: Any],
                  let noteView = data["note_view"] as? [String: Any],
                  let noteViewData = noteView["data"] as? [String: Any],
                  let noteViewEntries = noteViewData["entries"] as? [[String: Any]]
        {
            entries = noteViewEntries
        } else if let responseEntries = response["entries"] as? [[String: Any]] {
            entries = responseEntries
        }

        var notes: [Note] = []
        for entry in entries {
            if let note = NoteMapper.fromMinoteListData(entry) {
                notes.append(note)
            }
        }

        return notes
    }

    /// 解析文件夹列表
    ///
    /// 支持三种响应格式路径：
    /// 1. response["data"]["folders"]
    /// 2. response["data"]["note_view"]["data"]["folders"]
    /// 3. response["folders"]
    ///
    /// 自动添加系统文件夹（"所有笔记" id="0"、"置顶" id="starred"）
    ///
    /// - Parameter response: API 响应字典
    /// - Returns: 文件夹对象数组
    public static func parseFolders(from response: [String: Any]) -> [Folder] {
        var folderEntries: [[String: Any]] = []

        if let data = response["data"] as? [String: Any],
           let dataFolders = data["folders"] as? [[String: Any]]
        {
            folderEntries = dataFolders
        } else if let data = response["data"] as? [String: Any],
                  let noteView = data["note_view"] as? [String: Any],
                  let noteViewData = noteView["data"] as? [String: Any],
                  let noteViewFolders = noteViewData["folders"] as? [[String: Any]]
        {
            folderEntries = noteViewFolders
        } else if let responseFolders = response["folders"] as? [[String: Any]] {
            folderEntries = responseFolders
        }

        var folders: [Folder] = []
        for folderEntry in folderEntries {
            if let type = folderEntry["type"] as? String, type == "folder" {
                if let folder = Folder.fromMinoteData(folderEntry) {
                    folders.append(folder)
                }
            }
        }

        // 添加系统文件夹
        let hasAllNotes = folders.contains { $0.id == "0" }
        let hasStarred = folders.contains { $0.id == "starred" }

        if !hasAllNotes {
            folders.insert(Folder(id: "0", name: "所有笔记", count: 0, isSystem: true), at: 0)
        }
        if !hasStarred {
            let starredIndex = hasAllNotes ? 1 : 0
            folders.insert(Folder(id: "starred", name: "置顶", count: 0, isSystem: true), at: starredIndex)
        }

        return folders
    }
}
