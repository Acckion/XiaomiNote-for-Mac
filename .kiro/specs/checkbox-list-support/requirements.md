# 需求文档

## 简介

本功能为原生编辑器添加复选框列表支持。复选框列表的行为逻辑与有序列表和无序列表完全一致，仅有两个区别：
1. 复选框可以点击切换勾选状态
2. 复选框通过工具栏按钮触发，不接入格式菜单

## 术语表

- **Checkbox_List**: 复选框列表，使用 `InteractiveCheckboxAttachment` 渲染的可交互列表项
- **ListBehaviorHandler**: 列表行为处理器，负责处理列表的光标限制、回车键和删除键行为
- **ListFormatHandler**: 列表格式处理器，负责列表的创建、切换、转换和移除
- **InteractiveCheckboxAttachment**: 交互式复选框附件，NSTextAttachment 子类
- **FormatManager**: 格式管理器，统一管理所有格式操作

## 需求

### 需求 1：复选框列表应用

**用户故事：** 作为用户，我想要通过工具栏按钮创建复选框列表，以便管理待办事项。

#### 验收标准

1. WHEN 用户点击工具栏的复选框按钮 THEN ListFormatHandler SHALL 在当前行首插入 InteractiveCheckboxAttachment
2. WHEN 当前行已经是复选框列表 THEN ListFormatHandler SHALL 移除复选框格式，恢复为普通正文
3. WHEN 当前行是有序列表或无序列表 THEN ListFormatHandler SHALL 先移除原列表格式，再应用复选框格式
4. WHEN 应用复选框格式 THEN ListFormatHandler SHALL 设置 listType 属性为 .checkbox
5. WHEN 应用复选框格式 THEN ListFormatHandler SHALL 设置正确的段落样式（缩进）

### 需求 2：复选框列表回车键行为

**用户故事：** 作为用户，我想要在复选框列表项中按回车键时自动创建新的复选框项，以便快速添加待办事项。

#### 验收标准

1. WHEN 用户在有内容的复选框列表项中按回车键 THEN ListBehaviorHandler SHALL 在光标位置分割文本
2. WHEN 分割文本后 THEN ListBehaviorHandler SHALL 创建新的复选框列表项，继承缩进级别
3. WHEN 创建新复选框列表项 THEN ListBehaviorHandler SHALL 设置新项为未勾选状态
4. WHEN 用户在空复选框列表项中按回车键 THEN ListBehaviorHandler SHALL 取消复选框格式，不换行
5. WHEN 取消复选框格式后 THEN ListBehaviorHandler SHALL 将当前行转换为普通正文

### 需求 3：复选框列表删除键行为

**用户故事：** 作为用户，我想要在复选框列表项开头按删除键时能够合并或取消格式，以便灵活编辑待办事项。

#### 验收标准

1. WHEN 光标在复选框列表项内容起始位置按删除键 THEN ListBehaviorHandler SHALL 执行合并或取消操作
2. WHEN 复选框列表项为空 THEN ListBehaviorHandler SHALL 只删除复选框标记，保留空行
3. WHEN 复选框列表项有内容 THEN ListBehaviorHandler SHALL 将内容合并到上一行
4. WHEN 合并到上一行后 THEN ListBehaviorHandler SHALL 正确更新光标位置

### 需求 4：复选框光标限制

**用户故事：** 作为用户，我想要光标不能移动到复选框标记区域内，以便保护列表结构。

#### 验收标准

1. WHEN 光标尝试移动到复选框标记区域 THEN ListBehaviorHandler SHALL 将光标调整到内容起始位置
2. WHEN 检测光标位置 THEN ListBehaviorHandler SHALL 正确识别复选框附件的范围
3. WHEN 用户点击复选框区域 THEN 系统 SHALL 切换勾选状态而不是移动光标

### 需求 5：复选框勾选状态切换

**用户故事：** 作为用户，我想要点击复选框切换勾选状态，以便标记待办事项的完成情况。

#### 验收标准

1. WHEN 用户点击复选框附件 THEN InteractiveCheckboxAttachment SHALL 切换 isChecked 状态
2. WHEN 勾选状态切换后 THEN InteractiveCheckboxAttachment SHALL 更新视觉显示（☐ ↔ ☑）
3. WHEN 勾选状态切换后 THEN 系统 SHALL 保持光标位置不变
4. WHEN 勾选状态切换后 THEN 系统 SHALL 触发内容变化通知以便保存

### 需求 6：复选框 XML 格式转换

**用户故事：** 作为系统，我需要正确解析和导出复选框的 XML 格式，以便与小米笔记云端同步。

#### 验收标准

1. WHEN 解析 `<input type="checkbox" indent="N" level="M" />` THEN XiaoMiFormatConverter SHALL 创建 InteractiveCheckboxAttachment
2. WHEN 解析带有 `checked="true"` 属性的复选框 THEN XiaoMiFormatConverter SHALL 设置 isChecked 为 true
3. WHEN 导出复选框列表 THEN XiaoMiFormatConverter SHALL 生成正确的 XML 格式
4. WHEN 复选框为勾选状态 THEN XiaoMiFormatConverter SHALL 在 XML 中包含 `checked="true"` 属性

### 需求 7：复选框与其他格式的互斥

**用户故事：** 作为用户，我想要复选框列表与标题格式互斥，以便保持格式的一致性。

#### 验收标准

1. WHEN 应用复选框格式到标题行 THEN ListFormatHandler SHALL 先移除标题格式
2. WHEN 应用标题格式到复选框行 THEN ListFormatHandler SHALL 先移除复选框格式
3. WHEN 移除标题格式后 THEN ListFormatHandler SHALL 保留字体特性（加粗、斜体等）
4. WHEN 复选框行应用格式 THEN ListFormatHandler SHALL 使用正文字体大小（14pt）
