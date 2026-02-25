# OperationProcessor 第一层拆分设计

## 背景

`OperationProcessor` 当前 1441 行，是典型的 God Actor 模式：调度/重试/API 调用/数据修复/事件发布全部集中在一个文件。这是 `architecture-next.md` 9.1 节定义的前置任务之一。

## 目标

- 按操作域拆出 handler，降低单点复杂度
- OperationProcessor 仅保留调度层和错误分类
- 公共接口不变，外部调用方零改动
- 所有依赖通过构造器注入，不引入 `.shared`

## 方案：Handler 协议拆分

### 协议定义

```swift
protocol OperationHandler: Sendable {
    func handle(_ operation: NoteOperation) async throws
}
```

### Handler 分组

| Handler | 操作类型 | 依赖 |
|---------|---------|------|
| NoteOperationHandler | noteCreate, cloudUpload, cloudDelete | noteAPI, localStorage, idMappingRegistry, operationQueue, eventBus, responseParser |
| FileOperationHandler | imageUpload, audioUpload | fileAPI, localStorage, idMappingRegistry, operationQueue, eventBus, databaseService, responseParser |
| FolderOperationHandler | folderCreate, folderRename, folderDelete | folderAPI, databaseService, eventBus, responseParser |

### OperationResponseParser

响应解析辅助方法（isResponseSuccess / extractEntry / extractTag / extractErrorMessage）抽到独立的纯函数工具结构体，供各 handler 共用：

```swift
struct OperationResponseParser: Sendable {
    func isResponseSuccess(_ response: [String: Any]) -> Bool { ... }
    func extractEntry(from response: [String: Any]) -> [String: Any]? { ... }
    func extractTag(from response: [String: Any], fallbackTag: String) -> String { ... }
    func extractErrorMessage(from response: [String: Any], defaultMessage: String) -> String { ... }
}
```

### OperationProcessor 改动

`executeOperation` 改为查表分发：

```swift
private let handlers: [OperationType: OperationHandler]

private func executeOperation(_ operation: NoteOperation) async throws {
    guard let handler = handlers[operation.type] else {
        throw NSError(domain: "OperationProcessor", code: 400,
                      userInfo: [NSLocalizedDescriptionKey: "不支持的操作类型: \(operation.type.rawValue)"])
    }
    try await handler.handle(operation)
}
```

保留在 OperationProcessor 中的职责：
- 调度层（processImmediately / processQueue / processRetries / processOperationsAtStartup）
- 错误分类（classifyError / classifyURLError / classifyURLErrorCode）
- 重试策略（calculateRetryDelay / handleOperationFailure）
- 状态管理（isProcessing / currentOperation）
- 文件上传等待保护逻辑（processQueue 中的 hasPendingFileUpload 检查）

### 回调迁移

`onIdMappingCreated` 回调从 OperationProcessor 移到 NoteOperationHandler，因为只有 noteCreate 使用。

### SyncModule 集成

SyncModule 工厂负责构建各 handler 并注入到 OperationProcessor：

```swift
let responseParser = OperationResponseParser()

let noteHandler = NoteOperationHandler(
    noteAPI: networkModule.noteAPI,
    localStorage: storage,
    idMappingRegistry: registry,
    operationQueue: queue,
    eventBus: EventBus.shared,
    responseParser: responseParser
)

let fileHandler = FileOperationHandler(
    fileAPI: networkModule.fileAPI,
    localStorage: storage,
    idMappingRegistry: registry,
    operationQueue: queue,
    eventBus: EventBus.shared,
    databaseService: db,
    responseParser: responseParser
)

let folderHandler = FolderOperationHandler(
    folderAPI: networkModule.folderAPI,
    databaseService: db,
    eventBus: EventBus.shared,
    responseParser: responseParser
)

let processor = OperationProcessor(
    operationQueue: queue,
    apiClient: networkModule.apiClient,
    syncStateManager: stateManager,
    eventBus: EventBus.shared,
    idMappingRegistry: registry,
    handlers: [
        .noteCreate: noteHandler,
        .cloudUpload: noteHandler,
        .cloudDelete: noteHandler,
        .imageUpload: fileHandler,
        .audioUpload: fileHandler,
        .folderCreate: folderHandler,
        .folderRename: folderHandler,
        .folderDelete: folderHandler,
    ]
)
```

## 文件结构

```
Sources/Sync/OperationQueue/
├── OperationProcessor.swift          # 调度层 + 错误分类（~450 行）
├── OperationHandler.swift            # 协议定义 + OperationResponseParser（~60 行）
├── NoteOperationHandler.swift        # noteCreate/cloudUpload/cloudDelete（~400 行）
├── FileOperationHandler.swift        # imageUpload/audioUpload（~280 行）
├── FolderOperationHandler.swift      # folderCreate/folderRename/folderDelete（~200 行）
└── UnifiedOperationQueue.swift       # 不变
```

## 公共接口不变

外部调用方（SyncEngine, NoteStore, NoteEditingCoordinator 等）使用的接口完全不变：
- `processImmediately(_:)`
- `processQueue()`
- `processRetries()`
- `processOperationsAtStartup()`
- `isProcessing`
- `currentOperation`

## 验收标准

1. 编译通过
2. OperationProcessor 降到 ~450 行以内
3. 各 handler 可独立理解，单文件不超过 400 行
4. 外部调用方零改动
5. 主流程行为保持一致（创建/上传/删除/重试）
