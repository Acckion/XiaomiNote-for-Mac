# MiNoteMac 架构重构实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 MiNoteMac 从多数据副本、多写入路径的混乱架构重构为 Event Sourcing + 单一写入口（NoteStore）的清晰架构。

**Architecture:** EventBus（actor）作为全局事件总线，NoteStore（actor）作为唯一 DB 写入者，6 个 State 对象替代 3,668 行的 NotesViewModel，SyncEngine 替代 2,192 行的 SyncService。所有跨模块通信通过 EventBus，消除 NotificationCenter 和散落的 Combine 链。

**Tech Stack:** Swift 6.0, AppKit + SwiftUI, SQLite 3, async/await, Actor

**关联文档：**
- 设计文档：`docs/plans/2026-02-20-architecture-refactor-design.md`
- 审计报告：`.kiro/specs/99-architecture-audit/audit-report.md`

---

## 阶段概览

| 阶段 | 内容 | 预计任务数 |
|------|------|-----------|
| Phase 1 | EventBus + NoteStore + SyncEngine 核心层 | Task 1-5 |
| Phase 2 | 6 个 State 对象 + NoteMapper | Task 6-12 |
| Phase 3 | AppCoordinator 重写 + UI 层依赖注入 | Task 13-15 |
| Phase 4 | NativeEditor 外部接口更新 | Task 16-17 |
| Phase 5 | 删除旧代码 | Task 18-19 |
| Phase 6 | 目录结构整理 + 收尾 | Task 20-21 |

---

## Phase 1：核心层（EventBus + NoteStore + SyncEngine）

### Task 1：事件协议与事件类型定义

**Files:**
- Create: `Sources/Core/EventBus/AppEvent.swift`
- Create: `Sources/Core/EventBus/Events/NoteEvent.swift`
- Create: `Sources/Core/EventBus/Events/SyncEvent.swift`
- Create: `Sources/Core/EventBus/Events/AuthEvent.swift`
- Create: `Sources/Core/EventBus/Events/FolderEvent.swift`
- Create: `Sources/Core/EventBus/Events/ErrorEvent.swift`

**Step 1: 创建事件协议和基础类型**

```swift
// Sources/Core/EventBus/AppEvent.swift
import Foundation

/// 事件来源
public enum EventSource: String, Sendable {
    case editor
    case sync
    case user
    case system
}

/// 所有事件的基础协议
public protocol AppEvent: Sendable {
    var id: UUID { get }
    var timestamp: Date { get }
    var source: EventSource { get }
}
```

**Step 2: 创建笔记事件**

```swift
// Sources/Core/EventBus/Events/NoteEvent.swift
import Foundation

/// 笔记元数据变更
public struct NoteMetadataChanges: Sendable {
    public var folderId: String?
    public var isStarred: Bool?
    public var colorId: Int?
    public var status: String?

    public init(folderId: String? = nil, isStarred: Bool? = nil,
                colorId: Int? = nil, status: String? = nil) {
        self.folderId = folderId
        self.isStarred = isStarred
        self.colorId = colorId
        self.status = status
    }
}

/// 笔记事件
public enum NoteEvent: AppEvent {
    // 意图事件（State 发出）
    case created(Note)
    case contentUpdated(noteId: String, title: String, content: String)
    case metadataUpdated(noteId: String, changes: NoteMetadataChanges)
    case deleted(noteId: String, tag: String?)
    case moved(noteId: String, fromFolder: String, toFolder: String)
    case starred(noteId: String, isStarred: Bool)

    // 结果事件（NoteStore 发出）
    case saved(Note)
    case listChanged([Note])
    case folderNotesChanged(folderId: String, notes: [Note])

    public var id: UUID { UUID() }
    public var timestamp: Date { Date() }
    public var source: EventSource {
        switch self {
        case .created, .contentUpdated, .metadataUpdated,
             .deleted, .moved, .starred:
            return .user
        case .saved, .listChanged, .folderNotesChanged:
            return .system
        }
    }
}
```

**Step 3: 创建同步事件**

```swift
// Sources/Core/EventBus/Events/SyncEvent.swift
import Foundation

/// 同步模式
public enum SyncMode: Sendable {
    case incremental
    case full(FullSyncMode)
}

/// 完整同步子模式
public enum FullSyncMode: Sendable {
    case forceRedownload
    case normal
    case simulatedIncremental
}

/// 同步结果
public struct SyncResult: Sendable {
    public let downloadedCount: Int
    public let uploadedCount: Int
    public let deletedCount: Int
    public let duration: TimeInterval
    public let mode: SyncMode

    public init(downloadedCount: Int = 0, uploadedCount: Int = 0,
                deletedCount: Int = 0, duration: TimeInterval = 0,
                mode: SyncMode = .incremental) {
        self.downloadedCount = downloadedCount
        self.uploadedCount = uploadedCount
        self.deletedCount = deletedCount
        self.duration = duration
        self.mode = mode
    }
}

/// 同步事件
public enum SyncEvent: AppEvent {
    case requested(mode: SyncMode)
    case started
    case progress(message: String, percent: Double)
    case noteDownloaded(Note)
    case completed(result: SyncResult)
    case failed(error: Error)
    case tagUpdated(noteId: String, newTag: String)

    public var id: UUID { UUID() }
    public var timestamp: Date { Date() }
    public var source: EventSource { .sync }
}
```

**Step 4: 创建认证、文件夹、错误事件**

```swift
// Sources/Core/EventBus/Events/AuthEvent.swift
import Foundation

public enum AuthEvent: AppEvent {
    case loggedIn(UserProfile)
    case loggedOut
    case cookieExpired
    case cookieRefreshed
    case tokenRefreshFailed(Error)

    public var id: UUID { UUID() }
    public var timestamp: Date { Date() }
    public var source: EventSource { .system }
}
```

```swift
// Sources/Core/EventBus/Events/FolderEvent.swift
import Foundation

public enum FolderEvent: AppEvent {
    // 意图事件
    case created(name: String)
    case renamed(folderId: String, newName: String)
    case deleted(folderId: String)

    // 结果事件
    case saved(Folder)
    case listChanged([Folder])

    public var id: UUID { UUID() }
    public var timestamp: Date { Date() }
    public var source: EventSource {
        switch self {
        case .created, .renamed, .deleted:
            return .user
        case .saved, .listChanged:
            return .system
        }
    }
}
```

```swift
// Sources/Core/EventBus/Events/ErrorEvent.swift
import Foundation

public enum ErrorEvent: AppEvent {
    case storageFailed(operation: String, error: Error)
    case syncFailed(error: Error, retryable: Bool)
    case authRequired(reason: String)

    public var id: UUID { UUID() }
    public var timestamp: Date { Date() }
    public var source: EventSource { .system }
}
```

**Step 5: 编译验证**

Run: `xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: 提交**

```bash
git add Sources/Core/EventBus/
git commit -m "refactor(core): 添加 EventBus 事件协议和所有事件类型定义"
```

---

### Task 2：EventBus 实现

**Files:**
- Create: `Sources/Core/EventBus/EventBus.swift`

**Step 1: 实现 EventBus actor**

```swift
// Sources/Core/EventBus/EventBus.swift
import Foundation

/// 全局事件总线
///
/// 类型安全的事件发布/订阅系统，替代 NotificationCenter 和散落的 Combine 链。
/// 使用 actor 保证线程安全。
public actor EventBus {

    /// 共享实例
    public static let shared = EventBus()

    // 使用类型擦除存储订阅者
    private var subscribers: [ObjectIdentifier: [UUID: Any]] = [:]

    // 事件历史（调试用）
    private var eventHistory: [(timestamp: Date, eventType: String, source: EventSource)] = []
    private let maxHistoryCount = 200

    private init() {}

    // MARK: - 发布

    /// 发布事件到所有订阅者
    public func publish<E: AppEvent>(_ event: E) {
        let typeId = ObjectIdentifier(E.self)

        // 记录历史
        eventHistory.append((
            timestamp: event.timestamp,
            eventType: String(describing: type(of: event)),
            source: event.source
        ))
        if eventHistory.count > maxHistoryCount {
            eventHistory.removeFirst(eventHistory.count - maxHistoryCount)
        }

        // 分发给订阅者
        guard let typeSubscribers = subscribers[typeId] else { return }
        for (_, continuation) in typeSubscribers {
            if let cont = continuation as? AsyncStream<E>.Continuation {
                cont.yield(event)
            }
        }
    }

    // MARK: - 订阅

    /// 订阅特定类型的事件
    public func subscribe<E: AppEvent>(to type: E.Type) -> AsyncStream<E> {
        let typeId = ObjectIdentifier(E.self)
        let subscriptionId = UUID()

        return AsyncStream<E> { continuation in
            if self.subscribers[typeId] == nil {
                self.subscribers[typeId] = [:]
            }
            self.subscribers[typeId]?[subscriptionId] = continuation

            continuation.onTermination = { @Sendable _ in
                Task { await self.removeSubscription(typeId: typeId, subscriptionId: subscriptionId) }
            }
        }
    }

    /// 移除订阅
    private func removeSubscription(typeId: ObjectIdentifier, subscriptionId: UUID) {
        subscribers[typeId]?.removeValue(forKey: subscriptionId)
        if subscribers[typeId]?.isEmpty == true {
            subscribers.removeValue(forKey: typeId)
        }
    }

    // MARK: - 调试

    /// 查看最近的事件历史
    public func recentEvents(limit: Int = 50) -> [(timestamp: Date, eventType: String, source: EventSource)] {
        Array(eventHistory.suffix(limit))
    }

    /// 清空事件历史
    public func clearHistory() {
        eventHistory.removeAll()
    }

    /// 当前订阅者数量统计
    public func subscriberCount() -> [String: Int] {
        var result: [String: Int] = [:]
        for (typeId, subs) in subscribers {
            result["\(typeId)"] = subs.count
        }
        return result
    }
}
```

**Step 2: 编译验证**

Run: `xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: 提交**

```bash
git add Sources/Core/EventBus/EventBus.swift
git commit -m "refactor(core): 实现 EventBus actor 事件总线"
```

---

### Task 3：Note 模型重构 + NoteMapper

**Files:**
- Modify: `Sources/Model/Note.swift`
- Create: `Sources/Model/NoteMapper.swift`

**Step 1: 重构 Note 模型**

修改 `Sources/Model/Note.swift`：

1. 将 `@unchecked Sendable` 改为 `Sendable`（删除 rawData 后可以做到）
2. 删除 `rawData: [String: Any]?` 字段
3. 删除 `subject` 和 `alertDate` 字段
4. 修改 `==` 比较所有关键字段
5. 删除 `init?(from serverResponse:)`、`fromMinoteData`、`updateContent`、`toMinoteData` 方法（移到 NoteMapper）
6. 删除 `convertLegacyImageFormat`（移到 NoteMapper）
7. 保留 `primaryXMLContent`、`withPrimaryXMLContent`、`contentEquals`、图片附件扩展
8. 简化 Codable 实现（不再需要自定义 encode/decode）

重构后的 Note 核心结构：

```swift
public struct Note: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var content: String
    public var folderId: String
    public var isStarred: Bool = false
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String] = []
    public var snippet: String?
    public var colorId: Int = 0
    public var type: String = "note"
    public var serverTag: String?
    public var status: String = "normal"
    public var settingJson: String?
    public var extraInfoJson: String?

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

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

**Step 2: 创建 NoteMapper**

将 Note 中的所有数据转换逻辑抽取到 `Sources/Model/NoteMapper.swift`：

```swift
// Sources/Model/NoteMapper.swift
import Foundation

/// 笔记数据转换器
///
/// 负责服务器数据与 Note 模型之间的转换，
/// 从 Note 模型中抽取出来保持 Note 为纯数据结构。
public struct NoteMapper {

    /// 从服务器完整响应创建 Note
    public static func fromServerResponse(_ serverResponse: [String: Any]) -> Note? {
        // 从旧 Note.init?(from:) 迁移过来的逻辑
        // ...（完整实现从 Note.swift 的 init?(from serverResponse:) 迁移）
    }

    /// 从小米笔记列表 API 数据创建 Note（不含 content）
    public static func fromMinoteListData(_ data: [String: Any]) -> Note? {
        // 从旧 Note.fromMinoteData 迁移过来的逻辑
    }

    /// 用服务器详情更新已有 Note
    public static func updateFromServerDetails(_ note: inout Note, details: [String: Any]) {
        // 从旧 Note.updateContent(from:) 迁移过来的逻辑
    }

    /// 转换为上传 API 格式
    public static func toUploadPayload(_ note: Note) -> [String: Any] {
        // 从旧 Note.toMinoteData() 迁移过来的逻辑
    }

    /// 转换旧版图片格式
    public static func convertLegacyImageFormat(_ xml: String) -> String {
        // 从旧 Note.convertLegacyImageFormat 迁移过来的逻辑
    }
}
```

注意：NoteMapper 的每个方法的完整实现直接从 Note.swift 中对应方法复制，只需要：
- 将 `self.xxx = yyy` 改为构造 Note 对象
- 将 `rawData` 相关逻辑改为使用 `settingJson`/`extraInfoJson`
- 删除对 `subject`/`alertDate` 的处理

**Step 3: 修复所有编译错误**

搜索项目中所有使用以下 API 的地方并更新：
- `Note(from: serverResponse)` → `NoteMapper.fromServerResponse(serverResponse)`
- `Note.fromMinoteData(data)` → `NoteMapper.fromMinoteListData(data)`
- `note.updateContent(from: details)` → `NoteMapper.updateFromServerDetails(&note, details: details)`
- `note.toMinoteData()` → `NoteMapper.toUploadPayload(note)`
- `note.rawData` → 删除或替换为 `settingJson`/`extraInfoJson`
- `note.subject` → 删除
- `note.alertDate` → 删除

关键文件需要更新：
- `Sources/Service/Sync/SyncService.swift`（大量使用 rawData 和 fromMinoteData）
- `Sources/Service/Sync/OperationProcessor.swift`（使用 rawData 构造上传数据）
- `Sources/Service/Storage/DatabaseService.swift`（读写 rawData 字段）
- `Sources/Service/Storage/DatabaseService+Internal.swift`（DB 映射）
- `Sources/ViewModel/NotesViewModel.swift`（使用 rawData）
- `Sources/Service/Editor/NoteEditingCoordinator.swift`（构造 Note）

**Step 4: 编译验证**

Run: `xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: 提交**

```bash
git add Sources/Model/Note.swift Sources/Model/NoteMapper.swift
git add -u  # 添加所有修改的文件
git commit -m "refactor(model): 重构 Note 模型为纯数据结构，抽取 NoteMapper"
```

---

### Task 4：NoteStore 实现

**Files:**
- Create: `Sources/Store/NoteStore.swift`

**Step 1: 实现 NoteStore actor**

NoteStore 是唯一的 DB 写入者。消费意图事件 → 执行 DB 操作 → 发布结果事件。

```swift
// Sources/Store/NoteStore.swift
import Foundation

/// 笔记数据存储
///
/// 唯一的数据库写入者，所有数据变更必须通过 NoteStore。
/// 消费意图事件 -> 写入 DB -> 发布结果事件。
public actor NoteStore {

    private let db: DatabaseService
    private let eventBus: EventBus

    // 内存缓存：DB 的只读镜像
    private(set) var notes: [Note] = []
    private(set) var folders: [Folder] = []

    // 订阅任务
    private var noteEventTask: Task<Void, Never>?
    private var syncEventTask: Task<Void, Never>?
    private var folderEventTask: Task<Void, Never>?

    public init(db: DatabaseService, eventBus: EventBus) {
        self.db = db
        self.eventBus = eventBus
    }

    /// 启动事件订阅
    public func start() async {
        // 从 DB 加载初始数据
        await loadAllFromDB()

        // 订阅笔记意图事件
        noteEventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: NoteEvent.self)
            for await event in stream {
                await self.handleNoteEvent(event)
            }
        }

        // 订阅同步事件（noteDownloaded, tagUpdated）
        syncEventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: SyncEvent.self)
            for await event in stream {
                await self.handleSyncEvent(event)
            }
        }

        // 订阅文件夹事件
        folderEventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: FolderEvent.self)
            for await event in stream {
                await self.handleFolderEvent(event)
            }
        }

        LogService.shared.info(.storage, "NoteStore 启动完成，加载了 \(notes.count) 条笔记")
    }

    /// 停止事件订阅
    public func stop() {
        noteEventTask?.cancel()
        syncEventTask?.cancel()
        folderEventTask?.cancel()
    }

    // MARK: - 数据加载

    private func loadAllFromDB() async {
        do {
            notes = try db.getAllNotes()
            folders = try db.getAllFolders()
        } catch {
            LogService.shared.error(.storage, "NoteStore 加载数据失败: \(error)")
            await eventBus.publish(ErrorEvent.storageFailed(operation: "loadAll", error: error))
        }
    }

    /// 从 DB 重新加载笔记列表并发布变更事件
    private func reloadNotesAndPublish() async {
        do {
            notes = try db.getAllNotes()
            await eventBus.publish(NoteEvent.listChanged(notes))
        } catch {
            LogService.shared.error(.storage, "NoteStore 重新加载笔记失败: \(error)")
        }
    }

    /// 从 DB 重新加载文件夹列表并发布变更事件
    private func reloadFoldersAndPublish() async {
        do {
            folders = try db.getAllFolders()
            await eventBus.publish(FolderEvent.listChanged(folders))
        } catch {
            LogService.shared.error(.storage, "NoteStore 重新加载文件夹失败: \(error)")
        }
    }

    // MARK: - 笔记事件处理

    private func handleNoteEvent(_ event: NoteEvent) async {
        switch event {
        case .created(let note):
            await saveNote(note)

        case .contentUpdated(let noteId, let title, let content):
            await updateNoteContent(noteId: noteId, title: title, content: content)

        case .metadataUpdated(let noteId, let changes):
            await updateNoteMetadata(noteId: noteId, changes: changes)

        case .deleted(let noteId, _):
            await deleteNote(noteId: noteId)

        case .moved(let noteId, _, let toFolder):
            await updateNoteMetadata(noteId: noteId,
                changes: NoteMetadataChanges(folderId: toFolder))

        case .starred(let noteId, let isStarred):
            await updateNoteMetadata(noteId: noteId,
                changes: NoteMetadataChanges(isStarred: isStarred))

        // 结果事件不处理（是自己发出的）
        case .saved, .listChanged, .folderNotesChanged:
            break
        }
    }

    // MARK: - 同步事件处理

    private func handleSyncEvent(_ event: SyncEvent) async {
        switch event {
        case .noteDownloaded(let note):
            await saveNote(note)

        case .tagUpdated(let noteId, let newTag):
            await updateServerTag(noteId: noteId, newTag: newTag)

        case .completed:
            await reloadNotesAndPublish()

        default:
            break
        }
    }

    // MARK: - 文件夹事件处理

    private func handleFolderEvent(_ event: FolderEvent) async {
        switch event {
        case .created(let name):
            await createFolder(name: name)
        case .renamed(let folderId, let newName):
            await renameFolder(folderId: folderId, newName: newName)
        case .deleted(let folderId):
            await deleteFolder(folderId: folderId)
        case .saved, .listChanged:
            break
        }
    }

    // MARK: - DB 写入操作

    private func saveNote(_ note: Note) async {
        do {
            try db.saveNote(note)
            let savedNote = try db.getNote(byId: note.id) ?? note
            await eventBus.publish(NoteEvent.saved(savedNote))
            await reloadNotesAndPublish()
        } catch {
            LogService.shared.error(.storage, "NoteStore 保存笔记失败: \(note.id), \(error)")
            await eventBus.publish(ErrorEvent.storageFailed(operation: "saveNote", error: error))
        }
    }

    private func updateNoteContent(noteId: String, title: String, content: String) async {
        do {
            guard var note = try db.getNote(byId: noteId) else {
                LogService.shared.warning(.storage, "NoteStore 更新内容失败：笔记不存在 \(noteId)")
                return
            }
            note.title = title
            note.content = content
            note.updatedAt = Date()
            try db.saveNote(note)

            let savedNote = try db.getNote(byId: noteId) ?? note
            await eventBus.publish(NoteEvent.saved(savedNote))
            await reloadNotesAndPublish()
        } catch {
            LogService.shared.error(.storage, "NoteStore 更新笔记内容失败: \(noteId), \(error)")
            await eventBus.publish(ErrorEvent.storageFailed(operation: "updateContent", error: error))
        }
    }

    private func updateNoteMetadata(noteId: String, changes: NoteMetadataChanges) async {
        do {
            guard var note = try db.getNote(byId: noteId) else { return }
            if let folderId = changes.folderId { note.folderId = folderId }
            if let isStarred = changes.isStarred { note.isStarred = isStarred }
            if let colorId = changes.colorId { note.colorId = colorId }
            if let status = changes.status { note.status = status }
            note.updatedAt = Date()
            try db.saveNote(note)

            let savedNote = try db.getNote(byId: noteId) ?? note
            await eventBus.publish(NoteEvent.saved(savedNote))
            await reloadNotesAndPublish()
        } catch {
            LogService.shared.error(.storage, "NoteStore 更新笔记元数据失败: \(noteId), \(error)")
            await eventBus.publish(ErrorEvent.storageFailed(operation: "updateMetadata", error: error))
        }
    }

    /// 只更新 serverTag，不触碰其他字段
    private func updateServerTag(noteId: String, newTag: String) async {
        do {
            guard var note = try db.getNote(byId: noteId) else { return }
            note.serverTag = newTag
            try db.saveNote(note)
            let savedNote = try db.getNote(byId: noteId) ?? note
            await eventBus.publish(NoteEvent.saved(savedNote))
        } catch {
            LogService.shared.error(.storage, "NoteStore 更新 serverTag 失败: \(noteId), \(error)")
        }
    }

    private func deleteNote(noteId: String) async {
        do {
            try db.deleteNote(noteId: noteId)
            await reloadNotesAndPublish()
        } catch {
            LogService.shared.error(.storage, "NoteStore 删除笔记失败: \(noteId), \(error)")
            await eventBus.publish(ErrorEvent.storageFailed(operation: "deleteNote", error: error))
        }
    }

    private func createFolder(name: String) async {
        // 文件夹创建逻辑（生成 ID，写入 DB）
        do {
            let folder = Folder(id: UUID().uuidString, name: name)
            try db.saveFolder(folder)
            await eventBus.publish(FolderEvent.saved(folder))
            await reloadFoldersAndPublish()
        } catch {
            LogService.shared.error(.storage, "NoteStore 创建文件夹失败: \(error)")
        }
    }

    private func renameFolder(folderId: String, newName: String) async {
        do {
            try db.renameFolder(folderId: folderId, newName: newName)
            await reloadFoldersAndPublish()
        } catch {
            LogService.shared.error(.storage, "NoteStore 重命名文件夹失败: \(error)")
        }
    }

    private func deleteFolder(folderId: String) async {
        do {
            try db.deleteFolder(folderId: folderId)
            await reloadFoldersAndPublish()
        } catch {
            LogService.shared.error(.storage, "NoteStore 删除文件夹失败: \(error)")
        }
    }

    // MARK: - 只读查询（供外部直接调用）

    /// 获取指定笔记（从内存缓存）
    public func getNote(byId noteId: String) -> Note? {
        notes.first { $0.id == noteId }
    }

    /// 获取指定文件夹的笔记
    public func getNotes(inFolder folderId: String) -> [Note] {
        notes.filter { $0.folderId == folderId && $0.status == "normal" }
    }

    /// 获取最新的 serverTag（从 DB 读取，确保不过期）
    public func getLatestServerTag(noteId: String) -> String? {
        try? db.getNote(byId: noteId)?.serverTag
    }
}
```

**Step 2: 编译验证**

Run: `xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

注意：此时 NoteStore 中调用的 DatabaseService 方法（如 `getNote(byId:)`、`saveNote`、`getAllNotes`、`getAllFolders` 等）需要确认已存在。如果缺少某些方法，需要在 DatabaseService 中补充。

**Step 3: 提交**

```bash
git add Sources/Store/NoteStore.swift
git commit -m "refactor(store): 实现 NoteStore actor 作为唯一 DB 写入者"
```

---

### Task 5：SyncEngine 实现

**Files:**
- Create: `Sources/Sync/SyncEngine.swift`

**Step 1: 实现 SyncEngine actor**

SyncEngine 替代 SyncService（2,192 行），合并 5 种同步模式为 2 种。
SyncEngine 不直接写 DB，下载笔记后发布事件由 NoteStore 写入。

```swift
// Sources/Sync/SyncEngine.swift
import Foundation

/// 同步引擎
///
/// 替代旧的 SyncService，负责与云端的数据同步。
/// 不直接写 DB，通过 EventBus 发布事件由 NoteStore 处理。
public actor SyncEngine {

    private let api: MiNoteService
    private let eventBus: EventBus
    private let operationQueue: UnifiedOperationQueue
    private let operationProcessor: OperationProcessor
    private let syncStateManager: SyncStateManager

    private var isSyncing = false
    private var syncTask: Task<Void, Never>?
    private var periodicSyncTask: Task<Void, Never>?

    // 同步间隔（秒）
    private let syncInterval: TimeInterval = 300

    public init(
        api: MiNoteService,
        eventBus: EventBus,
        operationQueue: UnifiedOperationQueue,
        operationProcessor: OperationProcessor,
        syncStateManager: SyncStateManager
    ) {
        self.api = api
        self.eventBus = eventBus
        self.operationQueue = operationQueue
        self.operationProcessor = operationProcessor
        self.syncStateManager = syncStateManager
    }

    /// 启动同步引擎（订阅事件 + 启动定时同步）
    public func start() async {
        // 订阅同步请求事件
        syncTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: SyncEvent.self)
            for await event in stream {
                if case .requested(let mode) = event {
                    await self.performSync(mode: mode)
                }
            }
        }

        // 启动定时增量同步
        startPeriodicSync()

        LogService.shared.info(.sync, "SyncEngine 启动完成")
    }

    /// 停止同步引擎
    public func stop() {
        syncTask?.cancel()
        periodicSyncTask?.cancel()
        LogService.shared.info(.sync, "SyncEngine 已停止")
    }

    // MARK: - 定时同步

    private func startPeriodicSync() {
        periodicSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.syncInterval ?? 300) * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.performSync(mode: .incremental)
            }
        }
    }

    // MARK: - 同步执行

    /// 执行同步
    private func performSync(mode: SyncMode) async {
        guard !isSyncing else {
            LogService.shared.debug(.sync, "同步正在进行中，跳过")
            return
        }

        guard api.isAuthenticated() else {
            LogService.shared.debug(.sync, "未认证，跳过同步")
            return
        }

        isSyncing = true
        let startTime = Date()
        await eventBus.publish(SyncEvent.started)

        do {
            let result: SyncResult
            switch mode {
            case .incremental:
                result = try await performIncrementalSync(startTime: startTime)
            case .full(let fullMode):
                result = try await performFullSync(mode: fullMode, startTime: startTime)
            }

            await eventBus.publish(SyncEvent.completed(result: result))
            LogService.shared.info(.sync, "同步完成: 下载 \(result.downloadedCount), 上传 \(result.uploadedCount)")
        } catch {
            await eventBus.publish(SyncEvent.failed(error: error))
            LogService.shared.error(.sync, "同步失败: \(error)")
        }

        isSyncing = false

        // 同步完成后处理操作队列
        await operationProcessor.processQueue()
    }

    // MARK: - 增量同步

    /// 基于 syncTag 的增量同步
    private func performIncrementalSync(startTime: Date) async throws -> SyncResult {
        await eventBus.publish(SyncEvent.progress(message: "检查云端变更...", percent: 0.1))

        let currentSyncTag = try await syncStateManager.getCurrentSyncTag()

        // 调用 API 获取变更
        let response = try await api.syncNotes(syncTag: currentSyncTag)

        guard let data = response["data"] as? [String: Any],
              let entries = data["entries"] as? [[String: Any]]
        else {
            return SyncResult(mode: .incremental)
        }

        let newSyncTag = data["syncTag"] as? String

        var downloadedCount = 0

        await eventBus.publish(SyncEvent.progress(message: "下载变更笔记...", percent: 0.3))

        for entry in entries {
            guard let noteId = entry["id"] as? String else { continue }

            // 跳过有待上传操作的笔记
            if operationQueue.hasPendingUpload(for: noteId) {
                LogService.shared.debug(.sync, "跳过有待上传操作的笔记: \(noteId.prefix(8))...")
                continue
            }

            // 获取笔记详情
            do {
                let details = try await api.getNoteDetail(noteId: noteId)
                if var note = NoteMapper.fromServerResponse(details) {
                    await eventBus.publish(SyncEvent.noteDownloaded(note))
                    downloadedCount += 1
                }
            } catch {
                LogService.shared.warning(.sync, "下载笔记详情失败: \(noteId), \(error)")
            }
        }

        // 更新 syncTag
        if let newSyncTag {
            try await syncStateManager.updateSyncTag(newSyncTag)
        }

        let duration = Date().timeIntervalSince(startTime)
        return SyncResult(
            downloadedCount: downloadedCount,
            duration: duration,
            mode: .incremental
        )
    }

    // MARK: - 完整同步

    /// 完整同步（3 种子模式）
    private func performFullSync(mode: FullSyncMode, startTime: Date) async throws -> SyncResult {
        await eventBus.publish(SyncEvent.progress(message: "获取笔记列表...", percent: 0.1))

        // 获取所有笔记列表
        let noteList = try await api.getAllNotes()

        guard let entries = noteList["entries"] as? [[String: Any]] else {
            return SyncResult(mode: .full(mode))
        }

        var downloadedCount = 0
        let total = entries.count

        for (index, entry) in entries.enumerated() {
            guard let noteId = entry["id"] as? String else { continue }

            // 跳过有待上传操作的笔记
            if operationQueue.hasPendingUpload(for: noteId) { continue }

            let percent = 0.1 + 0.8 * Double(index) / Double(max(total, 1))
            await eventBus.publish(SyncEvent.progress(
                message: "同步笔记 \(index + 1)/\(total)...",
                percent: percent
            ))

            switch mode {
            case .simulatedIncremental:
                // 只更新 tag 不同的笔记
                let serverTag = entry["tag"] as? String
                // 需要从 NoteStore 查询当前 tag（通过 DB）
                // 如果 tag 相同则跳过
                break

            case .normal, .forceRedownload:
                do {
                    let details = try await api.getNoteDetail(noteId: noteId)
                    if let note = NoteMapper.fromServerResponse(details) {
                        await eventBus.publish(SyncEvent.noteDownloaded(note))
                        downloadedCount += 1
                    }
                } catch {
                    LogService.shared.warning(.sync, "完整同步下载失败: \(noteId), \(error)")
                }
            }
        }

        let newSyncTag = noteList["syncTag"] as? String
        if let newSyncTag {
            try await syncStateManager.updateSyncTag(newSyncTag)
        }

        let duration = Date().timeIntervalSince(startTime)
        return SyncResult(
            downloadedCount: downloadedCount,
            duration: duration,
            mode: .full(mode)
        )
    }
}
```

注意：SyncEngine 的实现是骨架，具体的 API 调用细节需要参考现有 SyncService 的实现来完善。关键原则是 SyncEngine 不直接写 DB，而是通过 `SyncEvent.noteDownloaded` 让 NoteStore 处理。

**Step 2: 编译验证**

Run: `xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: 提交**

```bash
git add Sources/Sync/SyncEngine.swift
git commit -m "refactor(sync): 实现 SyncEngine actor 替代旧 SyncService"
```

---

## Phase 2：State 对象层

### Task 6：NoteListState

**Files:**
- Create: `Sources/State/NoteListState.swift`

**Step 1: 实现 NoteListState**

```swift
// Sources/State/NoteListState.swift
import Combine
import Foundation

/// 笔记列表状态
///
/// 管理笔记列表的展示、排序、过滤。
/// 订阅 NoteEvent.listChanged 更新列表。
@MainActor
public final class NoteListState: ObservableObject {

    @Published public var notes: [Note] = []
    @Published public var selectedNoteId: String?
    @Published public var sortOrder: NoteSortOrder = .editDate
    @Published public var sortDirection: SortDirection = .descending
    @Published public var selectedFolderId: String?

    private let eventBus: EventBus
    private var subscriptionTask: Task<Void, Never>?

    public init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    /// 启动事件订阅
    public func start() {
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: NoteEvent.self)
            for await event in stream {
                await MainActor.run {
                    self.handleNoteEvent(event)
                }
            }
        }
    }

    public func stop() {
        subscriptionTask?.cancel()
    }

    private func handleNoteEvent(_ event: NoteEvent) {
        switch event {
        case .listChanged(let allNotes):
            updateNotes(allNotes)
        case .saved(let note):
            // 更新列表中的单条笔记
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = note
            }
        default:
            break
        }
    }

    /// 根据当前文件夹和排序设置更新笔记列表
    private func updateNotes(_ allNotes: [Note]) {
        var filtered = allNotes.filter { $0.status == "normal" }

        // 按文件夹过滤
        if let folderId = selectedFolderId {
            filtered = filtered.filter { $0.folderId == folderId }
        }

        // 排序
        notes = sortNotes(filtered)
    }

    private func sortNotes(_ notes: [Note]) -> [Note] {
        notes.sorted { a, b in
            let result: Bool
            switch sortOrder {
            case .editDate:
                result = a.updatedAt > b.updatedAt
            case .createDate:
                result = a.createdAt > b.createdAt
            case .title:
                result = a.title.localizedCompare(b.title) == .orderedAscending
            }
            return sortDirection == .descending ? result : !result
        }
    }

    /// 选择笔记
    public func selectNote(_ note: Note) {
        selectedNoteId = note.id
    }

    /// 切换文件夹
    public func selectFolder(_ folderId: String?) {
        selectedFolderId = folderId
    }
}
```

**Step 2: 编译验证并提交**

```bash
git add Sources/State/NoteListState.swift
git commit -m "refactor(state): 实现 NoteListState 笔记列表状态管理"
```

---

### Task 7：NoteEditorState

**Files:**
- Create: `Sources/State/NoteEditorState.swift`

**Step 1: 实现 NoteEditorState**

```swift
// Sources/State/NoteEditorState.swift
import Combine
import Foundation

/// 保存状态
public enum SaveStatus: Equatable {
    case idle
    case saving
    case saved
    case error(String)
}

/// 笔记编辑器状态
///
/// 管理当前编辑笔记的状态、保存逻辑。
/// 替代 NoteEditingCoordinator 的对外接口。
@MainActor
public final class NoteEditorState: ObservableObject {

    @Published public var currentNote: Note?
    @Published public var saveStatus: SaveStatus = .idle
    @Published public var editedTitle: String = ""
    @Published public var currentXMLContent: String = ""
    @Published public var isInitializing: Bool = true

    // 防抖保存
    private var saveDebounceTask: Task<Void, Never>?
    private let saveDebounceDelay: UInt64 = 300_000_000 // 300ms

    // 原始内容（用于检测变更）
    private var originalTitle: String = ""
    private var originalContent: String = ""

    private let eventBus: EventBus
    private var subscriptionTask: Task<Void, Never>?

    public init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    /// 启动事件订阅
    public func start() {
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: NoteEvent.self)
            for await event in stream {
                await MainActor.run {
                    self.handleNoteEvent(event)
                }
            }
        }
    }

    public func stop() {
        subscriptionTask?.cancel()
    }

    private func handleNoteEvent(_ event: NoteEvent) {
        switch event {
        case .saved(let note):
            guard note.id == currentNote?.id else { return }
            // 只更新元数据（serverTag 等），不覆盖正在编辑的内容
            currentNote?.serverTag = note.serverTag
            currentNote?.updatedAt = note.updatedAt
            if saveStatus == .saving {
                saveStatus = .saved
            }
        default:
            break
        }
    }

    /// 加载笔记到编辑器
    public func loadNote(_ note: Note) {
        isInitializing = true
        currentNote = note
        editedTitle = note.title
        currentXMLContent = note.primaryXMLContent
        originalTitle = note.title
        originalContent = note.primaryXMLContent
        saveStatus = .idle
        isInitializing = false
    }

    /// 内容变更（由编辑器调用，带防抖）
    public func contentDidChange(title: String, xmlContent: String) {
        guard !isInitializing else { return }
        editedTitle = title
        currentXMLContent = xmlContent

        // 防抖保存
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.saveDebounceDelay ?? 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveContent()
        }
    }

    /// 立即保存当前内容
    public func saveContent() async {
        guard let noteId = currentNote?.id else { return }
        guard editedTitle != originalTitle || currentXMLContent != originalContent else {
            return // 无变更
        }

        saveStatus = .saving

        // 发布内容更新事件，NoteStore 会处理 DB 写入
        await eventBus.publish(NoteEvent.contentUpdated(
            noteId: noteId,
            title: editedTitle,
            content: currentXMLContent
        ))

        originalTitle = editedTitle
        originalContent = currentXMLContent
    }

    /// 切换笔记前保存
    public func saveBeforeSwitch() async -> Bool {
        saveDebounceTask?.cancel()
        await saveContent()
        return true
    }

    /// 是否有未保存的变更
    public var hasUnsavedChanges: Bool {
        editedTitle != originalTitle || currentXMLContent != originalContent
    }
}
```

**Step 2: 编译验证并提交**

```bash
git add Sources/State/NoteEditorState.swift
git commit -m "refactor(state): 实现 NoteEditorState 编辑器状态管理"
```

---

### Task 8：FolderState

**Files:**
- Create: `Sources/State/FolderState.swift`

**Step 1: 实现 FolderState**

```swift
// Sources/State/FolderState.swift
import Foundation

/// 文件夹状态
@MainActor
public final class FolderState: ObservableObject {

    @Published public var folders: [Folder] = []
    @Published public var selectedFolderId: String?

    private let eventBus: EventBus
    private var subscriptionTask: Task<Void, Never>?

    public init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    public func start() {
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: FolderEvent.self)
            for await event in stream {
                await MainActor.run {
                    self.handleFolderEvent(event)
                }
            }
        }
    }

    public func stop() {
        subscriptionTask?.cancel()
    }

    private func handleFolderEvent(_ event: FolderEvent) {
        switch event {
        case .listChanged(let folders):
            self.folders = folders
        default:
            break
        }
    }

    public func selectFolder(_ folderId: String?) {
        selectedFolderId = folderId
    }

    public func createFolder(name: String) async {
        await eventBus.publish(FolderEvent.created(name: name))
    }

    public func renameFolder(folderId: String, newName: String) async {
        await eventBus.publish(FolderEvent.renamed(folderId: folderId, newName: newName))
    }

    public func deleteFolder(folderId: String) async {
        await eventBus.publish(FolderEvent.deleted(folderId: folderId))
    }
}
```

**Step 2: 编译验证并提交**

```bash
git add Sources/State/FolderState.swift
git commit -m "refactor(state): 实现 FolderState 文件夹状态管理"
```

---

### Task 9：SyncState

**Files:**
- Create: `Sources/State/SyncState.swift`

**Step 1: 实现 SyncState**

```swift
// Sources/State/SyncState.swift
import Foundation

/// 同步状态
@MainActor
public final class SyncState: ObservableObject {

    @Published public var isSyncing: Bool = false
    @Published public var syncProgress: String = ""
    @Published public var syncPercent: Double = 0
    @Published public var lastSyncTime: Date?
    @Published public var lastError: String?

    private let eventBus: EventBus
    private var subscriptionTask: Task<Void, Never>?

    public init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    public func start() {
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: SyncEvent.self)
            for await event in stream {
                await MainActor.run {
                    self.handleSyncEvent(event)
                }
            }
        }
    }

    public func stop() {
        subscriptionTask?.cancel()
    }

    private func handleSyncEvent(_ event: SyncEvent) {
        switch event {
        case .started:
            isSyncing = true
            syncProgress = "同步中..."
            syncPercent = 0
            lastError = nil

        case .progress(let message, let percent):
            syncProgress = message
            syncPercent = percent

        case .completed(let result):
            isSyncing = false
            lastSyncTime = Date()
            syncProgress = "同步完成"
            syncPercent = 1.0

        case .failed(let error):
            isSyncing = false
            lastError = error.localizedDescription
            syncProgress = "同步失败"

        default:
            break
        }
    }

    /// 请求同步
    public func requestSync(mode: SyncMode = .incremental) async {
        await eventBus.publish(SyncEvent.requested(mode: mode))
    }
}
```

**Step 2: 编译验证并提交**

```bash
git add Sources/State/SyncState.swift
git commit -m "refactor(state): 实现 SyncState 同步状态管理"
```

---

### Task 10：AuthState

**Files:**
- Create: `Sources/State/AuthState.swift`

**Step 1: 实现 AuthState**

```swift
// Sources/State/AuthState.swift
import Foundation

/// 认证状态
@MainActor
public final class AuthState: ObservableObject {

    @Published public var isLoggedIn: Bool = false
    @Published public var userProfile: UserProfile?
    @Published public var showLoginView: Bool = false
    @Published public var isPrivateNotesUnlocked: Bool = false

    private let eventBus: EventBus
    private var subscriptionTask: Task<Void, Never>?

    // Cookie 刷新定时器
    private var cookieRefreshTask: Task<Void, Never>?
    private let cookieRefreshInterval: TimeInterval = 3600 // 1 小时

    public init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    public func start() {
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: AuthEvent.self)
            for await event in stream {
                await MainActor.run {
                    self.handleAuthEvent(event)
                }
            }
        }

        // 检查初始登录状态
        checkInitialAuthState()
    }

    public func stop() {
        subscriptionTask?.cancel()
        cookieRefreshTask?.cancel()
    }

    private func handleAuthEvent(_ event: AuthEvent) {
        switch event {
        case .loggedIn(let profile):
            isLoggedIn = true
            userProfile = profile
            showLoginView = false
            startCookieRefreshTimer()

        case .loggedOut:
            isLoggedIn = false
            userProfile = nil
            cookieRefreshTask?.cancel()

        case .cookieExpired:
            showLoginView = true

        case .cookieRefreshed:
            break

        case .tokenRefreshFailed:
            showLoginView = true
        }
    }

    private func checkInitialAuthState() {
        let service = MiNoteService.shared
        isLoggedIn = service.isAuthenticated()
        if isLoggedIn {
            startCookieRefreshTimer()
        }
    }

    private func startCookieRefreshTimer() {
        cookieRefreshTask?.cancel()
        cookieRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.cookieRefreshInterval ?? 3600) * 1_000_000_000))
                guard !Task.isCancelled else { break }
                // Cookie 刷新逻辑
                await self?.refreshCookieIfNeeded()
            }
        }
    }

    private func refreshCookieIfNeeded() async {
        // 从现有 AuthenticationStateManager 迁移 Cookie 刷新逻辑
    }

    public func login() {
        showLoginView = true
    }

    public func logout() async {
        await eventBus.publish(AuthEvent.loggedOut)
    }
}
```

**Step 2: 编译验证并提交**

```bash
git add Sources/State/AuthState.swift
git commit -m "refactor(state): 实现 AuthState 认证状态管理"
```

---

### Task 11：SearchState

**Files:**
- Create: `Sources/State/SearchState.swift`

**Step 1: 实现 SearchState**

```swift
// Sources/State/SearchState.swift
import Foundation

/// 搜索状态
@MainActor
public final class SearchState: ObservableObject {

    @Published public var searchText: String = ""
    @Published public var searchResults: [Note] = []
    @Published public var isSearching: Bool = false

    // 搜索过滤选项
    @Published public var filterHasTags: Bool = false
    @Published public var filterHasImages: Bool = false
    @Published public var filterHasAudio: Bool = false
    @Published public var filterHasChecklist: Bool = false

    private let noteStore: NoteStore
    private var searchTask: Task<Void, Never>?

    public init(noteStore: NoteStore) {
        self.noteStore = noteStore
    }

    /// 执行搜索
    public func search(_ keyword: String) {
        searchText = keyword

        guard !keyword.isEmpty else {
            clearSearch()
            return
        }

        isSearching = true
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            // 防抖
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }

            let allNotes = await self?.noteStore.notes ?? []
            let lowercased = keyword.lowercased()

            let results = allNotes.filter { note in
                note.status == "normal" &&
                (note.title.lowercased().contains(lowercased) ||
                 note.content.lowercased().contains(lowercased))
            }

            await MainActor.run {
                self?.searchResults = results
                self?.isSearching = false
            }
        }
    }

    /// 清除搜索
    public func clearSearch() {
        searchText = ""
        searchResults = []
        isSearching = false
        searchTask?.cancel()
    }
}
```

**Step 2: 编译验证并提交**

```bash
git add Sources/State/SearchState.swift
git commit -m "refactor(state): 实现 SearchState 搜索状态管理"
```

---

### Task 12：Phase 2 集成验证

**Step 1: 确保所有 State 文件编译通过**

Run: `xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

此时新代码与旧代码并存，互不干扰。新的 EventBus、NoteStore、SyncEngine、6 个 State 对象都已创建但尚未被 UI 层使用。

**Step 2: 提交 Phase 2 完成标记**

```bash
git add -A
git commit -m "refactor: Phase 2 完成 - 所有 State 对象实现"
```

---

## Phase 3：AppCoordinator 重写 + UI 层切换

### Task 13：重写 AppCoordinator

**Files:**
- Modify: `Sources/Presentation/Coordinators/App/AppCoordinator.swift`

**Step 1: 重写 AppCoordinator**

将 AppCoordinator 从基于 Combine 的 ViewModel 协调改为基于 EventBus 的 State 协调。

```swift
// Sources/Presentation/Coordinators/App/AppCoordinator.swift
import Combine
import Foundation

/// 应用协调器（重构版）
///
/// 创建和管理所有核心组件，通过 EventBus 协调通信。
/// 不再使用 Combine 链式调用。
@MainActor
public final class AppCoordinator: ObservableObject {

    // MARK: - 核心组件

    public let eventBus: EventBus
    public let noteStore: NoteStore
    public let syncEngine: SyncEngine

    // MARK: - State 对象

    public let noteListState: NoteListState
    public let noteEditorState: NoteEditorState
    public let folderState: FolderState
    public let syncState: SyncState
    public let authState: AuthState
    public let searchState: SearchState

    // MARK: - 保留的旧组件（过渡期）

    public let audioPanelViewModel: AudioPanelViewModel

    /// 向后兼容：提供 NotesViewModel 接口
    /// 过渡期使用，最终删除
    public private(set) lazy var notesViewModel: NotesViewModel = NotesViewModelAdapter(coordinator: self)

    // MARK: - 初始化

    public init() {
        // 1. 创建核心组件
        let eventBus = EventBus.shared
        let db = DatabaseService.shared
        let noteStore = NoteStore(db: db, eventBus: eventBus)
        let syncEngine = SyncEngine(
            api: MiNoteService.shared,
            eventBus: eventBus,
            operationQueue: UnifiedOperationQueue.shared,
            operationProcessor: OperationProcessor.shared,
            syncStateManager: SyncStateManager.createDefault()
        )

        self.eventBus = eventBus
        self.noteStore = noteStore
        self.syncEngine = syncEngine

        // 2. 创建 State 对象
        self.noteListState = NoteListState(eventBus: eventBus)
        self.noteEditorState = NoteEditorState(eventBus: eventBus)
        self.folderState = FolderState(eventBus: eventBus)
        self.syncState = SyncState(eventBus: eventBus)
        self.authState = AuthState(eventBus: eventBus)
        self.searchState = SearchState(noteStore: noteStore)

        // 3. 保留的旧组件
        let container = DIContainer.shared
        let audioService = container.resolve(AudioServiceProtocol.self)
        let noteStorage = container.resolve(NoteStorageProtocol.self)
        self.audioPanelViewModel = AudioPanelViewModel(
            audioService: audioService,
            noteService: noteStorage
        )

        LogService.shared.info(.app, "AppCoordinator 初始化完成（EventBus 架构）")
    }

    // MARK: - 启动

    public func start() async {
        // 启动核心组件
        await noteStore.start()
        await syncEngine.start()

        // 启动所有 State 订阅
        noteListState.start()
        noteEditorState.start()
        folderState.start()
        syncState.start()
        authState.start()

        // 如果已登录，触发同步
        if authState.isLoggedIn {
            await syncState.requestSync()
        }

        LogService.shared.info(.app, "AppCoordinator 启动完成")
    }

    // MARK: - 公共操作

    public func handleNoteSelection(_ note: Note) {
        noteListState.selectNote(note)
        noteEditorState.loadNote(note)
    }

    public func handleFolderSelection(_ folderId: String?) {
        folderState.selectFolder(folderId)
        noteListState.selectFolder(folderId)
    }

    public func handleSyncRequest() async {
        await syncState.requestSync()
    }

    public func handleSearch(_ keyword: String) {
        searchState.search(keyword)
    }

    public func handleClearSearch() {
        searchState.clearSearch()
    }
}
```

注意：过渡期保留 `notesViewModel` 属性和 `NotesViewModelAdapter`，让未迁移的 UI 代码继续工作。

**Step 2: 编译验证**

此步骤可能产生大量编译错误，因为 AppCoordinator 的接口变了。需要逐步修复引用。

**Step 3: 提交**

```bash
git add Sources/Presentation/Coordinators/App/AppCoordinator.swift
git commit -m "refactor(coordinator): 重写 AppCoordinator 使用 EventBus 架构"
```

---

### Task 14：更新 UI 层依赖注入

**Files:**
- Modify: `Sources/Window/Controllers/MainWindowController.swift`
- Modify: `Sources/View/SwiftUIViews/Note/NoteDetailView.swift`
- Modify: `Sources/View/SwiftUIViews/Note/NotesListView.swift`
- Modify: 其他引用 NotesViewModel 的 SwiftUI 视图

**Step 1: 更新 MainWindowController 的环境注入**

在 MainWindowController 中，将 State 对象注入到 SwiftUI 环境：

```swift
// 在创建 NSHostingView 时注入所有 State
let coordinator = appCoordinator
let rootView = ContentView()
    .environmentObject(coordinator.noteListState)
    .environmentObject(coordinator.noteEditorState)
    .environmentObject(coordinator.folderState)
    .environmentObject(coordinator.syncState)
    .environmentObject(coordinator.authState)
    .environmentObject(coordinator.searchState)
    .environmentObject(coordinator) // 保留 coordinator 用于操作调度
```

**Step 2: 逐步更新 SwiftUI 视图**

对每个 SwiftUI 视图：
1. 将 `@EnvironmentObject var viewModel: NotesViewModel` 替换为对应的 State
2. 例如 NotesListView：`@EnvironmentObject var noteListState: NoteListState`
3. 例如 NoteDetailView：`@EnvironmentObject var noteEditorState: NoteEditorState`

这是最大的工作量步骤，需要逐个文件修改。关键原则：
- 读取笔记列表 → `noteListState.notes`
- 读取当前编辑笔记 → `noteEditorState.currentNote`
- 读取同步状态 → `syncState.isSyncing`
- 读取文件夹列表 → `folderState.folders`
- 读取登录状态 → `authState.isLoggedIn`
- 触发同步 → `syncState.requestSync()`
- 保存内容 → `noteEditorState.saveContent()`

**Step 3: 编译验证**

逐步修复编译错误，确保每个视图都能正确引用新的 State 对象。

**Step 4: 提交**

```bash
git add -u
git commit -m "refactor(ui): 更新 UI 层依赖注入，使用 State 对象替代 NotesViewModel"
```

---

### Task 15：更新 OperationProcessor 通知机制

**Files:**
- Modify: `Sources/Service/Sync/OperationProcessor.swift`

**Step 1: 将 NotificationCenter 替换为 EventBus**

OperationProcessor 中有多处使用 NotificationCenter 发送通知：
- `NoteServerTagUpdated` → 改为 `SyncEvent.tagUpdated`
- `NoteIdChanged` → 改为 `NoteEvent.saved` + ID 映射事件
- `OperationQueueProcessingCompleted` → 改为 `SyncEvent.completed`
- `OperationAuthFailed` → 改为 `ErrorEvent.authRequired`

```swift
// 替换 propagateServerTag 方法
private func propagateServerTag(_ newTag: String, forNoteId noteId: String) async {
    await EventBus.shared.publish(SyncEvent.tagUpdated(noteId: noteId, newTag: newTag))
}

// 替换 NoteIdChanged 通知
// 在 processNoteCreate 中：
await EventBus.shared.publish(NoteEvent.saved(updatedNote))

// 替换 OperationCompleted 通知
// 在 handleOperationSuccess 中：
// 不再需要单独通知，NoteStore 会通过 NoteEvent.saved 处理

// 替换 OperationAuthFailed 通知
await EventBus.shared.publish(ErrorEvent.authRequired(reason: "操作认证失败"))
```

**Step 2: 编译验证并提交**

```bash
git add Sources/Service/Sync/OperationProcessor.swift
git commit -m "refactor(sync): OperationProcessor 使用 EventBus 替代 NotificationCenter"
```

---

## Phase 4：NativeEditor 外部接口更新

### Task 16：更新 NativeEditorContext 桥接

**Files:**
- Modify: `Sources/View/Bridge/NativeEditorContext.swift`
- Modify: `Sources/View/Bridge/UnifiedEditorWrapper.swift`

**Step 1: 更新 NativeEditorContext**

NativeEditorContext 当前通过 NotesViewModel 与外部通信。
更新为通过 NoteEditorState 通信：

```swift
// NativeEditorContext 中的关键变更：
// 旧：通过 viewModel 保存
// 新：通过 NoteEditorState 保存

// 内容变更回调
func contentDidChange(title: String, xmlContent: String) {
    // 旧：viewModel.noteEditingCoordinator.contentDidChange(...)
    // 新：noteEditorState.contentDidChange(title: title, xmlContent: xmlContent)
}
```

**Step 2: 更新 UnifiedEditorWrapper**

确保 UnifiedEditorWrapper 使用 NoteEditorState 而非 NotesViewModel。

**Step 3: 编译验证并提交**

```bash
git add Sources/View/Bridge/
git commit -m "refactor(editor): 更新编辑器桥接层使用 NoteEditorState"
```

---

### Task 17：验证编辑器保存流程

**Step 1: 端到端验证编辑器保存流程**

确认以下数据流正确：

```
用户输入 → NativeEditorView → NativeEditorContext
→ NoteEditorState.contentDidChange()
→ 防抖 300ms
→ NoteEditorState.saveContent()
→ EventBus.publish(NoteEvent.contentUpdated)
→ NoteStore 收到 → 写入 DB → 发布 NoteEvent.saved
→ NoteEditorState 收到 → 更新 serverTag
→ NoteListState 收到 → 更新列表
→ SyncEngine/OperationQueue 收到 → 安排上传
```

**Step 2: 编译并运行测试**

Run: `xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: 提交**

```bash
git add -A
git commit -m "refactor(editor): 验证编辑器保存流程端到端正确"
```

---

## Phase 5：删除旧代码

### Task 18：删除旧 ViewModel 和适配层

**Files:**
- Delete: `Sources/ViewModel/NotesViewModel.swift`（3,668 行）
- Delete: `Sources/Presentation/Coordinators/App/NotesViewModelAdapter.swift`
- Delete: `Sources/Service/Editor/NoteEditingCoordinator.swift`（已被 NoteEditorState 替代）
- Delete: `Sources/Service/Sync/NoteOperationCoordinator.swift`（职责合并到 NoteStore）
- Delete: `Sources/Service/Sync/SyncStateManager.swift`（合并到 SyncState）
- Delete: `Sources/Service/Core/AuthenticationStateManager.swift`（合并到 AuthState）
- Delete: `Sources/Service/Core/ScheduledTaskManager.swift`（定时任务合并到各模块）

**Step 1: 确认所有引用已迁移**

搜索项目中对以下类型的引用，确保全部已替换：
- `NotesViewModel` → 各 State 对象
- `NotesViewModelAdapter` → 删除
- `NoteEditingCoordinator` → `NoteEditorState`
- `NoteOperationCoordinator` → `NoteStore`
- `SyncStateManager` → `SyncState` + `SyncEngine`
- `AuthenticationStateManager` → `AuthState`
- `ScheduledTaskManager` → 各模块自带定时器

**Step 2: 删除文件**

```bash
rm Sources/ViewModel/NotesViewModel.swift
rm Sources/Presentation/Coordinators/App/NotesViewModelAdapter.swift
rm Sources/Service/Editor/NoteEditingCoordinator.swift
rm Sources/Service/Sync/NoteOperationCoordinator.swift
rm Sources/Service/Sync/SyncStateManager.swift
rm Sources/Service/Core/AuthenticationStateManager.swift
rm Sources/Service/Core/ScheduledTaskManager.swift
```

**Step 3: 更新 project.yml 并重新生成项目**

```bash
# 编辑 project.yml 确保文件引用正确
xcodegen generate
```

**Step 4: 编译验证**

Run: `xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: 提交**

```bash
git add -A
git commit -m "refactor: 删除旧 ViewModel 和适配层代码（约 6,000+ 行）"
```

---

### Task 19：删除旧 SyncService

**Files:**
- Delete: `Sources/Service/Sync/SyncService.swift`（2,192 行）
- Modify: `Sources/Core/DependencyInjection/ServiceLocator.swift`（简化）

**Step 1: 确认 SyncEngine 已完全替代 SyncService**

搜索所有 `SyncService` 引用，确保已替换为 `SyncEngine`。

**Step 2: 删除 SyncService**

```bash
rm Sources/Service/Sync/SyncService.swift
```

**Step 3: 简化 ServiceLocator**

ServiceLocator 中删除对已删除服务的注册：
- 删除 `SyncServiceProtocol` 注册
- 删除 `AuthenticationStateManager` 相关
- 保留 `NoteStorageProtocol`、`NoteServiceProtocol`、`ImageServiceProtocol`、`AudioServiceProtocol`、`NetworkMonitorProtocol`

**Step 4: 更新 project.yml 并重新生成**

```bash
xcodegen generate
```

**Step 5: 编译验证并提交**

```bash
git add -A
git commit -m "refactor(sync): 删除旧 SyncService（2,192 行），完全由 SyncEngine 替代"
```

---

## Phase 6：目录结构整理 + 收尾

### Task 20：目录结构重组

**Step 1: 移动文件到新目录结构**

按照设计文档第十一节的目录结构，移动文件：

```bash
# EventBus 已在正确位置：Sources/Core/EventBus/

# NoteStore 移动到 Store 目录
# Sources/Store/NoteStore.swift（已在正确位置）

# DatabaseService 移动到 Store 目录
# Sources/Service/Storage/DatabaseService.swift → Sources/Store/DatabaseService.swift
# Sources/Service/Storage/DatabaseService+Internal.swift → Sources/Store/DatabaseService+Internal.swift
# Sources/Service/Storage/DatabaseMigrationManager.swift → Sources/Store/DatabaseMigrationManager.swift

# SyncEngine 已在正确位置：Sources/Sync/SyncEngine.swift

# OperationQueue 移动到 Sync 目录
# Sources/Service/Sync/UnifiedOperationQueue.swift → Sources/Sync/OperationQueue/UnifiedOperationQueue.swift
# Sources/Service/Sync/OperationProcessor.swift → Sources/Sync/OperationQueue/OperationProcessor.swift

# State 已在正确位置：Sources/State/

# Network 保持不变：Sources/Service/Network/

# AppCoordinator 移动
# Sources/Presentation/Coordinators/App/AppCoordinator.swift → Sources/Coordinator/AppCoordinator.swift
```

注意：每次移动文件后需要更新 `project.yml` 中的文件引用，然后运行 `xcodegen generate`。

**Step 2: 更新 project.yml**

确保所有新目录和文件路径在 project.yml 中正确配置。

**Step 3: 重新生成项目并编译验证**

```bash
xcodegen generate
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -5
```

**Step 4: 提交**

```bash
git add -A
git commit -m "refactor: 重组目录结构，按新架构分层组织代码"
```

---

### Task 21：收尾清理 + 最终验证

**Step 1: 清理残留的 NotificationCenter 使用**

搜索项目中所有 `NotificationCenter.default.post` 和 `NotificationCenter.default.addObserver`，确保全部替换为 EventBus。

保留的例外：
- 系统级通知（如 `NSApplication.willTerminateNotification`）可以保留
- 只清理自定义的业务通知

**Step 2: 清理残留的 Combine 链**

搜索 `$xxx.sink` 和 `.store(in: &cancellables)`，确保跨模块通信全部通过 EventBus。

模块内部的 Combine 使用（如 SwiftUI 的 `@Published` → View 绑定）保留不变。

**Step 3: 验证关键数据流**

手动验证以下场景：
1. 启动应用 → 加载笔记列表 → 显示正确
2. 选择笔记 → 编辑器加载内容 → 显示正确
3. 编辑内容 → 自动保存 → 列表标题更新
4. 触发同步 → 下载变更 → 列表刷新
5. 上传成功 → serverTag 更新 → 后续编辑不冲突
6. 切换文件夹 → 列表过滤正确
7. 搜索 → 结果正确

**Step 4: 最终编译验证**

```bash
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug build 2>&1 | tail -5
```

**Step 5: 最终提交**

```bash
git add -A
git commit -m "refactor: 架构重构收尾，清理残留通知和 Combine 链"
```

---

## 实施注意事项

### 编译策略

由于这是全面重构，建议采用"新旧并存 → 逐步切换 → 删除旧代码"的策略：
- Phase 1-2：新代码与旧代码并存，互不干扰
- Phase 3：逐步将 UI 从旧 ViewModel 切换到新 State
- Phase 4：更新编辑器接口
- Phase 5-6：删除旧代码，整理目录

每个 Task 完成后都应该是可编译状态。

### 风险点

1. **Note 模型重构（Task 3）**：删除 `rawData` 影响面最大，需要仔细处理所有引用
2. **UI 层切换（Task 14）**：SwiftUI 视图数量多，逐个修改工作量大
3. **SyncEngine 实现（Task 5）**：需要完整迁移 SyncService 的 API 调用逻辑
4. **OperationProcessor 改造（Task 15）**：NotificationCenter → EventBus 需要确保时序正确

### 回滚策略

每个 Phase 完成后创建 tag：
```bash
git tag refactor-phase-1-complete
git tag refactor-phase-2-complete
# ...
```

如果某个 Phase 出现严重问题，可以回滚到上一个 Phase 的 tag。
