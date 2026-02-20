import Combine
import Foundation
import SwiftUI

/// 笔记排序方式
public enum NoteSortOrder: String, Codable {
    case editDate // 编辑日期
    case createDate // 创建日期
    case title // 标题
}

/// 排序方向
public enum SortDirection: String, Codable {
    case ascending // 升序
    case descending // 降序
}

/// 笔记视图模型
///
/// 负责管理应用的主要业务逻辑和状态，包括：
/// - 笔记和文件夹的数据管理
/// - 同步操作（完整同步、增量同步）
/// - 离线操作队列处理
/// - 网络状态监控
/// - Cookie过期处理
///
/// **线程安全**：使用@MainActor确保所有UI更新在主线程执行
@MainActor
public class NotesViewModel: ObservableObject {
    // MARK: - 数据状态

    /// 笔记列表
    @Published public var notes: [Note] = []

    /// 文件夹列表
    @Published public var folders: [Folder] = []

    /// 当前选中的笔记
    @Published public var selectedNote: Note?

    /// 当前选中的文件夹
    @Published public var selectedFolder: Folder?

    /// 文件夹排序方式（按文件夹ID存储）
    @Published public var folderSortOrders: [String: NoteSortOrder] = [:]

    /// 笔记列表全局排序字段
    @Published public var notesListSortField: NoteSortOrder = .editDate

    /// 笔记列表排序方向
    @Published public var notesListSortDirection: SortDirection = .descending

    // MARK: - UI状态

    /// 是否正在加载
    @Published var isLoading = false

    /// 错误消息（用于显示错误提示）
    @Published var errorMessage: String?

    /// 搜索文本
    @Published var searchText = ""

    /// 搜索筛选选项
    @Published var searchFilterHasTags = false
    @Published var searchFilterHasChecklist = false
    @Published var searchFilterHasImages = false
    @Published var searchFilterHasAudio = false // 待实现
    @Published var searchFilterIsPrivate = false

    /// 是否显示登录视图
    @Published var showLoginView = false

    /// 私密笔记是否已解锁
    @Published var isPrivateNotesUnlocked = false

    /// 是否显示私密笔记密码输入对话框
    @Published var showPrivateNotesPasswordDialog = false

    /// 用户信息（用户名和头像）
    @Published var userProfile: UserProfile?

    /// 回收站笔记列表
    @Published var deletedNotes: [DeletedNote] = []

    /// 是否正在加载回收站笔记
    @Published var isLoadingDeletedNotes = false

    /// 是否显示回收站视图
    @Published var showTrashView = false

    /// 原生编辑器上下文（共享实例）
    @Published var nativeEditorContext = NativeEditorContext()

    /// 画廊视图是否展开（正在编辑笔记）
    @Published public var isGalleryExpanded = false

    // MARK: - 笔记切换保护

    /// 是否正在切换笔记
    private var isSwitchingNote = false

    /// 上次笔记切换的时间
    private var lastSwitchTime: Date?

    /// 笔记切换防抖时间间隔（秒）
    private let switchDebounceInterval: TimeInterval = 0.3

    /// 是否正在从 ViewStateCoordinator 更新状态
    private var isUpdatingFromCoordinator = false

    /// 当前加载任务的唯一标识符，跟踪延迟加载任务，防止过期任务完成时触发意外操作
    private var currentLoadingTaskId: UUID?

    // MARK: - 状态协调器

    /// 视图状态协调器
    ///
    /// 负责协调侧边栏、笔记列表和编辑器之间的状态同步
    public private(set) lazy var stateCoordinator = ViewStateCoordinator(viewModel: self)

    // MARK: - 设置

    /// 同步间隔（秒），默认5分钟
    @Published var syncInterval: Double = 300

    /// 是否自动保存
    @Published var autoSave = true

    // MARK: - 同步状态

    /// 是否正在同步
    @Published var isSyncing = false

    /// 同步进度（0.0 - 1.0）
    @Published var syncProgress: Double = 0

    /// 同步状态消息
    @Published var syncStatusMessage = ""

    /// 上次同步时间
    @Published var lastSyncTime: Date?

    /// 同步结果
    @Published var syncResult: SyncService.SyncResult?

    // MARK: - 数据加载状态指示

    /// 是否正在加载本地数据
    @Published var isLoadingLocalData = false

    /// 本地数据加载状态消息
    @Published var localDataLoadingMessage = ""

    /// 是否正在处理离线队列（从 OfflineOperationProcessor 同步）
    @Published var isProcessingOfflineQueue = false

    /// 离线队列处理进度（0.0 - 1.0）
    @Published var offlineQueueProgress = 0.0

    /// 离线队列处理状态消息
    @Published var offlineQueueStatusMessage = ""

    /// 离线队列待处理操作数量
    @Published var offlineQueuePendingCount = 0

    /// 离线队列已处理操作数量
    @Published var offlineQueueProcessedCount = 0

    /// 离线队列失败操作数量
    @Published var offlineQueueFailedCount = 0

    /// 同步完成后的笔记数量
    @Published var lastSyncedNotesCount = 0

    /// 是否处于离线模式
    @Published var isOfflineMode = false

    /// 离线模式原因
    @Published var offlineModeReason = ""

    /// 启动序列当前阶段（从 StartupSequenceManager 同步）
    @Published var startupPhase: StartupSequenceManager.StartupPhase = .idle

    /// 启动序列状态消息
    @Published var startupStatusMessage = ""

    /// 综合状态消息（用于状态栏显示）
    ///
    /// 根据当前状态返回最相关的状态消息
    var currentStatusMessage: String {
        // 优先显示离线模式
        if isOfflineMode {
            return "离线模式" + (offlineModeReason.isEmpty ? "" : "：\(offlineModeReason)")
        }

        // 显示启动序列状态
        if !startupStatusMessage.isEmpty, startupPhase != .completed, startupPhase != .idle {
            return startupStatusMessage
        }

        // 显示本地数据加载状态
        if isLoadingLocalData {
            return localDataLoadingMessage.isEmpty ? "正在加载本地数据..." : localDataLoadingMessage
        }

        // 显示离线队列处理状态
        if isProcessingOfflineQueue {
            return offlineQueueStatusMessage.isEmpty ? "正在处理离线操作..." : offlineQueueStatusMessage
        }

        // 显示同步状态
        if isSyncing {
            return syncStatusMessage.isEmpty ? "正在同步..." : syncStatusMessage
        }

        // 显示同步结果
        if let result = syncResult, lastSyncedNotesCount > 0 {
            return "已同步 \(lastSyncedNotesCount) 条笔记"
        }

        // 默认状态
        return ""
    }

    /// 是否有任何加载/处理操作正在进行
    var isAnyOperationInProgress: Bool {
        isLoadingLocalData || isProcessingOfflineQueue || isSyncing || isLoading
    }

    // MARK: - 离线操作处理器

    /// 操作处理器（用于观察处理状态）
    /// 基于 UnifiedOperationQueue
    @MainActor
    private let operationProcessor = OperationProcessor.shared

    // MARK: - 离线操作状态

    /// 待处理的离线操作数量（使用新的 UnifiedOperationQueue）
    var pendingOperationsCount: Int {
        unifiedQueue.getPendingOperations().count
    }

    /// 统一操作队列待上传数量
    var unifiedPendingUploadCount: Int {
        unifiedQueue.getPendingUploadCount()
    }

    /// 是否正在处理操作（从新的 OperationProcessor 获取）
    @Published var isProcessingOperations = false

    /// 操作处理进度（0.0 - 1.0）
    @Published var operationProgress = 0.0

    /// 操作处理状态消息
    @Published var operationStatusMessage = ""

    /// 统一操作队列所有待上传笔记 ID
    var unifiedPendingNoteIds: [String] {
        unifiedQueue.getAllPendingNoteIds()
    }

    /// 临时 ID 笔记数量（离线创建的笔记）
    var temporaryIdNoteCount: Int {
        unifiedQueue.getTemporaryIdNoteCount()
    }

    /// 检查笔记是否有待处理上传
    func hasPendingUpload(for noteId: String) -> Bool {
        unifiedQueue.hasPendingUpload(for: noteId)
    }

    /// 检查笔记是否使用临时 ID（离线创建）
    func isTemporaryIdNote(_ noteId: String) -> Bool {
        NoteOperation.isTemporaryId(noteId)
    }

    // MARK: - 网络状态（从 AuthenticationStateManager 同步）

    /// 是否在线（需要同时满足网络连接和Cookie有效）
    @Published var isOnline = true

    /// Cookie是否失效
    @Published var isCookieExpired = false

    /// 是否已显示Cookie失效提示（避免重复提示）
    @Published var cookieExpiredShown = false

    /// 是否显示Cookie失效弹窗
    @Published var showCookieExpiredAlert = false

    /// 是否保持离线模式（用户点击"取消"后设置为true，阻止后续请求）
    @Published var shouldStayOffline = false

    // MARK: - 依赖服务

    /// 小米笔记API服务
    let service = MiNoteService.shared

    /// 同步服务
    private let syncService = SyncService.shared

    /// 本地存储服务
    private let localStorage = LocalStorageService.shared

    /// 认证状态管理器（统一管理登录、Cookie刷新和在线状态）
    private let authStateManager = AuthenticationStateManager()

    /// 网络监控服务
    private let networkMonitor = NetworkMonitor.shared

    /// 统一操作队列
    private let unifiedQueue = UnifiedOperationQueue.shared

    /// Combine订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 自动刷新Cookie定时器
    private var autoRefreshCookieTimer: Timer?

    /// 自动同步定时器
    private var autoSyncTimer: Timer?

    /// 应用是否在前台
    @Published var isAppActive = true

    /// 上次同步时间戳（用于避免频繁同步）
    private var lastSyncTimestamp = Date.distantPast

    /// 最小同步间隔（秒）
    private let minSyncInterval: TimeInterval = 10.0

    // MARK: - 启动序列管理

    /// 启动序列管理器
    ///
    /// 负责协调应用启动时的各个步骤，确保按正确顺序执行
    private let startupManager = StartupSequenceManager()

    /// 是否为首次启动（本次会话）
    ///
    /// 用于区分首次启动和后续的数据刷新
    private var isFirstLaunch = true

    // MARK: - 计算属性

    /// 过滤后的笔记列表
    ///
    /// 根据搜索文本、选中的文件夹和筛选选项过滤笔记，并根据文件夹的排序方式排序
    var filteredNotes: [Note] {
        let filtered: [Note]

            // 首先根据搜索文本和文件夹过滤
            = if searchText.isEmpty
        {
            if let folder = selectedFolder {
                if folder.id == "starred" {
                    notes.filter(\.isStarred)
                } else if folder.id == "0" {
                    notes
                } else if folder.id == "2" {
                    // 私密笔记文件夹：显示 folderId 为 "2" 的笔记
                    notes.filter { $0.folderId == "2" }
                } else if folder.id == "uncategorized" {
                    // 未分类文件夹：显示 folderId 为 "0" 或空的笔记
                    notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }
                } else {
                    notes.filter { $0.folderId == folder.id }
                }
            } else {
                notes
            }
        } else {
            notes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                    note.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        // 应用搜索筛选选项
        let filteredBySearchOptions = filtered.filter { note in
            // 含标签的笔记
            if searchFilterHasTags, note.tags.isEmpty {
                return false
            }

            // 含核对清单的笔记
            if searchFilterHasChecklist, !noteHasChecklist(note) {
                return false
            }

            // 含图片的笔记
            if searchFilterHasImages, !noteHasImages(note) {
                return false
            }

            // 含录音的笔记（待实现）
            if searchFilterHasAudio, !noteHasAudio(note) {
                return false
            }

            // 私密笔记
            if searchFilterIsPrivate, note.folderId != "2" {
                return false
            }

            return true
        }

        // 应用全局排序（笔记列表排序方式）
        return sortNotes(filteredBySearchOptions, by: notesListSortField, direction: notesListSortDirection)
    }

    /// 检查笔记是否包含核对清单
    ///
    /// - Parameter note: 要检查的笔记
    /// - Returns: 如果包含核对清单返回 true，否则返回 false
    private func noteHasChecklist(_ note: Note) -> Bool {
        let content = note.primaryXMLContent.lowercased()
        // 检查是否包含 checkbox 相关标签
        return content.contains("checkbox") ||
            content.contains("type=\"checkbox\"") ||
            (content.contains("<input") && content.contains("checkbox"))
    }

    /// 检查笔记是否包含图片
    ///
    /// - Parameter note: 要检查的笔记
    /// - Returns: 如果包含图片返回 true，否则返回 false
    private func noteHasImages(_ note: Note) -> Bool {
        let content = note.primaryXMLContent.lowercased()
        // 检查是否包含图片相关标签
        if content.contains("<img") || content.contains("image") || content.contains("fileid") {
            return true
        }
        // 检查 rawData 中是否有图片数据
        if let setting = note.rawData?["setting"] as? [String: Any],
           let data = setting["data"] as? [[String: Any]], !data.isEmpty
        {
            return true
        }
        return false
    }

    /// 检查笔记是否包含录音（待实现）
    ///
    /// - Parameter note: 要检查的笔记
    /// - Returns: 如果包含录音返回 true，否则返回 false
    private func noteHasAudio(_: Note) -> Bool {
        // 待实现：检查笔记中是否包含录音
        // 目前返回 false
        false
    }

    /// 根据排序方式和方向对笔记进行排序
    ///
    /// 使用稳定排序：当主排序键相同时，使用 id 作为次要排序键，
    /// 确保排序结果的一致性，避免不必要的列表重排和动画。
    private func sortNotes(_ notes: [Note], by sortOrder: NoteSortOrder, direction: SortDirection) -> [Note] {
        let sorted: [Note] = switch sortOrder {
        case .editDate:
            // 使用稳定排序：先按 updatedAt 排序，相同时按 id 排序
            notes.sorted {
                if $0.updatedAt == $1.updatedAt {
                    return $0.id < $1.id
                }
                return $0.updatedAt < $1.updatedAt
            }
        case .createDate:
            // 使用稳定排序：先按 createdAt 排序，相同时按 id 排序
            notes.sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id < $1.id
                }
                return $0.createdAt < $1.createdAt
            }
        case .title:
            // 使用稳定排序：先按 title 排序，相同时按 id 排序
            notes.sorted {
                let comparison = $0.title.localizedCompare($1.title)
                if comparison == .orderedSame {
                    return $0.id < $1.id
                }
                return comparison == .orderedAscending
            }
        }

        // 根据排序方向决定是否反转
        return direction == .descending ? sorted.reversed() : sorted
    }

    /// 未分类文件夹（虚拟文件夹）
    ///
    /// 显示folderId为"0"或空的笔记，用于组织未分类的笔记
    var uncategorizedFolder: Folder {
        let uncategorizedCount = notes.count(where: { $0.folderId == "0" || $0.folderId.isEmpty })
        return Folder(id: "uncategorized", name: "未分类", count: uncategorizedCount, isSystem: false)
    }

    /// 是否已登录（是否有有效的Cookie）
    var isLoggedIn: Bool {
        service.isAuthenticated()
    }

    // MARK: - 初始化

    /// 初始化视图模型
    ///
    /// 执行以下初始化操作：
    /// 1. 加载本地数据（根据登录状态决定加载本地数据还是示例数据）
    /// 2. 加载设置
    /// 3. 加载同步状态
    /// 4. 恢复上次选中的笔记
    /// 5. 设置Cookie过期处理器
    /// 6. 监听网络状态
    /// 7. 如果已登录，执行启动序列（加载本地数据 → 处理离线队列 → 执行同步）
    ///
    public init() {
        // 加载本地数据（根据登录状态决定加载本地数据还是示例数据）
        loadLocalData()

        // 加载设置
        loadSettings()

        // 加载同步状态
        loadSyncStatus()

        // 恢复上次选中的文件夹和笔记
        restoreLastSelectedState()

        // 如果已登录，获取用户信息并执行启动序列
        if isLoggedIn {
            Task {
                await fetchUserProfile()
                // 执行启动序列（处理离线队列 → 执行同步）
                // 注意：本地数据已在 loadLocalData() 中加载
                await executeStartupSequence()
            }
        }

        // 同步 AuthenticationStateManager 的状态到 ViewModel
        // 这样 AuthenticationStateManager 的状态变化会触发 ViewModel 的 @Published 属性更新，进而触发 UI 更新
        setupAuthStateSync()

        // 同步 ViewOptionsManager 的排序设置到 ViewModel
        // 确保画廊视图和列表视图使用相同的排序设置
        setupViewOptionsSync()

        // 内容变化保存由 NoteEditingCoordinator 统一管理，不再在 ViewModel 中监听

        // 监听selectedNote和selectedFolder变化，保存状态
        Publishers.CombineLatest($selectedNote, $selectedFolder)
            .sink { [weak self] selectedNote, _ in
                self?.saveLastSelectedState()

                // 处理笔记切换时的音频面板状态同步
                if let newNoteId = selectedNote?.id {
                    self?.handleNoteSwitch(to: newNoteId)
                }
            }
            .store(in: &cancellables)

        // 监听网络恢复通知
        NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleNetworkRestored()
        }

        // 监听应用状态变化（前台/后台）
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppBecameActive()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppResignedActive()
        }

        // 监听启动序列完成通知
        NotificationCenter.default.addObserver(
            forName: .startupSequenceCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // 提取具体的值以避免跨隔离域传递字典
            let success = notification.userInfo?["success"] as? Bool ?? false
            let errors = notification.userInfo?["errors"] as? [String] ?? []
            let duration = notification.userInfo?["duration"] as? TimeInterval ?? 0
            Task { @MainActor in
                self?.handleStartupSequenceCompletedWithValues(success: success, errors: errors, duration: duration)
            }
        }

        // 监听 Cookie 刷新成功通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CookieRefreshedSuccessfully"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleCookieRefreshSuccess()
            }
        }

        // 监听 ID 映射完成通知
        NotificationCenter.default.addObserver(
            forName: IdMappingRegistry.idMappingCompletedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // 提取通知中的 ID 映射信息
            let localId = notification.userInfo?["localId"] as? String ?? ""
            let serverId = notification.userInfo?["serverId"] as? String ?? ""
            let entityType = notification.userInfo?["entityType"] as? String ?? ""
            Task { @MainActor in
                self?.handleIdMappingCompleted(localId: localId, serverId: serverId, entityType: entityType)
            }
        }

        // 启动自动同步定时器（如果应用在前台）
        if isAppActive {
            startAutoSyncTimer()
        }
    }

    /// 执行启动序列
    ///
    /// 使用 StartupSequenceManager 执行启动序列：
    /// 1. 处理离线队列（如果网络可用且Cookie有效）
    /// 2. 执行完整同步（如果网络可用且Cookie有效）
    ///
    /// 注意：本地数据已在 loadLocalData() 中加载，这里只执行后续步骤
    ///
    private func executeStartupSequence() async {
        guard isFirstLaunch else { return }

        LogService.shared.info(.viewmodel, "开始执行启动序列")
        isFirstLaunch = false

        // 使用 StartupSequenceManager 执行启动序列
        await startupManager.executeStartupSequence()

        // 启动序列完成后，重新加载本地数据以获取同步后的最新数据
        await reloadDataAfterStartup()
    }

    /// 启动序列完成后重新加载数据
    ///
    private func reloadDataAfterStartup() async {
        do {
            let localNotes = try localStorage.getAllLocalNotes()
            if !localNotes.isEmpty {
                notes = localNotes
                LogService.shared.info(.viewmodel, "启动后重新加载了 \(localNotes.count) 条笔记")
            }

            loadFolders()
            updateFolderCounts()
        } catch {
            LogService.shared.error(.viewmodel, "启动后重新加载数据失败: \(error)")
        }
    }

    /// 处理启动序列完成通知
    ///
    private func handleStartupSequenceCompletedWithValues(success: Bool, errors: [String], duration: TimeInterval) {
        LogService.shared.info(.viewmodel, "启动序列完成 - 成功: \(success), 耗时: \(String(format: "%.2f", duration))s")
        if !errors.isEmpty {
            LogService.shared.warning(.viewmodel, "启动序列错误: \(errors.joined(separator: ", "))")
        }
    }

    /// 同步 AuthenticationStateManager 的状态到 ViewModel
    ///
    /// 通过 Combine 将 AuthenticationStateManager 的 @Published 属性同步到 ViewModel 的 @Published 属性
    /// 这样 AuthenticationStateManager 的状态变化会自动触发 ViewModel 的状态更新，进而触发 UI 更新
    private func setupAuthStateSync() {
        // 同步 isOnline
        authStateManager.$isOnline
            .receive(on: DispatchQueue.main)
            .assign(to: &$isOnline)

        // 同步 isCookieExpired
        authStateManager.$isCookieExpired
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCookieExpired)

        // 同步 cookieExpiredShown
        authStateManager.$cookieExpiredShown
            .receive(on: DispatchQueue.main)
            .assign(to: &$cookieExpiredShown)

        // 同步 showCookieExpiredAlert
        authStateManager.$showCookieExpiredAlert
            .receive(on: DispatchQueue.main)
            .assign(to: &$showCookieExpiredAlert)

        // 同步 shouldStayOffline
        authStateManager.$shouldStayOffline
            .receive(on: DispatchQueue.main)
            .assign(to: &$shouldStayOffline)

        // 同步 showLoginView
        authStateManager.$showLoginView
            .receive(on: DispatchQueue.main)
            .assign(to: &$showLoginView)

        // 同步 ViewStateCoordinator 的状态到 ViewModel
        // - 1.1: 编辑笔记内容时保持选中状态不变
        // - 1.2: 笔记内容保存触发 notes 数组更新时不重置 selectedNote
        // - 4.1: 作为单一数据源管理 selectedFolder 和 selectedNote 的状态
        setupStateCoordinatorSync()

        // 同步数据加载状态指示
        setupDataLoadingStatusSync()
    }

    /// 同步数据加载状态指示
    ///
    /// 通过 Combine 将 OperationProcessor、StartupSequenceManager 和 OnlineStateManager 的状态同步到 ViewModel
    ///
    private func setupDataLoadingStatusSync() {
        // 监听 OperationProcessor 状态
        // 由于 OperationProcessor 是 actor，使用定时器定期更新
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    // 更新处理状态
                    isProcessingOperations = await operationProcessor.isProcessing

                    // 更新进度
                    let stats = unifiedQueue.getStatistics()
                    let totalCount = stats["pending", default: 0] +
                        stats["processing", default: 0] +
                        stats["failed", default: 0]
                    let processedCount = stats["completed", default: 0]
                    let failedCount = stats["failed", default: 0]

                    if totalCount + processedCount > 0 {
                        operationProgress = Double(processedCount) / Double(totalCount + processedCount)
                    } else {
                        operationProgress = 0.0
                    }

                    // 更新状态消息
                    if isProcessingOperations {
                        operationStatusMessage = "正在处理操作..."
                    } else if totalCount > 0 {
                        operationStatusMessage = "等待处理 \(totalCount) 个操作"
                    } else {
                        operationStatusMessage = ""
                    }

                    // 更新离线队列状态
                    offlineQueueProcessedCount = processedCount
                    offlineQueuePendingCount = totalCount
                    offlineQueueFailedCount = failedCount
                }
            }
            .store(in: &cancellables)

        // 同步 StartupSequenceManager 的状态
        startupManager.$currentPhase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self else { return }
                startupPhase = phase

                // 根据阶段更新加载状态
                switch phase {
                case .loadingLocalData:
                    isLoadingLocalData = true
                    localDataLoadingMessage = "正在加载本地数据..."
                case .processingOfflineQueue:
                    isLoadingLocalData = false
                    localDataLoadingMessage = ""
                case .syncing:
                    isLoadingLocalData = false
                    localDataLoadingMessage = ""
                case .completed, .failed:
                    isLoadingLocalData = false
                    localDataLoadingMessage = ""
                case .idle:
                    break
                }
            }
            .store(in: &cancellables)

        startupManager.$statusMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$startupStatusMessage)

        // 同步离线模式状态
        // 监听 OnlineStateManager 的在线状态
        OnlineStateManager.shared.$isOnline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOnline in
                guard let self else { return }
                isOfflineMode = !isOnline

                // 更新离线模式原因
                if !isOnline {
                    if !NetworkMonitor.shared.isConnected {
                        offlineModeReason = "网络未连接"
                    } else if !service.isAuthenticated() {
                        offlineModeReason = "未登录"
                    } else if isCookieExpired {
                        offlineModeReason = "登录已过期"
                    } else {
                        offlineModeReason = ""
                    }
                } else {
                    offlineModeReason = ""
                }
            }
            .store(in: &cancellables)
    }

    /// 同步 ViewStateCoordinator 的状态到 ViewModel
    ///
    /// 通过 Combine 将 ViewStateCoordinator 的 @Published 属性同步到 ViewModel 的 @Published 属性
    /// 这样 ViewStateCoordinator 的状态变化会自动触发 ViewModel 的状态更新，进而触发 UI 更新
    ///
    private func setupStateCoordinatorSync() {
        // 同步 selectedFolder
        stateCoordinator.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] folder in
                guard let self else { return }

                // 防止循环更新：当正在从 Coordinator 更新时，忽略新的更新
                guard !isUpdatingFromCoordinator else { return }

                if selectedFolder?.id != folder?.id {
                    isUpdatingFromCoordinator = true
                    selectedFolder = folder
                    isUpdatingFromCoordinator = false
                }
            }
            .store(in: &cancellables)

        // 同步 selectedNote
        stateCoordinator.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }

                guard !isUpdatingFromCoordinator else { return }

                if selectedNote?.id != note?.id {
                    isUpdatingFromCoordinator = true
                    selectedNote = note
                    isUpdatingFromCoordinator = false

                    postNoteSelectionNotification()
                }
            }
            .store(in: &cancellables)
    }

    // 发送笔记选中状态变化通知

    private func postNoteSelectionNotification() {
        let hasSelectedNote = selectedNote != nil
        NotificationCenter.default.post(
            name: .noteSelectionDidChange,
            object: self,
            userInfo: [
                "hasSelectedNote": hasSelectedNote,
                "noteId": selectedNote?.id as Any,
            ]
        )
    }

    /// 同步 ViewOptionsManager 的排序设置到 ViewModel
    ///
    /// 通过 Combine 将 ViewOptionsManager 的排序设置同步到 ViewModel 的排序属性
    /// 确保画廊视图和列表视图使用相同的排序设置
    ///
    private func setupViewOptionsSync() {
        // 同步排序方式
        ViewOptionsManager.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }

                if notesListSortField != state.sortOrder {
                    notesListSortField = state.sortOrder
                }

                if notesListSortDirection != state.sortDirection {
                    notesListSortDirection = state.sortDirection
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func handleNetworkRestored() {
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await processPendingOperations()
        }
    }

    // MARK: - 离线操作辅助方法

    /// 从 API 响应中提取 tag 值
    ///
    /// 优先从 response["data"]["tag"] 获取，其次从 response["entry"]["tag"] 获取
    /// - Parameter response: API 响应字典
    /// - Parameter fallbackTag: 如果响应中没有 tag，使用的默认值
    /// - Returns: 提取到的 tag 值，如果都没有则返回 fallbackTag
    private func extractTag(from response: [String: Any], fallbackTag: String) -> String {
        var tagValue: String?

        // 优先从 data.entry.tag 获取
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any]
        {
            tagValue = entry["tag"] as? String
        }

        // 其次从根级别的 entry.tag 获取
        if tagValue == nil, let entry = response["entry"] as? [String: Any] {
            tagValue = entry["tag"] as? String
        }

        // 最后从 data.tag 获取
        if tagValue == nil, let data = response["data"] as? [String: Any] {
            tagValue = data["tag"] as? String
        }

        return tagValue ?? fallbackTag
    }

    /// 从 API 响应中提取 entry 数据
    ///
    /// 优先从 response["data"]["entry"] 获取，其次从 response["entry"] 获取
    /// - Parameter response: API 响应字典
    /// - Returns: entry 字典，如果不存在则返回 nil
    private func extractEntry(from response: [String: Any]) -> [String: Any]? {
        // 优先从 data.entry 获取
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any]
        {
            return entry
        }

        // 其次从根级别的 entry 获取
        if let entry = response["entry"] as? [String: Any] {
            return entry
        }

        return nil
    }

    /// 检查 API 响应是否成功
    ///
    /// - Parameter response: API 响应字典
    /// - Returns: 如果成功返回 true，否则返回 false
    private func isResponseSuccess(_ response: [String: Any]) -> Bool {
        if let code = response["code"] as? Int {
            return code == 0
        }
        // 如果没有 code 字段，检查 result 字段
        if let result = response["result"] as? String {
            return result == "ok"
        }
        return false
    }

    /// 从 API 响应中提取错误信息
    ///
    /// - Parameter response: API 响应字典
    /// - Returns: 错误消息，如果无法提取则返回默认消息
    private func extractErrorMessage(from response: [String: Any], defaultMessage: String = "操作失败") -> String {
        response["description"] as? String
            ?? response["message"] as? String
            ?? defaultMessage
    }

    /// 统一处理离线操作的错误
    ///
    /// - Parameters:
    ///   - operation: 离线操作
    ///   - error: 发生的错误
    ///   - context: 操作上下文描述（用于日志）
    // MARK: - 统一的离线队列管理

    /// 统一处理错误并将操作添加到离线队列
    ///
    /// 此方法处理以下情况：
    /// - 401 Cookie过期：设置离线状态，添加到队列
    /// - 网络错误：添加到队列
    /// - 其他错误：根据错误类型决定是否添加到队列
    ///
    /// - Parameters:
    ///   - error: 发生的错误
    ///   - operationType: 操作类型
    ///   - noteId: 笔记或文件夹ID
    ///   - operationData: 操作数据（需要JSON编码）
    ///   - context: 操作上下文（用于日志）
    /// - Returns: 是否成功添加到离线队列
    @MainActor
    private func handleErrorAndAddToOfflineQueue(
        error: Error,
        operationType: OperationType,
        noteId: String,
        operationData: [String: Any],
        context: String
    ) -> Bool {
        LogService.shared.debug(.viewmodel, "处理错误并添加到离线队列: \(operationType.rawValue), context: \(context)")

        guard let data = try? JSONSerialization.data(withJSONObject: operationData, options: []) else {
            LogService.shared.error(.viewmodel, "无法编码操作数据")
            return false
        }

        // 使用 ErrorRecoveryService 统一处理错误
        let result = ErrorRecoveryService.shared.handleNetworkError(
            operation: operationType,
            noteId: noteId,
            data: data,
            error: error,
            context: context
        )

        switch result {
        case let .addedToQueue(message):
            LogService.shared.debug(.viewmodel, "已加入离线队列: \(message)")
            if case MiNoteError.cookieExpired = error {
                setOfflineStatus(reason: "Cookie过期")
            }
            return true

        case let .noRetry(message):
            LogService.shared.warning(.viewmodel, "操作不重试: \(message)")
            return false

        case let .permanentlyFailed(message):
            LogService.shared.error(.viewmodel, "操作永久失败: \(message)")
            errorMessage = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.errorMessage = nil
            }
            return false
        }
    }

    /// 将操作添加到离线队列（内部方法，统一编码逻辑）
    ///
    /// - Parameters:
    ///   - type: 操作类型
    ///   - noteId: 笔记或文件夹ID
    ///   - data: 操作数据字典
    /// - Returns: 是否成功添加
    @MainActor
    private func addOperationToOfflineQueue(
        type: OperationType,
        noteId: String,
        data: [String: Any],
        priority: Int? = nil
    ) -> Bool {
        do {
            let operationData = try JSONSerialization.data(withJSONObject: data, options: [])
            let operationPriority = priority ?? NoteOperation.calculatePriority(for: type)
            let operation = NoteOperation(
                type: type,
                noteId: noteId,
                data: operationData,
                priority: operationPriority
            )
            try unifiedQueue.enqueue(operation)
            return true
        } catch {
            LogService.shared.error(.viewmodel, "编码操作数据失败: \(error)")
            return false
        }
    }

    /// 设置离线状态
    ///
    /// - Parameter reason: 离线原因（用于日志）
    @MainActor
    private func setOfflineStatus(reason: String) {
        LogService.shared.warning(.viewmodel, "设置为离线状态，原因: \(reason)")
        isOnline = false
        isCookieExpired = true

        if !cookieExpiredShown {
            cookieExpiredShown = true
            errorMessage = "已切换到离线模式。操作将保存到离线队列，请重新登录后同步。"

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.errorMessage = nil
            }
        }
    }

    /// 恢复在线状态
    ///
    /// 当Cookie恢复有效时调用此方法
    /// 注意：在线状态现在由 OnlineStateManager 统一管理，这里只需要刷新状态并处理待同步操作
    @MainActor
    private func restoreOnlineStatus() {
        guard service.hasValidCookie() else { return }

        OnlineStateManager.shared.refreshStatus()

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)

            if isOnline {
                LogService.shared.info(.viewmodel, "已恢复在线状态，开始处理待同步操作")
                await processPendingOperations()
            }
        }
    }

    /// 处理待同步的离线操作
    ///
    /// 当网络恢复时，触发操作处理器处理待处理的操作
    ///
    /// **注意**：实际的操作处理由 OperationProcessor 完成
    @MainActor
    private func processPendingOperations() async {
        guard isOnline, service.isAuthenticated() else { return }

        Task {
            await operationProcessor.processQueue()
        }
    }

    private func loadLocalData() {
        do {
            let localNotes = try localStorage.getAllLocalNotes()
            if !localNotes.isEmpty {
                notes = localNotes
                LogService.shared.info(.viewmodel, "从本地存储加载了 \(localNotes.count) 条笔记")
            } else {
                notes = []
            }
        } catch {
            LogService.shared.error(.viewmodel, "加载本地数据失败: \(error)")
            notes = []
        }

        loadFolders()
    }

    public func loadFolders() {
        do {
            let localFolders = try localStorage.loadFolders()

            if !localFolders.isEmpty {
                // 确保系统文件夹存在
                var foldersWithCount = localFolders

                // 检查是否有系统文件夹，如果没有则添加
                let hasAllNotes = foldersWithCount.contains { $0.id == "0" }
                let hasStarred = foldersWithCount.contains { $0.id == "starred" }
                let hasPrivateNotes = foldersWithCount.contains { $0.id == "2" }

                if !hasAllNotes {
                    let insertIndex = min(0, foldersWithCount.count)
                    foldersWithCount.insert(Folder(id: "0", name: "所有笔记", count: notes.count, isSystem: true), at: insertIndex)
                }

                let currentHasAllNotes = foldersWithCount.contains { $0.id == "0" }
                if !hasStarred {
                    let insertIndex = min(currentHasAllNotes ? 1 : 0, foldersWithCount.count)
                    foldersWithCount.insert(
                        Folder(id: "starred", name: "置顶", count: notes.count(where: { $0.isStarred }), isSystem: true),
                        at: insertIndex
                    )
                }

                let currentHasStarred = foldersWithCount.contains { $0.id == "starred" }
                if !hasPrivateNotes {
                    let privateNotesCount = notes.count(where: { $0.folderId == "2" })
                    let insertIndex = min((currentHasAllNotes ? 1 : 0) + (currentHasStarred ? 1 : 0), foldersWithCount.count)
                    foldersWithCount.insert(Folder(id: "2", name: "私密笔记", count: privateNotesCount, isSystem: true), at: insertIndex)
                }

                // 回收站不再作为文件夹显示，而是作为按钮

                // 更新文件夹计数
                for i in 0 ..< foldersWithCount.count {
                    let folder = foldersWithCount[i]
                    if folder.id == "0" {
                        foldersWithCount[i].count = notes.count
                    } else if folder.id == "starred" {
                        foldersWithCount[i].count = notes.count(where: { $0.isStarred })
                    } else if folder.id == "2" {
                        // 私密笔记文件夹：显示 folderId 为 "2" 的笔记
                        foldersWithCount[i].count = notes.count(where: { $0.folderId == "2" })
                    } else if folder.id == "uncategorized" {
                        // 未分类文件夹：显示 folderId 为 "0" 或空的笔记
                        foldersWithCount[i].count = notes.count(where: { $0.folderId == "0" || $0.folderId.isEmpty })
                    } else {
                        foldersWithCount[i].count = notes.count(where: { $0.folderId == folder.id })
                    }
                }

                folders = foldersWithCount
            } else {
                // 如果没有本地文件夹数据，加载示例数据
                // loadSampleFolders()
            }
        } catch {
            LogService.shared.error(.viewmodel, "加载文件夹失败: \(error)")
        }
    }

    private func loadSyncStatus() {
        if let syncStatus = localStorage.loadSyncStatus() {
            lastSyncTime = syncStatus.lastSyncTime
        }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        syncInterval = defaults.double(forKey: "syncInterval")
        if syncInterval == 0 {
            syncInterval = 300 // 默认值
        }
        autoSave = defaults.bool(forKey: "autoSave")

        // 加载笔记列表排序设置
        if let sortFieldString = defaults.string(forKey: "notesListSortField"),
           let sortField = NoteSortOrder(rawValue: sortFieldString)
        {
            notesListSortField = sortField
        }
        if let sortDirectionString = defaults.string(forKey: "notesListSortDirection"),
           let sortDirection = SortDirection(rawValue: sortDirectionString)
        {
            notesListSortDirection = sortDirection
        }
    }

    /// 设置笔记列表排序字段
    func setNotesListSortField(_ field: NoteSortOrder) {
        notesListSortField = field
        let defaults = UserDefaults.standard
        defaults.set(field.rawValue, forKey: "notesListSortField")
    }

    /// 设置笔记列表排序方向
    func setNotesListSortDirection(_ direction: SortDirection) {
        notesListSortDirection = direction
        let defaults = UserDefaults.standard
        defaults.set(direction.rawValue, forKey: "notesListSortDirection")
    }

    /// 加载文件夹排序方式
    private func loadFolderSortOrders() {
        let defaults = UserDefaults.standard
        if let jsonString = defaults.string(forKey: "folderSortOrders"),
           let jsonData = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: NoteSortOrder].self, from: jsonData)
        {
            folderSortOrders = decoded
        }
    }

    /// 保存最后选中的文件夹和笔记ID
    private func saveLastSelectedState() {
        let defaults = UserDefaults.standard

        // 保存文件夹ID
        if let folderId = selectedFolder?.id {
            defaults.set(folderId, forKey: "lastSelectedFolderId")
        } else {
            defaults.removeObject(forKey: "lastSelectedFolderId")
        }

        // 保存笔记ID
        if let noteId = selectedNote?.id {
            defaults.set(noteId, forKey: "lastSelectedNoteId")
        } else {
            defaults.removeObject(forKey: "lastSelectedNoteId")
        }
    }

    /// 恢复上次选中的文件夹和笔记，如果没有则选中"所有笔记"文件夹的第一个笔记
    private func restoreLastSelectedState() {
        // 等待notes和folders加载完成后再恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }

            let defaults = UserDefaults.standard

            // 尝试恢复上次选中的文件夹
            var restoredFolder: Folder?
            let currentFolders = folders
            if let lastFolderId = defaults.string(forKey: "lastSelectedFolderId"),
               let folder = currentFolders.first(where: { $0.id == lastFolderId })
            {
                restoredFolder = folder
                selectedFolder = folder
            } else {
                restoredFolder = currentFolders.first(where: { $0.id == "0" })
                selectedFolder = restoredFolder
            }

            // 获取当前文件夹中的笔记列表
            let notesInFolder = getNotesInFolder(restoredFolder)
            let currentNotes = notes

            // 尝试恢复上次选中的笔记
            if let lastNoteId = defaults.string(forKey: "lastSelectedNoteId"),
               let lastNote = currentNotes.first(where: { $0.id == lastNoteId })
            {
                if notesInFolder.contains(where: { $0.id == lastNoteId }) {
                    selectedNote = lastNote
                } else {
                    selectedNote = notesInFolder.first
                }
            } else {
                selectedNote = notesInFolder.first
            }
        }
    }

    /// 获取文件夹中的笔记列表
    private func getNotesInFolder(_ folder: Folder?) -> [Note] {
        guard let folder else { return notes }

        if folder.id == "starred" {
            return notes.filter(\.isStarred)
        } else if folder.id == "0" {
            return notes
        } else if folder.id == "2" {
            // 私密笔记文件夹：显示 folderId 为 "2" 的笔记
            return notes.filter { $0.folderId == "2" }
        } else if folder.id == "uncategorized" {
            return notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }
        } else {
            return notes.filter { $0.folderId == folder.id }
        }
    }

    // MARK: - 登录和Cookie刷新成功处理

    /// 登录成功后的处理
    ///
    /// 清除示例数据，执行完整同步
    ///
    public func handleLoginSuccess() async {
        clearSampleDataIfNeeded()
        await fetchUserProfile()

        do {
            isSyncing = true
            syncStatusMessage = "正在同步数据..."

            let result = try await syncService.performFullSync()

            await reloadDataAfterSync()

            isSyncing = false
            syncStatusMessage = "同步完成"
            lastSyncTime = Date()
            lastSyncedNotesCount = result.syncedNotes

            LogService.shared.info(.viewmodel, "登录后同步成功，同步了 \(result.syncedNotes) 条笔记")
        } catch {
            isSyncing = false
            syncStatusMessage = "同步失败"
            errorMessage = "同步失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "登录后同步失败: \(error)")
        }
    }

    /// Cookie刷新成功后的处理
    ///
    /// 恢复在线状态，执行完整同步
    ///
    public func handleCookieRefreshSuccess() async {
        LogService.shared.info(.viewmodel, "处理Cookie刷新成功")

        restoreOnlineStatus()
        await processPendingOperations()

        do {
            isSyncing = true
            syncStatusMessage = "正在同步数据..."

            let result = try await syncService.performFullSync()

            await reloadDataAfterSync()

            isSyncing = false
            syncStatusMessage = "同步完成"
            lastSyncTime = Date()
            lastSyncedNotesCount = result.syncedNotes

            LogService.shared.info(.viewmodel, "Cookie刷新后同步成功，同步了 \(result.syncedNotes) 条笔记")
        } catch {
            isSyncing = false
            syncStatusMessage = "同步失败"
            errorMessage = "同步失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "Cookie刷新后同步失败: \(error)")
        }
    }

    /// 处理 ID 映射完成通知
    ///
    /// 当离线创建的笔记上传成功后，临时 ID 会被替换为云端下发的正式 ID。
    /// 此方法更新 ViewModel 中的相关引用。
    ///
    /// - Parameters:
    ///   - localId: 临时 ID（格式：local_xxx）
    ///   - serverId: 云端下发的正式 ID
    ///   - entityType: 实体类型（"note" 或 "folder"）
    ///
    private func handleIdMappingCompleted(localId: String, serverId: String, entityType: String) {
        LogService.shared.debug(.viewmodel, "处理 ID 映射完成: \(localId.prefix(16))... -> \(serverId.prefix(8))... (\(entityType))")

        guard entityType == "note" else { return }

        if selectedNote?.id == localId {
            if var updatedNote = selectedNote {
                updatedNote = Note(
                    id: serverId,
                    title: updatedNote.title,
                    content: updatedNote.content,
                    folderId: updatedNote.folderId,
                    isStarred: updatedNote.isStarred,
                    createdAt: updatedNote.createdAt,
                    updatedAt: updatedNote.updatedAt,
                    tags: updatedNote.tags,
                    rawData: updatedNote.rawData
                )
                selectedNote = updatedNote
            }
        }

        if let index = notes.firstIndex(where: { $0.id == localId }) {
            let oldNote = notes[index]
            let updatedNote = Note(
                id: serverId,
                title: oldNote.title,
                content: oldNote.content,
                folderId: oldNote.folderId,
                isStarred: oldNote.isStarred,
                createdAt: oldNote.createdAt,
                updatedAt: oldNote.updatedAt,
                tags: oldNote.tags,
                rawData: oldNote.rawData,
                snippet: oldNote.snippet,
                colorId: oldNote.colorId,
                subject: oldNote.subject,
                alertDate: oldNote.alertDate,
                type: oldNote.type,
                serverTag: oldNote.serverTag,
                status: oldNote.status,
                settingJson: oldNote.settingJson,
                extraInfoJson: oldNote.extraInfoJson
            )
            notes[index] = updatedNote
        }
    }

    /// 清除示例数据（如果有）
    ///
    /// 检查当前笔记是否为示例数据，如果是则清除
    ///
    private func clearSampleDataIfNeeded() {
        // 检查是否有示例数据（示例数据的ID以"sample-"开头）
        let hasSampleData = notes.contains { $0.id.hasPrefix("sample-") }

        if hasSampleData {
            notes.removeAll { $0.id.hasPrefix("sample-") }

            // 如果当前选中的是示例笔记，清除选中状态
            if let selectedNote, selectedNote.id.hasPrefix("sample-") {
                self.selectedNote = nil
            }

            // 更新文件夹计数
            updateFolderCounts()
        }
    }

    /// 同步后重新加载数据
    ///
    private func reloadDataAfterSync() async {
        do {
            let localNotes = try localStorage.getAllLocalNotes()
            notes = localNotes
            LogService.shared.debug(.viewmodel, "重新加载了 \(localNotes.count) 条笔记")

            // 同步后更新 selectedNote，确保编辑器显示最新内容
            if let currentId = selectedNote?.id,
               let updatedNote = localNotes.first(where: { $0.id == currentId })
            {
                selectedNote = updatedNote
                await MemoryCacheManager.shared.cacheNote(updatedNote)
            }

            loadFolders()
            updateFolderCounts()
        } catch {
            LogService.shared.error(.viewmodel, "重新加载数据失败: \(error)")
        }
    }

    // MARK: - 同步功能

    /// 执行完整同步
    ///
    /// 完整同步会清除所有本地数据，然后从云端拉取所有笔记和文件夹
    ///
    /// **注意**：此操作会丢失所有本地未同步的更改
    func performFullSync() async {
        let authStatus = service.isAuthenticated()

        guard authStatus else {
            errorMessage = "请先登录小米账号"
            return
        }

        guard !isSyncing else {
            errorMessage = "同步正在进行中"
            return
        }

        isSyncing = true
        syncProgress = 0
        syncStatusMessage = "开始同步..."
        errorMessage = nil

        defer {
            isSyncing = false
        }

        do {
            let result = try await syncService.performFullSync()

            syncResult = result
            lastSyncTime = result.lastSyncTime
            lastSyncedNotesCount = result.syncedNotes

            await loadLocalDataAfterSync()

            syncProgress = 1.0
            syncStatusMessage = "同步完成: 成功同步 \(result.syncedNotes) 条笔记"
            LogService.shared.info(.viewmodel, "同步成功，同步了 \(result.syncedNotes) 条笔记")
        } catch let error as MiNoteError {
            LogService.shared.error(.viewmodel, "同步失败 MiNoteError: \(error)")
            handleMiNoteError(error)
            syncStatusMessage = "同步失败"
        } catch {
            LogService.shared.error(.viewmodel, "同步失败: \(error)")
            errorMessage = "同步失败: \(error.localizedDescription)"
            syncStatusMessage = "同步失败"
        }
    }

    /// 执行增量同步
    ///
    /// 增量同步只同步自上次同步以来的更改，不会清除本地数据
    /// 如果从未同步过，会自动执行完整同步
    func performIncrementalSync() async {
        guard service.isAuthenticated() else {
            errorMessage = "请先登录小米账号"
            return
        }

        guard !isSyncing else {
            errorMessage = "同步正在进行中"
            return
        }

        isSyncing = true
        syncProgress = 0
        syncStatusMessage = "开始增量同步..."
        errorMessage = nil

        defer {
            isSyncing = false
        }

        do {
            let result = try await syncService.performIncrementalSync()

            // 更新同步结果
            syncResult = result
            lastSyncTime = result.lastSyncTime
            lastSyncedNotesCount = result.syncedNotes

            // 重新加载本地数据
            await loadLocalDataAfterSync()

            syncProgress = 1.0
            syncStatusMessage = "增量同步完成: 成功同步 \(result.syncedNotes) 条笔记"
        } catch let error as MiNoteError {
            handleMiNoteError(error)
            syncStatusMessage = "增量同步失败"
        } catch {
            errorMessage = "增量同步失败: \(error.localizedDescription)"
            syncStatusMessage = "增量同步失败"
        }
    }

    /// 同步后重新加载本地数据
    ///
    /// **关键修复**：如果用户正在编辑笔记且有未保存的更改，不更新 selectedNote 的内容
    /// 这样可以防止云端同步覆盖用户正在编辑的内容
    ///
    /// **统一操作队列集成**：使用 NoteOperationCoordinator 检查活跃编辑状态
    private func loadLocalDataAfterSync() async {
        do {
            let currentSelectedNoteId = selectedNote?.id
            let hasUnsavedChanges = nativeEditorContext.hasUnsavedChanges

            let isActivelyEditing: Bool = if let noteId = currentSelectedNoteId {
                await NoteOperationCoordinator.shared.isNoteActivelyEditing(noteId)
            } else {
                false
            }

            let isPendingUpload: Bool = if let noteId = currentSelectedNoteId {
                UnifiedOperationQueue.shared.hasPendingUpload(for: noteId)
            } else {
                false
            }

            let localNotes = try localStorage.getAllLocalNotes()
            notes = localNotes

            loadFolders()

            if let noteId = currentSelectedNoteId,
               let updatedNote = localNotes.first(where: { $0.id == noteId })
            {
                let shouldSkipUpdate = hasUnsavedChanges || isActivelyEditing || isPendingUpload

                if shouldSkipUpdate {
                    LogService.shared.debug(.viewmodel, "同步后跳过更新选中笔记（同步保护生效）: \(noteId)")
                } else {
                    await MainActor.run {
                        self.selectedNote = updatedNote
                    }
                }
            } else {
                // 如果没有选中的笔记，尝试恢复上次选中的状态
                restoreLastSelectedState()
            }
        } catch {
            LogService.shared.error(.viewmodel, "同步后加载本地数据失败: \(error)")
        }
    }

    /// 更新文件夹计数
    private func updateFolderCounts() {
        let currentNotes = notes
        // 使用局部变量避免在循环中修改数组
        var updatedFolders = folders
        for i in 0 ..< updatedFolders.count {
            let folder = updatedFolders[i]

            if folder.id == "0" {
                // 所有笔记
                updatedFolders[i].count = currentNotes.count
            } else if folder.id == "starred" {
                // 收藏
                updatedFolders[i].count = currentNotes.count(where: { $0.isStarred })
            } else if folder.id == "2" {
                // 私密笔记文件夹：显示 folderId 为 "2" 的笔记
                updatedFolders[i].count = currentNotes.count(where: { $0.folderId == "2" })
            } else if folder.id == "uncategorized" {
                // 未分类文件夹：显示 folderId 为 "0" 或空的笔记
                updatedFolders[i].count = currentNotes.count(where: { $0.folderId == "0" || $0.folderId.isEmpty })
            } else {
                // 普通文件夹
                updatedFolders[i].count = currentNotes.count(where: { $0.folderId == folder.id })
            }
        }
        // 一次性更新数组
        folders = updatedFolders
    }

    /// 取消同步
    func cancelSync() {
        syncService.cancelSync()
        isSyncing = false
        syncStatusMessage = "同步已取消"
    }

    /// 重置同步状态
    func resetSyncStatus() {
        do {
            try syncService.resetSyncStatus()
            lastSyncTime = nil
            syncResult = nil
            errorMessage = "同步状态已重置"
        } catch {
            errorMessage = "重置同步状态失败: \(error.localizedDescription)"
        }
    }

    /// 获取同步状态摘要
    var syncStatusSummary: String {
        guard let lastSync = lastSyncTime else {
            return "从未同步"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        return "上次同步: \(formatter.string(from: lastSync))"
    }

    // MARK: - 云端数据加载（旧方法，保留兼容性）

    /// 从云端加载笔记（首次登录时使用，执行完整同步）
    func loadNotesFromCloud() async {
        guard service.isAuthenticated() else {
            errorMessage = "请先登录小米账号"
            return
        }

        // 检查是否已有同步状态
        let hasSyncStatus = localStorage.loadSyncStatus() != nil

        if hasSyncStatus {
            // 如果有同步状态，使用增量同步
            await performIncrementalSync()
        } else {
            // 如果没有同步状态（首次登录），使用完整同步
            await performFullSync()
        }
    }

    // MARK: - 笔记CRUD操作（统一接口）

    /// 创建笔记
    ///
    /// **统一接口**：推荐使用此方法创建笔记，而不是直接调用API
    ///
    /// **特性**：
    /// - 支持离线模式：如果离线，使用 NoteOperationCoordinator.createNoteOffline() 创建临时 ID 笔记
    /// - 自动处理ID变更：如果服务器返回新的ID，会自动更新本地笔记
    /// - 自动更新UI：创建后会自动更新笔记列表和文件夹计数
    ///
    /// **统一操作队列集成**：
    /// - 离线时使用 NoteOperationCoordinator.createNoteOffline() 生成临时 ID
    /// - 在线时直接调用 API 创建笔记
    ///
    /// - Parameter note: 要创建的笔记对象
    /// - Throws: 创建失败时抛出错误（网络错误、认证错误等）
    public func createNote(_ note: Note) async throws {
        // 检查是否离线或未认证
        if !isOnline || !service.isAuthenticated() {
            // 离线模式：使用 NoteOperationCoordinator 创建临时 ID 笔记
            do {
                let offlineNote = try await NoteOperationCoordinator.shared.createNoteOffline(
                    title: note.title,
                    content: note.content,
                    folderId: note.folderId
                )

                // 更新视图数据
                if !notes.contains(where: { $0.id == offlineNote.id }) {
                    notes.append(offlineNote)
                }
                selectedNote = offlineNote
                updateFolderCounts()

                LogService.shared.info(.viewmodel, "离线笔记创建成功，临时 ID: \(offlineNote.id.prefix(16))...")
            } catch {
                LogService.shared.error(.viewmodel, "离线笔记创建失败: \(error)")
                throw error
            }
            return
        }

        // 在线模式：先保存到本地，然后上传到云端
        try localStorage.saveNote(note)

        // 更新视图数据
        if !notes.contains(where: { $0.id == note.id }) {
            notes.append(note)
        }
        selectedNote = note
        updateFolderCounts()

        // 在线模式：尝试上传到云端
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let response = try await service.createNote(
                title: note.title,
                content: note.content,
                folderId: note.folderId
            )

            // 解析响应：响应格式为 {"code": 0, "data": {"entry": {...}}}
            var noteId: String?
            var tag: String?
            var entryData: [String: Any]?

            // 检查响应格式
            if let code = response["code"] as? Int, code == 0 {
                if let data = response["data"] as? [String: Any],
                   let entry = data["entry"] as? [String: Any]
                {
                    noteId = entry["id"] as? String
                    tag = entry["tag"] as? String
                    entryData = entry
                }
            } else {
                noteId = response["id"] as? String
                tag = response["tag"] as? String
                entryData = response
            }

            if let noteId, let tag, !tag.isEmpty {
                // 获取服务器返回的 folderId（如果有）
                let serverFolderId: String = if let entryData, let folderIdValue = entryData["folderId"] {
                    if let folderIdInt = folderIdValue as? Int {
                        String(folderIdInt)
                    } else if let folderIdStr = folderIdValue as? String {
                        folderIdStr
                    } else {
                        note.folderId
                    }
                } else {
                    note.folderId
                }

                // 更新 rawData，包含完整的 entry 数据
                var updatedRawData = note.rawData ?? [:]
                if let entryData {
                    for (key, value) in entryData {
                        updatedRawData[key] = value
                    }
                }
                updatedRawData["tag"] = tag

                // 如果本地笔记的 ID 与服务器返回的不同，需要创建新笔记并删除旧的
                if note.id != noteId {
                    // 创建新的笔记对象（使用服务器返回的 ID 和 folderId，保留所有字段）
                    let updatedNote = Note(
                        id: noteId,
                        title: note.title,
                        content: note.content,
                        folderId: serverFolderId, // 使用服务器返回的 folderId
                        isStarred: note.isStarred,
                        createdAt: note.createdAt,
                        updatedAt: note.updatedAt,
                        tags: note.tags,
                        rawData: updatedRawData,
                        snippet: note.snippet,
                        colorId: note.colorId,
                        subject: note.subject,
                        alertDate: note.alertDate,
                        type: note.type,
                        serverTag: note.serverTag,
                        status: note.status,
                        settingJson: note.settingJson,
                        extraInfoJson: note.extraInfoJson
                    )

                    // 删除旧的本地文件
                    try? localStorage.deleteNote(noteId: note.id)

                    // 更新笔记列表
                    if let index = notes.firstIndex(where: { $0.id == note.id }) {
                        notes.remove(at: index)
                        notes.append(updatedNote)
                    }

                    // 保存新笔记
                    try localStorage.saveNote(updatedNote)

                    // 更新选中状态
                    selectedNote = updatedNote
                } else {
                    // ID 相同，更新现有笔记（保留所有字段）
                    let updatedNote = Note(
                        id: note.id,
                        title: note.title,
                        content: note.content,
                        folderId: note.folderId,
                        isStarred: note.isStarred,
                        createdAt: note.createdAt,
                        updatedAt: note.updatedAt,
                        tags: note.tags,
                        rawData: updatedRawData,
                        snippet: note.snippet,
                        colorId: note.colorId,
                        subject: note.subject,
                        alertDate: note.alertDate,
                        type: note.type,
                        serverTag: note.serverTag,
                        status: note.status,
                        settingJson: note.settingJson,
                        extraInfoJson: note.extraInfoJson
                    )

                    // 更新笔记列表
                    if let index = notes.firstIndex(where: { $0.id == note.id }) {
                        if index < notes.count {
                            notes[index] = updatedNote
                        }
                    }

                    // 保存更新后的笔记
                    try localStorage.saveNote(updatedNote)

                    // 更新选中状态
                    selectedNote = updatedNote
                }

                // 更新文件夹计数
                updateFolderCounts()
            } else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "创建笔记失败：服务器返回无效响应"])
            }
        } catch {
            // 使用统一的错误处理和离线队列添加逻辑
            _ = handleErrorAndAddToOfflineQueue(
                error: error,
                operationType: .noteCreate,
                noteId: note.id,
                operationData: [
                    "title": note.title,
                    "content": note.content,
                    "folderId": note.folderId,
                ],
                context: "创建笔记"
            )
            // 不设置 errorMessage，避免弹窗提示
        }
    }

    /// 更新笔记
    ///
    /// **统一接口**：推荐使用此方法更新笔记，而不是直接调用API
    ///
    /// **特性**：
    /// - 支持离线模式：如果离线，会保存到本地并添加到 UnifiedOperationQueue
    /// - 自动获取最新tag：更新前会从服务器获取最新的tag，避免并发冲突
    /// - 自动更新UI：更新后会自动更新笔记列表
    ///
    /// **统一操作队列集成**：
    /// - 使用 NoteOperationCoordinator 进行保存
    /// - 自动创建 cloudUpload 操作到 UnifiedOperationQueue
    /// - 网络可用时立即处理上传
    ///
    ///
    /// - Parameter note: 要更新的笔记对象
    /// - Throws: 更新失败时抛出错误（网络错误、认证错误等）
    func updateNote(_ note: Note) async throws {
        let noteToSave = mergeWithLocalData(note)

        let saveResult = await NoteOperationCoordinator.shared.saveNote(noteToSave)

        switch saveResult {
        case .success:
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = noteToSave
            }
            if selectedNote?.id == note.id {
                selectedNote = noteToSave
            }
        case let .failure(error):
            LogService.shared.error(.viewmodel, "保存笔记失败: \(error)")
            throw error
        }

        guard isOnline, service.isAuthenticated() else { return }
    }

    private func mergeWithLocalData(_ note: Note) -> Note {
        guard let existingNote = try? localStorage.loadNote(noteId: note.id),
              let existingRawData = existingNote.rawData
        else {
            return note
        }

        var mergedRawData = existingRawData
        if let newRawData = note.rawData {
            for (key, value) in newRawData {
                mergedRawData[key] = value
            }
        }

        // 特别处理 setting.data (图片)
        if let existingSetting = existingRawData["setting"] as? [String: Any],
           let existingSettingData = existingSetting["data"] as? [[String: Any]],
           !existingSettingData.isEmpty
        {
            var mergedSetting = mergedRawData["setting"] as? [String: Any] ?? [:]
            mergedSetting["data"] = existingSettingData
            mergedRawData["setting"] = mergedSetting
        }

        var merged = note
        merged.rawData = mergedRawData
        // 确保保留现有的内容，除非传入的笔记有更新的
        // 注意：Note模型中没有htmlContent属性，这里保留注释但移除相关代码
        return merged
    }

    private func applyLocalUpdate(_ note: Note) async throws {
        // 立即物理保存
        try localStorage.saveNote(note)

        // 更新内存列表
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }

        // 守卫更新 selectedNote 引用：只有当用户依然停留在当个笔记时才更新
        // 这样可以避免用户切换笔记后，旧任务的完成把 UI 拉回去
        if selectedNote?.id == note.id {
            selectedNote = note
        }
    }

    private func queueOfflineUpdate(_ note: Note) {
        let data: [String: Any] = [
            "title": note.title,
            "content": note.content,
            "folderId": note.folderId,
        ]
        _ = addOperationToOfflineQueue(type: .cloudUpload, noteId: note.id, data: data)
    }

    // MARK: - 精确更新方法（视图状态同步）

    /// 原地更新单个笔记（不替换整个数组）
    ///
    /// 此方法只更新 notes 数组中对应笔记的属性，不会触发整个数组的重新发布。
    /// 这样可以避免不必要的视图重建，保持选择状态不变。
    ///
    /// - Parameter note: 更新后的笔记对象
    /// - Returns: 是否成功更新（如果笔记不存在于数组中则返回 false）
    ///
    @discardableResult
    public func updateNoteInPlace(_ note: Note) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else {
            return false
        }

        notes[index] = note

        if selectedNote?.id == note.id {
            selectedNote = note
        }

        return true
    }

    /// 批量更新笔记（带动画）
    ///
    /// 支持批量更新多个笔记，使用 withAnimation 包装更新操作以提供平滑的动画效果。
    /// 适用于笔记排序位置变化等需要动画过渡的场景。
    ///
    /// - Parameter updates: 更新操作列表，每个元素包含笔记ID和更新闭包
    ///
    public func batchUpdateNotes(_ updates: [(noteId: String, update: (inout Note) -> Void)]) {
        guard !updates.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            for (noteId, update) in updates {
                if let index = notes.firstIndex(where: { $0.id == noteId }) {
                    update(&notes[index])

                    if selectedNote?.id == noteId {
                        selectedNote = notes[index]
                    }
                }
            }
        }
    }

    /// 更新笔记的时间戳（带动画）
    ///
    /// 专门用于更新笔记的 updatedAt 时间戳，会触发列表重新排序动画。
    ///
    /// - Parameters:
    ///   - noteId: 要更新的笔记ID
    ///   - timestamp: 新的时间戳
    /// - Returns: 是否成功更新
    ///
    @discardableResult
    public func updateNoteTimestamp(_ noteId: String, timestamp: Date) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return false }

        withAnimation(.easeInOut(duration: 0.3)) {
            notes[index].updatedAt = timestamp

            if selectedNote?.id == noteId {
                selectedNote = notes[index]
            }
        }

        return true
    }

    private func performCloudUpdateWithRetry(_ note: Note, retryOnConflict: Bool = true) async throws {
        var existingTag = note.rawData?["tag"] as? String ?? ""
        let originalCreateDate = note.rawData?["createDate"] as? Int

        // 如果没有 tag，先 fetch 一次（通常是新建笔记或者是从 snippet 转换来的）
        if existingTag.isEmpty {
            let details = try await service.fetchNoteDetails(noteId: note.id)
            if let entry = extractEntry(from: details), let tag = entry["tag"] as? String {
                existingTag = tag
            }
        }

        // 提取图片信息
        let imageData = (note.rawData?["setting"] as? [String: Any])?["data"] as? [[String: Any]]
        nonisolated(unsafe) let unsafeImageData = imageData

        let response = try await service.updateNote(
            noteId: note.id,
            title: note.title,
            content: note.content,
            folderId: note.folderId,
            existingTag: existingTag,
            originalCreateDate: originalCreateDate,
            imageData: unsafeImageData
        )

        let code = response["code"] as? Int ?? -1

        if code == 10017, retryOnConflict {
            let details = try await service.fetchNoteDetails(noteId: note.id)
            if let entry = extractEntry(from: details) {
                var updatedWithNewTag = note
                var raw = note.rawData ?? [:]
                for (k, v) in entry {
                    raw[k] = v
                }
                updatedWithNewTag.rawData = raw
                try await performCloudUpdateWithRetry(updatedWithNewTag, retryOnConflict: false)
                return
            }
        }

        if code == 0 {
            if let entry = extractEntry(from: response) {
                var updatedNote = note
                var updatedRawData = updatedNote.rawData ?? [:]
                for (key, value) in entry {
                    updatedRawData[key] = value
                }

                if let modifyDate = entry["modifyDate"] as? Int {
                    updatedNote.updatedAt = Date(timeIntervalSince1970: TimeInterval(modifyDate) / 1000)
                }
                updatedNote.rawData = updatedRawData

                // 再次应用本地更新（包含 ID 守卫判断）
                try await applyLocalUpdate(updatedNote)
            }
        } else {
            let message = response["message"] as? String ?? "更新笔记失败"
            LogService.shared.error(.viewmodel, "更新笔记失败，code: \(code), message: \(message)")
            throw NSError(domain: "MiNote", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    /// 统一处理更新时的错误（内部方法）
    private func handleUpdateError(_ error: Error, for note: Note) {
        // 使用 ErrorRecoveryService 统一处理错误
        let operationData: [String: Any] = [
            "title": note.title,
            "content": note.content,
            "folderId": note.folderId,
            "tag": note.rawData?["tag"] as? String ?? note.id,
        ]

        // 将操作数据编码为 Data
        guard let data = try? JSONSerialization.data(withJSONObject: operationData, options: []) else {
            LogService.shared.error(.viewmodel, "无法编码操作数据，笔记ID: \(note.id)")
            return
        }

        let result = ErrorRecoveryService.shared.handleNetworkError(
            operation: .cloudUpload,
            noteId: note.id,
            data: data,
            error: error,
            context: "更新笔记"
        )

        switch result {
        case let .addedToQueue(message):
            LogService.shared.debug(.viewmodel, "\(message)，笔记ID: \(note.id)")
        case let .noRetry(message):
            LogService.shared.warning(.viewmodel, "更新失败（不重试）: \(message)，笔记ID: \(note.id)")
        case let .permanentlyFailed(message):
            LogService.shared.error(.viewmodel, "更新永久失败: \(message)，笔记ID: \(note.id)")
            errorMessage = message
            // 3秒后清除错误消息
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.errorMessage = nil
            }
        }
    }

    /// 确保笔记有完整内容
    ///
    /// 如果笔记内容为空（只有snippet），会从服务器获取完整内容
    /// 用于延迟加载，提高列表加载速度
    ///
    /// - Parameter note: 要检查的笔记对象
    ///
    /// **注意**：此方法在更新笔记时会尽量避免触发不必要的排序变化，
    /// 以防止笔记在列表中错误移动。
    ///
    func ensureNoteHasFullContent(_ note: Note) async {
        if !note.content.isEmpty { return }

        if note.rawData?["snippet"] == nil { return }

        LogService.shared.debug(.viewmodel, "笔记内容为空，获取完整内容: \(note.id)")

        do {
            let noteDetails = try await service.fetchNoteDetails(noteId: note.id)

            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                var updatedNote = notes[index]

                let originalUpdatedAt = updatedNote.updatedAt
                let originalContent = updatedNote.content
                let originalTitle = updatedNote.title

                updatedNote.updateContent(from: noteDetails)

                let contentActuallyChanged = hasContentActuallyChanged(
                    currentContent: updatedNote.content,
                    savedContent: originalContent,
                    currentTitle: updatedNote.title,
                    originalTitle: originalTitle
                )

                if !contentActuallyChanged {
                    updatedNote.updatedAt = originalUpdatedAt
                }

                try localStorage.saveNote(updatedNote)

                notes[index] = updatedNote

                if selectedNote?.id == note.id {
                    selectedNote = updatedNote
                }

                LogService.shared.debug(
                    .viewmodel,
                    "已获取并更新笔记完整内容: \(note.id), 内容长度: \(updatedNote.content.count), 时间戳决策: \(contentActuallyChanged ? "更新" : "保持")"
                )
            }
        } catch {
            LogService.shared.error(.viewmodel, "获取笔记完整内容失败: \(error.localizedDescription)")
        }
    }

    /// 检查内容是否真正发生变化
    ///
    /// 通过标准化内容比较（去除空白字符差异）来准确判断内容是否真正变化
    ///
    /// - Parameters:
    ///   - currentContent: 当前内容
    ///   - savedContent: 保存的内容
    ///   - currentTitle: 当前标题
    ///   - originalTitle: 原始标题
    /// - Returns: 如果内容或标题发生实际变化返回 true，否则返回 false
    ///
    private func hasContentActuallyChanged(currentContent: String, savedContent: String, currentTitle: String, originalTitle: String) -> Bool {
        let normalizedCurrent = XMLNormalizer.shared.normalize(currentContent)
        let normalizedSaved = XMLNormalizer.shared.normalize(savedContent)

        let contentChanged = normalizedCurrent != normalizedSaved
        let titleChanged = currentTitle != originalTitle

        return contentChanged || titleChanged
    }

    func deleteNote(_ note: Note) {
        // 临时 ID 笔记被删除时取消 noteCreate 操作
        if NoteOperation.isTemporaryId(note.id) {
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                if index < notes.count { notes.remove(at: index) }
                if let folderIndex = folders.firstIndex(where: { $0.id == note.folderId }) {
                    folders[folderIndex].count = max(0, folders[folderIndex].count - 1)
                }
                if selectedNote?.id == note.id { selectedNote = nil }
            }

            Task {
                do {
                    try await NoteOperationCoordinator.shared.deleteTemporaryNote(note.id)
                } catch {
                    LogService.shared.error(.viewmodel, "临时 ID 笔记删除失败: \(error)")
                }
            }
            return
        }

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            if index < notes.count { notes.remove(at: index) }
            if let folderIndex = folders.firstIndex(where: { $0.id == note.folderId }) {
                folders[folderIndex].count = max(0, folders[folderIndex].count - 1)
            }
            if selectedNote?.id == note.id { selectedNote = nil }
        }

        do {
            try localStorage.deleteNote(noteId: note.id)
        } catch {
            LogService.shared.error(.viewmodel, "删除本地笔记失败: \(error)")
        }

        guard isOnline, service.isAuthenticated() else {
            let tag = note.rawData?["tag"] as? String ?? note.id
            let operationData: [String: Any] = ["tag": tag, "purge": false]

            guard let data = try? JSONSerialization.data(withJSONObject: operationData) else {
                LogService.shared.error(.viewmodel, "编码删除操作数据失败，笔记ID: \(note.id)")
                return
            }

            let operation = NoteOperation(
                type: .cloudDelete,
                noteId: note.id,
                data: data,
                status: .pending,
                priority: NoteOperation.calculatePriority(for: .cloudDelete)
            )

            do {
                try unifiedQueue.enqueue(operation)
            } catch {
                LogService.shared.error(.viewmodel, "添加删除操作到队列失败: \(error)")
            }

            return
        }

        Task {
            do {
                var finalTag = note.rawData?["tag"] as? String ?? note.id

                do {
                    let noteDetails = try await service.fetchNoteDetails(noteId: note.id)
                    if let data = noteDetails["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any],
                       let latestTag = entry["tag"] as? String, !latestTag.isEmpty
                    {
                        finalTag = latestTag
                    }
                } catch {
                    LogService.shared.debug(.viewmodel, "获取最新 tag 失败，使用本地 tag: \(finalTag)")
                }

                if finalTag.isEmpty { finalTag = note.id }

                _ = try await service.deleteNote(noteId: note.id, tag: finalTag, purge: false)
            } catch {
                LogService.shared.error(.viewmodel, "云端删除失败: \(error)")

                let tag = note.rawData?["tag"] as? String ?? note.id
                let operationData: [String: Any] = ["tag": tag, "purge": false]

                guard let data = try? JSONSerialization.data(withJSONObject: operationData) else {
                    LogService.shared.error(.viewmodel, "编码删除操作数据失败，笔记ID: \(note.id)")
                    return
                }

                let result = ErrorRecoveryService.shared.handleNetworkError(
                    operation: .cloudDelete,
                    noteId: note.id,
                    data: data,
                    error: error,
                    context: "删除笔记"
                )

                switch result {
                case let .addedToQueue(message):
                    LogService.shared.debug(.viewmodel, "\(message)，笔记ID: \(note.id)")
                case let .noRetry(message):
                    LogService.shared.warning(.viewmodel, "删除失败（不重试）: \(message)，笔记ID: \(note.id)")
                case let .permanentlyFailed(message):
                    LogService.shared.error(.viewmodel, "删除永久失败: \(message)，笔记ID: \(note.id)")
                    await MainActor.run {
                        self.errorMessage = message
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            self?.errorMessage = nil
                        }
                    }
                }
            }
        }
    }

    public func toggleStar(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            if index < notes.count {
                notes[index].isStarred.toggle()
            }

            // 更新文件夹计数
            if note.isStarred {
                // 从收藏变为非收藏
                if let folderIndex = folders.firstIndex(where: { $0.id == "starred" }) {
                    folders[folderIndex].count = max(0, folders[folderIndex].count - 1)
                }
            } else {
                // 从非收藏变为收藏
                if let folderIndex = folders.firstIndex(where: { $0.id == "starred" }) {
                    folders[folderIndex].count += 1
                }
            }

            // 如果更新的是当前选中的笔记，更新选择
            if selectedNote?.id == note.id {
                selectedNote = notes[index]
            }
        }
    }

    /// 设置文件夹的排序方式
    ///
    /// - Parameters:
    ///   - folder: 要设置排序方式的文件夹
    ///   - sortOrder: 排序方式
    func setFolderSortOrder(_ folder: Folder, sortOrder: NoteSortOrder) {
        folderSortOrders[folder.id] = sortOrder
        // 保存到 UserDefaults
        let defaults = UserDefaults.standard
        if let encoded = try? JSONEncoder().encode(folderSortOrders),
           let jsonString = String(data: encoded, encoding: .utf8)
        {
            defaults.set(jsonString, forKey: "folderSortOrders")
        }
    }

    /// 获取文件夹的排序方式
    ///
    /// - Parameter folder: 文件夹
    /// - Returns: 排序方式，如果没有设置则返回 nil
    func getFolderSortOrder(_ folder: Folder) -> NoteSortOrder? {
        folderSortOrders[folder.id]
    }

    /// 验证私密笔记密码
    ///
    /// - Parameter password: 输入的密码
    /// - Returns: 如果密码正确返回 true，否则返回 false
    func verifyPrivateNotesPassword(_ password: String) -> Bool {
        let isValid = PrivateNotesPasswordManager.shared.verifyPassword(password)
        if isValid {
            isPrivateNotesUnlocked = true
        }
        return isValid
    }

    /// 解锁私密笔记（用于跳过密码验证，例如未设置密码时或 Touch ID 验证成功后）
    func unlockPrivateNotes() {
        isPrivateNotesUnlocked = true
    }

    /// 处理私密笔记密码验证取消
    func handlePrivateNotesPasswordCancel() {
        isPrivateNotesUnlocked = false
        showPrivateNotesPasswordDialog = false
    }

    func selectFolder(_ folder: Folder?) {
        let oldFolder = selectedFolder

        // 如果文件夹没有变化，不需要处理
        if oldFolder?.id == folder?.id {
            return
        }

        // 先设置选中的文件夹，这样验证界面才能显示
        selectedFolder = folder

        // 同步更新 coordinator 的状态（不触发 coordinator 的选择逻辑，避免循环）
        // coordinator 的状态会在下次调用 coordinator.selectFolder 时同步

        // 如果切换到私密笔记文件夹，检查密码
        if let folder, folder.id == "2" {
            // 检查是否已设置密码
            if PrivateNotesPasswordManager.shared.hasPassword() {
                // 每次切换到私密笔记文件夹时，都需要重新验证
                // 重置解锁状态，强制用户重新验证
                isPrivateNotesUnlocked = false
                selectedNote = nil // 清空选中的笔记
            } else {
                // 未设置密码，直接允许访问
                isPrivateNotesUnlocked = true
            }
        } else {
            // 切换到其他文件夹，重置解锁状态
            isPrivateNotesUnlocked = false
        }

        // 获取新文件夹中的笔记列表
        let notesInNewFolder: [Note] = if let folder {
            if folder.id == "starred" {
                notes.filter(\.isStarred)
            } else if folder.id == "0" {
                notes
            } else if folder.id == "2" {
                // 私密笔记文件夹：显示 folderId 为 "2" 的笔记
                notes.filter { $0.folderId == "2" }
            } else if folder.id == "uncategorized" {
                notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }
            } else {
                notes.filter { $0.folderId == folder.id }
            }
        } else {
            []
        }

        // 检查当前选中的笔记是否在新文件夹中
        if let currentNote = selectedNote {
            let isNoteInNewFolder = notesInNewFolder.contains { $0.id == currentNote.id }

            if isNoteInNewFolder {
                // 当前笔记在新文件夹中，保持不变
                // 但需要确保使用最新的笔记对象（从 notesInNewFolder 中获取）
                if let updatedNote = notesInNewFolder.first(where: { $0.id == currentNote.id }) {
                    selectedNote = updatedNote
                }
            } else {
                // 当前笔记不在新文件夹中，选择新文件夹的第一个笔记
                selectedNote = notesInNewFolder.first
            }
        } else {
            // 当前没有选中的笔记，选择新文件夹的第一个笔记
            selectedNote = notesInNewFolder.first
        }
    }

    /// 通过状态协调器选择文件夹
    ///
    /// 使用 ViewStateCoordinator 进行状态管理，确保三个视图之间的状态同步
    ///
    ///
    /// - Parameter folder: 要选择的文件夹
    public func selectFolderWithCoordinator(_ folder: Folder?) {
        Task {
            await stateCoordinator.selectFolder(folder)
            // 同步 coordinator 的状态到 ViewModel
            syncStateFromCoordinator()
        }
    }

    /// 通过状态协调器选择笔记
    ///
    /// 使用 ViewStateCoordinator 进行状态管理，确保三个视图之间的状态同步
    ///
    ///
    /// **统一操作队列集成**：
    /// - 切换笔记时设置活跃编辑状态
    /// - 切换前保存当前笔记（如果有未保存的更改）
    ///
    /// **死循环防护**（Spec 60）：
    /// - 使用 `isSwitchingNote` 标志防止切换过程中被打断
    /// - 使用 `defer` 确保标志正确重置
    ///
    /// - Parameter note: 要选择的笔记
    public func selectNoteWithCoordinator(_ note: Note?) {
        guard !isSwitchingNote else { return }

        if let lastTime = lastSwitchTime {
            let timeSinceLastSwitch = Date().timeIntervalSince(lastTime)
            if timeSinceLastSwitch < switchDebounceInterval { return }
        }

        lastSwitchTime = Date()
        isSwitchingNote = true
        defer { isSwitchingNote = false }

        Task {
            let previousNoteId = selectedNote?.id

            if let prevId = previousNoteId,
               let prevNote = notes.first(where: { $0.id == prevId }),
               nativeEditorContext.hasUnsavedChanges
            {
                do {
                    try await NoteOperationCoordinator.shared.saveNoteImmediately(prevNote)
                } catch {
                    LogService.shared.warning(.viewmodel, "切换笔记前保存失败: \(error)")
                }
            }

            await NoteOperationCoordinator.shared.setActiveEditingNote(note?.id)
            await stateCoordinator.selectNote(note)
            syncStateFromCoordinator()
        }
    }

    /// 从 coordinator 同步状态到 ViewModel
    ///
    /// 将 ViewStateCoordinator 的选择状态同步到 ViewModel 的 @Published 属性
    /// 这样可以触发 UI 更新
    private func syncStateFromCoordinator() {
        // 只有当状态真正变化时才更新，避免不必要的 UI 刷新
        if selectedFolder?.id != stateCoordinator.selectedFolder?.id {
            selectedFolder = stateCoordinator.selectedFolder
        }
        if selectedNote?.id != stateCoordinator.selectedNote?.id {
            selectedNote = stateCoordinator.selectedNote
        }
    }

    /// 创建文件夹
    ///
    /// **特性**：
    /// - 支持离线模式：如果离线，会保存到本地并添加到离线队列
    /// - 自动处理ID变更：如果服务器返回新的ID，会自动更新本地文件夹
    ///
    /// - Parameter name: 文件夹名称
    /// - Throws: 创建失败时抛出错误
    public func createFolder(name: String) async throws -> String {
        // 生成临时文件夹ID（离线时使用）
        let tempFolderId = UUID().uuidString

        // 创建本地文件夹对象
        let newFolder = Folder(
            id: tempFolderId,
            name: name,
            count: 0,
            isSystem: false,
            createdAt: Date()
        )

        // 先保存到本地（无论在线还是离线）
        let systemFolders = folders.filter(\.isSystem)
        var userFolders = folders.filter { !$0.isSystem }
        userFolders.append(newFolder)
        try localStorage.saveFolders(userFolders)

        // 更新视图数据（系统文件夹在前）
        folders = systemFolders + userFolders

        // 如果离线或未认证，添加到统一操作队列
        if !isOnline || !service.isAuthenticated() {
            let operationData = try JSONEncoder().encode([
                "name": name,
            ])
            let operation = NoteOperation(
                type: .folderCreate,
                noteId: tempFolderId, // 对于文件夹操作，使用 folderId
                data: operationData,
                status: .pending,
                priority: NoteOperation.calculatePriority(for: .folderCreate)
            )
            try unifiedQueue.enqueue(operation)
            loadFolders()
            return tempFolderId
        }

        // 在线模式：尝试上传到云端
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let response = try await service.createFolder(name: name)

            // 解析响应：响应格式为 {"code": 0, "data": {"entry": {...}}}
            var folderId: String?
            var folderName: String?
            var entryData: [String: Any]?

            // 检查响应格式
            if let code = response["code"] as? Int, code == 0 {
                if let data = response["data"] as? [String: Any],
                   let entry = data["entry"] as? [String: Any]
                {
                    // 处理 ID（可能是 String 或 Int）
                    if let idString = entry["id"] as? String {
                        folderId = idString
                    } else if let idInt = entry["id"] as? Int {
                        folderId = String(idInt)
                    }
                    folderName = entry["subject"] as? String ?? name
                    entryData = entry
                }
            }

            if let folderId, let folderName {
                // 如果服务器返回的 ID 与本地不同，需要更新
                if tempFolderId != folderId {
                    // 1. 更新所有使用旧文件夹ID的笔记，将它们的 folder_id 更新为新ID
                    try DatabaseService.shared.updateNotesFolderId(oldFolderId: tempFolderId, newFolderId: folderId)

                    // 2. 更新内存中的笔记列表
                    notes = notes.map { note in
                        var updatedNote = note
                        if updatedNote.folderId == tempFolderId {
                            updatedNote.folderId = folderId
                        }
                        return updatedNote
                    }

                    // 3. 删除数据库中的旧文件夹记录
                    try DatabaseService.shared.deleteFolder(folderId: tempFolderId)

                    // 4. 创建新的文件夹对象（使用服务器返回的 ID）
                    let updatedFolder = Folder(
                        id: folderId,
                        name: folderName,
                        count: 0,
                        isSystem: false,
                        createdAt: Date()
                    )

                    // 5. 更新文件夹列表（保持系统文件夹在前）
                    let systemFolders = folders.filter(\.isSystem)
                    var userFolders = folders.filter { !$0.isSystem }

                    if let index = userFolders.firstIndex(where: { $0.id == tempFolderId }) {
                        if index < userFolders.count {
                            userFolders.remove(at: index)
                            userFolders.append(updatedFolder)
                        }
                    }

                    folders = systemFolders + userFolders

                    // 6. 保存到本地存储
                    try localStorage.saveFolders(userFolders)
                } else {
                    // ID 相同，更新现有文件夹
                    let updatedFolder = Folder(
                        id: folderId,
                        name: folderName,
                        count: 0,
                        isSystem: false,
                        createdAt: Date()
                    )

                    // 更新文件夹列表（保持系统文件夹在前）
                    let systemFolders = folders.filter(\.isSystem)
                    var userFolders = folders.filter { !$0.isSystem }

                    if let index = userFolders.firstIndex(where: { $0.id == tempFolderId }) {
                        userFolders[index] = updatedFolder
                    }

                    folders = systemFolders + userFolders

                    // 保存到本地存储
                    try localStorage.saveFolders(userFolders)
                }
            } else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "创建文件夹失败：服务器返回无效响应"])
            }

            // 返回文件夹ID
            return folderId ?? tempFolderId
        } catch {
            // 使用统一的错误处理和离线队列添加逻辑
            _ = handleErrorAndAddToOfflineQueue(
                error: error,
                operationType: .folderCreate,
                noteId: tempFolderId,
                operationData: [
                    "name": name,
                ],
                context: "创建文件夹"
            )
            // 不设置 errorMessage，避免弹窗提示
            // 返回临时文件夹ID
            return tempFolderId
        }
    }

    /// 切换文件夹置顶状态
    func toggleFolderPin(_ folder: Folder) async throws {
        // 先更新本地（无论在线还是离线）
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            if index < folders.count {
                folders[index].isPinned.toggle()
                try? localStorage.saveFolders(folders.filter { !$0.isSystem })
            }
            // 确保 selectedFolder 也更新
            if selectedFolder?.id == folder.id {
                selectedFolder?.isPinned.toggle()
            }
            // 重新加载文件夹列表以更新排序
            loadFolders()
        } else {
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
        }

        // 如果离线或未认证，保存到本地即可（置顶状态是本地功能，不需要同步到云端）
        if !isOnline || !service.isAuthenticated() {
            return
        }
    }

    /// 重命名文件夹
    func renameFolder(_ folder: Folder, newName: String) async throws {
        // 先更新本地（无论在线还是离线）
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            let currentFolder = folders[index]

            // 更新 rawData 中的 subject 字段
            var updatedRawData = currentFolder.rawData ?? [:]
            updatedRawData["subject"] = newName

            // 创建新的 Folder 实例（而不是修改现有实例），确保 SwiftUI 检测到变化
            let updatedFolder = Folder(
                id: currentFolder.id,
                name: newName,
                count: currentFolder.count,
                isSystem: currentFolder.isSystem,
                isPinned: currentFolder.isPinned,
                createdAt: currentFolder.createdAt,
                rawData: updatedRawData
            )

            // 重新创建数组以确保 SwiftUI 检测到变化
            var updatedFolders = folders
            updatedFolders[index] = updatedFolder
            folders = updatedFolders

            try localStorage.saveFolders(folders.filter { !$0.isSystem })

            // 确保 selectedFolder 也更新（使用新的 updatedFolder 实例）
            if selectedFolder?.id == folder.id {
                selectedFolder = updatedFolder
            }
        } else {
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
        }

        if !isOnline || !service.isAuthenticated() {
            let operationData = try JSONEncoder().encode([
                "oldName": folder.name,
                "newName": newName,
            ])
            let operation = NoteOperation(
                type: .folderRename,
                noteId: folder.id,
                data: operationData,
                status: .pending,
                priority: NoteOperation.calculatePriority(for: .folderRename)
            )
            try unifiedQueue.enqueue(operation)
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var existingTag = folder.rawData?["tag"] as? String ?? ""
            var originalCreateDate = folder.rawData?["createDate"] as? Int

            do {
                let folderDetails = try await service.fetchFolderDetails(folderId: folder.id)
                if let data = folderDetails["data"] as? [String: Any],
                   let entry = data["entry"] as? [String: Any]
                {
                    if let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                        existingTag = latestTag
                    }
                    if let latestCreateDate = entry["createDate"] as? Int {
                        originalCreateDate = latestCreateDate
                    }
                }
            } catch {
                LogService.shared.debug(.viewmodel, "获取最新文件夹信息失败: \(error)，使用本地 tag")
            }

            if existingTag.isEmpty { existingTag = folder.id }

            let response = try await service.renameFolder(
                folderId: folder.id,
                newName: newName,
                existingTag: existingTag,
                originalCreateDate: originalCreateDate
            )

            let code = response["code"] as? Int
            let isSuccess = (code == 0) || (code == nil && response["result"] as? String == "ok")

            if isSuccess {
                guard let index = folders.firstIndex(where: { $0.id == folder.id }) else {
                    throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
                }

                let currentFolder = folders[index]
                var updatedRawData: [String: Any] = currentFolder.rawData ?? [:]

                if let data = response["data"] as? [String: Any] {
                    updatedRawData = updatedRawData.merging(data) { _, new in new }
                }
                if let entry = response["entry"] as? [String: Any] {
                    updatedRawData = updatedRawData.merging(entry) { _, new in new }
                }

                let tagValue = extractTag(from: response, fallbackTag: existingTag)
                updatedRawData["tag"] = tagValue
                updatedRawData["subject"] = newName
                updatedRawData["id"] = folder.id
                updatedRawData["type"] = "folder"

                let updatedFolder = Folder(
                    id: currentFolder.id,
                    name: newName,
                    count: currentFolder.count,
                    isSystem: currentFolder.isSystem,
                    isPinned: currentFolder.isPinned,
                    createdAt: currentFolder.createdAt,
                    rawData: updatedRawData
                )

                var updatedFolders = folders
                updatedFolders[index] = updatedFolder
                folders = updatedFolders

                if selectedFolder?.id == folder.id {
                    selectedFolder = updatedFolder
                }

                try localStorage.saveFolders(folders.filter { !$0.isSystem })
                LogService.shared.info(.viewmodel, "文件夹重命名成功: \(folder.id) -> \(newName)")
            } else {
                let errorCode = code ?? -1
                let message = response["description"] as? String ?? response["message"] as? String ?? "重命名文件夹失败"
                LogService.shared.error(.viewmodel, "重命名文件夹失败，code: \(errorCode), message: \(message)")
                throw NSError(domain: "MiNote", code: errorCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
        } catch {
            _ = handleErrorAndAddToOfflineQueue(
                error: error,
                operationType: .folderRename,
                noteId: folder.id,
                operationData: [
                    "oldName": folder.name,
                    "newName": newName,
                ],
                context: "重命名文件夹"
            )
        }
    }

    /// 删除文件夹
    func deleteFolder(_ folder: Folder) async throws {
        if !isOnline || !service.isAuthenticated() {
            do {
                try LocalStorageService.shared.deleteFolderImageDirectory(folderId: folder.id)
            } catch {
                LogService.shared.warning(.viewmodel, "删除文件夹图片目录失败: \(error.localizedDescription)")
            }

            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders.remove(at: index)
                try DatabaseService.shared.deleteFolder(folderId: folder.id)
                try localStorage.saveFolders(folders.filter { !$0.isSystem })
                if selectedFolder?.id == folder.id { selectedFolder = nil }
            }

            let operationDict: [String: Any] = ["folderId": folder.id, "purge": false]
            guard let operationData = try? JSONSerialization.data(withJSONObject: operationDict) else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法序列化删除操作数据"])
            }

            let operation = NoteOperation(
                type: .folderDelete,
                noteId: folder.id,
                data: operationData,
                status: .pending,
                priority: NoteOperation.calculatePriority(for: .folderDelete)
            )
            try unifiedQueue.enqueue(operation)

            loadFolders()
            updateFolderCounts()
            return
        }

        var finalTag: String?

        do {
            let folderDetails = try await service.fetchFolderDetails(folderId: folder.id)
            if let data = folderDetails["data"] as? [String: Any],
               let entry = data["entry"] as? [String: Any],
               let latestTag = entry["tag"] as? String, !latestTag.isEmpty
            {
                finalTag = latestTag
            } else if let data = folderDetails["data"] as? [String: Any],
                      let dataTag = data["tag"] as? String, !dataTag.isEmpty
            {
                finalTag = dataTag
            }
        } catch {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法获取文件夹 tag，删除失败: \(error.localizedDescription)"])
        }

        guard let tag = finalTag, !tag.isEmpty else {
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法从服务器获取文件夹 tag，删除失败"])
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await service.deleteFolder(folderId: folder.id, tag: tag, purge: false)
        } catch {
            LogService.shared.error(.viewmodel, "云端删除文件夹失败: \(error.localizedDescription)")

            let operationDict: [String: Any] = ["folderId": folder.id, "purge": false]
            if let operationData = try? JSONSerialization.data(withJSONObject: operationDict) {
                let operation = NoteOperation(
                    type: .folderDelete,
                    noteId: folder.id,
                    data: operationData,
                    status: .pending,
                    priority: NoteOperation.calculatePriority(for: .folderDelete)
                )
                try? unifiedQueue.enqueue(operation)
            }
            throw error
        }

        do {
            try LocalStorageService.shared.deleteFolderImageDirectory(folderId: folder.id)
        } catch {
            LogService.shared.warning(.viewmodel, "删除文件夹图片目录失败: \(error.localizedDescription)")
        }

        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            if index < folders.count { folders.remove(at: index) }
            try DatabaseService.shared.deleteFolder(folderId: folder.id)
            try localStorage.saveFolders(folders.filter { !$0.isSystem })
            if selectedFolder?.id == folder.id { selectedFolder = nil }
        }

        loadFolders()
        updateFolderCounts()
    }

    // MARK: - 便捷方法

    /// 创建新笔记的便捷方法（用于快速创建空笔记）
    public func createNewNote() {
        // 创建一个默认笔记，使用标准的 XML 格式
        // 使用临时 ID（如果离线）或等待 API 返回的真实 ID（如果在线）
        let tempId = UUID().uuidString
        let newNote = Note(
            id: tempId,
            title: "新笔记",
            content: "<new-format/><text indent=\"1\"></text>",
            folderId: selectedFolder?.id ?? "0",
            isStarred: false,
            createdAt: Date(),
            updatedAt: Date()
        )

        // 使用统一的创建接口，它会处理在线/离线逻辑
        Task {
            do {
                try await createNote(newNote)
            } catch {
                LogService.shared.error(.viewmodel, "创建笔记失败: \(error)")
                errorMessage = "创建笔记失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Cookie过期处理（委托给 AuthenticationStateManager）

    /// 处理Cookie失效弹窗的"刷新Cookie"选项
    @MainActor
    func handleCookieExpiredRefresh() {
        authStateManager.handleCookieExpiredRefresh()
    }

    /// 处理Cookie失效弹窗的"取消"选项
    @MainActor
    func handleCookieExpiredCancel() {
        authStateManager.handleCookieExpiredCancel()
    }

    /// 处理Cookie刷新完成
    ///
    /// Cookie刷新成功后调用此方法
    @MainActor
    func handleCookieRefreshed() {
        authStateManager.handleCookieRefreshed()
    }

    // MARK: - 图片上传

    /// 上传图片并插入到当前笔记
    /// - Parameter imageURL: 图片文件URL
    /// - Returns: 上传成功后的 fileId
    func uploadImageAndInsertToNote(imageURL: URL) async throws -> String {
        guard let note = selectedNote else {
            throw NSError(domain: "MiNote", code: 400, userInfo: [NSLocalizedDescriptionKey: "请先选择笔记"])
        }

        guard service.isAuthenticated() else {
            throw NSError(domain: "MiNote", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录小米账号"])
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // 读取图片数据
            let imageData = try Data(contentsOf: imageURL)
            let fileName = imageURL.lastPathComponent

            // 根据文件扩展名推断 MIME 类型
            let fileExtension = (imageURL.pathExtension as NSString).lowercased
            let mimeType = switch fileExtension {
            case "jpg", "jpeg":
                "image/jpeg"
            case "png":
                "image/png"
            case "gif":
                "image/gif"
            case "webp":
                "image/webp"
            default:
                "image/jpeg"
            }

            // 上传图片
            let uploadResult = try await service.uploadImage(
                imageData: imageData,
                fileName: fileName,
                mimeType: mimeType
            )

            guard let fileId = uploadResult["fileId"] as? String,
                  let digest = uploadResult["digest"] as? String
            else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "上传图片失败：服务器返回无效响应"])
            }

            LogService.shared.info(.viewmodel, "图片上传成功: fileId=\(fileId)")

            // 保存图片到本地
            let fileType = String(mimeType.dropFirst("image/".count))
            try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)

            // 更新笔记的 setting.data，添加图片信息
            var updatedNote = note
            var rawData = updatedNote.rawData ?? [:]
            var setting = rawData["setting"] as? [String: Any] ?? [
                "themeId": 0,
                "stickyTime": 0,
                "version": 0,
            ]

            var settingData = setting["data"] as? [[String: Any]] ?? []
            let imageInfo: [String: Any] = [
                "fileId": fileId,
                "mimeType": mimeType,
                "digest": digest,
            ]
            settingData.append(imageInfo)
            setting["data"] = settingData
            rawData["setting"] = setting
            updatedNote.rawData = rawData

            // 注意：根据小米笔记的格式，图片不应该直接添加到 content 中
            // 图片信息只在 setting.data 中，content 中的图片标签由编辑器管理
            // 所以这里不修改 content，只更新 setting.data
            // 编辑器会在用户插入图片时自动添加 <img fileid="..." /> 标签

            // 更新笔记（需要传递 rawData 以包含 setting.data）
            // 注意：updateNote 方法会从 rawData 中提取 setting.data
            try await updateNote(updatedNote)

            // 返回 fileId，供编辑器使用
            LogService.shared.debug(.viewmodel, "图片已添加到笔记 setting.data: noteId=\(note.id), fileId=\(fileId)")

            // 更新本地笔记对象（从服务器响应中获取最新数据）
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                // 重新加载笔记以获取服务器返回的最新数据
                if let updated = try? localStorage.loadNote(noteId: note.id) {
                    notes[index] = updated
                    selectedNote = updated
                } else {
                    // 如果无法加载，至少更新本地对象
                    notes[index] = updatedNote
                    selectedNote = updatedNote
                }
            }

            LogService.shared.debug(.viewmodel, "图片已插入到笔记: \(note.id)")

            // 返回 fileId 供编辑器使用
            return fileId
        } catch {
            // 上传失败：静默处理，不显示弹窗
            LogService.shared.error(.viewmodel, "上传图片失败: \(error.localizedDescription)")
            // 不设置 errorMessage，避免弹窗提示
            throw error
        }
    }

    // MARK: - 历史记录

    /// 获取笔记历史记录列表
    /// - Parameter noteId: 笔记ID
    /// - Returns: 历史记录列表
    func getNoteHistoryTimes(noteId: String) async throws -> [NoteHistoryVersion] {
        guard service.isAuthenticated() else {
            throw NSError(domain: "MiNote", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录小米账号"])
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await service.getNoteHistoryTimes(noteId: noteId)

            guard let code = response["code"] as? Int, code == 0,
                  let data = response["data"] as? [String: Any],
                  let tvList = data["tvList"] as? [[String: Any]]
            else {
                throw MiNoteError.invalidResponse
            }

            var versions: [NoteHistoryVersion] = []
            for item in tvList {
                if let updateTime = item["updateTime"] as? Int64,
                   let version = item["version"] as? Int64
                {
                    versions.append(NoteHistoryVersion(version: version, updateTime: updateTime))
                }
            }

            return versions
        } catch {
            if let miNoteError = error as? MiNoteError {
                handleMiNoteError(miNoteError)
            } else {
                errorMessage = "获取历史记录失败: \(error.localizedDescription)"
            }
            throw error
        }
    }

    /// 获取笔记历史记录内容
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - version: 版本号
    /// - Returns: 历史记录的笔记对象
    func getNoteHistory(noteId: String, version: Int64) async throws -> Note {
        guard service.isAuthenticated() else {
            throw NSError(domain: "MiNote", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录小米账号"])
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await service.getNoteHistory(noteId: noteId, version: version)

            guard let code = response["code"] as? Int, code == 0,
                  let data = response["data"] as? [String: Any],
                  let entry = data["entry"] as? [String: Any]
            else {
                throw MiNoteError.invalidResponse
            }

            // 使用 Note.fromMinoteData 解析历史记录数据
            guard var note = Note.fromMinoteData(entry) else {
                throw MiNoteError.invalidResponse
            }

            // 使用 updateContent 更新内容（包括 content 字段）
            note.updateContent(from: response)

            return note
        } catch {
            if let miNoteError = error as? MiNoteError {
                handleMiNoteError(miNoteError)
            } else {
                errorMessage = "获取历史记录内容失败: \(error.localizedDescription)"
            }
            throw error
        }
    }

    /// 恢复笔记历史记录
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - version: 要恢复的版本号
    func restoreNoteHistory(noteId: String, version: Int64) async throws {
        guard service.isAuthenticated() else {
            throw NSError(domain: "MiNote", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录小米账号"])
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await service.restoreNoteHistory(noteId: noteId, version: version)

            guard let code = response["code"] as? Int, code == 0 else {
                throw MiNoteError.invalidResponse
            }

            // 恢复成功后，重新同步笔记以获取最新数据
            await performFullSync()

            // 更新选中的笔记
            if let index = notes.firstIndex(where: { $0.id == noteId }) {
                if index < notes.count {
                    selectedNote = notes[index]
                }
            }
        } catch {
            if let miNoteError = error as? MiNoteError {
                handleMiNoteError(miNoteError)
            } else {
                errorMessage = "恢复历史记录失败: \(error.localizedDescription)"
            }
            throw error
        }
    }

    // MARK: - Error Handling

    private func handleMiNoteError(_ error: MiNoteError) {
        switch error {
        case .cookieExpired:
            errorMessage = "Cookie已过期，正在尝试静默刷新..."
            LogService.shared.info(.viewmodel, "Cookie过期，尝试静默刷新")
            // 先尝试静默刷新，而不是直接显示登录界面
            Task {
                await handleCookieExpiredSilently()
            }
        case .notAuthenticated:
            errorMessage = "未登录，请先登录小米账号"
            showLoginView = true
        case let .networkError(underlyingError):
            errorMessage = "网络错误: \(underlyingError.localizedDescription)"
        case .invalidResponse:
            errorMessage = "服务器返回无效响应"
        }
    }

    /// 获取回收站笔记
    ///
    /// 从服务器获取已删除的笔记列表
    func fetchDeletedNotes() async {
        guard service.isAuthenticated() else {
            return
        }

        isLoadingDeletedNotes = true
        defer { isLoadingDeletedNotes = false }

        do {
            let response = try await service.fetchDeletedNotes()

            guard let code = response["code"] as? Int, code == 0,
                  let data = response["data"] as? [String: Any],
                  let entries = data["entries"] as? [[String: Any]]
            else {
                throw MiNoteError.invalidResponse
            }

            var deletedNotes: [DeletedNote] = []
            for entry in entries {
                if let deletedNote = DeletedNote.fromAPIResponse(entry) {
                    deletedNotes.append(deletedNote)
                }
            }

            await MainActor.run {
                self.deletedNotes = deletedNotes
                LogService.shared.info(.viewmodel, "获取回收站笔记成功，共 \(deletedNotes.count) 条")

                // 更新回收站文件夹的计数
                if let trashIndex = folders.firstIndex(where: { $0.id == "trash" }) {
                    folders[trashIndex].count = deletedNotes.count
                }
            }
        } catch {
            LogService.shared.error(.viewmodel, "获取回收站笔记失败: \(error.localizedDescription)")
            await MainActor.run {
                self.deletedNotes = []
            }
        }
    }

    /// 恢复回收站笔记
    ///
    /// 从回收站恢复笔记到原文件夹
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - tag: 笔记的tag（版本标识）
    /// - Throws: MiNoteError
    func restoreDeletedNote(noteId: String, tag: String) async throws {
        guard service.isAuthenticated() else {
            throw NSError(domain: "MiNote", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录小米账号"])
        }

        LogService.shared.info(.viewmodel, "开始恢复笔记: \(noteId)")

        do {
            let response = try await service.restoreDeletedNote(noteId: noteId, tag: tag)

            guard let code = response["code"] as? Int, code == 0 else {
                let message = response["description"] as? String ?? response["message"] as? String ?? "恢复笔记失败"
                throw NSError(domain: "MiNote", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            }

            LogService.shared.info(.viewmodel, "恢复笔记成功: \(noteId)")

            // 刷新笔记列表和回收站列表
            await reloadDataAfterSync()
            await fetchDeletedNotes()
        } catch {
            LogService.shared.error(.viewmodel, "恢复笔记失败: \(error.localizedDescription)")
            throw error
        }
    }

    /// 永久删除笔记
    ///
    /// 从回收站永久删除笔记，此操作不可恢复
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - tag: 笔记的tag（版本标识）
    /// - Throws: MiNoteError
    func permanentlyDeleteNote(noteId: String, tag: String) async throws {
        guard service.isAuthenticated() else {
            throw NSError(domain: "MiNote", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录小米账号"])
        }

        LogService.shared.info(.viewmodel, "开始永久删除笔记: \(noteId)")

        do {
            let response = try await service.deleteNote(noteId: noteId, tag: tag, purge: true)

            guard let code = response["code"] as? Int, code == 0 else {
                let message = response["description"] as? String ?? response["message"] as? String ?? "永久删除笔记失败"
                throw NSError(domain: "MiNote", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            }

            LogService.shared.info(.viewmodel, "永久删除笔记成功: \(noteId)")

            // 刷新回收站列表
            await fetchDeletedNotes()
        } catch {
            LogService.shared.error(.viewmodel, "永久删除笔记失败: \(error.localizedDescription)")
            throw error
        }
    }

    /// 获取用户信息
    ///
    /// 从服务器获取当前登录用户的昵称和头像
    func fetchUserProfile() async {
        guard service.isAuthenticated() else {
            return
        }

        do {
            let profileData = try await service.fetchUserProfile()
            if let profile = UserProfile.fromAPIResponse(profileData) {
                await MainActor.run {
                    self.userProfile = profile
                }
            }
        } catch {
            LogService.shared.error(.viewmodel, "获取用户信息失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 自动刷新Cookie定时器管理

    /// 启动自动刷新Cookie定时器（改进版）
    func startAutoRefreshCookieIfNeeded() {
        guard service.isAuthenticated() else {
            return
        }

        guard service.hasValidCookie() else {
            return
        }

        if autoRefreshCookieTimer != nil {
            return
        }

        let defaults = UserDefaults.standard
        let autoRefreshCookie = defaults.bool(forKey: "autoRefreshCookie")
        let autoRefreshInterval = defaults.double(forKey: "autoRefreshInterval")

        guard autoRefreshCookie, autoRefreshInterval > 0 else {
            return
        }

        if autoRefreshInterval == 0 {
            defaults.set(86400.0, forKey: "autoRefreshInterval")
        }

        LogService.shared.info(.viewmodel, "启动自动刷新Cookie定时器，间隔: \(autoRefreshInterval)秒")

        autoRefreshCookieTimer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                await self.refreshCookieAutomatically()
            }
        }
    }

    /// 停止自动刷新Cookie定时器
    func stopAutoRefreshCookie() {
        autoRefreshCookieTimer?.invalidate()
        autoRefreshCookieTimer = nil
    }

    /// 自动刷新Cookie（改进版）
    private func refreshCookieAutomatically() async {
        guard service.isAuthenticated() else {
            return
        }

        guard isOnline else {
            return
        }

        guard !service.hasValidCookie() else {
            return
        }

        do {
            let success = try await service.refreshCookie()
            if !success {
                LogService.shared.warning(.viewmodel, "自动刷新Cookie失败")
            }
        } catch {
            LogService.shared.error(.viewmodel, "自动刷新Cookie出错: \(error.localizedDescription)")
        }
    }

    /// 静默处理Cookie失效（由ContentView调用）
    func handleCookieExpiredSilently() async {
        await authStateManager.handleCookieExpiredSilently()
    }

    // MARK: - 应用状态监听和自动同步

    /// 处理应用变为前台
    private func handleAppBecameActive() {
        isAppActive = true
        startAutoSyncTimer()
    }

    private func handleAppResignedActive() {
        isAppActive = false
        stopAutoSyncTimer()
    }

    /// 启动自动同步定时器
    private func startAutoSyncTimer() {
        guard service.isAuthenticated() else {
            return
        }

        if autoSyncTimer != nil {
            return
        }

        let effectiveSyncInterval = max(syncInterval, minSyncInterval)
        LogService.shared.info(.viewmodel, "启动自动同步定时器，间隔: \(effectiveSyncInterval)秒")

        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: effectiveSyncInterval, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                await self.performAutoSync()
            }
        }
    }

    private func stopAutoSyncTimer() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }

    /// 执行自动同步
    private func performAutoSync() async {
        guard isAppActive else {
            return
        }

        guard service.isAuthenticated() else {
            return
        }

        guard isOnline else {
            return
        }

        guard !isSyncing else {
            return
        }

        let now = Date()
        let timeSinceLastSync = now.timeIntervalSince(lastSyncTimestamp)
        if timeSinceLastSync < minSyncInterval {
            return
        }

        lastSyncTimestamp = now
        await performIncrementalSync()
    }

    /// 更新同步间隔设置
    func updateSyncInterval(_ newInterval: Double) {
        let effectiveInterval = max(newInterval, minSyncInterval)
        syncInterval = effectiveInterval

        UserDefaults.standard.set(effectiveInterval, forKey: "syncInterval")

        if isAppActive {
            stopAutoSyncTimer()
            startAutoSyncTimer()
        }
    }

    // MARK: - 音频面板状态同步

    /// 处理笔记切换时的音频面板状态同步
    ///
    /// 当用户切换到其他笔记时，检查音频面板的状态：
    /// - 如果正在播放，停止播放并关闭面板
    /// - 如果正在录制，显示确认对话框
    ///
    /// - Parameter newNoteId: 新选中的笔记 ID
    private func handleNoteSwitch(to newNoteId: String) {
        // 调用 AudioPanelStateManager 的 handleNoteSwitch 方法
        // 该方法会根据当前状态决定是否需要确认对话框
        let canSwitch = AudioPanelStateManager.shared.handleNoteSwitch(to: newNoteId)

        if !canSwitch {
            // AudioPanelStateManager 会发送确认通知，MainWindowController 监听后显示确认对话框
        }
    }

    // MARK: - 清理

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
