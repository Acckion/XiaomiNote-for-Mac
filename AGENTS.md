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
├── App/                    # 应用程序入口（AppDelegate, MenuManager, AppStateManager）
├── Coordinator/            # 协调器（AppCoordinator, SyncCoordinator）
├── Core/                   # 核心基础设施
│   ├── Cache/              # 缓存工具
│   ├── Concurrency/        # 并发工具
│   ├── EventBus/           # 事件总线（跨层通信）
│   └── Pagination/         # 分页工具
├── Extensions/             # Swift 扩展
├── Model/                  # 数据模型（Note, Folder, NoteMapper 等）
├── Network/                # 网络层（APIClient, NetworkModule, NoteAPI, FolderAPI, FileAPI, SyncAPI, UserAPI）
│   ├── API/                # 领域 API 类（按功能拆分）
│   └── Implementation/     # 网络协议实现
├── Presentation/           # 展示层辅助
│   └── ViewModels/         # ViewModel（音频、认证、搜索等独立模块）
├── Service/                # 业务服务层
│   ├── Audio/              # 音频服务
│   ├── Authentication/     # 认证服务
│   ├── Cache/              # 缓存服务
│   ├── Core/               # 核心服务（StartupSequenceManager, LogService）
│   ├── Editor/             # 编辑器服务（NoteEditingCoordinator, FormatConverter）
│   ├── Image/              # 图片服务
│   └── Protocols/          # 服务协议定义
├── State/                  # 状态对象（替代 NotesViewModel）
│   ├── AuthState           # 认证状态
│   ├── FolderState         # 文件夹状态
│   ├── NoteEditorState     # 编辑器状态
│   ├── NoteListState       # 笔记列表状态
│   ├── SearchState         # 搜索状态
│   ├── SyncState           # 同步状态
│   ├── ViewOptionsState    # 视图选项状态
│   ├── ViewOptionsManager  # 视图选项管理
│   └── ViewState           # 视图状态
├── Store/                  # 数据存储层（DatabaseService, NoteStore）
├── Sync/                   # 同步引擎
│   ├── OperationQueue/     # 操作队列（UnifiedOperationQueue, OperationProcessor）
│   ├── SyncEngine          # 同步引擎核心（1 核心 + 4 extension）
│   ├── SyncModule          # 同步层模块工厂（构建同步层完整依赖图）
│   └── IdMappingRegistry   # ID 映射注册表
├── ToolbarItem/            # 工具栏组件
├── View/                   # UI 视图组件
│   ├── AppKitComponents/   # AppKit 视图控制器
│   ├── Bridge/             # SwiftUI-AppKit 桥接（NativeEditorContext, EditorEnums, EditorContentManager, EditorFormatDetector）
│   ├── NativeEditor/       # 原生富文本编辑器
│   │   └── Core/           # 核心组件（NativeEditorView, NativeEditorCoordinator, CoordinatorFormatApplier, NativeTextView）
│   ├── Shared/             # 共享组件（NoteMoveHelper 等）
│   └── SwiftUIViews/       # SwiftUI 视图
└── Window/                 # 窗口控制器
    └── Controllers/        # MainWindowController（1 核心 + 6 extension）

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

## 数据格式

- **本地存储**: SQLite 数据库
- **云端格式**: XML（小米笔记格式）
- **编辑器格式**: NSAttributedString（原生编辑器）

## 数据库迁移指南

项目使用版本化迁移机制管理数据库结构变更，迁移文件位于 `Sources/Store/DatabaseMigrationManager.swift`。

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
