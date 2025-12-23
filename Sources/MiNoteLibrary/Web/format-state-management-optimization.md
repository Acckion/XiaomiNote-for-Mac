# 格式状态管理优化总结

## 优化目标

参考 CKEditor 5 的实现方式，统一管理所有格式状态，使格式菜单能够根据光标位置动态刷新和修改状态。

## 参考的 CKEditor 5 实现

### 1. 状态同步机制

**CKEditor 5 的实现**：
- 使用命令的 `value` 属性来绑定 UI 状态
- UI 通过 `bind('isOn').to(command, 'value')` 自动同步状态
- 命令在执行后自动更新 `value` 属性
- UI 状态始终与编辑器状态保持一致

**关键代码**：
```typescript
// CKEditor 5 的按钮状态绑定
buttonView.bind('isOn').to(headingCommand, 'value', value => value === option.model);
buttonView.bind('isOn').to(paragraphCommand, 'value');
```

### 2. 状态检查机制

**CKEditor 5 的实现**：
- 命令的 `refresh()` 方法检查当前选择的状态
- 使用 `selection.hasAttribute()` 检查属性
- 使用 `schema.checkAttributeInSelection()` 检查是否允许应用属性

## 已实施的优化

### 1. 扩展格式状态检查

添加了以下检查方法（参考 CKEditor 5 的命令 value 检查）：

#### `checkHeadingLevel(range)`
- 检查标题级别（1=大标题, 2=二级标题, 3=三级标题, null=正文）
- 向上查找 `.mi-note-size`, `.mi-note-mid-size`, `.mi-note-h3-size` 类名

#### `checkListType(range)`
- 检查列表类型（'bullet'=无序列表, 'order'=有序列表, null=非列表）
- 向上查找 `.mi-note-bullet`, `.mi-note-order` 类名

#### `checkTextAlignment(range)`
- 检查文本对齐方式（'left', 'center', 'right'）
- 向上查找 `.mi-note-text` 元素，检查 `center` 和 `right` 类名

#### `checkQuoteState(range)`
- 检查是否在引用块中（boolean）
- 向上查找 `.mi-note-quote` 类名

### 2. 扩展 `syncFormatState` 函数

**改进前**：
- 只同步文本格式（加粗、斜体、下划线、删除线、高亮）

**改进后**：
- 同步所有格式状态：
  - 文本格式（加粗、斜体、下划线、删除线、高亮）
  - 标题级别
  - 列表类型
  - 对齐方式
  - 引用块状态

**关键改进**：
```javascript
const formatState = {
    isBold: window.MiNoteWebEditor.checkFormatState(range, 'bold'),
    isItalic: window.MiNoteWebEditor.checkFormatState(range, 'italic'),
    isUnderline: window.MiNoteWebEditor.checkFormatState(range, 'underline'),
    isStrikethrough: window.MiNoteWebEditor.checkFormatState(range, 'strikethrough'),
    isHighlighted: window.MiNoteWebEditor.checkFormatState(range, 'highlight'),
    headingLevel: window.MiNoteWebEditor.checkHeadingLevel(range),
    listType: window.MiNoteWebEditor.checkListType(range),
    textAlignment: window.MiNoteWebEditor.checkTextAlignment(range),
    isInQuote: window.MiNoteWebEditor.checkQuoteState(range)
};
```

### 3. 优化状态同步时机

**改进前**：
- 只在 `selectionchange` 事件中同步

**改进后**：
- 在多个事件中同步（参考 CKEditor 5）：
  - `selectionchange`：选择变化时
  - `input`：输入时
  - `keyup`：键盘抬起时
- 使用防抖机制（50ms），避免频繁更新
- 格式操作后立即同步状态

**关键改进**：
```javascript
// 选择变化监听
document.addEventListener('selectionchange', function() {
    clearTimeout(formatStateSyncTimer);
    formatStateSyncTimer = setTimeout(function() {
        syncFormatState();
    }, 50);
});

// 输入事件时也同步
editor.addEventListener('input', function() {
    clearTimeout(formatStateSyncTimer);
    formatStateSyncTimer = setTimeout(function() {
        syncFormatState();
    }, 50);
});

// 键盘事件时也同步
editor.addEventListener('keyup', function() {
    clearTimeout(formatStateSyncTimer);
    formatStateSyncTimer = setTimeout(function() {
        syncFormatState();
    }, 50);
});
```

### 4. 优化 Swift 端状态管理

#### 扩展 `WebEditorContext`
- 添加 `listType: String?` 属性（'bullet' 或 'order' 或 nil）
- 添加 `isInQuote: Bool` 属性
- 移除手动状态切换，改为由编辑器同步（参考 CKEditor 5）

#### 处理 `formatStateChanged` 消息
- 在 `WebEditorView.swift` 中处理 `formatStateChanged` 消息
- 更新所有格式状态到 `WebEditorContext`
- 确保状态在主线程上更新

**关键改进**：
```swift
case "formatStateChanged":
    if let formatState = body["formatState"] as? [String: Any] {
        DispatchQueue.main.async {
            // 更新所有格式状态
            webEditorContext.isBold = formatState["isBold"] as? Bool ?? false
            webEditorContext.headingLevel = formatState["headingLevel"] as? Int
            webEditorContext.listType = formatState["listType"] as? String
            webEditorContext.textAlignment = TextAlignment.fromString(formatState["textAlignment"] as? String ?? "left")
            // ...
        }
    }
```

### 5. 优化格式菜单 UI

#### 动态勾选状态（参考 CKEditor 5 的 `isOn` 绑定）
- 移除本地状态（`currentStyle`, `isBlockQuote`）
- 使用 `isStyleSelected()` 方法动态计算勾选状态
- 根据 `context` 的状态自动更新 UI

**关键改进**：
```swift
private func isStyleSelected(_ style: TextStyle) -> Bool {
    switch style {
    case .title:
        return context.headingLevel == 1
    case .subtitle:
        return context.headingLevel == 2
    case .subheading:
        return context.headingLevel == 3
    case .body:
        return context.headingLevel == nil && context.listType == nil
    case .bulletList:
        return context.listType == "bullet"
    case .numberedList:
        return context.listType == "order"
    }
}
```

## 优化效果

### 1. 统一的状态管理

- ✅ **文本格式**：加粗、斜体、下划线、删除线、高亮统一管理
- ✅ **标题级别**：大标题、二级标题、三级标题、正文动态检测
- ✅ **列表类型**：无序列表、有序列表动态检测
- ✅ **对齐方式**：左对齐、居中、右对齐动态检测
- ✅ **引用块**：引用块状态动态检测

### 2. 实时状态同步

- ✅ 光标移动时自动同步状态
- ✅ 输入时自动同步状态
- ✅ 格式操作后立即同步状态
- ✅ 使用防抖机制，避免频繁更新

### 3. UI 自动更新

- ✅ 格式菜单按钮状态自动更新
- ✅ 标题/列表勾选状态自动更新
- ✅ 对齐方式按钮状态自动更新
- ✅ 引用块勾选状态自动更新

## 关键改进点总结

| 改进项 | 改进前 | 改进后 | 参考 |
|--------|--------|--------|------|
| **状态检查** | 只检查文本格式 | 检查所有格式（文本、标题、列表、对齐、引用） | CKEditor 5 的命令 value |
| **状态同步** | 只在 selectionchange 中同步 | 在多个事件中同步（selectionchange, input, keyup） | CKEditor 5 的状态绑定 |
| **状态管理** | 手动切换状态 | 由编辑器同步状态 | CKEditor 5 的自动绑定 |
| **UI 更新** | 使用本地状态 | 根据编辑器状态动态计算 | CKEditor 5 的 isOn 绑定 |

## 测试建议

### 1. 文本格式状态

- [ ] 光标在加粗文本中 → 加粗按钮应高亮
- [ ] 光标在普通文本中 → 加粗按钮应不高亮
- [ ] 点击加粗按钮 → 按钮状态应立即更新
- [ ] 移动光标 → 按钮状态应自动更新

### 2. 标题/列表状态

- [ ] 光标在大标题中 → "大标题"应勾选
- [ ] 光标在正文中 → "正文"应勾选
- [ ] 光标在无序列表中 → "无序列表"应勾选
- [ ] 光标在有序列表中 → "有序列表"应勾选
- [ ] 移动光标 → 勾选状态应自动更新

### 3. 对齐方式状态

- [ ] 光标在居中文本中 → 居中按钮应高亮
- [ ] 光标在右对齐文本中 → 右对齐按钮应高亮
- [ ] 光标在左对齐文本中 → 左对齐按钮应高亮
- [ ] 移动光标 → 按钮状态应自动更新

### 4. 引用块状态

- [ ] 光标在引用块中 → "引用块"应勾选
- [ ] 光标在普通文本中 → "引用块"应不勾选
- [ ] 移动光标 → 勾选状态应自动更新

## 后续优化建议

1. **性能优化**：如果状态同步过于频繁，可以进一步优化防抖时间
2. **状态缓存**：可以缓存上次的状态，只在状态变化时更新
3. **批量更新**：可以批量更新多个状态，减少 UI 更新次数

## 总结

通过参考 CKEditor 5 的实现方式，我们优化了格式状态管理：

1. ✅ **统一的状态检查**：所有格式状态使用统一的检查机制
2. ✅ **实时状态同步**：在多个事件中同步状态，确保 UI 始终反映编辑器状态
3. ✅ **自动 UI 更新**：格式菜单根据编辑器状态自动更新，无需手动管理
4. ✅ **逻辑一致性**：所有格式操作（文本格式、标题、列表、对齐、引用）使用相同的状态管理机制

这些优化应该能够实现格式菜单的动态刷新和状态同步，与 CKEditor 5 的行为保持一致。




