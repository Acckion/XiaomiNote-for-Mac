# 实现计划: 音频面板四栏布局

## 概述

将录音功能从内嵌显示改为四栏式布局，在主窗口右侧增加独立的音频面板。

## 任务

- [x] 1. 创建音频面板状态管理器
  - [x] 1.1 创建 AudioPanelStateManager 类
    - 定义 Mode 枚举（recording, playback）
    - 实现 isVisible、mode、currentFileId、currentNoteId 属性
    - 实现 showForRecording()、showForPlayback()、hide()、canClose() 方法
    - _Requirements: 1.1, 1.3, 2.1, 2.2, 2.3, 5.1_
  - [x] 1.2 编写 AudioPanelStateManager 单元测试
    - 测试状态转换逻辑
    - 测试 canClose() 在各种状态下的返回值
    - _Requirements: 1.1, 1.3_

- [x] 2. 创建音频面板视图
  - [x] 2.1 创建 AudioPanelView SwiftUI 视图
    - 实现标题栏（关闭按钮、标题、更多选项）
    - 根据模式切换录制/播放内容
    - 设置深色背景和橙色主题色
    - _Requirements: 6.1, 6.2, 6.4, 6.5_
  - [x] 2.2 实现录制模式内容
    - 复用现有 AudioRecorderView 的录制逻辑
    - 适配面板布局（垂直排列）
    - 显示录制时长、音量指示器、控制按钮
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 6.3_
  - [x] 2.3 实现播放模式内容
    - 复用现有 AudioPlayerView 的播放逻辑
    - 适配面板布局
    - 显示播放进度、时间、控制按钮
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 3. 创建音频面板托管控制器
  - [x] 3.1 创建 AudioPanelHostingController 类
    - 继承 NSHostingController<AudioPanelView>
    - 接收 AudioPanelStateManager 和 NotesViewModel
    - _Requirements: 1.1, 1.2_

- [x] 4. 扩展 MainWindowController 支持四栏布局
  - [x] 4.1 添加音频面板状态管理器属性
    - 创建 audioPanelStateManager 实例
    - 设置状态变化监听
    - _Requirements: 1.1_
  - [x] 4.2 实现 showAudioPanel() 方法
    - 创建 AudioPanelHostingController
    - 添加到 NSSplitViewController 作为第四栏
    - 设置宽度约束（min: 280, max: 400）
    - 设置 holdingPriority 确保优先压缩编辑器
    - _Requirements: 1.1, 1.2, 1.4, 1.5_
  - [x] 4.3 实现 hideAudioPanel() 方法
    - 从 NSSplitViewController 移除第四栏
    - 恢复三栏布局
    - _Requirements: 1.3, 2.3_
  - [x] 4.4 编写布局切换属性测试
    - **Property 1: 四栏布局切换一致性**
    - **Validates: Requirements 1.1, 1.3, 2.3**

- [x] 5. 集成工具栏录音按钮
  - [x] 5.1 更新工具栏录音按钮动作
    - 点击时调用 showAudioPanel(mode: .recording)
    - 传入当前笔记 ID
    - _Requirements: 2.1_
  - [x] 5.2 添加键盘快捷键支持
    - Escape 键关闭面板（空闲状态）
    - _Requirements: 2.4_

- [x] 6. 集成音频附件点击
  - [x] 6.1 修改音频附件点击处理
    - 点击时调用 showAudioPanel(mode: .playback, fileId:)
    - 传入音频文件 ID 和笔记 ID
    - _Requirements: 2.2_

- [x] 7. 实现录制完成后插入附件
  - [x] 7.1 实现录制确认回调
    - 上传音频文件
    - 在编辑器光标位置插入音频附件
    - 关闭面板
    - _Requirements: 3.5, 5.3_
  - [x] 7.2 实现录制取消回调
    - 删除临时文件
    - 重置状态
    - _Requirements: 3.6_
  - [ ]* 7.3 编写音频附件插入属性测试
    - **Property 7: 音频附件插入一致性**
    - **Validates: Requirements 5.3**

- [x] 7.4 改进录音工作流程 - 先插入模板再录制
  - [x] 7.4.1 在 Web 编辑器中添加录音模板功能
    - 在 format.js 中添加 insertRecordingTemplate 和 updateRecordingTemplate 方法
    - 在 editor-api.js 中添加对应的 API 方法
    - 添加录音模板的 CSS 样式和脉冲动画效果
  - [x] 7.4.2 扩展 WebEditorContext 支持录音模板
    - 添加 insertRecordingTemplate 和 updateRecordingTemplate 方法
    - 添加对应的闭包属性
  - [x] 7.4.3 在 WebEditorView 中实现录音模板闭包
    - 实现 insertRecordingTemplateClosure 和 updateRecordingTemplateClosure
    - 调用 JavaScript 方法执行录音模板操作
  - [x] 7.4.4 修改录音工作流程
    - 修改 MainWindowController.insertAudioRecording 方法
    - 先插入录音模板占位符，然后显示音频面板
    - 在 AudioPanelStateManager 中添加 currentRecordingTemplateId 属性
  - [x] 7.4.5 更新录制完成处理逻辑
    - 修改 handleAudioRecordingComplete 方法
    - 录制完成后更新录音模板为实际的音频附件
    - 支持 Web 编辑器和原生编辑器的不同处理方式

- [x] 8. 实现笔记切换状态同步
  - [x] 8.1 监听笔记切换事件
    - 在 NotesViewModel.selectedNote 变化时检查面板状态
    - _Requirements: 5.1, 5.2_
  - [x] 8.2 实现播放状态下的自动关闭
    - 停止播放
    - 关闭面板
    - _Requirements: 5.1_
  - [x] 8.3 实现录制状态下的确认对话框
    - 显示确认对话框
    - 提供保存、放弃、取消选项
    - _Requirements: 5.2, 2.5_
  - [ ] 8.4 编写笔记切换状态同步属性测试
    - **Property 6: 笔记切换状态同步**
    - **Validates: Requirements 5.1, 5.2**

- [x] 9. 实现音频附件删除同步
  - [x] 9.1 监听音频附件删除事件
    - 检查当前播放的文件 ID
    - 如果匹配则关闭面板
    - _Requirements: 5.4_

- [x] 10. Checkpoint - 确保所有测试通过
  - 运行所有单元测试和属性测试
  - 验证四栏布局正常工作
  - 如有问题请询问用户

- [x] 11. 修复语音录制上传后手机无法播放的问题
  - [x] 11.1 在 MainWindowController.handleAudioRecordingComplete 中添加 setting.data 更新
    - 音频上传完成后更新笔记的 setting.data 元数据
    - 添加音频文件的 fileId、mimeType 和 digest 信息
    - 这是小米笔记服务器识别音频文件的关键信息
    - _Requirements: 基于 git 提交 86dc211 的修复_
  - [x] 11.2 验证修复效果
    - 确保代码编译通过
    - 验证修复代码正确应用
    - _Requirements: 确保手机端能正常播放 Mac 端录制的音频_

## 备注

- 标记 `*` 的任务为可选任务，可跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- Checkpoint 用于确保增量验证
- 属性测试验证通用正确性属性
- 单元测试验证具体示例和边界情况
