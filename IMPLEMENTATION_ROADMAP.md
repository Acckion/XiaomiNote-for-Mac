# 同步和离线操作优化 - 实施路线图

## 实施策略

### 原则
1. **渐进式重构**：每个步骤独立可测试，不破坏现有功能
2. **向后兼容**：确保旧数据可以迁移
3. **充分测试**：每个步骤完成后进行测试

## 阶段一：基础重构（预计2-3天）

### 步骤1：分析当前双重存储机制 ✅
**目标**：理解当前实现，确定迁移策略

**任务**：
- [x] 分析 OfflineOperationQueue 的 UserDefaults 实现
- [x] 分析 DatabaseService 的数据库实现
- [x] 确认数据格式兼容性
- [x] 确定迁移时机和策略

**输出**：迁移策略文档

---

### 步骤2：扩展数据库表结构
**目标**：为离线操作表添加新字段（优先级、重试次数、状态等）

**任务**：
- [ ] 修改 `offline_operations` 表结构，添加字段：
  - `priority INTEGER DEFAULT 0`
  - `retry_count INTEGER DEFAULT 0`
  - `last_error TEXT`
  - `status TEXT DEFAULT 'pending'`
- [ ] 实现数据库迁移逻辑
- [ ] 测试表结构更新

**风险**：需要处理已有数据，确保迁移安全

---

### 步骤3：重构 OfflineOperationQueue 使用数据库
**目标**：移除 UserDefaults，统一使用 DatabaseService

**任务**：
- [ ] 修改 `OfflineOperationQueue` 类：
  - 移除 UserDefaults 相关代码
  - 使用 `DatabaseService.addOfflineOperation()`
  - 使用 `DatabaseService.getAllOfflineOperations()`
  - 使用 `DatabaseService.deleteOfflineOperation()`
- [ ] 保持 API 接口不变（向后兼容）
- [ ] 更新所有调用点

**测试**：
- [ ] 添加操作
- [ ] 获取操作
- [ ] 删除操作
- [ ] 清空操作

---

### 步骤4：实现数据迁移逻辑
**目标**：将 UserDefaults 中的旧数据迁移到数据库

**任务**：
- [ ] 在应用启动时检查 UserDefaults 中是否有 `offline_operations`
- [ ] 如果有，读取并迁移到数据库
- [ ] 迁移成功后清除 UserDefaults 数据
- [ ] 添加迁移日志和错误处理

**测试**：
- [ ] 测试有旧数据时的迁移
- [ ] 测试无旧数据时的启动
- [ ] 测试迁移失败时的回滚

---

### 步骤5：创建 OfflineOperationProcessor 框架
**目标**：创建新的处理器类，分离处理逻辑

**任务**：
- [ ] 创建 `OfflineOperationProcessor.swift`
- [ ] 定义基本结构：
  - 状态属性（isProcessing, progress, currentOperation 等）
  - 配置属性（maxConcurrentOperations, maxRetryCount 等）
  - 基本方法框架
- [ ] 暂时不实现具体逻辑，只搭建框架

**文件位置**：`Sources/MiNoteLibrary/Service/OfflineOperationProcessor.swift`

---

### 步骤6：实现操作去重和合并逻辑
**目标**：优化操作队列，减少冗余操作

**任务**：
- [ ] 实现 `deduplicateOperations()` 方法
- [ ] 实现 `mergeOperations()` 方法
- [ ] 在添加操作时调用去重逻辑
- [ ] 在开始处理前再次去重

**测试用例**：
- [ ] 同一笔记的多个 updateNote → 只保留最新的
- [ ] createNote + updateNote → 合并为 createNote
- [ ] createNote + deleteNote → 删除两个操作
- [ ] updateNote + deleteNote → 只保留 deleteNote

---

### 步骤7：测试基础重构功能
**目标**：确保重构后功能正常

**任务**：
- [ ] 单元测试：OfflineOperationQueue 的所有方法
- [ ] 集成测试：添加、获取、删除操作
- [ ] 迁移测试：从 UserDefaults 迁移到数据库
- [ ] 回归测试：确保现有功能不受影响

---

## 阶段二：功能增强（预计2-3天）

### 步骤8：实现智能重试机制
**目标**：添加指数退避和错误分类

### 步骤9：实现并发处理
**目标**：支持并发执行多个操作

### 步骤10：实现操作优先级
**目标**：按优先级排序处理操作

### 步骤11：优化错误处理
**目标**：分类错误，区分可重试和不可重试

---

## 阶段三：用户体验（预计1-2天）

### 步骤12：添加进度反馈 UI
**目标**：显示处理进度

### 步骤13：添加状态指示器
**目标**：工具栏显示待处理操作数量

### 步骤14：添加错误提示
**目标**：失败时显示错误信息

### 步骤15：添加手动触发功能
**目标**：用户可以手动触发处理

---

## 当前步骤：步骤1 - 分析当前双重存储机制

**状态**：✅ 已完成分析

**发现**：
1. `OfflineOperationQueue` 使用 UserDefaults 存储（键：`offline_operations`）
2. `DatabaseService` 已有完整的数据库实现，但未被使用
3. 数据格式完全兼容（都是 `OfflineOperation` 结构）
4. 迁移策略：应用启动时一次性迁移，迁移后清除 UserDefaults

**下一步**：开始步骤2 - 扩展数据库表结构

