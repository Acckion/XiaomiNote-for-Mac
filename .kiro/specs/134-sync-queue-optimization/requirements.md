# spec-134：同步队列深度优化

## 背景

OperationProcessor 第一层拆分（spec-122）已完成，拆分为 NoteOperationHandler、FileOperationHandler、FolderOperationHandler。但 Processor 本身仍存在可观测性不足、重试参数分散、错误处理逻辑内聚度低等问题。

## 需求

### REQ-1：批处理可观测日志

`processQueue` 方法执行时，记录以下信息到 LogService：
- 首轮执行：待处理操作总数、实际执行数量、跳过数量（含跳过原因分类：未到重试时间 / 正在处理中）
- 次轮执行（如有）：同上
- 使用 `LogService.shared.info(.sync, ...)` 级别

### REQ-2：统一重试参数配置源

当前 `maxRetryCount` 在 OperationProcessor 和 UnifiedOperationQueue 中各有定义。统一为单一配置源：
- 在 OperationProcessor 或独立配置类中定义 `maxRetryCount`
- UnifiedOperationQueue 通过构造器注入或读取同一配置

### REQ-3：提取 OperationFailurePolicy

从 OperationProcessor 中提取错误分类和重试决策逻辑为独立类型 `OperationFailurePolicy`：
- 输入：操作类型 + 错误类型
- 输出：重试策略（立即重试 / 延迟重试 / 放弃）
- 减少 Processor 体积，提升错误处理逻辑的可测试性

## 验收标准

1. processQueue 执行时日志输出包含操作数量和跳过原因
2. maxRetryCount 只有一个定义源
3. OperationFailurePolicy 独立文件，有对应单元测试
4. 编译通过，同步队列回归测试（spec-132）通过
