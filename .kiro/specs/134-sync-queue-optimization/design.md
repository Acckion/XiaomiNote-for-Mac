# spec-134：同步队列深度优化 — 设计

## 技术方案

### 1. 批处理可观测日志

在 `OperationProcessor.processQueue()` 方法的关键节点插入日志：

```swift
func processQueue() async {
    let pending = await queue.pendingOperations()
    let skippedRetry = pending.filter { $0.nextRetryAt > Date() }.count
    let skippedProcessing = pending.filter { $0.isProcessing }.count
    let toProcess = pending.count - skippedRetry - skippedProcessing

    LogService.shared.info(.sync, "队列处理开始: 总计 \(pending.count), 执行 \(toProcess), 跳过(未到重试时间: \(skippedRetry), 处理中: \(skippedProcessing))")

    // ... 执行逻辑 ...

    LogService.shared.info(.sync, "队列处理完成: 成功 \(successCount), 失败 \(failCount)")
}
```

### 2. 统一重试参数

创建 `OperationQueueConfig` 结构体：

```swift
struct OperationQueueConfig: Sendable {
    let maxRetryCount: Int
    let retryBaseDelay: TimeInterval

    static let `default` = OperationQueueConfig(maxRetryCount: 3, retryBaseDelay: 5.0)
}
```

OperationProcessor 和 UnifiedOperationQueue 均通过构造器接收此配置。

### 3. OperationFailurePolicy

```swift
enum RetryDecision: Sendable {
    case retry(delay: TimeInterval)
    case abandon(reason: String)
}

struct OperationFailurePolicy: Sendable {
    func decide(operationType: String, error: Error, currentRetryCount: Int, maxRetry: Int) -> RetryDecision {
        // 网络错误 -> 延迟重试
        // 文件不存在 -> 放弃
        // 认证失败 -> 放弃
        // 超过最大重试 -> 放弃
    }
}
```

从 OperationProcessor 中提取现有的错误分类逻辑到此类型。

## 影响范围

- 修改：`Sources/Features/Sync/Infrastructure/OperationQueue/OperationProcessor.swift`
- 修改：`Sources/Features/Sync/Infrastructure/OperationQueue/UnifiedOperationQueue.swift`
- 新增：`Sources/Features/Sync/Infrastructure/OperationQueue/OperationQueueConfig.swift`
- 新增：`Sources/Features/Sync/Infrastructure/OperationQueue/OperationFailurePolicy.swift`
