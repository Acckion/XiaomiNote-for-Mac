# 需求文档

## 简介

将录音功能从当前的"内嵌在笔记内容中显示"改为"四栏式布局"，即在主窗口右侧增加第四栏专门显示录音内容，类似 Apple Notes 的设计。当用户点击录音按钮或选择包含录音的笔记时，第四栏会显示录音面板，提供录制和播放功能。

## 术语表

- **Audio_Panel**: 音频面板，显示在主窗口第四栏的录音/播放界面
- **Main_Window**: 主窗口，包含侧边栏、笔记列表、编辑器和音频面板的四栏布局
- **Split_View_Controller**: 分割视图控制器，管理多栏布局
- **Recording_State**: 录音状态，包括空闲、录制中、暂停、预览等
- **Audio_Attachment**: 音频附件，笔记中嵌入的音频文件引用

## 需求

### 需求 1：四栏布局支持

**用户故事：** 作为用户，我想要在主窗口右侧看到独立的音频面板，以便在不干扰笔记内容的情况下录制和播放语音。

#### 验收标准

1. WHEN 用户点击录音按钮 THEN Main_Window SHALL 在右侧显示第四栏 Audio_Panel
2. WHEN Audio_Panel 显示时 THEN Split_View_Controller SHALL 保持侧边栏、笔记列表和编辑器的原有布局
3. WHEN Audio_Panel 关闭时 THEN Main_Window SHALL 恢复为三栏布局
4. THE Audio_Panel SHALL 具有最小宽度 280 像素和最大宽度 400 像素
5. WHEN 窗口宽度不足时 THEN Split_View_Controller SHALL 优先压缩编辑器区域而非 Audio_Panel

### 需求 2：音频面板显示控制

**用户故事：** 作为用户，我想要通过多种方式打开和关闭音频面板，以便灵活地管理录音功能。

#### 验收标准

1. WHEN 用户点击工具栏录音按钮 THEN Audio_Panel SHALL 显示并进入录制准备状态
2. WHEN 用户点击笔记中的音频附件 THEN Audio_Panel SHALL 显示并加载该音频进行播放
3. WHEN 用户点击 Audio_Panel 关闭按钮 THEN Audio_Panel SHALL 关闭并恢复三栏布局
4. WHEN 用户按下 Escape 键且 Audio_Panel 处于空闲状态 THEN Audio_Panel SHALL 关闭
5. IF 用户在录制过程中尝试关闭 Audio_Panel THEN Main_Window SHALL 显示确认对话框

### 需求 3：录音功能集成

**用户故事：** 作为用户，我想要在音频面板中录制语音，以便将录音添加到当前笔记。

#### 验收标准

1. WHEN Audio_Panel 显示且处于录制准备状态 THEN Audio_Panel SHALL 显示录制按钮和时长限制提示
2. WHEN 用户点击录制按钮 THEN Audio_Panel SHALL 开始录制并显示录制时长和音量指示器
3. WHEN 用户点击暂停按钮 THEN Audio_Panel SHALL 暂停录制并保留当前进度
4. WHEN 用户点击停止按钮 THEN Audio_Panel SHALL 停止录制并进入预览状态
5. WHEN 用户确认录制 THEN Audio_Panel SHALL 将音频附件插入当前笔记并关闭面板
6. WHEN 用户取消录制 THEN Audio_Panel SHALL 删除临时文件并恢复到录制准备状态

### 需求 4：音频播放功能集成

**用户故事：** 作为用户，我想要在音频面板中播放笔记中的录音，以便收听之前录制的内容。

#### 验收标准

1. WHEN Audio_Panel 加载音频文件 THEN Audio_Panel SHALL 显示播放控件和音频时长
2. WHEN 用户点击播放按钮 THEN Audio_Panel SHALL 开始播放音频并显示播放进度
3. WHEN 用户拖动进度条 THEN Audio_Panel SHALL 跳转到指定位置继续播放
4. WHEN 用户点击前进/后退按钮 THEN Audio_Panel SHALL 跳转 15 秒
5. WHEN 音频播放完成 THEN Audio_Panel SHALL 停止播放并重置进度条

### 需求 5：状态同步

**用户故事：** 作为用户，我想要音频面板的状态与笔记内容保持同步，以便获得一致的用户体验。

#### 验收标准

1. WHEN 用户切换到其他笔记 THEN Audio_Panel SHALL 停止当前播放并关闭
2. WHEN 用户在录制过程中切换笔记 THEN Main_Window SHALL 显示确认对话框
3. WHEN 录音成功插入笔记 THEN 编辑器 SHALL 在光标位置显示音频附件占位符
4. WHEN 用户删除笔记中的音频附件 THEN Audio_Panel SHALL 关闭（如果正在播放该音频）

### 需求 6：视觉设计

**用户故事：** 作为用户，我想要音频面板具有与 Apple Notes 类似的视觉风格，以便获得一致的 macOS 体验。

#### 验收标准

1. THE Audio_Panel SHALL 使用深色背景与主窗口风格一致
2. THE Audio_Panel SHALL 显示录音标题、时间戳和时长信息
3. WHEN 录制中 THEN Audio_Panel SHALL 显示红色录制指示器和波形动画
4. THE Audio_Panel SHALL 使用橙色作为播放控件的主题色
5. THE Audio_Panel SHALL 在顶部显示关闭按钮和更多选项菜单
