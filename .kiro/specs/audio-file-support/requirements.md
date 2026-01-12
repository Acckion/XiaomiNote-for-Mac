# 需求文档

## 简介

本功能为小米笔记 macOS 客户端添加完整的语音文件（录音）支持，包括：
- 解析和显示语音文件占位符
- 下载和播放语音文件
- 录制和上传新的语音文件
- 删除语音文件

## 术语表

- **Sound_Element**: 小米笔记 XML 格式中的 `<sound>` 标签，表示一个语音文件
- **FileId**: 语音文件的唯一标识符，格式如 `1315204657.L-BDaSuaT0rAqtMLCX3cfw`
- **Setting_Data**: 笔记的 `setting.data` 字段，包含所有附件（图片、语音）的元数据
- **Audio_Attachment**: 用于在原生编辑器中显示语音文件的自定义附件类
- **Audio_Player**: 负责播放语音文件的播放器组件
- **Audio_Recorder**: 负责录制语音的录音组件
- **XiaoMi_Format_Converter**: 负责 XML 与 NSAttributedString 之间转换的格式转换器
- **XML_To_HTML_Converter**: 负责 XML 与 HTML 之间转换的 JavaScript 转换器
- **MiNote_Service**: 负责与小米笔记 API 交互的服务类

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

### 需求 12：在 Web 编辑器中插入语音录音

**用户故事：** 作为用户，我希望在使用 Web 编辑器时也能插入语音录音。

#### 验收标准

1. WHEN 用户在 Web 编辑器模式下点击录音按钮 THEN THE System SHALL 显示录音界面
2. WHEN 录音上传成功 THEN THE System SHALL 在 Web 编辑器中插入语音占位符 HTML
3. THE 插入的 HTML SHALL 包含正确的 fileId 属性
4. WHEN 笔记保存时 THEN THE HTML_To_XML_Converter SHALL 将语音占位符转换为 `<sound>` 标签

### 需求 13：在 Web 编辑器中播放语音

**用户故事：** 作为用户，我希望在 Web 编辑器中也能播放语音录音。

#### 验收标准

1. WHEN 用户点击 Web 编辑器中的语音占位符 THEN THE System SHALL 显示播放控件
2. THE 播放控件 SHALL 支持播放、暂停、进度跳转功能
3. THE System SHALL 复用原生编辑器的 AudioPlayerService 进行播放
4. WHEN 播放状态变化 THEN THE Web 编辑器 SHALL 更新占位符的视觉状态

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

### 需求 6：下载语音文件

**用户故事：** 作为用户，我希望能够下载语音文件到本地，以便我可以播放录音。

#### 验收标准

1. WHEN 用户点击语音占位符的播放按钮 THEN THE System SHALL 从服务器下载语音文件
2. THE MiNote_Service SHALL 使用 fileId 获取语音文件的下载 URL
3. THE System SHALL 将下载的语音文件缓存到本地，避免重复下载
4. IF 下载失败 THEN THE System SHALL 显示错误提示并允许重试
5. WHILE 下载进行中 THEN THE Audio_Attachment SHALL 显示下载进度指示器

### 需求 7：播放语音文件

**用户故事：** 作为用户，我希望能够在应用内播放语音录音，以便我可以收听录音内容。

#### 验收标准

1. WHEN 用户点击语音占位符的播放按钮 THEN THE Audio_Player SHALL 开始播放语音
2. THE Audio_Attachment SHALL 显示播放/暂停按钮
3. THE Audio_Attachment SHALL 显示播放进度条
4. THE Audio_Attachment SHALL 显示当前播放时间和总时长
5. WHEN 用户点击暂停按钮 THEN THE Audio_Player SHALL 暂停播放
6. WHEN 用户拖动进度条 THEN THE Audio_Player SHALL 跳转到指定位置
7. WHEN 播放完成 THEN THE Audio_Player SHALL 自动停止并重置到开始位置
8. IF 播放失败 THEN THE System SHALL 显示错误提示

### 需求 8：录制语音

**用户故事：** 作为用户，我希望能够在笔记中录制新的语音，以便我可以添加语音备忘。

#### 验收标准

1. WHEN 用户点击工具栏的录音按钮 THEN THE Audio_Recorder SHALL 开始录制
2. THE System SHALL 请求麦克风权限（如果尚未授权）
3. IF 用户拒绝麦克风权限 THEN THE System SHALL 显示权限说明并引导用户到系统设置
4. WHILE 录制进行中 THEN THE System SHALL 显示录制时长和音量指示器
5. THE System SHALL 限制单次录音的最大时长（如 5 分钟）
6. WHEN 用户点击停止按钮 THEN THE Audio_Recorder SHALL 停止录制
7. WHEN 录制停止 THEN THE System SHALL 显示预览界面，允许用户试听、重录或确认

### 需求 9：上传语音文件

**用户故事：** 作为用户，我希望录制的语音能够上传到服务器并保存到笔记中。

#### 验收标准

1. WHEN 用户确认录音 THEN THE MiNote_Service SHALL 上传语音文件到服务器
2. THE 上传请求 SHALL 使用 `note_img` 类型（与图片上传相同）
3. THE 上传请求 SHALL 使用 `audio/mpeg` MIME 类型
4. WHEN 上传成功 THEN THE System SHALL 获取 fileId 并插入 `<sound>` 标签到笔记
5. WHEN 上传成功 THEN THE System SHALL 更新笔记的 setting.data 元数据
6. IF 上传失败 THEN THE System SHALL 显示错误提示并允许重试
7. WHILE 上传进行中 THEN THE System SHALL 显示上传进度指示器

### 需求 10：语音文件缓存管理

**用户故事：** 作为用户，我希望应用能够智能管理语音文件缓存，以便节省存储空间。

#### 验收标准

1. THE System SHALL 将下载的语音文件缓存到本地目录
2. THE System SHALL 使用 fileId 作为缓存文件的唯一标识
3. WHEN 缓存空间超过限制 THEN THE System SHALL 自动清理最久未使用的缓存文件
4. THE System SHALL 提供手动清理缓存的选项
5. WHEN 笔记被删除 THEN THE System SHALL 清理相关的语音缓存文件

### 需求 11：API 测试支持

**用户故事：** 作为开发者，我希望能够测试语音文件相关的 API 功能。

#### 验收标准

1. THE System SHALL 支持测试语音文件的解析功能
2. THE System SHALL 支持测试语音文件的上传功能（三步流程）
3. THE System SHALL 支持测试语音文件的下载功能
4. THE API 响应 SHALL 包含正确的 fileId 和元数据信息

