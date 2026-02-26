# MiNoteMac 开发指南

小米笔记 macOS 客户端：一个使用 Swift 开发的原生 macOS 应用，用于同步和管理小米笔记。

## 项目概述

- **语言**: Swift 6.0
- **UI 框架**: AppKit + SwiftUI 混合架构
- **数据存储**: SQLite 3
- **网络请求**: URLSession
- **项目生成**: XcodeGen
- **最低系统要求**: macOS 15.0+

## 项目结构

```
Sources/
├── App/                    # 应用程序入口
│   ├── Bootstrap/          # 启动相关（AppDelegate, AppLaunchAssembler）
│   ├── Composition/        # 组合根 + 模块工厂（AppCoordinatorAssembler, NotesAssembler, SyncAssembler, AuthAssembler, EditorAssembler, AudioAssembler, EditorModule, AudioModule）
│   ├── Runtime/            # 运行时管理（AppStateManager, StartupSequenceManager, ErrorRecoveryService）
│   ├── App.swift           # SwiftUI 入口
│   └── Menu*/              # 菜单相关（MenuManager, MenuStateManager, MenuState, MenuItemTag）
├── Coordinator/            # 协调器（AppCoordinator）
├── Features/               # 按域组织的功能模块（7 个业务域）
│   ├── Notes/              # 笔记域（Vertical Slice）
│   │   ├── Domain/         # 领域模型（Note, NoteMapper, DeletedNote, NoteSortOrder, NoteImageAttachment, NoteHistoryVersion, PendingUploadEntry, TitleExtractionResult）
│   │   ├── Infrastructure/ # 基础设施（NoteStore, NotePreviewService, NoteOperationError, NoteAPI）
│   │   ├── Application/    # 应用层状态（NoteListState, NoteEditorState）
│   │   └── UI/             # 视图层（NotesListView, NoteDetailView, ContentAreaView, SidebarView, GalleryView, FloatingInfoBar, TrashView 等 22 个文件）
│   ├── Editor/             # 编辑器域（Vertical Slice）
│   │   ├── Domain/         # 领域模型（EditorConfiguration, TitleIntegrationError）
│   │   ├── Infrastructure/ # 基础设施（FormatConverter/：XML 解析、AST、双向转换等 18 个文件）
│   │   ├── Application/    # 应用层（NoteEditingCoordinator）
│   │   └── UI/             # 视图层
│   │       ├── Bridge/     # SwiftUI-AppKit 桥接（NativeEditorContext, EditorEnums, FormatStateManager 等 16 个文件）
│   │       └── NativeEditor/ # 原生富文本编辑器（Core, Format, Attachment, Manager, Model, Performance 等 40+ 个文件）
│   ├── Sync/               # 同步域（Vertical Slice）
│   │   ├── Domain/         # 领域模型（NoteOperation, OperationData, FileUploadOperationData, IdMapping, SyncGuard）
│   │   ├── Infrastructure/ # 基础设施
│   │   │   ├── Engine/     # SyncEngine（1 核心 + 4 extension）、SyncStateManager
│   │   │   ├── OperationQueue/ # OperationProcessor、OperationHandler、NoteOperationHandler、FileOperationHandler、FolderOperationHandler、UnifiedOperationQueue、OperationFailurePolicy、OperationQueueConfig
│   │   │   └── API/        # SyncAPI
│   │   ├── Application/    # SyncState、SyncCoordinator
│   │   └── UI/             # OfflineOperationsProgressView、OperationProcessorProgressView
│   ├── Auth/               # 认证域（Vertical Slice）
│   │   ├── Domain/         # 领域模型（AuthUser, UserProfile）
│   │   ├── Infrastructure/ # 基础设施（UserAPI, PassTokenManager, PrivateNotesPasswordManager）
│   │   ├── Application/    # AuthState
│   │   └── UI/             # LoginView, LoginWindowController, PrivateNotesPasswordInputDialogView, PrivateNotesVerificationView
│   ├── Folders/            # 文件夹域（Vertical Slice）
│   │   ├── Domain/         # 领域模型（Folder）
│   │   ├── Infrastructure/ # 基础设施（FolderAPI）
│   │   ├── Application/    # FolderState
│   │   └── UI/             # 预留
│   ├── Search/             # 搜索域（Vertical Slice）
│   │   ├── Domain/         # 预留
│   │   ├── Infrastructure/ # 预留
│   │   ├── Application/    # SearchState
│   │   └── UI/             # SearchFilterMenuContent
│   └── Audio/              # 音频域（Vertical Slice）
│       ├── Domain/         # 预留
│       ├── Infrastructure/ # AudioCacheService, AudioConverterService, AudioUploadService, AudioPlayerService, AudioRecorderService, AudioDecryptService, DefaultAudioService
│       ├── Application/    # AudioPanelStateManager, AudioPanelViewModel
│       └── UI/             # AudioPanelView, AudioPlayerView, AudioRecorderUploadView, AudioRecorderView
├── Network/                # 网络层（APIClient, NetworkModule, NetworkRequestManager, FileAPI 等）
├── Shared/                 # 跨域共享（三层结构）
│   ├── Contracts/          # 跨域协议（AudioServiceProtocol, CacheServiceProtocol, NetworkMonitorProtocol, NoteStorageProtocol）
│   ├── Kernel/             # 核心基础设施
│   │   ├── EventBus/       # 事件总线（EventBus, AppEvent, NoteUpdateEvent）
│   │   ├── Extensions/     # Swift 扩展（NSColor+Hex, NSWindow+MiNote, Notification+FormatState, Notification+MenuState）
│   │   ├── Store/          # 数据存储（DatabaseService + extensions, DatabaseMigrationManager, LocalStorageService, MemoryCacheManager）
│   │   │   ├── Cache/          # 缓存（DefaultCacheService）
│   │   ├── Command/        # 命令模式（AppCommand, NoteCommands, SyncCommands, FormatCommands, FileCommands, WindowCommands, ViewCommands, UtilityCommands, ImportContentConverter）
│   │   └── *.swift         # LogService, PerformanceService, PreviewHelper, Pageable, ViewOptionsManager, ViewOptionsState, ViewState
│   └── UICommons/          # 共享 UI 组件
│       ├── Settings/       # 设置视图（SettingsView, DebugSettingsView, EditorSettingsView 等 6 个文件）
│       └── Toolbar/        # 工具栏（MainWindowToolbarDelegate, ToolbarItemFactory, ToolbarItemProtocol, ToolbarVisibilityManager）
├── Window/                 # 窗口控制器
│   ├── Controllers/        # MainWindowController（1 核心 + 6 extension）、SettingsWindowController、DebugWindowController 等
│   └── State/              # WindowState, WindowStateManager, MainWindowState 等
├── Legacy/                 # 历史遗留代码过渡目录（DefaultNetworkMonitor.swift）

Tests/                      # 测试代码
References/                 # 参考项目（不参与编译）
```

## 构建命令

```bash
# 生成 Xcode 项目（修改 project.yml 后必须执行）
xcodegen generate

# 构建 Debug 版本
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug
```

## 代码规范

### 禁止事项

- 禁止在代码、注释、控制台输出中使用 emoji
- 禁止添加过多解释性注释，代码应当自解释

### 注释规范

- 只在复杂逻辑或非显而易见的实现处添加注释
- 注释使用中文
- 避免注释描述"做什么"、"为什么"
- 公开 API 使用文档注释（///）

### 日志规范

- 统一使用 `LogService.shared` 记录日志，禁止使用 `print()`
- 按模块标识记录：storage, network, sync, core, editor, app, viewmodel, window, audio
- 按级别选择：debug（调试）、info（关键操作）、warning（性能警告）、error（失败）
- 日志信息使用中文

### 命名规范

- 类型名使用 PascalCase
- 变量和函数名使用 camelCase
- 常量使用 camelCase 或 UPPER_SNAKE_CASE
- 文件名与主要类型名一致

## 架构分层

```
AppKit 控制器层 (AppDelegate, WindowController)
        ↓
模块工厂层 (NetworkModule → SyncModule → EditorModule → AudioModule)
        ↓
协调器层 (AppCoordinator → 管理 State 对象)
        ↓
SwiftUI 视图层 (View ← 读取 State 对象)
        ↓
状态层 (State 对象 → 调用 Store/Sync/Service)
        ↓
数据层 (NoteStore, DatabaseService, SyncEngine)
        ↓
数据模型层 (Model)
```

### 模块工厂

项目使用 4 个模块工厂集中构建依赖图，消除 `.shared` 单例耦合：

- **NetworkModule**（`Sources/Network/`）：构建网络层（APIClient, NetworkRequestManager, NoteAPI, FolderAPI, FileAPI, SyncAPI, UserAPI）
- **SyncModule**（`Sources/Features/Sync/Infrastructure/`）：构建同步层（LocalStorageService, UnifiedOperationQueue, IdMappingRegistry, OperationProcessor, OnlineStateManager, SyncEngine, NoteOperationHandler, FileOperationHandler, FolderOperationHandler）
- **EditorModule**（`Sources/App/Composition/`）：构建编辑器层（FormatStateManager, FontSizeManager, UnifiedFormatManager, CustomRenderer 等 20 个类）
- **AudioModule**（`Sources/App/Composition/`）：构建音频层（AudioCacheService, AudioConverterService, AudioUploadService, AudioPanelStateManager）

启动链：AppDelegate → NetworkModule → SyncModule → EditorModule → AudioModule → AppCoordinator

仅 9 个基础设施类保留 `static let shared`：LogService, DatabaseService, EventBus, AudioPlayerService, AudioRecorderService, AudioDecryptService, PrivateNotesPasswordManager, ViewOptionsManager, PerformanceService

其中 NetworkMonitor、NetworkErrorHandler、NetworkLogger、PreviewHelper 的 `static let shared` 已在 spec129 中删除。

## 架构治理

项目通过 ADR 文档和自动化脚本维护架构约束。

### ADR 文档

位于 `docs/adr/`，记录关键架构决策：

- ADR-001：依赖方向规则（Domain 层禁止 import AppKit/SwiftUI）
- ADR-002：事件治理规则（EventBus vs NotificationCenter 使用边界）
- ADR-003：网络主干规则（所有网络请求通过 NetworkModule）
- ADR-004：.shared 使用规则（禁止新增 .shared 单例）

### 架构检查脚本

```bash
./scripts/check-architecture.sh           # 报告模式
./scripts/check-architecture.sh --strict  # 严格模式（违规时退出码 1）
```

检查规则：RULE-001（Domain 层 import）、RULE-002（.shared 新增）、RULE-003（EventBus 生命周期）、RULE-004（URLSession 直接使用）。

CI 中已集成为强制门禁（`--strict` 模式，违规阻塞 PR），详见 `.github/workflows/build.yml`。

## 数据格式

- **本地存储**: SQLite 数据库
- **云端格式**: XML（小米笔记格式）
- **编辑器格式**: NSAttributedString（原生编辑器）

## 数据库迁移指南

项目使用版本化迁移机制管理数据库结构变更，迁移文件位于 `Sources/Shared/Kernel/Store/DatabaseMigrationManager.swift`。

### 添加新迁移

在 `DatabaseMigrationManager.migrations` 数组中添加新条目：

```swift
static let migrations: [Migration] = [
    // 已有迁移...
    
    // 新增迁移
    Migration(
        version: 2,  // 版本号递增
        description: "添加笔记归档字段",
        sql: "ALTER TABLE notes ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0;"
    ),
]
```

### 迁移规则

- 版本号必须递增（1, 2, 3...），不能跳跃或修改已发布的迁移
- 每个迁移是原子操作，失败会自动回滚
- SQL 语句建议使用 `IF NOT EXISTS` / `IF EXISTS` 增强健壮性
- 迁移在应用启动时自动执行


## Git 分支规范

- `main`：主分支，仅用于发布。未得到用户明确指令时，禁止直接操作
- `dev`：开发分支，所有功能分支的基准和合并目标
- `feature/{编号}-{描述}`、`fix/{编号}-{描述}`、`refactor/{编号}-{描述}`：功能分支

工作流：从 `dev` 创建功能分支 → 在功能分支上开发 → 等待用户指令合并回 `dev`（`--no-ff`）→ 删除功能分支

## Git 提交规范

```
<type>(<scope>): <subject>
```

类型：feat, fix, refactor, perf, style, docs, test, chore, revert

示例：
- `feat(editor): 添加原生富文本编辑器支持`
- `fix(sync): 修复离线操作队列重复执行问题`
- `docs: 更新技术文档`

## 注意事项

1. 修改 `project.yml` 后必须执行 `xcodegen generate`
2. 提交前确保代码可以编译通过
3. 大型任务拆分为多个小提交
4. 每个提交应该是可编译、可运行的状态
5. 本项目不依赖外部开源库，所有代码均为原创实现
