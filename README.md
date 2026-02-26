# 小米笔记 macOS 客户端

一个使用 Swift 开发的原生 macOS 客户端，用于同步和管理小米笔记。

## 风险提示

本项目用于个人学习和研究。使用时请自行评估账号、数据与合规风险，并仅访问自己的数据。

## 技术栈

- Swift 6.0
- AppKit + SwiftUI
- SQLite 3
- URLSession
- XcodeGen
- 最低系统版本：macOS 15.0+

## 当前架构（2026-02）

### 顶层目录

```text
Sources/
├── App/                    # 启动、组合根、运行时编排
├── Features/               # 7 个业务域（Vertical Slice）
├── Network/                # 网络主干（NetworkModule/APIClient）
├── Shared/                 # 跨域共享（Kernel/Contracts/UICommons）
└── Window/                 # 窗口控制器与窗口状态
```

### App 分层

```text
Sources/App/
├── Bootstrap/              # AppDelegate, AppLaunchAssembler
├── Composition/            # AppCoordinatorAssembler + 各域 Assembler
├── Runtime/                # AppStateManager, StartupSequenceManager, ErrorRecoveryService
├── App.swift
└── AppCoordinator.swift
```

### Features 分域

- `Notes`: Domain/Application/Infrastructure/UI
- `Editor`: Domain/Application/Infrastructure/UI
- `Sync`: Domain/Application/Infrastructure/UI
- `Auth`: Domain/Application/Infrastructure/UI
- `Folders`: Domain/Application/Infrastructure/UI
- `Search`: Domain/Application/Infrastructure/UI
- `Audio`: Domain/Application/Infrastructure/UI

## 构建与测试

```bash
# 生成 Xcode 工程（修改 project.yml 后必须执行）
xcodegen generate

# 构建
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug

# 测试
xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac -destination 'platform=macOS,arch=arm64'
```

## 架构治理

```bash
# 报告模式
./scripts/check-architecture.sh

# 严格模式（违规返回非 0）
./scripts/check-architecture.sh --strict
```

检查规则：
- RULE-001：Domain 层禁止 import AppKit/SwiftUI
- RULE-002：禁止新增未授权 `.shared`
- RULE-003：EventBus 订阅生命周期管理
- RULE-004：非 Network 主干禁止直接 URLSession

CI 已接入 `--strict` 模式，违规阻塞合并。

## 模块工厂

启动链路：

`AppDelegate -> NetworkModule -> SyncModule -> EditorModule -> AudioModule -> AppCoordinator`

组合根已按域拆分：
- `NotesAssembler`
- `SyncAssembler`
- `AuthAssembler`
- `EditorAssembler`
- `AudioAssembler`

## `.shared` 保留清单

当前仅 9 个基础设施类保留 `.shared`：

- `LogService`
- `DatabaseService`
- `EventBus`
- `AudioPlayerService`
- `AudioRecorderService`
- `AudioDecryptService`
- `PrivateNotesPasswordManager`
- `ViewOptionsManager`
- `PerformanceService`

## 文档索引

- [AGENTS.md](./AGENTS.md)：开发与协作规范
- [docs/architecture-next.md](./docs/architecture-next.md)：顶层架构蓝图与 DoD
- [docs/adr/README.md](./docs/adr/README.md)：架构决策记录
- [docs/plans/TODO](./docs/plans/TODO)：收尾清单
