# spec-133：组合根按域拆分 — 设计

## 技术方案

### 1. 域 Assembler 设计

每个域 Assembler 是一个 `@MainActor enum`（与现有 AppCoordinatorAssembler 风格一致），提供静态工厂方法，接收跨域依赖作为参数，返回域产出结构体。

```swift
@MainActor
enum NotesAssembler {
    struct Output {
        let noteStore: NoteStore
        let noteListState: NoteListState
        let noteEditorState: NoteEditorState
        let notePreviewService: NotePreviewService
    }

    static func assemble(
        eventBus: EventBus,
        networkModule: NetworkModule,
        syncModule: SyncModule
    ) -> Output { ... }
}
```

### 2. 拆分映射

| 域 Assembler | 构建的实例 | 跨域输入 |
|---|---|---|
| NotesAssembler | NoteStore, NoteListState, NoteEditorState, NotePreviewService | eventBus, networkModule, syncModule |
| SyncAssembler | SyncEngine, SyncState, StartupSequenceManager, ErrorRecoveryService, NetworkRecoveryHandler | eventBus, networkModule, syncModule, noteStore |
| AuthAssembler | PassTokenManager, AuthState, SearchState | eventBus, networkModule, syncModule, noteStore |
| EditorAssembler | wireEditorContext 调用 | noteEditorState, editorModule, audioModule |
| AudioAssembler | AudioPanelViewModel, MemoryCacheManager | (无跨域依赖) |

### 3. 主装配器简化后的伪代码

```swift
static func buildDependencies() -> AppCoordinator.Dependencies {
    let networkModule = NetworkModule()
    let syncModule = SyncModule(networkModule: networkModule)
    networkModule.requestManager.setOnlineStateManager(syncModule.onlineStateManager)
    let editorModule = EditorModule(syncModule: syncModule, networkModule: networkModule)
    let audioModule = AudioModule(syncModule: syncModule, networkModule: networkModule)

    let notes = NotesAssembler.assemble(eventBus: .shared, networkModule: networkModule, syncModule: syncModule)
    let sync = SyncAssembler.assemble(eventBus: .shared, networkModule: networkModule, syncModule: syncModule, noteStore: notes.noteStore)
    let auth = AuthAssembler.assemble(eventBus: .shared, networkModule: networkModule, syncModule: syncModule, noteStore: notes.noteStore)
    let audio = AudioAssembler.assemble()

    networkModule.setPassTokenManager(auth.passTokenManager)
    EditorAssembler.wireContext(noteEditorState: notes.noteEditorState, editorModule: editorModule, audioModule: audioModule)

    return Dependencies(...)
}
```

### 4. 文件位置

所有域 Assembler 放在 `Sources/Coordinator/` 目录（与 AppCoordinatorAssembler 同级），后续 spec-135 目录骨架建立时再迁移到 `Sources/App/Composition/`。

## 影响范围

- 修改：`Sources/Coordinator/AppCoordinatorAssembler.swift`
- 新增：`Sources/Coordinator/NotesAssembler.swift`、`SyncAssembler.swift`、`AuthAssembler.swift`、`EditorAssembler.swift`、`AudioAssembler.swift`
