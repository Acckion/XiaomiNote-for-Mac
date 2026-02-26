import Foundation

// MARK: - SyncEngine 类型定义和错误映射

extension SyncEngine {
    // MARK: - 同步结果

    /// 同步结果
    struct SyncResult {
        var totalNotes = 0
        var syncedNotes = 0
        var failedNotes = 0
        var skippedNotes = 0
        var lastSyncTime: Date?
        var noteResults: [NoteSyncResult] = []

        mutating func addNoteResult(_ result: NoteSyncResult) {
            noteResults.append(result)

            if result.success {
                switch result.status {
                case .created, .updated:
                    syncedNotes += 1
                case .skipped:
                    skippedNotes += 1
                case .failed:
                    failedNotes += 1
                }
            } else {
                failedNotes += 1
            }
        }
    }

    // MARK: - 笔记同步结果

    /// 单个笔记的同步结果
    struct NoteSyncResult {
        let noteId: String
        let noteTitle: String
        var success = false
        var status: SyncStatusType = .failed
        var message = ""

        enum SyncStatusType {
            case created
            case updated
            case skipped
            case failed
        }
    }

    // MARK: - 同步错误

    /// 同步错误类型
    enum SyncError: LocalizedError {
        case alreadySyncing
        case notAuthenticated
        case invalidNoteData
        case cookieExpired
        case networkError(Error)
        case storageError(Error)

        var errorDescription: String? {
            switch self {
            case .alreadySyncing:
                "同步正在进行中"
            case .notAuthenticated:
                "未登录小米账号"
            case .invalidNoteData:
                "笔记数据格式无效"
            case .cookieExpired:
                "Cookie已过期，请重新登录或刷新Cookie"
            case let .networkError(error):
                "网络错误: \(error.localizedDescription)"
            case let .storageError(error):
                "存储错误: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 辅助方法

    /// 从响应中提取 syncTag
    func extractSyncTags(from response: [String: Any]) -> String? {
        var syncTag: String?

        // 旧 API 格式
        if let oldSyncTag = response["syncTag"] as? String {
            syncTag = oldSyncTag
        }

        // data.syncTag 格式
        if let data = response["data"] as? [String: Any] {
            if let dataSyncTag = data["syncTag"] as? String {
                syncTag = dataSyncTag
            }

            // 网页版 API 格式：note_view.data.syncTag
            if let noteView = data["note_view"] as? [String: Any],
               let noteViewData = noteView["data"] as? [String: Any],
               let webSyncTag = noteViewData["syncTag"] as? String
            {
                syncTag = webSyncTag
            }
        }

        // 顶层 note_view.data.syncTag
        if let noteView = response["note_view"] as? [String: Any],
           let noteViewData = noteView["data"] as? [String: Any],
           let webSyncTag = noteViewData["syncTag"] as? String
        {
            syncTag = webSyncTag
        }

        if syncTag == nil {
            LogService.shared.warning(.sync, "无法从响应中提取 syncTag")
        }

        return syncTag
    }

    /// 将 MiNoteError 转换为 SyncError
    func mapMiNoteError(_ error: MiNoteError) -> SyncError {
        switch error {
        case .cookieExpired:
            .cookieExpired
        case .notAuthenticated:
            .notAuthenticated
        case let .networkError(underlyingError):
            .networkError(underlyingError)
        case .invalidResponse:
            .networkError(error)
        }
    }
}
