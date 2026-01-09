# 原生编辑器格式菜单修复需求文档

## 简介

本文档定义了修复原生富文本编辑器格式菜单功能的需求。当前原生编辑器的格式菜单存在两个关键问题：1) 使用工具栏中的格式菜单无法修改文本格式；2) 移动光标时，格式菜单中的选项应该勾选到当前光标所在处文本的状态，但目前状态同步不正确。

## 术语表

- **Format_Menu**: 工具栏中的格式菜单，提供文本格式选项
- **Native_Editor**: 基于 SwiftUI TextEditor、NSTextView 和自定义渲染的原生编辑器
- **Format_State**: 当前光标位置或选中文本的格式状态
- **Toolbar_Button**: 格式菜单中的格式按钮
- **Cursor_Position**: 光标在文本中的位置
- **Selection_Range**: 用户选中的文本范围
- **Format_Application**: 将格式应用到文本的过程
- **State_Synchronization**: 格式菜单状态与编辑器实际格式状态的同步

## 需求

### 需求 1：格式菜单格式应用功能

**用户故事：** 作为用户，我希望点击格式菜单中的格式按钮能够实际修改选中文本或光标位置的文本格式，就像在其他文本编辑器中一样。

#### 验收标准

1. WHEN 用户选中文本并点击加粗按钮 THEN THE Native_Editor SHALL 切换选中文本的加粗状态
2. WHEN 用户选中文本并点击斜体按钮 THEN THE Native_Editor SHALL 切换选中文本的斜体状态
3. WHEN 用户选中文本并点击下划线按钮 THEN THE Native_Editor SHALL 切换选中文本的下划线状态
4. WHEN 用户选中文本并点击删除线按钮 THEN THE Native_Editor SHALL 切换选中文本的删除线状态
5. WHEN 用户选中文本并点击高亮按钮 THEN THE Native_Editor SHALL 切换选中文本的高亮状态
6. WHEN 用户点击标题格式按钮 THEN THE Native_Editor SHALL 将当前行或选中行设置为对应的标题格式
7. WHEN 用户点击对齐按钮 THEN THE Native_Editor SHALL 设置当前段落的对齐方式
8. WHEN 用户点击列表按钮 THEN THE Native_Editor SHALL 切换当前行的列表格式

### 需求 2：格式菜单状态同步功能

**用户故事：** 作为用户，我希望移动光标时格式菜单中的按钮状态能够准确反映当前光标位置文本的格式状态，这样我就能知道当前位置有哪些格式。

#### 验收标准

1. WHEN 光标移动到加粗文本位置 THEN THE Format_Menu SHALL 显示加粗按钮为激活状态
2. WHEN 光标移动到斜体文本位置 THEN THE Format_Menu SHALL 显示斜体按钮为激活状态
3. WHEN 光标移动到下划线文本位置 THEN THE Format_Menu SHALL 显示下划线按钮为激活状态
4. WHEN 光标移动到删除线文本位置 THEN THE Format_Menu SHALL 显示删除线按钮为激活状态
5. WHEN 光标移动到高亮文本位置 THEN THE Format_Menu SHALL 显示高亮按钮为激活状态
6. WHEN 光标移动到标题文本位置 THEN THE Format_Menu SHALL 显示对应标题级别按钮为激活状态
7. WHEN 光标移动到居中对齐段落 THEN THE Format_Menu SHALL 显示居中按钮为激活状态
8. WHEN 光标移动到右对齐段落 THEN THE Format_Menu SHALL 显示右对齐按钮为激活状态
9. WHEN 光标移动到列表项 THEN THE Format_Menu SHALL 显示对应列表类型按钮为激活状态
10. WHEN 光标移动到引用块 THEN THE Format_Menu SHALL 显示引用按钮为激活状态

### 需求 3：格式菜单响应性能

**用户故事：** 作为用户，我希望格式菜单的响应速度足够快，不会影响我的编辑体验。

#### 验收标准

1. WHEN 用户点击格式按钮 THEN THE Native_Editor SHALL 在 50ms 内开始应用格式
2. WHEN 光标位置改变 THEN THE Format_Menu SHALL 在 100ms 内更新按钮状态
3. WHEN 用户快速移动光标 THEN THE Format_Menu SHALL 正确处理状态更新而不出现闪烁
4. WHEN 用户连续点击多个格式按钮 THEN THE Native_Editor SHALL 正确应用所有格式而不丢失操作

### 需求 4：格式菜单错误处理

**用户故事：** 作为用户，我希望当格式应用失败时能够得到适当的反馈，而不是静默失败。

#### 验收标准

1. WHEN 格式应用失败 THEN THE System SHALL 记录错误日志并保持界面状态一致
2. WHEN 状态同步失败 THEN THE System SHALL 重新检测格式状态并更新界面
3. WHEN 编辑器处于不可编辑状态 THEN THE Format_Menu SHALL 禁用所有格式按钮
4. WHEN 没有选中文本且格式不适用于光标位置 THEN THE System SHALL 提供适当的视觉反馈

### 需求 5：格式菜单与键盘快捷键一致性

**用户故事：** 作为用户，我希望格式菜单的行为与键盘快捷键的行为保持一致。

#### 验收标准

1. WHEN 用户使用 Cmd+B 快捷键 THEN THE Format_Menu SHALL 同步更新加粗按钮状态
2. WHEN 用户使用 Cmd+I 快捷键 THEN THE Format_Menu SHALL 同步更新斜体按钮状态
3. WHEN 用户使用 Cmd+U 快捷键 THEN THE Format_Menu SHALL 同步更新下划线按钮状态
4. WHEN 用户通过格式菜单应用格式 THEN THE System SHALL 与快捷键应用的格式效果完全相同
5. WHEN 用户撤销格式操作 THEN THE Format_Menu SHALL 正确更新按钮状态以反映撤销后的状态

### 需求 6：格式菜单多选文本处理

**用户故事：** 作为用户，我希望选中包含不同格式的文本时，格式菜单能够正确显示混合状态。

#### 验收标准

1. WHEN 用户选中部分加粗部分非加粗的文本 THEN THE Format_Menu SHALL 显示加粗按钮为部分激活状态或根据主要格式显示
2. WHEN 用户选中包含多种格式的文本 THEN THE Format_Menu SHALL 显示所有适用格式的按钮状态
3. WHEN 用户对混合格式文本应用格式 THEN THE Native_Editor SHALL 将格式应用到整个选中范围
4. WHEN 选中文本跨越多个段落 THEN THE Format_Menu SHALL 正确处理段落级格式（如对齐方式）

### 需求 7：格式菜单特殊元素处理

**用户故事：** 作为用户，我希望光标位于特殊元素（如复选框、分割线、图片）附近时，格式菜单能够正确处理。

#### 验收标准

1. WHEN 光标位于复选框列表项 THEN THE Format_Menu SHALL 显示复选框按钮为激活状态
2. WHEN 光标位于分割线附近 THEN THE Format_Menu SHALL 禁用不适用的格式按钮
3. WHEN 光标位于图片附近 THEN THE Format_Menu SHALL 显示适当的格式选项
4. WHEN 用户在特殊元素上应用格式 THEN THE System SHALL 根据元素类型决定是否应用格式

### 需求 8：格式菜单调试和监控

**用户故事：** 作为开发者，我希望能够调试格式菜单的状态同步问题，并监控其性能。

#### 验收标准

1. WHEN 启用调试模式 THEN THE System SHALL 输出格式状态变化的详细日志
2. WHEN 格式应用失败 THEN THE System SHALL 记录失败原因和上下文信息
3. WHEN 状态同步出现延迟 THEN THE System SHALL 记录性能指标
4. WHEN 用户报告格式问题 THEN THE System SHALL 提供足够的诊断信息
5. WHEN 测试格式功能 THEN THE System SHALL 提供自动化测试支持