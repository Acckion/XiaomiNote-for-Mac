# spec-134：同步队列深度优化 — 任务清单

参考文档：
- 需求：`.kiro/specs/134-sync-queue-optimization/requirements.md`
- 设计：`.kiro/specs/134-sync-queue-optimization/design.md`

---

## 任务 1：增加批处理可观测日志

- [x] 1. 在 processQueue 中插入日志
  - [x] 1.1 在 `OperationProcessor.processQueue()` 开始处记录待处理总数、跳过数量及原因
  - [x] 1.2 在处理完成后记录成功/失败数量
  - [x] 1.3 编译验证

## 任务 2：统一重试参数配置源

- [x] 2. 创建统一配置
  - [x] 2.1 创建 `Sources/Features/Sync/Infrastructure/OperationQueue/OperationQueueConfig.swift`
  - [x] 2.2 修改 OperationProcessor 构造器，接收 OperationQueueConfig
  - [x] 2.3 修改 UnifiedOperationQueue，移除内部 maxRetryCount 定义，改用 OperationQueueConfig
  - [x] 2.4 更新 SyncModule 中的构造调用
  - [x] 2.5 编译验证

## 任务 3：提取 OperationFailurePolicy

- [ ] 3. 提取错误分类逻辑
  - [ ] 3.1 创建 `Sources/Features/Sync/Infrastructure/OperationQueue/OperationFailurePolicy.swift`
  - [ ] 3.2 从 OperationProcessor 中提取错误分类和重试决策逻辑到 OperationFailurePolicy
  - [ ] 3.3 OperationProcessor 调用 OperationFailurePolicy.decide() 替代内联逻辑
  - [ ] 3.4 编译验证

## 任务 4：测试与提交

- [ ] 4. 验证与提交
  - [ ] 4.1 为 OperationFailurePolicy 编写单元测试（网络错误重试、文件不存在放弃、超过最大重试放弃）
  - [ ] 4.2 执行 `xcodegen generate`
  - [ ] 4.3 完整编译验证
  - [ ] 4.4 运行同步队列回归测试（如 spec-132 已完成）
  - [ ] 4.5 提交所有变更
