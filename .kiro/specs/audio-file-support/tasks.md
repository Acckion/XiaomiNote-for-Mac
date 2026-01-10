# 实现计划：语音文件支持

## 概述

本实现计划将语音文件支持功能分解为可执行的编码任务，按照增量开发的方式组织，确保每个步骤都能构建在前一步骤的基础上。

## 任务

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

- [ ] 4. 扩展 XiaoMiFormatConverter 导出 sound 标签
  - [ ] 4.1 在 convertAttachmentToXML 方法中添加 AudioAttachment 处理
    - 检测 AudioAttachment 类型
    - 生成 `<sound fileid="xxx" />` 格式的 XML
    - _Requirements: 5.1, 5.2_
  - [ ] 4.2 在 convertNSLineToXML 方法中添加 AudioAttachment 处理
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

- [ ] 6. 扩展 XMLToHTMLConverter 支持 sound 标签
  - [ ] 6.1 添加 parseSoundElement 方法
    - 解析 `<sound fileid="xxx" />` 标签
    - 生成包含音频图标和标签的 HTML
    - _Requirements: 3.1, 3.2_
  - [ ] 6.2 在 convert 方法中添加 sound 标签处理分支
    - 检测 `<sound` 开头的行
    - 调用 parseSoundElement
    - _Requirements: 3.1_
  - [ ] 6.3 添加 CSS 样式支持
    - 在 editor.html 中添加 .mi-note-sound 样式
    - 确保与图片占位符风格一致
    - _Requirements: 3.3_

- [x] 7. 使用 Postman 进行 API 测试
  - [x] 7.1 配置 Postman 测试集合
    - 创建语音文件解析测试请求
    - 添加示例 XML 数据作为测试输入
    - _Requirements: 6.1, 6.2_
  - [x] 7.2 验证 API 响应
    - 确认 fileId 正确解析
    - 验证错误处理逻辑
    - _Requirements: 6.2, 6.3_
  - [x] 7.3 测试语音文件上传 API
    - 验证 type 参数（必须使用 `note_img`）
    - 测试完整上传流程（request_upload_file → upload_block_chunk → commit）
    - 确认 MIME 类型使用 `audio/mpeg`
    - _Requirements: 6.1, 6.2_
  - [x] 7.4 实现 MiNoteService.uploadAudio 方法
    - 在 MiNoteService 中添加 uploadAudio 方法
    - 添加 requestAudioUpload 和 commitAudioUpload 辅助方法
    - 复用 uploadFileChunk 方法上传文件块
    - _Requirements: 6.1, 6.2_

- [ ] 8. 检查点 - 确保所有功能正常工作
  - 确保所有测试通过，如有问题请询问用户。

- [ ] 9. 更新 project.yml 添加新文件
  - [ ] 9.1 将 AudioAttachment.swift 添加到项目配置
    - _Requirements: 1.1, 1.2_

## 注意事项

- 标记为 `*` 的任务是可选的，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- 检查点确保增量验证
- 属性测试验证通用正确性属性
- 单元测试验证特定示例和边界情况
