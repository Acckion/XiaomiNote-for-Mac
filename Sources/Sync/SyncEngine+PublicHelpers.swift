import Foundation

// MARK: - SyncEngine 公共辅助方法

extension SyncEngine {

    /// 手动重新下载笔记的所有图片
    func redownloadNoteImages(noteId: String) async throws -> (success: Int, failed: Int) {
        LogService.shared.info(.sync, "手动重新下载笔记图片: \(noteId)")

        guard await apiClient.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }

        let noteDetails = try await noteAPI.fetchNoteDetails(noteId: noteId)

        guard let updatedSettingData = try await downloadNoteImages(
            from: noteDetails,
            noteId: noteId,
            forceRedownload: true
        ) else {
            return (0, 0)
        }

        var successCount = 0
        var failedCount = 0

        for data in updatedSettingData {
            if let downloaded = data["downloaded"] as? Bool, downloaded {
                successCount += 1
            } else if let mimeType = data["mimeType"] as? String, mimeType.hasPrefix("image/") {
                failedCount += 1
            }
        }

        LogService.shared.info(.sync, "图片重新下载完成: 成功 \(successCount), 失败 \(failedCount)")
        return (successCount, failedCount)
    }

    /// 手动同步单个笔记
    func syncSingleNote(noteId: String) async throws -> NoteSyncResult {
        guard await apiClient.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }

        let noteDetails: [String: Any]
        do {
            noteDetails = try await noteAPI.fetchNoteDetails(noteId: noteId)
        } catch let error as MiNoteError {
            throw mapMiNoteError(error)
        }

        guard let note = NoteMapper.fromMinoteListData(noteDetails) else {
            throw SyncError.invalidNoteData
        }

        return try await processNote(note)
    }

    /// 取消同步
    func cancelSync() {
        isSyncing = false
        LogService.shared.info(.sync, "同步已取消")
    }

    /// 重置同步状态
    func resetSyncStatus() throws {
        try localStorage.clearSyncStatus()
        LogService.shared.info(.sync, "同步状态已重置")
    }
}
