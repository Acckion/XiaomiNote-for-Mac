# spec-136：目录结构全面对齐 — 需求

## 背景

spec-126 至 spec-128 完成了 Notes、Sync、Auth、Folders 四个核心域的 Vertical Slice 迁移。spec-135 建立了目标目录骨架（App 三层、Shared 三层、Legacy）。本 spec 负责将所有散落在旧技术层目录中的代码迁入目标结构，全面对齐 `architecture-next.md` 第 5 节。

## 需求

### REQ-1：Search 域迁移

将搜索相关代码迁入 `Features/Search/`：

- `Sources/State/SearchState.swift` → `Features/Search/Application/`
- `Sources/View/SwiftUIViews/Search/SearchFilterMenuContent.swift` → `Features/Search/UI/`
- 建立四层目录结构（Domain/Infrastructure/Application/UI）

### REQ-2：Editor 域迁移

将编辑器相关代码迁入 `Features/Editor/`：

- Domain 层：`Service/Editor/EditorConfiguration.swift`、`Service/Editor/TitleIntegrationError.swift`
- Infrastructure 层：`Service/Editor/FormatConverter/` 整个目录
- Application 层：`Service/Editor/NoteEditingCoordinator.swift`
- UI 层：`View/Bridge/` 全部文件（16 个）、`View/NativeEditor/` 全部子目录和文件（约 50 个）
- `Service/Editor/EditorModule.swift` 保留原位（模块工厂）
- 建立四层目录结构

### REQ-3：Audio 域迁移

将音频相关代码迁入 `Features/Audio/`：

- Infrastructure 层：`Service/Audio/` 中的 AudioCacheService、AudioConverterService、AudioUploadService、AudioPlayerService、AudioRecorderService、AudioDecryptService、`Implementation/DefaultAudioService.swift`
- Application 层：`Service/Audio/AudioPanelStateManager.swift`、`Presentation/ViewModels/AudioPanel/AudioPanelViewModel.swift`
- UI 层：`View/SwiftUIViews/Audio/` 全部文件（4 个）、`View/Bridge/AudioPanelHostingController.swift`
- `Service/Audio/AudioModule.swift` 保留原位（模块工厂）
- 建立四层目录结构

### REQ-4：Auth 域 UI 补全

将认证相关 UI 迁入已有的 `Features/Auth/UI/`：

- `View/SwiftUIViews/Auth/LoginView.swift`
- `View/SwiftUIViews/Auth/PrivateNotesPasswordInputDialogView.swift`
- `View/SwiftUIViews/Auth/PrivateNotesVerificationView.swift`
- `Window/Controllers/LoginWindowController.swift`

### REQ-5：Shared/Kernel 迁入

将跨域核心基础设施迁入 `Shared/Kernel/`：

- `Core/EventBus/` 全部文件（EventBus.swift、AppEvent.swift、NoteUpdateEvent.swift、Events/ 子目录）
- `Service/Core/LogService.swift`
- `Service/Core/PerformanceService.swift`
- `Core/Pagination/Pageable.swift`
- `Extensions/` 全部文件（4 个）

### REQ-6：Shared/UICommons 迁入

将跨域共享 UI 组件迁入 `Shared/UICommons/`：

- `View/Shared/OnlineStatusIndicator.swift`
- `ToolbarItem/` 全部文件（4 个）

### REQ-7：Shared/Contracts 迁入

将服务协议迁入 `Shared/Contracts/`：

- `Service/Protocols/` 全部文件（AudioServiceProtocol、CacheServiceProtocol、NetworkMonitorProtocol、NoteStorageProtocol）

### REQ-8：散落 State 文件归位

将 `Sources/State/` 中剩余文件迁入对应域或 Shared：

- `ViewOptionsManager.swift`、`ViewOptionsState.swift`、`ViewState.swift` → `Shared/Kernel/`（跨域视图状态）

### REQ-9：散落 UI 视图归位

将 `View/SwiftUIViews/` 中非域专属的通用视图迁入合适位置：

- `Settings/` 全部文件（6 个）→ `Shared/UICommons/Settings/`（设置面板跨域）
- `Common/` 中的跨域视图 → `Shared/UICommons/`
- `View/AppKitComponents/SidebarViewController.swift` → `Shared/UICommons/`

### REQ-10：Store 层归位

将数据存储层迁入 `Shared/Kernel/`（跨域基础设施）：

- `Store/DatabaseService.swift` 及其所有 extension 文件（7 个）
- `Store/DatabaseMigrationManager.swift`
- `Store/LocalStorageService.swift`
- `Store/MemoryCacheManager.swift`
- `Store/Implementation/DefaultNoteStorage.swift`
- `Service/Cache/Implementation/DefaultCacheService.swift`

### REQ-11：遗留代码归档

将无法明确归入任何域的过渡代码迁入 `Legacy/`：

- `Network/Implementation/DefaultNetworkMonitor.swift`（协议实现，待评估是否迁入 Network 主干）
- 其他在迁移过程中发现的无主文件

### REQ-12：旧目录清理

迁移完成后，以下旧目录应为空或仅保留模块工厂：

- `Sources/State/` → 删除（所有文件已迁出）
- `Sources/Presentation/` → 删除（AudioPanelViewModel 已迁出）
- `Sources/Service/Cache/` → 删除（DefaultCacheService 已迁出）
- `Sources/Service/Protocols/` → 删除（协议已迁入 Shared/Contracts）
- `Sources/Service/Core/` → 仅保留 StartupSequenceManager、ErrorRecoveryService（启动链相关，暂留）
- `Sources/Service/Editor/` → 仅保留 EditorModule.swift
- `Sources/Service/Audio/` → 仅保留 AudioModule.swift
- `Sources/View/` → 删除或仅保留空壳（所有文件已迁入 Features 或 Shared）
- `Sources/Core/EventBus/` → 删除（已迁入 Shared/Kernel）
- `Sources/Core/Pagination/` → 删除（已迁入 Shared/Kernel）
- `Sources/Extensions/` → 删除（已迁入 Shared/Kernel）
- `Sources/ToolbarItem/` → 删除（已迁入 Shared/UICommons）

### REQ-13：模块工厂位置决策

EditorModule 和 AudioModule 当前在 `Service/Editor/` 和 `Service/Audio/`。迁移完成后这两个目录仅剩模块工厂文件，选择以下方案之一：

- 方案 A：保留原位（Service/Editor/EditorModule.swift、Service/Audio/AudioModule.swift）
- 方案 B：迁入 `App/Composition/`（与 Assembler 同级，统一管理工厂）

推荐方案 B：模块工厂本质是组合根的一部分，与 Assembler 放在一起更符合职责归属。

### REQ-14：迁移约束

- 每个迁移批次独立 commit，确保每步可编译可运行
- 使用 `git mv` 保留文件历史
- 每次迁移后执行 `xcodegen generate` + 编译验证
- 更新 AGENTS.md 中的项目结构描述
- 更新 architecture-next.md 反映最终状态

## 验收标准

1. `Features/` 下 7 个域（Notes/Sync/Auth/Folders/Search/Editor/Audio）均具备四层目录结构
2. `Shared/Kernel/` 包含 EventBus、LogService、DatabaseService、PerformanceService 等跨域基础设施
3. `Shared/UICommons/` 包含共享 UI 组件和设置面板
4. `Shared/Contracts/` 包含服务协议
5. `Sources/State/`、`Sources/Presentation/`、`Sources/View/`、`Sources/ToolbarItem/`、`Sources/Extensions/` 已删除
6. 模块工厂（EditorModule、AudioModule、NetworkModule、SyncModule）统一位于 `App/Composition/`
7. 编译通过
8. AGENTS.md 和 architecture-next.md 已更新
