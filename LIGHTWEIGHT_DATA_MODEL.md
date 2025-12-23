# 轻量级数据模型设计文档

## 一、什么是轻量级数据模型？

### 概念
轻量级数据模型是一个**独立于 DOM 的格式状态管理系统**，它：
- 将格式状态从 DOM 结构中分离出来
- 维护一个内存中的格式状态对象
- 在输入时根据状态对象应用格式，而不是检查 DOM

### 与当前实现的区别

**当前实现（DOM 驱动）：**
```
用户输入 → DOM 变化 → 检查 DOM → 修复格式 → DOM 再次变化
```
- 格式状态存储在 DOM 中（通过 `<b>`, `<i>` 等标签）
- 需要频繁遍历 DOM 来检测格式状态
- 容易出现时序问题和状态不一致

**轻量级数据模型（状态驱动）：**
```
用户输入 → 查询状态对象 → 应用格式 → DOM 更新
```
- 格式状态存储在内存对象中
- 直接从状态对象查询，不需要遍历 DOM
- 状态一致，时序可控

---

## 二、轻量级数据模型的设计

### 1. 核心数据结构

```javascript
class FormatStateModel {
    constructor() {
        // 光标位置的格式状态（当前输入位置的格式）
        this.cursorFormatState = {
            bold: false,
            italic: false,
            underline: false,
            strikethrough: false,
            highlight: false
        };
        
        // 选中文本的格式状态（如果有选中文本）
        this.selectionFormatState = null;
        
        // 格式状态历史（用于撤销/重做）
        this.formatHistory = [];
        
        // 监听器（用于通知格式状态变化）
        this.listeners = [];
    }
}
```

### 2. 状态管理方法

```javascript
// 设置格式状态
setFormatState(formatType, enabled) {
    this.cursorFormatState[formatType] = enabled;
    this.notifyListeners();
}

// 获取格式状态
getFormatState() {
    return { ...this.cursorFormatState };
}

// 监听状态变化
onStateChange(callback) {
    this.listeners.push(callback);
}
```

### 3. 与 DOM 的同步

**关键原则：**
- **状态对象是唯一真实来源**：格式状态只存储在状态对象中
- **DOM 是状态的反映**：DOM 结构根据状态对象生成
- **输入时应用状态**：输入时根据状态对象应用格式，而不是检查 DOM

---

## 三、实现方案

### 方案1：最小化改动（推荐）

在现有 `FormatManager` 基础上，引入格式状态对象：

```javascript
class FormatManager {
    constructor() {
        // 现有的 pendingFormats（重命名为 formatState，作为数据模型）
        this.formatState = {
            bold: false,
            italic: false,
            underline: false,
            strikethrough: false,
            highlight: false
        };
        
        // 格式状态监听器
        this.stateListeners = [];
    }
    
    // 设置格式状态（数据模型操作）
    setFormatState(formatType, enabled) {
        this.formatState[formatType] = enabled;
        this.notifyStateChange(formatType, enabled);
    }
    
    // 获取格式状态（从数据模型查询）
    getFormatState() {
        return { ...this.formatState };
    }
    
    // 切换格式（更新数据模型）
    toggleFormat(formatType) {
        const selection = window.getSelection();
        if (!selection.rangeCount) return false;
        
        const range = selection.getRangeAt(0);
        const hasSelection = !range.collapsed;
        
        if (hasSelection) {
            // 有选中文本：切换选中文本的格式
            return this.toggleSelectedTextFormat(formatType, range);
        } else {
            // 无选中文本：更新数据模型状态
            const newState = !this.formatState[formatType];
            this.setFormatState(formatType, newState);
            
            // 根据新状态更新 DOM
            if (newState) {
                this.applyFormatToCursor(formatType, range, selection);
            } else {
                this.removeFormatFromCursor(formatType, range, selection);
            }
            
            return true;
        }
    }
    
    // 应用格式到光标位置（根据数据模型状态）
    applyFormatToCursor(formatType, range, selection) {
        // 检查光标位置是否已经在格式元素内
        // 如果不在，插入格式标记
        // 这个方法应该更简单，因为状态已经在数据模型中
    }
    
    // 从光标位置移除格式（根据数据模型状态）
    removeFormatFromCursor(formatType, range, selection) {
        // 将光标移出格式元素
        // 这个方法应该更简单，因为状态已经在数据模型中
    }
}
```

### 方案2：完整的数据模型（更彻底）

引入独立的格式状态管理器：

```javascript
class FormatStateManager {
    constructor() {
        // 格式状态对象（数据模型）
        this.state = {
            bold: false,
            italic: false,
            underline: false,
            strikethrough: false,
            highlight: false
        };
        
        // 状态变化监听器
        this.listeners = [];
    }
    
    // 设置格式状态
    setFormat(formatType, enabled) {
        if (this.state[formatType] !== enabled) {
            this.state[formatType] = enabled;
            this.notifyListeners(formatType, enabled);
        }
    }
    
    // 切换格式状态
    toggleFormat(formatType) {
        this.setFormat(formatType, !this.state[formatType]);
    }
    
    // 获取格式状态
    getState() {
        return { ...this.state };
    }
    
    // 批量设置格式状态
    setFormats(formats) {
        let changed = false;
        for (const [formatType, enabled] of Object.entries(formats)) {
            if (this.state[formatType] !== enabled) {
                this.state[formatType] = enabled;
                changed = true;
            }
        }
        if (changed) {
            this.notifyListeners(null, null);
        }
    }
    
    // 重置所有格式
    reset() {
        const hadFormats = Object.values(this.state).some(v => v);
        this.state = {
            bold: false,
            italic: false,
            underline: false,
            strikethrough: false,
            highlight: false
        };
        if (hadFormats) {
            this.notifyListeners(null, null);
        }
    }
    
    // 通知监听器
    notifyListeners(formatType, enabled) {
        this.listeners.forEach(listener => {
            try {
                listener(this.state, formatType, enabled);
            } catch (error) {
                console.error('[FormatStateManager] 监听器错误:', error);
            }
        });
    }
    
    // 添加监听器
    onStateChange(listener) {
        this.listeners.push(listener);
    }
    
    // 移除监听器
    offStateChange(listener) {
        const index = this.listeners.indexOf(listener);
        if (index > -1) {
            this.listeners.splice(index, 1);
        }
    }
}
```

---

## 四、轻量级数据模型的工作流程

### 场景1：用户点击加粗按钮（无选中文本）

**当前实现流程：**
1. 切换 `pendingFormats.bold`
2. 调用 `insertFormatMarker('bold')`
3. 插入零宽度空格
4. 使用 `document.execCommand('bold')`
5. 设置光标位置
6. 在 `input` 事件中检查并修复格式

**轻量级数据模型流程：**
1. 更新 `formatState.bold = true`（数据模型）
2. 通知监听器格式状态变化
3. 在 `beforeinput` 事件中，根据 `formatState.bold` 应用格式
4. 输入时，新文本自动继承格式（因为光标已在格式元素内）

### 场景2：用户输入文本

**当前实现流程：**
1. 用户输入文本
2. `input` 事件触发
3. 检查 `pendingFormats` 状态
4. 遍历 DOM 查找格式元素
5. 如果格式元素不存在，创建并包裹文本节点
6. 如果格式元素存在但文本不在其中，移动文本节点

**轻量级数据模型流程：**
1. 用户输入文本
2. `beforeinput` 事件触发
3. 查询 `formatState` 对象（不需要遍历 DOM）
4. 根据 `formatState` 应用格式
5. 输入完成，格式已正确应用

---

## 五、优势

### 1. 状态一致性
- 格式状态只存储在数据模型中，不会出现不一致
- DOM 结构完全由数据模型驱动

### 2. 性能优化
- 不需要频繁遍历 DOM
- 格式状态查询是 O(1) 操作

### 3. 时序可控
- 格式状态更新是同步的
- DOM 操作可以精确控制时机

### 4. 易于调试
- 格式状态清晰可见
- 可以轻松记录和回放状态变化

### 5. 易于扩展
- 添加新格式只需在数据模型中添加字段
- 不需要修改复杂的 DOM 操作逻辑

---

## 六、实现建议

### 阶段1：引入 FormatStateManager（最小改动）

1. 创建 `FormatStateManager` 类
2. 在 `FormatManager` 中使用 `FormatStateManager`
3. 将 `pendingFormats` 替换为 `formatStateManager.getState()`
4. 格式切换时更新 `FormatStateManager`

### 阶段2：优化输入处理

1. 在 `beforeinput` 事件中根据 `FormatStateManager` 的状态应用格式
2. 减少 `input` 事件中的格式检查和修复
3. 只在必要时（格式状态变化时）进行 DOM 操作

### 阶段3：优化格式检测

1. 格式状态检测优先从 `FormatStateManager` 查询
2. 只在必要时（如从外部加载内容）才遍历 DOM
3. 将 DOM 检测结果同步到 `FormatStateManager`

---

## 七、示例代码

### 完整的轻量级数据模型实现

```javascript
class FormatStateManager {
    constructor() {
        this.state = {
            bold: false,
            italic: false,
            underline: false,
            strikethrough: false,
            highlight: false
        };
        this.listeners = [];
    }
    
    setFormat(formatType, enabled) {
        if (this.state[formatType] !== enabled) {
            const oldState = { ...this.state };
            this.state[formatType] = enabled;
            this.notifyListeners(oldState, this.state, formatType);
        }
    }
    
    toggleFormat(formatType) {
        this.setFormat(formatType, !this.state[formatType]);
    }
    
    getState() {
        return { ...this.state };
    }
    
    setFormats(formats) {
        const oldState = { ...this.state };
        let changed = false;
        
        for (const [formatType, enabled] of Object.entries(formats)) {
            if (this.state[formatType] !== enabled) {
                this.state[formatType] = enabled;
                changed = true;
            }
        }
        
        if (changed) {
            this.notifyListeners(oldState, this.state, null);
        }
    }
    
    reset() {
        const oldState = { ...this.state };
        const hadFormats = Object.values(this.state).some(v => v);
        
        this.state = {
            bold: false,
            italic: false,
            underline: false,
            strikethrough: false,
            highlight: false
        };
        
        if (hadFormats) {
            this.notifyListeners(oldState, this.state, null);
        }
    }
    
    notifyListeners(oldState, newState, changedFormatType) {
        this.listeners.forEach(listener => {
            try {
                listener(oldState, newState, changedFormatType);
            } catch (error) {
                console.error('[FormatStateManager] 监听器错误:', error);
            }
        });
    }
    
    onStateChange(listener) {
        this.listeners.push(listener);
        return () => this.offStateChange(listener);
    }
    
    offStateChange(listener) {
        const index = this.listeners.indexOf(listener);
        if (index > -1) {
            this.listeners.splice(index, 1);
        }
    }
}
```

### 在 FormatManager 中使用

```javascript
class FormatManager {
    constructor() {
        // 使用 FormatStateManager 作为数据模型
        this.stateManager = new FormatStateManager();
        
        // 格式命令映射（保持不变）
        this.formatCommands = { ... };
        
        // 监听状态变化，同步到 DOM
        this.stateManager.onStateChange((oldState, newState, changedFormatType) => {
            // 当格式状态变化时，更新 DOM
            this.syncStateToDOM(newState);
        });
    }
    
    toggleFormat(formatType) {
        const selection = window.getSelection();
        if (!selection.rangeCount) return false;
        
        const range = selection.getRangeAt(0);
        const hasSelection = !range.collapsed;
        
        if (hasSelection) {
            // 有选中文本：切换选中文本的格式
            return this.toggleSelectedTextFormat(formatType, range);
        } else {
            // 无选中文本：更新数据模型状态
            this.stateManager.toggleFormat(formatType);
            // 状态变化会触发监听器，自动更新 DOM
            return true;
        }
    }
    
    // 同步状态到 DOM（根据数据模型状态更新 DOM）
    syncStateToDOM(state) {
        const selection = window.getSelection();
        if (!selection.rangeCount) return;
        
        const range = selection.getRangeAt(0);
        if (!range.collapsed) return;
        
        // 根据状态对象更新 DOM
        // 这个方法应该更简单，因为状态已经在数据模型中
    }
    
    getCurrentFormatState() {
        // 优先从数据模型查询
        const selection = window.getSelection();
        if (!selection.rangeCount) {
            return this.stateManager.getState();
        }
        
        const range = selection.getRangeAt(0);
        if (range.collapsed) {
            // 光标位置：返回数据模型状态
            return this.stateManager.getState();
        } else {
            // 有选中文本：检测选中文本的格式（需要遍历 DOM）
            return this.detectFormatFromDOM(range);
        }
    }
}
```

---

## 八、总结

轻量级数据模型的核心思想是：
1. **状态与视图分离**：格式状态存储在内存对象中，不依赖 DOM
2. **状态驱动视图**：DOM 结构根据状态对象生成
3. **简化操作逻辑**：输入时根据状态应用格式，而不是检查 DOM

这样可以：
- 解决时序问题（状态更新是同步的）
- 减少 DOM 操作（不需要频繁检查和修复）
- 提高性能（状态查询是 O(1) 操作）
- 提高可靠性（状态一致，不会出现不一致的情况）




