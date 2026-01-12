# 需求文档

## 简介

本项目已达到约 10 万行代码规模，随着功能迭代（已有 22 个 spec），代码结构出现了一些组织问题。本需求文档定义了代码结构改善计划，旨在提高代码的可维护性、可读性和模块化程度。

## 术语表

- **Service**: 业务服务层，负责数据处理、网络请求、存储等核心逻辑
- **View**: 视图层，包含 SwiftUI 视图和 AppKit 组件
- **ViewModel**: 视图模型层，连接视图和服务层
- **Bridge**: SwiftUI 与 AppKit 之间的桥接层
- **NativeEditor**: 原生富文本编辑器模块
- **Module**: 功能模块，包含相关的服务、视图和模型

## 需求

### 需求 1：Service 层模块化拆分

**用户故事：** 作为开发者，我希望 Service 层按功能领域拆分为子目录，以便更容易找到和维护相关代码。

#### 验收标准

1. WHEN 开发者查看 Service 目录 THEN Service 目录 SHALL 包含以下子目录：Audio、Network、Sync、Storage、Editor
2. WHEN 音频相关服务被访问 THEN Audio 子目录 SHALL 包含 AudioCacheService、AudioConverterService、AudioDecryptService、AudioPlayerService、AudioRecorderService、AudioUploadService、AudioPanelStateManager
3. WHEN 网络相关服务被访问 THEN Network 子目录 SHALL 包含 NetworkErrorHandler、NetworkLogger、NetworkMonitor、NetworkRecoveryHandler、NetworkRequestManager、MiNoteService、MiNoteService+Encryption
4. WHEN 同步相关服务被访问 THEN Sync 子目录 SHALL 包含 SyncService、OfflineOperationQueue、OfflineOperationProcessor、OnlineStateManager、SaveQueueManager
5. WHEN 存储相关服务被访问 THEN Storage 子目录 SHALL 包含 DatabaseService、LocalStorageService、MemoryCacheManager
6. WHEN 编辑器相关服务被访问 THEN Editor 子目录 SHALL 包含 EditorConfiguration、EditorPreferencesService、XiaoMiFormatConverter
7. WHEN 项目编译 THEN 所有文件引用 SHALL 正确更新且编译通过

### 需求 2：NativeEditor 模块化拆分

**用户故事：** 作为开发者，我希望 NativeEditor 目录（32 个文件）按功能拆分为子目录，以便更好地理解和维护编辑器代码。

#### 验收标准

1. WHEN 开发者查看 NativeEditor 目录 THEN NativeEditor 目录 SHALL 包含以下子目录：Format、Attachment、Debug、Performance
2. WHEN 格式化相关代码被访问 THEN Format 子目录 SHALL 包含所有 Format 前缀的文件（FormatManager、FormatStateSynchronizer、FormatError 等）
3. WHEN 附件相关代码被访问 THEN Attachment 子目录 SHALL 包含 AudioAttachment、ImageAttachment、CustomAttachments、ImageStorageManager
4. WHEN 调试相关代码被访问 THEN Debug 子目录 SHALL 包含 NativeEditorDebugger、NativeEditorLogger、NativeEditorMetrics
5. WHEN 性能相关代码被访问 THEN Performance 子目录 SHALL 包含 PerformanceOptimizer、FormatApplicationPerformanceOptimizer
6. WHEN 项目编译 THEN 所有文件引用 SHALL 正确更新且编译通过

### 需求 3：SwiftUIViews 模块化拆分

**用户故事：** 作为开发者，我希望 SwiftUIViews 目录（34 个文件）按功能领域拆分，以便更快定位相关视图。

#### 验收标准

1. WHEN 开发者查看 SwiftUIViews 目录 THEN SwiftUIViews 目录 SHALL 包含以下子目录：Audio、Note、Settings、Auth、Search
2. WHEN 音频相关视图被访问 THEN Audio 子目录 SHALL 包含 AudioPanelView、AudioPlayerView、AudioRecorderView、AudioRecorderUploadView
3. WHEN 笔记相关视图被访问 THEN Note 子目录 SHALL 包含 NoteDetailView、NoteCardView、NotesListView、NoteHistoryView、NewNoteView、MoveNoteView、MoveNoteMenuView
4. WHEN 设置相关视图被访问 THEN Settings 子目录 SHALL 包含 SettingsView、EditorSettingsView、DebugSettingsView、ViewOptionsMenuView
5. WHEN 认证相关视图被访问 THEN Auth 子目录 SHALL 包含 LoginView、CookieRefreshView、PrivateNotesPasswordInputDialogView、PrivateNotesVerificationView
6. WHEN 搜索相关视图被访问 THEN Search 子目录 SHALL 包含 SearchPanelView、SearchFilterMenuContent
7. WHEN 项目编译 THEN 所有文件引用 SHALL 正确更新且编译通过

### 需求 4：Window 层职责分离

**用户故事：** 作为开发者，我希望 Window 目录中的状态管理代码与窗口控制器代码分离，以便更清晰地理解各自职责。

#### 验收标准

1. WHEN 开发者查看 Window 目录 THEN Window 目录 SHALL 包含 Controllers 和 State 两个子目录
2. WHEN 窗口控制器被访问 THEN Controllers 子目录 SHALL 包含所有 WindowController 后缀的文件
3. WHEN 窗口状态被访问 THEN State 子目录 SHALL 包含所有 WindowState 后缀的文件和 WindowStateManager
4. WHEN 项目编译 THEN 所有文件引用 SHALL 正确更新且编译通过

### 需求 5：空目录和单文件目录清理

**用户故事：** 作为开发者，我希望删除空的或仅含单个文件的目录，以保持项目结构整洁。

#### 验收标准

1. IF Sources/Search 目录为空 THEN 系统 SHALL 删除该目录
2. WHEN Helper 目录仅包含 NoteMoveHelper.swift THEN 系统 SHALL 将该文件移动到 ViewModel 目录
3. WHEN NoteMoveHelper.swift 移动完成 THEN 系统 SHALL 删除空的 Helper 目录
4. WHEN 项目编译 THEN project.yml SHALL 不包含对已删除目录的引用

### 需求 6：project.yml 结构优化

**用户故事：** 作为开发者，我希望 project.yml 的源文件配置反映新的目录结构，以便构建系统正确识别所有文件。

#### 验收标准

1. WHEN 目录结构重构完成 THEN project.yml SHALL 更新 sources 配置以匹配新结构
2. WHEN 运行 xcodegen generate THEN 系统 SHALL 成功生成 Xcode 项目
3. WHEN 运行 xcodebuild build THEN 项目 SHALL 编译成功

### 需求 7：steering 文档更新

**用户故事：** 作为开发者，我希望 steering 文档中的项目结构说明与实际结构保持一致。

#### 验收标准

1. WHEN 目录结构重构完成 THEN .kiro/steering/structure.md SHALL 更新以反映新的目录结构
2. WHEN 开发者阅读 structure.md THEN 文档 SHALL 准确描述当前的目录层级和文件组织方式
