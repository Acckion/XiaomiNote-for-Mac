# 实现计划：项目结构重构

## 概述

本实现计划将代码结构重构分解为可执行的任务。采用渐进式方法，每个阶段完成后验证编译通过。任务按依赖关系排序，确保每一步都是可编译的状态。

## 任务

- [x] 1. 清理空目录和单文件目录
  - [x] 1.1 删除空的 Sources/Search 目录
    - _需求: 5.1_
  - [x] 1.2 将 Sources/Helper/NoteMoveHelper.swift 移动到 Sources/ViewModel/
    - _需求: 5.2_
  - [x] 1.3 删除空的 Sources/Helper 目录
    - _需求: 5.3_
  - [x] 1.4 验证编译通过
    - 运行 `xcodegen generate && xcodebuild build`
    - _需求: 5.4_

- [x] 2. Service 层模块化 - Audio 子目录
  - [x] 2.1 创建 Sources/Service/Audio 目录
    - _需求: 1.1_
  - [x] 2.2 移动音频相关文件到 Audio 子目录
    - 移动 AudioCacheService.swift
    - 移动 AudioConverterService.swift
    - 移动 AudioDecryptService.swift
    - 移动 AudioPlayerService.swift
    - 移动 AudioRecorderService.swift
    - 移动 AudioUploadService.swift
    - 移动 AudioPanelStateManager.swift
    - _需求: 1.2_
  - [x] 2.3 验证编译通过
    - _需求: 1.7_

- [x] 3. Service 层模块化 - Network 子目录
  - [x] 3.1 创建 Sources/Service/Network 目录
    - _需求: 1.1_
  - [x] 3.2 移动网络相关文件到 Network 子目录
    - 移动 MiNoteService.swift
    - 移动 MiNoteService+Encryption.swift
    - 移动 NetworkErrorHandler.swift
    - 移动 NetworkLogger.swift
    - 移动 NetworkMonitor.swift
    - 移动 NetworkRecoveryHandler.swift
    - 移动 NetworkRequestManager.swift
    - _需求: 1.3_
  - [x] 3.3 验证编译通过
    - _需求: 1.7_

- [x] 4. Service 层模块化 - Sync 子目录
  - [x] 4.1 创建 Sources/Service/Sync 目录
    - _需求: 1.1_
  - [x] 4.2 移动同步相关文件到 Sync 子目录
    - 移动 SyncService.swift
    - 移动 OfflineOperationQueue.swift
    - 移动 OfflineOperationProcessor.swift
    - 移动 OnlineStateManager.swift
    - 移动 SaveQueueManager.swift
    - _需求: 1.4_
  - [x] 4.3 验证编译通过
    - _需求: 1.7_

- [x] 5. Service 层模块化 - Storage 子目录
  - [x] 5.1 创建 Sources/Service/Storage 目录
    - _需求: 1.1_
  - [x] 5.2 移动存储相关文件到 Storage 子目录
    - 移动 DatabaseService.swift
    - 移动 LocalStorageService.swift
    - 移动 MemoryCacheManager.swift
    - _需求: 1.5_
  - [x] 5.3 验证编译通过
    - _需求: 1.7_

- [x] 6. Service 层模块化 - Editor 子目录
  - [x] 6.1 创建 Sources/Service/Editor 目录
    - _需求: 1.1_
  - [x] 6.2 移动编辑器相关文件到 Editor 子目录
    - 移动 EditorConfiguration.swift
    - 移动 EditorPreferencesService.swift
    - 移动 XiaoMiFormatConverter.swift
    - _需求: 1.6_
  - [x] 6.3 验证编译通过
    - _需求: 1.7_

- [x] 7. Service 层模块化 - Core 子目录
  - [x] 7.1 创建 Sources/Service/Core 目录
    - _需求: 1.1_
  - [x] 7.2 移动核心服务文件到 Core 子目录
    - 移动 AuthenticationStateManager.swift
    - 移动 StartupSequenceManager.swift
    - 移动 ScheduledTaskManager.swift
    - 移动 ErrorRecoveryService.swift
    - 移动 PrivateNotesPasswordManager.swift
    - 移动 SilentCookieRefreshManager.swift
    - _需求: 1.1_
  - [x] 7.3 验证编译通过
    - _需求: 1.7_

- [x] 8. 检查点 - Service 层重构完成
  - 运行完整测试套件 `xcodebuild test`
  - 确保所有测试通过，如有问题询问用户

- [x] 9. NativeEditor 模块化 - Core 子目录
  - [x] 9.1 创建 Sources/View/NativeEditor/Core 目录
    - _需求: 2.1_
  - [x] 9.2 移动核心编辑器文件到 Core 子目录
    - 移动 NativeEditorView.swift
    - 移动 NativeEditorInitializer.swift
    - 移动 SafeRenderer.swift
    - 移动 CustomRenderer.swift
    - 移动 QuoteBlockRenderer.swift
    - _需求: 2.1_
  - [x] 9.3 验证编译通过
    - _需求: 2.6_

- [x] 10. NativeEditor 模块化 - Format 子目录
  - [x] 10.1 创建 Sources/View/NativeEditor/Format 目录
    - _需求: 2.1_
  - [x] 10.2 移动格式化相关文件到 Format 子目录
    - 移动所有 Format 前缀的文件
    - 移动 MixedFormatApplicationHandler.swift
    - 移动 MixedFormatStateHandler.swift
    - 移动 CrossParagraphFormatHandler.swift
    - 移动 SpecialElementFormatHandler.swift
    - 移动 UndoRedoStateHandler.swift
    - 移动 NativeFormatProvider.swift
    - 移动 EditorStateConsistencyChecker.swift
    - _需求: 2.2_
  - [x] 10.3 验证编译通过
    - _需求: 2.6_

- [x] 11. NativeEditor 模块化 - Attachment 子目录
  - [x] 11.1 创建 Sources/View/NativeEditor/Attachment 目录
    - _需求: 2.1_
  - [x] 11.2 移动附件相关文件到 Attachment 子目录
    - 移动 AudioAttachment.swift
    - 移动 ImageAttachment.swift
    - 移动 CustomAttachments.swift
    - 移动 ImageStorageManager.swift
    - _需求: 2.3_
  - [x] 11.3 验证编译通过
    - _需求: 2.6_

- [x] 12. NativeEditor 模块化 - Debug 子目录
  - [x] 12.1 创建 Sources/View/NativeEditor/Debug 目录
    - _需求: 2.1_
  - [x] 12.2 移动调试相关文件到 Debug 子目录
    - 移动 NativeEditorDebugger.swift
    - 移动 NativeEditorLogger.swift
    - 移动 NativeEditorMetrics.swift
    - 移动 NativeEditorErrorHandler.swift
    - _需求: 2.4_
  - [x] 12.3 验证编译通过
    - _需求: 2.6_

- [x] 13. NativeEditor 模块化 - Performance 子目录
  - [x] 13.1 创建 Sources/View/NativeEditor/Performance 目录
    - _需求: 2.1_
  - [x] 13.2 移动性能相关文件到 Performance 子目录
    - 移动 PerformanceOptimizer.swift
    - 移动 FormatApplicationPerformanceOptimizer.swift
    - _需求: 2.5_
  - [x] 13.3 验证编译通过
    - _需求: 2.6_

- [x] 14. 检查点 - NativeEditor 重构完成
  - 运行完整测试套件 `xcodebuild test`
  - 确保所有测试通过，如有问题询问用户

- [x] 15. SwiftUIViews 模块化 - Audio 子目录
  - [x] 15.1 创建 Sources/View/SwiftUIViews/Audio 目录
    - _需求: 3.1_
  - [x] 15.2 移动音频相关视图到 Audio 子目录
    - 移动 AudioPanelView.swift
    - 移动 AudioPlayerView.swift
    - 移动 AudioRecorderView.swift
    - 移动 AudioRecorderUploadView.swift
    - _需求: 3.2_
  - [x] 15.3 验证编译通过
    - _需求: 3.7_

- [x] 16. SwiftUIViews 模块化 - Note 子目录
  - [x] 16.1 创建 Sources/View/SwiftUIViews/Note 目录
    - _需求: 3.1_
  - [x] 16.2 移动笔记相关视图到 Note 子目录
    - 移动 NoteDetailView.swift
    - 移动 NoteDetailWindowView.swift
    - 移动 NoteCardView.swift
    - 移动 NotesListView.swift
    - 移动 NoteHistoryView.swift
    - 移动 NewNoteView.swift
    - 移动 MoveNoteView.swift
    - 移动 MoveNoteMenuView.swift
    - 移动 ExpandedNoteView.swift
    - 移动 TitleEditorView.swift
    - _需求: 3.3_
  - [x] 16.3 验证编译通过
    - _需求: 3.7_

- [x] 17. SwiftUIViews 模块化 - Settings 子目录
  - [x] 17.1 创建 Sources/View/SwiftUIViews/Settings 目录
    - _需求: 3.1_
  - [x] 17.2 移动设置相关视图到 Settings 子目录
    - 移动 SettingsView.swift
    - 移动 EditorSettingsView.swift
    - 移动 DebugSettingsView.swift
    - 移动 ViewOptionsMenuView.swift
    - _需求: 3.4_
  - [x] 17.3 验证编译通过
    - _需求: 3.7_

- [x] 18. SwiftUIViews 模块化 - Auth 子目录
  - [x] 18.1 创建 Sources/View/SwiftUIViews/Auth 目录
    - _需求: 3.1_
  - [x] 18.2 移动认证相关视图到 Auth 子目录
    - 移动 LoginView.swift
    - 移动 CookieRefreshView.swift
    - 移动 PrivateNotesPasswordInputDialogView.swift
    - 移动 PrivateNotesVerificationView.swift
    - _需求: 3.5_
  - [x] 18.3 验证编译通过
    - _需求: 3.7_

- [x] 19. SwiftUIViews 模块化 - Search 子目录
  - [x] 19.1 创建 Sources/View/SwiftUIViews/Search 目录
    - _需求: 3.1_
  - [x] 19.2 移动搜索相关视图到 Search 子目录
    - 移动 SearchPanelView.swift
    - 移动 SearchFilterMenuContent.swift
    - _需求: 3.6_
  - [x] 19.3 验证编译通过
    - _需求: 3.7_

- [x] 20. SwiftUIViews 模块化 - Common 子目录
  - [x] 20.1 创建 Sources/View/SwiftUIViews/Common 目录
    - _需求: 3.1_
  - [x] 20.2 移动通用视图到 Common 子目录
    - 移动 ContentView.swift
    - 移动 ContentAreaView.swift
    - 移动 GalleryView.swift
    - 移动 SidebarView.swift
    - 移动 TrashView.swift
    - 移动 NetworkLogView.swift
    - 移动 OfflineOperationsProgressView.swift
    - 移动 WebEditorView.swift
    - 移动 NativeFormatMenuView.swift
    - 移动 XMLDebugEditorView.swift
    - _需求: 3.1_
  - [x] 20.3 验证编译通过
    - _需求: 3.7_

- [x] 21. 检查点 - SwiftUIViews 重构完成
  - 运行完整测试套件 `xcodebuild test`
  - 确保所有测试通过，如有问题询问用户

- [x] 22. Window 层模块化 - Controllers 子目录
  - [x] 22.1 创建 Sources/Window/Controllers 目录
    - _需求: 4.1_
  - [x] 22.2 移动窗口控制器到 Controllers 子目录
    - 移动 MainWindowController.swift
    - 移动 LoginWindowController.swift
    - 移动 SettingsWindowController.swift
    - 移动 HistoryWindowController.swift
    - 移动 TrashWindowController.swift
    - 移动 DebugWindowController.swift
    - 移动 CookieRefreshWindowController.swift
    - 移动 SearchPanelController.swift
    - 移动 BaseSheetToolbarDelegate.swift
    - _需求: 4.2_
  - [x] 22.3 验证编译通过
    - _需求: 4.4_

- [x] 23. Window 层模块化 - State 子目录
  - [x] 23.1 创建 Sources/Window/State 目录
    - _需求: 4.1_
  - [x] 23.2 移动窗口状态文件到 State 子目录
    - 移动 WindowStateManager.swift
    - 移动 MainWindowState.swift
    - 移动 NoteDetailWindowState.swift
    - 移动 NotesListWindowState.swift
    - 移动 SidebarWindowState.swift
    - 移动 CustomSearchField.swift
    - _需求: 4.3_
  - [x] 23.3 验证编译通过
    - _需求: 4.4_

- [x] 24. 检查点 - Window 层重构完成
  - 运行完整测试套件 `xcodebuild test`
  - 确保所有测试通过，如有问题询问用户

- [x] 25. 更新 steering 文档
  - [x] 25.1 更新 .kiro/steering/structure.md 反映新的目录结构
    - _需求: 7.1, 7.2_
  - [x] 25.2 验证文档准确描述当前目录层级
    - _需求: 7.2_

- [x] 26. 最终检查点
  - 运行完整测试套件
  - 启动应用验证主要功能
  - 如有问题询问用户

## 注意事项

- Swift 使用模块级导入，目录结构变化不影响 import 语句
- 每个任务完成后都需要验证编译通过
- 使用 Git 版本控制，可随时回滚
- project.yml 使用通配符配置源文件，目录变化后自动识别
