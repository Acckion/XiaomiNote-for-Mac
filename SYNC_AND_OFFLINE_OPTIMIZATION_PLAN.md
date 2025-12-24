# 同步模块和离线操作模块优化计划

## 一、现状分析

### 1.1 当前架构

#### 同步模块
- **SyncService**: 负责完整同步和增量同步
  - 完整同步：清除本地数据，从云端拉取全部
  - 增量同步：使用 syncTag 获取增量更改
  - 冲突解决：基于时间戳比较
- **同步状态管理**: 使用 LocalStorageService 存储 SyncStatus

#### 离线操作模块
- **OfflineOperationQueue**: 管理离线操作队列
  - 使用 UserDefaults 存储操作（`offline_operations`）
  - 支持的操作类型：createNote, updateNote, deleteNote, uploadImage, createFolder, renameFolder, deleteFolder
- **DatabaseService**: 也提供离线操作存储（`offline_operations` 表）
  - **问题**: 存在双重存储机制，可能导致不一致

#### 网络恢复处理
- **NetworkMonitor**: 监控网络状态，网络恢复时发送通知
- **NotesViewModel.handleNetworkRestored()**: 监听通知，调用 `processPendingOperations()`
- **processPendingOperations()**: 串行处理所有离线操作

### 1.2 存在的问题

#### 架构问题
1. **双重存储**: OfflineOperationQueue 使用 UserDefaults，DatabaseService 也有离线操作表，但实际只使用 UserDefaults
2. **职责不清**: SyncService 和 NotesViewModel 都有处理离线操作的逻辑
3. **缺少统一的状态管理**: 离线操作状态分散在多个地方

#### 功能问题
1. **无进度反馈**: 用户无法看到离线操作的处理进度
2. **无错误重试机制**: 失败的操作会一直重试，没有退避策略
3. **串行处理**: 所有操作串行执行，速度慢
4. **无操作优先级**: 所有操作同等对待，无法优先处理重要操作
5. **无操作去重**: 同一笔记的多次更新会创建多个操作
6. **无操作合并**: 同一笔记的创建+更新可以合并

#### 用户体验问题
1. **无视觉反馈**: 用户不知道有多少待处理操作
2. **无错误提示**: 操作失败时用户不知道
3. **无手动触发**: 只能等待网络恢复自动处理
4. **无操作历史**: 无法查看已处理的操作历史

## 二、优化目标

### 2.1 架构优化
- 统一离线操作存储（使用数据库）
- 明确职责划分（SyncService 负责同步，OfflineOperationQueue 负责离线操作）
- 统一状态管理

### 2.2 功能优化
- 添加进度反馈
- 实现智能重试机制（指数退避）
- 支持并发处理（可配置并发数）
- 实现操作优先级
- 实现操作去重和合并
- 添加操作优先级队列

### 2.3 用户体验优化
- 添加离线操作状态显示（工具栏/状态栏）
- 添加进度显示
- 添加错误提示和重试按钮
- 支持手动触发处理
- 添加操作历史查看

## 三、详细优化方案

### 3.1 统一离线操作存储

#### 方案
- **移除**: OfflineOperationQueue 中的 UserDefaults 存储
- **统一使用**: DatabaseService 的 `offline_operations` 表
- **迁移**: 如果 UserDefaults 中有旧数据，启动时迁移到数据库

#### 实现步骤
1. 修改 `OfflineOperationQueue`，使用 `DatabaseService` 而不是 UserDefaults
2. 添加数据迁移逻辑（从 UserDefaults 迁移到数据库）
3. 移除 UserDefaults 相关代码
4. 测试迁移逻辑

### 3.2 重构离线操作处理架构

#### 方案
- **OfflineOperationQueue**: 负责操作的存储、查询、去重、合并
- **OfflineOperationProcessor**: 新建类，负责操作的执行、重试、错误处理
- **NotesViewModel**: 只负责触发处理和更新 UI

#### 类设计

```swift
/// 离线操作处理器
class OfflineOperationProcessor {
    // 处理配置
    var maxConcurrentOperations: Int = 3
    var maxRetryCount: Int = 3
    var retryDelay: TimeInterval = 5.0
    
    // 处理状态
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentOperation: OfflineOperation?
    @Published var processedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var failedOperations: [OfflineOperation] = []
    
    // 处理操作
    func processOperations() async
    func retryFailedOperations() async
    func cancelProcessing()
}
```

### 3.3 实现操作去重和合并

#### 去重逻辑
- 同一笔记的多个 `updateNote` 操作：只保留最新的
- 同一笔记的 `createNote` + `updateNote`：合并为 `createNote`（使用最新内容）
- 同一笔记的 `createNote` + `deleteNote`：删除两个操作
- 同一笔记的 `updateNote` + `deleteNote`：只保留 `deleteNote`

#### 合并逻辑
- 在添加操作时检查是否有可合并的操作
- 在开始处理前再次检查并合并

### 3.4 实现智能重试机制

#### 重试策略
- **指数退避**: 第1次重试延迟5秒，第2次10秒，第3次20秒
- **最大重试次数**: 3次
- **失败后**: 标记为失败，用户可手动重试
- **永久失败**: 某些错误（如笔记不存在）不重试

#### 错误分类
- **可重试错误**: 网络错误、服务器错误（5xx）
- **不可重试错误**: 认证错误、笔记不存在、权限错误
- **需要用户操作**: Cookie 过期

### 3.5 添加进度和状态反馈

#### UI 组件
1. **工具栏状态指示器**: 显示待处理操作数量
2. **进度弹窗**: 处理时显示进度
3. **错误提示**: 失败时显示错误信息
4. **操作历史**: 查看已处理的操作

#### 状态指示器设计
```swift
// 在工具栏显示
if pendingOperationsCount > 0 {
    HStack {
        Image(systemName: "arrow.up.circle")
        Text("\(pendingOperationsCount) 待同步")
    }
    .foregroundColor(.orange)
}
```

### 3.6 支持并发处理

#### 方案
- 使用 `TaskGroup` 并发处理多个操作
- 可配置最大并发数（默认3）
- 按优先级排序（删除 > 更新 > 创建）

#### 优先级规则
1. **高优先级**: deleteNote, deleteFolder
2. **中优先级**: updateNote, renameFolder
3. **低优先级**: createNote, createFolder, uploadImage

### 3.7 优化同步流程

#### 增量同步优化
- 处理离线操作队列中的操作
- 避免重复处理（如果离线操作已处理，同步时跳过）
- 更好的冲突解决策略

#### 完整同步优化
- 同步前先处理离线操作队列
- 避免数据丢失

## 四、实施计划

### 阶段一：基础重构（1-2天）
1. ✅ 统一离线操作存储（迁移到数据库）
2. ✅ 重构 OfflineOperationQueue
3. ✅ 创建 OfflineOperationProcessor
4. ✅ 实现操作去重和合并

### 阶段二：功能增强（2-3天）
5. ✅ 实现智能重试机制
6. ✅ 实现并发处理
7. ✅ 添加操作优先级
8. ✅ 优化错误处理

### 阶段三：用户体验（1-2天）
9. ✅ 添加进度反馈 UI
10. ✅ 添加状态指示器
11. ✅ 添加错误提示
12. ✅ 添加手动触发功能

### 阶段四：测试和优化（1天）
13. ✅ 全面测试
14. ✅ 性能优化
15. ✅ 文档更新

## 五、技术细节

### 5.1 数据库表结构优化

```sql
CREATE TABLE IF NOT EXISTS offline_operations (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    note_id TEXT NOT NULL,
    data BLOB NOT NULL,
    timestamp REAL NOT NULL,
    priority INTEGER DEFAULT 0,  -- 新增：优先级
    retry_count INTEGER DEFAULT 0,  -- 新增：重试次数
    last_error TEXT,  -- 新增：最后错误信息
    status TEXT DEFAULT 'pending'  -- 新增：状态（pending, processing, failed, completed）
);
```

### 5.2 操作去重算法

```swift
func deduplicateOperations(_ operations: [OfflineOperation]) -> [OfflineOperation] {
    var result: [String: OfflineOperation] = [:]
    
    // 按时间戳排序
    let sorted = operations.sorted { $0.timestamp < $1.timestamp }
    
    for op in sorted {
        let key = op.noteId
        
        switch op.type {
        case .createNote:
            // 如果已有创建或更新，合并
            if let existing = result[key] {
                if existing.type == .updateNote {
                    // 合并为创建操作
                    result[key] = op
                }
            } else {
                result[key] = op
            }
            
        case .updateNote:
            // 如果已有创建，合并到创建中
            if let existing = result[key], existing.type == .createNote {
                // 更新创建操作的数据
                result[key] = mergeOperationData(existing, op)
            } else {
                // 如果已有更新，只保留最新的
                if let existing = result[key], existing.type == .updateNote {
                    if op.timestamp > existing.timestamp {
                        result[key] = op
                    }
                } else {
                    result[key] = op
                }
            }
            
        case .deleteNote:
            // 删除操作会清除所有之前的操作
            result[key] = op
            
        default:
            result[key] = op
        }
    }
    
    return Array(result.values)
}
```

### 5.3 并发处理实现

```swift
func processOperations() async {
    let operations = await queue.getPendingOperations()
    let deduplicated = deduplicateOperations(operations)
    let sorted = sortByPriority(deduplicated)
    
    totalCount = sorted.count
    processedCount = 0
    isProcessing = true
    
    await withTaskGroup(of: Void.self) { group in
        var activeTasks = 0
        var index = 0
        
        while index < sorted.count || activeTasks > 0 {
            // 启动新任务
            while activeTasks < maxConcurrentOperations && index < sorted.count {
                let operation = sorted[index]
                index += 1
                activeTasks += 1
                
                group.addTask {
                    await self.processOperation(operation)
                    activeTasks -= 1
                }
            }
            
            // 等待一个任务完成
            await group.next()
        }
    }
    
    isProcessing = false
}
```

## 六、风险评估

### 6.1 数据迁移风险
- **风险**: 迁移过程中数据丢失
- **缓解**: 先备份 UserDefaults 数据，迁移失败时回滚

### 6.2 并发处理风险
- **风险**: 并发处理可能导致竞态条件
- **缓解**: 使用数据库事务，操作前加锁

### 6.3 性能风险
- **风险**: 大量操作时性能下降
- **缓解**: 限制并发数，分批处理

## 七、测试计划

### 7.1 单元测试
- 操作去重逻辑
- 操作合并逻辑
- 重试机制
- 优先级排序

### 7.2 集成测试
- 网络断开时的操作
- 网络恢复时的处理
- 同步过程中的离线操作

### 7.3 用户体验测试
- 大量操作时的性能
- UI 响应性
- 错误提示的清晰度

## 八、后续优化方向

1. **操作压缩**: 进一步优化操作存储
2. **增量上传**: 只上传变更部分
3. **冲突解决 UI**: 让用户选择解决冲突
4. **操作回滚**: 支持撤销已执行的操作
5. **统计分析**: 统计同步成功率、平均处理时间等

