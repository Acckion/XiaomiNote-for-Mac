# Cookie 自动刷新重构设计

## 问题描述

当 Cookie 失效时，应用不会自动通过 PassToken 刷新 Cookie。操作队列中的请求静默失败，控制台可见错误但无自动恢复。

## 根因分析

1. `MiNoteService.onCookieExpired` 回调从未被赋值，401 触发后调用是空操作
2. `OperationProcessor` 将 `authExpired` 标记为 `requiresUserAction`，直接放弃重试
3. `cookieExpiredFlag` 一旦设为 true，没有自动恢复机制
4. 部分 API 方法直接使用 `URLSession.shared`，绕过了 `NetworkRequestManager`

## 设计方案：网络层拦截器 + EventBus 状态同步

### 核心机制：NetworkRequestManager 自动刷新+重试

在 `NetworkRequestManager` 中统一处理 401 错误：

```
请求 → 收到 401 → 调用 PassTokenManager.refreshServiceToken()
                    ├─ 刷新成功 → 更新 Cookie → 重试原始请求（最多 1 次）
                    └─ 刷新失败 → 抛出错误 → 降级到 UI 提示
```

关键设计点：
- 使用 PassTokenManager 的防重入机制，多个并发 401 只触发一次刷新
- 重试上限 1 次，避免死循环
- 刷新前检查是否有存储的 passToken，没有则直接抛出 notAuthenticated

### 状态同步：EventBus 通知

- 刷新成功：发布 `AuthEvent.cookieRefreshed`
- 刷新失败：发布 `AuthEvent.tokenRefreshFailed`
- `AuthState` 已有监听逻辑，无需额外修改

### 清理工作

- 移除 `MiNoteService.onCookieExpired` 回调（已被替代）
- 修复 `cookieExpiredFlag` 在刷新成功后的重置逻辑
- `OperationProcessor` 中 `authExpired` 改为可重试
- 迁移直接使用 `URLSession.shared` 的 API 方法到 `NetworkRequestManager`

## 涉及文件

| 文件 | 变更类型 |
|------|---------|
| `Sources/Network/NetworkRequestManager.swift` | 添加 401 自动刷新+重试逻辑 |
| `Sources/Network/MiNoteService.swift` | 移除 onCookieExpired，迁移 API 方法 |
| `Sources/Sync/OperationQueue/OperationProcessor.swift` | authExpired 改为可重试 |
| `Sources/State/AuthState.swift` | 确认 EventBus 监听正确 |

## 不变的部分

- PassTokenManager 三步流程（已正确实现）
- AuthState 的 EventBus 监听逻辑（已正确实现）
- 定时 Cookie 有效性检查（保留作为兜底）
- 自动刷新定时器（保留作为预防性刷新）
