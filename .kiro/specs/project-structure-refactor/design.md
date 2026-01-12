# 设计文档

## 概述

本设计文档描述了小米笔记 macOS 客户端的代码结构重构方案。项目已达到约 10 万行代码规模，需要通过模块化拆分来提高可维护性。重构采用渐进式方法，每个阶段完成后都验证编译通过，确保不破坏现有功能。

## 架构

### View 和 Window 的关系说明

在 macOS AppKit + SwiftUI 混合架构中：

```
┌─────────────────────────────────────────────────────────────┐
│                    Window 层 (AppKit)                        │
│  MainWindowController - 管理 NSWindow、工具栏、分割视图      │
│  └── NSSplitViewController                                   │
│      ├── SidebarHostingController (Bridge)                   │
│      ├── NotesListHostingController (Bridge)                 │
│      └── NoteDetailHostingController (Bridge)                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    View 层 (SwiftUI)                         │
│  Bridge/ - HostingController 桥接 AppKit 和 SwiftUI          │
│  SwiftUIViews/ - 纯 SwiftUI 视图组件                         │
│  NativeEditor/ - 原生富文本编辑器（NSTextView 封装）          │
└─────────────────────────────────────────────────────────────┘
```

- **Window 层**：AppKit 窗口控制器，负责窗口管理、工具栏、菜单响应
- **View/Bridge**：HostingController 将 SwiftUI 视图嵌入 AppKit 容器
- **View/SwiftUIViews**：纯 SwiftUI 视图，被 Bridge 层包装后使用
- **View/NativeEditor**：基于 NSTextView 的原生编辑器，提供富文本编辑

### 当前架构问题

```
Sources/
├── Service/          # 31 个文件平铺，职责混杂
├── View/
│   ├── NativeEditor/ # 32 个文件平铺
│   └── SwiftUIViews/ # 34 个文件平铺
├── Window/           # 控制器和状态混合
├── Helper/           # 仅 1 个文件，可合并到其他目录
└── Search/           # 空目录
```

### 目标架构

```
Sources/
├── Service/
│   ├── Audio/        # 音频相关服务
│   ├── Network/      # 网络和 API 服务
│   ├── Sync/         # 同步和离线操作
│   ├── Storage/      # 数据存储服务
│   ├── Editor/       # 编辑器配置服务
│   └── Core/         # 核心服务（认证、启动等）
│
├── View/
│   ├── NativeEditor/
│   │   ├── Core/         # 核心编辑器组件
│   │   ├── Format/       # 格式化处理
│   │   ├── Attachment/   # 附件处理
│   │   ├── Debug/        # 调试工具
│   │   └── Performance/  # 性能优化
│   │
│   ├── SwiftUIViews/
│   │   ├── Audio/        # 音频相关视图
│   │   ├── Note/         # 笔记相关视图
│   │   ├── Settings/     # 设置相关视图
│   │   ├── Auth/         # 认证相关视图
│   │   ├── Search/       # 搜索相关视图
│   │   └── Common/       # 通用视图组件
│   │
│   ├── Bridge/           # 保持不变（AppKit-SwiftUI 桥接）
│   ├── AppKitComponents/ # 保持不变
│   └── Shared/           # 保持不变
│
├── Window/
│   ├── Controllers/  # 窗口控制器（管理 NSWindow）
│   └── State/        # 窗口状态管理
│
├── Model/            # 保持不变
├── ViewModel/        # 保持不变（合并 Helper 中的文件）
├── App/              # 保持不变
├── Extensions/       # 保持不变
├── ToolbarItem/      # 保持不变
└── Web/              # 保持不变

# 删除的目录：
# - Helper/  → NoteMoveHelper.swift 移动到 ViewModel/
# - Search/  → 空目录，直接删除
```

## 组件和接口

### Service 层模块划分

```
┌─────────────────────────────────────────────────────────────┐
│                        Service/                              │
├─────────────┬─────────────┬─────────────┬─────────────┬─────┤
│   Audio/    │  Network/   │   Sync/     │  Storage/   │Core/│
├─────────────┼─────────────┼─────────────┼─────────────┼─────┤
│AudioCache   │MiNoteService│SyncService  │Database     │Auth │
│AudioConvert │+Encryption  │OfflineQueue │LocalStorage │Start│
│AudioDecrypt │NetworkError │OfflineProc  │MemoryCache  │Sched│
│AudioPlayer  │NetworkLogger│OnlineState  │             │Error│
│AudioRecord  │NetworkMon   │SaveQueue    │             │Priv │
│AudioUpload  │NetworkRecov │             │             │     │
│AudioPanel   │NetworkReq   │             │             │     │
└─────────────┴─────────────┴─────────────┴─────────────┴─────┘
```

#### Audio 子目录（7 个文件）
- `AudioCacheService.swift` - 音频缓存
- `AudioConverterService.swift` - 音频格式转换
- `AudioDecryptService.swift` - 音频解密
- `AudioPlayerService.swift` - 音频播放
- `AudioRecorderService.swift` - 音频录制
- `AudioUploadService.swift` - 音频上传
- `AudioPanelStateManager.swift` - 音频面板状态

#### Network 子目录（7 个文件）
- `MiNoteService.swift` - 小米笔记 API
- `MiNoteService+Encryption.swift` - API 加密扩展
- `NetworkErrorHandler.swift` - 网络错误处理
- `NetworkLogger.swift` - 网络日志
- `NetworkMonitor.swift` - 网络状态监控
- `NetworkRecoveryHandler.swift` - 网络恢复处理
- `NetworkRequestManager.swift` - 网络请求管理

#### Sync 子目录（5 个文件）
- `SyncService.swift` - 同步服务
- `OfflineOperationQueue.swift` - 离线操作队列
- `OfflineOperationProcessor.swift` - 离线操作处理
- `OnlineStateManager.swift` - 在线状态管理
- `SaveQueueManager.swift` - 保存队列管理

#### Storage 子目录（3 个文件）
- `DatabaseService.swift` - SQLite 数据库
- `LocalStorageService.swift` - 本地文件存储
- `MemoryCacheManager.swift` - 内存缓存

#### Editor 子目录（3 个文件）
- `EditorConfiguration.swift` - 编辑器配置
- `EditorPreferencesService.swift` - 编辑器偏好设置
- `XiaoMiFormatConverter.swift` - 小米格式转换

#### Core 子目录（6 个文件）
- `AuthenticationStateManager.swift` - 认证状态
- `StartupSequenceManager.swift` - 启动序列
- `ScheduledTaskManager.swift` - 定时任务
- `ErrorRecoveryService.swift` - 错误恢复
- `PrivateNotesPasswordManager.swift` - 私密笔记密码
- `SilentCookieRefreshManager.swift` - Cookie 刷新

### NativeEditor 模块划分

```
┌─────────────────────────────────────────────────────────────┐
│                     NativeEditor/                            │
├─────────────┬─────────────┬─────────────┬─────────────┬─────┤
│   Core/     │  Format/    │ Attachment/ │   Debug/    │Perf/│
├─────────────┼─────────────┼─────────────┼─────────────┼─────┤
│EditorView   │FormatMgr    │AudioAttach  │Debugger     │Perf │
│EditorInit   │FormatSync   │ImageAttach  │Logger       │Fmt  │
│SafeRender   │FormatError  │CustomAttach │Metrics      │Perf │
│CustomRender │FormatHandler│ImageStorage │             │     │
│QuoteBlock   │FormatQueue  │             │             │     │
│             │FormatCheck  │             │             │     │
│             │...          │             │             │     │
└─────────────┴─────────────┴─────────────┴─────────────┴─────┘
```

#### Core 子目录（5 个文件）
- `NativeEditorView.swift` - 主编辑器视图
- `NativeEditorInitializer.swift` - 编辑器初始化
- `SafeRenderer.swift` - 安全渲染器
- `CustomRenderer.swift` - 自定义渲染器
- `QuoteBlockRenderer.swift` - 引用块渲染

#### Format 子目录（15 个文件）
- `FormatManager.swift` - 格式管理器
- `FormatStateSynchronizer.swift` - 格式状态同步
- `FormatError.swift` - 格式错误定义
- `FormatErrorHandler.swift` - 格式错误处理
- `FormatOperationQueue.swift` - 格式操作队列
- `FormatApplicationMethod.swift` - 格式应用方法
- `FormatApplicationConsistencyChecker.swift` - 格式一致性检查
- `FormatMenuDebugger.swift` - 格式菜单调试
- `FormatMenuDiagnostics.swift` - 格式菜单诊断
- `FormatMenuPerformanceMonitor.swift` - 格式菜单性能监控
- `MixedFormatApplicationHandler.swift` - 混合格式应用
- `MixedFormatStateHandler.swift` - 混合格式状态
- `CrossParagraphFormatHandler.swift` - 跨段落格式
- `SpecialElementFormatHandler.swift` - 特殊元素格式
- `UndoRedoStateHandler.swift` - 撤销重做状态
- `NativeFormatProvider.swift` - 原生格式提供者
- `EditorStateConsistencyChecker.swift` - 编辑器状态一致性

#### Attachment 子目录（4 个文件）
- `AudioAttachment.swift` - 音频附件
- `ImageAttachment.swift` - 图片附件
- `CustomAttachments.swift` - 自定义附件
- `ImageStorageManager.swift` - 图片存储管理

#### Debug 子目录（3 个文件）
- `NativeEditorDebugger.swift` - 编辑器调试器
- `NativeEditorLogger.swift` - 编辑器日志
- `NativeEditorMetrics.swift` - 编辑器指标

#### Performance 子目录（2 个文件）
- `PerformanceOptimizer.swift` - 性能优化器
- `FormatApplicationPerformanceOptimizer.swift` - 格式应用性能优化

### SwiftUIViews 模块划分

#### Audio 子目录（4 个文件）
- `AudioPanelView.swift`
- `AudioPlayerView.swift`
- `AudioRecorderView.swift`
- `AudioRecorderUploadView.swift`

#### Note 子目录（10 个文件）
- `NoteDetailView.swift`
- `NoteDetailWindowView.swift`
- `NoteCardView.swift`
- `NotesListView.swift`
- `NoteHistoryView.swift`
- `NewNoteView.swift`
- `MoveNoteView.swift`
- `MoveNoteMenuView.swift`
- `ExpandedNoteView.swift`
- `TitleEditorView.swift`

#### Settings 子目录（4 个文件）
- `SettingsView.swift`
- `EditorSettingsView.swift`
- `DebugSettingsView.swift`
- `ViewOptionsMenuView.swift`

#### Auth 子目录（4 个文件）
- `LoginView.swift`
- `CookieRefreshView.swift`
- `PrivateNotesPasswordInputDialogView.swift`
- `PrivateNotesVerificationView.swift`

#### Search 子目录（2 个文件）
- `SearchPanelView.swift`
- `SearchFilterMenuContent.swift`

#### Common 子目录（10 个文件）
- `ContentView.swift`
- `ContentAreaView.swift`
- `GalleryView.swift`
- `SidebarView.swift`
- `TrashView.swift`
- `NetworkLogView.swift`
- `OfflineOperationsProgressView.swift`
- `WebEditorView.swift`
- `NativeFormatMenuView.swift`
- `XMLDebugEditorView.swift`

### Window 层划分

#### Controllers 子目录（9 个文件）
- `MainWindowController.swift`
- `LoginWindowController.swift`
- `SettingsWindowController.swift`
- `HistoryWindowController.swift`
- `TrashWindowController.swift`
- `DebugWindowController.swift`
- `CookieRefreshWindowController.swift`
- `SearchPanelController.swift`
- `BaseSheetToolbarDelegate.swift`

#### State 子目录（6 个文件）
- `WindowStateManager.swift`
- `MainWindowState.swift`
- `NoteDetailWindowState.swift`
- `NotesListWindowState.swift`
- `SidebarWindowState.swift`
- `CustomSearchField.swift`

#### 根目录保留（3 个文件）
- `ToolbarIdentifiers.swift`
- `MiNoteToolbarItem.swift`

## 数据模型

本次重构不涉及数据模型变更，Model 目录保持不变。

## 正确性属性

*正确性属性是在系统所有有效执行中都应保持为真的特征或行为——本质上是关于系统应该做什么的形式化陈述。*

由于本次重构是结构性调整而非功能性变更，主要的正确性验证通过以下方式进行：

### 验证方式

1. **编译验证**：每个重构阶段完成后运行 `xcodebuild build` 确保编译通过
2. **测试验证**：运行 `xcodebuild test` 确保所有现有测试通过
3. **目录结构验证**：通过脚本检查目录结构是否符合预期

### 不变量

- **功能不变量**：重构前后所有功能行为保持一致
- **API 不变量**：所有公开接口保持不变
- **测试不变量**：所有现有测试继续通过

## 错误处理

### 重构风险

1. **文件移动导致编译失败**
   - 缓解：每移动一批文件后立即验证编译
   - 回滚：使用 Git 版本控制，可随时回滚

2. **import 路径问题**
   - 缓解：Swift 使用模块级导入，目录结构变化不影响 import
   - 注意：确保 project.yml 正确配置源文件路径

3. **Xcode 项目配置问题**
   - 缓解：使用 XcodeGen 自动生成项目文件
   - 验证：每次修改后重新生成并编译

## 测试策略

### 验证方法

由于这是结构重构而非功能变更，测试策略侧重于验证重构不破坏现有功能：

1. **编译测试**
   - 每个任务完成后运行 `xcodebuild build`
   - 确保无编译错误和警告

2. **单元测试**
   - 运行现有测试套件 `xcodebuild test`
   - 所有测试必须继续通过

3. **手动验证**
   - 重构完成后启动应用
   - 验证主要功能正常工作

### 检查点

在以下节点进行完整验证：
- Service 层重构完成后
- NativeEditor 重构完成后
- SwiftUIViews 重构完成后
- Window 层重构完成后
- 全部重构完成后
