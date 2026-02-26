# MiNoteMac 开发指南

小米笔记 macOS 客户端：使用 Swift 开发的原生 macOS 应用，用于同步与管理小米笔记。

## 项目概述

- 语言：Swift 6.0
- UI：AppKit + SwiftUI
- 存储：SQLite 3
- 网络：URLSession
- 工程生成：XcodeGen
- 最低系统：macOS 15.0+

## 当前目录结构（2026-02）

```text
Sources/
├── App/
│   ├── Bootstrap/              # AppDelegate, AppLaunchAssembler
│   ├── Composition/            # AppCoordinatorAssembler + 域 Assembler + EditorModule/AudioModule
│   ├── Runtime/                # AppStateManager, StartupSequenceManager, ErrorRecoveryService
│   ├── App.swift
│   ├── AppCoordinator.swift
│   └── Menu*.swift             # MenuManager/MenuStateManager/MenuState/MenuItemTag
├── Features/
│   ├── Notes/
│   ├── Editor/
│   ├── Sync/
│   ├── Auth/
│   ├── Folders/
│   ├── Search/
│   └── Audio/
├── Network/                    # APIClient, NetworkModule, NetworkRequestManager, FileAPI, DefaultNetworkMonitor
├── Shared/
│   ├── Contracts/              # 跨域协议
│   ├── Kernel/                 # LogService/EventBus/DatabaseService/Command/ViewState 等核心设施
│   └── UICommons/              # 通用 UI（Settings/Toolbar 等）
└── Window/
    ├── Controllers/
    └── State/
```

## 构建命令

```bash
# 修改 project.yml 后必须执行
xcodegen generate

# 构建 Debug
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug

# 运行测试
xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac -destination 'platform=macOS,arch=arm64'
```

## 代码规范

### 禁止事项

- 禁止在代码、注释、控制台输出中使用 emoji
- 禁止使用 `print()`，统一使用 `LogService.shared`
- 禁止“解释做什么”的冗余注释

### 注释规范

- 只在复杂逻辑处写注释
- 注释使用中文
- 公开 API 用 `///`

### 日志规范

- 模块：`storage`、`network`、`sync`、`core`、`editor`、`app`、`viewmodel`、`window`、`audio`
- 级别：`debug`、`info`、`warning`、`error`
- 日志内容使用中文

### 命名规范

- 类型：PascalCase
- 变量/函数：camelCase
- 常量：camelCase 或 UPPER_SNAKE_CASE
- 文件名与主要类型名一致

## 架构分层

```text
AppKit 控制器层 (AppDelegate, WindowController)
        ↓
模块工厂层 (NetworkModule → SyncModule → EditorModule → AudioModule)
        ↓
协调器层 (AppCoordinator)
        ↓
业务域层 (Features/*: UI/Application/Domain/Infrastructure)
        ↓
共享内核层 (Shared/Kernel)
```

## 模块工厂与启动链

- `NetworkModule`：网络主干与 API 依赖
- `SyncModule`：同步引擎、操作队列、在线状态
- `EditorModule`：编辑器格式与渲染依赖
- `AudioModule`：音频上传/缓存/状态依赖

启动链：

`AppDelegate -> NetworkModule -> SyncModule -> EditorModule -> AudioModule -> AppCoordinator`

## `.shared` 约束

仅 9 个基础设施类允许保留 `.shared`：

- LogService
- DatabaseService
- EventBus
- AudioPlayerService
- AudioRecorderService
- AudioDecryptService
- PrivateNotesPasswordManager
- ViewOptionsManager
- PerformanceService

其余目录禁止新增 `.shared`。

## 架构治理

ADR 位于 `docs/adr/`：

- ADR-001：依赖方向规则
- ADR-002：事件治理规则
- ADR-003：网络主干规则
- ADR-004：`.shared` 使用规则

架构检查：

```bash
./scripts/check-architecture.sh
./scripts/check-architecture.sh --strict
```

规则：

- RULE-001：Domain 层 import 约束
- RULE-002：`.shared` 新增约束
- RULE-003：EventBus 生命周期约束
- RULE-004：URLSession 主干约束

CI 已启用 `--strict`。

## 数据库迁移

迁移文件：`Sources/Shared/Kernel/Store/DatabaseMigrationManager.swift`

规则：

- 版本号严格递增
- 不修改已发布迁移
- 失败自动回滚
- 启动时自动执行

## Git 规范

分支：

- `main`：发布分支（无明确指令禁止直接操作）
- `dev`：开发基线
- 功能分支：`feature/*`、`fix/*`、`refactor/*`

提交格式：

`<type>(<scope>): <subject>`

类型：`feat`、`fix`、`refactor`、`perf`、`style`、`docs`、`test`、`chore`、`revert`

## 注意事项

1. 修改 `project.yml` 后必须执行 `xcodegen generate`
2. 提交前必须保证可编译
3. 大任务拆小提交
4. 每个提交保持可编译、可运行
5. 项目不依赖外部开源库（业务实现保持原创）
