# 需求文档

## 简介

修复格式菜单中段落样式显示和应用不正确的问题。当用户输入正文内容或将标题转换为正文时，格式菜单应该正确显示"正文"，并且内容应该使用正文的字体大小（13pt）。

## 术语表

- **Format_Menu**: 格式菜单，包含段落样式选项（大标题、二级标题、三级标题、正文等）
- **Paragraph_Style**: 段落样式，表示文本的层级和类型
- **Heading_Level**: 标题级别，通过自定义属性 `headingLevel` 标记
- **Body_Text**: 正文，默认的段落样式，字体大小为 13pt
- **Format_Detection**: 格式检测，根据文本属性判断当前格式状态
- **Menu_State**: 菜单状态，控制菜单项的勾选和启用状态
- **Font_Size_Threshold**: 字体大小阈值，用于通过字体大小判断段落样式

## 需求

### 需求 1: 正文格式检测和应用

**用户故事:** 作为用户，我希望在输入正文内容或将标题转换为正文时，格式菜单能正确显示"正文"状态，并且文本使用正文字体大小（13pt），这样我就能清楚地知道当前的段落样式。

#### 验收标准

1. WHEN 用户在编辑器中输入文本且没有应用任何标题格式 THEN THE Format_Detection SHALL 将段落样式识别为 Body_Text
2. WHEN 文本没有 Heading_Level 自定义属性 AND 字体大小为 13pt THEN THE Format_Detection SHALL 将段落样式识别为 Body_Text
3. WHEN 文本没有 Heading_Level 自定义属性 AND 字体大小小于 15pt THEN THE Format_Detection SHALL 将段落样式识别为 Body_Text
4. WHEN Format_Detection 检测到 Body_Text THEN THE Format_Menu SHALL 显示"正文"为选中状态
5. WHEN Format_Detection 检测到 Body_Text THEN THE Format_Menu SHALL 不显示任何标题选项为选中状态
6. WHEN 用户通过格式菜单应用"正文"格式 THEN THE 系统 SHALL 将文本字体大小设置为 13pt
7. WHEN 用户将标题转换为正文 THEN THE 系统 SHALL 移除 Heading_Level 属性 AND 将字体大小设置为 13pt

### 需求 2: 标题格式检测优先级

**用户故事:** 作为用户，我希望系统能准确区分标题和正文，避免将正文误判为标题，这样我就能正确管理文档结构。

#### 验收标准

1. WHEN 检测段落样式时 THEN THE Format_Detection SHALL 优先检查 Heading_Level 自定义属性
2. WHEN Heading_Level 属性存在且值为 1/2/3 THEN THE Format_Detection SHALL 将段落样式识别为对应的标题级别
3. WHEN Heading_Level 属性不存在 THEN THE Format_Detection SHALL 仅在字体大小明显大于正文时才识别为标题
4. WHEN 字体大小为 13pt 或 14pt THEN THE Format_Detection SHALL 将段落样式识别为 Body_Text
5. WHEN 字体大小小于 15pt THEN THE Format_Detection SHALL 将段落样式识别为 Body_Text

### 需求 3: 格式菜单状态同步

**用户故事:** 作为用户，我希望格式菜单能实时反映当前光标位置的段落样式，这样我就能快速了解和修改格式。

#### 验收标准

1. WHEN 光标位置改变时 THEN THE Format_Menu SHALL 更新段落样式的勾选状态
2. WHEN 段落样式为 Body_Text THEN THE Format_Menu SHALL 仅勾选"正文"菜单项
3. WHEN 段落样式为 Heading1/2/3 THEN THE Format_Menu SHALL 仅勾选对应的标题菜单项
4. WHEN 段落样式变化时 THEN THE Format_Menu SHALL 在 50ms 内完成状态更新
5. WHEN 用户通过菜单切换段落样式时 THEN THE Format_Detection SHALL 立即反映新的样式状态

### 需求 4: 字体大小阈值调整

**用户故事:** 作为开发者，我希望调整字体大小检测阈值和标题字体大小，避免将正文误判为标题，这样系统就能更准确地识别段落样式。

#### 验收标准

1. WHEN 字体大小 >= 20pt THEN THE Format_Detection SHALL 将段落样式识别为大标题
2. WHEN 字体大小 >= 17pt AND < 20pt THEN THE Format_Detection SHALL 将段落样式识别为二级标题
3. WHEN 字体大小 >= 15pt AND < 17pt THEN THE Format_Detection SHALL 将段落样式识别为三级标题
4. WHEN 字体大小 < 15pt THEN THE Format_Detection SHALL 将段落样式识别为 Body_Text
5. WHEN Heading_Level 属性存在时 THEN THE Format_Detection SHALL 忽略字体大小阈值检测
6. WHEN 应用三级标题格式时 THEN THE 系统 SHALL 将字体大小设置为 16pt
7. WHEN 应用正文格式时 THEN THE 系统 SHALL 将字体大小设置为 13pt

### 需求 5: 默认段落样式处理

**用户故事:** 作为用户，我希望新输入的内容默认为正文样式（13pt），这样我就能直接开始写作而不需要手动设置格式。

#### 验收标准

1. WHEN 用户在空白编辑器中输入文本 THEN THE Format_Detection SHALL 将段落样式识别为 Body_Text AND 字体大小为 13pt
2. WHEN 用户在正文段落末尾按回车键 THEN THE 新段落 SHALL 继承 Body_Text 样式 AND 字体大小为 13pt
3. WHEN 用户在标题段落末尾按回车键 THEN THE 新段落 SHALL 恢复为 Body_Text 样式 AND 字体大小为 13pt
4. WHEN 文本没有任何格式属性时 THEN THE Format_Detection SHALL 将段落样式识别为 Body_Text
5. WHEN Format_Detection 无法确定段落样式时 THEN THE Format_Detection SHALL 默认返回 Body_Text
