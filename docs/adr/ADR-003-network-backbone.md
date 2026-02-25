# ADR-003: 网络主干规则

## 状态

已采纳

## 上下文

spec-114 建立了 NetworkModule 作为网络层唯一模块工厂，所有 API 类共享同一个 APIClient 实例。如果允许在 NetworkModule 体系外直接使用 URLSession，会绕过统一的认证管理（401 自动刷新 Cookie）、请求队列、日志记录和错误处理机制。

## 决策

### 规则

1. 所有网络请求必须通过 NetworkModule 提供的 API 类（NoteAPI、FolderAPI、FileAPI、SyncAPI、UserAPI）
2. 禁止在 `Sources/` 非 `Network/` 目录中直接使用 `URLSession`
3. 禁止引入第二套网络抽象层

### 已知豁免

- `Sources/Network/` 目录内的 `NetworkRequestManager` 使用 `URLSession.shared` 是合规的（它是网络主干的一部分）
- `Sources/Network/NetworkMonitor.swift` 使用 `NWPathMonitor` 不涉及 HTTP 请求

### 豁免机制

代码中可使用 `// arch-ignore` 注释豁免单行检查。

## 后果

- 正面：所有网络请求经过统一管道，保证认证、日志、重试策略一致
- 代价：新增网络功能必须通过 API 类封装，不能直接发起 HTTP 请求

## 自动化检查

- RULE-004（`scripts/check-architecture.sh`）：检测非 Network/ 目录的 URLSession 直接使用

## 相关 Spec

- spec-114: NetworkModule 模块工厂
- spec-125: 架构治理与约束自动化
