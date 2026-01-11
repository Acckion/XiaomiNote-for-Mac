# 实现计划：语音文件支持

## 概述

本实现计划将语音文件支持功能分解为可执行的编码任务，按照增量开发的方式组织，确保每个步骤都能构建在前一步骤的基础上。

## 第一阶段：基础解析和显示（已完成）

- [x] 1. 创建 AudioAttachment 类
  - [x] 1.1 创建 AudioAttachment.swift 文件，实现基础结构
    - 继承 NSTextAttachment，实现 ThemeAwareAttachment 协议
    - 添加 fileId、digest、mimeType 属性
    - 实现便捷初始化方法
    - _Requirements: 2.1, 2.4_
  - [x] 1.2 实现占位符图像渲染
    - 实现 createPlaceholderImage() 方法
    - 绘制音频图标（麦克风/扬声器图标）
    - 添加"语音录音"文字标签
    - 支持深色/浅色模式
    - _Requirements: 2.1, 2.2, 2.4_
  - [x] 1.3 实现 NSTextAttachment 重写方法
    - 重写 image(forBounds:textContainer:characterIndex:)
    - 重写 attachmentBounds(for:proposedLineFragment:glyphPosition:characterIndex:)
    - _Requirements: 2.1_

- [x] 2. 扩展 CustomRenderer 支持音频附件
  - [x] 2.1 在 CustomRenderer 中添加 createAudioAttachment 方法
    - 创建并配置 AudioAttachment 实例
    - 设置默认尺寸和样式
    - _Requirements: 1.2_

- [x] 3. 扩展 XiaoMiFormatConverter 解析 sound 标签
  - [x] 3.1 添加 processSoundElementToNSAttributedString 方法
    - 解析 `<sound fileid="xxx" />` 标签
    - 提取 fileid 属性
    - 调用 CustomRenderer 创建 AudioAttachment
    - _Requirements: 1.1, 1.2_
  - [x] 3.2 在 processXMLLineToNSAttributedString 中添加 sound 标签处理分支
    - 检测 `<sound` 开头的行
    - 调用 processSoundElementToNSAttributedString
    - _Requirements: 1.1_
  - [ ]* 3.3 编写 Sound 标签解析属性测试
    - **Property 1: Sound 标签解析正确性**
    - **Validates: Requirements 1.1, 1.2**

## 第二阶段：导出和 Web 编辑器支持

- [x] 4. 扩展 XiaoMiFormatConverter 导出 sound 标签
  - [x] 4.1 在 convertAttachmentToXML 方法中添加 AudioAttachment 处理
    - 检测 AudioAttachment 类型
    - 生成 `<sound fileid="xxx" />` 格式的 XML
    - _Requirements: 5.1, 5.2_
  - [x] 4.2 在 convertNSLineToXML 方法中添加 AudioAttachment 处理
    - 检测附件类型为 AudioAttachment
    - 调用 convertAttachmentToXML
    - _Requirements: 5.1_
  - [ ]* 4.3 编写 AudioAttachment 导出属性测试
    - **Property 6: AudioAttachment 导出正确性**
    - **Validates: Requirements 5.1, 5.2**
  - [ ]* 4.4 编写往返一致性属性测试
    - **Property 7: 往返一致性（Round-trip）**
    - **Validates: Requirements 5.3**

- [ ] 5. 检查点 - 确保原生编辑器测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 6. 扩展 XMLToHTMLConverter 支持 sound 标签
  - [x] 6.1 添加 parseSoundElement 方法
    - 解析 `<sound fileid="xxx" />` 标签
    - 生成包含音频图标和标签的 HTML
    - _Requirements: 3.1, 3.2_
  - [x] 6.2 在 convert 方法中添加 sound 标签处理分支
    - 检测 `<sound` 开头的行
    - 调用 parseSoundElement
    - _Requirements: 3.1_
  - [x] 6.3 添加 CSS 样式支持
    - 在 editor.html 中添加 .mi-note-sound 样式
    - 确保与图片占位符风格一致
    - _Requirements: 3.3_

## 第三阶段：API 测试和上传功能（已完成）

- [x] 7. 使用 Postman 进行 API 测试
  - [x] 7.1 配置 Postman 测试集合
    - 创建语音文件解析测试请求
    - 添加示例 XML 数据作为测试输入
    - _Requirements: 11.1, 11.2_
  - [x] 7.2 验证 API 响应
    - 确认 fileId 正确解析
    - 验证错误处理逻辑
    - _Requirements: 11.2, 11.3_
  - [x] 7.3 测试语音文件上传 API
    - 验证 type 参数（必须使用 `note_img`）
    - 测试完整上传流程（request_upload_file → upload_block_chunk → commit）
    - 确认 MIME 类型使用 `audio/mpeg`
    - _Requirements: 9.2, 9.3, 11.2_
  - [x] 7.4 实现 MiNoteService.uploadAudio 方法
    - 在 MiNoteService 中添加 uploadAudio 方法
    - 添加 requestAudioUpload 和 commitAudioUpload 辅助方法
    - 复用 uploadFileChunk 方法上传文件块
    - _Requirements: 9.1, 9.2, 9.3_

## 第四阶段：下载和缓存功能

- [x] 8. 创建 AudioCacheService 缓存服务
  - [x] 8.1 创建 AudioCacheService.swift 文件
    - 实现单例模式
    - 配置缓存目录（~/Library/Caches/MiNoteMac/Audio/）
    - 设置最大缓存大小（100 MB）
    - _Requirements: 10.1, 10.2, 10.3_
  - [x] 8.2 实现缓存读写方法
    - getCachedFile(for fileId:) - 获取缓存文件路径
    - cacheFile(data:fileId:mimeType:) - 缓存音频文件
    - isCached(fileId:) - 检查是否已缓存
    - _Requirements: 10.1, 10.2_
  - [x] 8.3 实现缓存清理方法
    - getCacheSize() - 获取当前缓存大小
    - clearCache() - 清理所有缓存
    - removeCache(for fileId:) - 清理指定文件缓存
    - evictLeastRecentlyUsed(targetSize:) - LRU 淘汰策略
    - _Requirements: 10.3, 10.4, 10.5_

- [x] 9. 实现 MiNoteService 下载方法
  - [x] 9.1 添加 getAudioDownloadURL 方法
    - 使用 fileId 获取下载 URL
    - 处理 API 错误响应
    - _Requirements: 6.2_
  - [x] 9.2 添加 downloadAudio 方法
    - 下载音频文件数据
    - 支持进度回调
    - _Requirements: 6.1, 6.4_
  - [x] 9.3 测试下载 API
    - 使用测试 fileId 验证下载功能
    - 确认返回的音频数据正确
    - _Requirements: 11.3_

- [ ] 10. 检查点 - 确保下载和缓存功能正常
  - 测试下载 API 返回正确数据
  - 测试缓存读写功能
  - 确保缓存清理正常工作

## 第五阶段：播放功能

- [x] 11. 创建 AudioPlayerService 播放服务
  - [x] 11.1 创建 AudioPlayerService.swift 文件
    - 实现单例模式
    - 使用 AVAudioPlayer 播放音频
    - 添加 @Published 属性用于状态绑定
    - _Requirements: 7.1, 7.2_
  - [x] 11.2 实现播放控制方法
    - play(url:) - 播放音频文件
    - pause() - 暂停播放
    - stop() - 停止播放
    - seek(to progress:) - 跳转到指定位置
    - _Requirements: 7.1, 7.5, 7.6_
  - [x] 11.3 实现播放状态管理
    - 定时更新 currentTime 和 progress
    - 播放完成自动重置
    - 错误处理和状态通知
    - _Requirements: 7.3, 7.4, 7.7, 7.8_

- [x] 12. 扩展 AudioAttachment 添加播放控制
  - [x] 12.1 添加播放状态属性
    - playbackState（idle/loading/playing/paused/error）
    - playbackProgress（0.0 - 1.0）
    - currentTime 和 duration
    - _Requirements: 7.2, 7.3, 7.4_
  - [x] 12.2 实现播放控制方法
    - play() - 开始播放（自动下载和缓存）
    - pause() - 暂停播放
    - stop() - 停止播放
    - seek(to:) - 跳转位置
    - _Requirements: 7.1, 7.5, 7.6_
  - [x] 12.3 更新占位符渲染
    - 显示播放/暂停按钮
    - 显示播放进度条
    - 显示时间信息
    - _Requirements: 7.2, 7.3, 7.4_

- [x] 13. 创建 AudioPlayerView（SwiftUI）
  - [x] 13.1 创建 AudioPlayerView.swift 文件
    - 显示播放进度条
    - 显示当前时间和总时长
    - 播放/暂停/跳转控制按钮
    - _Requirements: 7.2, 7.3, 7.4, 7.6_

- [x] 14. 检查点 - 确保播放功能正常
  - 测试播放/暂停/停止功能
  - 测试进度跳转功能
  - 确保播放状态正确更新

## 第六阶段：录制功能

- [x] 15. 创建 AudioRecorderService 录制服务
  - [x] 15.1 创建 AudioRecorderService.swift 文件
    - 实现单例模式
    - 使用 AVAudioRecorder 录制音频
    - 添加 @Published 属性用于状态绑定
    - _Requirements: 8.1, 8.4_
  - [x] 15.2 实现权限管理
    - requestPermission() - 请求麦克风权限
    - checkPermissionStatus() - 检查权限状态
    - _Requirements: 8.2, 8.3_
  - [x] 15.3 实现录制控制方法
    - startRecording() - 开始录制
    - pauseRecording() - 暂停录制
    - resumeRecording() - 继续录制
    - stopRecording() - 停止录制并返回文件 URL
    - cancelRecording() - 取消录制
    - _Requirements: 8.1, 8.6_
  - [x] 15.4 实现录制状态管理
    - 定时更新 recordingDuration
    - 更新音量级别 audioLevel
    - 最大时长限制（5 分钟）
    - _Requirements: 8.4, 8.5_

- [x] 16. 创建 AudioRecorderView（SwiftUI）
  - [x] 16.1 创建 AudioRecorderView.swift 文件
    - 显示录制时长
    - 显示音量指示器
    - 录制/停止/取消按钮
    - _Requirements: 8.1, 8.4, 8.6_
  - [x] 16.2 实现预览功能
    - 录制完成后显示预览界面
    - 支持试听、重录、确认操作
    - _Requirements: 8.7_

- [x] 17. 集成录制和上传流程
  - [x] 17.1 实现录制完成后的上传流程
    - 调用 MiNoteService.uploadAudio 上传文件
    - 获取 fileId 并创建 AudioAttachment
    - 插入到编辑器当前位置
    - _Requirements: 9.1, 9.4, 9.5_
    
  - [x] 17.2 实现上传进度显示
    - 显示上传进度指示器
    - 上传失败时显示错误提示和重试按钮
    - _Requirements: 9.6, 9.7_

- [x] 18. 检查点 - 确保录制功能正常
  - 测试麦克风权限请求
  - 测试录制/暂停/停止功能
  - 测试上传流程

## 第七阶段：集成和完善

- [x] 19. 更新 project.yml 添加新文件
  - [x] 19.1 将所有新文件添加到项目配置
    - AudioAttachment.swift
    - AudioCacheService.swift
    - AudioPlayerService.swift
    - AudioRecorderService.swift
    - AudioPlayerView.swift
    - AudioRecorderView.swift
    - _Requirements: 所有_

- [x] 20. 添加工具栏录音按钮
  - [x] 20.1 在工具栏添加录音按钮
    - 点击显示录音界面
    - _Requirements: 8.1_

- [x] 21. 最终检查点
  - 确保所有功能正常工作
  - 确保所有测试通过
  - 如有问题请询问用户

## 第八阶段：Web 编辑器支持

- [x] 22. 在 Web 编辑器中插入语音录音
  - [x] 22.1 扩展 WebEditorContext 支持插入语音
    - 添加 insertAudio(fileId:digest:mimeType:) 方法
    - 调用 JavaScript 方法插入 HTML 占位符
    - _Requirements: 12.1, 12.2, 12.3_
  - [x] 22.2 实现 JavaScript 插入方法
    - 在 editor.js 中添加 insertAudioElement 方法
    - 生成带有 fileId 的语音占位符 HTML
    - _Requirements: 12.2, 12.3_
  - [x] 22.3 更新 MainWindowController 支持 Web 编辑器录音
    - 在 insertAudioRecording 方法中添加 Web 编辑器分支
    - 调用 WebEditorContext.insertAudio
    - _Requirements: 12.1_

- [x] 23. 扩展 HTMLToXMLConverter 支持语音标签
  - [x] 23.1 添加语音占位符解析逻辑
    - 识别 .mi-note-sound 类的 HTML 元素
    - 提取 data-fileid 属性
    - 生成 `<sound fileid="xxx" />` XML 标签
    - _Requirements: 12.4_

- [x] 24. 在 Web 编辑器中播放语音
  - [x] 24.1 添加语音占位符点击事件处理
    - 在 editor.js 中监听语音占位符点击
    - 通过 WebKit 消息处理器通知 Swift
    - _Requirements: 13.1_
  - [x] 24.2 实现 Swift 端播放控制
    - 在 WebEditorContext 中添加播放控制方法
    - 复用 AudioPlayerService 进行播放
    - _Requirements: 13.2, 13.3_
  - [x] 24.3 更新 Web 编辑器占位符状态
    - 通过 JavaScript 更新占位符的播放状态样式
    - 显示播放/暂停图标
    - _Requirements: 13.4_

- [ ] 25. 检查点 - 确保 Web 编辑器语音功能正常
  - 测试在 Web 编辑器中插入录音
  - 测试在 Web 编辑器中播放录音
  - 测试保存后 XML 格式正确

## 注意事项

- 标记为 `*` 的任务是可选的，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- 检查点确保增量验证
- 属性测试验证通用正确性属性
- 单元测试验证特定示例和边界情况

## API 关键发现

- **type 参数**: 语音文件上传必须使用 `note_img`（与图片相同）
- **MIME 类型**: 推荐使用 `audio/mpeg`
- **上传流程**: request_upload_file → upload_block_chunk → commit（三步流程）
- **测试笔记 ID**: `48926433520534752`
- **测试语音 fileId**: `1315204657.jgHyouv563iSF_XCE4jhAg`
