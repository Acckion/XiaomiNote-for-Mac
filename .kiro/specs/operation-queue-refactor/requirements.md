# 需求文档：操作队列重构

## 简介

本文档描述操作队列系统的重构需求。目标是将三个冗余的队列组件（SaveQueueManager、PendingUploadRegistry、OfflineOperationQueue）合并为一个统一的操作队列，同时优化上传触发时机和错误处理机制。

## 问题分析

### 当前架构的问题

1. **队列冗余**：三个组件功能高度重叠
   - `SaveQueueManager`：本地保存队列（内存）
   - `PendingUploadRegistry`：待上传追踪（SQLite）
   - `OfflineOperationQueue`：云端操作队列（SQLite）

2. **上传触发低效**：无论网络是否可用，都先加入队列再处理

3. **状态分散**：同一笔记的状态分布在多处，清理逻辑复杂

4. **错误处理不完善**：缺少错误分类和指数退避重试

## 术语表

- **UnifiedOperationQueue**: 统一操作队列，合并后的单一队列
- **NoteOperation**: 笔记操作，包含本地保存和云端同步
- **OperationProcessor**: 操作处理器，负责执行队列中的操作
- **SyncGuard**: 同步保护器，防止同步覆盖本地修改

## 需求

### 需求 1：统一操作队列

**用户故事：** 作为开发者，我希望有一个统一的操作队列管理所有笔记操作，简化代码维护。

#### 验收标准

1.1 WHEN 系统初始化，THE UnifiedOperationQueue SHALL 从数据库恢复所有待处理操作
1.2 WHEN 用户保存笔记，THE UnifiedOperationQueue SHALL 创建包含本地保存和云端上传的操作记录
1.3 WHEN 操作完成，THE UnifiedOperationQueue SHALL 更新操作状态并持久化
1.4 WHEN 查询待上传笔记，THE UnifiedOperationQueue SHALL 返回所有 cloudUpload 状态为 pending 的笔记 ID

### 需求 2：智能上传触发

**用户故事：** 作为用户，我希望我的编辑能尽快同步到云端，减少等待时间。

#### 验收标准

2.1 WHEN 本地保存完成且网络可用，THE OperationProcessor SHALL 立即尝试上传，不经过队列等待
2.2 WHEN 上传成功，THE OperationProcessor SHALL 直接更新操作状态为 completed
2.3 WHEN 上传失败（网络错误），THE OperationProcessor SHALL 将操作保留在队列中等待重试
2.4 WHEN 上传失败（认证错误），THE OperationProcessor SHALL 标记操作为 authFailed 并通知用户

### 需求 3：操作合并优化

**用户故事：** 作为用户，我希望连续编辑不会产生大量冗余的同步请求。

#### 验收标准

3.1 WHEN 添加新操作，THE UnifiedOperationQueue SHALL 检查是否存在同一笔记的待处理操作
3.2 WHEN 存在同笔记的 updateNote 操作，THE UnifiedOperationQueue SHALL 合并为最新的操作
3.3 WHEN 添加 deleteNote 操作，THE UnifiedOperationQueue SHALL 清除该笔记的所有其他待处理操作
3.4 WHEN 添加 createNote 后又 deleteNote，THE UnifiedOperationQueue SHALL 两个操作都删除

### 需求 4：同步保护集成

**用户故事：** 作为用户，我希望正在编辑或待上传的笔记不会被同步覆盖。

#### 验收标准

4.1 WHEN SyncService 检查笔记是否可同步，THE SyncGuard SHALL 查询 UnifiedOperationQueue 中是否有该笔记的待处理上传
4.2 WHEN 笔记有待处理上传，THE SyncGuard SHALL 返回 shouldSkip = true
4.3 WHEN 笔记正在编辑（activeEditingNoteId），THE SyncGuard SHALL 返回 shouldSkip = true
4.4 WHEN 笔记无待处理操作且未在编辑，THE SyncGuard SHALL 返回 shouldSkip = false

### 需求 5：错误处理与重试

**用户故事：** 作为用户，我希望上传失败后系统能智能重试，而不是无限等待。

#### 验收标准

5.1 WHEN 操作失败，THE OperationProcessor SHALL 区分可重试错误和不可重试错误
5.2 WHEN 可重试错误发生，THE OperationProcessor SHALL 使用指数退避策略重试（1s, 2s, 4s, 8s, 最大 60s）
5.3 WHEN 重试次数超过 5 次，THE OperationProcessor SHALL 标记操作为 maxRetryExceeded
5.4 WHEN 不可重试错误发生，THE OperationProcessor SHALL 立即标记操作为失败并通知用户

### 需求 6：状态可观察性

**用户故事：** 作为用户，我希望知道哪些笔记还没有同步到云端。

#### 验收标准

6.1 WHEN 查询同步状态，THE UnifiedOperationQueue SHALL 返回待上传笔记数量
6.2 WHEN 笔记有待处理上传，THE UI SHALL 显示"未同步"标记
6.3 WHEN 所有操作完成，THE UI SHALL 显示"已同步"状态

### 需求 7：数据迁移

**用户故事：** 作为用户，我希望升级后现有的待处理操作不会丢失。

#### 验收标准

7.1 WHEN 应用首次启动（重构后），THE UnifiedOperationQueue SHALL 从旧表迁移数据
7.2 WHEN 迁移 PendingUploadRegistry 数据，THE UnifiedOperationQueue SHALL 转换为 cloudUpload 操作
7.3 WHEN 迁移 OfflineOperationQueue 数据，THE UnifiedOperationQueue SHALL 保留原有操作类型和状态
7.4 WHEN 迁移完成，THE UnifiedOperationQueue SHALL 标记迁移状态防止重复迁移

### 需求 8：离线创建笔记与 ID 映射

**用户故事：** 作为用户，我希望在离线时也能创建新笔记，上线后自动同步到云端。

#### 验收标准

8.1 WHEN 用户离线创建笔记，THE System SHALL 生成临时 ID（格式：`local_<UUID>`）并立即保存到本地
8.2 WHEN 用户离线创建笔记，THE UnifiedOperationQueue SHALL 创建 `noteCreate` 操作并标记 `isLocalId = true`
8.3 WHILE 笔记使用临时 ID，THE System SHALL 允许对该笔记进行编辑、删除等所有操作
8.4 WHEN 网络恢复且 `noteCreate` 操作执行成功，THE System SHALL 获取云端下发的正式 ID
8.5 WHEN 获取到正式 ID，THE System SHALL 更新本地数据库中的笔记 ID
8.6 WHEN 获取到正式 ID，THE UnifiedOperationQueue SHALL 更新所有引用临时 ID 的待处理操作
8.7 WHEN 获取到正式 ID，THE System SHALL 更新 UI 中的笔记引用（selectedNote 等）
8.8 IF 临时 ID 笔记被删除（在上传前），THEN THE UnifiedOperationQueue SHALL 取消 `noteCreate` 操作

### 需求 9：ID 映射表管理

**用户故事：** 作为系统，我需要追踪临时 ID 和正式 ID 的映射关系，确保数据一致性。

#### 验收标准

9.1 WHEN 临时 ID 映射到正式 ID，THE IdMappingRegistry SHALL 记录映射关系
9.2 WHEN 查询笔记 ID，THE IdMappingRegistry SHALL 返回最新的有效 ID（如果有映射则返回正式 ID）
9.3 WHEN 映射完成且所有引用已更新，THE IdMappingRegistry SHALL 清理过期的映射记录
9.4 WHEN 应用重启，THE IdMappingRegistry SHALL 从数据库恢复未完成的映射关系
