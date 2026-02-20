# MiNoteMac 架构重构设计文档

> 状态：设计完成
> 日期：2026-02-20
> 关联审计报告：`.kiro/specs/99-architecture-audit/audit-report.md`

## 一、背景与目标

### 1.1 当前问题

审计报告发现 8 个核心架构问题：

1. 同一份 Note 数据在 6 个地方存在副本，26 处数据库写入分散在 4 个类中
2. 用户编辑后数据到达数据库有 5 条不同路径，各自逻辑不一致
3. 5 个类存在职责重叠（NotesViewModel / NoteEditingCoordinator / NoteOperationCoordinator / SyncService / NotesViewModelAdapter）
4. 三种状态传播机制混用（NotificationCenter / Combine / 直接赋值）
5. `Note.==` 只比较 id，导致数组比较、防循环逻辑等静默失效
6. NotesViewModel 3,668 行承担 15+ 职责
7. 新旧架构并存，NotesViewModelAdapter 用 4 个布尔标志位防循环
8. SyncService 2,192 行包含 5 种同步模式，代码重复度高

### 1.2 重构目标

- 建立单一数据真相来源（SQLite DB），消除数据副本不一致
- 统一所有数据写入为单一入口（NoteStore）
- 用类型安全的 EventBus 替代所有 NotificationCenter 和散落的 Combine 链
- 拆分巨型文件，每个组件职责单一
- 消除新旧架构并存的适配层

### 1.3 设计决策汇总

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 架构模式 | Event Sourcing + 单一写入口 | 模块解耦彻底，事件可追溯，天然支持异步副作用编排 |
| UI 层 | 保持 AppKit + SwiftUI 混合 | NSToolbar/NSSplitView/NSTextView 在纯 SwiftUI 中不成熟 |
| 编辑器 | 保留 NativeEditor 体系，只重构对外接口 | 编辑器内部复杂度是功能性的，不是架构性的 |
| 同步模式 | 2 种（增量 + 完整），完整同步 1 函数 3 子模式 | 消除 5 种模式的代码重复 |
| 操作队列 | 保留 UnifiedOperationQueue + OperationProcessor | 现有实现完善，只需清理 NotificationCenter |
| 状态传播 | 全部通过 EventBus | 替代 NotificationCenter + 散落的 Combine |

## 二、整体架构

```
+---------------------------------------------------+
|                    UI 层                           |
|  AppKit Controllers + SwiftUI Views               |
|  (MainWindowController, NoteDetailView, ...)      |
|         | 读取 @Published    ^ 用户操作            |
+---------------------------------------------------+
|                ViewModel 层                        |
|  NoteListState / NoteEditorState / SyncState      |
|  AuthState / FolderState / SearchState            |
|         | 发送 Event        ^ 订阅 Event           |
+---------------------------------------------------+
|               EventBus (actor)                    |
|  类型安全，支持 async 订阅，事件历史可查           |
|         | 分发事件给所有订阅者                      |
+---------------------------------------------------+
|                事件消费者层                         |
|  +----------+ +----------+ +------------------+   |
|  |NoteStore | |SyncEngine| |OperationQueue    |   |
|  |(唯一 DB  | |(增量/完整| |(保留现有实现)     |   |
|  | 写入者)  | | 同步)    | |                  |   |
|  +----------+ +----------+ +------------------+   |
+---------------------------------------------------+
|                基础设施层                          |
|  SQLite DB / MiNoteService / NetworkMonitor       |
|  LogService / AuthService                         |
+---------------------------------------------------+
```

### 2.1 核心原则

- DB 是唯一真相来源，内存数据是 DB 的只读镜像
- NoteStore 是唯一的 DB 写入者，其他组件禁止直接调用 DatabaseService 写方法
- 所有跨模块通信通过 EventBus，不使用 NotificationCenter 或直接引用
- 事件分为"意图事件"（ViewModel 发出）和"结果事件"（NoteStore/SyncEngine 发出）

## 三、EventBus 设计

### 3.1 核心接口

```swift
actor EventBus {
    /// 发布事件
    func publish(_ event: any AppEvent)

    /// 订阅特定类型的事件，返回 AsyncStream
    func subscribe<E: AppEvent>(to type: E.Type) -> AsyncStream<E>

    /// 查看最近的事件历史（调试用）
    func recentEvents(limit: Int) -> [any AppEvent]
}
```

### 3.2 事件协议

```swift
protocol AppEvent: Sendable {
    var id: UUID { get }
    var timestamp: Date { get }
    var source: EventSource { get }
}

enum EventSource: Sendable {
    case editor      // 编辑器操作
    case sync        // 同步引擎
    case user        // 用户直接操作（UI 按钮等）
    case system      // 系统事件（定时器、网络变化等）
}
```

### 3.3 事件类型

#### 笔记事件

```swift
enum NoteEvent: AppEvent {
    // 意图事件（ViewModel 发出）
    case created(Note)
    case contentUpdated(noteId: String, title: String, content: String)
    case metadataUpdated(noteId: String, changes: NoteMetadataChanges)
    case deleted(noteId: String)
    case moved(noteId: String, fromFolder: String, toFolder: String)
    case starred(noteId: String, isStarred: Bool)

    // 结果事件（NoteStore 发出）
    case saved(Note)
    case listChanged([Note])
}
```

#### 同步事件

```swift
enum SyncEvent: AppEvent {
    case requested(mode: SyncMode)
    case started
    case noteDownloaded(Note)
    case completed(result: SyncResult)
    case failed(error: Error)
    case tagUpdated(noteId: String, newTag: String)
}
```

#### 认证事件

```swift
enum AuthEvent: AppEvent {
    case loggedIn(UserProfile)
    case loggedOut
    case cookieExpired
    case cookieRefreshed
    case tokenRefreshFailed(Error)
}
```

#### 文件夹事件

```swift
enum FolderEvent: AppEvent {
    case created(Folder)
    case renamed(folderId: String, newName: String)
    case deleted(folderId: String)
    case listChanged([Folder])
}
```

### 3.4 关键设计点

- 每个事件都有 id + timestamp + source，方便调试追溯
- `contentUpdated` 只携带 noteId + title + content，不携带完整 Note 对象，避免传递过时的 serverTag（之前 bug 的根源）
- `tagUpdated` 是独立事件，NoteStore 对它的处理是"只更新 tag，不碰其他字段"
- EventBus 保留最近 N 条事件历史，支持调试时查看事件流

## 四、NoteStore 设计

### 4.1 职责

NoteStore 是唯一的数据库写入者，核心逻辑：消费意图事件 -> 执行 DB 操作 -> 发布结果事件。

```swift
actor NoteStore {
    private let db: DatabaseService
    private let eventBus: EventBus

    // 内存缓存：DB 的只读镜像
    private(set) var notes: [Note] = []
    private(set) var folders: [Folder] = []

    func start() {
        // 订阅需要写 DB 的事件：
        // NoteEvent: created, contentUpdated, metadataUpdated, deleted, moved, starred
        // SyncEvent: noteDownloaded, tagUpdated
        // FolderEvent: created, renamed, deleted
    }
}
```

### 4.2 数据流示例

#### 用户编辑笔记

```
1. 用户在 NativeEditorView 中输入
2. NoteEditingCoordinator 防抖后调用 NoteEditorState.saveContent()
3. NoteEditorState 发布 NoteEvent.contentUpdated(noteId, title, content)
4. EventBus 分发：
   +-- NoteStore 收到 -> 写入 DB -> 从 DB 读取最新 Note -> 发布 NoteEvent.saved(note)
5. EventBus 分发 NoteEvent.saved：
   +-- NoteStore 更新内存缓存 -> 发布 NoteEvent.listChanged(notes)
   +-- SyncEngine 收到 -> 将 note 加入 UnifiedOperationQueue
   +-- NoteEditorState 收到 -> 更新保存状态为"已保存"
6. EventBus 分发 NoteEvent.listChanged：
   +-- NoteListState 收到 -> 更新 @Published notes -> UI 刷新
```

#### 同步下载

```
1. 定时器或用户触发 SyncEvent.requested(mode: .incremental)
2. SyncEngine 收到 -> 调用 MiNoteService API -> 获取变更笔记列表
3. 对每条变更笔记，SyncEngine 发布 SyncEvent.noteDownloaded(note)
4. NoteStore 收到 -> 写入 DB -> 发布 NoteEvent.saved(note)
5. 同步完成后，SyncEngine 发布 SyncEvent.completed
6. NoteStore 从 DB 重新加载完整列表 -> 发布 NoteEvent.listChanged
7. NoteListState 收到 -> UI 刷新
```

#### 上传成功 tag 回写

```
1. OperationProcessor 上传成功，获得新 serverTag
2. OperationProcessor 发布 SyncEvent.tagUpdated(noteId, newTag)
3. NoteStore 收到 -> 只更新 DB 中该笔记的 tag 字段（不触碰 content/title）
4. NoteStore 发布 NoteEvent.saved(updatedNote)
5. NoteEditorState 收到 -> 只更新内存中的 serverTag，不干扰编辑中的 content
```

### 4.3 关键约束

- NoteStore 是唯一写 DB 的地方，其他组件禁止直接调用 DatabaseService 写方法
- 内存缓存是 DB 的只读镜像，每次写入后从 DB 重新读取
- contentUpdated 事件只携带变更字段，NoteStore 负责与 DB 现有数据合并
- tagUpdated 的处理逻辑是"只更新 tag，不碰其他字段"

## 五、ViewModel 层拆分

### 5.1 拆分方案

```
NotesViewModel (3,668 行) -----> 删除
NotesViewModelAdapter (300+ 行) -> 删除

拆分为 6 个独立 State 对象：
- NoteListState      笔记列表、排序、过滤
- NoteEditorState    当前编辑笔记、保存状态、编辑器交互
- FolderState        文件夹列表、选中文件夹
- SyncState          同步状态、进度、错误信息
- AuthState          登录状态、Cookie 管理、用户信息
- SearchState        搜索关键词、搜索结果
```

### 5.2 各 State 职责

```swift
@MainActor
final class NoteListState: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedNoteId: String?
    @Published var sortOrder: SortOrder = .updatedAt
    @Published var sortDirection: SortDirection = .descending

    // 订阅 NoteEvent.listChanged
    // 收到后根据当前 sortOrder/filter 重新排序
}

@MainActor
final class NoteEditorState: ObservableObject {
    @Published var currentNote: Note?
    @Published var saveStatus: SaveStatus = .idle

    // 订阅 NoteEvent.saved（更新 serverTag 等元数据）
    // 提供 saveContent(title:content:) 方法，发布 NoteEvent.contentUpdated
    // NoteEditingCoordinator 通过这个 State 与事件系统交互
}

@MainActor
final class FolderState: ObservableObject {
    @Published var folders: [Folder] = []
    @Published var selectedFolderId: String?

    // 订阅 FolderEvent.listChanged
}

@MainActor
final class SyncState: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var syncProgress: String = ""
    @Published var lastSyncTime: Date?

    // 订阅 SyncEvent（started/completed/failed）
}

@MainActor
final class AuthState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var userProfile: UserProfile?
    @Published var showLoginView: Bool = false

    // 订阅 AuthEvent
    // 管理 Cookie 刷新定时器
}

@MainActor
final class SearchState: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchResults: [Note] = []

    // 搜索逻辑：直接查询 NoteStore 的内存缓存或 DB
}
```

### 5.3 UI 注入方式

所有 State 通过 EnvironmentObject 注入：

```swift
// AppCoordinator 创建所有 State
// MainWindowController 在创建窗口时注入环境
window.contentView = NSHostingView(
    rootView: ContentView()
        .environmentObject(noteListState)
        .environmentObject(noteEditorState)
        .environmentObject(folderState)
        .environmentObject(syncState)
        .environmentObject(authState)
        .environmentObject(searchState)
)
```

## 六、SyncEngine 设计

### 6.1 同步模式

合并现有 5 种同步模式为 2 种：

```swift
actor SyncEngine {
    private let api: MiNoteService
    private let eventBus: EventBus
    private let operationQueue: UnifiedOperationQueue

    /// 增量同步：基于 syncTag 的变更检测
    func incrementalSync() async throws

    /// 完整同步：1 个函数，3 种子模式
    func fullSync(mode: FullSyncMode) async throws
}

enum FullSyncMode {
    case forceRedownload       // 重新下载所有笔记和附件
    case normal                // 下载所有笔记，跳过已存在的附件
    case simulatedIncremental  // 只更新 tag 不同的笔记
}
```

### 6.2 关键约束

- SyncEngine 不直接写 DB，下载笔记后发布 `SyncEvent.noteDownloaded`，由 NoteStore 写入
- 上传通过 UnifiedOperationQueue 处理
- OperationProcessor 上传成功后发布 `SyncEvent.tagUpdated`

## 七、AppCoordinator 简化

```swift
@MainActor
final class AppCoordinator {
    let eventBus: EventBus
    let noteStore: NoteStore
    let syncEngine: SyncEngine

    // ViewModel States
    let noteListState: NoteListState
    let noteEditorState: NoteEditorState
    let folderState: FolderState
    let syncState: SyncState
    let authState: AuthState
    let searchState: SearchState

    init() {
        // 创建 EventBus
        // 创建 NoteStore、SyncEngine
        // 创建所有 State 对象，注入 EventBus
        // 启动所有订阅
    }
}
```

不再有 `setupCommunication()` 中的 Combine 链式调用，所有通信通过 EventBus。

## 八、保留不变的部分

- NativeEditor 体系（NativeEditorView / FormatManager / AttachmentManager 等）：只重构对外接口
- UnifiedOperationQueue + OperationProcessor：保留现有实现，清理 NotificationCenter 改为发布事件
- MiNoteService：API 层保持不变
- DatabaseService：保持现有实现，但只允许 NoteStore 调用写方法
- MainWindowController：保持 AppKit 窗口/工具栏管理，更新依赖注入方式

## 九、Note 模型重构

### 9.1 当前问题

- `==` 只比较 id，导致数组比较静默失效
- `rawData: [String: Any]?` 不符合 Sendable，不类型安全
- 模型承担了过多数据转换职责（`fromMinoteData`、`updateContent`、`toMinoteData`、XML 格式转换）

### 9.2 新设计

```swift
// Note 模型：纯数据，不包含转换逻辑
public struct Note: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var title: String
    public var content: String
    public var folderId: String
    public var isStarred: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String]
    public var snippet: String?
    public var colorId: Int
    public var type: String
    public var serverTag: String?
    public var status: String
    public var settingJson: String?
    public var extraInfoJson: String?

    // == 比较所有关键字段
    public static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.content == rhs.content &&
        lhs.folderId == rhs.folderId &&
        lhs.isStarred == rhs.isStarred &&
        lhs.updatedAt == rhs.updatedAt &&
        lhs.serverTag == rhs.serverTag &&
        lhs.status == rhs.status
    }

    // hash 只用 id（Identifiable 需要）
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// 数据转换逻辑抽取到独立的 Mapper
struct NoteMapper {
    static func fromServerResponse(_ response: [String: Any]) -> Note?
    static func fromMinoteData(_ data: [String: Any]) -> Note?
    static func toUploadPayload(_ note: Note) -> [String: Any]
}
```

### 9.3 关键变化

- 删除 `rawData: [String: Any]?`，所有需要的字段提升为显式属性，API 额外字段存在 `settingJson` / `extraInfoJson` 中
- 删除 `subject` 和 `alertDate`（UI 中未使用）
- `==` 比较所有关键字段，SwiftUI List 通过 `Identifiable`（只需 id）保持选择状态
- 数据转换逻辑从 Note 抽出到 NoteMapper，Note 变成纯数据结构

## 十、错误处理策略

### 10.1 错误分类

1. 可恢复错误（网络超时、API 限流）：SyncEngine 内部重试，不发布错误事件。超过重试次数后发布 `SyncEvent.failed`，SyncState 展示给用户。

2. 不可恢复错误（DB 写入失败、数据格式错误）：NoteStore 发布专门的错误事件，UI 层展示错误提示。

### 10.2 错误事件

```swift
enum ErrorEvent: AppEvent {
    case storageFailed(operation: String, error: Error)
    case syncFailed(error: Error, retryable: Bool)
    case authRequired(reason: String)
}
```

### 10.3 关键约束

- NoteStore 的 DB 写入如果失败，不发布 `NoteEvent.saved`，而是发布 `ErrorEvent.storageFailed`
- 下游消费者（SyncEngine、UI）不会收到错误的"保存成功"信号

## 十一、目录结构重组

```
Sources/
├── App/                          # 应用入口（保持不变）
│   ├── AppDelegate.swift
│   └── MenuActionHandler.swift
│
├── Core/                         # 核心基础设施
│   ├── EventBus/                 # 事件总线
│   │   ├── EventBus.swift
│   │   ├── AppEvent.swift
│   │   └── Events/
│   │       ├── NoteEvent.swift
│   │       ├── SyncEvent.swift
│   │       ├── AuthEvent.swift
│   │       ├── FolderEvent.swift
│   │       └── ErrorEvent.swift
│   ├── DI/                       # 依赖注入（简化）
│   └── Logging/                  # 日志服务（保持不变）
│
├── Model/                        # 数据模型
│   ├── Note.swift                # 纯数据结构
│   ├── Folder.swift
│   ├── NoteMapper.swift          # 服务器数据转换
│   └── UserProfile.swift
│
├── Store/                        # 数据存储层（新增）
│   ├── NoteStore.swift           # 唯一 DB 写入者
│   ├── DatabaseService.swift     # SQLite 操作（保持不变）
│   └── DatabaseMigrationManager.swift
│
├── Sync/                         # 同步引擎（重写）
│   ├── SyncEngine.swift          # 增量/完整同步
│   ├── OperationQueue/           # 保留现有实现
│   │   ├── UnifiedOperationQueue.swift
│   │   └── OperationProcessor.swift
│   └── IdMappingRegistry.swift
│
├── Network/                      # 网络层（保持不变）
│   ├── MiNoteService.swift
│   └── NetworkMonitor.swift
│
├── Auth/                         # 认证（整合）
│   └── AuthService.swift
│
├── State/                        # ViewModel 层（新增）
│   ├── NoteListState.swift
│   ├── NoteEditorState.swift
│   ├── FolderState.swift
│   ├── SyncState.swift
│   ├── AuthState.swift
│   └── SearchState.swift
│
├── Coordinator/                  # 协调器（简化）
│   └── AppCoordinator.swift
│
├── View/                         # UI 层
│   ├── NativeEditor/             # 保持不变
│   ├── SwiftUIViews/             # SwiftUI 视图（简化）
│   ├── Bridge/                   # 桥接层（大幅精简）
│   └── Shared/
│
├── Window/                       # 窗口管理（保持不变）
├── ToolbarItem/                  # 工具栏（保持不变）
└── Extensions/                   # 扩展（保持不变）
```

### 11.1 删除的文件

- `Sources/ViewModel/NotesViewModel.swift`（3,668 行）
- `Sources/Presentation/Coordinators/App/NotesViewModelAdapter.swift`
- `Sources/Service/Editor/NoteEditingCoordinator.swift`（重写为 NoteEditorState 的一部分）
- `Sources/Service/Sync/SyncService.swift`（重写为 SyncEngine）
- `Sources/Service/Sync/NoteOperationCoordinator.swift`（职责合并到 NoteStore）
- `Sources/Service/Sync/SyncStateManager.swift`（合并到 SyncState）
- `Sources/Service/Core/AuthenticationStateManager.swift`（合并到 AuthState）
- `Sources/Service/Core/ScheduledTaskManager.swift`（定时任务合并到各自模块）
- `Sources/Core/DependencyInjection/ServiceLocator.swift`（简化）

## 十二、迁移策略

由于用户接受全面重写，采用"新建并行 -> 切换 -> 删除旧代码"的策略：

1. 先建立 EventBus + NoteStore + SyncEngine 核心层，确保数据流正确
2. 创建 6 个 State 对象，逐步替代 NotesViewModel 的各项职责
3. 更新 UI 层的依赖注入，从 NotesViewModel 切换到新的 State 对象
4. 更新 NativeEditor 的对外接口，通过 NoteEditorState 与事件系统交互
5. 删除旧代码（NotesViewModel、NotesViewModelAdapter、旧 SyncService 等）
6. 整理目录结构

每个步骤完成后都应该是可编译、可运行的状态。
