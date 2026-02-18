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
        print("[SYNC] SyncService 初始化完成，已注入 SyncStateManager")
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
            print("[SYNC] ⚠️ 同步锁获取失败：同步正在进行中")
            return false
        }

        _isSyncing = true // 直接设置而不调用setter，避免死锁
        print("[SYNC] 🔒 同步锁已获取")
        return true
    }

    /// 释放同步锁
    /// 遵循需求 6.2: 同步完成后更新状态
    private func releaseSyncLock() {
        syncLock.lock()
        defer { syncLock.unlock() }

        _isSyncingInternal = false
        print("[SYNC] 🔓 同步锁已释放")
    }

    /// 执行智能同步
    /// 遵循需求 6.3, 6.4:
    /// - 如果存在有效的 SyncStatus，使用增量同步
    /// - 如果是首次登录或 SyncStatus 不存在，执行完整同步
    /// - Returns: 同步结果
    /// - Throws: SyncError
    func performSmartSync() async throws -> SyncResult {
        print("[SYNC] 🧠 开始智能同步...")

        if hasValidSyncStatus {
            print("[SYNC] 存在有效的同步状态，执行增量同步（需求 6.3）")
            return try await performIncrementalSync()
        } else {
            print("[SYNC] 不存在有效的同步状态，执行完整同步（需求 6.4）")
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
        print("[SYNC] 开始执行完整同步，checkIsSyncing: \(checkIsSyncing)")

        if checkIsSyncing {
            guard !_isSyncingInternal else {
                print("[SYNC] 错误：同步正在进行中")
                throw SyncError.alreadySyncing
            }
        }

        guard miNoteService.isAuthenticated() else {
            print("[SYNC] 错误：未认证")
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
            print("[SYNC] 同步结束，isSyncing设置为false")
        }

        var result = SyncResult()
        var syncTag = ""

        do {
            // 1. 清除所有本地数据（保护临时 ID 笔记）
            syncStatusMessage = "清除所有本地数据..."
            print("[SYNC] 清除所有本地笔记和文件夹")
            let localNotes = try localStorage.getAllLocalNotes()
            for note in localNotes {
                // 🛡️ 保护临时 ID 笔记（离线创建的笔记）
                // 这些笔记尚未上传到云端，不应该被删除
                if NoteOperation.isTemporaryId(note.id) {
                    print("[SYNC] 🛡️ 保护临时 ID 笔记: \(note.id.prefix(8))... - \(note.title)")
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
            print("[SYNC] 已清除所有本地数据")

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
                    print("[SYNC] ✅ 已保存 \(allCloudFolders.count) 个云端文件夹")
                } catch {
                    print("[SYNC] ⚠️ 保存文件夹失败: \(error.localizedDescription)")
                    // 继续执行，不影响笔记同步
                }
            } else {
                print("[SYNC] ⚠️ 没有找到云端文件夹")
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
                    print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")

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
                            print("[SYNC] 更新笔记的 setting.data 和 settingJson，包含 \(updatedSettingData.count) 个图片条目")
                            print("[SYNC] 📝 settingJson 内容: \(settingString.prefix(200))...")
                        } else {
                            print("[SYNC] ⚠️ 无法将 setting 转换为 JSON 字符串")
                        }
                    }

                    // 保存到本地
                    print("[SYNC] 保存笔记: \(updatedNote.id)")
                    try localStorage.saveNote(updatedNote)
                    syncedNotes += 1
                } catch {
                    print("[SYNC] ⚠️ 保存笔记失败: \(note.id) - \(error.localizedDescription)")
                    failedNotes += 1
                    // 继续处理下一个笔记
                }
            }

            // 5. 获取并同步私密笔记
            syncStatusMessage = "获取私密笔记..."
            do {
                let privateNotesResponse = try await miNoteService.fetchPrivateNotes(folderId: "2", limit: 200)
                let privateNotes = miNoteService.parseNotes(from: privateNotesResponse)

                print("[SYNC] 获取到 \(privateNotes.count) 条私密笔记")
                totalNotes += privateNotes.count

                // 处理私密笔记
                for (index, note) in privateNotes.enumerated() {
                    _syncProgressInternal = Double(syncedNotes + index) / Double(max(totalNotes, 1))
                    syncStatusMessage = "正在同步私密笔记: \(note.title)"

                    // 获取笔记详情
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    var updatedNote = note
                    updatedNote.updateContent(from: noteDetails)
                    print("[SYNC] 更新私密笔记内容，content长度: \(updatedNote.content.count)")

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
                            print("[SYNC] 更新私密笔记的 setting.data 和 settingJson，包含 \(updatedSettingData.count) 个图片条目")
                            print("[SYNC] 📝 settingJson 内容: \(settingString.prefix(200))...")
                        } else {
                            print("[SYNC] ⚠️ 无法将 setting 转换为 JSON 字符串")
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

                    print("[SYNC] 保存私密笔记: \(finalNote.id)")
                    try localStorage.saveNote(finalNote)
                    syncedNotes += 1
                }
            } catch {
                print("[SYNC] ⚠️ 获取私密笔记失败: \(error.localizedDescription)")
                // 不抛出错误，继续执行同步流程
            }

            // 6. 更新同步状态 - 使用 SyncStateManager
            // 保存syncTag（即使为空也要保存，但记录警告）
            // 注意：syncStatus.syncTag 已经在循环中被设置，这里不需要检查 syncTag 变量
            var finalSyncTag = syncStatus.syncTag

            if let currentSyncTag = syncStatus.syncTag, !currentSyncTag.isEmpty {
                print("[SYNC] 完整同步：找到 syncTag: \(currentSyncTag)")
            } else {
                print("[SYNC] ⚠️ 完整同步：syncTag为空，尝试从最后一次API响应中提取")
                // 尝试从最后一次API响应中提取syncTag
                do {
                    let lastPageResponse = try await miNoteService.fetchPage(syncTag: "")
                    print("[SYNC] 完整同步：获取最后一次API响应成功")
                    if let lastSyncTag = lastPageResponse["syncTag"] as? String,
                       !lastSyncTag.isEmpty
                    {
                        finalSyncTag = lastSyncTag
                        print("[SYNC] 完整同步：从最后一次API响应中提取syncTag: \(lastSyncTag)")
                    } else {
                        // 尝试使用extractSyncTags方法提取
                        if let extractedSyncTag = extractSyncTags(from: lastPageResponse) {
                            finalSyncTag = extractedSyncTag
                            print("[SYNC] 完整同步：使用extractSyncTags提取syncTag: \(extractedSyncTag)")
                        } else {
                            print("[SYNC] ⚠️ 完整同步：无法从最后一次API响应中提取syncTag")
                        }
                    }
                } catch {
                    print("[SYNC] ⚠️ 完整同步：获取最后一次API响应失败: \(error)")
                    // 即使失败也要继续，但syncTag可能为空
                }
            }

            // 使用 SyncStateManager 暂存 syncTag（需求 2.1, 2.3）
            if let syncTag = finalSyncTag, !syncTag.isEmpty {
                print("[SYNC] 完整同步：使用 SyncStateManager 暂存 syncTag: \(syncTag)")

                // 完整同步后通常没有待上传笔记，直接确认
                let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
                print("[SYNC] 完整同步：是否有待上传笔记: \(hasPendingNotes)")

                try await syncStateManager.stageSyncTag(syncTag, hasPendingNotes: hasPendingNotes)
                print("[SYNC] 完整同步：syncTag 已通过 SyncStateManager 处理")
            } else {
                print("[SYNC] ⚠️ 完整同步：syncTag 为空，无法暂存")
            }

            // 移除直接更新 LocalStorageService 的代码（已由 SyncStateManager 处理）
            // 移除内部缓存更新（不再需要）

            _syncProgressInternal = 1.0
            syncStatusMessage = "完整同步完成"

            result.totalNotes = totalNotes
            result.syncedNotes = syncedNotes
            result.lastSyncTime = Date()

            // 打印同步统计
            print("[SYNC] 📊 完整同步统计:")
            print("[SYNC]   - 总笔记数: \(totalNotes)")
            print("[SYNC]   - 成功同步: \(syncedNotes)")
            print("[SYNC]   - 失败笔记: \(failedNotes)")
            print("[SYNC]   - 文件夹数: \(allCloudFolders.count)")

            // 显示同步状态信息
            print("[SYNC] 🔍 完整同步完成，显示同步状态信息:")
            if let savedStatus = localStorage.loadSyncStatus() {
                print("[SYNC]   - lastSyncTime: \(savedStatus.lastSyncTime?.description ?? "nil")")
                print("[SYNC]   - syncTag: \(savedStatus.syncTag ?? "nil")")
            } else {
                print("[SYNC]   ⚠️ 无法加载同步状态")
            }
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
        print("[SYNC] 开始执行增量同步")
        guard !_isSyncingInternal else {
            print("[SYNC] 错误：同步正在进行中")
            throw SyncError.alreadySyncing
        }

        guard miNoteService.isAuthenticated() else {
            print("[SYNC] 错误：未认证")
            throw SyncError.notAuthenticated
        }

        // 加载现有的同步状态
        guard let syncStatus = localStorage.loadSyncStatus() else {
            // 如果没有同步状态，执行完整同步（在设置 isSyncing 之前检查）
            print("[SYNC] 未找到同步记录，执行完整同步...")
            return try await performFullSync()
        }

        _isSyncingInternal = true
        _syncProgressInternal = 0
        syncStatusMessage = "开始增量同步..."

        defer {
            _isSyncingInternal = false
            print("[SYNC] 增量同步结束，isSyncing设置为false")
        }

        var result = SyncResult()

        do {
            // 优先尝试轻量级增量同步
            print("[SYNC] 优先尝试轻量级增量同步")
            do {
                result = try await performLightweightIncrementalSync()
                print("[SYNC] 轻量级增量同步成功")
                return result
            } catch {
                print("[SYNC] 轻量级增量同步失败，回退到网页版增量同步: \(error)")
            }

            // 如果轻量级同步失败，尝试网页版增量同步
            print("[SYNC] 尝试网页版增量同步")
            do {
                result = try await performWebIncrementalSync()
                print("[SYNC] 网页版增量同步成功")
                return result
            } catch {
                print("[SYNC] 网页版增量同步失败，回退到旧API增量同步: \(error)")
            }

            // 如果网页版增量同步也失败，使用旧API增量同步
            print("[SYNC] 使用旧API增量同步")

            // 使用 SyncStateManager 获取 syncTag（需求 1.1）
            let lastSyncTag = await syncStateManager.getCurrentSyncTag()
            print("[SYNC] 从 SyncStateManager 获取 syncTag: \(lastSyncTag)")

            syncStatusMessage = "获取自上次同步以来的更改..."

            let syncResponse = try await miNoteService.fetchPage(syncTag: lastSyncTag)
            print("[SYNC] 旧API调用成功")

            // 解析笔记和文件夹
            let notes = miNoteService.parseNotes(from: syncResponse)
            let folders = miNoteService.parseFolders(from: syncResponse)

            var syncedNotes = 0
            var cloudNoteIds = Set<String>() // 收集云端笔记ID
            var cloudFolderIds = Set<String>() // 收集云端文件夹ID

            // 收集云端笔记和文件夹ID
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

            // 更新同步状态
            // 从响应中提取新的syncTag
            if let newSyncTag = extractSyncTags(from: syncResponse) {
                print("[SYNC] 提取到新的 syncTag: \(newSyncTag)")

                // 检查是否有待上传笔记（需求 2.1, 2.2, 2.3）
                let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
                print("[SYNC] 是否有待上传笔记: \(hasPendingNotes)")

                // 使用 SyncStateManager 暂存 syncTag
                try await syncStateManager.stageSyncTag(newSyncTag, hasPendingNotes: hasPendingNotes)
                print("[SYNC] syncTag 已通过 SyncStateManager 处理")
            }

            // 移除直接更新 LocalStorageService 的代码（已由 SyncStateManager 处理）
            // 移除内部缓存更新（不再需要）

            // 处理只有本地存在但云端不存在的笔记和文件夹
            syncStatusMessage = "检查本地独有的笔记和文件夹..."
            try await syncLocalOnlyItems(cloudNoteIds: cloudNoteIds, cloudFolderIds: cloudFolderIds)

            _syncProgressInternal = 1.0
            syncStatusMessage = "增量同步完成"

            result.totalNotes = notes.count
            result.syncedNotes = syncedNotes
            result.lastSyncTime = Date()

            // 显示同步状态信息
            print("[SYNC] 🔍 增量同步完成，显示同步状态信息:")
            if let savedStatus = localStorage.loadSyncStatus() {
                print("[SYNC]   - lastSyncTime: \(savedStatus.lastSyncTime?.description ?? "nil")")
                print("[SYNC]   - syncTag: \(savedStatus.syncTag ?? "nil")")
            } else {
                print("[SYNC]   ⚠️ 无法加载同步状态")
            }
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
        print("[SYNC] 开始执行网页版增量同步")

        guard miNoteService.isAuthenticated() else {
            print("[SYNC] 错误：未认证")
            throw SyncError.notAuthenticated
        }

        // 加载现有的同步状态
        guard let syncStatus = localStorage.loadSyncStatus() else {
            // 如果没有同步状态，执行完整同步（不检查isSyncing标志，因为已经由performIncrementalSync处理）
            print("[SYNC] 未找到同步记录，执行完整同步...")
            return try await performFullSync(checkIsSyncing: false)
        }

        _syncProgressInternal = 0
        syncStatusMessage = "开始网页版增量同步..."

        var result = SyncResult()

        do {
            // 使用 SyncStateManager 获取 syncTag（需求 1.1）
            let lastSyncTag = await syncStateManager.getCurrentSyncTag()
            print("[SYNC] 从 SyncStateManager 获取 syncTag: \(lastSyncTag)")

            syncStatusMessage = "获取自上次同步以来的更改..."

            // 使用网页版增量同步API
            let syncResponse = try await miNoteService.syncFull(syncTag: lastSyncTag)
            print("[SYNC] 网页版增量同步API调用成功")

            // 解析笔记和文件夹
            let notes = miNoteService.parseNotes(from: syncResponse)
            let folders = miNoteService.parseFolders(from: syncResponse)

            var syncedNotes = 0
            var cloudNoteIds = Set<String>() // 收集云端笔记ID
            var cloudFolderIds = Set<String>() // 收集云端文件夹ID

            // 收集云端笔记和文件夹ID
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

            // 更新同步状态
            // 从响应中提取新的syncTag
            if let newSyncTag = extractSyncTags(from: syncResponse) {
                print("[SYNC] 提取到新的 syncTag: \(newSyncTag)")

                // 检查是否有待上传笔记（需求 2.1, 2.2, 2.3）
                let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
                print("[SYNC] 是否有待上传笔记: \(hasPendingNotes)")

                // 使用 SyncStateManager 暂存 syncTag
                try await syncStateManager.stageSyncTag(newSyncTag, hasPendingNotes: hasPendingNotes)
                print("[SYNC] syncTag 已通过 SyncStateManager 处理")
            }

            // 移除直接更新 LocalStorageService 的代码（已由 SyncStateManager 处理）
            // 移除内部缓存更新（不再需要）

            // 处理只有本地存在但云端不存在的笔记和文件夹
            syncStatusMessage = "检查本地独有的笔记和文件夹..."
            try await syncLocalOnlyItems(cloudNoteIds: cloudNoteIds, cloudFolderIds: cloudFolderIds)

            _syncProgressInternal = 1.0
            syncStatusMessage = "网页版增量同步完成"

            result.totalNotes = notes.count
            result.syncedNotes = syncedNotes
            result.lastSyncTime = Date()

            // 显示同步状态信息
            print("[SYNC] 🔍 网页版增量同步完成，显示同步状态信息:")
            if let savedStatus = localStorage.loadSyncStatus() {
                print("[SYNC]   - lastSyncTime: \(savedStatus.lastSyncTime?.description ?? "nil")")
                print("[SYNC]   - syncTag: \(savedStatus.syncTag ?? "nil")")
            } else {
                print("[SYNC]   ⚠️ 无法加载同步状态")
            }
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
        print("[SYNC] 开始执行轻量级增量同步")

        guard miNoteService.isAuthenticated() else {
            print("[SYNC] 错误：未认证")
            throw SyncError.notAuthenticated
        }

        // 加载现有的同步状态
        guard let syncStatus = localStorage.loadSyncStatus() else {
            // 如果没有同步状态，执行完整同步（不检查isSyncing标志，因为已经由performIncrementalSync处理）
            print("[SYNC] 未找到同步记录，执行完整同步...")
            return try await performFullSync(checkIsSyncing: false)
        }

        _syncProgressInternal = 0
        syncStatusMessage = "开始轻量级增量同步..."

        var result = SyncResult()

        do {
            // 使用 SyncStateManager 获取 syncTag（需求 1.1）
            let lastSyncTag = await syncStateManager.getCurrentSyncTag()
            print("[SYNC] 从 SyncStateManager 获取 syncTag: \(lastSyncTag)")

            syncStatusMessage = "获取自上次同步以来的更改..."

            // 使用轻量级增量同步API
            let syncResponse = try await miNoteService.syncFull(syncTag: lastSyncTag)
            print("[SYNC] 轻量级增量同步API调用成功")

            // 解析响应，获取有修改的条目
            let (modifiedNotes, modifiedFolders, newSyncTag) = try parseLightweightSyncResponse(syncResponse)

            print("[SYNC] 找到 \(modifiedNotes.count) 个有修改的笔记，\(modifiedFolders.count) 个有修改的文件夹")

            var syncedNotes = 0
            var cloudNoteIds = Set<String>() // 收集云端笔记ID
            var cloudFolderIds = Set<String>() // 收集云端文件夹ID

            // 收集云端笔记和文件夹ID
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

            // 更新同步状态
            if !newSyncTag.isEmpty {
                print("[SYNC] 提取到新的 syncTag: \(newSyncTag)")

                // 检查是否有待上传笔记（需求 2.1, 2.2, 2.3）
                let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
                print("[SYNC] 是否有待上传笔记: \(hasPendingNotes)")

                // 使用 SyncStateManager 暂存 syncTag
                try await syncStateManager.stageSyncTag(newSyncTag, hasPendingNotes: hasPendingNotes)
                print("[SYNC] syncTag 已通过 SyncStateManager 处理")
            }

            // 移除直接更新 LocalStorageService 的代码（已由 SyncStateManager 处理）
            // 移除内部缓存更新（不再需要）

            // 注意：轻量级同步不调用 syncLocalOnlyItems，因为它只返回有修改的笔记
            // 未修改的笔记应该保持不变，删除操作通过笔记的"status"字段处理

            _syncProgressInternal = 1.0
            syncStatusMessage = "轻量级增量同步完成"

            result.totalNotes = modifiedNotes.count
            result.syncedNotes = syncedNotes
            result.lastSyncTime = Date()

            // 显示同步状态信息
            print("[SYNC] 🔍 轻量级增量同步完成，显示同步状态信息:")
            if let savedStatus = localStorage.loadSyncStatus() {
                print("[SYNC]   - lastSyncTime: \(savedStatus.lastSyncTime?.description ?? "nil")")
                print("[SYNC]   - syncTag: \(savedStatus.syncTag ?? "nil")")
            } else {
                print("[SYNC]   ⚠️ 无法加载同步状态")
            }
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

        print("[SYNC] 🔍 开始提取syncTag，响应键: \(response.keys)")

        // 尝试旧API格式：直接返回syncTag字段
        if let oldSyncTag = response["syncTag"] as? String {
            syncTag = oldSyncTag
            print("[SYNC] ✅ 从旧API格式提取syncTag: \(oldSyncTag)")
        }

        // 尝试完整同步API格式：data.syncTag
        if let data = response["data"] as? [String: Any] {
            print("[SYNC] 🔍 找到data字段，键: \(data.keys)")

            // 检查 data.syncTag
            if let dataSyncTag = data["syncTag"] as? String {
                syncTag = dataSyncTag
                print("[SYNC] ✅ 从data.syncTag提取syncTag: \(dataSyncTag)")
            }

            // 尝试网页版API格式：note_view.data.syncTag
            if let noteView = data["note_view"] as? [String: Any] {
                print("[SYNC] 🔍 找到note_view字段，键: \(noteView.keys)")
                if let noteViewData = noteView["data"] as? [String: Any] {
                    print("[SYNC] 🔍 找到note_view.data字段，键: \(noteViewData.keys)")
                    if let webSyncTag = noteViewData["syncTag"] as? String {
                        syncTag = webSyncTag
                        print("[SYNC] ✅ 从网页版API格式提取syncTag: \(webSyncTag)")
                    }
                }
            }
        }

        // 尝试另一种可能的格式：顶层note_view.data.syncTag
        if let noteView = response["note_view"] as? [String: Any] {
            print("[SYNC] 🔍 找到顶层note_view字段，键: \(noteView.keys)")
            if let noteViewData = noteView["data"] as? [String: Any] {
                print("[SYNC] 🔍 找到顶层note_view.data字段，键: \(noteViewData.keys)")
                if let webSyncTag = noteViewData["syncTag"] as? String {
                    syncTag = webSyncTag
                    print("[SYNC] ✅ 从另一种格式提取syncTag: \(webSyncTag)")
                }
            }
        }

        if syncTag == nil {
            print("[SYNC] ⚠️ 警告：无法从响应中提取syncTag")
            // 打印响应结构以便调试
            print("[SYNC] 🔍 响应结构: \(response)")
        } else {
            print("[SYNC] ✅ 提取syncTag成功: \(syncTag!)")
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
                    // 1.2 云端较新，拉取云端覆盖本地
                    try localStorage.saveFolders([cloudFolder])
                    print("[SYNC] 文件夹云端较新，已更新: \(cloudFolder.name)")
                } else if localFolder.createdAt > cloudFolder.createdAt {
                    // 1.1 本地较新，上传本地到云端（通过统一操作队列）
                    // 这里需要检查是否有重命名操作
                    let hasRenameOp = pendingOps.contains { operation in
                        operation.type == .folderRename && operation.noteId == localFolder.id
                    }
                    if !hasRenameOp {
                        // 创建更新操作
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
                        print("[SYNC] 文件夹本地较新，已添加到上传队列: \(localFolder.name)")
                    }
                } else {
                    // 1.3 时间一致，考虑内容（这里简单比较名称）
                    if cloudFolder.name != localFolder.name {
                        // 名称不同，使用云端版本
                        try localStorage.saveFolders([cloudFolder])
                        print("[SYNC] 文件夹名称不同，已更新: \(cloudFolder.name)")
                    }
                }
            } else {
                // 情况2：只有云端存在，本地不存在
                // 2.1 检查离线删除队列
                let hasDeleteOp = pendingOps.contains { operation in
                    operation.type == .folderDelete && operation.noteId == cloudFolder.id
                }
                if hasDeleteOp {
                    // 在删除队列中，删除云端文件夹
                    if let tag = cloudFolder.rawData?["tag"] as? String {
                        _ = try await miNoteService.deleteFolder(folderId: cloudFolder.id, tag: tag, purge: false)
                        print("[SYNC] 文件夹在删除队列中，已删除云端: \(cloudFolder.name)")
                    }
                } else {
                    // 2.2 不在删除队列，拉取到本地
                    try localStorage.saveFolders([cloudFolder])
                    print("[SYNC] 新文件夹，已拉取到本地: \(cloudFolder.name)")
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

        // 🛡️ 同步保护检查：使用 SyncGuard 检查笔记是否应该被跳过
        // 包括：临时 ID 笔记、正在编辑、待上传等情况
        let shouldSkip = await syncGuard.shouldSkipSync(
            noteId: cloudNote.id,
            cloudTimestamp: cloudNote.updatedAt
        )
        if shouldSkip {
            // 获取跳过原因用于日志
            if let skipReason = await syncGuard.getSkipReason(
                noteId: cloudNote.id,
                cloudTimestamp: cloudNote.updatedAt
            ) {
                print("[SYNC] 🛡️ 同步保护：跳过笔记 \(cloudNote.id.prefix(8))... - \(skipReason.description)")
            }
            result.status = .skipped
            result.message = "同步保护：笔记正在编辑、待上传或使用临时 ID"
            result.success = true
            return result
        }

        if let localNote = try localStorage.loadNote(noteId: cloudNote.id) {
            // 情况1：云端和本地都存在
            if localNote.updatedAt > cloudNote.updatedAt {
                // 1.1 本地较新，上传本地到云端
                let hasUpdateOp = pendingOps.contains { operation in
                    operation.type == .cloudUpload && operation.noteId == localNote.id
                }
                if !hasUpdateOp {
                    // 创建更新操作
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
                    print("[SYNC] 笔记本地较新，已添加到上传队列: \(localNote.title)")
                }
                result.status = .skipped
                result.message = "本地较新，等待上传"
                result.success = true
            } else if cloudNote.updatedAt > localNote.updatedAt {
                // 1.2 云端较新，拉取云端覆盖本地
                let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                var updatedNote = cloudNote
                updatedNote.updateContent(from: noteDetails)
                print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")

                // 下载图片，并获取更新后的 setting.data
                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                    // 更新笔记的 rawData 中的 setting.data
                    var rawData = updatedNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    updatedNote.rawData = rawData
                    print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                }

                print("[SYNC] 保存笔记: \(updatedNote.id)")
                try localStorage.saveNote(updatedNote)
                result.status = .updated
                result.message = "已从云端更新"
                result.success = true
                print("[SYNC] 笔记云端较新，已更新: \(cloudNote.title)")
            } else {
                // 1.3 时间一致，比较内容
                if localNote.primaryXMLContent != cloudNote.primaryXMLContent {
                    // 内容不同，获取详情并更新
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                    var updatedNote = cloudNote
                    updatedNote.updateContent(from: noteDetails)
                    print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")

                    // 下载图片，并获取更新后的 setting.data
                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                        // 更新笔记的 rawData 中的 setting.data
                        var rawData = updatedNote.rawData ?? [:]
                        var setting = rawData["setting"] as? [String: Any] ?? [:]
                        setting["data"] = updatedSettingData
                        rawData["setting"] = setting
                        updatedNote.rawData = rawData
                        print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                    }

                    print("[SYNC] 保存笔记: \(updatedNote.id)")
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
            // 情况2：只有云端存在，本地不存在
            // 2.1 检查离线删除队列
            let hasDeleteOp: Bool = pendingOps.contains { operation in
                operation.type == .cloudDelete && operation.noteId == cloudNote.id
            }
            if hasDeleteOp {
                // 在删除队列中，删除云端笔记
                if let tag = cloudNote.rawData?["tag"] as? String {
                    _ = try await miNoteService.deleteNote(noteId: cloudNote.id, tag: tag, purge: false)
                    result.status = .skipped
                    result.message = "在删除队列中，已删除云端"
                    result.success = true
                    print("[SYNC] 笔记在删除队列中，已删除云端: \(cloudNote.title)")
                }
            } else {
                // 2.2 不在删除队列，拉取到本地
                // 再次检查本地是否已存在（防止竞态条件）
                if let existingNote = try? localStorage.loadNote(noteId: cloudNote.id) {
                    // 笔记已存在，使用更新逻辑而不是创建逻辑
                    if existingNote.updatedAt < cloudNote.updatedAt {
                        // 云端较新，更新本地
                        let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                        var updatedNote = cloudNote
                        updatedNote.updateContent(from: noteDetails)
                        print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")

                        // 下载图片，并获取更新后的 setting.data
                        if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                            // 更新笔记的 rawData 中的 setting.data
                            var rawData = updatedNote.rawData ?? [:]
                            var setting = rawData["setting"] as? [String: Any] ?? [:]
                            setting["data"] = updatedSettingData
                            rawData["setting"] = setting
                            updatedNote.rawData = rawData
                            print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                        }

                        print("[SYNC] 保存笔记: \(updatedNote.id)")
                        try localStorage.saveNote(updatedNote)
                        result.status = .updated
                        result.message = "已从云端更新"
                        result.success = true
                        print("[SYNC] 笔记已存在但云端较新，已更新: \(cloudNote.title)")
                    } else {
                        // 本地较新或相同，跳过
                        result.status = .skipped
                        result.message = "本地已存在且较新或相同"
                        result.success = true
                        print("[SYNC] 笔记已存在且本地较新或相同，跳过: \(cloudNote.title)")
                    }
                } else {
                    // 确实不存在，拉取到本地
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                    var updatedNote = cloudNote
                    updatedNote.updateContent(from: noteDetails)
                    print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")

                    // 下载图片，并获取更新后的 setting.data
                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                        // 更新笔记的 rawData 中的 setting.data
                        var rawData = updatedNote.rawData ?? [:]
                        var setting = rawData["setting"] as? [String: Any] ?? [:]
                        setting["data"] = updatedSettingData
                        rawData["setting"] = setting
                        updatedNote.rawData = rawData
                        print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                    }

                    print("[SYNC] 保存笔记: \(updatedNote.id)")
                    try localStorage.saveNote(updatedNote)
                    result.status = .created
                    result.message = "已从云端拉取"
                    result.success = true
                    print("[SYNC] 新笔记，已拉取到本地: \(cloudNote.title)")
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
            // 🛡️ 跳过临时 ID 笔记（离线创建的笔记）
            // 临时 ID 笔记不会出现在云端，需要等待 noteCreate 操作完成后才能同步
            if NoteOperation.isTemporaryId(localNote.id) {
                print("[SYNC] 🛡️ 跳过临时 ID 笔记: \(localNote.id.prefix(8))... - \(localNote.title)")
                continue
            }

            if !cloudNoteIds.contains(localNote.id) {
                // 情况3：只有本地存在，云端不存在
                // 3.1 检查离线新建队列
                let hasCreateOp: Bool = pendingOps.contains { operation in
                    operation.type == .noteCreate && operation.noteId == localNote.id
                }
                if hasCreateOp {
                    // 在新建队列中，上传到云端
                    // 注意：上传后可能会返回新的ID，但此时增量同步已经完成，不会导致重复
                    // 因为下次同步时会正确处理ID变更
                    do {
                        let response = try await miNoteService.createNote(
                            title: localNote.title,
                            content: localNote.content,
                            folderId: localNote.folderId
                        )

                        // 如果服务器返回了新的ID，更新本地笔记
                        if let code = response["code"] as? Int, code == 0,
                           let data = response["data"] as? [String: Any],
                           let entry = data["entry"] as? [String: Any],
                           let serverNoteId = entry["id"] as? String,
                           serverNoteId != localNote.id
                        {
                            // 服务器返回了新的ID，需要更新本地笔记
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

                            // 先保存新笔记，再删除旧笔记
                            try localStorage.saveNote(updatedNote)
                            try localStorage.deleteNote(noteId: localNote.id)
                            print("[SYNC] 笔记上传后ID变更: \(localNote.id) -> \(serverNoteId)")
                        } else {
                            print("[SYNC] 笔记在新建队列中，已上传到云端: \(localNote.title)")
                        }
                    } catch {
                        print("[SYNC] 上传笔记失败: \(error.localizedDescription)")
                        // 继续处理，不中断同步
                    }
                } else {
                    // 3.2 不在新建队列，删除本地笔记
                    // 但需要检查是否有待处理的更新操作（可能笔记正在上传中）
                    let hasUpdateOp: Bool = pendingOps.contains { operation in
                        operation.type == .cloudUpload && operation.noteId == localNote.id
                    }
                    if !hasUpdateOp {
                        // 没有待处理的操作，删除本地笔记
                        try localStorage.deleteNote(noteId: localNote.id)
                        print("[SYNC] 笔记不在新建队列，已删除本地: \(localNote.title)")
                    } else {
                        print("[SYNC] 笔记有待处理的更新操作，保留本地: \(localNote.title)")
                    }
                }
            }
        }

        // 处理本地独有的文件夹
        for localFolder in localFolders {
            if !localFolder.isSystem,
               localFolder.id != "0",
               localFolder.id != "starred",
               !cloudFolderIds.contains(localFolder.id)
            {
                // 情况3：只有本地存在，云端不存在
                // 3.1 检查离线新建队列
                let hasCreateOp: Bool = pendingOps.contains { operation in
                    operation.type == .folderCreate && operation.noteId == localFolder.id
                }
                if hasCreateOp {
                    // 在新建队列中，上传到云端
                    let response = try await miNoteService.createFolder(name: localFolder.name)

                    // 解析响应并获取服务器返回的文件夹ID
                    if let code = response["code"] as? Int, code == 0,
                       let data = response["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any]
                    {

                        // 处理 ID（可能是 String 或 Int）
                        var serverFolderId: String?
                        if let idString = entry["id"] as? String {
                            serverFolderId = idString
                        } else if let idInt = entry["id"] as? Int {
                            serverFolderId = String(idInt)
                        }

                        if let folderId = serverFolderId, folderId != localFolder.id {
                            // ID不同，需要更新
                            // 1. 更新所有使用旧文件夹ID的笔记
                            try DatabaseService.shared.updateNotesFolderId(oldFolderId: localFolder.id, newFolderId: folderId)

                            // 2. 删除旧的文件夹记录
                            try DatabaseService.shared.deleteFolder(folderId: localFolder.id)

                            // 3. 创建新文件夹并保存
                            let updatedFolder = Folder(
                                id: folderId,
                                name: entry["subject"] as? String ?? localFolder.name,
                                count: 0,
                                isSystem: false,
                                createdAt: Date()
                            )
                            try localStorage.saveFolders([updatedFolder])

                            print("[SYNC] ✅ 文件夹ID已更新: \(localFolder.id) -> \(folderId), 并删除了旧文件夹记录")
                        } else {
                            print("[SYNC] 文件夹在新建队列中，已上传到云端: \(localFolder.name), ID: \(serverFolderId ?? localFolder.id)")
                        }
                    } else {
                        print("[SYNC] ⚠️ 文件夹在新建队列中，已上传到云端，但服务器返回无效响应: \(localFolder.name)")
                    }
                } else {
                    // 3.2 不在新建队列，删除本地文件夹
                    try DatabaseService.shared.deleteFolder(folderId: localFolder.id)
                    print("[SYNC] 文件夹不在新建队列，已删除本地: \(localFolder.name)")
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
        print("[SYNC] 开始处理笔记: \(note.id) - \(note.title), 完整同步模式: \(isFullSync)")
        var result = NoteSyncResult(noteId: note.id, noteTitle: note.title)

        do {
            // 如果是完整同步模式，直接下载并替换，不进行任何比较
            if isFullSync {
                print("[SYNC] 完整同步模式：直接下载并替换笔记: \(note.id)")
                // 获取笔记详情（包含完整内容）
                syncStatusMessage = "下载笔记: \(note.title)"
                print("[SYNC] 获取笔记详情: \(note.id)")
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    print("[SYNC] 获取笔记详情成功: \(note.id)")
                } catch let error as MiNoteError {
                    print("[SYNC] 获取笔记详情失败 (MiNoteError): \(error)")
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
                    print("[SYNC] 获取笔记详情失败: \(error)")
                    throw SyncError.networkError(error)
                }

                // 更新笔记内容
                var updatedNote = note
                updatedNote.updateContent(from: noteDetails)
                print("[SYNC] 更新笔记内容完成: \(note.id), 内容长度: \(updatedNote.content.count)")

                // 处理图片：下载笔记中的图片，并获取更新后的 setting.data
                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    // 更新笔记的 rawData 中的 setting.data
                    var rawData = updatedNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    updatedNote.rawData = rawData
                    print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                }

                // 保存到本地（替换现有文件）
                print("[SYNC] 保存笔记到本地: \(updatedNote.id)")
                try localStorage.saveNote(updatedNote)
                print("[SYNC] 保存笔记到本地: \(note.id)")

                result.status = localStorage.noteExistsLocally(noteId: note.id) ? .updated : .created
                result.message = result.status == .updated ? "笔记已替换" : "笔记已下载"
                result.success = true
                return result
            }

            // 检查笔记是否已存在本地
            let existsLocally = localStorage.noteExistsLocally(noteId: note.id)
            print("[SYNC] 笔记 \(note.id) 本地存在: \(existsLocally)")

            if existsLocally {
                // 获取本地笔记对象（使用笔记对象中的updatedAt，而不是文件系统时间）
                if let localNote = try? localStorage.loadNote(noteId: note.id) {
                    let localModDate = localNote.updatedAt
                    print("[SYNC] 本地修改时间: \(localModDate), 云端修改时间: \(note.updatedAt)")

                    // 比较修改时间（允许2秒的误差，因为时间戳可能有精度差异和网络延迟）
                    let timeDifference = abs(note.updatedAt.timeIntervalSince(localModDate))

                    // 如果云端时间早于本地时间，且差异超过2秒，说明本地版本较新
                    if note.updatedAt < localModDate, timeDifference > 2.0 {
                        // 本地版本明显较新（差异超过2秒），跳过（本地修改尚未上传）
                        print("[SYNC] 本地版本较新，跳过: \(note.id) (本地: \(localModDate), 云端: \(note.updatedAt), 差异: \(timeDifference)秒)")
                        result.status = .skipped
                        result.message = "本地版本较新，跳过同步"
                        result.success = true
                        return result
                    }

                    // 如果时间戳接近（在2秒误差内），需要获取完整内容进行比较
                    if timeDifference < 2.0 {
                        // 时间相同（在2秒误差内），需要获取完整内容检查是否真的相同
                        print("[SYNC] 时间戳接近（差异: \(timeDifference)秒），获取完整内容进行比较: \(note.id)")

                        // 获取云端笔记的完整内容
                        do {
                            let noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                            var cloudNote = note
                            cloudNote.updateContent(from: noteDetails)
                            print("[SYNC] 更新笔记内容，content长度: \(cloudNote.content.count)")

                            // 比较完整内容
                            let localContent = localNote.primaryXMLContent
                            let cloudContent = cloudNote.primaryXMLContent

                            if localContent == cloudContent {
                                // 内容相同，跳过
                                print("[SYNC] 笔记未修改（时间和内容都相同），跳过: \(note.id)")
                                result.status = .skipped
                                result.message = "笔记未修改"
                                result.success = true
                                return result
                            } else {
                                // 内容不同，需要更新
                                print("[SYNC] 时间戳接近但内容不同，需要更新: \(note.id)")
                                // 处理图片：下载笔记中的图片，并获取更新后的 setting.data
                                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                                    // 更新笔记的 rawData 中的 setting.data
                                    var rawData = cloudNote.rawData ?? [:]
                                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                                    setting["data"] = updatedSettingData
                                    rawData["setting"] = setting
                                    cloudNote.rawData = rawData
                                    print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                                }

                                // 使用已获取的 noteDetails 继续更新流程
                                var updatedNote = cloudNote
                                updatedNote.updateContent(from: noteDetails)
                                print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")
                                print("[SYNC] 保存笔记到本地: \(updatedNote.id)")
                                try localStorage.saveNote(updatedNote)
                                print("[SYNC] 保存笔记到本地: \(note.id)")
                                result.status = .updated
                                result.message = "笔记已更新"
                                result.success = true
                                return result
                            }
                        } catch {
                            print("[SYNC] 获取笔记详情失败，继续使用原有逻辑: \(error)")
                            // 如果获取详情失败，继续使用原有逻辑（会在后面获取详情）
                        }
                    }

                    // 云端版本较新，继续更新（会在后面获取详情并更新）
                    print("[SYNC] 需要更新笔记: \(note.id)")
                } else {
                    print("[SYNC] 无法加载本地笔记，继续同步")
                }

                // 获取笔记详情（包含完整内容）
                syncStatusMessage = "获取笔记详情: \(note.title)"
                print("[SYNC] 获取笔记详情: \(note.id)")
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    print("[SYNC] 获取笔记详情成功: \(note.id)")
                    print("[SYNC] 笔记详情响应结构: \(noteDetails.keys)")

                    // 调试：打印响应结构
                    if let data = noteDetails["data"] as? [String: Any] {
                        print("[SYNC] data字段存在，包含: \(data.keys)")
                        if let entry = data["entry"] as? [String: Any] {
                            print("[SYNC] entry字段存在，包含: \(entry.keys)")
                            if let content = entry["content"] as? String {
                                print("[SYNC] 找到content字段，长度: \(content.count)")
                            } else {
                                print("[SYNC] entry中没有content字段")
                            }
                        } else {
                            print("[SYNC] data中没有entry字段")
                        }
                    } else {
                        print("[SYNC] 响应中没有data字段")
                        // 尝试直接查找content
                        if let content = noteDetails["content"] as? String {
                            print("[SYNC] 直接找到content字段，长度: \(content.count)")
                        }
                    }
                } catch let error as MiNoteError {
                    print("[SYNC] 获取笔记详情失败 (MiNoteError): \(error)")
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
                    print("[SYNC] 获取笔记详情失败: \(error)")
                    throw SyncError.networkError(error)
                }

                // 更新笔记内容
                var updatedNote = note
                updatedNote.updateContent(from: noteDetails)
                print("[SYNC] 更新笔记内容完成: \(note.id), 内容长度: \(updatedNote.content.count)")

                // 处理图片：下载笔记中的图片，并获取更新后的 setting.data
                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    // 更新笔记的 rawData 中的 setting.data
                    var rawData = updatedNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    updatedNote.rawData = rawData
                    print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                }

                // 调试：检查更新后的内容
                if updatedNote.content.isEmpty {
                    print("[SYNC] 警告：更新后内容仍然为空！")
                    print("[SYNC] 原始响应: \(noteDetails)")
                }

                // 保存到本地
                print("[SYNC] 保存笔记到本地: \(updatedNote.id)")
                try localStorage.saveNote(updatedNote)
                print("[SYNC] 保存笔记到本地: \(note.id)")

                result.status = .updated
                result.message = "笔记已更新"
            } else {
                // 新笔记，获取详情并保存
                syncStatusMessage = "下载新笔记: \(note.title)"
                print("[SYNC] 下载新笔记: \(note.id)")
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    print("[SYNC] 获取新笔记详情成功: \(note.id)")
                    print("[SYNC] 新笔记详情响应结构: \(noteDetails.keys)")

                    // 调试：打印响应结构
                    if let data = noteDetails["data"] as? [String: Any] {
                        print("[SYNC] data字段存在，包含: \(data.keys)")
                        if let entry = data["entry"] as? [String: Any] {
                            print("[SYNC] entry字段存在，包含: \(entry.keys)")
                            if let content = entry["content"] as? String {
                                print("[SYNC] 找到content字段，长度: \(content.count)")
                            } else {
                                print("[SYNC] entry中没有content字段")
                            }
                        } else {
                            print("[SYNC] data中没有entry字段")
                        }
                    } else {
                        print("[SYNC] 响应中没有data字段")
                        // 尝试直接查找content
                        if let content = noteDetails["content"] as? String {
                            print("[SYNC] 直接找到content字段，长度: \(content.count)")
                        }
                    }
                } catch let error as MiNoteError {
                    print("[SYNC] 获取新笔记详情失败 (MiNoteError): \(error)")
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
                    print("[SYNC] 获取新笔记详情失败: \(error)")
                    throw SyncError.networkError(error)
                }

                // 更新笔记内容
                var newNote = note
                newNote.updateContent(from: noteDetails)
                print("[SYNC] 更新新笔记内容完成: \(note.id), 内容长度: \(newNote.content.count)")

                // 处理图片：下载笔记中的图片，并获取更新后的 setting.data
                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    // 更新笔记的 rawData 中的 setting.data
                    var rawData = newNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    newNote.rawData = rawData
                    print("[SYNC] 更新新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                }

                // 调试：检查更新后的内容
                if newNote.content.isEmpty {
                    print("[SYNC] 警告：新笔记更新后内容仍然为空！")
                    print("[SYNC] 原始响应: \(noteDetails)")
                }

                // 保存到本地
                print("[SYNC] 保存新笔记到本地: \(newNote.id)")
                try localStorage.saveNote(newNote)
                print("[SYNC] 保存新笔记到本地: \(note.id)")

                result.status = .created
                result.message = "新笔记已下载"
            }

            result.success = true
            print("[SYNC] 笔记处理成功: \(note.id)")
        } catch let error as SyncError {
            // 如果是SyncError，直接重新抛出
            print("[SYNC] SyncError: \(error)")
            throw error
        } catch {
            print("[SYNC] 其他错误: \(error)")
            result.success = false
            result.status = .failed
            result.message = "处理失败: \(error.localizedDescription)"
        }

        return result
    }

    // MARK: - 处理文件夹

    private func processFolder(_ folder: Folder) async throws {
        // 创建文件夹目录
        do {
            _ = try localStorage.createFolder(folder.name)
        } catch {
            print("创建文件夹失败 \(folder.name): \(error)")
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
        print("[SYNC] 开始下载笔记附件: \(noteId), forceRedownload: \(forceRedownload)")
        print("[SYNC] noteDetails 键: \(noteDetails.keys)")

        // 提取 entry 对象
        var entry: [String: Any]?
        if let data = noteDetails["data"] as? [String: Any] {
            print("[SYNC] 找到 data 字段，包含键: \(Array(data.keys))")
            if let dataEntry = data["entry"] as? [String: Any] {
                entry = dataEntry
                print("[SYNC] 从 data.entry 提取到 entry，包含键: \(Array(dataEntry.keys))")
            }
        } else if let directEntry = noteDetails["entry"] as? [String: Any] {
            entry = directEntry
            print("[SYNC] 从顶层 entry 提取到 entry，包含键: \(Array(directEntry.keys))")
        } else if noteDetails["id"] != nil || noteDetails["content"] != nil {
            entry = noteDetails
            print("[SYNC] 使用 noteDetails 本身作为 entry，包含键: \(Array(noteDetails.keys))")
        }

        guard let entry else {
            print("[SYNC] 无法提取 entry，跳过附件下载: \(noteId)")
            return nil
        }

        // 第一步：处理 setting.data 中的图片（如果存在）
        var settingData: [[String: Any]] = []

        if let setting = entry["setting"] as? [String: Any] {
            print("[SYNC] 找到 setting 字段，包含键: \(setting.keys)")

            if let existingData = setting["data"] as? [[String: Any]] {
                settingData = existingData
                print("[SYNC] 找到 \(settingData.count) 个 setting.data 附件条目")
            } else {
                print("[SYNC] setting 中没有 data 字段或 data 不是数组")
            }
        } else {
            print("[SYNC] entry 中没有 setting 字段")
        }

        // 使用简单的异步循环处理 setting.data 中的附件
        for index in 0 ..< settingData.count {
            let attachmentData = settingData[index]
            print("[SYNC] 处理 setting.data 附件条目 \(index + 1)/\(settingData.count): \(attachmentData.keys)")

            guard let fileId = attachmentData["fileId"] as? String else {
                print("[SYNC] 附件条目 \(index + 1) 没有 fileId，跳过")
                continue
            }

            guard let mimeType = attachmentData["mimeType"] as? String else {
                print("[SYNC] 附件条目 \(index + 1) 没有 mimeType，跳过")
                continue
            }

            // 根据 MIME 类型处理不同类型的附件
            if mimeType.hasPrefix("image/") {
                // 处理图片
                let fileType = String(mimeType.dropFirst("image/".count))
                print("[SYNC] 找到图片: fileId=\(fileId), fileType=\(fileType)")

                // 如果不是强制重新下载,检查图片是否已存在且有效
                if !forceRedownload {
                    print("[SYNC] 检查图片是否存在: \(fileId).\(fileType)")
                    if localStorage.validateImage(fileId: fileId, fileType: fileType) {
                        print("[SYNC] ✅ 图片已存在且有效，跳过下载: \(fileId).\(fileType)")
                        var updatedData = attachmentData
                        updatedData["localExists"] = true
                        settingData[index] = updatedData
                        continue
                    } else {
                        print("[SYNC] ⚠️ 图片不存在或无效，需要下载: \(fileId).\(fileType)")
                    }
                } else {
                    print("[SYNC] ⚠️ 强制重新下载图片: \(fileId).\(fileType)")
                }

                // 下载图片(带重试)
                do {
                    print("[SYNC] 开始下载图片: \(fileId).\(fileType)")
                    let imageData = try await downloadImageWithRetry(fileId: fileId, type: "note_img")
                    print("[SYNC] 图片下载完成，大小: \(imageData.count) 字节")
                    try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)
                    print("[SYNC] 图片保存成功: \(fileId).\(fileType)")

                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    updatedData["downloaded"] = true
                    settingData[index] = updatedData
                } catch {
                    print("[SYNC] 图片下载失败: \(fileId).\(fileType), 错误: \(error.localizedDescription)")
                }
            } else if mimeType.hasPrefix("audio/") {
                // 处理音频文件
                print("[SYNC] 找到音频: fileId=\(fileId), mimeType=\(mimeType)")

                // 检查音频是否已缓存
                if AudioCacheService.shared.isCached(fileId: fileId) {
                    print("[SYNC] 音频已缓存，跳过下载: \(fileId)")
                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    settingData[index] = updatedData
                    continue
                }

                // 下载音频文件
                do {
                    print("[SYNC] 开始下载音频: \(fileId)")
                    let audioData = try await miNoteService.downloadAudio(fileId: fileId)
                    print("[SYNC] 音频下载完成，大小: \(audioData.count) 字节")

                    // 缓存音频文件
                    try AudioCacheService.shared.cacheFile(data: audioData, fileId: fileId, mimeType: mimeType)
                    print("[SYNC] 音频缓存成功: \(fileId)")

                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    updatedData["downloaded"] = true
                    settingData[index] = updatedData
                } catch {
                    print("[SYNC] 音频下载失败: \(fileId), 错误: \(error.localizedDescription)")
                }
            } else {
                print("[SYNC] 附件条目 \(index + 1) 未知类型: \(mimeType)，跳过")
            }
        }

        print("[SYNC] setting.data 中的附件处理完成，共处理 \(settingData.count) 个条目")

        // 第二步：统一检测并下载所有附件（旧版图片、新版图片、音频）
        if let content = entry["content"] as? String {
            let allAttachmentData = await extractAndDownloadAllAttachments(
                from: content,
                existingSettingData: settingData,
                forceRedownload: forceRedownload
            )

            // 使用统一处理后的完整 setting.data
            settingData = allAttachmentData
            print("[SYNC] 统一处理后共 \(settingData.count) 个附件记录")
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
                print("[SYNC] 尝试下载图片 (第 \(attempt)/\(maxRetries) 次): \(fileId)")
                let data = try await miNoteService.downloadFile(fileId: fileId, type: type)
                print("[SYNC] 图片下载成功: \(fileId), 大小: \(data.count) 字节")
                return data
            } catch {
                lastError = error
                print("[SYNC] 图片下载失败 (第 \(attempt)/\(maxRetries) 次): \(fileId), 错误: \(error)")

                // 如果不是最后一次尝试,等待后重试
                if attempt < maxRetries {
                    let delay = TimeInterval(attempt) // 1秒, 2秒, 3秒
                    print("[SYNC] 等待 \(delay) 秒后重试...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // 所有重试都失败
        print("[SYNC] ❌ 所有重试都失败: \(fileId)")
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
        print("[SYNC] 🔍 开始检测所有附件...")

        var allSettingData: [[String: Any]] = existingSettingData
        var existingFileIds = Set<String>()

        // 提取已存在的 fileId
        for entry in existingSettingData {
            if let fileId = entry["fileId"] as? String {
                existingFileIds.insert(fileId)
            }
        }
        print("[SYNC] 已存在 \(existingFileIds.count) 个附件记录")

        // 1. 检测旧版图片格式: ☺ fileId<0/></>
        let legacyImageData = await extractLegacyImages(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !legacyImageData.isEmpty {
            print("[SYNC] 📷 找到 \(legacyImageData.count) 个旧版格式图片")
            allSettingData.append(contentsOf: legacyImageData)
            for entry in legacyImageData {
                if let fileId = entry["fileId"] as? String {
                    existingFileIds.insert(fileId)
                }
            }
        }

        // 2. 检测新版图片格式: <img fileid="xxx" />
        let newImageData = await extractNewFormatImages(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !newImageData.isEmpty {
            print("[SYNC] 🖼️ 找到 \(newImageData.isEmpty) 个新版格式图片")
            allSettingData.append(contentsOf: newImageData)
            for entry in newImageData {
                if let fileId = entry["fileId"] as? String {
                    existingFileIds.insert(fileId)
                }
            }
        }

        // 3. 检测音频格式: <sound fileid="xxx" />
        let audioData = await extractAudioAttachments(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !audioData.isEmpty {
            print("[SYNC] 🎵 找到 \(audioData.count) 个音频附件")
            allSettingData.append(contentsOf: audioData)
            for entry in audioData {
                if let fileId = entry["fileId"] as? String {
                    existingFileIds.insert(fileId)
                }
            }
        }

        print("[SYNC] ✅ 附件检测完成，共 \(allSettingData.count) 个附件记录")
        return allSettingData
    }

    /// 提取旧版格式图片
    private func extractLegacyImages(
        from content: String,
        existingFileIds: Set<String>,
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        // 使用正则表达式提取旧版格式的图片ID
        // 格式: ☺ fileId<0/></>
        let pattern = "☺ ([^<]+)<0/></>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        if matches.isEmpty {
            return []
        }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }

            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            // 跳过已存在的附件
            if existingFileIds.contains(fileId) {
                print("[SYNC] ⏭️ 旧版图片已在 settingJson 中，跳过: \(fileId)")
                continue
            }

            print("[SYNC] 📷 处理旧版格式图片: \(fileId)")

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
        // 使用正则表达式提取新版格式的图片ID
        // 格式: <img fileid="xxx" ... />
        let pattern = "<img[^>]+fileid=\"([^\"]+)\"[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        if matches.isEmpty {
            return []
        }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }

            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            // 跳过已存在的附件
            if existingFileIds.contains(fileId) {
                print("[SYNC] ⏭️ 新版图片已在 settingJson 中，跳过: \(fileId)")
                continue
            }

            print("[SYNC] 🖼️ 处理新版格式图片: \(fileId)")

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
        // 使用正则表达式提取音频ID
        // 格式: <sound fileid="xxx" ... />
        let pattern = "<sound[^>]+fileid=\"([^\"]+)\"[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        if matches.isEmpty {
            return []
        }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }

            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            // 跳过已存在的附件
            if existingFileIds.contains(fileId) {
                print("[SYNC] ⏭️ 音频已在 settingJson 中，跳过: \(fileId)")
                continue
            }

            print("[SYNC] 🎵 处理音频附件: \(fileId)")

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
        // 检查附件是否已存在且有效
        var existingFormat: String?
        var fileSize = 0

        if !forceRedownload {
            if attachmentType == "image" {
                // 尝试所有可能的图片格式
                let formats = ["jpg", "jpeg", "png", "gif", "webp"]
                for format in formats {
                    if localStorage.validateImage(fileId: fileId, fileType: format) {
                        print("[SYNC] ✅ 图片已存在且有效，跳过下载: \(fileId).\(format)")
                        existingFormat = format
                        if let imageData = localStorage.loadImage(fileId: fileId, fileType: format) {
                            fileSize = imageData.count
                        }
                        break
                    }
                }
            } else if attachmentType == "audio" {
                // 检查音频文件是否已缓存
                if AudioCacheService.shared.isCached(fileId: fileId) {
                    print("[SYNC] ✅ 音频已缓存，跳过下载: \(fileId)")
                    existingFormat = "amr" // 默认格式

                    // 获取缓存文件信息
                    if let cachedFileURL = AudioCacheService.shared.getCachedFile(for: fileId) {
                        do {
                            let attributes = try FileManager.default.attributesOfItem(atPath: cachedFileURL.path)
                            if let size = attributes[.size] as? Int {
                                fileSize = size
                                print("[SYNC] 音频文件大小: \(size) 字节")
                            }
                        } catch {
                            print("[SYNC] ⚠️ 获取音频文件大小失败: \(error)")
                        }
                    }
                }
            }
        }

        // 下载附件（如果需要）
        var downloadedFormat: String?

        if existingFormat == nil {
            do {
                print("[SYNC] 📥 开始下载附件: \(fileId), 类型: \(type)")
                let data = try await downloadImageWithRetry(fileId: fileId, type: type)
                print("[SYNC] ✅ 附件下载完成，大小: \(data.count) 字节")
                fileSize = data.count

                if attachmentType == "image" {
                    // 检测图片格式
                    let detectedFormat = detectImageFormat(from: data)
                    downloadedFormat = detectedFormat

                    // 保存图片
                    try localStorage.saveImage(imageData: data, fileId: fileId, fileType: detectedFormat)
                    print("[SYNC] 💾 图片保存成功: \(fileId).\(detectedFormat)")
                } else if attachmentType == "audio" {
                    // 检测音频格式
                    let detectedFormat = detectAudioFormat(from: data)
                    downloadedFormat = detectedFormat

                    // 使用 AudioCacheService 保存音频
                    let mimeType = "audio/\(detectedFormat)"
                    do {
                        try AudioCacheService.shared.cacheFile(
                            data: data,
                            fileId: fileId,
                            mimeType: mimeType
                        )
                        print("[SYNC] 💾 音频保存成功: \(fileId).\(detectedFormat)")
                    } catch {
                        print("[SYNC] ❌ 音频保存失败: \(fileId), 错误: \(error)")
                        return nil
                    }
                }
            } catch {
                print("[SYNC] ❌ 附件下载失败: \(fileId), 错误: \(error.localizedDescription)")
                return nil
            }
        }

        // 生成 setting.data 条目
        let finalFormat = downloadedFormat ?? existingFormat ?? (attachmentType == "image" ? "jpeg" : "amr")
        let mimeType = attachmentType == "image" ? "image/\(finalFormat)" : "audio/\(finalFormat)"

        let settingEntry: [String: Any] = [
            "fileId": fileId,
            "mimeType": mimeType,
            "size": fileSize,
        ]

        print("[SYNC] 📝 生成 setting.data 条目: \(fileId), mimeType: \(mimeType), size: \(fileSize)")
        return settingEntry
    }

    /// 从content中提取并下载旧版格式的图片，同时生成 setting.data
    /// 旧版格式: ☺ fileId<0/></>
    ///
    /// ⚠️ 已废弃：请使用 extractAndDownloadAllAttachments 方法
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
        print("[SYNC] 手动重新下载笔记图片: \(noteId)")

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

        print("[SYNC] 图片重新下载完成: 成功 \(successCount), 失败 \(failedCount)")
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
        print("[SYNC] 解析轻量级同步响应")

        // 提取 syncTag
        var syncTag = ""
        if let data = response["data"] as? [String: Any],
           let noteView = data["note_view"] as? [String: Any],
           let noteViewData = noteView["data"] as? [String: Any],
           let newSyncTag = noteViewData["syncTag"] as? String
        {
            syncTag = newSyncTag
        }

        // 提取有修改的条目
        var modifiedNotes: [Note] = []
        var modifiedFolders: [Folder] = []

        if let data = response["data"] as? [String: Any],
           let noteView = data["note_view"] as? [String: Any],
           let noteViewData = noteView["data"] as? [String: Any]
        {

            // 提取有修改的笔记
            if let entries = noteViewData["entries"] as? [[String: Any]] {
                for entry in entries {
                    if let note = Note.fromMinoteData(entry) {
                        modifiedNotes.append(note)
                        print("[SYNC] 找到有修改的笔记: \(note.id), 状态: \(entry["status"] as? String ?? "normal")")
                    }
                }
            }

            // 提取有修改的文件夹
            if let folders = noteViewData["folders"] as? [[String: Any]] {
                for folderEntry in folders {
                    if let folder = Folder.fromMinoteData(folderEntry) {
                        modifiedFolders.append(folder)
                        print("[SYNC] 找到有修改的文件夹: \(folder.id), 状态: \(folderEntry["status"] as? String ?? "normal")")
                    }
                }
            }
        }

        print("[SYNC] 解析完成: \(modifiedNotes.count) 个笔记, \(modifiedFolders.count) 个文件夹, syncTag: \(syncTag)")
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
        print("[SYNC] 处理有修改的文件夹: \(folder.id) - \(folder.name)")

        // 检查文件夹状态
        if let rawData = folder.rawData,
           let status = rawData["status"] as? String,
           status == "deleted"
        {
            // 文件夹已删除，从本地删除
            print("[SYNC] 文件夹状态为 deleted，从本地删除: \(folder.id)")
            try DatabaseService.shared.deleteFolder(folderId: folder.id)
        } else {
            // 文件夹正常，保存到本地
            print("[SYNC] 文件夹状态正常，保存到本地: \(folder.id)")
            try localStorage.saveFolders([folder])
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
        print("[SYNC] 处理有修改的笔记: \(note.id) - \(note.title)")
        var result = NoteSyncResult(noteId: note.id, noteTitle: note.title)

        // 🛡️ 同步保护检查：使用 SyncGuard 检查笔记是否应该被跳过
        // 包括：临时 ID 笔记、正在编辑、待上传等情况
        let shouldSkip = await syncGuard.shouldSkipSync(
            noteId: note.id,
            cloudTimestamp: note.updatedAt
        )
        if shouldSkip {
            // 获取跳过原因用于日志
            if let skipReason = await syncGuard.getSkipReason(
                noteId: note.id,
                cloudTimestamp: note.updatedAt
            ) {
                print("[SYNC] 🛡️ 同步保护：跳过笔记 \(note.id.prefix(8))... - \(skipReason.description)")
            }
            result.status = .skipped
            result.message = "同步保护：笔记正在编辑、待上传或使用临时 ID"
            result.success = true
            return result
        }

        // 检查笔记状态
        if let rawData = note.rawData,
           let status = rawData["status"] as? String,
           status == "deleted"
        {
            // 笔记已删除，从本地删除
            print("[SYNC] 笔记状态为 deleted，从本地删除: \(note.id)")
            try localStorage.deleteNote(noteId: note.id)
            result.status = .skipped
            result.message = "笔记已从云端删除"
            result.success = true
            return result
        }

        // 笔记正常，获取完整内容并保存
        do {
            // 获取笔记详情
            syncStatusMessage = "获取笔记详情: \(note.title)"
            let noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)

            // 更新笔记内容
            var updatedNote = note
            updatedNote.updateContent(from: noteDetails)
            print("[SYNC] 更新笔记内容完成: \(note.id), 内容长度: \(updatedNote.content.count)")

            // 下载图片，并获取更新后的 setting.data
            if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                // 更新笔记的 rawData 中的 setting.data
                var rawData = updatedNote.rawData ?? [:]
                var setting = rawData["setting"] as? [String: Any] ?? [:]
                setting["data"] = updatedSettingData
                rawData["setting"] = setting
                updatedNote.rawData = rawData
                print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
            }

            // 保存到本地
            print("[SYNC] 保存笔记到本地: \(updatedNote.id)")
            try localStorage.saveNote(updatedNote)

            // 检查是更新还是创建
            let existsLocally = localStorage.noteExistsLocally(noteId: note.id)
            result.status = existsLocally ? .updated : .created
            result.message = existsLocally ? "笔记已更新" : "新笔记已下载"
            result.success = true
        } catch let error as MiNoteError {
            print("[SYNC] 获取笔记详情失败 (MiNoteError): \(error)")
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
            print("[SYNC] 获取笔记详情失败: \(error)")
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
