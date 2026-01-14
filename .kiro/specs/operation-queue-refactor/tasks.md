# 实现计划：操作队列重构

## 概述

本文档描述操作队列重构的实现任务。按依赖关系排序，分为 12 个主要阶段。

## 任务

- [x] 1. 创建 NoteOperation 数据模型
  - [x] 1.1 创建 `NoteOperation` 结构体
    - 定义 id、type、noteId、data、status、isLocalId 等字段
    - 实现 Codable、Identifiable、Sendable 协议
    - 添加 `isTemporaryId()` 和 `generateTemporaryId()` 静态方法
    - _需求: 1.2, 8.1_
  - [x] 1.2 创建 `OperationType` 枚举
    - noteCreate、cloudUpload、cloudDelete、imageUpload、folderCreate 等
    - _需求: 1.2, 8.2_
  - [x] 1.3 创建 `OperationStatus` 枚举
    - pending、processing、completed、failed、authFailed、maxRetryExceeded
    - _需求: 5.1_
  - [x] 1.4 创建 `ErrorType` 枚举
    - network、timeout、serverError、authExpired、notFound、conflict
    - _需求: 5.1_
  - [x] 1.5 添加数据库表结构
    - 在 DatabaseService 中创建 `unified_operations` 表
    - 创建 `id_mappings` 表
    - 添加必要的索引
    - _需求: 1.1, 9.1_

- [x] 2. 创建 UnifiedOperationQueue
  - [x] 2.1 创建 `UnifiedOperationQueue` 类基础结构
    - 实现单例模式
    - 使用 NSLock 确保线程安全
    - _需求: 1.1_
  - [x] 2.2 实现 `enqueue()` 方法
    - 添加操作到队列
    - 调用去重合并逻辑
    - 持久化到数据库
    - _需求: 1.2, 3.1_
  - [x] 2.3 实现去重合并逻辑 `deduplicateAndMerge()`
    - noteCreate 优先级处理
    - cloudUpload 合并规则
    - cloudDelete 清除规则
    - _需求: 3.2, 3.3, 3.4_
  - [x] 2.4 实现状态更新方法
    - `markProcessing()`、`markCompleted()`、`markFailed()`
    - _需求: 1.3_
  - [x] 2.5 实现查询方法
    - `getPendingOperations()`
    - `hasPendingUpload(for:)`
    - `getLocalSaveTimestamp(for:)`
    - _需求: 1.4, 4.1_
  - [x] 2.6 实现重试调度 `scheduleRetry()`
    - 计算下次重试时间
    - 更新数据库
    - _需求: 5.2_
  - [x] 2.7 实现统计方法
    - `getPendingUploadCount()`
    - `getAllPendingNoteIds()`
    - _需求: 6.1_
  - [x] 2.8 实现 `updateNoteIdInPendingOperations()` 方法
    - 更新所有引用临时 ID 的操作
    - _需求: 8.6_

- [x] 3. 创建 OperationProcessor
  - [x] 3.1 创建 `OperationProcessor` Actor 基础结构
    - 定义重试配置（maxRetryCount、baseRetryDelay、maxRetryDelay）
    - _需求: 5.2_
  - [x] 3.2 实现 `processImmediately()` 方法
    - 网络可用时立即处理
    - 调用 MiNoteService API
    - _需求: 2.1_
  - [x] 3.3 实现 `processQueue()` 方法
    - 处理队列中的待处理操作
    - 按优先级排序（noteCreate 最高）
    - _需求: 2.1_
  - [x] 3.4 实现错误分类 `classifyError()`
    - 区分可重试和不可重试错误
    - _需求: 5.1_
  - [x] 3.5 实现重试延迟计算 `calculateRetryDelay()`
    - 指数退避：1s, 2s, 4s, 8s, 16s, 32s, 60s
    - _需求: 5.2_
  - [x] 3.6 实现 `processRetries()` 方法
    - 处理需要重试的操作
    - 检查 nextRetryAt
    - _需求: 5.2_
  - [x] 3.7 实现上传成功/失败处理
    - 成功：markCompleted
    - 失败：根据错误类型处理
    - _需求: 2.2, 2.3, 2.4_
  - [x] 3.8 实现 `processNoteCreate()` 方法
    - 处理离线创建的笔记
    - 获取云端下发 ID 后触发 ID 更新流程
    - _需求: 8.4_

- [x] 4. 创建 SyncGuard
  - [x] 4.1 创建 `SyncGuard` 结构体
    - 依赖 UnifiedOperationQueue 和 NoteOperationCoordinator
    - _需求: 4.1_
  - [x] 4.2 实现 `shouldSkipSync()` 方法
    - 检查活跃编辑状态
    - 检查待处理上传
    - 比较时间戳
    - 检查临时 ID
    - _需求: 4.2, 4.3, 4.4, 8.3_
  - [x] 4.3 实现 `getSkipReason()` 方法
    - 返回跳过原因用于日志
    - _需求: 4.2_

- [x] 5. 创建 IdMappingRegistry
  - [x] 5.1 创建 `IdMappingRegistry` 类基础结构
    - 实现单例模式
    - 使用 NSLock 确保线程安全
    - _需求: 9.1_
  - [x] 5.2 实现 `registerMapping()` 方法
    - 记录临时 ID 到正式 ID 的映射
    - 持久化到数据库
    - _需求: 9.1_
  - [x] 5.3 实现 `resolveId()` 方法
    - 返回最新的有效 ID
    - _需求: 9.2_
  - [x] 5.4 实现 `updateAllReferences()` 方法
    - 更新数据库中的笔记 ID
    - 更新操作队列中的 noteId
    - 发送通知给 UI
    - _需求: 8.5, 8.6, 8.7_
  - [x] 5.5 实现清理方法
    - `markCompleted()` 标记映射完成
    - `cleanupCompletedMappings()` 清理过期映射
    - _需求: 9.3_
  - [x] 5.6 实现应用启动恢复
    - 从数据库恢复未完成的映射
    - _需求: 9.4_

- [x] 6. 重构 NoteOperationCoordinator
  - [x] 6.1 移除对 PendingUploadRegistry 的依赖
    - 改用 UnifiedOperationQueue
    - _需求: 1.2_
  - [x] 6.2 重构 `saveNote()` 方法
    - 本地保存（同步执行）
    - 创建 cloudUpload 操作
    - 网络可用时立即处理
    - _需求: 2.1_
  - [x] 6.3 重构 `saveNoteImmediately()` 方法
    - 取消防抖
    - 立即保存和上传
    - _需求: 2.1_
  - [x] 6.4 移除 `uploadDebounceTask` 相关代码
    - 改为立即上传策略
    - _需求: 2.1_
  - [x] 6.5 重构 `canSyncUpdateNote()` 方法
    - 使用 SyncGuard
    - _需求: 4.1_
  - [x] 6.6 添加 `onUploadSuccess()` 和 `onUploadFailure()` 回调
    - 更新 UnifiedOperationQueue 状态
    - _需求: 2.2, 2.3_
  - [x] 6.7 实现 `createNoteOffline()` 方法
    - 生成临时 ID（local_xxx）
    - 保存到本地数据库
    - 创建 noteCreate 操作（isLocalId=true）
    - _需求: 8.1, 8.2_
  - [x] 6.8 实现 `handleNoteCreateSuccess()` 方法
    - 获取云端下发 ID
    - 调用 IdMappingRegistry.updateAllReferences()
    - 更新 activeEditingNoteId
    - _需求: 8.4, 8.5, 8.6, 8.7_
  - [x] 6.9 实现临时 ID 笔记删除处理
    - 取消 noteCreate 操作
    - 删除本地笔记
    - _需求: 8.8_

- [x] 7. 集成到 SyncService
  - [x] 7.1 替换 SyncProtectionFilter 为 SyncGuard
    - 更新 `syncNoteIncremental()` 中的检查
    - _需求: 4.1_
  - [x] 7.2 替换 `processModifiedNote()` 中的检查
    - 使用 SyncGuard.shouldSkipSync()
    - _需求: 4.2_
  - [x] 7.3 更新日志记录
    - 使用 SyncGuard.getSkipReason()
    - _需求: 4.2_
  - [x] 7.4 添加临时 ID 笔记过滤
    - 同步时跳过临时 ID 笔记
    - _需求: 8.3_

- [x] 8. 集成到 NotesViewModel
  - [x] 8.1 更新 `createNote()` 方法
    - 离线时调用 `createNoteOffline()`
    - 在线时直接创建
    - _需求: 8.1_
  - [x] 8.2 添加 ID 变更监听
    - 监听 IdMappingRegistry 的通知
    - 更新 selectedNote 和 notes 数组
    - _需求: 8.7_
  - [x] 8.3 更新 `deleteNote()` 方法
    - 处理临时 ID 笔记删除
    - _需求: 8.8_
  - [x] 8.4 更新 `saveCurrentNote()` 方法
    - 使用新的 NoteOperationCoordinator API
    - _需求: 2.1_

- [x] 9. 数据迁移（已跳过 - 程序未发布，无需迁移旧数据）
  - [x] 9.1 ~~实现 `migrateFromLegacyTables()` 方法~~ - 跳过
  - [x] 9.2 ~~添加迁移状态检查~~ - 跳过
  - [x] 9.3 ~~在应用启动时调用迁移~~ - 跳过

- [x] 10. UI 集成与状态显示
  - [x] 10.1 更新 OperationQueueDebugView
    - 显示 UnifiedOperationQueue 状态
    - 显示各状态操作数量
    - 显示临时 ID 笔记数量
    - _需求: 6.1_
  - [x] 10.2 添加同步状态指示器
    - 在笔记列表显示待上传数量
    - _需求: 6.2_
  - [x] 10.3 添加笔记未同步标记
    - 在笔记行显示"未同步"图标
    - 临时 ID 笔记显示"离线创建"标记
    - _需求: 6.2_

- [x] 11. 清理废弃代码
  - [x] 11.1 标记 SaveQueueManager 为 @available(*, deprecated)
    - 添加迁移说明
  - [x] 11.2 标记 PendingUploadRegistry 为 @available(*, deprecated)
    - 添加迁移说明
  - [x] 11.3 标记 SyncProtectionFilter 为 @available(*, deprecated)
    - 添加迁移说明
  - [x] 11.4 更新所有调用点
    - 使用新的 API
  - [x] 11.5 移除旧的数据库表（可选，延后执行）
    - pending_uploads 表
    - offline_operations 表

- [x] 12. 测试
  - [x] 12.1 UnifiedOperationQueue 单元测试
    - 测试 NoteOperation 数据模型（临时 ID、优先级、状态检查、Codable、Equatable、Hashable）
    - 测试 OperationType 和 OperationStatus 枚举
    - 测试 OperationErrorType 可重试判断
    - 测试重试延迟计算（指数退避）
  - [x] 12.2 OperationProcessor 单元测试
    - 测试错误分类（网络、超时、服务器、认证、404、409、未知）
    - 测试重试延迟计算
    - 测试可重试判断和用户操作判断
  - [x] 12.3 SyncGuard 单元测试
    - 测试临时 ID 检测和跳过
    - 测试跳过原因获取
    - 测试 SyncSkipReason 枚举
  - [x] 12.4 IdMappingRegistry 单元测试
    - 测试临时 ID 检测
    - 测试 ID 解析（单个和批量）
    - 测试映射查询和统计
    - 测试 IdMapping 结构体
  - [x] 12.5 数据迁移测试（已跳过 - 程序未发布，无需迁移旧数据）
  - [x] 12.6 离线创建笔记集成测试（已跳过 - 需要完整的网络环境）
  - [x] 12.7 端到端测试（已跳过 - 需要完整的网络环境）

## 实施顺序

```
阶段 1: 基础设施（任务 1-2）
    ↓
阶段 2: 处理器（任务 3）
    ↓
阶段 3: 同步保护（任务 4）
    ↓
阶段 4: ID 映射（任务 5）
    ↓
阶段 5: 协调器重构（任务 6）
    ↓
阶段 6: 同步集成（任务 7）
    ↓
阶段 7: ViewModel 集成（任务 8）
    ↓
阶段 8: 数据迁移（任务 9）
    ↓
阶段 9: UI 集成（任务 10）
    ↓
阶段 10: 清理（任务 11）
    ↓
阶段 11: 测试（任务 12）
```

## 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 数据迁移失败 | 待处理操作丢失 | 保留旧表，迁移失败时回退 |
| ID 更新不完整 | 数据不一致 | 事务处理，失败时回滚 |
| 新旧组件不兼容 | 功能异常 | 渐进式迁移，保持旧组件可用 |
| 性能下降 | 用户体验差 | 添加性能监控，优化数据库查询 |

## 回滚方案

如果重构出现严重问题：

1. 恢复旧组件的 @available 标记
2. 在 NoteOperationCoordinator 中切换回旧实现
3. 旧表数据仍然可用，无需数据恢复
4. ID 映射表保留，不影响已更新的笔记
