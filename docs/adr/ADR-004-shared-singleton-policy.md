# ADR-004: .shared 使用规则

## 状态

已采纳

## 上下文

项目历史上大量使用 `static let shared` 单例模式，导致隐式依赖、测试困难和初始化顺序不可控。spec-114 至 spec-136 已通过模块工厂、Vertical Slice 与目录重组逐步收敛 `.shared`，当前仅保留 9 个基础设施类。需要明确规则防止新增单例。

## 决策

### 规则

1. 非 Composition 目录（`Sources/App/Composition/`）禁止新增 `static let shared` 或 `static var shared`
2. 新增 `.shared` 需要在 PR 中说明理由并更新本 ADR 的允许列表
3. 已标记 `@available(*, deprecated)` 的 `.shared` 不计入允许列表，待后续 spec 统一清理

### 允许保留 .shared 的类清单

| 类名 | 文件路径 | 理由 |
|------|---------|------|
| LogService | Sources/Shared/Kernel/LogService.swift | 全局日志，启动最早期即需使用 |
| DatabaseService | Sources/Shared/Kernel/Store/DatabaseService.swift | 数据库单连接，全局唯一 |
| EventBus | Sources/Shared/Kernel/EventBus/EventBus.swift | 事件总线，跨层通信基础设施 |
| AudioPlayerService | Sources/Features/Audio/Infrastructure/AudioPlayerService.swift | 音频播放全局状态 |
| AudioRecorderService | Sources/Features/Audio/Infrastructure/AudioRecorderService.swift | 音频录制全局状态 |
| AudioDecryptService | Sources/Features/Audio/Infrastructure/AudioDecryptService.swift | 音频解密工具 |
| PrivateNotesPasswordManager | Sources/Features/Auth/Infrastructure/PrivateNotesPasswordManager.swift | 私密笔记密码管理 |
| ViewOptionsManager | Sources/Shared/Kernel/ViewOptionsManager.swift | 视图选项全局状态 |
| PerformanceService | Sources/Shared/Kernel/PerformanceService.swift | 性能监控 |

### 已退出的 .shared（已完成）

| 类名 | 文件路径 | 迁入目标 | 相关 Spec |
|------|---------|---------|-----------|
| NetworkMonitor | Sources/Network/NetworkMonitor.swift | NetworkModule 注入 | spec-129 |
| NetworkErrorHandler | Sources/Network/NetworkErrorHandler.swift | NetworkModule 注入 | spec-129 |
| NetworkLogger | Sources/Network/NetworkLogger.swift | NetworkModule 注入 | spec-129 |
| PreviewHelper | Sources/View/SwiftUIViews/Common/PreviewHelper.swift | 零调用方，已删除 | spec-129 |

### 豁免机制

代码中可使用 `// arch-ignore` 注释豁免单行检查。

## 后果

- 正面：依赖关系显式化，可测试性提升，初始化顺序可控
- 代价：新增基础设施类需要通过模块工厂注入，增加构造器参数

## 自动化检查

- RULE-002（`scripts/check-architecture.sh`）：扫描非允许列表的 `static let/var shared` 声明

## 相关 Spec

- spec-114: NetworkModule 模块工厂
- spec-116: SyncModule 模块工厂
- spec-117: EditorModule 模块工厂
- spec-118: 剩余单例清理
- spec-125: 架构治理与约束自动化
- spec-129: 第一级 .shared 退出
