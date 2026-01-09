# 原生编辑器工具栏与渲染问题修复需求文档

## 简介

本文档定义了修复原生富文本编辑器工具栏集成和渲染问题的需求。当前原生编辑器存在以下关键问题：
1. 工具栏按钮（格式菜单、复选框、分割线、附件）未连接到原生编辑器
2. 斜体文本无法正确渲染
3. 水平分割线渲染存在问题
4. 列表格式使用纯文本而非附件，导致无法检测列表格式和自动续行

## 术语表

- **Native_Editor**: 基于 NSTextView 和自定义渲染的原生编辑器
- **Web_Editor**: 基于 WKWebView 的 Web 编辑器
- **Toolbar_Button**: 主窗口工具栏中的格式按钮
- **Format_Menu**: 工具栏中的格式菜单弹出窗口
- **BulletAttachment**: 无序列表项目符号附件
- **OrderAttachment**: 有序列表编号附件
- **HorizontalRuleAttachment**: 水平分割线附件
- **InteractiveCheckboxAttachment**: 交互式复选框附件
- **XiaoMiFormatConverter**: 小米笔记 XML 格式与 NSAttributedString 的转换器

## 需求

### 需求 1：工具栏格式菜单与原生编辑器集成

**用户故事：** 作为用户，我希望在使用原生编辑器时，点击工具栏中的格式菜单按钮能够显示原生编辑器的格式菜单，而不是 Web 编辑器的格式菜单。

#### 验收标准

1. WHEN 用户使用原生编辑器并点击工具栏格式菜单按钮 THEN THE System SHALL 显示 NativeFormatMenuView 而非 WebFormatMenuView
2. WHEN 用户使用 Web 编辑器并点击工具栏格式菜单按钮 THEN THE System SHALL 显示 WebFormatMenuView
3. WHEN 用户在原生编辑器中通过格式菜单应用格式 THEN THE Native_Editor SHALL 正确应用所选格式
4. WHEN 用户切换编辑器类型 THEN THE Toolbar_Button SHALL 自动适配对应的编辑器上下文

### 需求 2：工具栏其他按钮与原生编辑器集成

**用户故事：** 作为用户，我希望工具栏中的所有格式相关按钮（复选框、分割线、附件等）在原生编辑器中都能正常工作。

#### 验收标准

1. WHEN 用户使用原生编辑器并点击复选框按钮 THEN THE Native_Editor SHALL 在当前位置插入交互式复选框
2. WHEN 用户使用原生编辑器并点击分割线按钮 THEN THE Native_Editor SHALL 在当前位置插入水平分割线
3. WHEN 用户使用原生编辑器并点击附件按钮 THEN THE System SHALL 显示附件选择对话框
4. WHEN 用户使用原生编辑器并点击撤销/重做按钮 THEN THE Native_Editor SHALL 执行对应的撤销/重做操作
5. WHEN 用户使用原生编辑器并点击缩进按钮 THEN THE Native_Editor SHALL 调整当前行的缩进级别

### 需求 3：斜体文本正确渲染

**用户故事：** 作为用户，我希望在原生编辑器中能够正确显示斜体文本，就像在其他文本编辑器中一样。

#### 验收标准

1. WHEN XML 中包含斜体格式的文本 THEN THE Native_Editor SHALL 使用正确的斜体字体渲染该文本
2. WHEN 系统字体没有斜体变体 THEN THE System SHALL 使用仿斜体（oblique）或其他可用的斜体字体
3. WHEN 用户应用斜体格式 THEN THE Native_Editor SHALL 立即显示斜体效果
4. WHEN 斜体文本与其他格式（粗体、下划线等）组合 THEN THE Native_Editor SHALL 正确显示组合格式

### 需求 4：水平分割线正确渲染

**用户故事：** 作为用户，我希望在原生编辑器中能够正确显示水平分割线，具有适当的样式和间距。

#### 验收标准

1. WHEN XML 中包含 `<hr>` 元素 THEN THE Native_Editor SHALL 渲染为可见的水平分割线
2. WHEN 分割线渲染时 THEN THE HorizontalRuleAttachment SHALL 具有适当的垂直间距
3. WHEN 分割线渲染时 THEN THE HorizontalRuleAttachment SHALL 根据容器宽度自适应
4. WHEN 主题切换（深色/浅色模式）THEN THE HorizontalRuleAttachment SHALL 更新颜色以适配当前主题

### 需求 5：列表格式使用附件渲染

**用户故事：** 作为用户，我希望无序列表和有序列表使用专用附件渲染，而不是纯文本符号，这样可以支持列表格式检测和自动续行。

#### 验收标准

1. WHEN XML 中包含 `<bullet>` 元素 THEN THE XiaoMiFormatConverter SHALL 创建 BulletAttachment 而非纯文本 "• "
2. WHEN XML 中包含 `<order>` 元素 THEN THE XiaoMiFormatConverter SHALL 创建 OrderAttachment 而非纯文本 "1. "
3. WHEN 光标位于列表项 THEN THE NativeEditorContext.detectListFormats() SHALL 正确检测列表类型
4. WHEN 用户在列表项末尾按 Enter THEN THE Native_Editor SHALL 自动创建新的列表项
5. WHEN 用户在空列表项按 Enter THEN THE Native_Editor SHALL 结束列表并创建普通段落
6. WHEN 列表项有缩进级别 THEN THE BulletAttachment/OrderAttachment SHALL 根据缩进级别调整显示样式

### 需求 6：列表自动续行功能

**用户故事：** 作为用户，我希望在列表项末尾按 Enter 时能够自动创建新的列表项，提高编辑效率。

#### 验收标准

1. WHEN 用户在无序列表项末尾按 Enter THEN THE Native_Editor SHALL 在下一行创建新的无序列表项
2. WHEN 用户在有序列表项末尾按 Enter THEN THE Native_Editor SHALL 在下一行创建编号递增的有序列表项
3. WHEN 用户在复选框列表项末尾按 Enter THEN THE Native_Editor SHALL 在下一行创建新的未选中复选框
4. WHEN 用户在空列表项按 Enter THEN THE Native_Editor SHALL 移除列表格式并创建普通段落
5. WHEN 用户在列表项中间按 Enter THEN THE Native_Editor SHALL 分割列表项并保持列表格式

### 需求 7：编辑器类型检测准确性

**用户故事：** 作为开发者，我希望系统能够准确检测当前使用的编辑器类型，以便正确路由工具栏操作。

#### 验收标准

1. WHEN 原生编辑器处于活动状态 THEN THE isUsingNativeEditor SHALL 返回 true
2. WHEN Web 编辑器处于活动状态 THEN THE isUsingNativeEditor SHALL 返回 false
3. WHEN 编辑器类型切换 THEN THE System SHALL 立即更新 isUsingNativeEditor 状态
4. WHEN 工具栏按钮被点击 THEN THE System SHALL 根据 isUsingNativeEditor 状态路由到正确的处理器

### 需求 8：格式转换一致性

**用户故事：** 作为用户，我希望在原生编辑器中编辑的内容能够正确保存为小米笔记 XML 格式，并在重新加载时保持一致。

#### 验收标准

1. WHEN 用户在原生编辑器中创建列表 THEN THE System SHALL 将列表保存为正确的 XML 格式
2. WHEN 用户在原生编辑器中插入分割线 THEN THE System SHALL 将分割线保存为 `<hr>` 元素
3. WHEN 用户在原生编辑器中应用斜体 THEN THE System SHALL 将斜体保存为正确的 XML 格式
4. WHEN 保存的 XML 重新加载 THEN THE Native_Editor SHALL 显示与保存前相同的格式

### 需求 9：错误处理和降级

**用户故事：** 作为用户，我希望当格式渲染或应用失败时，系统能够优雅地处理并提供反馈。

#### 验收标准

1. WHEN 斜体字体不可用 THEN THE System SHALL 使用备用字体或仿斜体
2. WHEN 附件创建失败 THEN THE System SHALL 记录错误并使用纯文本降级显示
3. WHEN 格式转换失败 THEN THE System SHALL 保留原始内容并记录错误
4. WHEN 工具栏操作失败 THEN THE System SHALL 显示适当的错误提示
