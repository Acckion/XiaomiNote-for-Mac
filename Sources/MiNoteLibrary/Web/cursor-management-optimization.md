# 光标管理优化总结

## 优化目标

参考 CKEditor 5 的实现方式，优化当前编辑器中的光标管理和格式状态管理，解决格式切换时的问题。

## 参考的 CKEditor 5 实现

### 1. AttributeCommand（格式切换核心）

**CKEditor 5 的实现**：
```typescript
// 对于折叠选择（光标位置）
if (selection.isCollapsed) {
    if (value) {
        writer.setSelectionAttribute(this.attributeKey, true);
    } else {
        writer.removeSelectionAttribute(this.attributeKey);
    }
} else {
    // 对于非折叠选择（选中文本）
    const ranges = model.schema.getValidRanges(selection.getRanges(), this.attributeKey);
    for (const range of ranges) {
        if (value) {
            writer.setAttribute(this.attributeKey, value, range);
        } else {
            writer.removeAttribute(this.attributeKey, range);
        }
    }
}
```

**关键点**：
- 折叠选择：使用 `setSelectionAttribute` / `removeSelectionAttribute`
- 非折叠选择：使用 `setAttribute` / `removeAttribute` 在范围内操作
- 自动处理光标位置，不需要手动管理

### 2. RemoveFormatCommand（格式清除）

**CKEditor 5 的实现**：
```typescript
// 遍历选择范围内的所有格式化项
for (const item of this._getFormattingItems(model.document.selection)) {
    if (item.is('selection')) {
        for (const attributeName of this._getFormattingAttributes(item)) {
            writer.removeSelectionAttribute(attributeName);
        }
    } else {
        const itemRange = writer.createRangeOn(item);
        for (const attributeName of this._getFormattingAttributes(item)) {
            this._removeFormatting(attributeName, item, itemRange, writer);
        }
    }
}
```

**关键点**：
- 自动识别所有格式化项
- 使用 writer 统一处理
- 自动维护光标位置

## 已实施的优化

### 1. 优化 `clearFormatAtCursor` 方法

**改进前**：
- 手动查找格式元素
- 手动插入文本节点
- 手动移动光标
- 逻辑复杂，容易出错

**改进后**：
- 优先使用 `execCommand`（类似 CKEditor 5 的 `writer.removeSelectionAttribute`）
- 回退到手动方法（当 execCommand 不可用时）
- 简化逻辑，提高可靠性

**关键改进**：
```javascript
// 方法1：优先使用 execCommand（最可靠）
try {
    const isFormatted = document.queryCommandState(format);
    if (isFormatted) {
        document.execCommand(format, false, null);
        // execCommand 会自动处理光标位置
        return;
    }
} catch (e) {
    // 回退到手动方法
}

// 方法2：手动清除（当 execCommand 不可用时）
// 查找格式元素，将光标移出
```

### 2. 优化格式切换逻辑

**改进前**：
- 应用格式前需要手动确保光标位置
- 逻辑复杂，可能遗漏边界情况

**改进后**：
- 参考 CKEditor 5 的 `AttributeCommand.execute`
- 折叠选择：直接使用 `execCommand`（类似 `setSelectionAttribute`）
- 非折叠选择：使用 `execCommand` 在范围内操作（类似 `setAttribute`）
- 简化逻辑，提高可靠性

**关键改进**：
```javascript
if (range.collapsed) {
    // 折叠选择：类似 writer.setSelectionAttribute/writer.removeSelectionAttribute
    if (isCurrentlyFormatted) {
        this.clearFormatAtCursor(range, format, tagName, className);
    } else {
        // execCommand 会自动处理，不需要手动移动光标
        document.execCommand(format, false, null);
    }
} else {
    // 非折叠选择：类似 writer.setAttribute/writer.removeAttribute
    if (isCurrentlyFormatted) {
        this.removeFormatFromSelection(range, format, tagName, className);
    } else {
        document.execCommand(format, false, null);
    }
}
```

### 3. 优化 `ensureCursorOutsideFormatElements` 方法

**改进前**：
- 对所有格式都进行手动处理
- 逻辑复杂

**改进后**：
- 对于 `execCommand` 支持的格式（bold, italic, underline, strikethrough），直接返回
- 只对自定义格式（如高亮）进行手动处理
- 简化逻辑，提高性能

**关键改进**：
```javascript
// 对于 execCommand 支持的格式，不需要手动处理
if (tagName && ['bold', 'italic', 'underline', 'strikethrough'].includes(format)) {
    return; // execCommand 会自动处理
}

// 只对自定义格式（如高亮）需要手动处理
```

### 4. 优化 `removeFormatFromSelection` 方法

**改进前**：
- 手动遍历 DOM 树
- 逻辑复杂，可能遗漏某些情况

**改进后**：
- 优先使用 `execCommand`（类似 CKEditor 5 的 `writer.removeAttribute`）
- 回退到手动方法（当 execCommand 不可用时）
- 支持所有标签变体（`<b>`/`<strong>`, `<i>`/`<em>` 等）

**关键改进**：
```javascript
// 方法1：优先使用 execCommand（最可靠）
if (tagName) {
    document.execCommand(format, false, null);
    return;
}

// 方法2：手动移除（当 execCommand 不可用时）
// 支持所有标签变体，递归处理嵌套格式
```

### 5. 优化格式状态检测

**改进前**：
- 只检查光标位置的格式
- 可能不准确

**改进后**：
- 优先使用 `queryCommandState`（类似 CKEditor 5 的 `selection.hasAttribute`）
- DOM 检查支持所有标签变体
- 对于非折叠选择，检查选中文本是否包含格式（类似 CKEditor 5 的 `range.getItems`）

**关键改进**：
```javascript
// 方法1：优先使用 queryCommandState（最准确）
const state = document.queryCommandState(format);
if (state !== undefined && state !== null) {
    return Boolean(state);
}

// 方法2：DOM 检查（支持所有标签变体）
// 检查 <b>/<strong>, <i>/<em>, <s>/<strike>/<del> 等

// 方法3：对于非折叠选择，检查选中文本
// 类似 CKEditor 5 的 range.getItems()
```

## 优化效果

### 1. 代码简化

- **clearFormatAtCursor**：优先使用 `execCommand`，简化逻辑
- **ensureCursorOutsideFormatElements**：对标准格式直接返回，减少不必要的处理
- **格式切换逻辑**：参考 CKEditor 5，更简洁清晰

### 2. 可靠性提升

- 优先使用浏览器原生 API（`execCommand`, `queryCommandState`）
- 自动处理光标位置（不需要手动管理）
- 支持所有标签变体（`<b>`/`<strong>`, `<i>`/`<em>` 等）

### 3. 性能提升

- 减少 DOM 操作
- 减少手动光标移动
- 利用浏览器原生优化

## 关键改进点总结

| 方法 | 改进前 | 改进后 | 参考 |
|------|--------|--------|------|
| **clearFormatAtCursor** | 手动查找和移动光标 | 优先使用 execCommand | CKEditor 5 的 `removeSelectionAttribute` |
| **格式切换逻辑** | 复杂的手动处理 | 直接使用 execCommand | CKEditor 5 的 `AttributeCommand.execute` |
| **ensureCursorOutsideFormatElements** | 对所有格式都处理 | 只处理自定义格式 | 优化逻辑 |
| **removeFormatFromSelection** | 手动遍历 DOM | 优先使用 execCommand | CKEditor 5 的 `removeAttribute` |
| **格式状态检测** | 简单的 DOM 检查 | 多层检测机制 | CKEditor 5 的 `selection.hasAttribute` |

## 测试建议

### 1. 基本格式切换

- [ ] 光标在普通文本中，应用加粗 → 输入文本应该是加粗
- [ ] 光标在加粗文本中，取消加粗 → 输入文本应该不加粗
- [ ] 光标在加粗文本末尾，取消加粗 → 输入文本应该不加粗
- [ ] 选中加粗文本，取消加粗 → 文本应该变为普通文本

### 2. 嵌套格式

- [ ] 光标在加粗+斜体文本中，取消加粗 → 应该只取消加粗，保留斜体
- [ ] 光标在加粗文本中，应用斜体 → 应该同时应用加粗和斜体

### 3. 边界情况

- [ ] 光标在格式元素开头
- [ ] 光标在格式元素中间
- [ ] 光标在格式元素末尾
- [ ] 选中文本跨越多个格式元素

### 4. 所有格式类型

- [ ] 加粗（bold）
- [ ] 斜体（italic）
- [ ] 下划线（underline）
- [ ] 删除线（strikethrough）
- [ ] 高亮（highlight）

## 后续优化（第二版）

### 问题：光标仍然四处乱跑

用户反馈虽然格式切换逻辑正确，但光标位置仍然不稳定。进一步优化：

#### 1. 添加光标位置修复机制（`normalizeCursorPosition`）

参考 CKEditor 5 的 `selection post-fixer`，实现光标位置规范化：

- **检查光标是否在不可编辑元素内**（checkbox、hr、image 等）
- **检查光标是否在空文本节点中**（只有零宽度空格）
- **自动移动到最近的有效文本位置**

**关键改进**：
```javascript
// 类似 CKEditor 5 的 getNearestSelectionRange
// 找到最近的有效文本位置，而不是创建新节点
```

#### 2. 优化 `clearFormatAtCursor` 方法

**改进前**：
- 总是创建新的文本节点
- 可能导致光标跳动

**改进后**：
- 优先查找格式元素后的现有文本节点
- 只有在必要时才创建新节点
- 减少 DOM 操作，避免光标跳动

**关键改进**：
```javascript
// 检查格式元素后是否已有文本节点
let nextTextNode = null;
// 查找格式元素后的第一个文本节点
// 如果存在，直接移动光标到那里（避免创建新节点）
if (nextTextNode) {
    // 直接使用现有节点
} else {
    // 只有在必要时才创建新节点
}
```

#### 3. 减少不必要的光标修复调用

**改进前**：
- 在 `selectionchange` 事件中总是调用 `normalizeCursorPosition`
- 在格式切换后也调用 `normalizeCursorPosition`
- 可能导致冲突和光标跳动

**改进后**：
- 移除 `selectionchange` 中的自动修复（避免与格式操作冲突）
- 只在必要时（手动清除格式时）才修复光标位置
- 对于 `execCommand` 支持的格式，信任浏览器自动处理

**关键改进**：
```javascript
// execCommand 会自动处理光标位置，不需要额外修复
document.execCommand(format, false, null);
// 不需要调用 normalizeCursorPosition，避免光标跳动
```

## 后续优化建议

1. **添加单元测试**：覆盖各种边界情况
2. **性能监控**：监控格式切换的性能
3. **用户体验测试**：收集用户反馈，持续优化
4. **光标位置监控**：添加调试日志，追踪光标位置变化

## 总结

通过参考 CKEditor 5 的实现方式，我们优化了光标管理和格式状态管理：

### 第一版优化
1. ✅ **简化了代码**：优先使用浏览器原生 API
2. ✅ **提高了可靠性**：自动处理光标位置
3. ✅ **提升了性能**：减少不必要的 DOM 操作
4. ✅ **保持了兼容性**：支持所有标签变体

### 第二版优化（解决光标乱跑问题）
1. ✅ **添加光标位置修复机制**：参考 CKEditor 5 的 selection post-fixer
2. ✅ **优化 DOM 操作**：优先使用现有节点，减少创建新节点
3. ✅ **减少不必要的修复调用**：避免与格式操作冲突
4. ✅ **信任浏览器原生 API**：对于 execCommand 支持的格式，不额外修复

这些优化应该能够解决光标管理和状态管理问题，包括光标乱跑的问题。

