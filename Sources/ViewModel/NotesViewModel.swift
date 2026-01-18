import Foundation
import SwiftUI
import Combine

/// 笔记排序方式
public enum NoteSortOrder: String, Codable {
    case editDate = "editDate"      // 编辑日期
    case createDate = "createDate"  // 创建日期
    case title = "title"            // 标题
}

/// 排序方向
public enum SortDirection: String, Codable {
    case ascending = "ascending"   // 升序
    case descending = "descending"  // 降序
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
    @Published var searchFilterHasTags: Bool = false
    @Published var searchFilterHasChecklist: Bool = false
    @Published var searchFilterHasImages: Bool = false
    @Published var searchFilterHasAudio: Bool = false // 待实现
    @Published var searchFilterIsPrivate: Bool = false
    
    /// 是否显示登录视图
    @Published var showLoginView: Bool = false
    
    /// 是否显示Cookie刷新视图
    @Published var showCookieRefreshView: Bool = false
    
    /// 私密笔记是否已解锁
    @Published var isPrivateNotesUnlocked: Bool = false
    
    /// 是否显示私密笔记密码输入对话框
    @Published var showPrivateNotesPasswordDialog: Bool = false
    
    /// 用户信息（用户名和头像）
    @Published var userProfile: UserProfile?
    
    /// 回收站笔记列表
    @Published var deletedNotes: [DeletedNote] = []
    
    /// 是否正在加载回收站笔记
    @Published var isLoadingDeletedNotes: Bool = false
    
    /// 是否显示回收站视图
    @Published var showTrashView: Bool = false
    
    /// 原生编辑器上下文（共享实例）
    /// 需求: 1.1, 1.3 - 在 MainWindowController 和 NoteDetailView 之间共享
    @Published var nativeEditorContext = NativeEditorContext()
    
    /// 画廊视图是否展开（正在编辑笔记）
    /// 用于工具栏可见性管理，在画廊视图展开时显示返回按钮和编辑器工具栏项
    @Published public var isGalleryExpanded: Bool = false
    
    // MARK: - 笔记切换保护
    
    /// 是否正在切换笔记
    /// 
    /// 用于防止笔记切换过程中被打断，避免死循环问题
    /// 
    /// **使用场景**：
    /// - 在 `selectNoteWithCoordinator()` 中设置为 true
    /// - 切换完成后自动重置为 false
    /// - 切换过程中忽略新的切换请求
    /// 
    /// _Requirements: Spec 60 - 修复笔记切换死循环_
    private var isSwitchingNote: Bool = false
    
    /// 上次笔记切换的时间
    /// 
    /// 用于实现防抖机制，防止快速连续切换导致的死循环问题
    /// 
    /// **使用场景**：
    /// - 在 `selectNoteWithCoordinator()` 中记录切换时间
    /// - 切换前检查距离上次切换的时间间隔
    /// - 如果间隔小于 `switchDebounceInterval`，则忽略本次切换
    /// 
    /// _Requirements: Spec 60 - 修复笔记切换死循环_
    private var lastSwitchTime: Date?
    
    /// 笔记切换防抖时间间隔（秒）
    /// 
    /// 防止快速连续切换导致的死循环问题。如果两次切换的时间间隔小于此值，
    /// 则忽略第二次切换请求。
    /// 
    /// **值说明**：
    /// - 设置为 0.3 秒（300ms）
    /// - 这个时间足够短，不会影响正常使用体验
    /// - 同时足够长，可以防止意外的快速切换
    /// 
    /// _Requirements: Spec 60 - 修复笔记切换死循环_
    private let switchDebounceInterval: TimeInterval = 0.3
    
    /// 是否正在从 ViewStateCoordinator 更新状态
    /// 
    /// 用于防止状态同步的循环依赖，打破双向绑定的循环更新
    /// 
    /// **使用场景**：
    /// - 在 `setupStateCoordinatorSync()` 中从 ViewStateCoordinator 同步状态时设置为 true
    /// - 更新完成后立即重置为 false
    /// - 当此标志为 true 时，忽略来自 ViewStateCoordinator 的状态更新
    /// 
    /// **问题背景**：
    /// - NotesViewModel 从 ViewStateCoordinator 同步 selectedNote
    /// - 某些操作又会更新 ViewStateCoordinator 的状态
    /// - 双向绑定没有足够的防护机制，导致循环更新
    /// 
    /// **解决方案**：
    /// - 使用此标志确保单向数据流
    /// - 防止 NotesViewModel → ViewStateCoordinator → NotesViewModel 的循环更新
    /// 
    /// _Requirements: Spec 60 - 修复笔记切换死循环_
    private var isUpdatingFromCoordinator: Bool = false
    
    /// 当前加载任务的唯一标识符
    /// 
    /// 用于跟踪延迟加载任务，防止过期任务完成时触发意外操作
    /// 
    /// **使用场景**：
    /// - 在开始加载笔记内容时生成新的 UUID 并赋值给此属性
    /// - 在延迟加载完成前检查任务 ID 是否仍然有效
    /// - 如果任务 ID 已经改变（说明用户已切换到其他笔记），则取消当前任务
    /// 
    /// **问题背景**：
    /// - 快速切换笔记时，延迟加载任务可能还未完成
    /// - 新的切换已经发生，但旧任务完成时发现笔记 ID 不匹配
    /// - 取消操作可能触发了新的切换，导致死循环
    /// 
    /// **解决方案**：
    /// - 使用唯一的任务 ID 跟踪每个加载任务
    /// - 任务完成前检查 ID 是否仍然有效
    /// - 如果 ID 已过期，直接返回，不执行任何操作
    /// 
    /// **示例**：
    /// ```swift
    /// func loadNoteContent(_ note: Note) async {
    ///     let taskId = UUID()
    ///     currentLoadingTaskId = taskId
    ///     
    ///     // 延迟加载
    ///     try? await Task.sleep(nanoseconds: 100_000_000)
    ///     
    ///     // 检查任务是否仍然有效
    ///     guard currentLoadingTaskId == taskId else {
    ///         print("[快速切换] 任务已过期，取消加载")
    ///         return
    ///     }
    ///     
    ///     // 执行加载...
    /// }
    /// ```
    /// 
    /// _Requirements: Spec 60 - 修复笔记切换死循环_
    private var currentLoadingTaskId: UUID?
    
    // MARK: - 状态协调器
    
    /// 视图状态协调器
    /// 
    /// 负责协调侧边栏、笔记列表和编辑器之间的状态同步
    /// 
    /// - 4.1: 作为单一数据源管理 selectedFolder 和 selectedNote 的状态
    /// - 4.2: selectedFolder 变化时按顺序更新 Notes_List_View 和 Editor
    public private(set) lazy var stateCoordinator: ViewStateCoordinator = {
        let coordinator = ViewStateCoordinator(viewModel: self)
        return coordinator
    }()
    
    // MARK: - 设置
    
    /// 同步间隔（秒），默认5分钟
    @Published var syncInterval: Double = 300
    
    /// 是否自动保存
    @Published var autoSave: Bool = true
    
    // MARK: - 同步状态
    
    /// 是否正在同步
    @Published var isSyncing = false
    
    /// 同步进度（0.0 - 1.0）
    @Published var syncProgress: Double = 0
    
    /// 同步状态消息
    @Published var syncStatusMessage: String = ""
    
    /// 上次同步时间
    @Published var lastSyncTime: Date?
    
    /// 同步结果
    @Published var syncResult: SyncService.SyncResult?
    
    // MARK: - 数据加载状态指示
    // _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_
    
    /// 是否正在加载本地数据
    /// _Requirements: 7.1_
    @Published var isLoadingLocalData: Bool = false
    
    /// 本地数据加载状态消息
    /// _Requirements: 7.1_
    @Published var localDataLoadingMessage: String = ""
    
    /// 是否正在处理离线队列（从 OfflineOperationProcessor 同步）
    /// _Requirements: 7.2_
    @Published var isProcessingOfflineQueue: Bool = false
    
    /// 离线队列处理进度（0.0 - 1.0）
    /// _Requirements: 7.2_
    @Published var offlineQueueProgress: Double = 0.0
    
    /// 离线队列处理状态消息
    /// _Requirements: 7.2_
    @Published var offlineQueueStatusMessage: String = ""
    
    /// 离线队列待处理操作数量
    /// _Requirements: 7.2_
    @Published var offlineQueuePendingCount: Int = 0
    
    /// 离线队列已处理操作数量
    /// _Requirements: 7.2_
    @Published var offlineQueueProcessedCount: Int = 0
    
    /// 离线队列失败操作数量
    /// _Requirements: 7.2_
    @Published var offlineQueueFailedCount: Int = 0
    
    /// 同步完成后的笔记数量
    /// _Requirements: 7.4_
    @Published var lastSyncedNotesCount: Int = 0
    
    /// 是否处于离线模式
    /// _Requirements: 7.5_
    @Published var isOfflineMode: Bool = false
    
    /// 离线模式原因
    /// _Requirements: 7.5_
    @Published var offlineModeReason: String = ""
    
    /// 启动序列当前阶段（从 StartupSequenceManager 同步）
    /// _Requirements: 7.1, 7.2, 7.3_
    @Published var startupPhase: StartupSequenceManager.StartupPhase = .idle
    
    /// 启动序列状态消息
    /// _Requirements: 7.1, 7.2, 7.3_
    @Published var startupStatusMessage: String = ""
    
    /// 综合状态消息（用于状态栏显示）
    /// 
    /// 根据当前状态返回最相关的状态消息
    /// _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_
    var currentStatusMessage: String {
        // 优先显示离线模式
        if isOfflineMode {
            return "离线模式" + (offlineModeReason.isEmpty ? "" : "：\(offlineModeReason)")
        }
        
        // 显示启动序列状态
        if !startupStatusMessage.isEmpty && startupPhase != .completed && startupPhase != .idle {
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
    /// _Requirements: 7.1, 7.2, 7.3_
    var isAnyOperationInProgress: Bool {
        return isLoadingLocalData || isProcessingOfflineQueue || isSyncing || isLoading
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
    /// _需求: 6.1, 6.2_
    var unifiedPendingUploadCount: Int {
        unifiedQueue.getPendingUploadCount()
    }
    
    /// 是否正在处理操作（从新的 OperationProcessor 获取）
    @Published var isProcessingOperations: Bool = false
    
    /// 操作处理进度（0.0 - 1.0）
    @Published var operationProgress: Double = 0.0
    
    /// 操作处理状态消息
    @Published var operationStatusMessage: String = ""
    
    /// 统一操作队列所有待上传笔记 ID
    /// _需求: 6.1_
    var unifiedPendingNoteIds: [String] {
        unifiedQueue.getAllPendingNoteIds()
    }
    
    /// 临时 ID 笔记数量（离线创建的笔记）
    /// _需求: 6.1_
    var temporaryIdNoteCount: Int {
        unifiedQueue.getTemporaryIdNoteCount()
    }
    
    /// 检查笔记是否有待处理上传
    /// _需求: 6.2_
    func hasPendingUpload(for noteId: String) -> Bool {
        unifiedQueue.hasPendingUpload(for: noteId)
    }
    
    /// 检查笔记是否使用临时 ID（离线创建）
    /// _需求: 6.2_
    func isTemporaryIdNote(_ noteId: String) -> Bool {
        NoteOperation.isTemporaryId(noteId)
    }
    
    // MARK: - 网络状态（从 AuthenticationStateManager 同步）
    
    /// 是否在线（需要同时满足网络连接和Cookie有效）
    @Published var isOnline: Bool = true
    
    /// Cookie是否失效
    @Published var isCookieExpired: Bool = false
    
    /// 是否已显示Cookie失效提示（避免重复提示）
    @Published var cookieExpiredShown: Bool = false
    
    /// 是否显示Cookie失效弹窗
    @Published var showCookieExpiredAlert: Bool = false
    
    /// 是否保持离线模式（用户点击"取消"后设置为true，阻止后续请求）
    @Published var shouldStayOffline: Bool = false
    
    // MARK: - 依赖服务
    
    /// 小米笔记API服务
    internal let service = MiNoteService.shared
    
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
    @Published var isAppActive: Bool = true
    
    /// 上次同步时间戳（用于避免频繁同步）
    private var lastSyncTimestamp: Date = Date.distantPast
    
    /// 最小同步间隔（秒）
    private let minSyncInterval: TimeInterval = 10.0
    
    // MARK: - 启动序列管理
    
    /// 启动序列管理器
    /// 
    /// 负责协调应用启动时的各个步骤，确保按正确顺序执行
    /// _Requirements: 2.1, 2.2, 2.3, 2.4_
    private let startupManager = StartupSequenceManager()
    
    /// 是否为首次启动（本次会话）
    /// 
    /// 用于区分首次启动和后续的数据刷新
    /// _Requirements: 1.1, 1.2_
    private var isFirstLaunch: Bool = true
    
    // MARK: - 计算属性
    
    /// 过滤后的笔记列表
    /// 
    /// 根据搜索文本、选中的文件夹和筛选选项过滤笔记，并根据文件夹的排序方式排序
    var filteredNotes: [Note] {
        let filtered: [Note]
        
        // 首先根据搜索文本和文件夹过滤
        if searchText.isEmpty {
            if let folder = selectedFolder {
                if folder.id == "starred" {
                    filtered = notes.filter { $0.isStarred }
                } else if folder.id == "0" {
                    filtered = notes
                } else if folder.id == "2" {
                    // 私密笔记文件夹：显示 folderId 为 "2" 的笔记
                    filtered = notes.filter { $0.folderId == "2" }
                } else if folder.id == "uncategorized" {
                    // 未分类文件夹：显示 folderId 为 "0" 或空的笔记
                    filtered = notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }
                } else {
                    filtered = notes.filter { $0.folderId == folder.id }
                }
            } else {
                filtered = notes
            }
        } else {
            filtered = notes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 应用搜索筛选选项
        let filteredBySearchOptions = filtered.filter { note in
            // 含标签的笔记
            if searchFilterHasTags && note.tags.isEmpty {
                return false
            }
            
            // 含核对清单的笔记
            if searchFilterHasChecklist && !noteHasChecklist(note) {
                return false
            }
            
            // 含图片的笔记
            if searchFilterHasImages && !noteHasImages(note) {
                return false
            }
            
            // 含录音的笔记（待实现）
            if searchFilterHasAudio && !noteHasAudio(note) {
                return false
            }
            
            // 私密笔记
            if searchFilterIsPrivate && note.folderId != "2" {
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
           let data = setting["data"] as? [[String: Any]], !data.isEmpty {
            return true
        }
        return false
    }
    
    /// 检查笔记是否包含录音（待实现）
    /// 
    /// - Parameter note: 要检查的笔记
    /// - Returns: 如果包含录音返回 true，否则返回 false
    private func noteHasAudio(_ note: Note) -> Bool {
        // 待实现：检查笔记中是否包含录音
        // 目前返回 false
        return false
    }
    
    /// 根据排序方式和方向对笔记进行排序
    /// 
    /// 使用稳定排序：当主排序键相同时，使用 id 作为次要排序键，
    /// 确保排序结果的一致性，避免不必要的列表重排和动画。
    private func sortNotes(_ notes: [Note], by sortOrder: NoteSortOrder, direction: SortDirection) -> [Note] {
        let sorted: [Note]
        switch sortOrder {
        case .editDate:
            // 使用稳定排序：先按 updatedAt 排序，相同时按 id 排序
            sorted = notes.sorted { 
                if $0.updatedAt == $1.updatedAt {
                    return $0.id < $1.id
                }
                return $0.updatedAt < $1.updatedAt 
            }
        case .createDate:
            // 使用稳定排序：先按 createdAt 排序，相同时按 id 排序
            sorted = notes.sorted { 
                if $0.createdAt == $1.createdAt {
                    return $0.id < $1.id
                }
                return $0.createdAt < $1.createdAt 
            }
        case .title:
            // 使用稳定排序：先按 title 排序，相同时按 id 排序
            sorted = notes.sorted { 
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
        let uncategorizedCount = notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }.count
        return Folder(id: "uncategorized", name: "未分类", count: uncategorizedCount, isSystem: false)
    }
    
    /// 是否已登录（是否有有效的Cookie）
    var isLoggedIn: Bool {
        return service.isAuthenticated()
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
    /// _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4_
    public init() {
        // 加载本地数据（根据登录状态决定加载本地数据还是示例数据）
        // _Requirements: 1.1, 1.2, 1.3_
        loadLocalData()
        
        // 加载设置
        loadSettings()
        
        // 加载同步状态
        loadSyncStatus()
        
        // 恢复上次选中的文件夹和笔记
        restoreLastSelectedState()
        
        // 如果已登录，获取用户信息并执行启动序列
        // _Requirements: 2.1, 2.2, 2.3, 2.4_
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
        // _Requirements: 8.1, 8.3, 8.4, 8.5_
        setupViewOptionsSync()
        
        // 监听原生编辑器的内容变化（基于版本号机制）
        // _Requirements: FR-6.2_ - 只在有未保存更改时触发保存
        setupNativeEditorContentChangeListener()
        
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
        // _Requirements: 2.4_
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
        // _Requirements: 5.2_
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
        // _Requirements: 8.7_ - 更新 UI 中的笔记引用（selectedNote 等）
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
    /// _Requirements: 2.1, 2.2, 2.3_
    private func executeStartupSequence() async {
        guard isFirstLaunch else {
            print("[NotesViewModel] 非首次启动，跳过启动序列")
            return
        }
        
        print("[NotesViewModel] 🚀 开始执行启动序列")
        isFirstLaunch = false
        
        // 使用 StartupSequenceManager 执行启动序列
        await startupManager.executeStartupSequence()
        
        // 启动序列完成后，重新加载本地数据以获取同步后的最新数据
        await reloadDataAfterStartup()
    }
    
    /// 启动序列完成后重新加载数据
    /// 
    /// _Requirements: 1.4, 4.4_
    private func reloadDataAfterStartup() async {
        print("[NotesViewModel] 启动序列完成，重新加载数据")
        
        // 重新加载本地数据
        do {
            let localNotes = try localStorage.getAllLocalNotes()
            if !localNotes.isEmpty {
                self.notes = localNotes
                print("[NotesViewModel] 重新加载了 \(localNotes.count) 条笔记")
            }
            
            // 重新加载文件夹
            loadFolders()
            updateFolderCounts()
            
            // 更新 UI
            objectWillChange.send()
        } catch {
            print("[NotesViewModel] 重新加载数据失败: \(error)")
        }
    }
    
    /// 处理启动序列完成通知
    /// 
    /// _Requirements: 2.4_
    private func handleStartupSequenceCompletedWithValues(success: Bool, errors: [String], duration: TimeInterval) {
        print("[NotesViewModel] 📊 启动序列完成通知:")
        print("[NotesViewModel]   - 成功: \(success)")
        print("[NotesViewModel]   - 耗时: \(String(format: "%.2f", duration)) 秒")
        
        if !errors.isEmpty {
            print("[NotesViewModel]   - 错误: \(errors.joined(separator: ", "))")
        }
    }
    
    /// 同步 AuthenticationStateManager 的状态到 ViewModel
    /// 
    /// 通过 Combine 将 AuthenticationStateManager 的 @Published 属性同步到 ViewModel 的 @Published 属性
    /// 这样 AuthenticationStateManager 的状态变化会自动触发 ViewModel 的状态更新，进而触发 UI 更新
    private func setupAuthStateSync() {
        // 同步 isOnline
        authStateManager.$isOnline
            .assign(to: &$isOnline)
        
        // 同步 isCookieExpired
        authStateManager.$isCookieExpired
            .assign(to: &$isCookieExpired)
        
        // 同步 cookieExpiredShown
        authStateManager.$cookieExpiredShown
            .assign(to: &$cookieExpiredShown)
        
        // 同步 showCookieExpiredAlert
        authStateManager.$showCookieExpiredAlert
            .assign(to: &$showCookieExpiredAlert)
        
        // 同步 shouldStayOffline
        authStateManager.$shouldStayOffline
            .assign(to: &$shouldStayOffline)
        
        // 同步 showLoginView
        authStateManager.$showLoginView
            .assign(to: &$showLoginView)
        
        // 同步 showCookieRefreshView
        authStateManager.$showCookieRefreshView
            .assign(to: &$showCookieRefreshView)
        
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
    /// - 7.1: 加载指示器状态
    /// - 7.2: 离线队列处理进度状态
    /// - 7.3: 同步进度和状态消息
    /// - 7.4: 同步结果
    /// - 7.5: 离线模式指示
    private func setupDataLoadingStatusSync() {
        // 监听 OperationProcessor 状态
        // 由于 OperationProcessor 是 actor，使用定时器定期更新
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    // 更新处理状态
                    self.isProcessingOperations = await self.operationProcessor.isProcessing
                    
                    // 更新进度
                    let stats = self.unifiedQueue.getStatistics()
                    let totalCount = stats["pending", default: 0] + 
                                   stats["processing", default: 0] + 
                                   stats["failed", default: 0]
                    let processedCount = stats["completed", default: 0]
                    let failedCount = stats["failed", default: 0]
                    
                    if totalCount + processedCount > 0 {
                        self.operationProgress = Double(processedCount) / Double(totalCount + processedCount)
                    } else {
                        self.operationProgress = 0.0
                    }
                    
                    // 更新状态消息
                    if self.isProcessingOperations {
                        self.operationStatusMessage = "正在处理操作..."
                    } else if totalCount > 0 {
                        self.operationStatusMessage = "等待处理 \(totalCount) 个操作"
                    } else {
                        self.operationStatusMessage = ""
                    }
                    
                    // 更新离线队列状态
                    self.offlineQueueProcessedCount = processedCount
                    self.offlineQueuePendingCount = totalCount
                    self.offlineQueueFailedCount = failedCount
                }
            }
            .store(in: &cancellables)
        
        // 同步 StartupSequenceManager 的状态（需求 7.1, 7.2, 7.3）
        startupManager.$currentPhase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self = self else { return }
                self.startupPhase = phase
                
                // 根据阶段更新加载状态
                switch phase {
                case .loadingLocalData:
                    self.isLoadingLocalData = true
                    self.localDataLoadingMessage = "正在加载本地数据..."
                case .processingOfflineQueue:
                    self.isLoadingLocalData = false
                    self.localDataLoadingMessage = ""
                case .syncing:
                    self.isLoadingLocalData = false
                    self.localDataLoadingMessage = ""
                case .completed, .failed:
                    self.isLoadingLocalData = false
                    self.localDataLoadingMessage = ""
                case .idle:
                    break
                }
            }
            .store(in: &cancellables)
        
        startupManager.$statusMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$startupStatusMessage)
        
        // 同步离线模式状态（需求 7.5）
        // 监听 OnlineStateManager 的在线状态
        OnlineStateManager.shared.$isOnline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOnline in
                guard let self = self else { return }
                self.isOfflineMode = !isOnline
                
                // 更新离线模式原因
                if !isOnline {
                    if !NetworkMonitor.shared.isConnected {
                        self.offlineModeReason = "网络未连接"
                    } else if !self.service.isAuthenticated() {
                        self.offlineModeReason = "未登录"
                    } else if self.isCookieExpired {
                        self.offlineModeReason = "登录已过期"
                    } else {
                        self.offlineModeReason = ""
                    }
                } else {
                    self.offlineModeReason = ""
                }
            }
            .store(in: &cancellables)
    }
    
    /// 同步 ViewStateCoordinator 的状态到 ViewModel
    /// 
    /// 通过 Combine 将 ViewStateCoordinator 的 @Published 属性同步到 ViewModel 的 @Published 属性
    /// 这样 ViewStateCoordinator 的状态变化会自动触发 ViewModel 的状态更新，进而触发 UI 更新
    /// 
    /// - 1.1: 编辑笔记内容时保持选中状态不变
    /// - 1.2: 笔记内容保存触发 notes 数组更新时不重置 selectedNote
    /// - 4.1: 作为单一数据源管理 selectedFolder 和 selectedNote 的状态
    private func setupStateCoordinatorSync() {
        // 同步 selectedFolder
        stateCoordinator.$selectedFolder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] folder in
                guard let self = self else { return }
                
                // 防止循环更新：当正在从 Coordinator 更新时，忽略新的更新
                // _Requirements: Spec 60 - 修复笔记切换死循环_
                guard !self.isUpdatingFromCoordinator else {
                    print("[NotesViewModel] 正在从 Coordinator 更新，忽略 selectedFolder 变化")
                    return
                }
                
                // 只有当状态真正变化时才更新，避免循环更新
                if self.selectedFolder?.id != folder?.id {
                    print("[NotesViewModel] 从 stateCoordinator 同步 selectedFolder: \(folder?.name ?? "nil")")
                    
                    // 设置标志，防止循环更新
                    self.isUpdatingFromCoordinator = true
                    self.selectedFolder = folder
                    self.isUpdatingFromCoordinator = false
                }
            }
            .store(in: &cancellables)
        
        // 同步 selectedNote
        stateCoordinator.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self = self else { return }
                
                // 防止循环更新：当正在从 Coordinator 更新时，忽略新的更新
                // _Requirements: Spec 60 - 修复笔记切换死循环_
                guard !self.isUpdatingFromCoordinator else {
                    print("[NotesViewModel] 正在从 Coordinator 更新，忽略 selectedNote 变化")
                    return
                }
                
                // 只有当状态真正变化时才更新，避免循环更新
                if self.selectedNote?.id != note?.id {
                    print("[NotesViewModel] 从 stateCoordinator 同步 selectedNote: \(note?.title ?? "nil")")
                    
                    // 设置标志，防止循环更新
                    self.isUpdatingFromCoordinator = true
                    self.selectedNote = note
                    self.isUpdatingFromCoordinator = false
                    
                    // 发送笔记选中状态变化通知
                    // _Requirements: 14.4_
                    self.postNoteSelectionNotification()
                }
            }
            .store(in: &cancellables)
    }
    
    /// 发送笔记选中状态变化通知
    /// 
    /// 当笔记选中状态变化时，发送通知以更新菜单状态
    /// 
    /// _Requirements: 14.4_
    private func postNoteSelectionNotification() {
        let hasSelectedNote = selectedNote != nil
        NotificationCenter.default.post(
            name: .noteSelectionDidChange,
            object: self,
            userInfo: [
                "hasSelectedNote": hasSelectedNote,
                "noteId": selectedNote?.id as Any
            ]
        )
        print("[NotesViewModel] 发送笔记选中状态变化通知: hasSelectedNote=\(hasSelectedNote)")
    }
    
    /// 同步 ViewOptionsManager 的排序设置到 ViewModel
    /// 
    /// 通过 Combine 将 ViewOptionsManager 的排序设置同步到 ViewModel 的排序属性
    /// 确保画廊视图和列表视图使用相同的排序设置
    /// 
    /// - 8.1: 文件夹切换时画廊视图更新
    /// - 8.3: 搜索时画廊视图过滤
    /// - 8.4: 画廊视图尊重所有搜索筛选选项
    /// - 8.5: 切换视图模式时保持选中文件夹和搜索状态
    private func setupViewOptionsSync() {
        // 同步排序方式
        ViewOptionsManager.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                
                // 同步排序方式
                if self.notesListSortField != state.sortOrder {
                    print("[NotesViewModel] 从 ViewOptionsManager 同步排序方式: \(state.sortOrder.displayName)")
                    self.notesListSortField = state.sortOrder
                }
                
                // 同步排序方向
                if self.notesListSortDirection != state.sortDirection {
                    print("[NotesViewModel] 从 ViewOptionsManager 同步排序方向: \(state.sortDirection.displayName)")
                    self.notesListSortDirection = state.sortDirection
                }
            }
            .store(in: &cancellables)
    }
    
    /// 设置原生编辑器内容变化监听器
    /// 
    /// 监听 NativeEditorContext 的 contentChangePublisher，基于版本号机制判断是否需要保存
    /// 只在有未保存更改时触发保存操作
    /// 
    /// _Requirements: FR-6.2_ - 只在有未保存更改时保存
    private func setupNativeEditorContentChangeListener() {
        nativeEditorContext.contentChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                // 检查是否需要保存（基于版本号机制）
                // _Requirements: FR-6.2_
                guard self.nativeEditorContext.needsSave else {
                    print("[NotesViewModel] 内容变化但无需保存，跳过")
                    return
                }
                
                // 检查是否有选中的笔记
                guard let note = self.selectedNote else {
                    print("[NotesViewModel] 内容变化但无选中笔记，跳过保存")
                    return
                }
                
                print("[NotesViewModel] 📝 检测到内容变化且需要保存")
                print("[NotesViewModel]   - 笔记ID: \(note.id.prefix(8))...")
                print("[NotesViewModel]   - needsSave: \(self.nativeEditorContext.needsSave)")
                
                // 触发保存操作
                Task { @MainActor in
                    await self.handleContentChangeAndSave(note)
                }
            }
            .store(in: &cancellables)
    }
    
    /// 处理内容变化并保存
    /// 
    /// 当编辑器内容变化且需要保存时，执行保存操作
    /// 
    /// _Requirements: FR-6.2_ - 只在有未保存更改时保存
    @MainActor
    private func handleContentChangeAndSave(_ note: Note) async {
        // 导出 XML 内容
        let xmlContent = nativeEditorContext.exportToXML()
        
        guard !xmlContent.isEmpty else {
            print("[NotesViewModel] ⚠️ 导出的 XML 为空，取消保存")
            return
        }
        
        print("[NotesViewModel] 💾 开始保存笔记")
        print("[NotesViewModel]   - 笔记ID: \(note.id.prefix(8))...")
        print("[NotesViewModel]   - XML 长度: \(xmlContent.count)")
        
        // 构建更新的笔记对象
        let updatedNote = Note(
            id: note.id,
            title: note.title,
            content: xmlContent,
            folderId: note.folderId,
            isStarred: note.isStarred,
            createdAt: note.createdAt,
            updatedAt: Date(),
            tags: note.tags,
            rawData: note.rawData
        )
        
        // 使用 NoteOperationCoordinator 保存笔记
        // 这会处理本地保存和云端同步
        do {
            let saveResult = await NoteOperationCoordinator.shared.saveNote(updatedNote)
            
            switch saveResult {
            case .success:
                print("[NotesViewModel] ✅ 笔记保存成功")
                
                // 通知 changeTracker 保存成功
                // _Requirements: FR-4.1_
                nativeEditorContext.changeTracker.didSaveSuccessfully()
                
                // 更新内存中的笔记列表
                if let index = notes.firstIndex(where: { $0.id == updatedNote.id }) {
                    notes[index] = updatedNote
                }
                
                // 更新选中的笔记
                if selectedNote?.id == updatedNote.id {
                    selectedNote = updatedNote
                }
                
            case .failure(let error):
                print("[NotesViewModel] ❌ 笔记保存失败: \(error)")
                
                // 通知 changeTracker 保存失败
                // _Requirements: FR-4.2, FR-4.3_
                nativeEditorContext.changeTracker.didSaveFail()
                
                // 保存失败时，版本号机制会保持 needsSave 状态
                // 后续会自动重试
            }
        }
    }
    
    @MainActor
    private func handleNetworkRestored() {
        print("[VIEWMODEL] 网络已恢复，开始处理待同步操作")
        // 注意：OfflineOperationProcessor 现在会自动响应在线状态变化
        // 这里可以保留作为备用触发方式，或者移除
        Task {
            // 延迟一下，确保网络完全恢复
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
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
        var tagValue: String? = nil
        
        // 优先从 data.entry.tag 获取
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any] {
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
           let entry = data["entry"] as? [String: Any] {
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
        return response["description"] as? String 
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
        print("[OfflineQueue] 统一处理错误并添加到离线队列: \(operationType.rawValue), noteId: \(noteId), context: \(context)")
        
        // 将操作数据编码为 Data
        guard let data = try? JSONSerialization.data(withJSONObject: operationData, options: []) else {
            print("[OfflineQueue] ❌ 无法编码操作数据")
            return false
        }
        
        // 使用 ErrorRecoveryService 统一处理错误（需求 8.1, 8.7）
        let result = ErrorRecoveryService.shared.handleNetworkError(
            operation: operationType,
            noteId: noteId,
            data: data,
            error: error,
            context: context
        )
        
        switch result {
        case .addedToQueue(let message):
            print("[OfflineQueue] ✅ \(message): \(operationType.rawValue)")
            // 如果是 Cookie 过期，设置离线状态
            if case MiNoteError.cookieExpired = error {
                setOfflineStatus(reason: "Cookie过期")
            }
            return true
            
        case .noRetry(let message):
            print("[OfflineQueue] ⚠️ 不重试: \(message)")
            return false
            
        case .permanentlyFailed(let message):
            print("[OfflineQueue] ❌ 永久失败: \(message)")
            // 显示错误消息给用户
            errorMessage = message
            // 3秒后清除错误消息
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
            // 使用 JSONSerialization 编码 [String: Any] 字典
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
            print("[OfflineQueue] ❌ 编码操作数据失败: \(error)")
            return false
        }
    }
    
    /// 设置离线状态
    /// 
    /// - Parameter reason: 离线原因（用于日志）
    @MainActor
    private func setOfflineStatus(reason: String) {
        print("[OfflineStatus] 设置为离线状态，原因: \(reason)")
        isOnline = false
        isCookieExpired = true
        
        // 仅在首次设置为离线时显示提示
        if !cookieExpiredShown {
            cookieExpiredShown = true
            errorMessage = "已切换到离线模式。操作将保存到离线队列，请重新登录后同步。"
            
            // 3秒后清除错误消息
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
        guard service.hasValidCookie() else {
            print("[OfflineStatus] Cookie仍然无效，不能恢复在线状态")
            return
        }
        
        print("[OfflineStatus] 恢复在线状态")
        // 状态标志的清除由 AuthenticationStateManager 处理
        // 这里只需要刷新 OnlineStateManager 的状态，然后检查是否需要处理待同步操作
        
        // 刷新在线状态（会触发状态同步）
        OnlineStateManager.shared.refreshStatus()
        
        // 等待状态同步后检查是否在线
        // 由于状态是响应式的，我们需要稍微延迟一下以确保状态已更新
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            
            if isOnline {
                print("[OfflineStatus] ✅ 已恢复在线状态，开始处理待同步操作")
                // 触发离线队列处理
                await processPendingOperations()
            } else {
                print("[OfflineStatus] ⚠️ Cookie已恢复，但网络未连接或状态未同步，仍保持离线状态")
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
        // 确保在线且已认证
        guard isOnline && service.isAuthenticated() else {
            print("[VIEWMODEL] 网络未恢复或未认证，跳过处理离线操作")
            return
        }
        
        print("[VIEWMODEL] 触发 OperationProcessor 处理待同步操作")
        
        // 触发操作处理器处理队列
        Task {
            await operationProcessor.processQueue()
        }
    }
    
    
    private func loadLocalData() {
        // 根据登录状态决定数据加载策略
        // _Requirements: 1.1, 1.2, 1.3_
        
        let isUserLoggedIn = service.isAuthenticated()
        print("[NotesViewModel] loadLocalData - 登录状态: \(isUserLoggedIn)")
        
        // 尝试从本地存储加载数据
        do {
            let localNotes = try localStorage.getAllLocalNotes()
            if !localNotes.isEmpty {
                self.notes = localNotes
                print("[NotesViewModel] 从本地存储加载了 \(localNotes.count) 条笔记")
            } else  {
                self.notes = []
                print("[NotesViewModel] 无笔记数据，显示空列表")
            } 
        } catch {
            // _Requirements: 1.5 - 加载本地数据时发生错误，记录错误日志并显示空列表
            print("[NotesViewModel] 加载本地数据失败: \(error)")
            self.notes = []
        }
        
        // 加载文件夹（优先从本地存储加载）
        loadFolders()
        
        // _Requirements: 1.4 - 加载完成后立即更新 UI
        objectWillChange.send()
    }
    
    public func loadFolders() {
        print("[FolderRename] 开始加载文件夹列表")
        
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
                    foldersWithCount.insert(Folder(id: "starred", name: "置顶", count: notes.filter { $0.isStarred }.count, isSystem: true), at: insertIndex)
                }
                
                let currentHasStarred = foldersWithCount.contains { $0.id == "starred" }
                if !hasPrivateNotes {
                    let privateNotesCount = notes.filter { $0.folderId == "2" }.count
                    let insertIndex = min((currentHasAllNotes ? 1 : 0) + (currentHasStarred ? 1 : 0), foldersWithCount.count)
                    foldersWithCount.insert(Folder(id: "2", name: "私密笔记", count: privateNotesCount, isSystem: true), at: insertIndex)
                }
                
                // 回收站不再作为文件夹显示，而是作为按钮
                
                // 更新文件夹计数
                for i in 0..<foldersWithCount.count {
                    let folder = foldersWithCount[i]
                    if folder.id == "0" {
                        foldersWithCount[i].count = notes.count
                    } else if folder.id == "starred" {
                        foldersWithCount[i].count = notes.filter { $0.isStarred }.count
                    } else if folder.id == "2" {
                        // 私密笔记文件夹：显示 folderId 为 "2" 的笔记
                        foldersWithCount[i].count = notes.filter { $0.folderId == "2" }.count
                    } else if folder.id == "uncategorized" {
                        // 未分类文件夹：显示 folderId 为 "0" 或空的笔记
                        foldersWithCount[i].count = notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }.count
                    } else {
                        foldersWithCount[i].count = notes.filter { $0.folderId == folder.id }.count
                    }
                }
                
                self.folders = foldersWithCount
                
                // 强制触发 UI 更新
                objectWillChange.send()
            } else {
                // 如果没有本地文件夹数据，加载示例数据
                // loadSampleFolders()
            }
        } catch {
            print("[VIEWMODEL] 加载文件夹失败: \(error)")
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
           let sortField = NoteSortOrder(rawValue: sortFieldString) {
            notesListSortField = sortField
        }
        if let sortDirectionString = defaults.string(forKey: "notesListSortDirection"),
           let sortDirection = SortDirection(rawValue: sortDirectionString) {
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
           let decoded = try? JSONDecoder().decode([String: NoteSortOrder].self, from: jsonData) {
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
            guard let self = self else { return }
            
            let defaults = UserDefaults.standard
            
        // 尝试恢复上次选中的文件夹
        var restoredFolder: Folder?
        let currentFolders = self.folders
        if let lastFolderId = defaults.string(forKey: "lastSelectedFolderId"),
           let folder = currentFolders.first(where: { $0.id == lastFolderId }) {
            restoredFolder = folder
            self.selectedFolder = folder
            print("[VIEWMODEL] 已恢复上次选中的文件夹: \(lastFolderId)")
        } else {
            // 没有上次选中的文件夹，默认选择"所有笔记"
            restoredFolder = currentFolders.first(where: { $0.id == "0" })
            self.selectedFolder = restoredFolder
            print("[VIEWMODEL] 默认选择所有笔记文件夹")
        }
        
        // 获取当前文件夹中的笔记列表
        let notesInFolder = self.getNotesInFolder(restoredFolder)
        let currentNotes = self.notes
        
        // 尝试恢复上次选中的笔记
        if let lastNoteId = defaults.string(forKey: "lastSelectedNoteId"),
           let lastNote = currentNotes.first(where: { $0.id == lastNoteId }) {
            // 检查笔记是否在当前文件夹中
            if notesInFolder.contains(where: { $0.id == lastNoteId }) {
                // 笔记在当前文件夹中，选中它
                self.selectedNote = lastNote
                print("[VIEWMODEL] 已恢复上次选中的笔记: \(lastNoteId)")
            } else {
                // 笔记不在当前文件夹中，选择当前文件夹的第一个笔记
                self.selectedNote = notesInFolder.first
                print("[VIEWMODEL] 笔记不在当前文件夹，选择第一个笔记")
            }
        } else {
            // 没有上次选中的笔记，选择当前文件夹的第一个笔记
            self.selectedNote = notesInFolder.first
            print("[VIEWMODEL] 选择当前文件夹的第一个笔记")
        }
        }
    }
    
    /// 获取文件夹中的笔记列表
    private func getNotesInFolder(_ folder: Folder?) -> [Note] {
        guard let folder = folder else { return notes }
        
        if folder.id == "starred" {
            return notes.filter { $0.isStarred }
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
    /// _Requirements: 5.1, 5.3, 5.4_
    /// - 5.1: 用户成功登录后自动执行完整同步
    /// - 5.3: 登录后同步失败时显示错误信息并保留本地数据
    /// - 5.4: 登录后同步成功时清除示例数据并显示云端数据
    public func handleLoginSuccess() async {
        print("[NotesViewModel] 🎉 处理登录成功")
        
        // 清除示例数据（如果有）
        // _Requirements: 5.4_
        clearSampleDataIfNeeded()
        
        // 获取用户信息
        await fetchUserProfile()
        
        // 执行完整同步
        // _Requirements: 5.1_
        do {
            print("[NotesViewModel] 开始执行登录后完整同步...")
            isSyncing = true
            syncStatusMessage = "正在同步数据..."
            
            let result = try await syncService.performFullSync()
            
            // 同步成功，重新加载本地数据
            // _Requirements: 5.4_
            await reloadDataAfterSync()
            
            isSyncing = false
            syncStatusMessage = "同步完成"
            lastSyncTime = Date()
            lastSyncedNotesCount = result.syncedNotes  // _Requirements: 7.4_
            
            print("[NotesViewModel] ✅ 登录后同步成功，同步了 \(result.syncedNotes) 条笔记")
        } catch {
            // _Requirements: 5.3_
            isSyncing = false
            syncStatusMessage = "同步失败"
            errorMessage = "同步失败: \(error.localizedDescription)"
            print("[NotesViewModel] ❌ 登录后同步失败: \(error)")
        }
    }
    
    /// Cookie刷新成功后的处理
    /// 
    /// 恢复在线状态，执行完整同步
    /// 
    /// _Requirements: 5.2, 5.3, 5.4_
    /// - 5.2: 用户成功刷新Cookie后自动执行完整同步
    /// - 5.3: 同步失败时显示错误信息并保留本地数据
    /// - 5.4: 同步成功时更新本地数据
    public func handleCookieRefreshSuccess() async {
        print("[NotesViewModel] 🔄 处理Cookie刷新成功")
        
        // 恢复在线状态
        restoreOnlineStatus()
        
        // 处理离线队列中的待处理操作
        await processPendingOperations()
        
        // 执行完整同步
        // _Requirements: 5.2_
        do {
            print("[NotesViewModel] 开始执行Cookie刷新后完整同步...")
            isSyncing = true
            syncStatusMessage = "正在同步数据..."
            
            let result = try await syncService.performFullSync()
            
            // 同步成功，重新加载本地数据
            // _Requirements: 5.4_
            await reloadDataAfterSync()
            
            isSyncing = false
            syncStatusMessage = "同步完成"
            lastSyncTime = Date()
            lastSyncedNotesCount = result.syncedNotes  // _Requirements: 7.4_
            
            print("[NotesViewModel] ✅ Cookie刷新后同步成功，同步了 \(result.syncedNotes) 条笔记")
        } catch {
            // _Requirements: 5.3_
            isSyncing = false
            syncStatusMessage = "同步失败"
            errorMessage = "同步失败: \(error.localizedDescription)"
            print("[NotesViewModel] ❌ Cookie刷新后同步失败: \(error)")
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
    /// **需求覆盖**：
    /// - 需求 8.7: 更新 UI 中的笔记引用（selectedNote 等）
    private func handleIdMappingCompleted(localId: String, serverId: String, entityType: String) {
        print("[NotesViewModel] 🔄 处理 ID 映射完成: \(localId.prefix(16))... -> \(serverId.prefix(8))... (\(entityType))")
        
        guard entityType == "note" else {
            // 文件夹 ID 映射暂不处理
            print("[NotesViewModel] ⏭️ 跳过文件夹 ID 映射")
            return
        }
        
        // 1. 更新 selectedNote
        if selectedNote?.id == localId {
            // 创建新的笔记对象，使用正式 ID
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
                print("[NotesViewModel] ✅ 更新 selectedNote ID: \(localId.prefix(16))... -> \(serverId.prefix(8))...")
            }
        }
        
        // 2. 更新 notes 数组中的引用
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
                rawData: oldNote.rawData
            )
            notes[index] = updatedNote
            print("[NotesViewModel] ✅ 更新 notes 数组中的笔记 ID: \(localId.prefix(16))... -> \(serverId.prefix(8))...")
        }
        
        // 3. 通知 UI 更新
        objectWillChange.send()
        
        print("[NotesViewModel] ✅ ID 映射处理完成")
    }
    
    /// 清除示例数据（如果有）
    /// 
    /// 检查当前笔记是否为示例数据，如果是则清除
    /// 
    /// _Requirements: 5.4_
    private func clearSampleDataIfNeeded() {
        // 检查是否有示例数据（示例数据的ID以"sample-"开头）
        let hasSampleData = notes.contains { $0.id.hasPrefix("sample-") }
        
        if hasSampleData {
            print("[NotesViewModel] 清除示例数据")
            // 移除所有示例数据
            notes.removeAll { $0.id.hasPrefix("sample-") }
            
            // 如果当前选中的是示例笔记，清除选中状态
            if let selectedNote = selectedNote, selectedNote.id.hasPrefix("sample-") {
                self.selectedNote = nil
            }
            
            // 更新文件夹计数
            updateFolderCounts()
        }
    }
    
    /// 同步后重新加载数据
    /// 
    /// _Requirements: 5.4_
    private func reloadDataAfterSync() async {
        print("[NotesViewModel] 同步完成，重新加载数据")
        
        do {
            let localNotes = try localStorage.getAllLocalNotes()
            self.notes = localNotes
            print("[NotesViewModel] 重新加载了 \(localNotes.count) 条笔记")
            
            // 重新加载文件夹
            loadFolders()
            updateFolderCounts()
            
            // 更新 UI
            objectWillChange.send()
        } catch {
            print("[NotesViewModel] 重新加载数据失败: \(error)")
        }
    }
    
    // MARK: - 同步功能
    
    /// 执行完整同步
    /// 
    /// 完整同步会清除所有本地数据，然后从云端拉取所有笔记和文件夹
    /// 
    /// **注意**：此操作会丢失所有本地未同步的更改
    func performFullSync() async {
        print("[VIEWMODEL] 开始执行完整同步")
        print("[VIEWMODEL] 检查认证状态...")
        let authStatus = service.isAuthenticated()
        print("[VIEWMODEL] 认证状态: \(authStatus)")
        
        guard authStatus else {
            print("[VIEWMODEL] 错误：未认证")
            print("[VIEWMODEL] Cookie状态: cookie=\(MiNoteService.shared.hasValidCookie())")
            print("[VIEWMODEL] 检查UserDefaults中的cookie...")
            if let savedCookie = UserDefaults.standard.string(forKey: "minote_cookie") {
                print("[VIEWMODEL] UserDefaults中有cookie，长度: \(savedCookie.count) 字符")
                print("[VIEWMODEL] Cookie内容（前100字符）: \(String(savedCookie.prefix(100)))")
            } else {
                print("[VIEWMODEL] UserDefaults中没有cookie")
            }
            errorMessage = "请先登录小米账号"
            return
        }
        
        print("[VIEWMODEL] 检查同步状态...")
        guard !isSyncing else {
            print("[VIEWMODEL] 错误：同步正在进行中")
            errorMessage = "同步正在进行中"
            return
        }
        
        isSyncing = true
        syncProgress = 0
        syncStatusMessage = "开始同步..."
        errorMessage = nil
        
        print("[VIEWMODEL] 同步状态已设置为进行中")
        
        defer {
            isSyncing = false
            print("[VIEWMODEL] 同步结束，isSyncing设置为false")
        }
        
        do {
            print("[FolderRename] ========== performFullSync() 开始 ==========")
            print("[FolderRename] 同步前 folders 数组数量: \(folders.count)")
            print("[FolderRename] 同步前 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
            
            print("[VIEWMODEL] 调用syncService.performFullSync()")
            let result = try await syncService.performFullSync()
            print("[VIEWMODEL] syncService.performFullSync() 成功完成")
            
            // 更新同步结果
            self.syncResult = result
            self.lastSyncTime = result.lastSyncTime
            self.lastSyncedNotesCount = result.syncedNotes  // _Requirements: 7.4_
            
            // 重新加载本地数据
            print("[FolderRename] 同步完成，准备重新加载本地数据...")
            await loadLocalDataAfterSync()
            
            print("[FolderRename] 同步后 folders 数组数量: \(folders.count)")
            print("[FolderRename] 同步后 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
            
            syncProgress = 1.0
            syncStatusMessage = "同步完成: 成功同步 \(result.syncedNotes) 条笔记"
            print("[VIEWMODEL] 同步成功: 同步了 \(result.syncedNotes) 条笔记")
            print("[FolderRename] ========== performFullSync() 完成 ==========")
            
        } catch let error as MiNoteError {
            print("[VIEWMODEL] MiNoteError: \(error)")
            handleMiNoteError(error)
            syncStatusMessage = "同步失败"
        } catch {
            print("[VIEWMODEL] 其他错误: \(error)")
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
            self.syncResult = result
            self.lastSyncTime = result.lastSyncTime
            self.lastSyncedNotesCount = result.syncedNotes  // _Requirements: 7.4_
            
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
        print("[FolderRename] ========== loadLocalDataAfterSync() 开始 ==========")
        print("[FolderRename] 同步前 folders 数组数量: \(folders.count)")
        print("[FolderRename] 同步前 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
        
        do {
            // 保存当前选中的笔记ID
            let currentSelectedNoteId = selectedNote?.id
            
            // 关键修复：检查原生编辑器是否有未保存的更改
            // 如果有未保存的更改，不应该用云端数据覆盖用户正在编辑的内容
            let hasUnsavedChanges = nativeEditorContext.hasUnsavedChanges
            
            // 🛡️ 统一操作队列集成：检查笔记是否正在活跃编辑
            let isActivelyEditing: Bool
            if let noteId = currentSelectedNoteId {
                isActivelyEditing = await NoteOperationCoordinator.shared.isNoteActivelyEditing(noteId)
            } else {
                isActivelyEditing = false
            }
            
            // 🛡️ 统一操作队列集成：检查笔记是否在待上传列表中
            // 使用 UnifiedOperationQueue 替代废弃的 PendingUploadRegistry
            let isPendingUpload: Bool
            if let noteId = currentSelectedNoteId {
                isPendingUpload = UnifiedOperationQueue.shared.hasPendingUpload(for: noteId)
            } else {
                isPendingUpload = false
            }
            
            let localNotes = try localStorage.getAllLocalNotes()
            self.notes = localNotes
            
            // 重新加载文件夹（从本地存储）
            print("[FolderRename] 调用 loadFolders() 重新加载文件夹列表")
            loadFolders()
            
            print("[FolderRename] 同步后 folders 数组数量: \(folders.count)")
            print("[FolderRename] 同步后 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
            
            // 如果之前有选中的笔记，更新为重新加载的版本（确保内容是最新的）
            if let noteId = currentSelectedNoteId,
               let updatedNote = localNotes.first(where: { $0.id == noteId }) {
                
                // 关键修复：如果用户正在编辑且有未保存的更改，跳过更新 selectedNote
                // 这样可以防止云端同步覆盖用户正在编辑的内容 
                // 🛡️ 统一操作队列集成：增加活跃编辑和待上传检查
                let shouldSkipUpdate = hasUnsavedChanges || isActivelyEditing || isPendingUpload
                
                if shouldSkipUpdate {
                    print("[VIEWMODEL] ⚠️ 同步后跳过更新选中笔记 - 同步保护生效")
                    print("[VIEWMODEL]   - 笔记ID: \(noteId)")
                    print("[VIEWMODEL]   - hasUnsavedChanges: \(hasUnsavedChanges)")
                    print("[VIEWMODEL]   - isActivelyEditing: \(isActivelyEditing)")
                    print("[VIEWMODEL]   - isPendingUpload: \(isPendingUpload)")
                    // 不更新 selectedNote，保留用户正在编辑的内容
                } else {
                    // 没有未保存的更改，可以安全地更新 selectedNote
                    await MainActor.run {
                        self.selectedNote = updatedNote
                        print("[VIEWMODEL] 同步后更新选中笔记: \(noteId)")
                    }
                }
            } else {
                // 如果没有选中的笔记，尝试恢复上次选中的状态
                restoreLastSelectedState()
            }
            
            print("[FolderRename] ========== loadLocalDataAfterSync() 完成 ==========")
            
        } catch {
            print("[FolderRename] ❌ 同步后加载本地数据失败: \(error)")
            print("[FolderRename] ========== loadLocalDataAfterSync() 失败 ==========")
        }
    }
    
    /// 更新文件夹计数
    private func updateFolderCounts() {
        let currentNotes = self.notes
        // 使用局部变量避免在循环中修改数组
        var updatedFolders = self.folders
        for i in 0..<updatedFolders.count {
            let folder = updatedFolders[i]
            
            if folder.id == "0" {
                // 所有笔记
                updatedFolders[i].count = currentNotes.count
            } else if folder.id == "starred" {
                // 收藏
                updatedFolders[i].count = currentNotes.filter { $0.isStarred }.count
            } else if folder.id == "2" {
                // 私密笔记文件夹：显示 folderId 为 "2" 的笔记
                updatedFolders[i].count = currentNotes.filter { $0.folderId == "2" }.count
            } else if folder.id == "uncategorized" {
                // 未分类文件夹：显示 folderId 为 "0" 或空的笔记
                updatedFolders[i].count = currentNotes.filter { $0.folderId == "0" || $0.folderId.isEmpty }.count
            } else {
                // 普通文件夹
                updatedFolders[i].count = currentNotes.filter { $0.folderId == folder.id }.count
            }
        }
        // 一次性更新数组
        self.folders = updatedFolders
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
    /// - 需求 8.1: 离线时调用 createNoteOffline()
    /// 
    /// - Parameter note: 要创建的笔记对象
    /// - Throws: 创建失败时抛出错误（网络错误、认证错误等）
    public func createNote(_ note: Note) async throws {
        // 检查是否离线或未认证
        // 需求 8.1: 离线时调用 createNoteOffline()，在线时直接创建
        if !isOnline || !service.isAuthenticated() {
            // 离线模式：使用 NoteOperationCoordinator 创建临时 ID 笔记
            print("[VIEWMODEL] 📴 离线模式：使用 NoteOperationCoordinator.createNoteOffline()")
            
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
                
                print("[VIEWMODEL] ✅ 离线笔记创建成功，临时 ID: \(offlineNote.id.prefix(16))...")
            } catch {
                print("[VIEWMODEL] ❌ 离线笔记创建失败: \(error)")
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
                   let entry = data["entry"] as? [String: Any] {
                    noteId = entry["id"] as? String
                    tag = entry["tag"] as? String
                    entryData = entry
                    print("[VIEWMODEL] 从 data.entry 获取笔记信息: id=\(noteId ?? "nil"), tag=\(tag ?? "nil")")
                }
            } else {
                // 兼容旧格式：直接在响应根级别
                noteId = response["id"] as? String
                tag = response["tag"] as? String
                entryData = response
                print("[VIEWMODEL] 使用旧格式响应: id=\(noteId ?? "nil"), tag=\(tag ?? "nil")")
            }
            
            if let noteId = noteId, let tag = tag, !tag.isEmpty {
                // 获取服务器返回的 folderId（如果有）
                let serverFolderId: String
                if let entryData = entryData, let folderIdValue = entryData["folderId"] {
                    if let folderIdInt = folderIdValue as? Int {
                        serverFolderId = String(folderIdInt)
                    } else if let folderIdStr = folderIdValue as? String {
                        serverFolderId = folderIdStr
                    } else {
                        serverFolderId = note.folderId
                    }
                } else {
                    serverFolderId = note.folderId
                }
                
                // 更新 rawData，包含完整的 entry 数据
                var updatedRawData = note.rawData ?? [:]
                if let entryData = entryData {
                    for (key, value) in entryData {
                        updatedRawData[key] = value
                    }
                }
                updatedRawData["tag"] = tag
                
                // 如果本地笔记的 ID 与服务器返回的不同，需要创建新笔记并删除旧的
                if note.id != noteId {
                    // 创建新的笔记对象（使用服务器返回的 ID 和 folderId）
                    let updatedNote = Note(
                        id: noteId,
                        title: note.title,
                        content: note.content,
                        folderId: serverFolderId, // 使用服务器返回的 folderId
                        isStarred: note.isStarred,
                        createdAt: note.createdAt,
                        updatedAt: note.updatedAt,
                        tags: note.tags,
                        rawData: updatedRawData
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
                    // ID 相同，更新现有笔记
                    let updatedNote = Note(
                        id: note.id,
                        title: note.title,
                        content: note.content,
                        folderId: note.folderId,
                        isStarred: note.isStarred,
                        createdAt: note.createdAt,
                        updatedAt: note.updatedAt,
                        tags: note.tags,
                        rawData: updatedRawData
                    )
                    
                    // 更新笔记列表
                    if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                        if index < self.notes.count {
                            self.notes[index] = updatedNote
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
                    "folderId": note.folderId
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
    /// **需求覆盖**：
    /// - 需求 2.1: 本地保存完成且网络可用时立即尝试上传
    /// 
    /// - Parameter note: 要更新的笔记对象
    /// - Throws: 更新失败时抛出错误（网络错误、认证错误等）
    func updateNote(_ note: Note) async throws {
        print("[VIEWMODEL] updateNote: \(note.id), title: \(note.title)")
        
        // 1. 合并并本地持久化
        let noteToSave = mergeWithLocalData(note)
        
        // 🛡️ 统一操作队列集成：使用 NoteOperationCoordinator 进行保存
        // 需求 2.1: 本地保存后创建 cloudUpload 操作，网络可用时立即处理
        let saveResult = await NoteOperationCoordinator.shared.saveNote(noteToSave)
        
        switch saveResult {
        case .success:
            print("[VIEWMODEL] ✅ 通过 NoteOperationCoordinator 保存成功: \(note.id.prefix(8))...")
            // 更新内存列表
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = noteToSave
            }
            // 更新 selectedNote
            if selectedNote?.id == note.id {
                selectedNote = noteToSave
            }
        case .failure(let error):
            print("[VIEWMODEL] ❌ 通过 NoteOperationCoordinator 保存失败: \(error)")
            throw error
        }
        
        // 2. 检查同步状态（云端上传由 NoteOperationCoordinator 自动处理）
        // 如果离线，操作已经被添加到 UnifiedOperationQueue
        guard isOnline && service.isAuthenticated() else {
            print("[VIEWMODEL] 📴 离线模式，操作已加入 UnifiedOperationQueue 等待网络恢复")
            return
        }
    }
    
    private func mergeWithLocalData(_ note: Note) -> Note {
        guard let existingNote = try? localStorage.loadNote(noteId: note.id),
              let existingRawData = existingNote.rawData else {
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
           !existingSettingData.isEmpty {
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
            "folderId": note.folderId
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
            print("[VIEWMODEL] updateNoteInPlace: 笔记不存在于数组中, id=\(note.id)")
            return false
        }
        
        // 直接更新数组中的元素，不触发整个数组的重新发布
        // 由于 @Published 的特性，单个元素的更新会触发最小化的 UI 更新
        notes[index] = note
        
        // 如果当前选中的是这个笔记，同步更新 selectedNote
        // 但不改变选择状态本身
        if selectedNote?.id == note.id {
            selectedNote = note
        }
        
        print("[VIEWMODEL] updateNoteInPlace: 成功更新笔记, id=\(note.id), title=\(note.title)")
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
        guard !updates.isEmpty else {
            print("[VIEWMODEL] batchUpdateNotes: 没有需要更新的笔记")
            return
        }
        
        print("[VIEWMODEL] batchUpdateNotes: 开始批量更新 \(updates.count) 个笔记")
        
        // 使用 withAnimation 包装更新操作，提供 300ms 的 easeInOut 动画 
        withAnimation(.easeInOut(duration: 0.3)) {
            for (noteId, update) in updates {
                if let index = notes.firstIndex(where: { $0.id == noteId }) {
                    // 应用更新闭包
                    update(&notes[index])
                    
                    // 如果当前选中的是这个笔记，同步更新 selectedNote
                    if selectedNote?.id == noteId {
                        selectedNote = notes[index]
                    }
                    
                    print("[VIEWMODEL] batchUpdateNotes: 更新笔记 id=\(noteId)")
                } else {
                    print("[VIEWMODEL] batchUpdateNotes: 笔记不存在, id=\(noteId)")
                }
            }
        }
        
        print("[VIEWMODEL] batchUpdateNotes: 批量更新完成")
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
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else {
            print("[VIEWMODEL] updateNoteTimestamp: 笔记不存在, id=\(noteId)")
            return false
        }
        
        // 使用动画更新时间戳
        withAnimation(.easeInOut(duration: 0.3)) {
            notes[index].updatedAt = timestamp
            
            // 如果当前选中的是这个笔记，同步更新 selectedNote
            if selectedNote?.id == noteId {
                selectedNote = notes[index]
            }
        }
        
        print("[VIEWMODEL] updateNoteTimestamp: 更新笔记时间戳, id=\(noteId), timestamp=\(timestamp)")
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
        
        // 10017 通常是 tag 冲突代码
        if code == 10017 && retryOnConflict {
            print("[VIEWMODEL] 检测到 Tag 冲突，尝试拉取最新状态并重试...")
            let details = try await service.fetchNoteDetails(noteId: note.id)
            if let entry = extractEntry(from: details) {
                var updatedWithNewTag = note
                var raw = note.rawData ?? [:]
                for (k, v) in entry { raw[k] = v }
                updatedWithNewTag.rawData = raw
                // 递归重试一次，不再允许冲突重试
                try await performCloudUpdateWithRetry(updatedWithNewTag, retryOnConflict: false)
                return
            }
        }
        
        if code == 0 {
            if let entry = extractEntry(from: response) {
                var updatedNote = note
                var updatedRawData = updatedNote.rawData ?? [:]
                for (key, value) in entry { updatedRawData[key] = value }

                if let modifyDate = entry["modifyDate"] as? Int {
                    updatedNote.updatedAt = Date(timeIntervalSince1970: TimeInterval(modifyDate) / 1000)
                }
                updatedNote.rawData = updatedRawData

                // 再次应用本地更新（包含 ID 守卫判断）
                try await applyLocalUpdate(updatedNote)
            }
        } else {
            let message = response["message"] as? String ?? "更新笔记失败"
            print("[[调试]]步骤48.1 [VIEWMODEL] 更新笔记失败，code: \(code), message: \(message)")
            throw NSError(domain: "MiNote", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    /// 统一处理更新时的错误（内部方法）
    private func handleUpdateError(_ error: Error, for note: Note) {
        // 使用 ErrorRecoveryService 统一处理错误（需求 8.1, 8.7）
        let operationData: [String: Any] = [
            "title": note.title,
            "content": note.content,
            "folderId": note.folderId,
            "tag": note.rawData?["tag"] as? String ?? note.id
        ]
        
        // 将操作数据编码为 Data
        guard let data = try? JSONSerialization.data(withJSONObject: operationData, options: []) else {
            print("[VIEWMODEL] ❌ 无法编码操作数据")
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
        case .addedToQueue(let message):
            print("[VIEWMODEL] \(message)，笔记ID: \(note.id)")
        case .noRetry(let message):
            print("[VIEWMODEL] 更新失败（不重试）: \(message)，笔记ID: \(note.id)")
        case .permanentlyFailed(let message):
            print("[VIEWMODEL] ⚠️ 更新永久失败: \(message)，笔记ID: \(note.id)")
            // 显示错误消息给用户
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
    /// _需求: 3.5_
    func ensureNoteHasFullContent(_ note: Note) async {
        // 性能监控：记录开始时间
        // _需求: 3.5_
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 如果笔记已经有完整内容，不需要获取
        if !note.content.isEmpty {
            let skipDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[性能监控] ⏱️ ensureNoteHasFullContent 跳过（已有内容）耗时: \(String(format: "%.2f", skipDuration))ms")
            return
        }
        
        // 如果连 snippet 都没有，可能笔记不存在，不需要获取
        if note.rawData?["snippet"] == nil {
            let skipDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[性能监控] ⏱️ ensureNoteHasFullContent 跳过（无 snippet）耗时: \(String(format: "%.2f", skipDuration))ms")
            return
        }
        
        print("[VIEWMODEL] 笔记内容为空，获取完整内容: \(note.id)")
        
        do {
            // 获取笔记详情
            let noteDetails = try await service.fetchNoteDetails(noteId: note.id)
            
            // 更新笔记内容
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                var updatedNote = notes[index]
                
                // 4.1 保存原始时间戳
                let originalUpdatedAt = updatedNote.updatedAt
                let originalContent = updatedNote.content
                let originalTitle = updatedNote.title
                
                // 增强日志：记录 ensureNoteHasFullContent 的详细信息
                // _需求: 3.3_
                print("[VIEWMODEL] [ensureNoteHasFullContent] ═══════════════════════════════════════")
                print("[VIEWMODEL] [ensureNoteHasFullContent] 📝 笔记ID: \(note.id.prefix(8))...")
                print("[VIEWMODEL] [ensureNoteHasFullContent] 🕐 原始时间戳: \(originalUpdatedAt)")
                print("[VIEWMODEL] [ensureNoteHasFullContent] 📏 原始内容长度: \(originalContent.count)")
                
                updatedNote.updateContent(from: noteDetails)
                print("[VIEWMODEL] [ensureNoteHasFullContent] ✅ 内容更新完成")
                print("[VIEWMODEL] [ensureNoteHasFullContent] 📏 新内容长度: \(updatedNote.content.count)")
                
                // 4.2 检测内容实际变化
                let contentActuallyChanged = hasContentActuallyChanged(
                    currentContent: updatedNote.content,
                    savedContent: originalContent,
                    currentTitle: updatedNote.title,
                    originalTitle: originalTitle
                )
                
                // 4.3 添加调试日志
                print("[VIEWMODEL] [ensureNoteHasFullContent] 📊 内容变化检测结果: \(contentActuallyChanged)")
                
                // 如果内容无实际变化，恢复原始时间戳
                if !contentActuallyChanged {
                    updatedNote.updatedAt = originalUpdatedAt
                    print("[VIEWMODEL] [ensureNoteHasFullContent] 🕐 内容无实际变化，恢复原始时间戳: \(originalUpdatedAt)")
                    print("[VIEWMODEL] [ensureNoteHasFullContent] ✅ 时间戳决策: 保持不变")
                } else {
                    print("[VIEWMODEL] [ensureNoteHasFullContent] 🕐 内容有实际变化，保持新时间戳: \(updatedNote.updatedAt)")
                    print("[VIEWMODEL] [ensureNoteHasFullContent] ✅ 时间戳决策: 更新")
                }
                print("[VIEWMODEL] [ensureNoteHasFullContent] ═══════════════════════════════════════")
                
                // 保存到本地
                print("[VIEWMODEL] [ensureNoteHasFullContent] 💾 保存到本地数据库")
                try localStorage.saveNote(updatedNote)
                
                // 更新列表中的笔记
                // 注意：即使 updatedAt 没有变化，我们仍然需要更新 notes 数组以反映新的内容
                // 但由于 Note 的 Equatable 只比较 id，这不会导致 SwiftUI 认为笔记发生了变化
                notes[index] = updatedNote
                
                // 如果这是当前选中的笔记，更新选中状态
                if selectedNote?.id == note.id {
                    selectedNote = updatedNote
                }
                
                // 性能监控：记录完成时间
                // _需求: 3.5_
                let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                print("[性能监控] ═══════════════════════════════════════")
                print("[性能监控] ⏱️ ensureNoteHasFullContent 总耗时: \(String(format: "%.2f", totalDuration))ms")
                print("[性能监控] 📏 内容长度: \(updatedNote.content.count)")
                print("[性能监控] 🕐 时间戳决策: \(contentActuallyChanged ? "更新" : "保持")")
                if totalDuration > 200 {
                    print("[性能监控] ⚠️ 警告: 内容获取耗时超过 200ms，可能影响用户体验")
                } else {
                    print("[性能监控] ✅ 内容获取性能正常")
                }
                print("[性能监控] ═══════════════════════════════════════")
                
                print("[VIEWMODEL] 已获取并更新笔记完整内容: \(note.id), 内容长度: \(updatedNote.content.count), 时间戳决策: \(contentActuallyChanged ? "更新" : "保持")")
            }
        } catch {
            // 性能监控：记录失败时的耗时
            // _需求: 3.5_
            let errorDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[性能监控] ⏱️ ensureNoteHasFullContent 失败耗时: \(String(format: "%.2f", errorDuration))ms")
            print("[VIEWMODEL] 获取笔记完整内容失败: \(error.localizedDescription)")
            // 不显示错误，因为可能只是网络问题，用户仍然可以查看 snippet
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
    /// _需求: 2.1, 2.2, 3.3_
    private func hasContentActuallyChanged(currentContent: String, savedContent: String, currentTitle: String, originalTitle: String) -> Bool {
        // 记录检测开始时间（用于性能监控）
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 使用 XMLNormalizer 进行语义比较
        // _需求: 2.1.2, 2.1.3_
        let normalizedCurrent = XMLNormalizer.shared.normalize(currentContent)
        let normalizedSaved = XMLNormalizer.shared.normalize(savedContent)
        
        let contentChanged = normalizedCurrent != normalizedSaved
        let titleChanged = currentTitle != originalTitle
        
        // 计算检测耗时
        let elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        // 增强日志：记录详细的内容变化检测信息
        // _需求: 2.1.4, 2.2.1, 2.2.2, 2.2.3, 3.3_
        print("[VIEWMODEL] [内容检测] ═══════════════════════════════════════")
        print("[VIEWMODEL] [内容检测] 📊 检测结果: 内容变化=\(contentChanged), 标题变化=\(titleChanged)")
        print("[VIEWMODEL] [内容检测] 📏 原始内容长度: 当前=\(currentContent.count), 保存=\(savedContent.count)")
        print("[VIEWMODEL] [内容检测] 📏 规范化后长度: 当前=\(normalizedCurrent.count), 保存=\(normalizedSaved.count)")
        print("[VIEWMODEL] [内容检测] ⏱️ 检测耗时: \(String(format: "%.2f", elapsedTime))ms")
        
        if contentChanged {
            // 如果内容长度差异较大，记录更详细的信息
            let originalLengthDiff = abs(currentContent.count - savedContent.count)
            let normalizedLengthDiff = abs(normalizedCurrent.count - normalizedSaved.count)
            
            print("[VIEWMODEL] [内容检测] 📝 原始内容长度差异: \(originalLengthDiff) 字符")
            print("[VIEWMODEL] [内容检测] 📝 规范化后长度差异: \(normalizedLengthDiff) 字符")
            
            if normalizedLengthDiff > 10 {
                print("[VIEWMODEL] [内容检测] ⚠️ 规范化后仍有显著差异，这是实际内容变化")
            } else {
                print("[VIEWMODEL] [内容检测] ℹ️ 规范化后差异较小")
            }
            
            // 如果规范化后内容变化较小，记录前后内容的前100个字符用于调试
            if normalizedLengthDiff <= 50 {
                let currentPreview = String(normalizedCurrent.prefix(100))
                let savedPreview = String(normalizedSaved.prefix(100))
                print("[VIEWMODEL] [内容检测] 🔍 当前内容预览: \(currentPreview)")
                print("[VIEWMODEL] [内容检测] 🔍 保存内容预览: \(savedPreview)")
            }
        } else {
            print("[VIEWMODEL] [内容检测] ✅ 内容无变化（规范化后相同）")
            
            // 如果原始内容不同但规范化后相同，说明只是格式差异
            if currentContent != savedContent {
                let originalLengthDiff = abs(currentContent.count - savedContent.count)
                print("[VIEWMODEL] [内容检测] ℹ️ 原始内容有差异（\(originalLengthDiff) 字符），但规范化后相同 - 这是格式化差异")
            }
        }
        
        if titleChanged {
            print("[VIEWMODEL] [内容检测] 📝 标题变化: '\(originalTitle)' -> '\(currentTitle)'")
        } else {
            print("[VIEWMODEL] [内容检测] ✅ 标题无变化")
        }
        
        // 记录时间戳更新决策
        // _需求: 3.2.3, 3.3_
        let shouldUpdateTimestamp = contentChanged || titleChanged
        print("[VIEWMODEL] [内容检测] 🕐 时间戳决策: \(shouldUpdateTimestamp ? "需要更新" : "保持不变")")
        print("[VIEWMODEL] [内容检测] ═══════════════════════════════════════")
        
        return contentChanged || titleChanged
    }
    
    func deleteNote(_ note: Note) {
        // 检查是否为临时 ID 笔记（离线创建的笔记）
        // 需求 8.8: 临时 ID 笔记被删除时取消 noteCreate 操作
        if NoteOperation.isTemporaryId(note.id) {
            print("[VIEWMODEL] 🗑️ 删除临时 ID 笔记: \(note.id.prefix(16))...")
            
            // 1. 先在本地删除（UI 更新）
            if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                if index < self.notes.count {
                    self.notes.remove(at: index)
                }
                
                // 更新文件夹计数
                if let folderIndex = folders.firstIndex(where: { $0.id == note.folderId }) {
                    folders[folderIndex].count = max(0, folders[folderIndex].count - 1)
                }
                
                // 如果删除的是当前选中的笔记，清空选择
                if selectedNote?.id == note.id {
                    selectedNote = nil
                }
            }
            
            // 2. 使用 NoteOperationCoordinator 删除临时 ID 笔记
            // 这会取消 noteCreate 操作并删除本地笔记
            Task {
                do {
                    try await NoteOperationCoordinator.shared.deleteTemporaryNote(note.id)
                    print("[VIEWMODEL] ✅ 临时 ID 笔记删除成功: \(note.id.prefix(16))...")
                } catch {
                    print("[VIEWMODEL] ❌ 临时 ID 笔记删除失败: \(error)")
                }
            }
            return
        }
        
        // 正常笔记删除流程
        // 1. 先在本地删除
        if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
            if index < self.notes.count {
                self.notes.remove(at: index)
            }
            
            // 更新文件夹计数
            if let folderIndex = folders.firstIndex(where: { $0.id == note.folderId }) {
                folders[folderIndex].count = max(0, folders[folderIndex].count - 1)
            }
            
            // 如果删除的是当前选中的笔记，清空选择
            if selectedNote?.id == note.id {
                selectedNote = nil
            }
        }
        
        // 2. 从本地存储删除
        do {
            try localStorage.deleteNote(noteId: note.id)
        } catch {
            print("[VIEWMODEL] 删除本地笔记失败: \(error)")
        }
        
        // 3. 检查在线状态，决定是立即删除还是添加到队列
        guard isOnline && service.isAuthenticated() else {
            print("[VIEWMODEL] 离线状态，将删除操作添加到队列")
            
            // 离线状态，直接添加到队列
            let tag = note.rawData?["tag"] as? String ?? note.id
            let operationData: [String: Any] = [
                "tag": tag,
                "purge": false
            ]
            
            // 编码操作数据
            guard let data = try? JSONSerialization.data(withJSONObject: operationData) else {
                print("[VIEWMODEL] ❌ 编码操作数据失败")
                return
            }
            
            // 创建删除操作
            let operation = NoteOperation(
                type: .cloudDelete,
                noteId: note.id,
                data: data,
                status: .pending,
                priority: NoteOperation.calculatePriority(for: .cloudDelete)
            )
            
            // 添加到队列
            do {
                try unifiedQueue.enqueue(operation)
                print("[VIEWMODEL] ✅ 删除操作已添加到队列: \(note.id)")
            } catch {
                print("[VIEWMODEL] ❌ 添加删除操作到队列失败: \(error)")
            }
            
            return
        }
        
        // 4. 在线状态，尝试使用API删除云端
        Task {
            do {
                // 总是先从服务器获取最新的 tag（确保使用最新的 tag）
                var finalTag = note.rawData?["tag"] as? String ?? note.id
                
                print("[VIEWMODEL] 删除笔记前，尝试从服务器获取最新 tag，当前 tag: \(finalTag)")
                do {
                    let noteDetails = try await service.fetchNoteDetails(noteId: note.id)
                    if let data = noteDetails["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any],
                       let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                        finalTag = latestTag
                        print("[VIEWMODEL] ✅ 从服务器获取到最新 tag: \(finalTag)（之前: \(note.rawData?["tag"] as? String ?? "nil")）")
                    } else {
                        print("[VIEWMODEL] ⚠️ 服务器响应中没有 tag，使用本地 tag: \(finalTag)")
                    }
                } catch {
                    print("[VIEWMODEL] ⚠️ 获取最新 tag 失败: \(error)，将使用本地 tag: \(finalTag)")
                    // 如果获取失败，继续使用本地 tag
                }
                
                // 确保 tag 不为空
                if finalTag.isEmpty {
                    finalTag = note.id
                    print("[VIEWMODEL] ⚠️ tag 最终为空，使用 noteId: \(finalTag)")
                }
                
                // 调用删除API
                _ = try await service.deleteNote(noteId: note.id, tag: finalTag, purge: false)
                print("[VIEWMODEL] 云端删除成功: \(note.id)")
                
            } catch {
                print("[VIEWMODEL] 云端删除失败: \(error)，使用 ErrorRecoveryService 处理")
                
                // 使用 ErrorRecoveryService 统一处理错误
                let tag = note.rawData?["tag"] as? String ?? note.id
                let operationData: [String: Any] = [
                    "tag": tag,
                    "purge": false
                ]
                
                // 编码操作数据
                guard let data = try? JSONSerialization.data(withJSONObject: operationData) else {
                    print("[VIEWMODEL] ❌ 编码操作数据失败")
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
                case .addedToQueue(let message):
                    print("[VIEWMODEL] \(message)，笔记ID: \(note.id)")
                case .noRetry(let message):
                    print("[VIEWMODEL] 删除失败（不重试）: \(message)，笔记ID: \(note.id)")
                case .permanentlyFailed(let message):
                    print("[VIEWMODEL] ⚠️ 删除永久失败: \(message)，笔记ID: \(note.id)")
                    await MainActor.run {
                        self.errorMessage = message
                        // 3秒后清除错误消息
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            self?.errorMessage = nil
                        }
                    }
                }
            }
        }
    }
    
    public func toggleStar(_ note: Note) {
        if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
            if index < self.notes.count {
                self.notes[index].isStarred.toggle()
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
           let jsonString = String(data: encoded, encoding: .utf8) {
            defaults.set(jsonString, forKey: "folderSortOrders")
        }
    }
    
    /// 获取文件夹的排序方式
    /// 
    /// - Parameter folder: 文件夹
    /// - Returns: 排序方式，如果没有设置则返回 nil
    func getFolderSortOrder(_ folder: Folder) -> NoteSortOrder? {
        return folderSortOrders[folder.id]
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
        if let folder = folder, folder.id == "2" {
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
        let notesInNewFolder: [Note]
        if let folder = folder {
            if folder.id == "starred" {
                notesInNewFolder = notes.filter { $0.isStarred }
            } else if folder.id == "0" {
                notesInNewFolder = notes
            } else if folder.id == "2" {
                // 私密笔记文件夹：显示 folderId 为 "2" 的笔记
                notesInNewFolder = notes.filter { $0.folderId == "2" }
            } else if folder.id == "uncategorized" {
                notesInNewFolder = notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }
            } else {
                notesInNewFolder = notes.filter { $0.folderId == folder.id }
            }
        } else {
            notesInNewFolder = []
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
    /// - 4.1: 通过 coordinator 作为单一数据源管理状态
    /// - 4.2: 按顺序更新 Notes_List_View 和 Editor
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
    /// - 4.3: 验证笔记是否属于当前文件夹
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
        // 🛡️ Spec 60: 防止在切换过程中被打断
        guard !isSwitchingNote else {
            print("[VIEWMODEL] ⚠️ 正在切换笔记，忽略新的切换请求")
            return
        }
        
        // 🛡️ Spec 60: 防抖检查 - 防止快速连续切换
        if let lastTime = lastSwitchTime {
            let timeSinceLastSwitch = Date().timeIntervalSince(lastTime)
            if timeSinceLastSwitch < switchDebounceInterval {
                print("[VIEWMODEL] ⚠️ 切换过快，忽略 - 距上次切换: \(String(format: "%.3f", timeSinceLastSwitch))s")
                return
            }
        }
        
        // 记录本次切换时间
        lastSwitchTime = Date()
        
        isSwitchingNote = true
        defer { 
            isSwitchingNote = false
            print("[VIEWMODEL] ✅ 笔记切换完成，重置标志")
        }
        
        Task {
            // 🛡️ 统一操作队列集成：切换笔记前的处理
            let previousNoteId = selectedNote?.id
            
            // 如果有之前选中的笔记且有未保存的更改，先保存
            if let prevId = previousNoteId,
               let prevNote = notes.first(where: { $0.id == prevId }),
               nativeEditorContext.hasUnsavedChanges {
                print("[VIEWMODEL] 🛡️ 切换笔记前保存: \(prevId.prefix(8))...")
                do {
                    try await NoteOperationCoordinator.shared.saveNoteImmediately(prevNote)
                } catch {
                    print("[VIEWMODEL] ⚠️ 切换笔记前保存失败: \(error)")
                }
            }
            
            // 🛡️ 统一操作队列集成：设置新的活跃编辑笔记
            await NoteOperationCoordinator.shared.setActiveEditingNote(note?.id)
            
            await stateCoordinator.selectNote(note)
            // 同步 coordinator 的状态到 ViewModel
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
        let systemFolders = folders.filter { $0.isSystem }
        var userFolders = folders.filter { !$0.isSystem }
        userFolders.append(newFolder)
        try localStorage.saveFolders(userFolders)
        
        // 更新视图数据（系统文件夹在前）
        folders = systemFolders + userFolders
        
        // 如果离线或未认证，添加到统一操作队列
        if !isOnline || !service.isAuthenticated() {
            let operationData = try JSONEncoder().encode([
                "name": name
            ])
            let operation = NoteOperation(
                type: .folderCreate,
                noteId: tempFolderId, // 对于文件夹操作，使用 folderId
                data: operationData,
                status: .pending,
                priority: NoteOperation.calculatePriority(for: .folderCreate)
            )
            try unifiedQueue.enqueue(operation)
            print("[VIEWMODEL] 离线模式：文件夹已保存到本地，等待同步: \(tempFolderId)")
            // 刷新文件夹列表
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
                   let entry = data["entry"] as? [String: Any] {
                    // 处理 ID（可能是 String 或 Int）
                    if let idString = entry["id"] as? String {
                        folderId = idString
                    } else if let idInt = entry["id"] as? Int {
                        folderId = String(idInt)
                    }
                    folderName = entry["subject"] as? String ?? name
                    entryData = entry
                    print("[VIEWMODEL] 从 data.entry 获取文件夹信息: id=\(folderId ?? "nil"), name=\(folderName ?? "nil")")
                }
            }
            
            if let folderId = folderId, let folderName = folderName {
                // 如果服务器返回的 ID 与本地不同，需要更新
                if tempFolderId != folderId {
                    // 1. 更新所有使用旧文件夹ID的笔记，将它们的 folder_id 更新为新ID
                    try DatabaseService.shared.updateNotesFolderId(oldFolderId: tempFolderId, newFolderId: folderId)
                    
                    // 2. 更新内存中的笔记列表
                    self.notes = self.notes.map { note in
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
                    let systemFolders = folders.filter { $0.isSystem }
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
                    
                    print("[VIEWMODEL] ✅ 文件夹ID已更新: \(tempFolderId) -> \(folderId), 并删除了旧文件夹记录")
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
                    let systemFolders = folders.filter { $0.isSystem }
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
                    "name": name
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
            if let index = self.folders.firstIndex(where: { $0.id == folder.id }) {
                if index < self.folders.count {
                    self.folders[index].isPinned.toggle()
                    try? localStorage.saveFolders(self.folders.filter { !$0.isSystem })
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
            print("[VIEWMODEL] 离线模式：文件夹置顶状态已更新: \(folder.id)")
            return
        }
        
        // 在线模式：保存到本地数据库（置顶状态是本地功能，不需要同步到云端）
        print("[VIEWMODEL] 文件夹置顶状态已更新: \(folder.id)")
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
            
            // 强制触发 UI 更新（通过 objectWillChange）
            objectWillChange.send()
            
            try localStorage.saveFolders(folders.filter { !$0.isSystem })
            
            // 确保 selectedFolder 也更新（使用新的 updatedFolder 实例）
            if selectedFolder?.id == folder.id {
                selectedFolder = updatedFolder
                print("[VIEWMODEL] ✅ 已更新 selectedFolder（初始）: \(newName)")
            }
            
            // 打印调试信息
            print("[VIEWMODEL] 🔍 调试：初始更新后，文件夹名称 = \(updatedFolder.name)")
        } else {
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
        }
        
        // 如果离线或未认证，添加到统一操作队列（本地已更新，等待上线后同步）
        if !isOnline || !service.isAuthenticated() {
            print("[FolderRename] ========== 离线模式 ==========")
            print("[FolderRename] isOnline: \(isOnline), isAuthenticated: \(service.isAuthenticated())")
            print("[FolderRename] 文件夹已在本地重命名（'\(folder.name)' -> '\(newName)'），添加到统一操作队列")
            
            let operationData = try JSONEncoder().encode([
                "oldName": folder.name,  // 保存原始名称（重命名前的名称）
                "newName": newName       // 保存新名称
            ])
            let operation = NoteOperation(
                type: .folderRename,
                noteId: folder.id, // 对于文件夹操作，使用 folderId
                data: operationData,
                status: .pending,
                priority: NoteOperation.calculatePriority(for: .folderRename)
            )
            try unifiedQueue.enqueue(operation)
            print("[FolderRename] ✅ 离线重命名操作已添加到队列: \(folder.id)")
            print("[FolderRename] ========== 离线模式处理完成 ==========")
            return
        }
        
        // 在线模式：尝试上传到云端
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            // 获取最新的 tag 和 createDate
            var existingTag = folder.rawData?["tag"] as? String ?? ""
            var originalCreateDate = folder.rawData?["createDate"] as? Int
            
            print("[VIEWMODEL] 上传前获取最新 tag，当前 tag: \(existingTag.isEmpty ? "空" : existingTag)")
            do {
                let folderDetails = try await service.fetchFolderDetails(folderId: folder.id)
                if let data = folderDetails["data"] as? [String: Any],
                   let entry = data["entry"] as? [String: Any] {
                    if let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                        existingTag = latestTag
                        print("[VIEWMODEL] 从服务器获取到最新 tag: \(existingTag)")
                    }
                    if let latestCreateDate = entry["createDate"] as? Int {
                        originalCreateDate = latestCreateDate
                        print("[VIEWMODEL] 从服务器获取到最新 createDate: \(latestCreateDate)")
                    }
                }
            } catch {
                print("[VIEWMODEL] 获取最新文件夹信息失败: \(error)，将使用本地存储的 tag")
            }
            
            if existingTag.isEmpty {
                existingTag = folder.id
                print("[VIEWMODEL] 警告：tag 仍然为空，使用 folderId 作为 fallback: \(existingTag)")
            }
            
            let response = try await service.renameFolder(
                folderId: folder.id,
                newName: newName,
                existingTag: existingTag,
                originalCreateDate: originalCreateDate
            )
            
            // 检查响应是否成功（code == 0 或没有 code 字段但 result == "ok"）
            let code = response["code"] as? Int
            let isSuccess = (code == 0) || (code == nil && response["result"] as? String == "ok")
            
            if isSuccess {
                print("[FolderRename] ========== 云端重命名成功，更新本地数据 ==========")
                print("[FolderRename] 响应 code: \(code ?? -1)")
                print("[FolderRename] 当前 folders 数组数量: \(folders.count)")
                print("[FolderRename] 当前 folders 数组内容: \(folders.map { "\($0.id):\($0.name)" }.joined(separator: ", "))")
                
                // 更新本地文件夹对象（类已经是 @MainActor，不需要额外的 MainActor.run）
                guard let index = folders.firstIndex(where: { $0.id == folder.id }) else {
                    print("[FolderRename] ❌ 错误：在 folders 数组中未找到文件夹，folderId: \(folder.id)")
                    print("[FolderRename] 当前 folders 数组: \(folders.map { "\($0.id):\($0.name)" }.joined(separator: ", "))")
                    throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
                }
                
                print("[FolderRename] ✅ 找到文件夹，索引: \(index)")
                print("[FolderRename] 更新前的文件夹: id=\(folders[index].id), name='\(folders[index].name)'")
                
                // 获取当前文件夹对象
                let currentFolder = folders[index]
                
                // 构建更新的 rawData
                // 先保留原有的 rawData（包含 subject 等字段）
                var updatedRawData: [String: Any] = currentFolder.rawData ?? [:]
                
                // 如果有 data 字段，合并它（包含新的 tag、modifyDate 等）
                if let data = response["data"] as? [String: Any] {
                    // 合并 data，但保留原有的 subject 字段（因为 data 中没有 subject）
                    updatedRawData = updatedRawData.merging(data) { (old, new) in new }
                    print("[FolderRename] 合并 response.data 到 rawData")
                }
                
                // 如果有 entry 字段（根级别），也合并进去（包含完整的文件夹信息）
                if let entry = response["entry"] as? [String: Any] {
                    updatedRawData = updatedRawData.merging(entry) { (_, new) in new }
                    print("[FolderRename] 合并 response.entry 到 rawData")
                }
                
                // 使用统一的提取方法获取 tag
                let tagValue = extractTag(from: response, fallbackTag: existingTag)
                updatedRawData["tag"] = tagValue
                // 确保 subject 字段设置为新名称（因为 API 响应中可能没有 subject）
                updatedRawData["subject"] = newName
                // 确保 id 字段正确
                updatedRawData["id"] = folder.id
                // 确保 type 字段
                updatedRawData["type"] = "folder"
                
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
                
                print("[FolderRename] 更新后的文件夹对象: id=\(updatedFolder.id), name='\(updatedFolder.name)', tag='\(tagValue)'")
                
                // 更新文件夹列表：重新创建数组以确保 SwiftUI 检测到变化
                // 由于 Folder 的 Equatable 只比较 id，我们需要确保创建新数组来触发 SwiftUI 更新
                var updatedFolders = folders
                print("[FolderRename] 更新前 folders 数组引用: \(Unmanaged.passUnretained(folders as AnyObject).toOpaque())")
                updatedFolders[index] = updatedFolder
                folders = updatedFolders
                print("[FolderRename] 更新后 folders 数组引用: \(Unmanaged.passUnretained(folders as AnyObject).toOpaque())")
                print("[FolderRename] 更新后 folders 数组数量: \(folders.count)")
                print("[FolderRename] 更新后 folders 数组内容: \(folders.map { "\($0.id):\($0.name)" }.joined(separator: ", "))")
                
                // 强制触发 UI 更新（通过 objectWillChange）
                print("[FolderRename] 调用 objectWillChange.send() 触发 UI 更新")
                objectWillChange.send()
                
                // 更新选中的文件夹（如果当前选中的是这个文件夹）
                if selectedFolder?.id == folder.id {
                    print("[FolderRename] 更新 selectedFolder: '\(selectedFolder?.name ?? "nil")' -> '\(newName)'")
                    selectedFolder = updatedFolder
                    print("[FolderRename] ✅ selectedFolder 已更新: '\(selectedFolder?.name ?? "nil")'")
                } else {
                    print("[FolderRename] selectedFolder 不是当前文件夹，无需更新")
                }
                
                // 保存到本地存储（保存的是更新后的 folders）
                print("[FolderRename] 保存到本地存储...")
                try localStorage.saveFolders(folders.filter { !$0.isSystem })
                print("[FolderRename] ✅ 已保存到本地存储")
                
                // 验证保存后的数据
                if let savedFolders = try? localStorage.loadFolders() {
                    if let savedFolder = savedFolders.first(where: { $0.id == folder.id }) {
                        print("[FolderRename] ✅ 验证：从数据库读取的文件夹名称 = '\(savedFolder.name)'")
                    } else {
                        print("[FolderRename] ⚠️ 验证：从数据库读取时未找到文件夹")
                    }
                }
                
                print("[FolderRename] ✅ 文件夹重命名成功: \(folder.id) -> \(newName), 新 tag: \(tagValue)")
                print("[FolderRename] ========== 云端重命名完成 ==========")
            } else {
                let errorCode = code ?? -1
                let message = response["description"] as? String ?? response["message"] as? String ?? "重命名文件夹失败"
                print("[VIEWMODEL] 重命名文件夹失败，code: \(errorCode), message: \(message)")
                throw NSError(domain: "MiNote", code: errorCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
        } catch {
            // 使用统一的错误处理和离线队列添加逻辑
            _ = handleErrorAndAddToOfflineQueue(
                error: error,
                operationType: .folderRename,
                noteId: folder.id,
                operationData: [
                    "oldName": folder.name,
                    "newName": newName
                ],
                context: "重命名文件夹"
            )
            // 不设置 errorMessage，避免弹窗提示
        }
    }
    
    /// 删除文件夹
    func deleteFolder(_ folder: Folder) async throws {
        // 如果离线或未认证，先删除本地文件夹，然后添加到离线队列
        if !isOnline || !service.isAuthenticated() {
            print("[VIEWMODEL] 离线模式：先删除本地文件夹，然后添加到离线队列，folderId: \(folder.id)")
            
            // 1. 先删除本地文件夹
            // 删除文件夹的图片目录
            do {
                try LocalStorageService.shared.deleteFolderImageDirectory(folderId: folder.id)
                print("[VIEWMODEL] ✅ 已删除文件夹图片目录: \(folder.id)")
            } catch {
                print("[VIEWMODEL] ⚠️ 删除文件夹图片目录失败: \(error.localizedDescription)")
                // 不抛出错误，继续执行删除操作
            }
            
            // 从本地删除文件夹
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders.remove(at: index)
                // 从数据库删除文件夹记录
                try DatabaseService.shared.deleteFolder(folderId: folder.id)
                // 保存剩余的文件夹列表
                try localStorage.saveFolders(folders.filter { !$0.isSystem })
                if selectedFolder?.id == folder.id {
                    selectedFolder = nil
                }
                print("[VIEWMODEL] ✅ 已从本地删除文件夹: \(folder.id)")
            } else {
                print("[VIEWMODEL] ⚠️ 文件夹列表中未找到要删除的文件夹: \(folder.id)")
            }
            
            // 2. 添加到统一操作队列（只保存 folderID，等待上线后再通过 folderID 查询 tag 并删除）
            let operationDict: [String: Any] = [
                "folderId": folder.id,
                "purge": false
            ]
            
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
            print("[VIEWMODEL] ✅ 离线删除操作已添加到队列: \(folder.id)")
            
            // 刷新文件夹列表和笔记列表
            loadFolders()
            updateFolderCounts()
            return
        }
        
        // 在线模式：执行删除操作
        // 1. 从服务器获取最新的 tag
        var finalTag: String? = nil
        
        print("[VIEWMODEL] 删除文件夹前，从服务器获取最新 tag")
        do {
            let folderDetails = try await service.fetchFolderDetails(folderId: folder.id)
            if let data = folderDetails["data"] as? [String: Any],
               let entry = data["entry"] as? [String: Any],
               let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                finalTag = latestTag
                print("[VIEWMODEL] ✅ 从服务器获取到最新 tag: \(finalTag!)")
            } else {
                // 尝试从 data.tag 获取（如果 entry.tag 不存在）
                if let data = folderDetails["data"] as? [String: Any],
                   let dataTag = data["tag"] as? String, !dataTag.isEmpty {
                    finalTag = dataTag
                    print("[VIEWMODEL] ✅ 从 data.tag 获取到 tag: \(finalTag!)")
                } else {
                    print("[VIEWMODEL] ⚠️ 服务器响应中没有 tag 字段")
                }
            }
        } catch {
            print("[VIEWMODEL] ⚠️ 获取最新文件夹 tag 失败: \(error)")
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法获取文件夹 tag，删除失败: \(error.localizedDescription)"])
        }
        
        // 确保获取到了 tag
        guard let tag = finalTag, !tag.isEmpty else {
            print("[VIEWMODEL] ❌ 无法从服务器获取有效的 tag，无法删除文件夹")
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法从服务器获取文件夹 tag，删除失败"])
        }
        
        finalTag = tag
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        // 2. 调用API删除云端
        do {
            _ = try await service.deleteFolder(folderId: folder.id, tag: finalTag!, purge: false)
            print("[VIEWMODEL] ✅ 云端文件夹删除成功: \(folder.id), tag: \(finalTag!)")
        } catch {
            // 云端删除失败，保存到统一操作队列以便后续重试
            print("[VIEWMODEL] ⚠️ 云端删除文件夹失败: \(error.localizedDescription)，已保存到统一操作队列")
            
            let operationDict: [String: Any] = [
                "folderId": folder.id,
                "purge": false
            ]
            
            if let operationData = try? JSONSerialization.data(withJSONObject: operationDict) {
                let operation = NoteOperation(
                    type: .folderDelete,
                    noteId: folder.id,
                    data: operationData,
                    status: .pending,
                    priority: NoteOperation.calculatePriority(for: .folderDelete)
                )
                try? unifiedQueue.enqueue(operation)
                print("[VIEWMODEL] 云端删除失败，已保存到统一操作队列等待重试: \(folder.id)")
            }
            throw error
        }
        
        // 3. 云端删除成功后，删除本地数据
        // 删除文件夹的图片目录
        do {
            try LocalStorageService.shared.deleteFolderImageDirectory(folderId: folder.id)
            print("[VIEWMODEL] ✅ 已删除文件夹图片目录: \(folder.id)")
        } catch {
            print("[VIEWMODEL] ⚠️ 删除文件夹图片目录失败: \(error.localizedDescription)")
            // 不抛出错误，继续执行删除操作
        }
        
        // 从本地删除文件夹
        if let index = self.folders.firstIndex(where: { $0.id == folder.id }) {
            if index < self.folders.count {
                self.folders.remove(at: index)
            }
            // 从数据库删除文件夹记录
            try DatabaseService.shared.deleteFolder(folderId: folder.id)
            // 保存剩余的文件夹列表
            try localStorage.saveFolders(folders.filter { !$0.isSystem })
            if selectedFolder?.id == folder.id {
                selectedFolder = nil
            }
            print("[VIEWMODEL] ✅ 已从本地删除文件夹: \(folder.id)")
        } else {
            print("[VIEWMODEL] ⚠️ 文件夹列表中未找到要删除的文件夹: \(folder.id)")
        }
        
        // 刷新文件夹列表和笔记列表
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
                print("[VIEWMODEL] 创建笔记失败: \(error)")
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
            let mimeType: String
            switch fileExtension {
            case "jpg", "jpeg":
                mimeType = "image/jpeg"
            case "png":
                mimeType = "image/png"
            case "gif":
                mimeType = "image/gif"
            case "webp":
                mimeType = "image/webp"
            default:
                mimeType = "image/jpeg"
            }
            
            // 上传图片
            let uploadResult = try await service.uploadImage(
                imageData: imageData,
                fileName: fileName,
                mimeType: mimeType
            )
            
            guard let fileId = uploadResult["fileId"] as? String,
                  let digest = uploadResult["digest"] as? String else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "上传图片失败：服务器返回无效响应"])
            }
            
            print("[VIEWMODEL] 图片上传成功: fileId=\(fileId), digest=\(digest)")
            
            // 保存图片到本地
            let fileType = String(mimeType.dropFirst("image/".count))
            try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)
            
            // 更新笔记的 setting.data，添加图片信息
            var updatedNote = note
            var rawData = updatedNote.rawData ?? [:]
            var setting = rawData["setting"] as? [String: Any] ?? [
                "themeId": 0,
                "stickyTime": 0,
                "version": 0
            ]
            
            var settingData = setting["data"] as? [[String: Any]] ?? []
            let imageInfo: [String: Any] = [
                "fileId": fileId,
                "mimeType": mimeType,
                "digest": digest
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
            print("[VIEWMODEL] 图片已添加到笔记的 setting.data: \(note.id), fileId: \(fileId)")
            
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
            
            print("[VIEWMODEL] 图片已插入到笔记: \(note.id)")
            
            // 返回 fileId 供编辑器使用
            return fileId
        } catch {
            // 上传失败：静默处理，不显示弹窗
            print("[VIEWMODEL] 上传图片失败: \(error.localizedDescription)")
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
                  let tvList = data["tvList"] as? [[String: Any]] else {
                throw MiNoteError.invalidResponse
            }
            
            var versions: [NoteHistoryVersion] = []
            for item in tvList {
                if let updateTime = item["updateTime"] as? Int64,
                   let version = item["version"] as? Int64 {
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
                  let entry = data["entry"] as? [String: Any] else {
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
            if let index = self.notes.firstIndex(where: { $0.id == noteId }) {
                if index < self.notes.count {
                    selectedNote = self.notes[index]
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
            print("[VIEWMODEL] Cookie过期，尝试静默刷新...")
            // 先尝试静默刷新，而不是直接显示登录界面
            Task {
                await handleCookieExpiredSilently()
            }
        case .notAuthenticated:
            errorMessage = "未登录，请先登录小米账号"
            showLoginView = true
        case .networkError(let underlyingError):
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
            print("[VIEWMODEL] 未认证，无法获取回收站笔记")
            return
        }
        
        isLoadingDeletedNotes = true
        defer { isLoadingDeletedNotes = false }
        
        do {
            let response = try await service.fetchDeletedNotes()
            
            guard let code = response["code"] as? Int, code == 0,
                  let data = response["data"] as? [String: Any],
                  let entries = data["entries"] as? [[String: Any]] else {
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
                print("[VIEWMODEL] ✅ 获取回收站笔记成功，共 \(deletedNotes.count) 条")
                
                // 更新回收站文件夹的计数
                if let trashIndex = folders.firstIndex(where: { $0.id == "trash" }) {
                    folders[trashIndex].count = deletedNotes.count
                }
            }
        } catch {
            print("[VIEWMODEL] ❌ 获取回收站笔记失败: \(error.localizedDescription)")
            await MainActor.run {
                self.deletedNotes = []
            }
        }
    }
    
    /// 获取用户信息
    /// 
    /// 从服务器获取当前登录用户的昵称和头像
    func fetchUserProfile() async {
        guard service.isAuthenticated() else {
            print("[VIEWMODEL] 未认证，无法获取用户信息")
            return
        }
        
        do {
            let profileData = try await service.fetchUserProfile()
            if let profile = UserProfile.fromAPIResponse(profileData) {
                await MainActor.run {
                    self.userProfile = profile
                    print("[VIEWMODEL] ✅ 获取用户信息成功: \(profile.nickname)")
                }
            } else {
                print("[VIEWMODEL] ⚠️ 无法解析用户信息")
            }
        } catch {
            print("[VIEWMODEL] ❌ 获取用户信息失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 自动刷新Cookie定时器管理
    
    /// 启动自动刷新Cookie定时器（改进版）
    func startAutoRefreshCookieIfNeeded() {
        // 检查是否已登录
        guard service.isAuthenticated() else {
            print("[VIEWMODEL] 未登录，不启动自动刷新Cookie定时器")
            return
        }
        
        // 检查Cookie是否有效，避免不必要的定时器
        guard service.hasValidCookie() else {
            print("[VIEWMODEL] Cookie无效，不启动自动刷新Cookie定时器")
            return
        }
        
        // 检查是否已有定时器在运行
        if autoRefreshCookieTimer != nil {
            print("[VIEWMODEL] 自动刷新Cookie定时器已在运行")
            return
        }
        
        // 从UserDefaults获取刷新间隔
        let defaults = UserDefaults.standard
        let autoRefreshCookie = defaults.bool(forKey: "autoRefreshCookie")
        let autoRefreshInterval = defaults.double(forKey: "autoRefreshInterval")
        
        guard autoRefreshCookie, autoRefreshInterval > 0 else {
            print("[VIEWMODEL] 自动刷新Cookie未启用或间隔为0")
            return
        }
        
        if autoRefreshInterval == 0 {
            // 默认每天刷新一次（24小时）
            defaults.set(86400.0, forKey: "autoRefreshInterval")
        }
        
        print("[VIEWMODEL] 启动自动刷新Cookie定时器，间隔: \(autoRefreshInterval)秒")
        
        // 创建定时器
        autoRefreshCookieTimer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                print("[VIEWMODEL] 自动刷新Cookie定时器触发")
                await self.refreshCookieAutomatically()
            }
        }
    }
    
    /// 停止自动刷新Cookie定时器
    func stopAutoRefreshCookie() {
        print("[VIEWMODEL] 停止自动刷新Cookie定时器")
        autoRefreshCookieTimer?.invalidate()
        autoRefreshCookieTimer = nil
    }
    
    /// 自动刷新Cookie（改进版）
    private func refreshCookieAutomatically() async {
        print("[VIEWMODEL] 开始自动刷新Cookie")
        
        // 检查是否已登录
        guard service.isAuthenticated() else {
            print("[VIEWMODEL] 未登录，跳过自动刷新Cookie")
            return
        }
        
        // 检查是否在线
        guard isOnline else {
            print("[VIEWMODEL] 离线状态，跳过自动刷新Cookie")
            return
        }
        
        // 检查Cookie是否仍然有效，避免不必要的刷新
        guard !service.hasValidCookie() else {
            print("[VIEWMODEL] ✅ Cookie仍然有效，跳过自动刷新")
            return
        }
        
        do {
            // 尝试刷新Cookie
            let success = try await service.refreshCookie()
            if success {
                print("[VIEWMODEL] ✅ 自动刷新Cookie成功")
            } else {
                print("[VIEWMODEL] ⚠️ 自动刷新Cookie失败")
            }
        } catch {
            print("[VIEWMODEL] ❌ 自动刷新Cookie出错: \(error.localizedDescription)")
        }
    }
    
    /// 静默处理Cookie失效（由ContentView调用）
    func handleCookieExpiredSilently() async {
        print("[VIEWMODEL] 静默处理Cookie失效")
        await authStateManager.handleCookieExpiredSilently()
    }
    
    // MARK: - 应用状态监听和自动同步
    
    /// 处理应用变为前台
    private func handleAppBecameActive() {
        print("[VIEWMODEL] 应用变为前台")
        isAppActive = true
        startAutoSyncTimer()
    }
    
    /// 处理应用变为后台
    private func handleAppResignedActive() {
        print("[VIEWMODEL] 应用变为后台")
        isAppActive = false
        stopAutoSyncTimer()
    }
    
    /// 启动自动同步定时器
    private func startAutoSyncTimer() {
        // 检查是否已登录
        guard service.isAuthenticated() else {
            print("[VIEWMODEL] 未登录，不启动自动同步定时器")
            return
        }
        
        // 检查是否已有定时器在运行
        if autoSyncTimer != nil {
            print("[VIEWMODEL] 自动同步定时器已在运行")
            return
        }
        
        // 确保同步间隔不小于最小间隔
        let effectiveSyncInterval = max(syncInterval, minSyncInterval)
        print("[VIEWMODEL] 启动自动同步定时器，间隔: \(effectiveSyncInterval)秒")
        
        // 创建定时器
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: effectiveSyncInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                print("[VIEWMODEL] 自动同步定时器触发")
                await self.performAutoSync()
            }
        }
    }
    
    /// 停止自动同步定时器
    private func stopAutoSyncTimer() {
        print("[VIEWMODEL] 停止自动同步定时器")
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }
    
    /// 执行自动同步
    private func performAutoSync() async {
        // 检查是否在前台
        guard isAppActive else {
            print("[VIEWMODEL] 应用在后台，跳过自动同步")
            return
        }
        
        // 检查是否已登录
        guard service.isAuthenticated() else {
            print("[VIEWMODEL] 未登录，跳过自动同步")
            return
        }
        
        // 检查是否在线
        guard isOnline else {
            print("[VIEWMODEL] 离线状态，跳过自动同步")
            return
        }
        
        // 检查是否正在同步
        guard !isSyncing else {
            print("[VIEWMODEL] 同步正在进行中，跳过自动同步")
            return
        }
        
        // 检查是否超过最小同步间隔
        let now = Date()
        let timeSinceLastSync = now.timeIntervalSince(lastSyncTimestamp)
        if timeSinceLastSync < minSyncInterval {
            print("[VIEWMODEL] 距离上次同步仅 \(Int(timeSinceLastSync)) 秒，小于最小间隔 \(Int(minSyncInterval)) 秒，跳过自动同步")
            return
        }
        
        print("[VIEWMODEL] 开始执行自动同步")
        lastSyncTimestamp = now
        
        // 执行增量同步
        await performIncrementalSync()
    }
    
    /// 更新同步间隔设置
    func updateSyncInterval(_ newInterval: Double) {
        // 确保不小于最小间隔
        let effectiveInterval = max(newInterval, minSyncInterval)
        syncInterval = effectiveInterval
        
        // 保存到UserDefaults
        UserDefaults.standard.set(effectiveInterval, forKey: "syncInterval")
        
        // 如果应用在前台，重启定时器
        if isAppActive {
            stopAutoSyncTimer()
            startAutoSyncTimer()
        }
        
        print("[VIEWMODEL] 同步间隔已更新为 \(effectiveInterval) 秒")
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
            // 如果不能切换（正在录制中），AudioPanelStateManager 会发送确认通知
            // MainWindowController 会监听该通知并显示确认对话框
            print("[NotesViewModel] 笔记切换被阻止，等待用户确认")
        }
    }
}
