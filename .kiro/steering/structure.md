# 项目结构

```
Sources/
├── App/                    # 应用程序入口
│   ├── App.swift           # SwiftUI 应用入口
│   ├── AppDelegate.swift   # AppKit 应用委托
│   ├── AppStateManager.swift
│   ├── MenuManager.swift   # 菜单系统
│   ├── MenuActionHandler.swift
│   ├── WindowManager.swift
│   └── Assets.xcassets/    # 资源文件
│
├── Model/                  # 数据模型
│   ├── Note.swift          # 笔记模型
│   ├── Folder.swift        # 文件夹模型
│   ├── DeletedNote.swift
│   ├── NoteHistoryVersion.swift
│   └── UserProfile.swift
│
├── Service/                # 业务服务层（模块化）
│   ├── Audio/              # 音频服务
│   │   ├── AudioCacheService.swift
│   │   ├── AudioConverterService.swift
│   │   ├── AudioDecryptService.swift
│   │   ├── AudioPlayerService.swift
│   │   ├── AudioRecorderService.swift
│   │   ├── AudioUploadService.swift
│   │   └── AudioPanelStateManager.swift
│   ├── Network/            # 网络服务
│   │   ├── MiNoteService.swift
│   │   ├── MiNoteService+Encryption.swift
│   │   ├── NetworkErrorHandler.swift
│   │   ├── NetworkLogger.swift
│   │   ├── NetworkMonitor.swift
│   │   ├── NetworkRecoveryHandler.swift
│   │   └── NetworkRequestManager.swift
│   ├── Sync/               # 同步服务
│   │   ├── SyncService.swift
│   │   ├── OfflineOperationQueue.swift
│   │   ├── OfflineOperationProcessor.swift
│   │   ├── OnlineStateManager.swift
│   │   └── SaveQueueManager.swift
│   ├── Storage/            # 存储服务
│   │   ├── DatabaseService.swift
│   │   ├── LocalStorageService.swift
│   │   └── MemoryCacheManager.swift
│   ├── Editor/             # 编辑器服务
│   │   ├── EditorConfiguration.swift
│   │   ├── EditorPreferencesService.swift
│   │   └── XiaoMiFormatConverter.swift
│   └── Core/               # 核心服务
│       ├── AuthenticationStateManager.swift
│       ├── StartupSequenceManager.swift
│       ├── ScheduledTaskManager.swift
│       ├── ErrorRecoveryService.swift
│       └── PrivateNotesPasswordManager.swift
│
├── ViewModel/              # 视图模型
│   ├── NotesViewModel.swift        # 主视图模型
│   ├── NoteMoveHelper.swift        # 笔记移动辅助
│   ├── ViewState.swift
│   └── ViewStateCoordinator.swift
│
├── View/                   # UI 视图组件
│   ├── AppKitComponents/   # AppKit 视图控制器
│   ├── Bridge/             # SwiftUI-AppKit 桥接
│   ├── NativeEditor/       # 原生富文本编辑器（模块化）
│   │   ├── Core/           # 核心编辑器组件
│   │   ├── Format/         # 格式化处理
│   │   ├── Attachment/     # 附件处理
│   │   ├── Debug/          # 调试工具
│   │   └── Performance/    # 性能优化
│   ├── SwiftUIViews/       # SwiftUI 视图（模块化）
│   │   ├── Audio/          # 音频相关视图
│   │   ├── Note/           # 笔记相关视图
│   │   ├── Settings/       # 设置相关视图
│   │   ├── Auth/           # 认证相关视图
│   │   ├── Search/         # 搜索相关视图
│   │   └── Common/         # 通用视图组件
│   └── Shared/             # 共享组件
│
├── Window/                 # 窗口管理（模块化）
│   ├── Controllers/        # 窗口控制器
│   │   ├── MainWindowController.swift
│   │   ├── LoginWindowController.swift
│   │   ├── SettingsWindowController.swift
│   │   └── ...
│   ├── State/              # 窗口状态
│   │   ├── WindowStateManager.swift
│   │   ├── MainWindowState.swift
│   │   └── ...
│   ├── ToolbarIdentifiers.swift
│   └── MiNoteToolbarItem.swift
│
├── ToolbarItem/            # 工具栏组件
├── Extensions/             # Swift 扩展
│
└── Web/                    # Web 编辑器
    ├── editor.html
    ├── converter/          # 格式转换器
    └── modules/            # JS 模块

Tests/
└── NativeEditorTests/      # 原生编辑器测试

References/                 # 参考项目和文档
```

## 架构分层

```
AppKit 控制器层 (AppDelegate, WindowController)
        ↓
SwiftUI 视图层 (View + ViewModel)
        ↓
服务层 (Service)
        ↓
数据模型层 (Model)
```

## 关键文件

- `AppDelegate.swift`: 应用生命周期、菜单系统
- `MainWindowController.swift`: 主窗口、工具栏、分割视图
- `NotesViewModel.swift`: 主业务逻辑和状态管理
- `MiNoteService.swift`: 小米笔记 API 调用
- `DatabaseService.swift`: SQLite 数据库操作
