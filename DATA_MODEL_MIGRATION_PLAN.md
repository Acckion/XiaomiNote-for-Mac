# 全面转向数据模型的重构计划

## 一、架构设计

### 核心组件

```
┌─────────────────────────────────────────────────────────┐
│              FormatStateManager (数据模型)                │
│  - formatState: { bold, italic, underline, ... }         │
│  - 状态变化监听器                                          │
│  - 状态历史管理（可选）                                     │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│              FormatCommand (命令系统)                      │
│  - execute(formatType)                                    │
│  - undo() / redo()                                        │
│  - 命令历史管理                                            │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│              DOMRenderer (DOM 同步)                        │
│  - syncModelToDOM()                                       │
│  - syncDOMToModel()                                       │
│  - applyFormatToDOM()                                     │
│  - removeFormatFromDOM()                                  │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│              FormatManager (重构后)                        │
│  - 使用 FormatStateManager                                │
│  - 使用 FormatCommand                                     │
│  - 使用 DOMRenderer                                       │
└─────────────────────────────────────────────────────────┘
```

---

## 二、实现步骤

### 步骤1：实现 FormatStateManager

**位置：** `editor.html` 中，在 `FormatManager` 类之前

**功能：**
- 管理格式状态（bold, italic, underline, strikethrough, highlight）
- 状态变化监听
- 状态查询（O(1)）
- 状态历史（可选，用于撤销/重做）

**API：**
```javascript
class FormatStateManager {
    constructor()
    getState() → { bold: boolean, italic: boolean, ... }
    setFormat(formatType, enabled) → void
    toggleFormat(formatType) → void
    isFormatActive(formatType) → boolean
    onStateChange(callback) → void
    clearState() → void
}
```

### 步骤2：实现 FormatCommand

**位置：** `editor.html` 中，在 `FormatStateManager` 之后

**功能：**
- 执行格式命令
- 支持撤销/重做（可选）
- 命令历史管理

**API：**
```javascript
class FormatCommand {
    constructor(formatStateManager, domRenderer)
    execute(formatType, range) → boolean
    undo() → boolean
    redo() → boolean
    canUndo() → boolean
    canRedo() → boolean
}
```

### 步骤3：实现 DOMRenderer

**位置：** `editor.html` 中，在 `FormatCommand` 之后

**功能：**
- 同步数据模型到 DOM
- 同步 DOM 到数据模型
- 应用/移除格式到 DOM

**API：**
```javascript
class DOMRenderer {
    constructor(formatStateManager)
    syncModelToDOM(range) → void
    syncDOMToModel(range) → void
    applyFormatToDOM(formatType, range) → void
    removeFormatFromDOM(formatType, range) → void
    getFormatStateFromDOM(range) → { bold: boolean, ... }
}
```

### 步骤4：重构 FormatManager

**位置：** `editor.html` 中，替换现有的 `FormatManager` 类

**功能：**
- 使用 `FormatStateManager` 管理状态
- 使用 `FormatCommand` 执行命令
- 使用 `DOMRenderer` 同步 DOM
- 保持现有 API 兼容性

**API：**
```javascript
class FormatManager {
    constructor()
    toggleFormat(formatType) → boolean
    getCurrentFormatState() → { bold: boolean, ... }
    // ... 其他方法保持不变
}
```

### 步骤5：优化输入处理

**位置：** `editor.html` 中，`setupEditor()` 函数

**功能：**
- `beforeinput` 事件：根据数据模型应用格式
- `input` 事件：同步 DOM 到数据模型（如果需要）

**修改：**
```javascript
editor.addEventListener('beforeinput', (e) => {
    if (e.inputType === 'insertText' && !hasSelection) {
        // 根据 formatStateManager 应用格式
        const state = formatStateManager.getState();
        // 应用格式...
    }
});
```

### 步骤6：集成到 XML/HTML 转换

**位置：** `editor.html` 中，`convertHTMLToXML()` 和 `renderXMLToEditor()`

**功能：**
- 在 `convertHTMLToXML()` 前同步 DOM 到数据模型
- 在 `renderXMLToEditor()` 后同步 DOM 到数据模型

**修改：**
```javascript
function convertHTMLToXML(htmlContent) {
    // 同步 DOM 到数据模型（确保状态一致）
    if (formatStateManager) {
        const selection = window.getSelection();
        if (selection.rangeCount) {
            const range = selection.getRangeAt(0);
            domRenderer.syncDOMToModel(range);
        }
    }
    
    // ... 现有转换逻辑 ...
}

function renderXMLToEditor(xmlContent) {
    // ... 现有渲染逻辑 ...
    
    // 渲染后，同步 DOM 到数据模型
    if (formatStateManager && domRenderer) {
        const selection = window.getSelection();
        if (selection.rangeCount) {
            const range = selection.getRangeAt(0);
            domRenderer.syncDOMToModel(range);
        }
    }
}
```

---

## 三、代码结构

### 文件组织

```
editor.html
├── FormatStateManager (新)
├── FormatCommand (新)
├── DOMRenderer (新)
├── FormatManager (重构)
├── setupEditor() (修改)
├── convertHTMLToXML() (修改)
└── renderXMLToEditor() (修改)
```

### 依赖关系

```
FormatManager
  ├── FormatStateManager
  ├── FormatCommand
  │     ├── FormatStateManager
  │     └── DOMRenderer
  │           └── FormatStateManager
  └── DOMRenderer
        └── FormatStateManager
```

---

## 四、测试计划

### 测试用例

1. **格式切换**
   - 无选中文本：切换格式按钮，输入文本，验证格式应用
   - 有选中文本：选中文本，切换格式，验证格式应用

2. **格式状态一致性**
   - 应用格式后，查询状态，验证状态正确
   - 移除格式后，查询状态，验证状态正确

3. **输入处理**
   - 启用格式后输入，验证输入继承格式
   - 禁用格式后输入，验证输入不继承格式

4. **XML/HTML 转换**
   - 应用格式后保存，验证 XML 包含格式
   - 加载带格式的 XML，验证格式正确显示

5. **边界情况**
   - 光标在格式元素边界
   - 多个格式叠加
   - 格式嵌套顺序

---

## 五、实施时间估算

- **步骤1：FormatStateManager** - 2-3 小时
- **步骤2：FormatCommand** - 2-3 小时
- **步骤3：DOMRenderer** - 3-4 小时
- **步骤4：重构 FormatManager** - 2-3 小时
- **步骤5：优化输入处理** - 1-2 小时
- **步骤6：集成转换流程** - 1 小时
- **测试和修复** - 2-3 小时

**总计：约 13-19 小时（2-3 天）**

---

## 六、风险控制

### 风险1：破坏现有功能
- **缓解措施：** 保持 FormatManager 的 API 不变，逐步迁移

### 风险2：性能问题
- **缓解措施：** 使用批量 DOM 操作，避免频繁同步

### 风险3：状态不一致
- **缓解措施：** 在关键操作前后同步状态

---

## 七、回滚计划

如果重构出现问题：
1. 保留现有 `FormatManager` 的备份
2. 可以快速回滚到旧实现
3. 逐步迁移，确保每个步骤都可以独立测试




