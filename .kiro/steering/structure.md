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
├── Service/                # 业务服务层
│   ├── MiNoteService.swift         # 小米笔记 API
│   ├── DatabaseService.swift       # SQLite 数据库
│   ├── SyncService.swift           # 同步服务
│   ├── LocalStorageService.swift   # 本地文件存储
│   ├── MemoryCacheManager.swift    # 内存缓存
│   ├── SaveQueueManager.swift      # 保存队列
│   ├── OfflineOperationQueue.swift # 离线操作队列
│   ├── NetworkMonitor.swift        # 网络状态监控
│   └── ...
│
├── ViewModel/              # 视图模型
│   ├── NotesViewModel.swift        # 主视图模型
│   ├── ViewState.swift
│   └── ViewStateCoordinator.swift
│
├── View/                   # UI 视图组件
│   ├── AppKitComponents/   # AppKit 视图控制器
│   ├── Bridge/             # SwiftUI-AppKit 桥接
│   ├── NativeEditor/       # 原生富文本编辑器
│   ├── SwiftUIViews/       # SwiftUI 视图
│   └── Shared/             # 共享组件
│
├── Window/                 # 窗口控制器
│   ├── MainWindowController.swift
│   ├── LoginWindowController.swift
│   ├── SettingsWindowController.swift
│   └── ...
│
├── ToolbarItem/            # 工具栏组件
├── Extensions/             # Swift 扩展
├── Helper/                 # 辅助工具
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
