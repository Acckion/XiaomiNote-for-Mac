# editor.html 清理计划

## 已备份
- ✅ `editor.html.backup` - 完整备份，供未来修复参考

## 需要清理的代码块

### 1. DOMContentLoaded 事件处理（1074-1281行）
- **状态**: 已提取到 `modules/editor/editor-init.js`
- **操作**: 移除整个事件处理函数
- **保留**: 全局变量定义（1062-1071行）需要保留，但改为在 window 对象上初始化

### 2. DOMWriter 类定义（1283-2197行）
- **状态**: 已提取到 `modules/dom/dom-writer.js`
- **操作**: 移除整个类定义
- **保留**: 全局变量 `let domWriter = null;`（2200行）需要移除，因为已在模块中管理

### 3. getIndentFromElement 和 setIndentForElement 函数（2207-2257行）
- **状态**: 已提取到 `modules/core/utils.js`
- **操作**: 移除这两个函数
- **保留**: 无

### 4. window.MiNoteWebEditor 对象定义（2260-5157行）
- **状态**: 已提取到 `modules/editor/editor-api.js`
- **操作**: 移除整个对象定义
- **保留**: 无（模块会自动创建）

### 5. 其他需要检查的函数
- `handleEnterKey` 函数（5164行开始）- 检查是否还在使用
- `syncFormatState` 函数 - 检查是否已提取到 Editor Core
- `notifyContentChanged` 函数 - 检查是否已提取到 Editor Core

## 清理步骤

1. 移除 DOMContentLoaded 事件处理（保留全局变量定义，但改为 window 对象）
2. 移除 DOMWriter 类定义
3. 移除 getIndentFromElement 和 setIndentForElement 函数
4. 移除 window.MiNoteWebEditor 对象定义
5. 检查并清理其他重复代码
6. 验证功能是否正常

## 注意事项

- 保留全局变量定义，但改为在 window 对象上初始化（供模块访问）
- 保留必要的辅助函数（如果模块中未定义）
- 确保模块加载顺序正确
- 测试所有功能是否正常


