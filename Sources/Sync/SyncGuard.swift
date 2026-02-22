import Foundation

// MARK: - 同步保护器

/// 同步保护器
///
/// 在同步时过滤掉不应被更新的笔记，防止同步覆盖本地修改。
/// 替代旧的 SyncProtectionFilter，使用 UnifiedOperationQueue 作为数据源。
///
/// **检查顺序**：
/// 1. 检查是否为临时 ID（离线创建的笔记）
/// 2. 检查是否正在编辑（活跃编辑保护）
/// 3. 检查是否有待处理上传（待上传保护）
/// 4. 比较时间戳（本地较新时跳过）
public struct SyncGuard: Sendable {

    // MARK: - 依赖

    /// 统一操作队列
    private let operationQueue: UnifiedOperationQueue

    /// 笔记数据仓库（提供活跃编辑状态查询）
    private let noteStore: NoteStore

    // MARK: - 初始化

    /// 创建同步保护器
    ///
    /// - Parameters:
    ///   - operationQueue: 统一操作队列
    ///   - noteStore: 笔记数据仓库
    public init(
        operationQueue: UnifiedOperationQueue = .shared,
        noteStore: NoteStore
    ) {
        self.operationQueue = operationQueue
        self.noteStore = noteStore
    }
}

// MARK: - 同步保护检查

public extension SyncGuard {

    /// 检查笔记是否应该被同步跳过
    func shouldSkipSync(noteId: String, cloudTimestamp: Date) async -> Bool {
        // 1. 检查是否为临时 ID（离线创建的笔记）
        if NoteOperation.isTemporaryId(noteId) {
            LogService.shared.debug(.sync, "跳过同步: 临时 ID 笔记 \(noteId.prefix(8))...")
            return true
        }

        // 2. 检查是否正在编辑
        let isEditing = await noteStore.isNoteActivelyEditing(noteId)
        if isEditing {
            LogService.shared.debug(.sync, "跳过同步: 笔记正在编辑 \(noteId.prefix(8))...")
            return true
        }

        // 3. 检查是否有待处理上传
        if operationQueue.hasPendingUpload(for: noteId) {
            if let localTimestamp = operationQueue.getLocalSaveTimestamp(for: noteId) {
                if localTimestamp >= cloudTimestamp {
                    LogService.shared.debug(.sync, "跳过同步: 本地较新 \(noteId.prefix(8))...")
                    return true
                }
            }
            // 即使云端较新，但笔记在待上传列表中，也应该跳过（用户优先策略）
            LogService.shared.debug(.sync, "跳过同步: 待上传中 \(noteId.prefix(8))...")
            return true
        }

        // 4. 检查是否有待处理的 noteCreate 操作
        if operationQueue.hasPendingNoteCreate(for: noteId) {
            LogService.shared.debug(.sync, "跳过同步: 待创建中 \(noteId.prefix(8))...")
            return true
        }

        // 5. 检查是否有待处理的文件上传操作（避免覆盖包含临时 fileId 的内容）
        if operationQueue.hasPendingFileUpload(for: noteId) {
            LogService.shared.debug(.sync, "跳过同步: 文件上传中 \(noteId.prefix(8))...")
            return true
        }

        // 6. 无保护条件，允许同步
        return false
    }

    /// 检查笔记是否正在编辑
    func isActivelyEditing(noteId: String) async -> Bool {
        await noteStore.isNoteActivelyEditing(noteId)
    }

    /// 检查笔记是否有待处理上传
    func hasPendingUpload(noteId: String) -> Bool {
        operationQueue.hasPendingUpload(for: noteId)
    }

    /// 获取笔记的本地保存时间戳
    func getLocalSaveTimestamp(noteId: String) -> Date? {
        operationQueue.getLocalSaveTimestamp(for: noteId)
    }

    /// 检查笔记是否为临时 ID
    func isTemporaryId(_ noteId: String) -> Bool {
        NoteOperation.isTemporaryId(noteId)
    }
}

// MARK: - 跳过原因

public extension SyncGuard {

    /// 获取跳过同步的原因
    func getSkipReason(noteId: String, cloudTimestamp: Date) async -> SyncSkipReason? {
        if NoteOperation.isTemporaryId(noteId) {
            return .temporaryId
        }

        if await noteStore.isNoteActivelyEditing(noteId) {
            return .activelyEditing
        }

        if operationQueue.hasPendingUpload(for: noteId) {
            if let localTimestamp = operationQueue.getLocalSaveTimestamp(for: noteId) {
                if localTimestamp >= cloudTimestamp {
                    return .localNewer(localTimestamp: localTimestamp, cloudTimestamp: cloudTimestamp)
                } else {
                    return .pendingUpload
                }
            }
            return .pendingUpload
        }

        if operationQueue.hasPendingNoteCreate(for: noteId) {
            return .pendingCreate
        }

        if operationQueue.hasPendingFileUpload(for: noteId) {
            return .pendingFileUpload
        }

        return nil
    }
}

// MARK: - 同步跳过原因

/// 同步跳过原因
public enum SyncSkipReason: Sendable, Equatable {
    /// 笔记使用临时 ID（离线创建）
    case temporaryId
    /// 笔记正在编辑
    case activelyEditing
    /// 笔记在待上传列表中
    case pendingUpload
    /// 笔记在待创建列表中
    case pendingCreate
    /// 笔记有待处理的文件上传
    case pendingFileUpload
    /// 本地版本较新
    case localNewer(localTimestamp: Date, cloudTimestamp: Date)

    /// 获取描述信息
    public var description: String {
        switch self {
        case .temporaryId:
            "笔记使用临时 ID（离线创建）"
        case .activelyEditing:
            "笔记正在编辑"
        case .pendingUpload:
            "笔记在待上传列表中"
        case .pendingCreate:
            "笔记在待创建列表中"
        case .pendingFileUpload:
            "笔记有待处理的文件上传"
        case let .localNewer(localTimestamp, cloudTimestamp):
            "本地版本较新 (本地: \(localTimestamp), 云端: \(cloudTimestamp))"
        }
    }
}
