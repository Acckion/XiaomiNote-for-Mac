# 需求文档

## 简介

本功能为小米笔记 macOS 客户端添加语音文件（录音）的支持。由于小米笔记浏览器端不支持收听和上传录音（只能显示一个录音标志代表此处有录音），本功能的目标是达到与浏览器端同样的效果：能够看到此处有一个录音，并且能够删除它。后续可能扩展为支持播放和上传录音。

## 术语表

- **Sound_Element**: 小米笔记 XML 格式中的 `<sound>` 标签，表示一个语音文件
- **FileId**: 语音文件的唯一标识符，格式如 `1315204657.L-BDaSuaT0rAqtMLCX3cfw`
- **Setting_Data**: 笔记的 `setting.data` 字段，包含所有附件（图片、语音）的元数据
- **Audio_Attachment**: 用于在原生编辑器中显示语音文件的自定义附件类
- **XiaoMi_Format_Converter**: 负责 XML 与 NSAttributedString 之间转换的格式转换器
- **XML_To_HTML_Converter**: 负责 XML 与 HTML 之间转换的 JavaScript 转换器

## 需求

### 需求 1：解析语音文件 XML 元素

**用户故事：** 作为用户，我希望应用能够正确解析包含语音文件的笔记，以便我能看到笔记中存在录音。

#### 验收标准

1. WHEN 笔记内容包含 `<sound fileid="xxx" />` 标签 THEN THE XiaoMi_Format_Converter SHALL 解析该标签并提取 fileId 属性
2. WHEN 解析 `<sound>` 标签时 THEN THE XiaoMi_Format_Converter SHALL 创建一个 Audio_Attachment 对象
3. WHEN 笔记的 setting.data 包含语音文件元数据 THEN THE System SHALL 正确解析 digest、mimeType 和 fileId 字段
4. IF `<sound>` 标签缺少 fileid 属性 THEN THE XiaoMi_Format_Converter SHALL 记录警告并跳过该元素

### 需求 2：显示语音文件占位符

**用户故事：** 作为用户，我希望在编辑器中看到一个清晰的语音文件标识，以便我知道此处有一段录音。

#### 验收标准

1. THE Audio_Attachment SHALL 显示一个带有麦克风/音频图标的占位符
2. THE Audio_Attachment SHALL 显示"语音录音"或类似的文字标签
3. WHEN 用户将鼠标悬停在语音占位符上 THEN THE System SHALL 显示工具提示，包含文件 ID 信息
4. THE Audio_Attachment SHALL 支持深色和浅色模式的主题适配

### 需求 3：在 Web 编辑器中显示语音文件

**用户故事：** 作为用户，我希望在 Web 编辑器中也能看到语音文件的占位符。

#### 验收标准

1. WHEN XML 内容包含 `<sound>` 标签 THEN THE XML_To_HTML_Converter SHALL 将其转换为 HTML 占位符元素
2. THE HTML 占位符 SHALL 显示音频图标和"语音录音"文字
3. THE HTML 占位符 SHALL 使用与图片占位符一致的样式风格

### 需求 4：删除语音文件

**用户故事：** 作为用户，我希望能够删除笔记中的语音文件，以便我可以清理不需要的录音。

#### 验收标准

1. WHEN 用户选中语音占位符并按下删除键 THEN THE System SHALL 删除该语音元素
2. WHEN 用户右键点击语音占位符 THEN THE System SHALL 显示包含"删除"选项的上下文菜单
3. WHEN 语音元素被删除 THEN THE System SHALL 从笔记内容中移除对应的 `<sound>` 标签
4. WHEN 笔记保存时 THEN THE System SHALL 正确导出不包含已删除语音的 XML 内容

### 需求 5：导出语音文件 XML

**用户故事：** 作为用户，我希望保存笔记时语音文件信息能够正确保留。

#### 验收标准

1. WHEN 将 NSAttributedString 转换为 XML THEN THE XiaoMi_Format_Converter SHALL 将 Audio_Attachment 转换为 `<sound fileid="xxx" />` 格式
2. THE 导出的 XML SHALL 保留原始的 fileId 属性值
3. FOR ALL 包含语音的笔记，解析后再导出 SHALL 产生等效的 XML 内容（往返一致性）

### 需求 6：API 测试支持

**用户故事：** 作为开发者，我希望能够使用 Postman 测试语音文件相关的 API 功能。

#### 验收标准

1. THE System SHALL 支持通过 Postman 测试语音文件的解析功能
2. THE API 响应 SHALL 包含正确解析的 fileId 信息
3. THE System SHALL 提供可测试的 XML 解析端点或方法
