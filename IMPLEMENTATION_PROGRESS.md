# 同步和离线操作优化 - 实施进度

## ✅ 已完成的工作

### 步骤1：分析当前双重存储机制 ✅
- [x] 分析了 OfflineOperationQueue 的 UserDefaults 实现
- [x] 分析了 DatabaseService 的数据库实现
- [x] 确认数据格式兼容性
- [x] 确定了迁移策略

### 步骤2：扩展数据库表结构 ✅
- [x] 修改 `offline_operations` 表结构，添加新字段：
  - `priority INTEGER NOT NULL DEFAULT 0` - 操作优先级
  - `retry_count INTEGER NOT NULL DEFAULT 0` - 重试次数
  - `last_error TEXT` - 最后错误信息
  - `status TEXT NOT NULL DEFAULT 'pending'` - 操作状态
- [x] 实现数据库迁移逻辑 `migrateOfflineOperationsTable()`
- [x] 添加新索引：
  - `idx_offline_operations_status` - 按状态查询
  - `idx_offline_operations_priority` - 按优先级和时间排序
- [x] 更新 `parseOfflineOperation()` 支持新字段，并兼容旧数据

### 步骤3：扩展 OfflineOperation 结构体 ✅
- [x] 添加 `OfflineOperationStatus` 枚举（pending, processing, completed, failed）
- [x] 扩展 `OfflineOperation` 结构体，添加新字段：
  - `priority: Int`
  - `retryCount: Int`
  - `lastError: String?`
  - `status: OfflineOperationStatus`
- [x] 添加 `calculatePriority(for:)` 静态方法，根据操作类型计算优先级
- [x] 更新初始化方法，新字段有默认值（向后兼容）

### 步骤4：更新数据库操作方法 ✅
- [x] 更新 `addOfflineOperation()` 支持新字段
- [x] 更新 `getAllOfflineOperations()` 按优先级和时间排序
- [x] 更新 `parseOfflineOperation()` 解析新字段并兼容旧数据

## ✅ 已完成的工作

### 步骤5：重构 OfflineOperationQueue 使用数据库 ✅
**状态**：已完成

**任务**：
- [x] 修改 `OfflineOperationQueue` 类，移除 UserDefaults
- [x] 使用 `DatabaseService` 的方法
- [x] 保持 API 接口不变
- [x] 实现数据迁移逻辑（从 UserDefaults 到数据库）
- [x] 添加 `getAllOperations()` 方法（获取所有操作）
- [x] 添加 `updateOperationStatus()` 方法（更新操作状态）
- [x] `getPendingOperations()` 现在只返回 pending 或 failed 状态的操作

## 📋 下一步计划

### 步骤6：实现数据迁移逻辑 ✅
- [x] 在 OfflineOperationQueue 初始化时检查 UserDefaults
- [x] 迁移旧数据到数据库
- [x] 迁移成功后清除 UserDefaults
- [x] 使用 UserDefaults 标记避免重复迁移

### 步骤7：创建 OfflineOperationProcessor 框架 ✅
- [x] 创建新文件 `OfflineOperationProcessor.swift`
- [x] 定义基本结构和方法框架
- [x] 添加状态属性（isProcessing, progress, currentOperation 等）
- [x] 添加配置属性（maxConcurrentOperations, maxRetryCount 等）
- [x] 实现基本的 processOperations() 方法（临时串行实现）
- [x] 添加 retryFailedOperations() 和 cancelProcessing() 方法

### 步骤8：实现操作去重和合并逻辑 ✅
- [x] 实现 `deduplicateAndMerge()` 方法
- [x] 实现合并算法：
  - createNote + updateNote → createNote（使用最新内容）
  - createNote + deleteNote → 删除两个操作
  - updateNote + updateNote → 只保留最新的
  - updateNote + deleteNote → 只保留 deleteNote
  - deleteNote → 清除所有之前的操作
- [x] 集成到 `addOperation()` 方法
- [x] 文件夹操作的去重逻辑（类似笔记操作）

## 🔄 阶段二：功能增强

### 步骤9：实现错误分类逻辑 ✅
- [x] 实现 `isRetryableError()` 方法
- [x] 实现 `requiresUserAction()` 方法
- [x] 分类处理 MiNoteError：
  - cookieExpired, notAuthenticated → 不可重试，需要用户操作
  - networkError → 可重试
  - invalidResponse → 可重试
- [x] 分类处理 NSError：
  - 404（笔记不存在）→ 不可重试
  - 403（权限错误）→ 不可重试
  - 5xx（服务器错误）→ 可重试
  - 网络错误（超时、连接丢失等）→ 可重试

### 步骤10：实现智能重试机制（指数退避） ✅
- [x] 实现 `calculateRetryDelay()` 方法（指数退避算法）
- [x] 在 `processOperationWithRetry()` 中实现重试逻辑
- [x] 支持最大重试次数限制
- [x] 根据错误类型决定是否重试
- [x] 更新操作状态和重试次数

### 步骤11：实现并发处理（TaskGroup） ✅
- [x] 使用 `withTaskGroup` 实现并发处理
- [x] 支持可配置的最大并发数（`maxConcurrentOperations`）
- [x] 按优先级排序处理操作
- [x] 动态管理并发任务（完成一个启动一个）

### 步骤12：完善 OfflineOperationProcessor 的具体处理逻辑 ✅
- [x] 实现 `processCreateNoteOperation()` - 创建笔记
- [x] 实现 `processUpdateNoteOperation()` - 更新笔记
- [x] 实现 `processDeleteNoteOperation()` - 删除笔记
- [x] 实现 `processCreateFolderOperation()` - 创建文件夹
- [x] 实现 `processRenameFolderOperation()` - 重命名文件夹
- [x] 实现 `processDeleteFolderOperation()` - 删除文件夹
- [x] 实现辅助方法：
  - `isResponseSuccess()` - 检查响应是否成功
  - `extractErrorMessage()` - 提取错误消息
  - `extractEntry()` - 提取 entry 数据
  - `extractTag()` - 提取 tag 值

## 🔄 阶段三：用户体验

### 步骤13：工具栏状态指示器显示待处理操作数量 ✅
- [x] 在 `NotesViewModel` 中添加计算属性：
  - `pendingOperationsCount` - 待处理操作数量
  - `isProcessingOfflineOperations` - 是否正在处理
  - `offlineOperationsProgress` - 处理进度
  - `failedOperationsCount` - 失败操作数量
- [x] 在 `ContentView` 的状态指示器中显示待处理操作数量
- [x] 更新状态提示文本，包含待处理操作信息
- [x] 在状态指示器菜单中添加处理离线操作的选项

### 步骤14：进度弹窗显示处理进度 ✅
- [x] 创建 `OfflineOperationsProgressView` 视图
- [x] 显示处理进度条和状态消息
- [x] 显示当前正在处理的操作
- [x] 显示处理结果（成功/失败数量）
- [x] 显示失败操作的详细列表和错误信息
- [x] 添加取消、重试、关闭按钮
- [x] 在 `ContentView` 中集成进度视图（使用 sheet）

### 步骤15：错误提示和手动重试功能 ✅
- [x] 在进度视图中显示失败操作的错误信息
- [x] 提供重试失败操作的按钮
- [x] 在状态指示器菜单中添加重试选项
- [x] 处理完成后发送通知（如果有失败的操作）
- [x] 优化按钮布局和键盘快捷键

## 📝 技术细节

### 数据库表结构
```sql
CREATE TABLE offline_operations (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    note_id TEXT NOT NULL,
    data BLOB NOT NULL,
    timestamp REAL NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    retry_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    status TEXT NOT NULL DEFAULT 'pending'
);
```

### 优先级规则
- **高优先级 (3)**: deleteNote, deleteFolder
- **中优先级 (2)**: updateNote, renameFolder
- **低优先级 (1)**: createNote, createFolder, uploadImage

### 向后兼容
- 新字段都有默认值，现有代码无需修改即可工作
- `parseOfflineOperation()` 兼容旧数据（只有5列的情况）
- 数据库迁移自动执行，不影响现有数据

## ⚠️ 注意事项

1. **数据迁移**：迁移逻辑会在每次启动时执行，但使用 `ignoreError: true` 避免重复添加字段的错误
2. **兼容性**：所有新字段都有默认值，确保向后兼容
3. **测试**：需要在有旧数据和无旧数据的情况下测试迁移

## 🎯 当前阶段目标

完成阶段一的基础重构，为后续功能增强打好基础。

