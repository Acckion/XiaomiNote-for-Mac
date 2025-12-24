# 撤销/重做系统改进说明

## 改进概述

根据 CKEditor 5 的实现方式，我们改进了操作合并逻辑，使其更加精确和用户友好。

## 核心改进

### 1. 操作合并策略（参考 CKEditor 5）

#### 输入操作合并
- **时间窗口**：100ms 内的连续输入可以合并
- **合并限制**：最多合并 50 次，避免无限合并
- **光标检测**：如果光标位置变化太大（路径长度差异 > 2），不合并
- **效果**：快速连续输入会被合并为一个撤销步骤，但用户停顿后的输入会创建新的撤销步骤

#### 删除操作合并
- **时间窗口**：150ms 内的连续删除可以合并
- **合并限制**：最多合并 30 次
- **效果**：快速连续删除会被合并为一个撤销步骤

#### 格式操作
- **不合并**：每次格式操作都是独立的撤销步骤
- **原因**：格式操作通常是用户有意的操作，应该可以单独撤销
- **例外**：只有在明确的批量操作模式下才合并

### 2. 关键实现细节

#### 操作类型枚举
```javascript
const OPERATION_TYPES = {
    INPUT: 'input',           // 文本输入
    DELETE: 'delete',         // 删除操作
    FORMAT: 'format',         // 格式操作
    FORMAT_REMOVE: 'format_remove', // 移除格式
    // ... 其他类型
};
```

#### 合并判断逻辑
```javascript
_shouldMergeOperations(op1, op2) {
    // 1. 必须相同类型
    // 2. 检查时间间隔
    // 3. 检查合并次数限制
    // 4. 检查光标位置变化（仅输入操作）
    // 5. 格式操作默认不合并
}
```

#### 操作记录结构
```javascript
{
    type: OPERATION_TYPES.INPUT,
    command: 'insertText',
    beforeState: { html: '...', cursorPosition: {...} },
    afterState: { html: '...', cursorPosition: {...} },
    savedPosition: {...},
    timestamp: Date.now(),
    isBatch: false,        // 是否允许合并
    mergedCount: 1         // 合并次数（合并后增加）
}
```

## 与 CKEditor 5 的对比

| 特性 | CKEditor 5 | 当前实现 | 说明 |
|------|-----------|---------|------|
| 输入合并 | Batch 机制 | 100ms 时间窗口 | 类似效果，但实现方式不同 |
| 格式合并 | 不合并 | 不合并 | ✅ 一致 |
| 删除合并 | Batch 机制 | 150ms 时间窗口 | 类似效果 |
| 批量操作 | change() 块 | isBatch 标记 | 概念相似 |

## 使用示例

### 正常输入
```
用户快速输入 "hello"（5个字符，每个字符间隔 < 100ms）
→ 合并为 1 个撤销步骤
→ 一次撤销会撤销整个 "hello"
```

### 停顿后输入
```
用户输入 "hello"，停顿 200ms，然后输入 "world"
→ "hello" 为 1 个撤销步骤
→ "world" 为另 1 个撤销步骤
→ 需要两次撤销才能完全撤销
```

### 格式操作
```
用户输入 "hello"，点击加粗，输入 "world"
→ "hello" 为 1 个撤销步骤
→ 加粗为 1 个撤销步骤（独立）
→ "world" 为 1 个撤销步骤
→ 可以单独撤销加粗操作
```

## 配置参数

可以通过修改以下参数调整合并行为：

```javascript
// 输入操作合并时间窗口（毫秒）
const inputMergeWindow = 100;

// 删除操作合并时间窗口（毫秒）
const deleteMergeWindow = 150;

// 批量操作合并时间窗口（毫秒）
const batchMergeWindow = 200;

// 输入操作最大合并次数
const maxInputMergedCount = 50;

// 删除操作最大合并次数
const maxDeleteMergedCount = 30;
```

## 调试

可以通过日志查看操作合并情况：

```javascript
// 在浏览器控制台查看日志
// 合并操作时会输出：
log.debug(LOG_MODULES.HISTORY, '合并操作', { 
    type: 'input', 
    mergedCount: 5 
});
```

## 未来改进

1. **更智能的合并判断**：基于内容变化量，而不仅仅是时间
2. **用户可配置**：允许用户自定义合并时间窗口
3. **操作分组**：类似 CKEditor 5 的 Batch 机制，支持嵌套操作分组


