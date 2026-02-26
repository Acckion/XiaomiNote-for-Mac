# spec-136：目录结构全面对齐 — 设计

## 概述

本 spec 是架构改进路线图的收官之作，负责将所有散落在旧技术层目录中的代码迁入 `architecture-next.md` 第 5 节定义的目标结构。迁移涉及约 150 个文件，横跨 14 个需求，按依赖关系分为 12 个批次执行。

## 迁移顺序设计

迁移顺序遵循"被依赖者先行"原则，避免中间态编译失败：

```
批次 1: Search 域（最轻量，验证流程）
批次 2: Auth 域 UI 补全（3 个视图 + 1 个窗口控制器）
批次 3: Shared/Contracts（服务协议，被多域依赖）
批次 4: Shared/Kernel — 核心基础设施（EventBus、LogService、Extensions）
批次 5: Shared/Kernel — 数据存储层（Store 全部文件）
批次 6: Shared/Kernel — State 文件归位
批次 7: Shared/UICommons — 共享 UI 组件
批次 8: Editor 域（服务层 + UI 层，最大批次）
批次 9: Audio 域（服务层 + UI 层）
批次 10: Common 视图分流（按域归位）
批次 11: 旧目录清理 + 模块工厂迁移
批次 12: 文档更新
```

---

## 批次 1：Search 域迁移（REQ-1）

Search 域最轻量，仅 2 个文件，用于验证迁移流程。

```
Features/Search/
├── Domain/                          # 建壳
├── Infrastructure/                  # 建壳
├── Application/
│   └── SearchState.swift            ← State/SearchState.swift
└── UI/
    └── SearchFilterMenuContent.swift ← View/SwiftUIViews/Search/SearchFilterMenuContent.swift
```

迁移清单：
- `git mv Sources/State/SearchState.swift Sources/Features/Search/Application/`
- `git mv Sources/View/SwiftUIViews/Search/SearchFilterMenuContent.swift Sources/Features/Search/UI/`

---

## 批次 2：Auth 域 UI 补全（REQ-4）

Auth 域已有四层结构（spec-128 建立），UI 层当前为空壳，补入认证相关视图。

```
Features/Auth/UI/
├── LoginView.swift                          ← View/SwiftUIViews/Auth/LoginView.swift
├── PrivateNotesPasswordInputDialogView.swift ← View/SwiftUIViews/Auth/PrivateNotesPasswordInputDialogView.swift
├── PrivateNotesVerificationView.swift       ← View/SwiftUIViews/Auth/PrivateNotesVerificationView.swift
└── LoginWindowController.swift              ← Window/Controllers/LoginWindowController.swift
```

迁移清单：
- `git mv Sources/View/SwiftUIViews/Auth/*.swift Sources/Features/Auth/UI/`
- `git mv Sources/Window/Controllers/LoginWindowController.swift Sources/Features/Auth/UI/`

---

## 批次 3：Shared/Contracts 迁入（REQ-7）

服务协议被多个域引用，需先于域代码迁移。

```
Shared/Contracts/
├── AudioServiceProtocol.swift       ← Service/Protocols/AudioServiceProtocol.swift
├── CacheServiceProtocol.swift       ← Service/Protocols/CacheServiceProtocol.swift
├── NetworkMonitorProtocol.swift     ← Service/Protocols/NetworkMonitorProtocol.swift
└── NoteStorageProtocol.swift        ← Service/Protocols/NoteStorageProtocol.swift
```

迁移清单：
- `git mv Sources/Service/Protocols/*.swift Sources/Shared/Contracts/`
- 删除 `Sources/Shared/Contracts/.gitkeep`（已有实际文件）

---

## 批次 4：Shared/Kernel — 核心基础设施（REQ-5 部分）

EventBus、LogService、PerformanceService 等跨域基础设施迁入 Kernel。

```
Shared/Kernel/
├── EventBus/
│   ├── EventBus.swift               ← Core/EventBus/EventBus.swift
│   ├── AppEvent.swift               ← Core/EventBus/AppEvent.swift
│   ├── NoteUpdateEvent.swift        ← Core/EventBus/NoteUpdateEvent.swift
│   └── Events/
│       ├── AuthEvent.swift          ← Core/EventBus/Events/AuthEvent.swift
│       ├── ErrorEvent.swift         ← Core/EventBus/Events/ErrorEvent.swift
│       ├── FolderEvent.swift        ← Core/EventBus/Events/FolderEvent.swift
│       ├── IdMappingEvent.swift     ← Core/EventBus/Events/IdMappingEvent.swift
│       ├── NetworkRecoveryEvent.swift ← Core/EventBus/Events/NetworkRecoveryEvent.swift
│       ├── NoteEvent.swift          ← Core/EventBus/Events/NoteEvent.swift
│       ├── OnlineEvent.swift        ← Core/EventBus/Events/OnlineEvent.swift
│       ├── OperationEvent.swift     ← Core/EventBus/Events/OperationEvent.swift
│       ├── SettingsEvent.swift      ← Core/EventBus/Events/SettingsEvent.swift
│       ├── StartupEvent.swift       ← Core/EventBus/Events/StartupEvent.swift
│       └── SyncEvent.swift          ← Core/EventBus/Events/SyncEvent.swift
├── LogService.swift                 ← Service/Core/LogService.swift
├── PerformanceService.swift         ← Service/Core/PerformanceService.swift
├── Pageable.swift                   ← Core/Pagination/Pageable.swift
├── Extensions/
│   ├── Notification+FormatState.swift ← Extensions/Notification+FormatState.swift
│   ├── Notification+MenuState.swift   ← Extensions/Notification+MenuState.swift
│   ├── NSColor+Hex.swift              ← Extensions/NSColor+Hex.swift
│   └── NSWindow+MiNote.swift          ← Extensions/NSWindow+MiNote.swift
└── PreviewHelper.swift              ← View/SwiftUIViews/Common/PreviewHelper.swift
```

迁移清单：
- `git mv Sources/Core/EventBus Sources/Shared/Kernel/EventBus`
- `git mv Sources/Service/Core/LogService.swift Sources/Shared/Kernel/`
- `git mv Sources/Service/Core/PerformanceService.swift Sources/Shared/Kernel/`
- `git mv Sources/Core/Pagination/Pageable.swift Sources/Shared/Kernel/`
- `mkdir -p Sources/Shared/Kernel/Extensions`
- `git mv Sources/Extensions/*.swift Sources/Shared/Kernel/Extensions/`
- `git mv Sources/View/SwiftUIViews/Common/PreviewHelper.swift Sources/Shared/Kernel/`
- 删除 `Sources/Shared/Kernel/README.md`（已有实际文件）

保留在 `Service/Core/` 的文件：
- `StartupSequenceManager.swift`：启动链编排，属于 App 层职责
- `ErrorRecoveryService.swift`：错误恢复，属于 App 层职责

---

## 批次 5：Shared/Kernel — 数据存储层（REQ-10）

DatabaseService 及相关文件是跨域基础设施，迁入 Kernel。

```
Shared/Kernel/
├── Store/
│   ├── DatabaseService.swift                    ← Store/DatabaseService.swift
│   ├── DatabaseService+Folders.swift            ← Store/DatabaseService+Folders.swift
│   ├── DatabaseService+Internal.swift           ← Store/DatabaseService+Internal.swift
│   ├── DatabaseService+Notes.swift              ← Store/DatabaseService+Notes.swift
│   ├── DatabaseService+NoteStorageProtocol.swift ← Store/DatabaseService+NoteStorageProtocol.swift
│   ├── DatabaseService+Operations.swift         ← Store/DatabaseService+Operations.swift
│   ├── DatabaseService+SyncStatus.swift         ← Store/DatabaseService+SyncStatus.swift
│   ├── DatabaseMigrationManager.swift           ← Store/DatabaseMigrationManager.swift
│   ├── LocalStorageService.swift                ← Store/LocalStorageService.swift
│   ├── MemoryCacheManager.swift                 ← Store/MemoryCacheManager.swift
│   └── Implementation/
│       └── DefaultNoteStorage.swift             ← Store/Implementation/DefaultNoteStorage.swift
└── Cache/
    └── DefaultCacheService.swift                ← Service/Cache/Implementation/DefaultCacheService.swift
```

迁移清单：
- `mkdir -p Sources/Shared/Kernel/Store/Implementation`
- `git mv Sources/Store/DatabaseService.swift Sources/Shared/Kernel/Store/`
- `git mv Sources/Store/DatabaseService+*.swift Sources/Shared/Kernel/Store/`
- `git mv Sources/Store/DatabaseMigrationManager.swift Sources/Shared/Kernel/Store/`
- `git mv Sources/Store/LocalStorageService.swift Sources/Shared/Kernel/Store/`
- `git mv Sources/Store/MemoryCacheManager.swift Sources/Shared/Kernel/Store/`
- `git mv Sources/Store/Implementation/DefaultNoteStorage.swift Sources/Shared/Kernel/Store/Implementation/`
- `mkdir -p Sources/Shared/Kernel/Cache`
- `git mv Sources/Service/Cache/Implementation/DefaultCacheService.swift Sources/Shared/Kernel/Cache/`

---

## 批次 6：Shared/Kernel — State 文件归位（REQ-8）

`Sources/State/` 中剩余的跨域视图状态文件迁入 Kernel。

```
Shared/Kernel/
├── ViewOptionsManager.swift         ← State/ViewOptionsManager.swift
├── ViewOptionsState.swift           ← State/ViewOptionsState.swift
└── ViewState.swift                  ← State/ViewState.swift
```

迁移清单：
- `git mv Sources/State/ViewOptionsManager.swift Sources/Shared/Kernel/`
- `git mv Sources/State/ViewOptionsState.swift Sources/Shared/Kernel/`
- `git mv Sources/State/ViewState.swift Sources/Shared/Kernel/`

---

## 批次 7：Shared/UICommons — 共享 UI 组件（REQ-6、REQ-9 部分）

跨域共享的 UI 组件和设置面板迁入 UICommons。

```
Shared/UICommons/
├── OnlineStatusIndicator.swift      ← View/Shared/OnlineStatusIndicator.swift
├── SidebarViewController.swift      ← View/AppKitComponents/SidebarViewController.swift
├── NetworkLogView.swift             ← View/SwiftUIViews/Common/NetworkLogView.swift
├── Toolbar/
│   ├── MainWindowToolbarDelegate.swift  ← ToolbarItem/MainWindowToolbarDelegate.swift
│   ├── ToolbarItemFactory.swift         ← ToolbarItem/ToolbarItemFactory.swift
│   ├── ToolbarItemProtocol.swift        ← ToolbarItem/ToolbarItemProtocol.swift
│   └── ToolbarVisibilityManager.swift   ← ToolbarItem/ToolbarVisibilityManager.swift
└── Settings/
    ├── DebugSettingsView.swift          ← View/SwiftUIViews/Settings/DebugSettingsView.swift
    ├── EditorSettingsView.swift         ← View/SwiftUIViews/Settings/EditorSettingsView.swift
    ├── OperationQueueDebugView.swift    ← View/SwiftUIViews/Settings/OperationQueueDebugView.swift
    ├── SettingsView.swift               ← View/SwiftUIViews/Settings/SettingsView.swift
    ├── ViewOptionsMenuView.swift        ← View/SwiftUIViews/Settings/ViewOptionsMenuView.swift
    └── XMLRoundtripDebugView.swift      ← View/SwiftUIViews/Settings/XMLRoundtripDebugView.swift
```

文件归属说明：
- `OnlineStatusIndicator`：在线状态指示器，多个窗口使用，跨域
- `SidebarViewController`：AppKit 侧边栏控制器，窗口级组件，跨域
- `NetworkLogView`：网络日志调试视图，跨域调试工具
- `Toolbar/`：工具栏组件，窗口级基础设施，跨域
- `Settings/`：设置面板，跨域配置界面

迁移清单：
- `git mv Sources/View/Shared/OnlineStatusIndicator.swift Sources/Shared/UICommons/`
- `git mv Sources/View/AppKitComponents/SidebarViewController.swift Sources/Shared/UICommons/`
- `git mv Sources/View/SwiftUIViews/Common/NetworkLogView.swift Sources/Shared/UICommons/`
- `mkdir -p Sources/Shared/UICommons/Toolbar`
- `git mv Sources/ToolbarItem/*.swift Sources/Shared/UICommons/Toolbar/`
- `mkdir -p Sources/Shared/UICommons/Settings`
- `git mv Sources/View/SwiftUIViews/Settings/*.swift Sources/Shared/UICommons/Settings/`
- 删除 `Sources/Shared/UICommons/README.md`

---

## 批次 8：Editor 域迁移（REQ-2）

Editor 域是本 spec 最大的迁移批次，涉及服务层代码和大量 UI 文件。

### 8a. Editor 服务层

```
Features/Editor/
├── Domain/
│   ├── EditorConfiguration.swift    ← Service/Editor/EditorConfiguration.swift
│   └── TitleIntegrationError.swift  ← Service/Editor/TitleIntegrationError.swift
├── Infrastructure/
│   └── FormatConverter/             ← Service/Editor/FormatConverter/（整体迁移，保留子目录结构）
│       ├── AST/                     （3 个文件）
│       ├── Converter/               （4 个文件）
│       ├── Generator/               （1 个文件）
│       ├── Parser/                  （3 个文件）
│       ├── Utils/                   （3 个文件）
│       ├── ConversionError.swift
│       ├── XiaoMiFormatConverter.swift
│       ├── XMLNormalizer.swift
│       └── XMLRoundtripChecker.swift
└── Application/
    └── NoteEditingCoordinator.swift ← Service/Editor/NoteEditingCoordinator.swift
```

### 8b. Editor UI 层 — Bridge 文件

Bridge 文件全部属于编辑器域，迁入 `Features/Editor/UI/Bridge/`。

```
Features/Editor/UI/
├── Bridge/
│   ├── AudioPanelHostingController.swift    ← View/Bridge/AudioPanelHostingController.swift
│   ├── AutoSaveManager.swift                ← View/Bridge/AutoSaveManager.swift
│   ├── ContentAreaHostingController.swift   ← View/Bridge/ContentAreaHostingController.swift
│   ├── CursorFormatManager.swift            ← View/Bridge/CursorFormatManager.swift
│   ├── EditorChangeTracker.swift            ← View/Bridge/EditorChangeTracker.swift
│   ├── EditorContentManager.swift           ← View/Bridge/EditorContentManager.swift
│   ├── EditorEnums.swift                    ← View/Bridge/EditorEnums.swift
│   ├── EditorFormatDetector.swift           ← View/Bridge/EditorFormatDetector.swift
│   ├── FormatAttributesBuilder.swift        ← View/Bridge/FormatAttributesBuilder.swift
│   ├── FormatMenuProvider.swift             ← View/Bridge/FormatMenuProvider.swift
│   ├── FormatState.swift                    ← View/Bridge/FormatState.swift
│   ├── FormatStateManager.swift             ← View/Bridge/FormatStateManager.swift
│   ├── GalleryHostingController.swift       ← View/Bridge/GalleryHostingController.swift
│   ├── NativeEditorContext.swift            ← View/Bridge/NativeEditorContext.swift
│   ├── SidebarHostingController.swift       ← View/Bridge/SidebarHostingController.swift
│   └── UnifiedEditorWrapper.swift           ← View/Bridge/UnifiedEditorWrapper.swift
```

注意：`AudioPanelHostingController.swift` 虽然名称含 Audio，但它是 AppKit-SwiftUI 桥接控制器，职责是将 AudioPanelView 嵌入编辑器窗口，属于编辑器域的 UI 集成层。

### 8c. Editor UI 层 — NativeEditor 文件

NativeEditor 整体迁入，保留子目录结构。

```
Features/Editor/UI/
└── NativeEditor/
    ├── Attachment/                          （8 个文件，整体迁移）
    ├── Core/                               （11 个文件，整体迁移）
    ├── Format/                             （16 个文件，整体迁移）
    ├── Manager/                            （5 个文件，整体迁移）
    ├── Model/                              （5 个文件，整体迁移）
    └── Performance/                        （1 个文件，整体迁移）
```

### 8d. Editor UI 层 — Common 中的编辑器视图

```
Features/Editor/UI/
├── NativeFormatMenuView.swift       ← View/SwiftUIViews/Common/NativeFormatMenuView.swift
└── XMLDebugEditorView.swift         ← View/SwiftUIViews/Common/XMLDebugEditorView.swift
```

迁移清单（批次 8 合计）：
- `git mv Sources/Service/Editor/EditorConfiguration.swift Sources/Features/Editor/Domain/`
- `git mv Sources/Service/Editor/TitleIntegrationError.swift Sources/Features/Editor/Domain/`
- `git mv Sources/Service/Editor/FormatConverter Sources/Features/Editor/Infrastructure/FormatConverter`
- `git mv Sources/Service/Editor/NoteEditingCoordinator.swift Sources/Features/Editor/Application/`
- `mkdir -p Sources/Features/Editor/UI/Bridge`
- `git mv Sources/View/Bridge/*.swift Sources/Features/Editor/UI/Bridge/`
- `git mv Sources/View/NativeEditor Sources/Features/Editor/UI/NativeEditor`
- `git mv Sources/View/SwiftUIViews/Common/NativeFormatMenuView.swift Sources/Features/Editor/UI/`
- `git mv Sources/View/SwiftUIViews/Common/XMLDebugEditorView.swift Sources/Features/Editor/UI/`

保留在原位：`Service/Editor/EditorModule.swift`（模块工厂，批次 11 统一处理）

---

## 批次 9：Audio 域迁移（REQ-3）

Audio 域涉及服务层和 UI 层文件。

```
Features/Audio/
├── Domain/                              # 建壳
├── Infrastructure/
│   ├── AudioCacheService.swift          ← Service/Audio/AudioCacheService.swift
│   ├── AudioConverterService.swift      ← Service/Audio/AudioConverterService.swift
│   ├── AudioUploadService.swift         ← Service/Audio/AudioUploadService.swift
│   ├── AudioPlayerService.swift         ← Service/Audio/AudioPlayerService.swift
│   ├── AudioRecorderService.swift       ← Service/Audio/AudioRecorderService.swift
│   ├── AudioDecryptService.swift        ← Service/Audio/AudioDecryptService.swift
│   └── DefaultAudioService.swift        ← Service/Audio/Implementation/DefaultAudioService.swift
├── Application/
│   ├── AudioPanelStateManager.swift     ← Service/Audio/AudioPanelStateManager.swift
│   └── AudioPanelViewModel.swift        ← Presentation/ViewModels/AudioPanel/AudioPanelViewModel.swift
└── UI/
    ├── AudioPanelView.swift             ← View/SwiftUIViews/Audio/AudioPanelView.swift
    ├── AudioPlayerView.swift            ← View/SwiftUIViews/Audio/AudioPlayerView.swift
    ├── AudioRecorderUploadView.swift    ← View/SwiftUIViews/Audio/AudioRecorderUploadView.swift
    └── AudioRecorderView.swift          ← View/SwiftUIViews/Audio/AudioRecorderView.swift
```

迁移清单：
- `git mv Sources/Service/Audio/AudioCacheService.swift Sources/Features/Audio/Infrastructure/`
- `git mv Sources/Service/Audio/AudioConverterService.swift Sources/Features/Audio/Infrastructure/`
- `git mv Sources/Service/Audio/AudioUploadService.swift Sources/Features/Audio/Infrastructure/`
- `git mv Sources/Service/Audio/AudioPlayerService.swift Sources/Features/Audio/Infrastructure/`
- `git mv Sources/Service/Audio/AudioRecorderService.swift Sources/Features/Audio/Infrastructure/`
- `git mv Sources/Service/Audio/AudioDecryptService.swift Sources/Features/Audio/Infrastructure/`
- `git mv Sources/Service/Audio/Implementation/DefaultAudioService.swift Sources/Features/Audio/Infrastructure/`
- `git mv Sources/Service/Audio/AudioPanelStateManager.swift Sources/Features/Audio/Application/`
- `git mv Sources/Presentation/ViewModels/AudioPanel/AudioPanelViewModel.swift Sources/Features/Audio/Application/`
- `git mv Sources/View/SwiftUIViews/Audio/*.swift Sources/Features/Audio/UI/`

保留在原位：`Service/Audio/AudioModule.swift`（模块工厂，批次 11 统一处理）

---

## 批次 10：Common 视图分流（REQ-9 部分）

`View/SwiftUIViews/Common/` 中剩余文件按域归位：

| 文件 | 目标位置 | 归属理由 |
|------|---------|---------|
| ContentAreaView.swift | Features/Notes/UI/ | 主内容区域，协调 Notes 列表和详情视图 |
| SidebarView.swift | Features/Notes/UI/ | 侧边栏，显示文件夹导航和笔记列表 |
| GalleryView.swift | Features/Notes/UI/ | 画廊视图，展示笔记卡片网格 |
| FloatingInfoBar.swift | Features/Notes/UI/ | 笔记元信息栏（修改日期、字数等） |
| TrashView.swift | Features/Notes/UI/ | 回收站视图，管理已删除笔记 |
| OperationProcessorProgressView.swift | Features/Sync/UI/ | 操作处理器进度，属于同步域 |
| OfflineOperationsProgressView.swift | Features/Sync/UI/ | 离线操作进度，属于同步域 |

迁移清单：
- `git mv Sources/View/SwiftUIViews/Common/ContentAreaView.swift Sources/Features/Notes/UI/`
- `git mv Sources/View/SwiftUIViews/Common/SidebarView.swift Sources/Features/Notes/UI/`
- `git mv Sources/View/SwiftUIViews/Common/GalleryView.swift Sources/Features/Notes/UI/`
- `git mv Sources/View/SwiftUIViews/Common/FloatingInfoBar.swift Sources/Features/Notes/UI/`
- `git mv Sources/View/SwiftUIViews/Common/TrashView.swift Sources/Features/Notes/UI/`
- `git mv Sources/View/SwiftUIViews/Common/OperationProcessorProgressView.swift Sources/Features/Sync/UI/`
- `git mv Sources/View/SwiftUIViews/Common/OfflineOperationsProgressView.swift Sources/Features/Sync/UI/`

---

## 批次 11：旧目录清理 + 模块工厂迁移（REQ-12、REQ-13、REQ-11）

### 11a. 模块工厂迁移（REQ-13，方案 B）

EditorModule 和 AudioModule 本质是组合根的一部分，迁入 `App/Composition/` 与 Assembler 统一管理。

```
App/Composition/
├── AppCoordinatorAssembler.swift    （已有）
├── NotesAssembler.swift             （已有）
├── SyncAssembler.swift              （已有）
├── AuthAssembler.swift              （已有）
├── EditorAssembler.swift            （已有）
├── AudioAssembler.swift             （已有）
├── EditorModule.swift               ← Service/Editor/EditorModule.swift
└── AudioModule.swift                ← Service/Audio/AudioModule.swift
```

注意：NetworkModule 和 SyncModule 当前在 `Network/NetworkModule.swift` 和 `Features/Sync/Infrastructure/`，位置合理，暂不迁移。

### 11b. 遗留代码归档（REQ-11）

```
Legacy/
└── DefaultNetworkMonitor.swift      ← Network/Implementation/DefaultNetworkMonitor.swift
```

`DefaultNetworkMonitor` 是 `NetworkMonitorProtocol` 的实现，当前仅被 NetworkModule 引用。迁入 Legacy 标记待评估，后续可考虑迁入 Network 主干或 Shared/Kernel。

### 11c. 启动链文件迁移

`Service/Core/` 中剩余的启动链文件迁入 `App/Runtime/`：

```
App/Runtime/
├── AppStateManager.swift            （已有）
├── StartupSequenceManager.swift     ← Service/Core/StartupSequenceManager.swift
└── ErrorRecoveryService.swift       ← Service/Core/ErrorRecoveryService.swift
```

### 11d. 旧目录清理

迁移完成后，以下目录应为空，执行删除：

| 目录 | 状态 |
|------|------|
| `Sources/State/` | 全部文件已迁出，删除 |
| `Sources/Presentation/` | AudioPanelViewModel 已迁出，删除 |
| `Sources/Service/Cache/` | DefaultCacheService 已迁出，删除 |
| `Sources/Service/Protocols/` | 协议已迁入 Shared/Contracts，删除 |
| `Sources/Service/Core/` | 文件已迁出，删除 |
| `Sources/Service/Editor/` | EditorModule 已迁出，FormatConverter 已迁出，删除 |
| `Sources/Service/Audio/` | AudioModule 已迁出，服务文件已迁出，删除 |
| `Sources/Service/` | 所有子目录已清空，删除 |
| `Sources/View/Bridge/` | 全部迁入 Features/Editor/UI/Bridge，删除 |
| `Sources/View/NativeEditor/` | 全部迁入 Features/Editor/UI/NativeEditor，删除 |
| `Sources/View/Shared/` | OnlineStatusIndicator 已迁出，删除 |
| `Sources/View/AppKitComponents/` | SidebarViewController 已迁出，删除 |
| `Sources/View/SwiftUIViews/` | 所有子目录已清空，删除 |
| `Sources/View/` | 所有子目录已清空，删除 |
| `Sources/Core/EventBus/` | 已迁入 Shared/Kernel，删除 |
| `Sources/Core/Pagination/` | Pageable 已迁出，删除 |
| `Sources/Extensions/` | 已迁入 Shared/Kernel/Extensions，删除 |
| `Sources/ToolbarItem/` | 已迁入 Shared/UICommons/Toolbar，删除 |
| `Sources/Store/` | 已迁入 Shared/Kernel/Store，删除 |
| `Sources/Network/Implementation/` | DefaultNetworkMonitor 已迁入 Legacy，删除 |

保留的目录：
- `Sources/Core/Command/` — 命令模式，跨域基础设施，保留
- `Sources/Core/Cache/`、`Core/Concurrency/` — 如果存在，保留
- `Sources/Network/` — 网络主干（APIClient、NetworkModule 等），保留
- `Sources/Window/` — 窗口控制器，保留（LoginWindowController 已迁出）
- `Sources/Coordinator/` — AppCoordinator，保留
- `Sources/Legacy/` — 过渡目录，保留

---

## 批次 12：文档更新（REQ-14）

- 更新 `AGENTS.md` 中的项目结构描述，反映最终目录布局
- 更新 `architecture-next.md` 第 5 节，标记目录重组已完成
- 更新 `docs/plans/TODO`，标记 spec-136 完成
- 删除 `Sources/Shared/Kernel/README.md`、`Sources/Shared/UICommons/README.md`、`Sources/Legacy/README.md`（已有实际文件替代）

---

## 影响范围汇总

| 类别 | 文件数 |
|------|--------|
| Search 域 | 2 |
| Auth 域 UI | 4 |
| Shared/Contracts | 4 |
| Shared/Kernel（核心） | 20 |
| Shared/Kernel（Store） | 12 |
| Shared/Kernel（State） | 3 |
| Shared/UICommons | 12 |
| Editor 域（服务层） | 3 + FormatConverter 目录（17 个文件） |
| Editor 域（UI 层） | 16 + 46 + 2 = 64 |
| Audio 域 | 11 |
| Common 视图分流 | 7 |
| 模块工厂迁移 | 2 |
| 启动链迁移 | 2 |
| 遗留归档 | 1 |
| 合计 | 约 163 个文件 |

## 风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| 大量文件移动导致 XcodeGen 配置问题 | 每批次后执行 `xcodegen generate` + 编译验证 |
| import 路径变化导致编译失败 | XcodeGen 按目录自动收集源文件，无需手动更新 import |
| git 历史断裂 | 使用 `git mv` 保留文件历史 |
| 批次间依赖导致中间态编译失败 | 严格按批次顺序执行，被依赖者先行 |
| Editor UI 迁移量大（64 个文件） | 拆分为 Bridge、NativeEditor、Common 三个子步骤 |
