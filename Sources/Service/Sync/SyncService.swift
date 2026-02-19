import AppKit
import Foundation

/// 同步服务
///
/// 负责管理本地笔记与云端笔记的同步，包括：
/// - 完整同步：清除所有本地数据，从云端拉取全部笔记
/// - 增量同步：只同步自上次同步以来的更改
/// - 冲突解决：处理本地和云端同时修改的情况
/// - 离线操作队列：管理网络断开时的操作
/// - 同步保护：防止覆盖正在编辑或待上传的笔记
final class SyncService: @unchecked Sendable {
    static let shared = SyncService()

    // MARK: - 依赖服务

    /// 小米笔记API服务
    private let miNoteService = MiNoteService.shared

    /// 本地存储服务
    private let localStorage = LocalStorageService.shared

    /// 同步状态管理器
    /// 负责统一管理 syncTag 的获取、更新和确认
    private let syncStateManager: SyncStateManager

    /// 同步保护器
    /// 用于检查笔记是否应该被同步跳过（正在编辑、待上传或临时 ID）
    /// 替代旧的 SyncProtectionFilter，使用 UnifiedOperationQueue 作为数据源
    private let syncGuard = SyncGuard()

    /// 统一操作队列
    let unifiedQueue = UnifiedOperationQueue.shared

    // MARK: - 初始化

    /// 初始化同步服务
    ///
    /// - Parameter syncStateManager: 同步状态管理器，默认创建新实例
    private init(syncStateManager: SyncStateManager = SyncStateManager.createDefault()) {
        self.syncStateManager = syncStateManager
        LogService.shared.info(.sync, "SyncService 初始化完成")
    }

    // MARK: - 同步状态

    /// 同步锁 - 使用 NSLock 确保线程安全
    /// 遵循需求 6.1: 同步正在进行中时阻止新的同步请求
    private let syncLock = NSLock()

    /// 是否正在同步（内部状态）
    private var _isSyncing = false

    /// 是否正在同步（线程安全访问）
    private var _isSyncingInternal: Bool {
        get {
            syncLock.lock()
            defer { syncLock.unlock() }
            return _isSyncing
        }
        set {
            syncLock.lock()
            defer { syncLock.unlock() }
            _isSyncing = newValue
        }
    }

    /// 同步进度（0.0 - 1.0）
    private var _syncProgressInternal: Double = 0

    /// 同步状态消息（用于UI显示）
    private var syncStatusMessage = ""

    /// 上次同步时间（从 SyncStatus 加载）
    private var _lastSyncTime: Date?

    /// 当前 syncTag（从 SyncStatus 加载）
    private var _currentSyncTag: String?

    var isSyncingNow: Bool {
        _isSyncingInternal
    }

    var currentProgress: Double {
        _syncProgressInternal
    }

    var currentStatusMessage: String {
        syncStatusMessage
    }

    /// 获取上次同步时间
    var lastSyncTime: Date? {
        _lastSyncTime ?? localStorage.loadSyncStatus()?.lastSyncTime
    }

    /// 获取当前 syncTag
    var currentSyncTag: String? {
        _currentSyncTag ?? localStorage.loadSyncStatus()?.syncTag
    }

    /// 检查是否存在有效的同步状态
    /// 遵循需求 6.3, 6.4: 根据 SyncStatus 决定使用增量同步还是完整同步
    var hasValidSyncStatus: Bool {
        guard let status = localStorage.loadSyncStatus() else {
            return false
        }
        // 有效的同步状态需要有 lastSyncTime 和非空的 syncTag
        guard let syncTag = status.syncTag else { return false }
        return status.lastSyncTime != nil && !syncTag.isEmpty
    }

    // MARK: - 同步锁管理

    /// 尝试获取同步锁
    /// 遵循需求 6.1: 同步正在进行中时阻止新的同步请求
    /// - Returns: 是否成功获取锁
    private func tryAcquireSyncLock() -> Bool {
        syncLock.lock()
        defer { syncLock.unlock() }

        if _isSyncing {
            LogService.shared.warning(.sync, "同步锁获取失败：同步正在进行中")
            return false
        }

        _isSyncing = true // 直接设置而不调用setter，避免死锁
        return true
    }

    /// 释放同步锁
    /// 遵循需求 6.2: 同步完成后更新状态
    private func releaseSyncLock() {
        syncLock.lock()
        defer { syncLock.unlock() }

        _isSyncingInternal = false
    }

    /// 执行智能同步
    /// 遵循需求 6.3, 6.4:
    /// - 如果存在有效的 SyncStatus，使用增量同步
    /// - 如果是首次登录或 SyncStatus 不存在，执行完整同步
    /// - Returns: 同步结果
    /// - Throws: SyncError
    func performSmartSync() async throws -> SyncResult {
        LogService.shared.info(.sync, "开始智能同步")

        if hasValidSyncStatus {
            LogService.shared.debug(.sync, "存在有效的同步状态，执行增量同步")
            return try await performIncrementalSync()
        } else {
            LogService.shared.debug(.sync, "不存在有效的同步状态，执行完整同步")
            return try await performFullSync()
        }
    }

    // MARK: - 完整同步

    /// 执行完整同步
    ///
    /// 完整同步会：
    /// 1. 清除所有本地笔记和文件夹
    /// 2. 从云端拉取所有笔记和文件夹
    /// 3. 下载笔记的完整内容和图片
    ///
    /// **注意**：完整同步会丢失所有本地未同步的更改，请谨慎使用
    ///
    /// - Parameter checkIsSyncing: 是否检查 isSyncing 标志（默认为 true，当被其他同步方法调用时应设为 false）
    /// - Returns: 同步结果，包含同步的笔记数量等信息
    /// - Throws: SyncError（同步错误、网络错误等）
    func performFullSync(checkIsSyncing: Bool = true) async throws -> SyncResult {
        LogService.shared.info(.sync, "开始执行完整同步")

        if checkIsSyncing {
            guard !_isSyncingInternal else {
                LogService.shared.warning(.sync, "完整同步被阻止：同步正在进行中")
                throw SyncError.alreadySyncing
            }
        }

        guard miNoteService.isAuthenticated() else {
            LogService.shared.error(.sync, "完整同步失败：未认证")
            throw SyncError.notAuthenticated
        }

        // 使用线程安全的方式设置同步状态
        syncLock.withLock {
            _isSyncing = true
            _syncProgressInternal = 0
            syncStatusMessage = "开始完整同步..."
        }

        defer {
            syncLock.withLock {
                _isSyncing = false
            }
            LogService.shared.debug(.sync, "完整同步结束")
        }

        var result = SyncResult()
        var syncTag = ""

        do {
            // 1. 清除所有本地数据（保护临时 ID 笔记）
            syncStatusMessage = "清除所有本地数据..."
            LogService.shared.debug(.sync, "清除所有本地笔记和文件夹")
            let localNotes = try localStorage.getAllLocalNotes()
            for note in localNotes {
                // 临时 ID 笔记尚未上传到云端，不应该被删除
                if NoteOperation.isTemporaryId(note.id) {
                    LogService.shared.debug(.sync, "保护临时 ID 笔记: \(note.id.prefix(8))")
                    continue
                }
                try localStorage.deleteNote(noteId: note.id)
            }
            let localFolders = try localStorage.loadFolders()
            for folder in localFolders {
                if !folder.isSystem, folder.id != "0", folder.id != "starred" {
                    try DatabaseService.shared.deleteFolder(folderId: folder.id)
                }
            }
            LogService.shared.debug(.sync, "已清除所有本地数据")

            // 2. 拉取所有云端文件夹和笔记
            var syncStatus = SyncStatus()
            var pageCount = 0
            var totalNotes = 0
            var syncedNotes = 0
            var failedNotes = 0
            var allCloudFolders: [Folder] = []
            var allCloudNotes: [Note] = []

            while true {
                pageCount += 1
                syncStatusMessage = "正在获取第 \(pageCount) 页..."

                // 获取一页数据
                let pageResponse: [String: Any]
                do {
                    pageResponse = try await miNoteService.fetchPage(syncTag: syncTag)
                } catch let error as MiNoteError {
                    switch error {
                    case .cookieExpired:
                        throw SyncError.cookieExpired
                    case .notAuthenticated:
                        throw SyncError.notAuthenticated
                    case let .networkError(underlyingError):
                        throw SyncError.networkError(underlyingError)
                    case .invalidResponse:
                        throw SyncError.networkError(error)
                    }
                } catch {
                    throw SyncError.networkError(error)
                }

                // 解析笔记和文件夹
                let notes = miNoteService.parseNotes(from: pageResponse)
                let folders = miNoteService.parseFolders(from: pageResponse)

                totalNotes += notes.count

                // 收集所有云端文件夹
                for folder in folders {
                    if !folder.isSystem, folder.id != "0", folder.id != "starred" {
                        allCloudFolders.append(folder)
                    }
                }

                // 收集所有云端笔记（稍后处理）
                allCloudNotes.append(contentsOf: notes)

                // 检查是否还有下一页
                if let nextSyncTag = pageResponse["syncTag"] as? String, !nextSyncTag.isEmpty {
                    syncTag = nextSyncTag
                    syncStatus.syncTag = nextSyncTag
                } else {
                    // 没有更多页面
                    break
                }
            }

            // 3. 先保存所有云端文件夹（在处理笔记之前）
            syncStatusMessage = "保存云端文件夹..."
            if !allCloudFolders.isEmpty {
                do {
                    try localStorage.saveFolders(allCloudFolders)
                    LogService.shared.debug(.sync, "已保存 \(allCloudFolders.count) 个云端文件夹")
                } catch {
                    LogService.shared.warning(.sync, "保存文件夹失败: \(error.localizedDescription)")
                    // 继续执行，不影响笔记同步
                }
            } else {
                LogService.shared.warning(.sync, "没有找到云端文件夹")
            }

            // 4. 处理所有笔记（添加错误处理，单个笔记失败不影响整体同步）
            for (index, note) in allCloudNotes.enumerated() {
                _syncProgressInternal = Double(index) / Double(max(totalNotes, 1))
                syncStatusMessage = "正在同步笔记: \(note.title)"

                do {
                    // 获取笔记详情
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    var updatedNote = note
                    updatedNote.updateContent(from: noteDetails)

                    // 下载图片，并获取更新后的 setting.data (完整同步强制重新下载)
                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id, forceRedownload: true) {
                        // 更新笔记的 rawData 中的 setting.data
                        var rawData = updatedNote.rawData ?? [:]
                        var setting = rawData["setting"] as? [String: Any] ?? [:]
                        setting["data"] = updatedSettingData
                        rawData["setting"] = setting
                        updatedNote.rawData = rawData

                        // 同步更新 settingJson 字段
                        if let settingData = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
                           let settingString = String(data: settingData, encoding: .utf8)
                        {
                            updatedNote.settingJson = settingString
                        }
                    }

                    // 保存到本地
                    try localStorage.saveNote(updatedNote)
                    syncedNotes += 1
                } catch {
                    LogService.shared.error(.sync, "保存笔记失败: \(note.id) - \(error.localizedDescription)")
                    failedNotes += 1
                    // 继续处理下一个笔记
                }
            }

            // 5. 获取并同步私密笔记
            syncStatusMessage = "获取私密笔记..."
            do {
                let privateNotesResponse = try await miNoteService.fetchPrivateNotes(folderId: "2", limit: 200)
                let privateNotes = miNoteService.parseNotes(from: privateNotesResponse)

                LogService.shared.debug(.sync, "获取到 \(privateNotes.count) 条私密笔记")
                totalNotes += privateNotes.count

                // 处理私密笔记
                for (index, note) in privateNotes.enumerated() {
                    _syncProgressInternal = Double(syncedNotes + index) / Double(max(totalNotes, 1))
                    syncStatusMessage = "正在同步私密笔记: \(note.title)"

                    // 获取笔记详情
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    var updatedNote = note
                    updatedNote.updateContent(from: noteDetails)

                    // 下载图片，并获取更新后的 setting.data (完整同步强制重新下载)
                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id, forceRedownload: true) {
                        var rawData = updatedNote.rawData ?? [:]
                        var setting = rawData["setting"] as? [String: Any] ?? [:]
                        setting["data"] = updatedSettingData
                        rawData["setting"] = setting
                        updatedNote.rawData = rawData

                        if let settingData = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
                           let settingString = String(data: settingData, encoding: .utf8)
                        {
                            updatedNote.settingJson = settingString
                        }
                    }

                    // 保存到本地（确保 folderId 为 "2"）
                    var finalNote = updatedNote
                    if finalNote.folderId != "2" {
                        finalNote = Note(
                            id: finalNote.id,
                            title: finalNote.title,
                            content: finalNote.content,
                            folderId: "2",
                            isStarred: finalNote.isStarred,
                            createdAt: finalNote.createdAt,
                            updatedAt: finalNote.updatedAt,
                            tags: finalNote.tags,
                            rawData: finalNote.rawData
                        )
                    }

                    try localStorage.saveNote(finalNote)
                    syncedNotes += 1
                }
            } catch {
                LogService.shared.warning(.sync, "获取私密笔记失败: \(error.localizedDescription)")
                // 不抛出错误，继续执行同步流程
            }

            // 6. 更新同步状态 - 使用 SyncStateManager
            // 保存syncTag（即使为空也要保存，但记录警告）
            // 注意：syncStatus.syncTag 已经在循环中被设置，这里不需要检查 syncTag 变量
            var finalSyncTag = syncStatus.syncTag

            if let currentSyncTag = syncStatus.syncTag, !currentSyncTag.isEmpty {
                LogService.shared.debug(.sync, "完整同步：找到 syncTag")
            } else {
                LogService.shared.warning(.sync, "完整同步：syncTag 为空，尝试从最后一次 API 响应中提取")
                // 尝试从最后一次API响应中提取syncTag
                do {
                    let lastPageResponse = try await miNoteService.fetchPage(syncTag: "")
                    if let lastSyncTag = lastPageResponse["syncTag"] as? String,
                       !lastSyncTag.isEmpty
                    {
                        finalSyncTag = lastSyncTag
                    } else {
                        if let extractedSyncTag = extractSyncTags(from: lastPageResponse) {
                            finalSyncTag = extractedSyncTag
                        } else {
                            LogService.shared.warning(.sync, "完整同步：无法从最后一次 API 响应中提取 syncTag")
                        }
                    }
                } catch {
                    LogService.shared.warning(.sync, "完整同步：获取最后一次 API 响应失败: \(error)")
                }
            }

            // 使用 SyncStateManager 暂存 syncTag（需求 2.1, 2.3）
            if let syncTag = finalSyncTag, !syncTag.isEmpty {
                let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
                try await syncStateManager.stageSyncTag(syncTag, hasPendingNotes: hasPendingNotes)
                LogService.shared.debug(.sync, "完整同步：syncTag 已通过 SyncStateManager 处理")
            } else {
                LogService.shared.warning(.sync, "完整同步：syncTag 为空，无法暂存")
            }

            // 移除直接更新 LocalStorageService 的代码（已由 SyncStateManager 处理）
            // 移除内部缓存更新（不再需要）

            _syncProgressInternal = 1.0
            syncStatusMessage = "完整同步完成"

            result.totalNotes = totalNotes
            result.syncedNotes = syncedNotes
            result.lastSyncTime = Date()

            LogService.shared.info(.sync, "完整同步完成 - 总计: \(totalNotes), 成功: \(syncedNotes), 失败: \(failedNotes), 文件夹: \(allCloudFolders.count)")
        } catch {
            syncStatusMessage = "同步失败: \(error.localizedDescription)"
            throw error
        }

        return result
    }

    // MARK: - 增量同步

    /// 执行增量同步
    ///
    /// 增量同步会：
    /// 1. 优先使用轻量级增量同步（只同步有修改的条目）
    /// 2. 如果轻量级同步失败，回退到网页版增量同步
    /// 3. 如果网页版增量同步失败，回退到旧API增量同步
    /// 4. 比较本地和云端的时间戳，决定使用哪个版本
    /// 5. 处理冲突：本地较新则上传，云端较新则下载
    /// 6. 处理离线操作队列中的操作
    ///
    /// **同步策略**：
    /// - 如果本地修改时间 > 云端修改时间：保留本地版本，上传到云端
    /// - 如果云端修改时间 > 本地修改时间：下载云端版本，覆盖本地
    /// - 如果时间相同但内容不同：下载云端版本（以云端为准）
    ///
    /// - Returns: 同步结果，包含同步的笔记数量等信息
    /// - Throws: SyncError（同步错误、网络错误等）
    func performIncrementalSync() async throws -> SyncResult {
        LogService.shared.info(.sync, "开始执行增量同步")
        guard !_isSyncingInternal else {
            LogService.shared.warning(.sync, "增量同步被阻止：同步正在进行中")
            throw SyncError.alreadySyncing
        }

        guard miNoteService.isAuthenticated() else {
            LogService.shared.error(.sync, "增量同步失败：未认证")
            throw SyncError.notAuthenticated
        }

        // 加载现有的同步状态
        guard let syncStatus = localStorage.loadSyncStatus() else {
            LogService.shared.info(.sync, "未找到同步记录，执行完整同步")
            return try await performFullSync()
        }

        _isSyncingInternal = true
        _syncProgressInternal = 0
        syncStatusMessage = "开始增量同步..."

        defer {
            _isSyncingInternal = false
            LogService.shared.debug(.sync, "增量同步结束")
        }

        var result = SyncResult()

        do {
            // 优先尝试轻量级增量同步
            do {
                result = try await performLightweightIncrementalSync()
                LogService.shared.debug(.sync, "轻量级增量同步成功")
                return result
            } catch {
                LogService.shared.warning(.sync, "轻量级增量同步失败，回退到网页版: \(error)")
            }

            // 如果轻量级同步失败，尝试网页版增量同步
            do {
                result = try await performWebIncrementalSync()
                LogService.shared.debug(.sync, "网页版增量同步成功")
                return result
            } catch {
                LogService.shared.warning(.sync, "网页版增量同步失败，回退到旧 API: \(error)")
            }

            // 使用 SyncStateManager 获取 syncTag（需求 1.1）
            let lastSyncTag = await syncStateManager.getCurrentSyncTag()

            syncStatusMessage = "获取自上次同步以来的更改..."

            let syncResponse = try await miNoteService.fetchPage(syncTag: lastSyncTag)
            LogService.shared.debug(.sync, "旧 API 调用成功")

            // 解析笔记和文件夹
            let notes = miNoteService.parseNotes(from: syncResponse)
            let folders = miNoteService.parseFolders(from: syncResponse)

            var syncedNotes = 0
            var cloudNoteIds = Set<String>()
            var cloudFolderIds = Set<String>()

            for note in notes {
                cloudNoteIds.insert(note.id)
            }
            for folder in folders {
                if !folder.isSystem, folder.id != "0", folder.id != "starred" {
                    cloudFolderIds.insert(folder.id)
                }
            }

            // 处理文件夹（按照增量同步规则）
            syncStatusMessage = "同步文件夹..."
            try await syncFoldersIncremental(cloudFolders: folders, cloudFolderIds: cloudFolderIds)

            // 处理笔记（按照增量同步规则）
            for (index, note) in notes.enumerated() {
                _syncProgressInternal = Double(index) / Double(max(notes.count, 1))
                syncStatusMessage = "正在同步笔记: \(note.title)"

                let noteResult = try await syncNoteIncremental(cloudNote: note)
                result.addNoteResult(noteResult)

                if noteResult.success {
                    syncedNotes += 1
                }
            }

            // 从响应中提取新的 syncTag
            if let newSyncTag = extractSyncTags(from: syncResponse) {
                let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
                try await syncStateManager.stageSyncTag(newSyncTag, hasPendingNotes: hasPendingNotes)
                LogService.shared.debug(.sync, "增量同步：syncTag 已通过 SyncStateManager 处理")
            }

            // 处理只有本地存在但云端不存在的笔记和文件夹
            syncStatusMessage = "检查本地独有的笔记和文件夹..."
            try await syncLocalOnlyItems(cloudNoteIds: cloudNoteIds, cloudFolderIds: cloudFolderIds)

            _syncProgressInternal = 1.0
            syncStatusMessage = "增量同步完成"

            result.totalNotes = notes.count
            result.syncedNotes = syncedNotes
            result.lastSyncTime = Date()

            LogService.shared.info(.sync, "增量同步完成 - 总计: \(notes.count), 成功: \(syncedNotes)")
        } catch {
            syncStatusMessage = "增量同步失败: \(error.localizedDescription)"
            throw error
        }

        return result
    }

    /// 执行网页版增量同步（使用新的API）
    ///
    /// 使用网页版的 `/note/sync/full/` API 进行增量同步
    /// 这个API比 `/note/full/page` 更高效，专门为增量同步设计
    ///
    /// **注意**：此方法由 `performIncrementalSync` 调用，不检查 `isSyncing` 标志
    ///
    /// - Returns: 同步结果，包含同步的笔记数量等信息
    /// - Throws: SyncError（同步错误、网络错误等）
    func performWebIncrementalSync() async throws -> SyncResult {
        guard miNoteService.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }

        guard let syncStatus = localStorage.loadSyncStatus() else {
            LogService.shared.info(.sync, "未找到同步记录，执行完整同步")
            return try await performFullSync(checkIsSyncing: false)
        }

        _syncProgressInternal = 0
        syncStatusMessage = "开始网页版增量同步..."

        var result = SyncResult()

        do {
            // 使用 SyncStateManager 获取 syncTag（需求 1.1）
            let lastSyncTag = await syncStateManager.getCurrentSyncTag()

            syncStatusMessage = "获取自上次同步以来的更改..."

            // 使用网页版增量同步API
            let syncResponse = try await miNoteService.syncFull(syncTag: lastSyncTag)

            // 解析笔记和文件夹
            let notes = miNoteService.parseNotes(from: syncResponse)
            let folders = miNoteService.parseFolders(from: syncResponse)

            var syncedNotes = 0
            var cloudNoteIds = Set<String>()
            var cloudFolderIds = Set<String>()

            for note in notes {
                cloudNoteIds.insert(note.id)
            }
            for folder in folders {
                if !folder.isSystem, folder.id != "0", folder.id != "starred" {
                    cloudFolderIds.insert(folder.id)
                }
            }

            // 处理文件夹（按照增量同步规则）
            syncStatusMessage = "同步文件夹..."
            try await syncFoldersIncremental(cloudFolders: folders, cloudFolderIds: cloudFolderIds)

            // 处理笔记（按照增量同步规则）
            for (index, note) in notes.enumerated() {
                _syncProgressInternal = Double(index) / Double(max(notes.count, 1))
                syncStatusMessage = "正在同步笔记: \(note.title)"

                let noteResult = try await syncNoteIncremental(cloudNote: note)
                result.addNoteResult(noteResult)

                if noteResult.success {
                    syncedNotes += 1
                }
            }

            // 从响应中提取新的 syncTag
            if let newSyncTag = extractSyncTags(from: syncResponse) {
                let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
                try await syncStateManager.stageSyncTag(newSyncTag, hasPendingNotes: hasPendingNotes)
                LogService.shared.debug(.sync, "网页版增量同步：syncTag 已通过 SyncStateManager 处理")
            }

            // 处理只有本地存在但云端不存在的笔记和文件夹
            syncStatusMessage = "检查本地独有的笔记和文件夹..."
            try await syncLocalOnlyItems(cloudNoteIds: cloudNoteIds, cloudFolderIds: cloudFolderIds)

            _syncProgressInternal = 1.0
            syncStatusMessage = "网页版增量同步完成"

            result.totalNotes = notes.count
            result.syncedNotes = syncedNotes
            result.lastSyncTime = Date()

            LogService.shared.info(.sync, "网页版增量同步完成 - 总计: \(notes.count), 成功: \(syncedNotes)")
        } catch {
            syncStatusMessage = "网页版增量同步失败: \(error.localizedDescription)"
            throw error
        }

        return result
    }

    // MARK: 轻量级增量同步（优化版）

    ///
    /// 使用网页版的 `/note/sync/full/` API 进行轻量级增量同步
    /// 这个API只返回有修改的条目，然后程序依次请求这些文件夹和笔记的详细内容
    ///
    /// 优势：
    /// 1. 更高效：只同步有修改的条目，减少网络流量
    /// 2. 实时性更好：基于syncTag的增量同步更准确
    /// 3. 支持删除同步：可以同步服务器端的删除操作
    ///
    /// **注意**：此方法由 `performIncrementalSync` 调用，不检查 `isSyncing` 标志
    ///
    /// - Returns: 同步结果，包含同步的笔记数量等信息
    /// - Throws: SyncError（同步错误、网络错误等）
    func performLightweightIncrementalSync() async throws -> SyncResult {
        guard miNoteService.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }

        guard let syncStatus = localStorage.loadSyncStatus() else {
            LogService.shared.info(.sync, "未找到同步记录，执行完整同步")
            return try await performFullSync(checkIsSyncing: false)
        }

        _syncProgressInternal = 0
        syncStatusMessage = "开始轻量级增量同步..."

        var result = SyncResult()

        do {
            let lastSyncTag = await syncStateManager.getCurrentSyncTag()

            syncStatusMessage = "获取自上次同步以来的更改..."

            let syncResponse = try await miNoteService.syncFull(syncTag: lastSyncTag)

            let (modifiedNotes, modifiedFolders, newSyncTag) = try parseLightweightSyncResponse(syncResponse)

            LogService.shared.info(.sync, "轻量级增量同步：\(modifiedNotes.count) 个笔记，\(modifiedFolders.count) 个文件夹有修改")

            var syncedNotes = 0
            var cloudNoteIds = Set<String>()
            var cloudFolderIds = Set<String>()

            for note in modifiedNotes {
                cloudNoteIds.insert(note.id)
            }
            for folder in modifiedFolders {
                if !folder.isSystem, folder.id != "0", folder.id != "starred" {
                    cloudFolderIds.insert(folder.id)
                }
            }

            // 处理有修改的文件夹
            syncStatusMessage = "同步有修改的文件夹..."
            if !modifiedFolders.isEmpty {
                for (index, folder) in modifiedFolders.enumerated() {
                    _syncProgressInternal = Double(index) / Double(max(modifiedFolders.count + modifiedNotes.count, 1))
                    syncStatusMessage = "正在同步文件夹: \(folder.name)"
                    try await processModifiedFolder(folder)
                }
            }

            // 处理有修改的笔记
            syncStatusMessage = "同步有修改的笔记..."
            if !modifiedNotes.isEmpty {
                for (index, note) in modifiedNotes.enumerated() {
                    _syncProgressInternal = Double(modifiedFolders.count + index) / Double(max(modifiedFolders.count + modifiedNotes.count, 1))
                    syncStatusMessage = "正在同步笔记: \(note.title)"

                    let noteResult = try await processModifiedNote(note)
                    result.addNoteResult(noteResult)

                    if noteResult.success {
                        syncedNotes += 1
                    }
                }
            }

            if !newSyncTag.isEmpty {
                let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
                try await syncStateManager.stageSyncTag(newSyncTag, hasPendingNotes: hasPendingNotes)
                LogService.shared.debug(.sync, "轻量级增量同步：syncTag 已通过 SyncStateManager 处理")
            }

            _syncProgressInternal = 1.0
            syncStatusMessage = "轻量级增量同步完成"

            result.totalNotes = modifiedNotes.count
            result.syncedNotes = syncedNotes
            result.lastSyncTime = Date()

            LogService.shared.info(.sync, "轻量级增量同步完成 - 总计: \(modifiedNotes.count), 成功: \(syncedNotes)")
        } catch {
            syncStatusMessage = "轻量级增量同步失败: \(error.localizedDescription)"
            throw error
        }

        return result
    }

    /// 从响应中提取syncTag
    ///
    /// 支持多种响应格式：
    /// 1. 旧API格式：直接返回syncTag字段
    /// 2. 网页版API格式：嵌套在note_view.data.syncTag中
    /// 3. 完整同步API格式：嵌套在data.syncTag中
    ///
    /// - Parameter response: API响应字典
    /// - Returns: syncTag，如果找不到则返回nil
    private func extractSyncTags(from response: [String: Any]) -> String? {
        var syncTag: String?

        // 尝试旧API格式：直接返回syncTag字段
        if let oldSyncTag = response["syncTag"] as? String {
            syncTag = oldSyncTag
        }

        // 尝试完整同步API格式：data.syncTag
        if let data = response["data"] as? [String: Any] {
            if let dataSyncTag = data["syncTag"] as? String {
                syncTag = dataSyncTag
            }

            // 尝试网页版API格式：note_view.data.syncTag
            if let noteView = data["note_view"] as? [String: Any],
               let noteViewData = noteView["data"] as? [String: Any],
               let webSyncTag = noteViewData["syncTag"] as? String
            {
                syncTag = webSyncTag
            }
        }

        // 尝试顶层 note_view.data.syncTag
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

    // MARK: - 增量同步辅助方法

    /// 增量同步文件夹
    ///
    /// 处理文件夹的增量同步逻辑：
    /// - 如果云端和本地都存在：比较时间戳，使用较新的版本
    /// - 如果只有云端存在：检查是否在删除队列中，如果是则删除云端，否则拉取到本地
    /// - 如果只有本地存在：检查是否在创建队列中，如果是则上传到云端，否则删除本地
    ///
    /// - Parameters:
    ///   - cloudFolders: 云端文件夹列表
    ///   - cloudFolderIds: 云端文件夹ID集合（用于快速查找）
    private func syncFoldersIncremental(cloudFolders: [Folder], cloudFolderIds _: Set<String>) async throws {
        // 使用统一操作队列
        let pendingOps = unifiedQueue.getPendingOperations()
        let localFolders = try localStorage.loadFolders()

        for cloudFolder in cloudFolders {
            // 跳过系统文件夹
            if cloudFolder.isSystem || cloudFolder.id == "0" || cloudFolder.id == "starred" {
                continue
            }

            if let localFolder = localFolders.first(where: { $0.id == cloudFolder.id }) {
                // 情况1：云端和本地都存在
                // 比较时间戳
                if cloudFolder.createdAt > localFolder.createdAt {
                    // 云端较新，拉取云端覆盖本地
                    try localStorage.saveFolders([cloudFolder])
                    LogService.shared.debug(.sync, "文件夹云端较新，已更新: \(cloudFolder.name)")
                } else if localFolder.createdAt > cloudFolder.createdAt {
                    // 本地较新，上传本地到云端（通过统一操作队列）
                    let hasRenameOp = pendingOps.contains { operation in
                        operation.type == .folderRename && operation.noteId == localFolder.id
                    }
                    if !hasRenameOp {
                        let opData: [String: Any] = [
                            "folderId": localFolder.id,
                            "name": localFolder.name,
                        ]
                        let data = try JSONSerialization.data(withJSONObject: opData)
                        let operation = NoteOperation(
                            type: .folderRename,
                            noteId: localFolder.id,
                            data: data,
                            status: .pending,
                            priority: NoteOperation.calculatePriority(for: .folderRename)
                        )
                        try unifiedQueue.enqueue(operation)
                        LogService.shared.debug(.sync, "文件夹本地较新，已添加到上传队列: \(localFolder.name)")
                    }
                } else {
                    if cloudFolder.name != localFolder.name {
                        try localStorage.saveFolders([cloudFolder])
                        LogService.shared.debug(.sync, "文件夹名称不同，已更新: \(cloudFolder.name)")
                    }
                }
            } else {
                // 只有云端存在，本地不存在
                let hasDeleteOp = pendingOps.contains { operation in
                    operation.type == .folderDelete && operation.noteId == cloudFolder.id
                }
                if hasDeleteOp {
                    if let tag = cloudFolder.rawData?["tag"] as? String {
                        _ = try await miNoteService.deleteFolder(folderId: cloudFolder.id, tag: tag, purge: false)
                        LogService.shared.debug(.sync, "文件夹在删除队列中，已删除云端: \(cloudFolder.name)")
                    }
                } else {
                    try localStorage.saveFolders([cloudFolder])
                    LogService.shared.debug(.sync, "新文件夹，已拉取到本地: \(cloudFolder.name)")
                }
            }
        }
    }

    /// 增量同步单个笔记
    ///
    /// 处理单个笔记的增量同步逻辑：
    /// - 如果本地和云端都存在：
    ///   - 本地较新：添加到更新队列，等待上传
    ///   - 云端较新：下载并覆盖本地
    ///   - 时间相同：比较内容，如果不同则下载云端版本
    /// - 如果只有云端存在：
    ///   - 在删除队列中：删除云端笔记
    ///   - 不在删除队列：下载到本地
    ///
    /// - Parameter cloudNote: 云端笔记对象
    /// - Returns: 同步结果，包含同步状态和消息
    private func syncNoteIncremental(cloudNote: Note) async throws -> NoteSyncResult {
        var result = NoteSyncResult(noteId: cloudNote.id, noteTitle: cloudNote.title)
        // 使用统一操作队列
        let pendingOps = unifiedQueue.getPendingOperations()

        // 同步保护检查：使用 SyncGuard 检查笔记是否应该被跳过
        // 包括：临时 ID 笔记、正在编辑、待上传等情况
        let shouldSkip = await syncGuard.shouldSkipSync(
            noteId: cloudNote.id,
            cloudTimestamp: cloudNote.updatedAt
        )
        if shouldSkip {
            if let skipReason = await syncGuard.getSkipReason(
                noteId: cloudNote.id,
                cloudTimestamp: cloudNote.updatedAt
            ) {
                LogService.shared.debug(.sync, "同步保护：跳过笔记 \(cloudNote.id.prefix(8)) - \(skipReason.description)")
            }
            result.status = .skipped
            result.message = "同步保护：笔记正在编辑、待上传或使用临时 ID"
            result.success = true
            return result
        }

        if let localNote = try localStorage.loadNote(noteId: cloudNote.id) {
            // 情况1：云端和本地都存在
            if localNote.updatedAt > cloudNote.updatedAt {
                // 本地较新，上传本地到云端
                let hasUpdateOp = pendingOps.contains { operation in
                    operation.type == .cloudUpload && operation.noteId == localNote.id
                }
                if !hasUpdateOp {
                    let opData: [String: Any] = [
                        "title": localNote.title,
                        "content": localNote.content,
                        "folderId": localNote.folderId,
                    ]
                    let data = try JSONSerialization.data(withJSONObject: opData)
                    let operation = NoteOperation(
                        type: .cloudUpload,
                        noteId: localNote.id,
                        data: data,
                        status: .pending,
                        priority: NoteOperation.calculatePriority(for: .cloudUpload)
                    )
                    try unifiedQueue.enqueue(operation)
                    LogService.shared.debug(.sync, "笔记本地较新，已添加到上传队列: \(localNote.title)")
                }
                result.status = .skipped
                result.message = "本地较新，等待上传"
                result.success = true
            } else if cloudNote.updatedAt > localNote.updatedAt {
                // 云端较新，拉取云端覆盖本地
                let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                var updatedNote = cloudNote
                updatedNote.updateContent(from: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                    var rawData = updatedNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    updatedNote.rawData = rawData
                }

                try localStorage.saveNote(updatedNote)
                result.status = .updated
                result.message = "已从云端更新"
                result.success = true
                LogService.shared.debug(.sync, "笔记云端较新，已更新: \(cloudNote.title)")
            } else {
                // 时间一致，比较内容
                if localNote.primaryXMLContent != cloudNote.primaryXMLContent {
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                    var updatedNote = cloudNote
                    updatedNote.updateContent(from: noteDetails)

                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                        var rawData = updatedNote.rawData ?? [:]
                        var setting = rawData["setting"] as? [String: Any] ?? [:]
                        setting["data"] = updatedSettingData
                        rawData["setting"] = setting
                        updatedNote.rawData = rawData
                    }

                    try localStorage.saveNote(updatedNote)
                    result.status = .updated
                    result.message = "内容不同，已更新"
                    result.success = true
                } else {
                    result.status = .skipped
                    result.message = "内容相同，跳过"
                    result.success = true
                }
            }
        } else {
            // 只有云端存在，本地不存在
            let hasDeleteOp: Bool = pendingOps.contains { operation in
                operation.type == .cloudDelete && operation.noteId == cloudNote.id
            }
            if hasDeleteOp {
                if let tag = cloudNote.rawData?["tag"] as? String {
                    _ = try await miNoteService.deleteNote(noteId: cloudNote.id, tag: tag, purge: false)
                    result.status = .skipped
                    result.message = "在删除队列中，已删除云端"
                    result.success = true
                    LogService.shared.debug(.sync, "笔记在删除队列中，已删除云端: \(cloudNote.title)")
                }
            } else {
                if let existingNote = try? localStorage.loadNote(noteId: cloudNote.id) {
                    if existingNote.updatedAt < cloudNote.updatedAt {
                        let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                        var updatedNote = cloudNote
                        updatedNote.updateContent(from: noteDetails)

                        if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                            var rawData = updatedNote.rawData ?? [:]
                            var setting = rawData["setting"] as? [String: Any] ?? [:]
                            setting["data"] = updatedSettingData
                            rawData["setting"] = setting
                            updatedNote.rawData = rawData
                        }

                        try localStorage.saveNote(updatedNote)
                        result.status = .updated
                        result.message = "已从云端更新"
                        result.success = true
                    } else {
                        result.status = .skipped
                        result.message = "本地已存在且较新或相同"
                        result.success = true
                    }
                } else {
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                    var updatedNote = cloudNote
                    updatedNote.updateContent(from: noteDetails)

                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                        var rawData = updatedNote.rawData ?? [:]
                        var setting = rawData["setting"] as? [String: Any] ?? [:]
                        setting["data"] = updatedSettingData
                        rawData["setting"] = setting
                        updatedNote.rawData = rawData
                    }

                    try localStorage.saveNote(updatedNote)
                    result.status = .created
                    result.message = "已从云端拉取"
                    result.success = true
                    LogService.shared.debug(.sync, "新笔记，已拉取到本地: \(cloudNote.title)")
                }
            }
        }

        return result
    }

    /// 处理只有本地存在但云端不存在的笔记和文件夹
    ///
    /// 这种情况可能发生在：
    /// 1. 本地创建了笔记但尚未上传（在创建队列中）
    /// 2. 云端已删除但本地仍存在（需要删除本地）
    ///
    /// **处理策略**：
    /// - 如果在创建队列中：上传到云端
    /// - 如果不在创建队列中：删除本地（说明云端已删除）
    ///
    /// - Parameters:
    ///   - cloudNoteIds: 云端笔记ID集合
    ///   - cloudFolderIds: 云端文件夹ID集合
    private func syncLocalOnlyItems(cloudNoteIds: Set<String>, cloudFolderIds: Set<String>) async throws {
        // 使用统一操作队列
        let pendingOps = unifiedQueue.getPendingOperations()
        let localNotes = try localStorage.getAllLocalNotes()
        let localFolders = try localStorage.loadFolders()

        // 处理本地独有的笔记
        for localNote in localNotes {
            // 临时 ID 笔记不会出现在云端，需要等待 noteCreate 操作完成后才能同步
            if NoteOperation.isTemporaryId(localNote.id) {
                continue
            }

            if !cloudNoteIds.contains(localNote.id) {
                let hasCreateOp: Bool = pendingOps.contains { operation in
                    operation.type == .noteCreate && operation.noteId == localNote.id
                }
                if hasCreateOp {
                    do {
                        let response = try await miNoteService.createNote(
                            title: localNote.title,
                            content: localNote.content,
                            folderId: localNote.folderId
                        )

                        if let code = response["code"] as? Int, code == 0,
                           let data = response["data"] as? [String: Any],
                           let entry = data["entry"] as? [String: Any],
                           let serverNoteId = entry["id"] as? String,
                           serverNoteId != localNote.id
                        {
                            var updatedRawData = localNote.rawData ?? [:]
                            for (key, value) in entry {
                                updatedRawData[key] = value
                            }

                            let updatedNote = Note(
                                id: serverNoteId,
                                title: localNote.title,
                                content: localNote.content,
                                folderId: localNote.folderId,
                                isStarred: localNote.isStarred,
                                createdAt: localNote.createdAt,
                                updatedAt: localNote.updatedAt,
                                tags: localNote.tags,
                                rawData: updatedRawData
                            )

                            try localStorage.saveNote(updatedNote)
                            try localStorage.deleteNote(noteId: localNote.id)
                            LogService.shared.info(.sync, "笔记上传后 ID 变更: \(localNote.id.prefix(8)) -> \(serverNoteId.prefix(8))")
                        }
                    } catch {
                        LogService.shared.error(.sync, "上传笔记失败: \(error.localizedDescription)")
                    }
                } else {
                    let hasUpdateOp: Bool = pendingOps.contains { operation in
                        operation.type == .cloudUpload && operation.noteId == localNote.id
                    }
                    if !hasUpdateOp {
                        try localStorage.deleteNote(noteId: localNote.id)
                        LogService.shared.debug(.sync, "笔记不在新建队列，已删除本地: \(localNote.title)")
                    }
                }
            }
        }

        for localFolder in localFolders {
            if !localFolder.isSystem,
               localFolder.id != "0",
               localFolder.id != "starred",
               !cloudFolderIds.contains(localFolder.id)
            {
                let hasCreateOp: Bool = pendingOps.contains { operation in
                    operation.type == .folderCreate && operation.noteId == localFolder.id
                }
                if hasCreateOp {
                    let response = try await miNoteService.createFolder(name: localFolder.name)

                    if let code = response["code"] as? Int, code == 0,
                       let data = response["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any]
                    {
                        var serverFolderId: String?
                        if let idString = entry["id"] as? String {
                            serverFolderId = idString
                        } else if let idInt = entry["id"] as? Int {
                            serverFolderId = String(idInt)
                        }

                        if let folderId = serverFolderId, folderId != localFolder.id {
                            try DatabaseService.shared.updateNotesFolderId(oldFolderId: localFolder.id, newFolderId: folderId)
                            try DatabaseService.shared.deleteFolder(folderId: localFolder.id)

                            let updatedFolder = Folder(
                                id: folderId,
                                name: entry["subject"] as? String ?? localFolder.name,
                                count: 0,
                                isSystem: false,
                                createdAt: Date()
                            )
                            try localStorage.saveFolders([updatedFolder])

                            LogService.shared.info(.sync, "文件夹 ID 已更新: \(localFolder.id.prefix(8)) -> \(folderId.prefix(8))")
                        }
                    } else {
                        LogService.shared.warning(.sync, "文件夹上传后服务器返回无效响应: \(localFolder.name)")
                    }
                } else {
                    try DatabaseService.shared.deleteFolder(folderId: localFolder.id)
                    LogService.shared.debug(.sync, "文件夹不在新建队列，已删除本地: \(localFolder.name)")
                }
            }
        }
    }

    // MARK: - 处理单个笔记

    /// 处理单个笔记（完整同步模式）
    ///
    /// 在完整同步模式下，直接下载并替换本地笔记，不进行任何比较
    ///
    /// - Parameters:
    ///   - note: 要处理的笔记
    ///   - isFullSync: 是否为完整同步模式
    /// - Returns: 同步结果
    private func processNote(_ note: Note, isFullSync: Bool = false) async throws -> NoteSyncResult {
        var result = NoteSyncResult(noteId: note.id, noteTitle: note.title)

        do {
            if isFullSync {
                syncStatusMessage = "下载笔记: \(note.title)"
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                } catch let error as MiNoteError {
                    switch error {
                    case .cookieExpired: throw SyncError.cookieExpired
                    case .notAuthenticated: throw SyncError.notAuthenticated
                    case let .networkError(e): throw SyncError.networkError(e)
                    case .invalidResponse: throw SyncError.networkError(error)
                    }
                } catch {
                    throw SyncError.networkError(error)
                }

                var updatedNote = note
                updatedNote.updateContent(from: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    var rawData = updatedNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    updatedNote.rawData = rawData
                }

                try localStorage.saveNote(updatedNote)

                result.status = localStorage.noteExistsLocally(noteId: note.id) ? .updated : .created
                result.message = result.status == .updated ? "笔记已替换" : "笔记已下载"
                result.success = true
                return result
            }

            let existsLocally = localStorage.noteExistsLocally(noteId: note.id)

            if existsLocally {
                if let localNote = try? localStorage.loadNote(noteId: note.id) {
                    let localModDate = localNote.updatedAt
                    let timeDifference = abs(note.updatedAt.timeIntervalSince(localModDate))

                    if note.updatedAt < localModDate, timeDifference > 2.0 {
                        result.status = .skipped
                        result.message = "本地版本较新，跳过同步"
                        result.success = true
                        return result
                    }

                    if timeDifference < 2.0 {
                        do {
                            let noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                            var cloudNote = note
                            cloudNote.updateContent(from: noteDetails)

                            let localContent = localNote.primaryXMLContent
                            let cloudContent = cloudNote.primaryXMLContent

                            if localContent == cloudContent {
                                result.status = .skipped
                                result.message = "笔记未修改"
                                result.success = true
                                return result
                            } else {
                                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                                    var rawData = cloudNote.rawData ?? [:]
                                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                                    setting["data"] = updatedSettingData
                                    rawData["setting"] = setting
                                    cloudNote.rawData = rawData
                                }

                                var updatedNote = cloudNote
                                updatedNote.updateContent(from: noteDetails)
                                try localStorage.saveNote(updatedNote)
                                result.status = .updated
                                result.message = "笔记已更新"
                                result.success = true
                                return result
                            }
                        } catch {
                            LogService.shared.warning(.sync, "获取笔记详情失败，继续使用原有逻辑: \(error)")
                        }
                    }
                }

                syncStatusMessage = "获取笔记详情: \(note.title)"
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                } catch let error as MiNoteError {
                    switch error {
                    case .cookieExpired: throw SyncError.cookieExpired
                    case .notAuthenticated: throw SyncError.notAuthenticated
                    case let .networkError(e): throw SyncError.networkError(e)
                    case .invalidResponse: throw SyncError.networkError(error)
                    }
                } catch {
                    throw SyncError.networkError(error)
                }

                var updatedNote = note
                updatedNote.updateContent(from: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    var rawData = updatedNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    updatedNote.rawData = rawData
                }

                try localStorage.saveNote(updatedNote)
                result.status = .updated
                result.message = "笔记已更新"
            } else {
                syncStatusMessage = "下载新笔记: \(note.title)"
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                } catch let error as MiNoteError {
                    switch error {
                    case .cookieExpired: throw SyncError.cookieExpired
                    case .notAuthenticated: throw SyncError.notAuthenticated
                    case let .networkError(e): throw SyncError.networkError(e)
                    case .invalidResponse: throw SyncError.networkError(error)
                    }
                } catch {
                    throw SyncError.networkError(error)
                }

                var newNote = note
                newNote.updateContent(from: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    var rawData = newNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    newNote.rawData = rawData
                }

                try localStorage.saveNote(newNote)
                result.status = .created
                result.message = "新笔记已下载"
            }

            result.success = true
        } catch let error as SyncError {
            throw error
        } catch {
            result.success = false
            result.status = .failed
            result.message = "处理失败: \(error.localizedDescription)"
        }

        return result
    }

    // MARK: - 处理文件夹

    private func processFolder(_ folder: Folder) async throws {
        do {
            _ = try localStorage.createFolder(folder.name)
        } catch {
            LogService.shared.error(.sync, "创建文件夹失败 \(folder.name): \(error)")
        }
    }

    // MARK: - 附件处理（图片和音频）

    /// 下载笔记中的附件（图片和音频）
    ///
    /// 从笔记的setting.data字段中提取附件信息，并下载到本地
    /// 附件信息包括：fileId、mimeType等
    ///
    /// - Parameters:
    ///   - noteDetails: 笔记详情响应（包含setting.data字段）
    /// 下载笔记中的附件(图片和音频)
    /// - Parameters:
    ///   - noteDetails: 笔记详情响应
    ///   - noteId: 笔记ID（用于日志和错误处理）
    ///   - forceRedownload: 是否强制重新下载(忽略现有文件)
    /// - Returns: 更新后的setting.data数组，包含附件下载状态信息
    private func downloadNoteImages(from noteDetails: [String: Any], noteId: String, forceRedownload: Bool = false) async throws -> [[String: Any]]? {
        // 提取 entry 对象
        var entry: [String: Any]?
        if let data = noteDetails["data"] as? [String: Any] {
            if let dataEntry = data["entry"] as? [String: Any] {
                entry = dataEntry
            }
        } else if let directEntry = noteDetails["entry"] as? [String: Any] {
            entry = directEntry
        } else if noteDetails["id"] != nil || noteDetails["content"] != nil {
            entry = noteDetails
        }

        guard let entry else {
            LogService.shared.debug(.sync, "无法提取 entry，跳过附件下载: \(noteId)")
            return nil
        }

        var settingData: [[String: Any]] = []

        if let setting = entry["setting"] as? [String: Any],
           let existingData = setting["data"] as? [[String: Any]]
        {
            settingData = existingData
        }

        for index in 0 ..< settingData.count {
            let attachmentData = settingData[index]

            guard let fileId = attachmentData["fileId"] as? String else { continue }
            guard let mimeType = attachmentData["mimeType"] as? String else { continue }

            if mimeType.hasPrefix("image/") {
                let fileType = String(mimeType.dropFirst("image/".count))

                if !forceRedownload {
                    if localStorage.validateImage(fileId: fileId, fileType: fileType) {
                        var updatedData = attachmentData
                        updatedData["localExists"] = true
                        settingData[index] = updatedData
                        continue
                    }
                }

                do {
                    let imageData = try await downloadImageWithRetry(fileId: fileId, type: "note_img")
                    try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)
                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    updatedData["downloaded"] = true
                    settingData[index] = updatedData
                } catch {
                    LogService.shared.error(.sync, "图片下载失败: \(fileId).\(fileType) - \(error.localizedDescription)")
                }
            } else if mimeType.hasPrefix("audio/") {
                if AudioCacheService.shared.isCached(fileId: fileId) {
                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    settingData[index] = updatedData
                    continue
                }

                do {
                    let audioData = try await miNoteService.downloadAudio(fileId: fileId)
                    try AudioCacheService.shared.cacheFile(data: audioData, fileId: fileId, mimeType: mimeType)
                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    updatedData["downloaded"] = true
                    settingData[index] = updatedData
                } catch {
                    LogService.shared.error(.sync, "音频下载失败: \(fileId) - \(error.localizedDescription)")
                }
            }
        }

        if let content = entry["content"] as? String {
            let allAttachmentData = await extractAndDownloadAllAttachments(
                from: content,
                existingSettingData: settingData,
                forceRedownload: forceRedownload
            )
            settingData = allAttachmentData
        }

        return settingData
    }

    /// 下载图片(带重试机制)
    /// - Parameters:
    ///   - fileId: 文件ID
    ///   - type: 文件类型
    ///   - maxRetries: 最大重试次数
    /// - Returns: 图片数据
    /// - Throws: 下载失败错误
    private func downloadImageWithRetry(
        fileId: String,
        type: String,
        maxRetries: Int = 3
    ) async throws -> Data {
        var lastError: Error?

        for attempt in 1 ... maxRetries {
            do {
                return try await miNoteService.downloadFile(fileId: fileId, type: type)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let delay = TimeInterval(attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        LogService.shared.error(.sync, "图片下载失败（已重试 \(maxRetries) 次）: \(fileId)")
        throw lastError ?? SyncError.networkError(NSError(domain: "SyncService", code: -1, userInfo: [NSLocalizedDescriptionKey: "图片下载失败"]))
    }

    /// 从 content 中提取所有附件（图片和音频），并生成 setting.data
    ///
    /// 支持的格式：
    /// - 旧版图片格式: ☺ fileId<0/></>
    /// - 新版图片格式: <img fileid="xxx" />
    /// - 音频格式: <sound fileid="xxx" />
    ///
    /// - Parameters:
    ///   - content: 笔记内容
    ///   - existingSettingData: 已存在的 setting.data 数组
    ///   - forceRedownload: 是否强制重新下载
    /// - Returns: 完整的 setting.data 数组（包含所有附件的元数据）
    private func extractAndDownloadAllAttachments(
        from content: String,
        existingSettingData: [[String: Any]],
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        var allSettingData: [[String: Any]] = existingSettingData
        var existingFileIds = Set<String>()

        for entry in existingSettingData {
            if let fileId = entry["fileId"] as? String {
                existingFileIds.insert(fileId)
            }
        }

        let legacyImageData = await extractLegacyImages(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !legacyImageData.isEmpty {
            allSettingData.append(contentsOf: legacyImageData)
            for entry in legacyImageData {
                if let fileId = entry["fileId"] as? String { existingFileIds.insert(fileId) }
            }
        }

        let newImageData = await extractNewFormatImages(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !newImageData.isEmpty {
            allSettingData.append(contentsOf: newImageData)
            for entry in newImageData {
                if let fileId = entry["fileId"] as? String { existingFileIds.insert(fileId) }
            }
        }

        let audioData = await extractAudioAttachments(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !audioData.isEmpty {
            allSettingData.append(contentsOf: audioData)
        }

        return allSettingData
    }

    /// 提取旧版格式图片
    private func extractLegacyImages(
        from content: String,
        existingFileIds: Set<String>,
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        let pattern = "☺ ([^<]+)<0/></>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        if matches.isEmpty { return [] }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }

            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            if existingFileIds.contains(fileId) { continue }

            if let entry = await downloadAndCreateSettingEntry(
                fileId: fileId,
                type: "note_img",
                attachmentType: "image",
                forceRedownload: forceRedownload
            ) {
                settingDataEntries.append(entry)
            }
        }

        return settingDataEntries
    }

    /// 提取新版格式图片
    private func extractNewFormatImages(
        from content: String,
        existingFileIds: Set<String>,
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        let pattern = "<img[^>]+fileid=\"([^\"]+)\"[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        if matches.isEmpty { return [] }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }

            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            if existingFileIds.contains(fileId) { continue }

            if let entry = await downloadAndCreateSettingEntry(
                fileId: fileId,
                type: "note_img",
                attachmentType: "image",
                forceRedownload: forceRedownload
            ) {
                settingDataEntries.append(entry)
            }
        }

        return settingDataEntries
    }

    /// 提取音频附件
    private func extractAudioAttachments(
        from content: String,
        existingFileIds: Set<String>,
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        let pattern = "<sound[^>]+fileid=\"([^\"]+)\"[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        if matches.isEmpty { return [] }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }

            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            if existingFileIds.contains(fileId) { continue }

            if let entry = await downloadAndCreateSettingEntry(
                fileId: fileId,
                type: "note_audio",
                attachmentType: "audio",
                forceRedownload: forceRedownload
            ) {
                settingDataEntries.append(entry)
            }
        }

        return settingDataEntries
    }

    /// 下载附件并创建 setting.data 条目
    ///
    /// - Parameters:
    ///   - fileId: 文件ID
    ///   - type: 下载类型（note_img 或 note_audio）
    ///   - attachmentType: 附件类型（image 或 audio）
    ///   - forceRedownload: 是否强制重新下载
    /// - Returns: setting.data 条目，如果下载失败则返回 nil
    private func downloadAndCreateSettingEntry(
        fileId: String,
        type: String,
        attachmentType: String,
        forceRedownload: Bool
    ) async -> [String: Any]? {
        var existingFormat: String?
        var fileSize = 0

        if !forceRedownload {
            if attachmentType == "image" {
                let formats = ["jpg", "jpeg", "png", "gif", "webp"]
                for format in formats {
                    if localStorage.validateImage(fileId: fileId, fileType: format) {
                        existingFormat = format
                        if let imageData = localStorage.loadImage(fileId: fileId, fileType: format) {
                            fileSize = imageData.count
                        }
                        break
                    }
                }
            } else if attachmentType == "audio" {
                if AudioCacheService.shared.isCached(fileId: fileId) {
                    existingFormat = "amr"
                    if let cachedFileURL = AudioCacheService.shared.getCachedFile(for: fileId) {
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: cachedFileURL.path),
                           let size = attributes[.size] as? Int
                        {
                            fileSize = size
                        }
                    }
                }
            }
        }

        var downloadedFormat: String?

        if existingFormat == nil {
            do {
                let data = try await downloadImageWithRetry(fileId: fileId, type: type)
                fileSize = data.count

                if attachmentType == "image" {
                    let detectedFormat = detectImageFormat(from: data)
                    downloadedFormat = detectedFormat
                    try localStorage.saveImage(imageData: data, fileId: fileId, fileType: detectedFormat)
                } else if attachmentType == "audio" {
                    let detectedFormat = detectAudioFormat(from: data)
                    downloadedFormat = detectedFormat
                    let mimeType = "audio/\(detectedFormat)"
                    do {
                        try AudioCacheService.shared.cacheFile(data: data, fileId: fileId, mimeType: mimeType)
                    } catch {
                        LogService.shared.error(.sync, "音频保存失败: \(fileId) - \(error)")
                        return nil
                    }
                }
            } catch {
                LogService.shared.error(.sync, "附件下载失败: \(fileId) - \(error.localizedDescription)")
                return nil
            }
        }

        let finalFormat = downloadedFormat ?? existingFormat ?? (attachmentType == "image" ? "jpeg" : "amr")
        let mimeType = attachmentType == "image" ? "image/\(finalFormat)" : "audio/\(finalFormat)"

        return [
            "fileId": fileId,
            "mimeType": mimeType,
            "size": fileSize,
        ]
    }

    /// 从content中提取并下载旧版格式的图片，同时生成 setting.data
    /// 旧版格式: ☺ fileId<0/></>
    ///
    /// 已废弃：请使用 extractAndDownloadAllAttachments 方法
    ///
    /// - Parameters:
    ///   - content: 笔记内容
    ///   - forceRedownload: 是否强制重新下载
    /// - Returns: 生成的 setting.data 数组（包含旧版格式图片的元数据）
    private func downloadLegacyFormatImages(from content: String, forceRedownload: Bool) async -> [[String: Any]] {
        // 调用新的统一方法
        await extractLegacyImages(from: content, existingFileIds: Set(), forceRedownload: forceRedownload)
    }

    /// 检测图片格式
    /// - Parameter data: 图片数据
    /// - Returns: 图片格式（jpeg, png, gif, webp）
    private func detectImageFormat(from data: Data) -> String {
        // 检查文件头来判断格式
        guard data.count >= 12 else { return "jpeg" }

        let bytes = [UInt8](data.prefix(12))

        // PNG: 89 50 4E 47
        if bytes.count >= 4, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            return "png"
        }

        // GIF: 47 49 46
        if bytes.count >= 3, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 {
            return "gif"
        }

        // WebP: 52 49 46 46 ... 57 45 42 50
        if bytes.count >= 12, bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50
        {
            return "webp"
        }

        // JPEG: FF D8 FF
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "jpeg"
        }

        // 默认返回 jpeg
        return "jpeg"
    }

    /// 检测音频格式
    ///
    /// 通过检查文件头魔数来判断音频格式
    ///
    /// - Parameter data: 音频数据
    /// - Returns: 音频格式（amr, mp3, m4a, wav 等）
    private func detectAudioFormat(from data: Data) -> String {
        // 检查文件头魔数
        guard data.count >= 12 else {
            return "amr" // 默认格式
        }

        let bytes = [UInt8](data.prefix(12))

        // AMR 格式: #!AMR\n (0x23 0x21 0x41 0x4D 0x52 0x0A)
        if bytes.count >= 6,
           bytes[0] == 0x23, bytes[1] == 0x21,
           bytes[2] == 0x41, bytes[3] == 0x4D,
           bytes[4] == 0x52, bytes[5] == 0x0A
        {
            return "amr"
        }

        // MP3 格式: ID3 (0x49 0x44 0x33) 或 0xFF 0xFB
        if bytes.count >= 3,
           (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
           (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0)
        {
            return "mp3"
        }

        // M4A 格式: ftyp (0x66 0x74 0x79 0x70)
        if bytes.count >= 8,
           bytes[4] == 0x66, bytes[5] == 0x74,
           bytes[6] == 0x79, bytes[7] == 0x70
        {
            return "m4a"
        }

        // WAV 格式: RIFF...WAVE (0x52 0x49 0x46 0x46 ... 0x57 0x41 0x56 0x45)
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49,
           bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x41,
           bytes[10] == 0x56, bytes[11] == 0x45
        {
            return "wav"
        }

        // 默认返回 amr（小米笔记主要使用 AMR 格式）
        return "amr"
    }

    /// 手动重新下载笔记的所有图片
    /// - Parameter noteId: 笔记ID
    /// - Returns: 下载结果(成功数量, 失败数量)
    /// - Throws: 同步错误
    func redownloadNoteImages(noteId: String) async throws -> (success: Int, failed: Int) {
        LogService.shared.info(.sync, "手动重新下载笔记图片: \(noteId)")

        guard miNoteService.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }

        // 获取笔记详情
        let noteDetails = try await miNoteService.fetchNoteDetails(noteId: noteId)

        // 强制重新下载所有图片
        guard let updatedSettingData = try await downloadNoteImages(
            from: noteDetails,
            noteId: noteId,
            forceRedownload: true
        ) else {
            return (0, 0)
        }

        // 统计结果
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

    // MARK: - 手动同步单个笔记

    /// 手动同步单个笔记
    ///
    /// 用于用户手动触发单个笔记的同步，例如在笔记详情页面点击"同步"按钮
    ///
    /// - Parameter noteId: 要同步的笔记ID
    /// - Returns: 同步结果
    /// - Throws: SyncError（同步错误、网络错误等）
    func syncSingleNote(noteId: String) async throws -> NoteSyncResult {
        guard miNoteService.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }

        syncStatusMessage = "同步单个笔记..."

        // 获取笔记详情
        let noteDetails: [String: Any]
        do {
            noteDetails = try await miNoteService.fetchNoteDetails(noteId: noteId)
        } catch let error as MiNoteError {
            switch error {
            case .cookieExpired:
                throw SyncError.cookieExpired
            case .notAuthenticated:
                throw SyncError.notAuthenticated
            case let .networkError(underlyingError):
                throw SyncError.networkError(underlyingError)
            case .invalidResponse:
                throw SyncError.networkError(error)
            }
        } catch {
            throw SyncError.networkError(error)
        }

        // 转换为Note对象
        guard let note = Note.fromMinoteData(noteDetails) else {
            throw SyncError.invalidNoteData
        }

        // 处理笔记
        return try await processNote(note)
    }

    // MARK: - 取消同步

    /// 取消正在进行的同步
    ///
    /// 注意：此方法只是设置标志位，不会立即中断正在执行的网络请求
    func cancelSync() {
        _isSyncingInternal = false
        syncStatusMessage = "同步已取消"
    }

    // MARK: - 轻量级增量同步辅助方法

    /// 解析轻量级同步响应
    ///
    /// 解析网页版 `/note/sync/full/` API 的响应，提取：
    /// 1. 有修改的笔记（包括删除的笔记）
    /// 2. 有修改的文件夹（包括删除的文件夹）
    /// 3. 新的 syncTag
    ///
    /// - Parameter response: API响应字典
    /// - Returns: 包含有修改的笔记、文件夹和新的syncTag的元组
    /// - Throws: SyncError（如果响应格式无效）
    private func parseLightweightSyncResponse(_ response: [String: Any]) throws -> (notes: [Note], folders: [Folder], syncTag: String) {
        var syncTag = ""
        if let data = response["data"] as? [String: Any],
           let noteView = data["note_view"] as? [String: Any],
           let noteViewData = noteView["data"] as? [String: Any],
           let newSyncTag = noteViewData["syncTag"] as? String
        {
            syncTag = newSyncTag
        }

        var modifiedNotes: [Note] = []
        var modifiedFolders: [Folder] = []

        if let data = response["data"] as? [String: Any],
           let noteView = data["note_view"] as? [String: Any],
           let noteViewData = noteView["data"] as? [String: Any]
        {
            if let entries = noteViewData["entries"] as? [[String: Any]] {
                for entry in entries {
                    if let note = Note.fromMinoteData(entry) {
                        modifiedNotes.append(note)
                    }
                }
            }

            if let folders = noteViewData["folders"] as? [[String: Any]] {
                for folderEntry in folders {
                    if let folder = Folder.fromMinoteData(folderEntry) {
                        modifiedFolders.append(folder)
                    }
                }
            }
        }

        LogService.shared.debug(.sync, "解析轻量级同步响应: \(modifiedNotes.count) 个笔记, \(modifiedFolders.count) 个文件夹")
        return (modifiedNotes, modifiedFolders, syncTag)
    }

    /// 处理有修改的文件夹
    ///
    /// 根据文件夹的状态进行处理：
    /// - 如果状态为 "deleted": 从本地删除
    /// - 如果状态为 "normal": 保存到本地
    ///
    /// - Parameter folder: 有修改的文件夹
    /// - Throws: SyncError（存储错误等）
    private func processModifiedFolder(_ folder: Folder) async throws {
        if let rawData = folder.rawData,
           let status = rawData["status"] as? String,
           status == "deleted"
        {
            try DatabaseService.shared.deleteFolder(folderId: folder.id)
            LogService.shared.debug(.sync, "文件夹已删除: \(folder.id)")
        } else {
            try localStorage.saveFolders([folder])
            LogService.shared.debug(.sync, "文件夹已更新: \(folder.name)")
        }
    }

    /// 处理有修改的笔记
    ///
    /// 根据笔记的状态进行处理：
    /// - 如果状态为 "deleted": 从本地删除
    /// - 如果状态为 "normal": 获取完整内容并保存到本地
    ///
    /// - Parameter note: 有修改的笔记
    /// - Returns: 同步结果
    /// - Throws: SyncError（网络错误、存储错误等）
    private func processModifiedNote(_ note: Note) async throws -> NoteSyncResult {
        var result = NoteSyncResult(noteId: note.id, noteTitle: note.title)

        let shouldSkip = await syncGuard.shouldSkipSync(
            noteId: note.id,
            cloudTimestamp: note.updatedAt
        )
        if shouldSkip {
            if let skipReason = await syncGuard.getSkipReason(
                noteId: note.id,
                cloudTimestamp: note.updatedAt
            ) {
                LogService.shared.debug(.sync, "同步保护：跳过笔记 \(note.id.prefix(8)) - \(skipReason.description)")
            }
            result.status = .skipped
            result.message = "同步保护：笔记正在编辑、待上传或使用临时 ID"
            result.success = true
            return result
        }

        if let rawData = note.rawData,
           let status = rawData["status"] as? String,
           status == "deleted"
        {
            try localStorage.deleteNote(noteId: note.id)
            result.status = .skipped
            result.message = "笔记已从云端删除"
            result.success = true
            return result
        }

        do {
            syncStatusMessage = "获取笔记详情: \(note.title)"
            let noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)

            var updatedNote = note
            updatedNote.updateContent(from: noteDetails)

            if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                var rawData = updatedNote.rawData ?? [:]
                var setting = rawData["setting"] as? [String: Any] ?? [:]
                setting["data"] = updatedSettingData
                rawData["setting"] = setting
                updatedNote.rawData = rawData
            }

            try localStorage.saveNote(updatedNote)

            let existsLocally = localStorage.noteExistsLocally(noteId: note.id)
            result.status = existsLocally ? .updated : .created
            result.message = existsLocally ? "笔记已更新" : "新笔记已下载"
            result.success = true
        } catch let error as MiNoteError {
            switch error {
            case .cookieExpired:
                throw SyncError.cookieExpired
            case .notAuthenticated:
                throw SyncError.notAuthenticated
            case let .networkError(underlyingError):
                throw SyncError.networkError(underlyingError)
            case .invalidResponse:
                throw SyncError.networkError(error)
            }
        } catch {
            LogService.shared.error(.sync, "获取笔记详情失败: \(error)")
            throw SyncError.networkError(error)
        }

        return result
    }

    // MARK: - 重置同步状态

    /// 重置同步状态
    ///
    /// 清除所有同步记录，下次同步将执行完整同步
    /// 用于解决同步问题或重新开始同步
    func resetSyncStatus() throws {
        try localStorage.clearSyncStatus()
    }

    // MARK: - 同步结果模型

    /// 同步结果
    ///
    /// 包含同步操作的统计信息，用于UI显示和日志记录
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

    /// 单个笔记的同步结果
    struct NoteSyncResult {
        let noteId: String
        let noteTitle: String
        var success = false
        var status: SyncStatusType = .failed
        var message = ""

        /// 同步状态类型
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
}
