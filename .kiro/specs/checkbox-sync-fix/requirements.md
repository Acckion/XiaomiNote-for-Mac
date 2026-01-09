# 需求文档：复选框同步修复

## 简介

本文档定义了修复原生编辑器中复选框（checkbox）同步问题的需求。当前实现使用 Unicode 字符（☐）来表示复选框，这会导致：
1. 同步到小米笔记云端时格式错误
2. 无法点击勾选复选框

需要改为使用 `InteractiveCheckboxAttachment`（NSTextAttachment 子类）来正确渲染和转换复选框。NSTextAttachment 在文本中会占用一个特殊的对象替换字符（`\u{FFFC}`），可以显示自定义图像并支持点击交互。

## 术语表

- **InteractiveCheckboxAttachment**: 自定义 NSTextAttachment 子类，用于渲染可交互的复选框
- **NSTextAttachment**: AppKit 中用于在文本中嵌入自定义对象的类，占用一个特殊字符位置
- **Object_Replacement_Character**: Unicode 字符 `\u{FFFC}`，NSTextAttachment 在文本中的占位符
- **XiaoMiFormatConverter**: 负责 AttributedString/NSAttributedString 与小米笔记 XML 格式之间转换的组件
- **CustomRenderer**: 自定义渲染器，用于创建复选框、分割线等特殊元素的附件
- **XiaoMi_XML**: 小米笔记使用的 XML 格式，复选框格式为 `<input type="checkbox" indent="1" level="3" />内容`

## 技术方案概述

使用 `NSTextAttachment` 作为复选框的实现方式：
1. **显示**：NSTextAttachment 可以渲染自定义图像（复选框图标）
2. **交互**：通过 NSTextView 的鼠标事件检测点击位置，判断是否点击了复选框附件
3. **存储**：在 NSAttributedString 中，附件占用一个 `\u{FFFC}` 字符位置
4. **转换**：导出时检测 `InteractiveCheckboxAttachment` 类型，生成正确的 XML 格式

## 需求

### 需求 1：复选框 XML 解析修复

**用户故事：** 作为用户，我希望从小米笔记同步下来的复选框能够正确显示为可交互的复选框图标，而不是 Unicode 字符。

#### 验收标准

1. WHEN 解析包含 `<input type="checkbox">` 的 XML THEN XiaoMiFormatConverter SHALL 创建 InteractiveCheckboxAttachment 附件并插入到 NSAttributedString 中
2. WHEN 创建复选框附件 THEN 系统 SHALL 正确提取 indent 和 level 属性并设置到附件对象
3. WHEN 复选框附件创建完成 THEN 系统 SHALL 将复选框后的文本内容作为普通文本追加到同一行
4. WHEN 显示复选框 THEN 系统 SHALL 使用 Apple Notes 风格的复选框图标（通过 NSTextAttachment 的 image 方法渲染）

### 需求 2：复选框 XML 导出修复

**用户故事：** 作为用户，我希望在原生编辑器中编辑的复选框能够正确同步到小米笔记云端，保持正确的 XML 格式。

#### 验收标准

1. WHEN 导出包含 InteractiveCheckboxAttachment 的内容 THEN XiaoMiFormatConverter SHALL 生成 `<input type="checkbox" indent="N" level="M" />内容` 格式
2. WHEN 复选框后有文本内容 THEN 系统 SHALL 将文本内容追加在复选框 XML 标签之后（不使用 `<text>` 包裹）
3. WHEN 复选框有缩进 THEN 系统 SHALL 正确设置 indent 属性值
4. WHEN 复选框有级别 THEN 系统 SHALL 正确设置 level 属性值（默认为 3）

### 需求 3：复选框往返转换一致性

**用户故事：** 作为用户，我希望复选框在多次同步后保持格式一致，不会出现格式丢失或变形。

#### 验收标准

1. WHEN 复选框 XML 经过解析和导出往返转换 THEN 系统 SHALL 生成等价的 XML 格式
2. WHEN 复选框包含富文本内容 THEN 系统 SHALL 正确保留富文本格式标签
3. IF 转换过程中出现错误 THEN 系统 SHALL 记录错误日志并保留原始内容

### 需求 4：复选框交互功能

**用户故事：** 作为用户，我希望能够点击复选框来切换选中状态，并且状态变化能够正确反映在编辑器中。

#### 验收标准

1. WHEN 用户点击复选框附件区域 THEN 系统 SHALL 切换复选框的选中状态
2. WHEN 复选框状态改变 THEN 系统 SHALL 立即更新复选框的视觉显示（重新渲染附件图像）
3. WHEN 复选框被选中 THEN 系统 SHALL 显示蓝色填充的勾选图标
4. WHEN 复选框未选中 THEN 系统 SHALL 显示空心的方框图标
5. WHEN 导出到 XML THEN 系统 SHALL 不保存选中状态（符合小米笔记规范，选中状态仅在本地显示）

### 需求 5：复选框插入功能

**用户故事：** 作为用户，我希望能够通过工具栏按钮在当前光标位置插入新的复选框。

#### 验收标准

1. WHEN 用户点击工具栏的复选框按钮 THEN 系统 SHALL 在当前光标位置插入一个 InteractiveCheckboxAttachment
2. WHEN 插入复选框 THEN 系统 SHALL 默认设置为未选中状态
3. WHEN 插入复选框 THEN 系统 SHALL 将光标移动到复选框之后，方便用户输入文本内容
