# 历史记录内存优化总结

## 改进概述

实现了增量记录机制，大幅减少历史记录的内存占用，同时保持撤销/重做的功能完整性。

## 核心实现

### 1. DOM Diff 工具

#### DOMWriter.DOMDiff 类
- **`diff(oldHtml, newHtml)`**: 计算两个 HTML 字符串之间的差异
  - 如果完全相同，返回 `{ type: 'no-change' }`
  - 如果变化超过 50%，返回完整快照（更高效）
  - 否则返回增量差异（记录变化的位置和内容）

- **`apply(baseHtml, diff)`**: 根据差异恢复 HTML
  - 支持增量差异恢复
  - 支持完整快照恢复

### 2. 增量状态捕获

#### `_captureState(useIncremental, previousState)`
- **参数**:
  - `useIncremental`: 是否使用增量记录（默认 false）
  - `previousState`: 前一个状态（用于计算差异）

- **逻辑**:
  1. 如果使用增量记录且有前一个状态，计算差异
  2. 如果差异类型是增量，返回增量记录
  3. 如果差异太大（>50%），使用完整快照
  4. 否则返回完整快照

### 3. 快照间隔机制

- **快照间隔**: 每隔 10 个操作保存一个完整快照
- **目的**: 平衡内存使用和恢复速度
- **实现**: `lastSnapshotIndex` 跟踪最后一个快照位置

### 4. 状态恢复

#### `_restoreState(state)`
- 支持恢复完整快照
- 支持恢复增量记录（递归恢复基础状态）
- 处理未知类型（回退到直接使用）

## 内存优化效果

### 优化前
- 每个操作保存完整的 HTML 快照
- 50 个操作 = 50 个完整 HTML 快照
- 内存占用：O(n × HTML大小)

### 优化后
- 大部分操作使用增量记录（只保存变化部分）
- 每隔 10 个操作保存一个完整快照
- 50 个操作 ≈ 5 个完整快照 + 45 个增量记录
- 内存占用：O(快照数 × HTML大小 + 增量数 × 变化大小)

### 预期效果
- **内存占用减少**: 60-80%（取决于操作类型）
- **恢复速度**: 略有影响（需要递归恢复），但可接受
- **功能完整性**: 100% 保持

## 配置参数

```javascript
// DOMWriter 构造函数中
this.useIncrementalRecording = true;  // 是否使用增量记录
this.snapshotInterval = 10;            // 快照间隔（每隔 N 个操作）
this.maxHistorySize = 50;              // 最大历史记录数
```

## 使用示例

### 增量记录结构
```javascript
{
    type: 'incremental',
    diff: {
        type: 'incremental',
        start: 100,
        oldLength: 5,
        newLength: 10,
        oldContent: 'hello',
        newContent: 'hello world'
    },
    cursorPosition: {...},
    baseState: {...}  // 引用基础状态
}
```

### 完整快照结构
```javascript
{
    type: 'full-snapshot',
    html: '<div>...</div>',
    cursorPosition: {...}
}
```

## 注意事项

1. **增量记录链**: 增量记录可能形成引用链，需要递归恢复
2. **快照重建**: 当历史记录被截断时，需要重建快照
3. **性能权衡**: 增量记录减少内存，但恢复时需要更多计算

## 未来改进

1. **更智能的差异算法**: 使用树形差异算法（类似 React 的 diff）
2. **压缩增量记录**: 对增量内容进行压缩
3. **自适应快照间隔**: 根据内存使用情况动态调整快照间隔

