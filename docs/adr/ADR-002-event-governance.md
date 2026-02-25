# ADR-002: 事件治理规则

## 状态

已采纳

## 上下文

项目中存在两套事件机制：自定义 EventBus 和系统 NotificationCenter。如果不明确各自的使用边界，会导致事件流混乱、订阅泄漏和调试困难。spec-109 已完成 NotificationCenter 到 EventBus 的迁移，需要固化边界规则。

## 决策

### EventBus 使用场景

- 跨域业务事件（同步完成、认证失效、ID 迁移等）
- 新增业务通知默认走 EventBus

### NotificationCenter 使用场景

- Apple 系统通知（如 `NSApplication.willTerminateNotification`）
- AppKit 内部桥接通知（如 `NSTextView` 相关通知）

### 生命周期管理

- EventBus 订阅必须有生命周期管理：通过 Task 取消或 Cancellable 追踪
- 禁止无生命周期管理的 `EventBus.on` 调用（fire-and-forget 订阅）

### 禁止事项

- 禁止将新增业务事件注册到 NotificationCenter
- 禁止在 EventBus 订阅中忽略返回的 Task/Cancellable

## 后果

- 正面：事件流清晰可追踪，避免订阅泄漏
- 代价：需要在每个订阅点维护 Task/Cancellable 的生命周期

## 自动化检查

- RULE-003（`scripts/check-architecture.sh`）：检测 EventBus.on 订阅的生命周期管理

## 相关 Spec

- spec-109: NotificationCenter 到 EventBus 迁移
- spec-125: 架构治理与约束自动化
