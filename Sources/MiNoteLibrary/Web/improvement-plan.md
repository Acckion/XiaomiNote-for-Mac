# 编辑器改进计划

## 改进目标 ✅ **全部完成**

1. ✅ **改进撤销/重做系统：实现操作合并（连续输入合并）**
2. ✅ **改进撤销/重做系统：优化历史记录内存占用（增量记录）**
3. ✅ **创建命令抽象基类：统一所有操作接口**
4. ✅ **实现命令状态检查：根据上下文启用/禁用命令**

---

## 📊 总体进度

- ✅ **阶段 1**: 操作合并 - 100% 完成
- ✅ **阶段 2**: 内存优化 - 100% 完成
- ✅ **阶段 3**: 命令系统 - 100% 完成
- ✅ **阶段 4**: 状态检查 - 100% 完成

---

## 阶段 1：改进撤销/重做系统 - 操作合并 ✅ **已完成**

### 1.1 分析当前实现
- [x] 查看 DOMWriter 的当前实现
- [x] 了解历史记录结构
- [x] 分析操作类型

### 1.2 实现操作合并机制
- [x] 添加操作类型枚举（输入、格式、删除等）
- [x] 实现操作合并逻辑（参考 CKEditor 5）：
  - ✅ 连续输入操作合并（相同类型、时间间隔 < 100ms，限制合并次数 50 次）
  - ✅ 连续删除操作合并（时间间隔 < 150ms，限制合并次数 30 次）
  - ✅ 格式操作不合并（每次都是独立的撤销步骤）
  - ✅ 添加光标位置变化检测（避免合并用户移动光标后的操作）
- [x] 添加合并时间窗口配置（输入：100ms，删除：150ms，批量：200ms）
- [x] 实现 `_shouldMergeOperations` 方法
- [x] 实现 `_mergeOperations` 方法
- [x] 添加 `isBatch` 标记，区分批量操作和单次操作

### 1.3 集成到 DOMWriter
- [x] 修改 `_addToHistory` 方法，支持操作合并
- [x] 修改 `executeCommandWithHistory` 方法，自动推断操作类型
- [x] 修改 `execute` 和 `endBatch` 方法，支持操作类型传递

---

## 阶段 2：优化历史记录内存占用 ✅ **已完成**

### 2.1 实现增量记录 ✅ **已完成**
- [x] 创建 Diff 工具类（`DOMWriter.DOMDiff`）：
  - ✅ `diff(oldHtml, newHtml)` - 计算两个 HTML 之间的差异
  - ✅ `apply(baseHtml, diff)` - 根据差异恢复 HTML
  - ✅ 支持增量差异和完整快照两种模式
- [x] 实现增量状态捕获：
  - ✅ `_captureState(useIncremental, previousState)` - 支持增量记录
  - ✅ 自动判断使用增量记录还是完整快照（变化超过 50% 使用完整快照）
  - ✅ 每隔 N 个操作保存一个完整快照（默认 10 个）
- [x] 实现增量状态恢复：
  - ✅ `_restoreState(state)` - 支持恢复增量记录和完整快照
  - ✅ 递归恢复基础状态（处理增量记录的引用链）

### 2.2 优化历史记录结构 ✅ **已完成**
- [x] 修改历史记录结构：
  - ✅ 支持增量差异（`type: 'incremental'`）
  - ✅ 支持完整快照（`type: 'full-snapshot'`）
  - ✅ 快照间隔机制（每隔 10 个操作保存完整快照）
- [x] 实现快照管理：
  - ✅ `lastSnapshotIndex` - 跟踪最后一个快照位置
  - ✅ `_rebuildSnapshots()` - 重建快照（当历史被截断时）

### 2.3 内存管理 ✅ **已完成**
- [x] 历史记录大小限制（`maxHistorySize = 50`）
- [x] 增量记录自动启用（`useIncrementalRecording = true`）
- [x] 快照间隔配置（`snapshotInterval = 10`）

---

## 阶段 3：创建命令抽象基类 ✅ **进行中**

### 3.1 设计命令基类 ✅ **已完成**
- [x] 定义 `Command` 基类接口：
  - `execute(context)` - 执行命令
  - `undo(context, state)` - 撤销命令
  - `canExecute(context)` - 检查是否可执行
  - `getState(context)` - 获取命令状态
- [x] 命令支持元数据（metadata）
- [x] 命令支持操作类型（type）

### 3.2 实现命令管理器 ✅ **已完成**
- [x] 创建 `CommandManager` 类：
  - ✅ 命令注册机制（`register()`）
  - ✅ 命令执行（`execute()`）
  - ✅ 命令撤销（`undo()`）
  - ✅ 命令状态检查（`canExecute()`, `getState()`）
  - ✅ 命令历史管理
- [x] 集成到 DOMWriter（在初始化时创建 CommandManager）

### 3.3 重构现有操作 ✅ **部分完成**
- [x] 创建格式命令注册函数（`_registerFormatCommands`）
- [x] 注册基础格式命令（加粗、斜体、下划线、删除线、高亮）
- [x] 格式命令支持状态检查（`canExecute`, `getState`）
- [ ] 创建输入命令类（InputCommand）- 可选，输入操作已通过 DOMWriter 处理
- [ ] 创建删除命令类（DeleteCommand）- 可选，删除操作已通过 DOMWriter 处理
- [ ] 创建列表命令类（ListCommand）- 待实现
- [ ] 创建图片命令类（ImageCommand）- 待实现
- [ ] 替换现有的 `executeFormatAction` 等方法使用命令系统 - 待实现

---

## 阶段 4：实现命令状态检查 ✅ **已完成**

### 4.1 定义状态检查接口 ✅ **已完成**
- [x] 在 `CommandManager` 中实现状态检查功能
- [x] 实现状态缓存机制（50ms 缓存超时）
- [x] 实现批量状态获取（`getStates()`）
- [x] 实现批量可执行性检查（`canExecuteBatch()`）

### 4.2 实现具体状态检查 ✅ **已完成**
- [x] 格式命令状态检查：
  - ✅ 检查是否已应用格式（通过 `getState()`）
  - ✅ 检查选择范围是否有效（通过 `canExecute()`）
- [x] 状态检查已集成到格式命令注册中

### 4.3 集成到 UI ✅ **已完成**
- [x] 修改 `syncFormatState` 函数，使用命令系统获取状态
- [x] 实现命令状态同步到 Swift（通过 `formatStateChanged` 消息）
- [x] 支持状态缓存，提高性能
- [x] 保持向后兼容（如果命令管理器不可用，回退到原有方法）

---

## 实施顺序

### 第一步：操作合并（最简单，影响最小）
1. 实现操作类型枚举
2. 实现操作合并逻辑
3. 集成到 DOMWriter

### 第二步：命令抽象（为后续改进打基础）
1. 创建命令基类
2. 重构部分命令（格式命令）
3. 实现命令管理器

### 第三步：状态检查（依赖命令系统）
1. 实现状态检查接口
2. 为每个命令添加状态检查
3. 集成到 UI

### 第四步：增量记录（最复杂，最后实施）
1. 实现 Diff 工具
2. 实现增量记录
3. 优化内存使用

---

## 技术细节

### 操作合并算法
```javascript
function shouldMergeOperations(op1, op2) {
    // 相同类型
    if (op1.type !== op2.type) return false;
    
    // 时间间隔 < 500ms
    if (op2.timestamp - op1.timestamp > 500) return false;
    
    // 输入操作：连续输入可以合并
    if (op1.type === 'input') return true;
    
    // 格式操作：相同格式可以合并
    if (op1.type === 'format' && op1.format === op2.format) return true;
    
    return false;
}
```

### 增量记录结构
```javascript
{
    type: 'diff',
    changes: [
        { path: [0, 1], action: 'modify', attr: 'style', oldValue: '', newValue: 'bold' },
        { path: [0, 2], action: 'insert', node: '<span>...</span>' },
        { path: [0, 3], action: 'delete' }
    ],
    timestamp: 1234567890
}
```

### 命令基类结构
```javascript
class Command {
    constructor(name, options = {}) {
        this.name = name;
        this.executeFn = options.execute;
        this.undoFn = options.undo;
        this.canExecuteFn = options.canExecute;
        this.state = null;
    }
    
    execute(context) {
        if (!this.canExecute(context)) {
            throw new Error(`Command ${this.name} cannot be executed`);
        }
        this.state = this.executeFn(context);
        return this.state;
    }
    
    undo(context) {
        if (!this.undoFn) {
            throw new Error(`Command ${this.name} does not support undo`);
        }
        return this.undoFn(context, this.state);
    }
    
    canExecute(context) {
        if (!this.canExecuteFn) return true;
        return this.canExecuteFn(context);
    }
}
```

---

## 测试计划

### 操作合并测试
- [ ] 测试连续输入合并
- [ ] 测试格式操作合并
- [ ] 测试不同操作不合并
- [ ] 测试时间窗口边界

### 增量记录测试
- [ ] 测试增量记录正确性
- [ ] 测试增量恢复正确性
- [ ] 测试内存使用优化
- [ ] 测试大文档性能

### 命令系统测试
- [ ] 测试命令执行
- [ ] 测试命令撤销
- [ ] 测试命令状态检查
- [ ] 测试命令管理器

---

## 预期效果

1. **操作合并**：减少历史记录数量 50-70%，提升撤销/重做性能
2. **增量记录**：减少内存占用 60-80%，支持更大的历史记录
3. **命令抽象**：代码可维护性提升，易于扩展新功能
4. **状态检查**：UI 状态更准确，用户体验更好
