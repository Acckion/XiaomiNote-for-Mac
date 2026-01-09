# 原生编辑器工具栏与渲染问题修复任务清单

## 任务概览

本文档列出修复原生编辑器工具栏集成和渲染问题的所有实现任务。

---

## 任务 1：修复工具栏格式菜单集成

**关联需求**：需求 1、需求 2、需求 7

### 子任务

- [ ] 1.1 修改 `MainWindowController.showFormatMenu(_:)` 方法
  - 添加 `isUsingNativeEditor` 检查
  - 根据编辑器类型选择显示 `NativeFormatMenuView` 或 `WebFormatMenuView`
  - 获取正确的编辑器上下文（`NativeEditorContext` 或 `WebEditorContext`）

- [ ] 1.2 确保 `NotesViewModel` 提供 `nativeEditorContext` 访问
  - 检查现有实现
  - 如需要，添加公开属性

- [ ] 1.3 修改其他工具栏按钮的处理方法
  - `toggleCheckbox(_:)` - 支持原生编辑器
  - `insertHorizontalRule(_:)` - 支持原生编辑器
  - `insertAttachment(_:)` - 支持原生编辑器
  - `increaseIndent(_:)` / `decreaseIndent(_:)` - 支持原生编辑器

**涉及文件**：
- `Sources/Window/MainWindowController.swift`
- `Sources/ViewModel/NotesViewModel.swift`

---

## 任务 2：修复斜体文本渲染

**关联需求**：需求 3

### 子任务

- [ ] 2.1 改进 `NSFont.italic()` 扩展方法
  - 添加多种斜体获取策略
  - 使用 `NSFontManager` 作为备选方案
  - 添加日志记录失败情况

- [ ] 2.2 测试各种字体的斜体渲染
  - 系统字体
  - 自定义字体
  - 中文字体

**涉及文件**：
- `Sources/Service/XiaoMiFormatConverter.swift`

---

## 任务 3：修改列表格式使用附件渲染

**关联需求**：需求 5

### 子任务

- [ ] 3.1 修改 `processBulletElementToNSAttributedString` 方法
  - 使用 `BulletAttachment` 替代纯文本 "• "
  - 保留缩进级别信息
  - 正确处理内联格式

- [ ] 3.2 修改 `processOrderElementToNSAttributedString` 方法
  - 使用 `OrderAttachment` 替代纯文本 "1. "
  - 保留编号和缩进信息
  - 正确处理 `inputNumber` 逻辑

- [ ] 3.3 确保 `BulletAttachment` 和 `OrderAttachment` 正确渲染
  - 检查附件边界设置
  - 检查主题适配
  - 检查缩进级别样式

**涉及文件**：
- `Sources/Service/XiaoMiFormatConverter.swift`
- `Sources/View/NativeEditor/CustomAttachments.swift`

---

## 任务 4：更新列表格式检测

**关联需求**：需求 5

### 子任务

- [ ] 4.1 更新 `NativeEditorContext.detectListFormats()` 方法
  - 检测 `BulletAttachment` 存在
  - 检测 `OrderAttachment` 存在
  - 检测 `InteractiveCheckboxAttachment` 存在
  - 返回正确的列表状态

- [ ] 4.2 更新格式菜单状态同步
  - 确保列表按钮状态正确反映当前格式

**涉及文件**：
- `Sources/View/Bridge/NativeEditorContext.swift`
- `Sources/View/SwiftUIViews/NativeFormatMenuView.swift`

---

## 任务 5：实现列表自动续行功能

**关联需求**：需求 6

### 子任务

- [ ] 5.1 在 `FormatManager` 中添加列表续行处理
  - 检测当前行是否为列表项
  - 判断是否为空列表项
  - 创建新列表项或结束列表

- [ ] 5.2 实现无序列表续行
  - 创建新的 `BulletAttachment`
  - 保持缩进级别

- [ ] 5.3 实现有序列表续行
  - 创建新的 `OrderAttachment`
  - 自动递增编号

- [ ] 5.4 实现复选框列表续行
  - 创建新的 `InteractiveCheckboxAttachment`
  - 默认未选中状态

- [ ] 5.5 处理空列表项
  - 移除列表格式
  - 创建普通段落

**涉及文件**：
- `Sources/View/NativeEditor/FormatManager.swift`
- `Sources/View/NativeEditor/NativeEditorView.swift`（键盘事件处理）

---

## 任务 6：修复水平分割线渲染

**关联需求**：需求 4

### 子任务

- [ ] 6.1 检查 `HorizontalRuleAttachment` 渲染
  - 验证边界设置
  - 验证颜色适配
  - 验证宽度自适应

- [ ] 6.2 修复可能的渲染问题
  - 调整垂直间距
  - 确保主题切换时更新

**涉及文件**：
- `Sources/View/NativeEditor/CustomAttachments.swift`
- `Sources/Service/XiaoMiFormatConverter.swift`

---

## 任务 7：格式转换一致性

**关联需求**：需求 8

### 子任务

- [ ] 7.1 更新 `attributedStringToXML` 方法
  - 正确识别 `BulletAttachment` 并转换为 `<bullet>` 元素
  - 正确识别 `OrderAttachment` 并转换为 `<order>` 元素
  - 保留缩进和编号信息

- [ ] 7.2 添加往返转换测试
  - XML → NSAttributedString → XML
  - 验证格式保持一致

**涉及文件**：
- `Sources/Service/XiaoMiFormatConverter.swift`
- `Tests/NativeEditorTests/XiaoMiFormatConverterTests.swift`

---

## 任务 8：错误处理和日志

**关联需求**：需求 9

### 子任务

- [ ] 8.1 添加斜体字体降级日志
  - 记录无法获取斜体的字体名称
  - 记录使用的降级方案

- [ ] 8.2 添加附件创建失败处理
  - 捕获异常
  - 使用纯文本降级
  - 记录错误日志

- [ ] 8.3 添加工具栏操作错误处理
  - 检测编辑器上下文是否可用
  - 显示适当的错误提示

**涉及文件**：
- `Sources/Service/XiaoMiFormatConverter.swift`
- `Sources/Window/MainWindowController.swift`
- `Sources/View/NativeEditor/FormatManager.swift`

---

## 任务 9：测试和验证

### 子任务

- [ ] 9.1 手动测试工具栏集成
  - 原生编辑器模式下测试所有工具栏按钮
  - Web 编辑器模式下测试所有工具栏按钮
  - 测试编辑器切换

- [ ] 9.2 手动测试斜体渲染
  - 测试各种字体
  - 测试格式组合

- [ ] 9.3 手动测试列表功能
  - 测试列表渲染
  - 测试列表格式检测
  - 测试列表自动续行

- [ ] 9.4 手动测试分割线渲染
  - 测试插入分割线
  - 测试主题切换

---

## 优先级排序

1. **高优先级**（核心功能）
   - 任务 1：工具栏格式菜单集成
   - 任务 3：列表格式使用附件渲染
   - 任务 4：列表格式检测

2. **中优先级**（用户体验）
   - 任务 2：斜体文本渲染
   - 任务 5：列表自动续行
   - 任务 6：水平分割线渲染

3. **低优先级**（完善和测试）
   - 任务 7：格式转换一致性
   - 任务 8：错误处理和日志
   - 任务 9：测试和验证

---

## 预估工时

| 任务 | 预估时间 |
|------|----------|
| 任务 1 | 2-3 小时 |
| 任务 2 | 1-2 小时 |
| 任务 3 | 2-3 小时 |
| 任务 4 | 1-2 小时 |
| 任务 5 | 3-4 小时 |
| 任务 6 | 1 小时 |
| 任务 7 | 2-3 小时 |
| 任务 8 | 1-2 小时 |
| 任务 9 | 2-3 小时 |
| **总计** | **15-23 小时** |
