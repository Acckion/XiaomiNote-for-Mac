# Checkbox 光标限制修复

## 问题描述

复选框（checkbox）列表的光标可以移动到勾选框的左侧，这与无序列表和有序列表的行为不一致。

## 修复内容

### 1. 更新 `ListBehaviorHandler.swift`

#### 1.1 增强 `isInListMarkerArea` 方法
- 添加了明确的注释说明该方法支持 checkbox
- 确保 checkbox 附件被正确识别为列表标记区域

#### 1.2 增强 `getContentStartPosition` 方法
- 添加了明确的注释说明支持 checkbox
- 确保正确查找 `InteractiveCheckboxAttachment` 并返回其后的位置

#### 1.3 增强 `adjustCursorPosition` 方法
- 添加了调试日志，便于追踪光标位置调整
- 明确说明该方法处理 checkbox

### 2. 更新 `NativeEditorView.swift`

#### 2.1 增强 `moveLeft` 方法
- 添加了注释说明支持 checkbox
- 添加了调试日志

#### 2.2 增强 `moveToBeginningOfLine` 方法
- 添加了注释说明支持 checkbox
- 添加了调试日志

#### 2.3 增强 `moveWordLeft` 方法
- 添加了注释说明支持 checkbox
- 添加了调试日志

### 3. 更新 `AttachmentSelectionManager.swift`

#### 3.1 增强 `isSelectableAttachment` 方法
- 添加了注释说明 checkbox 不使用高亮机制
- 明确说明列表类型的光标限制由 `ListBehaviorHandler` 处理

### 4. 新增测试文件

创建了 `CheckboxCursorRestrictionTests.swift`，包含以下测试用例：

1. **testIsInCheckboxMarkerArea** - 测试检测复选框标记区域
2. **testGetCheckboxContentStartPosition** - 测试获取复选框内容起始位置
3. **testAdjustCursorPositionForCheckbox** - 测试调整光标位置
4. **testGetCheckboxListItemInfo** - 测试获取复选框列表项信息
5. **testIsEmptyCheckboxListItem** - 测试检测空复选框列表项
6. **testMultipleCheckboxLines** - 测试多行复选框列表的光标限制
7. **testCheckboxVsOtherListTypes** - 测试复选框与其他列表类型的区分

## 技术实现

### 核心逻辑

1. **光标位置检测**：通过 `ListBehaviorHandler.isInListMarkerArea` 检测光标是否在 checkbox 标记区域内
2. **内容起始位置**：通过 `ListBehaviorHandler.getContentStartPosition` 获取 checkbox 后的内容起始位置
3. **光标位置调整**：通过 `ListBehaviorHandler.adjustCursorPosition` 将光标调整到内容起始位置
4. **键盘事件拦截**：在 `NativeEditorView` 中重写 `moveLeft`、`moveToBeginningOfLine`、`moveWordLeft` 等方法

### 关键代码路径

```
用户按下左方向键
    ↓
NativeEditorView.moveLeft()
    ↓
检查是否在列表项内容起始位置
    ↓
如果是，跳到上一行末尾
    ↓
否则，执行默认左移
    ↓
检查移动后位置是否在标记区域内
    ↓
如果是，调整到内容起始位置
```

## 验证方法

1. 创建一个复选框列表项
2. 将光标放在文本内容的开头
3. 按下左方向键
4. 验证光标是否跳到上一行末尾，而不是移动到 checkbox 左侧

## 相关文件

- `Sources/View/NativeEditor/Format/ListBehaviorHandler.swift`
- `Sources/View/NativeEditor/Core/NativeEditorView.swift`
- `Sources/View/NativeEditor/Attachment/AttachmentSelectionManager.swift`
- `Tests/NativeEditorTests/CheckboxCursorRestrictionTests.swift`

## 注意事项

1. 该修复与无序列表和有序列表的光标限制逻辑保持一致
2. 所有列表类型（bullet、ordered、checkbox）都使用相同的光标限制机制
3. 调试日志已添加，便于追踪问题
