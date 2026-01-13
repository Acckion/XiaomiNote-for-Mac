# 实现计划：统一操作队列

## 概述

本文档描述了统一操作队列功能的实现任务。基于设计文档，将实现分为 6 个主要任务，按依赖关系排序。

## 任务

- [x] 1. 创建 PendingUploadRegistry
  - [x] 1.1 创建 `PendingUploadEntry` 数据模型
    - 定义 noteId、localSaveTimestamp、registeredAt 字段
    - _需求: 1.1, 6.1_
  - [x] 1.2 创建 `PendingUploadRegistry` 类
    - 实现单例模式
    - 使用 NSLock 确保线程安全
    - _需求: 1.1, 1.2_
  - [x] 1.3 实现注册/注销方法
    - `register(noteId:timestamp:)` 注册待上传笔记
    - `unregister(noteId:)` 注销待上传笔记
    - _需求: 1.1, 1.2_
  - [x] 1.4 实现查询方法
    - `isRegistered(_:)` 检查笔记是否在列表中
    - `getLocalSaveTimestamp(_:)` 获取本地保存时间戳
    - `getAllPendingNoteIds()` 获取所有待上传笔记 ID
    - _需求: 2.1, 2.2_
  - [x] 1.5 实现数据库持久化
    - 在 DatabaseService 中添加 `pending_uploads` 表
    - 实现 `savePendingUpload`、`deletePendingUpload`、`getAllPendingUploads` 方法
    - _需求: 6.1, 6.2_
  - [x] 1.6 实现应用启动时恢复
    - 在初始化时从数据库恢复状态
    - _需求: 1.4, 6.2_
  - [x] 1.7 编写单元测试
    - 测试注册/注销操作
    - 测试查询功能
    - 测试线程安全
    - _需求: 1.1, 1.2, 1.3, 1.4_

- [x] 2. 创建 NoteOperationCoordinator Actor
  - [x] 2.1 创建 `NoteOperationCoordinator` Actor 基础结构
    - 实现单例模式
    - 定义依赖（PendingUploadRegistry、DatabaseService 等）
    - _需求: 1.1, 3.1_
  - [x] 2.2 实现 `saveNote()` 方法
    - 本地保存后注册到 PendingUploadRegistry
    - _需求: 1.1, 4.1_
  - [x] 2.3 实现 `saveNoteImmediately()` 方法
    - 用于切换笔记时立即保存
    - _需求: 3.3_
  - [x] 2.4 实现活跃编辑笔记管理
    - `setActiveEditingNote(_:)` 设置活跃编辑笔记
    - `isNoteActivelyEditing(_:)` 检查笔记是否正在编辑
    - _需求: 3.1, 3.2, 3.3_
  - [x] 2.5 实现上传防抖机制
    - 1 秒延迟，合并连续保存
    - _需求: 4.2, 4.3_
  - [x] 2.6 实现 `canSyncUpdateNote()` 同步保护检查
    - 检查笔记是否可以被同步更新
    - _需求: 2.1, 2.2, 2.3_
  - [x] 2.7 实现 `resolveConflict()` 冲突解决逻辑
    - 比较时间戳，决定保留本地或使用云端
    - _需求: 5.1, 5.2, 5.3, 5.4_
  - [x]* 2.8 编写单元测试
    - 测试保存流程
    - 测试活跃编辑状态管理
    - 测试冲突解决逻辑
    - _需求: 1.1, 3.1, 5.1_

- [x] 3. 创建 SyncProtectionFilter
  - [x] 3.1 创建 `SyncProtectionFilter` 结构体
    - 定义依赖（NoteOperationCoordinator、PendingUploadRegistry）
    - _需求: 2.1_
  - [x] 3.2 实现 `shouldSkipSync()` 方法
    - 检查笔记是否应该被同步跳过
    - _需求: 2.1, 2.2, 2.3, 2.4_
  - [x] 3.3 集成活跃编辑检查
    - 正在编辑的笔记跳过同步
    - _需求: 3.2_
  - [x] 3.4 集成待上传检查
    - 待上传的笔记跳过同步
    - _需求: 2.2_
  - [x] 3.5 实现时间戳比较逻辑
    - 本地较新时跳过
    - _需求: 2.3, 5.1_
  - [x]* 3.6 编写单元测试
    - 测试跳过条件判断
    - 测试边界情况处理
    - _需求: 2.1, 2.2, 2.3, 2.4_

- [x] 4. 集成到 SyncService
  - [x] 4.1 在 `syncNoteIncremental()` 中集成 SyncProtectionFilter
    - 同步前检查是否应该跳过
    - _需求: 2.1, 2.2_
  - [x] 4.2 在 `processModifiedNote()` 中集成 SyncProtectionFilter
    - 处理修改笔记前检查
    - _需求: 2.1, 2.2_
  - [x] 4.3 在 `loadLocalDataAfterSync()` 中检查活跃编辑状态
    - 防止覆盖正在编辑的笔记
    - _需求: 3.2, 3.4_
  - [x] 4.4 添加日志记录
    - 标记被跳过的笔记
    - _需求: 2.2_
  - [ ]* 4.5 编写集成测试
    - 验证同步保护
    - _需求: 2.1, 2.2, 2.3, 2.4_

- [x] 5. 集成到 NotesViewModel
  - [x] 5.1 在 `saveCurrentNote()` 中使用 NoteOperationCoordinator
    - 替换现有保存逻辑
    - _需求: 1.1, 4.1_
  - [x] 5.2 在 `selectNote()` 中设置活跃编辑笔记
    - 切换笔记时更新活跃编辑状态
    - _需求: 3.1, 3.3_
  - [x] 5.3 在笔记切换时调用 `saveNoteImmediately()`
    - 确保切换前保存
    - _需求: 3.3_
  - [x] 5.4 在 `hasUnsavedChanges` 检查中集成协调器状态
    - 同步未保存状态
    - _需求: 3.4_
  - [x] 5.5 移除或重构现有的 SaveQueueManager 调用
    - 统一使用 NoteOperationCoordinator
    - _需求: 4.1_
  - [ ]* 5.6 编写集成测试
    - 验证保存流程
    - _需求: 1.1, 3.1, 4.1_

- [x] 6. Checkpoint - 确保所有测试通过
  - 所有 40 个单元测试通过
  - 构建成功

- [ ]* 7. 属性测试与端到端测试
  - [ ]* 7.1 Property 1 测试：待上传注册一致性
    - **Property 1: 待上传注册一致性**
    - **Validates: Requirements 1.1, 1.2, 1.3, 6.1**
  - [ ]* 7.2 Property 2 测试：同步保护有效性
    - **Property 2: 同步保护有效性**
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 3.2**
  - [ ]* 7.3 Property 3 测试：活跃编辑状态管理
    - **Property 3: 活跃编辑状态管理**
    - **Validates: Requirements 3.1, 3.3, 3.4**
  - [ ]* 7.4 Property 5 测试：冲突解决正确性
    - **Property 5: 冲突解决正确性**
    - **Validates: Requirements 5.1, 5.2, 5.3, 5.4**
  - [ ]* 7.5 Property 6 测试：状态持久化 Round-Trip
    - **Property 6: 状态持久化 Round-Trip**
    - **Validates: Requirements 1.4, 6.1, 6.2, 6.3**
  - [ ]* 7.6 端到端测试：保存-同步竞态场景
    - 模拟用户编辑 → 保存 → 定时同步场景
    - _需求: 1.1, 2.1, 2.2_
  - [ ]* 7.7 端到端测试：网络恢复后上传场景
    - 模拟离线编辑 → 网络恢复 → 上传场景
    - _需求: 1.3, 6.3_
  - [ ]* 7.8 端到端测试：应用重启后恢复场景
    - 模拟应用重启后 PendingUploadRegistry 恢复
    - _需求: 1.4, 6.2_

## 备注

- 任务标记 `*` 的为可选任务（测试相关）
- 每个任务引用具体的需求编号以确保可追溯性
- Checkpoint 任务用于验证阶段性成果
