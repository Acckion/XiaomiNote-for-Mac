# 小米笔记 macOS 客户端 - 技术文档

## 目录

1. [项目概述](#项目概述)
2. [技术架构](#技术架构)
3. [核心模块](#核心模块)
4. [数据模型](#数据模型)
5. [服务层](#服务层)
6. [UI 层](#ui-层)
7. [窗口管理](#窗口管理)
8. [同步机制](#同步机制)
9. [离线操作](#离线操作)
10. [Web 编辑器](#web-编辑器)
11. [开发指南](#开发指南)
12. [设计规范](#设计规范)
13. [API 参考](#api-参考)

---

## 项目概述

### 项目简介

小米笔记 macOS 客户端是一个使用 **AppKit + SwiftUI 混合架构** 开发的原生 macOS 应用程序，通过调用小米笔记的 Web API 实现完整的笔记管理功能。

### 架构演进

项目经历了从纯 SwiftUI 到 AppKit+SwiftUI 混合架构的演进：

- **初始版本**: 纯 SwiftUI 架构，使用 SwiftUI 的 App 结构和 NavigationSplitView
- **当前版本**: AppKit+SwiftUI 混合架构，使用 AppDelegate、NSWindowController 和原生菜单系统
- **迁移原因**: 需要更好的窗口管理、原生工具栏、完整菜单系统、多窗口支持等 macOS 原生功能

### 技术栈

- **开发语言**: Swift 6.0
- **UI 框架**: AppKit + SwiftUI 混合架构
- **窗口管理**: NSWindowController, NSSplitViewController
- **富文本编辑**: 自定义 Web 编辑器（基于 CKEditor 5）
- **数据存储**: SQLite 3
- **网络请求**: URLSession
- **架构模式**: MVVM (Model-View-ViewModel) + AppKit 控制器
- **并发处理**: async/await, Task, Actor

### 系统要求

- macOS 14.0 或更高版本
- Xcode 15.0 或更高版本
- Swift 6.0

### 项目结构

```
SwiftUI-MiNote-for-Mac/
├── Sources/
│   ├── MiNoteLibrary/          # 核心库
│   │   ├── Model/              # 数据模型
│   │   │   ├── Note.swift
│   │   │   ├── Folder.swift
│   │   │   ├── DeletedNote.swift
│   │   │   ├── NoteHistoryVersion.swift
│   │   │   └── UserProfile.swift
│   │   ├── Service/             # 业务服务层
│   │   │   ├── MiNoteService.swift          # 小米笔记 API 服务
│   │   │   ├── DatabaseService.swift        # SQLite 数据库服务
│   │   │   ├── LocalStorageService.swift    # 本地文件存储服务
│   │   │   ├── SyncService.swift           # 同步服务
│   │   │   ├── OfflineOperationQueue.swift # 离线操作队列
│   │   │   ├── OfflineOperationProcessor.swift # 离线操作处理器
│   │   │   ├── NetworkMonitor.swift        # 网络状态监控
│   │   │   ├── AuthenticationStateManager.swift # 认证状态管理
│   │   │   ├── PrivateNotesPasswordManager.swift # 私密笔记密码管理
│   │   │   ├── SaveQueueManager.swift      # 保存队列管理器
│   │   │   └── MemoryCacheManager.swift    # 内存缓存管理器
│   │   ├── View/                # UI 视图组件
│   │   │   ├── AppKitComponents/           # AppKit 视图控制器
│   │   │   │   ├── NoteDetailViewController.swift
│   │   │   │   ├── NotesListViewController.swift
│   │   │   │   └── SidebarViewController.swift
│   │   │   ├── Bridge/                     # SwiftUI-AppKit 桥接
│   │   │   │   ├── NotesListHostingController.swift
│   │   │   │   ├── SidebarHostingController.swift
│   │   │   │   ├── WebEditorContext.swift
│   │   │   │   ├── WebEditorWrapper.swift
│   │   │   │   └── WebFormatMenuView.swift
│   │   │   ├── Shared/                     # 共享视图组件
│   │   │   │   └── OnlineStatusIndicator.swift
│   │   │   ├── SwiftUIViews/               # SwiftUI 视图
│   │   │   │   ├── ContentView.swift            # 主内容视图（三栏布局）
│   │   │   │   ├── NotesListView.swift          # 笔记列表视图
│   │   │   │   ├── NoteDetailView.swift         # 笔记详情/编辑视图
│   │   │   │   ├── SidebarView.swift            # 侧边栏视图
│   │   │   │   ├── WebEditorView.swift          # Web 编辑器视图
│   │   │   │   └── ...
│   │   ├── ViewModel/           # 视图模型
│   │   │   └── NotesViewModel.swift        # 主视图模型
│   │   ├── Window/              # 窗口控制器
│   │   │   ├── MainWindowController.swift       # 主窗口控制器
│   │   │   ├── LoginWindowController.swift      # 登录窗口控制器
│   │   │   ├── SettingsWindowController.swift   # 设置窗口控制器
│   │   │   ├── HistoryWindowController.swift    # 历史记录窗口控制器
│   │   │   ├── TrashWindowController.swift      # 回收站窗口控制器
│   │   │   ├── CookieRefreshWindowController.swift # Cookie刷新窗口控制器
│   │   │   ├── DebugWindowController.swift      # 调试窗口控制器
│   │   │   ├── WindowStateManager.swift         # 窗口状态管理器
│   │   │   └── ...
│   │   ├── Extensions/          # 扩展
│   │   │   └── NSWindow+MiNote.swift
│   │   ├── Helper/              # 辅助工具
│   │   │   └── NoteMoveHelper.swift
│   │   └── Web/                 # Web 编辑器相关文件
│   │       ├── editor.html                  # 编辑器 HTML
│   │       ├── xml-to-html.js               # XML 转 HTML 转换器
│   │       └── html-to-xml.js               # HTML 转 XML 转换器
│   └── MiNoteMac/               # 应用程序入口
│       ├── AppDelegate.swift                # AppKit 应用委托
│       ├── App.swift                        # SwiftUI App（已弃用）
│       └── Resources/                       # 资源文件
├── build/                       # 构建产物
├── MiNoteMac.xcodeproj/        # Xcode 项目文件
└── README.md                    # 项目说明
```

---

## 技术架构

### 架构模式

项目采用 **混合架构模式**，结合了 AppKit 的控制器模式和 SwiftUI 的声明式 UI：

```
┌─────────────────────────────────────────────────────────┐
│                    AppKit 控制器层                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ AppDelegate │  │ WindowCtrl  │  │ ViewCtrl    │    │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘    │
│         │                │                 │           │
│         ▼                ▼                 ▼           │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                 SwiftUI 视图层 (MVVM)                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │    View     │◄─┤  ViewModel  │◄─┤   Service   │    │
│  │  (SwiftUI)  │  │ (Observable)│  │   Layer     │    │
│  └─────────────┘  └──────┬──────┘  └──────┬──────┘    │
│         │                 │                 │           │
│         ▼                 ▼                 ▼           │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                    数据模型层                            │
│                  ┌─────────────┐                       │
│                  │    Model    │                       │
│                  │  (Struct)   │                       │
│                  └─────────────┘                       │
└─────────────────────────────────────────────────────────┘
```

### 各层职责

1. **AppKit 控制器层**:
   - `AppDelegate`: 应用程序生命周期管理、菜单系统
   - `WindowController`: 窗口管理、工具栏、窗口状态
   - `ViewController`: 视图控制器，管理 SwiftUI 视图

2. **SwiftUI 视图层 (MVVM)**:
   - `View`: SwiftUI 声明式 UI
   - `ViewModel`: 业务逻辑、状态管理
   - `Service`: API 调用、数据库操作、文件存储

3. **数据模型层**:
   - `Model`: 数据结构定义

### 数据流

1. **用户操作** → AppKit 控制器接收事件
2. **控制器** → 调用 ViewModel 方法
3. **ViewModel** → 处理业务逻辑，更新 `@Published` 状态
4. **Service** → 执行具体操作（API、数据库、文件）
5. **Model** → 数据更新
6. **ViewModel** → 状态变化触发 SwiftUI View 自动更新

### 线程模型

- **主线程**: 所有 UI 更新、AppKit 操作、ViewModel 操作（使用 `@MainActor`）
- **后台线程**: 网络请求、数据库操作、文件 I/O、离线操作处理
- **并发处理**: 使用 `async/await` 和 `Task` 进行异步操作
- **线程安全**: 数据库操作使用并发队列，网络请求使用异步任务

---

## 核心模块

### 1. 应用程序层 (AppKit)

#### AppDelegate

**职责**:
- 应用程序生命周期管理
- 菜单系统设置和管理
- 多窗口管理
- 应用程序状态保存和恢复

**关键特性**:
- 完整的 macOS 菜单系统（文件、编辑、格式、显示、窗口、帮助）
- 多窗口支持（新建窗口、窗口状态恢复）
- 应用程序状态持久化
- 应用程序重新打开处理

#### MainWindowController

**职责**:
- 主窗口管理和配置
- 工具栏设置和验证
- 窗口状态保存和恢复
- 分割视图管理

**关键特性**:
- 三栏分割视图（侧边栏、笔记列表、笔记详情）
- 完整的工具栏系统（新建、格式、搜索、同步等）
- 窗口状态持久化
- 工具栏项验证和状态管理

### 2. 数据模型层 (Model)

#### Note (笔记模型)

```swift
public struct Note: Identifiable, Codable, Hashable {
    public let id: String
    public var title: String
    public var content: String          // XML 格式（小米笔记格式）
    public var folderId: String
    public var isStarred: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String]
    public var rawData: [String: Any]?  // 原始 API 数据（包含 tag 等）
    public var htmlContent: String?     // HTML 缓存内容
}
```

**关键特性**:
- `content`: 存储为 XML 格式，兼容小米笔记服务器
- `rawData`: 保存完整的 API 响应数据，包含 `tag`、`createDate` 等字段
- `htmlContent`: HTML 格式缓存，用于快速显示
- 实现 `Hashable` 和 `Equatable`，支持 SwiftUI 列表更新

#### Folder (文件夹模型)

```swift
public struct Folder: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var count: Int
    public var isSystem: Bool
    public var isPinned: Bool
    public var createdAt: Date
    public var rawData: [String: Any]?
}
```

**系统文件夹**:
- `id = "0"`: 所有笔记
- `id = "starred"`: 置顶笔记
- `id = "2"`: 私密笔记
- `id = "uncategorized"`: 未分类笔记

### 3. 服务层 (Service)

#### MiNoteService (小米笔记 API 服务)

**职责**:
- 管理 Cookie 和 ServiceToken 认证
- 实现所有小米笔记 API 调用
- 处理 API 错误和重试逻辑
- Cookie 过期检测和处理

**主要方法**:
- `fetchNotes()`: 获取笔记列表
- `createNote(_:)`: 创建笔记
- `updateNote(_:)`: 更新笔记
- `deleteNote(_:)`: 删除笔记
- `uploadImage(_:)`: 上传图片
- `fetchFolders()`: 获取文件夹列表
- `createFolder(_:)`: 创建文件夹
- `deleteFolder(_:)`: 删除文件夹

**认证机制**:
- 使用 Cookie 字符串进行认证
- 从 Cookie 中提取 `serviceToken` 作为 API 参数
- Cookie 过期时触发回调，显示登录界面

#### DatabaseService (数据库服务)

**职责**:
- SQLite 数据库的初始化和连接管理
- 笔记和文件夹的 CRUD 操作
- 离线操作队列管理
- 同步状态管理
- HTML 内容缓存管理

**数据库表结构**:

1. **notes 表**: 存储笔记数据
   - `id`, `title`, `content`, `folder_id`, `is_starred`
   - `created_at`, `updated_at`, `tags`, `raw_data`, `html_content`

2. **folders 表**: 存储文件夹数据
   - `id`, `name`, `count`, `is_system`, `is_pinned`, `created_at`, `raw_data`

3. **offline_operations 表**: 存储离线操作
   - `id`, `type`, `note_id`, `data`, `created_at`
   - `priority`, `retry_count`, `last_error`, `status`

4. **sync_status 表**: 存储同步状态（单行表）
   - `last_sync_time`, `sync_tag`, `last_full_sync_time`

5. **pending_deletions 表**: 存储待删除的笔记
   - `note_id`, `deleted_at`

**线程安全**:
- 使用并发队列 (`DispatchQueue`) 确保线程安全
- 使用 `SQLITE_OPEN_FULLMUTEX` 标志支持多线程访问
- 提供异步 API 避免阻塞主线程

#### LocalStorageService (本地文件存储服务)

**职责**:
- 图片文件的本地缓存管理
- 文件夹配置的持久化存储
- 用户设置的存储

**存储位置**:
- 图片: `~/Documents/MiNoteImages/{folderId}/{fileId}.{ext}`
- 配置: `UserDefaults`

#### SyncService (同步服务)

**职责**:
- 完整同步（清除本地数据，从云端拉取全部）
- 增量同步（使用 `syncTag` 获取增量更改）
- 冲突解决（基于时间戳比较）
- 双向同步（上传本地更改，下载云端更改）

**同步策略**:
- **完整同步**: 首次同步或手动触发
- **增量同步**: 使用 `syncTag` 获取自上次同步后的更改
- **冲突解决**: 比较 `modifyDate`，保留最新的版本

#### MemoryCacheManager (内存缓存管理器)

**职责**:
- 笔记对象的内存缓存
- 快速切换笔记时的内容预加载
- 缓存失效和更新管理

**缓存策略**:
- LRU（最近最少使用）缓存策略
- 按需加载和缓存
- 内存压力时自动清理

#### SaveQueueManager (保存队列管理器)

**职责**:
- 管理笔记保存任务的队列
- 合并相同笔记的多次保存
- 优先级管理（立即保存 vs 延迟保存）

**队列特性**:
- 防抖机制减少不必要的保存
- 优先级队列确保重要操作优先执行
- 错误重试机制

### 4. 视图模型层 (ViewModel)

#### NotesViewModel

**职责**:
- 管理应用的主要业务逻辑和状态
- 笔记和文件夹的数据管理
- 同步操作协调
- UI 状态管理（加载、错误、搜索等）
- Web 编辑器上下文管理

**主要状态**:
- `notes: [Note]`: 笔记列表
- `folders: [Folder]`: 文件夹列表
- `selectedNote: Note?`: 当前选中的笔记
- `selectedFolder: Folder?`: 当前选中的文件夹
- `searchText: String`: 搜索文本
- `isSyncing: Bool`: 是否正在同步
- `isLoggedIn: Bool`: 是否已登录
- `isCookieExpired: Bool`: Cookie 是否过期
- `webEditorContext: WebEditorContext`: Web 编辑器上下文

**主要方法**:
- `loadNotes()`: 加载笔记列表
- `createNote()`: 创建新笔记
- `updateNote(_:)`: 更新笔记
- `deleteNote(_:)`: 删除笔记
- `syncNotes()`: 同步笔记
- `processPendingOperations()`: 处理离线操作
- `ensureNoteHasFullContent(_:)`: 确保笔记有完整内容

**线程安全**:
- 使用 `@MainActor` 确保所有操作在主线程执行
- 使用 `@Published` 属性包装器实现响应式更新

---

## 数据模型

### Note 数据模型详解

#### 内容格式

笔记内容使用 **XML 格式**存储，兼容小米笔记服务器：

```xml
<note>
  <p>段落文本</p>
  <p><strong>加粗文本</strong></p>
  <p><em>斜体文本</em></p>
  <ul>
    <li>列表项 1</li>
    <li>列表项 2</li>
  </ul>
  <img src="fileId" />
</note>
```

#### rawData 结构

`rawData` 包含完整的 API 响应数据：

```swift
[
  "id": "note_id",
  "title": "笔记标题",
  "content": "XML 内容",
  "folderId": "folder_id",
  "isStarred": false,
  "createDate": 1234567890,
  "modifyDate": 1234567890,
  "tag": "sync_tag",
  "setting": [
    "data": [
      [
        "fileId": "image_file_id",
        "mimeType": "image/png"
      ]
    ]
  ]
]
```

### Folder 数据模型详解

#### 系统文件夹

- **所有笔记** (`id = "0"`): 显示所有非私密笔记
- **置顶** (`id = "starred"`): 显示所有置顶笔记
- **私密笔记** (`id = "2"`): 显示所有私密笔记（需要密码）
- **未分类** (`id = "uncategorized"`): 显示 `folderId` 为 "0" 或空的笔记

---

## 服务层

### MiNoteService API 调用

#### 认证流程

1. 用户登录，获取 Cookie
2. 从 Cookie 中提取 `serviceToken`
3. 所有 API 请求携带 Cookie 和 `serviceToken`

#### API 端点

- **获取笔记列表**: `GET /note/v2/user/notes`
- **创建笔记**: `POST /note/v2/user/note`
- **更新笔记**: `POST /note/v2/user/note`
- **删除笔记**: `POST /note/v2/user/note/delete`
- **获取文件夹列表**: `GET /note/v2/user/folders`
- **创建文件夹**: `POST /note/v2/user/folder`
- **删除文件夹**: `POST /note/v2/user/folder/delete`
- **上传图片**: `POST /file/v2/user/upload_file`

#### 错误处理

- **401 错误**: Cookie 过期，触发登录流程
- **网络错误**: 添加到离线操作队列
- **服务器错误**: 显示错误提示，支持重试

### DatabaseService 数据库操作

#### 数据库初始化

```swift
// 数据库位置
~/Library/Application Support/MiNoteMac/minote.db

// 初始化步骤
1. 创建数据库文件
2. 创建所有表
3. 执行数据库迁移（如果需要）
4. 设置外键约束
```

#### 主要操作

- **笔记操作**: `saveNote()`, `loadNote()`, `deleteNote()`, `getAllNotes()`
- **文件夹操作**: `saveFolder()`, `loadFolder()`, `deleteFolder()`, `getAllFolders()`
- **离线操作**: `addOfflineOperation()`, `getAllOfflineOperations()`, `deleteOfflineOperation()`
- **同步状态**: `saveSyncStatus()`, `loadSyncStatus()`
- **HTML 缓存**: `updateHTMLContentOnly()`, `getHTMLContent()`

### LocalStorageService 文件存储

#### 图片存储

```
~/Documents/MiNoteImages/
  ├── {folderId}/
  │   ├── {fileId}.png
  │   ├── {fileId}.jpg
  │   └── ...
```

#### 图片操作

- `saveImage(fileId:fileType:data:)`: 保存图片
- `loadImage(fileId:fileType:)`: 加载图片
- `deleteImage(fileId:fileType:)`: 删除图片
- `deleteFolderImageDirectory(folderId:)`: 删除文件夹的所有图片

### MemoryCacheManager 内存缓存

#### 缓存策略

- **缓存类型**: 笔记对象完整缓存
- **缓存大小**: 动态调整，基于可用内存
- **失效策略**: LRU（最近最少使用）
- **更新机制**: 笔记保存时自动更新缓存

#### 主要方法

- `cacheNote(_:)`: 缓存笔记对象
- `getNote(noteId:)`: 获取缓存的笔记
- `clearCache()`: 清空缓存
- `removeNote(noteId:)`: 移除特定笔记缓存

### SaveQueueManager 保存队列

#### 队列特性

- **优先级管理**: 高优先级（立即保存）、普通优先级（防抖保存）
- **防抖机制**: 相同笔记的多次保存合并为一次
- **错误处理**: 保存失败时自动重试
- **并发控制**: 控制同时进行的保存操作数量

#### 主要方法

- `enqueueSave(_:priority:)`: 加入保存队列
- `processQueue()`: 处理队列中的保存任务
- `cancelSave(forNoteId:)`: 取消特定笔记的保存任务

---

## UI 层

### 混合架构 UI 设计

项目采用 **AppKit 控制器 + SwiftUI 视图** 的混合架构：

#### AppKit 视图控制器

1. **NoteDetailViewController**
   - 管理笔记详情视图
   - 托管 SwiftUI 的 NoteDetailView
   - 处理窗口状态保存和恢复

2. **NotesListViewController** 
   - 管理笔记列表视图
   - 托管 SwiftUI 的 NotesListView
   - 处理列表选择和搜索

3. **SidebarViewController**
   - 管理侧边栏视图
   - 托管 SwiftUI 的 SidebarView
   - 处理文件夹选择和导航

#### SwiftUI 视图

1. **NoteDetailView** (笔记详情/编辑视图)
   - 标题编辑和显示
   - Web 编辑器集成
   - 保存状态指示器
   - 格式工具栏

2. **NotesListView** (笔记列表视图)
   - 按时间分组显示笔记
   - 搜索高亮和筛选
   - 笔记预览（标题、时间、内容片段）
   - 滑动操作（删除、置顶）

3. **SidebarView** (侧边栏视图)
   - 文件夹列表显示
   - 系统文件夹（所有笔记、置顶、私密笔记、未分类）
   - 自定义文件夹管理
   - 文件夹计数显示

4. **WebEditorView** (Web 编辑器视图)
   - 富文本编辑功能
   - 格式工具栏集成
   - 图片插入和显示
   - 撤销/重做支持

### 视图桥接

#### NSHostingController 使用

项目使用 `NSHostingController` 将 SwiftUI 视图嵌入到 AppKit 视图控制器中：

```swift
// 示例：在 AppKit 视图控制器中托管 SwiftUI 视图
class NoteDetailViewController: NSViewController {
    private var hostingController: NSHostingController<NoteDetailView>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 创建 SwiftUI 视图
        let noteDetailView = NoteDetailView(viewModel: viewModel)
        
        // 创建托管控制器
        hostingController = NSHostingController(rootView: noteDetailView)
        
        // 添加托管视图
        if let hostingView = hostingController?.view {
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hostingView)
            
            // 设置约束
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: view.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
}
```

#### WebEditorContext 桥接

`WebEditorContext` 作为 SwiftUI 和 Web 编辑器之间的桥梁：

- **双向通信**: SwiftUI ↔ JavaScript
- **状态管理**: 编辑器状态、内容、格式
- **命令执行**: 格式命令、插入操作、撤销/重做

---

## 窗口管理

### MainWindowController

#### 窗口配置

- **窗口样式**: 标题栏、关闭按钮、最小化按钮、缩放按钮、全尺寸内容视图
- **工具栏**: 自定义工具栏，支持用户定制
- **分割视图**: 三栏布局（侧边栏、笔记列表、笔记详情）
- **最小尺寸**: 600×400 像素

#### 工具栏系统

**工具栏项类型**:
1. **按钮项**: 新建笔记、新建文件夹、同步等
2. **格式项**: 粗体、斜体、下划线、删除线等
3. **菜单项**: 在线状态、笔记操作、测试菜单
4. **搜索项**: 笔记搜索
5. **分隔符**: 跟踪分隔符（连接到分割视图）
6. **空间项**: 弹性空间、固定空间

**工具栏标识符**:
- `.newNote`, `.newFolder`: 新建操作
- `.bold`, `.italic`, `.underline`: 格式操作
- `.formatMenu`: 格式菜单
- `.search`: 搜索框
- `.sync`, `.onlineStatus`: 同步和状态
- `.settings`, `.login`, `.cookieRefresh`: 设置和登录
- `.noteOperations`, `.testMenu`: 菜单项
- `.sidebarTrackingSeparator`, `.timelineTrackingSeparator`: 跟踪分隔符

#### 窗口状态管理

**状态保存**:
- 窗口位置和大小
- 分割视图各栏宽度
- 侧边栏显示/隐藏状态
- 各视图控制器的状态

**状态恢复**:
- 应用程序启动时恢复窗口状态
- 新建窗口时应用默认或保存的状态
- 窗口关闭时自动保存状态

### 多窗口支持

#### 窗口创建

- **主窗口**: 应用程序启动时创建
- **新建窗口**: 通过菜单或快捷键创建新窗口
- **专用窗口**: 登录、设置、历史记录、回收站等专用窗口

#### 窗口生命周期

1. **创建**: 使用 `MainWindowController` 初始化窗口
2. **配置**: 设置窗口属性、工具栏、内容视图
3. **显示**: 显示窗口并置于前台
4. **管理**: 跟踪窗口引用，防止内存泄漏
5. **关闭**: 清理资源，保存状态

#### 窗口控制器管理

- **引用管理**: 保持窗口控制器引用，防止提前释放
- **清理机制**: 窗口关闭时自动清理引用
- **状态同步**: 多窗口间的状态同步（通过共享 ViewModel）

### 专用窗口控制器

#### LoginWindowController
- 登录界面管理
- Cookie 输入和处理
- 登录状态反馈

#### SettingsWindowController
- 应用程序设置
- 同步配置
- 外观设置

#### HistoryWindowController
- 笔记历史版本查看
- 版本对比和恢复
- 历史记录管理

#### TrashWindowController
- 回收站管理
- 删除笔记查看和恢复
- 永久删除操作

#### CookieRefreshWindowController
- Cookie 刷新界面
- 自动刷新机制
- 刷新状态反馈

#### DebugWindowController
- 调试信息显示
- 网络日志查看
- 系统状态监控

---

## 同步机制

### 同步类型

#### 1. 完整同步

**触发时机**:
- 首次启动应用
- 手动触发完整同步
- 同步状态丢失或损坏

**流程**:
1. 清除本地所有笔记和文件夹
2. 从云端获取所有数据
3. 保存到本地数据库
4. 更新同步状态

#### 2. 增量同步

**触发时机**:
- 定期自动同步（默认 5 分钟）
- 网络恢复时
- 手动触发同步

**流程**:
1. 获取本地 `syncTag`
2. 调用增量同步 API，传入 `syncTag`
3. 获取自上次同步后的更改
4. 合并更改到本地数据库
5. 上传本地待同步的更改
6. 更新 `syncTag`

### 冲突解决

**策略**: 基于时间戳比较

- 比较 `modifyDate`（修改时间）
- 保留时间戳更新的版本
- 如果时间戳相同，保留云端版本

### 同步状态管理

**存储位置**: `sync_status` 表（单行表）

**字段**:
- `last_sync_time`: 上次同步时间
- `sync_tag`: 同步标签（用于增量同步）
- `last_full_sync_time`: 上次完整同步时间

---

## 离线操作

### 离线操作队列

**存储**: SQLite 数据库 `offline_operations` 表

**操作类型**:
- `createNote`: 创建笔记
- `updateNote`: 更新笔记
- `deleteNote`: 删除笔记
- `uploadImage`: 上传图片
- `createFolder`: 创建文件夹
- `renameFolder`: 重命名文件夹
- `deleteFolder`: 删除文件夹

### 操作去重和合并

**去重规则**:
- 同一笔记的多个 `updateNote` → 只保留最新的
- `createNote + updateNote` → 合并为 `createNote`（使用最新内容）
- `createNote + deleteNote` → 删除两个操作（无操作）
- `updateNote + deleteNote` → 只保留 `deleteNote`

### 操作优先级

**优先级计算**:
- `createNote`: 优先级 10
- `updateNote`: 优先级 5
- `deleteNote`: 优先级 15（最高）
- `uploadImage`: 优先级 8
- 文件夹操作: 优先级 3

**处理顺序**: 按优先级降序处理

### 智能重试机制

**重试策略**: 指数退避

- 第 1 次重试: 延迟 5 秒
- 第 2 次重试: 延迟 10 秒
- 第 3 次重试: 延迟 20 秒
- 最大重试次数: 3 次

**错误分类**:
- **可重试错误**: 网络错误、临时服务器错误
- **不可重试错误**: 认证错误、数据格式错误

### 并发处理

**配置**:
- 默认最大并发数: 3
- 可配置调整

**实现**: 使用 `TaskGroup` 并发执行多个操作

---

## Web 编辑器

### 架构设计

**技术栈**:
- HTML + JavaScript (CKEditor 5 风格)
- `WKWebView` 加载编辑器
- JavaScript 桥接实现双向通信

### 格式转换

#### XML → HTML

**转换器**: `xml-to-html.js`

**转换规则**:
- `<p>` → `<p>`
- `<strong>` → `<strong>`
- `<em>` → `<em>`
- `<u>` → `<u>`
- `<s>` → `<s>`
- `<mark>` → `<mark>`
- `<ul><li>` → `<ul><li>`
- `<ol><li>` → `<ol><li>`
- `<img src="fileId" />` → `<img src="local_path" />`

#### HTML → XML

**转换器**: `html-to-xml.js`

**转换规则**:
- 反向转换，将 HTML 格式转换回小米笔记 XML 格式
- 处理图片路径转换（本地路径 → fileId）

### 编辑器通信

**Swift → JavaScript**:
```swift
webView.evaluateJavaScript("editor.setContent('\(html)')")
```

**JavaScript → Swift**:
```javascript
webkit.messageHandlers.editor.postMessage({
  type: 'contentChanged',
  content: html
})
```

### 编辑器功能

**文本格式**:
- 加粗 (`<strong>`)
- 斜体 (`<em>`)
- 下划线 (`<u>`)
- 删除线 (`<s>`)
- 高亮 (`<mark>`)

**标题**:
- 大标题 (H1)
- 二级标题 (H2)
- 三级标题 (H3)

**列表**:
- 无序列表 (`<ul>`)
- 有序列表 (`<ol>`)
- 复选框列表 (`<input type="checkbox">`)

**其他**:
- 文本对齐（左、中、右）
- 缩进（增加、减少）
- 分割线 (`<hr>`)
- 图片插入

---

## 开发指南

### 项目设置

#### 1. 环境准备

```bash
# 检查 Swift 版本
swift --version  # 需要 6.0+

# 检查 Xcode 版本
xcodebuild -version  # 需要 15.0+
```

#### 2. 打开项目

```bash
# 使用 Xcode 打开
open MiNoteMac.xcodeproj
```

#### 3. 构建项目

```bash
# 在 Xcode 中按 ⌘R 运行
# 或使用命令行
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug
```

### 代码规范

#### 命名规范

- **类型**: 使用 PascalCase（`Note`, `NotesViewModel`）
- **变量/函数**: 使用 camelCase（`selectedNote`, `loadNotes()`）
- **常量**: 使用 camelCase（`baseURL`, `maxRetryCount`）
- **私有成员**: 使用 `private` 关键字

#### 注释规范

- **类/结构体**: 使用文档注释 `///`
- **方法**: 使用文档注释说明参数、返回值、功能
- **复杂逻辑**: 使用行内注释说明

#### 线程安全

- **UI 更新**: 必须在主线程（使用 `@MainActor`）
- **数据库操作**: 使用 `DatabaseService` 的并发队列
- **网络请求**: 使用 `async/await` 在后台线程执行

### 调试技巧

#### 日志格式

所有调试日志使用统一格式：

```swift
print("[ClassName] 日志内容")
```

**关键日志标记**:
- `[[调试]]`: 重要调试信息
- `[VIEWMODEL]`: ViewModel 相关日志
- `[MiNoteService]`: API 服务相关日志
- `[Database]`: 数据库相关日志
- `[保存流程]`: 笔记保存相关日志
- `[快速切换]`: 笔记切换相关日志
- `[窗口管理]`: 窗口状态相关日志

#### 调试工具

- **Xcode 调试器**: 设置断点、查看变量
- **控制台日志**: 查看 `print` 输出
- **网络日志**: `NetworkLogger` 记录所有网络请求
- **数据库查看**: 使用 SQLite 工具查看数据库文件
- **内存调试**: 使用 Instruments 分析内存使用

### 测试

#### 单元测试

```swift
// 示例：测试笔记创建
func testCreateNote() async throws {
    let note = Note(...)
    try await viewModel.createNote(note)
    XCTAssertNotNil(viewModel.notes.first { $0.id == note.id })
}
```

#### 集成测试

- 测试完整同步流程
- 测试离线操作处理
- 测试冲突解决
- 测试窗口状态保存和恢复

### 常见问题

#### 1. Cookie 过期

**症状**: API 调用返回 401 错误

**解决**: 
- 自动显示登录界面
- 用户重新登录后更新 Cookie

#### 2. 同步冲突

**症状**: 本地和云端数据不一致

**解决**:
- 基于时间戳自动解决冲突
- 保留时间戳更新的版本

#### 3. 离线操作失败

**症状**: 离线操作一直重试失败

**解决**:
- 检查网络连接
- 检查 Cookie 是否有效
- 查看错误日志确定具体原因

#### 4. 窗口状态丢失

**症状**: 应用程序重启后窗口位置和大小恢复不正确

**解决**:
- 检查窗口状态保存逻辑
- 确保状态保存和恢复的时机正确
- 验证状态数据的完整性

---

## 设计规范

### 文件结构规范

#### 目录结构

```
Sources/MiNoteLibrary/
├── Model/              # 数据模型
│   ├── Note.swift
│   ├── Folder.swift
│   └── ...
├── Service/            # 服务层
│   ├── MiNoteService.swift
│   ├── DatabaseService.swift
│   └── ...
├── View/               # UI 视图
│   ├── AppKitComponents/    # AppKit 视图控制器
│   ├── Bridge/              # SwiftUI-AppKit 桥接
│   ├── SwiftUIViews/        # SwiftUI 视图
│   └── Shared/              # 共享视图组件
├── ViewModel/          # 视图模型
│   └── NotesViewModel.swift
├── Window/             # 窗口控制器
│   ├── MainWindowController.swift
│   ├── LoginWindowController.swift
│   └── ...
├── Extensions/         # 扩展
├── Helper/             # 辅助工具
└── Web/                # Web 编辑器文件
```

#### 文件命名规范

- **Swift 文件**: 使用 PascalCase，如 `NoteDetailViewController.swift`
- **资源文件**: 使用 snake_case，如 `editor.html`
- **配置文件**: 使用 kebab-case，如 `project.yml`

### 代码组织规范

#### 混合架构代码组织

1. **AppKit 控制器**:
   - 放置在 `Window/` 目录（窗口控制器）
   - 放置在 `View/AppKitComponents/` 目录（视图控制器）
   - 使用 `NSWindowController` 或 `NSViewController` 子类

2. **SwiftUI 视图**:
   - 放置在 `View/SwiftUIViews/` 目录
   - 使用 `View` 协议实现
   - 通过 `@ObservedObject` 绑定 ViewModel

3. **桥接代码**:
   - 放置在 `View/Bridge/` 目录
   - 使用 `NSHostingController` 包装 SwiftUI 视图
   - 实现 SwiftUI 和 AppKit 之间的数据传递

#### 依赖关系

- **上层依赖下层**: View → ViewModel → Service → Model
- **避免循环依赖**: 使用协议和依赖注入
- **模块化设计**: 各模块职责清晰，接口明确

### 开发流程规范

#### 新功能开发流程

1. **需求分析**: 明确功能需求和界面设计
2. **架构设计**: 确定使用 AppKit 还是 SwiftUI，或混合使用
3. **数据模型**: 设计或扩展数据模型
4. **服务层**: 实现业务逻辑和数据操作
5. **ViewModel**: 实现状态管理和业务逻辑
6. **UI 层**: 实现界面（AppKit 控制器或 SwiftUI 视图）
7. **测试**: 单元测试和集成测试
8. **文档**: 更新技术文档和 API 文档

#### 代码审查要点

- **架构一致性**: 符合混合架构设计原则
- **代码质量**: 遵循代码规范，无警告和错误
- **性能考虑**: 内存使用、响应速度、电池消耗
- **安全性**: 数据加密、认证安全、输入验证
- **可维护性**: 代码清晰、注释完整、易于修改

### 窗口和视图管理规范

#### 窗口创建和管理

1. **主窗口**: 使用 `MainWindowController` 管理
2. **模态窗口**: 使用 `NSWindowController` 子类
3. **窗口状态**: 实现 `savableWindowState()` 和 `restoreWindowState(_:)`
4. **窗口生命周期**: 正确处理创建、显示、隐藏、关闭

#### 视图控制器使用

1. **AppKit 视图控制器**: 管理特定区域的 UI
2. **SwiftUI 托管**: 使用 `NSHostingController` 包装 SwiftUI 视图
3. **状态传递**: 通过 ViewModel 在视图间传递状态
4. **生命周期**: 正确处理 `viewDidLoad()`、`viewWillAppear()` 等

### 性能优化规范

#### 内存优化

1. **缓存策略**: 合理使用内存缓存和磁盘缓存
2. **图片优化**: 压缩图片，按需加载
3. **对象生命周期**: 及时释放不再使用的对象
4. **循环引用**: 避免强引用循环，使用 `weak` 或 `unowned`

#### 响应速度优化

1. **异步操作**: 使用 `async/await` 避免阻塞主线程
2. **防抖机制**: 减少不必要的操作（如保存、搜索）
3. **懒加载**: 按需加载数据和视图
4. **预加载**: 预加载可能需要的资源

#### 电池消耗优化

1. **网络请求**: 合并请求，减少频率
2. **定时任务**: 合理设置定时器间隔
3. **后台任务**: 优化后台同步和处理
4. **资源使用**: 减少不必要的 CPU 和内存使用

### 错误处理规范

#### 错误分类

1. **用户错误**: 输入错误、操作错误
2. **网络错误**: 连接失败、超时、服务器错误
3. **数据错误**: 数据格式错误、数据不一致
4. **系统错误**: 内存不足、磁盘空间不足、权限错误

#### 错误处理策略

1. **用户友好**: 显示清晰的错误信息，提供解决方案
2. **自动恢复**: 尽可能自动恢复错误状态
3. **错误日志**: 记录详细的错误信息，便于调试
4. **错误上报**: 重要错误上报到服务器（可选）

---

## API 参考

### NotesViewModel

#### 数据属性

```swift
@Published var notes: [Note]
@Published var folders: [Folder]
@Published var selectedNote: Note?
@Published var selectedFolder: Folder?
@Published var searchText: String
@Published var isSyncing: Bool
@Published var isLoggedIn: Bool
@Published var isCookieExpired: Bool
@Published var showLoginView: Bool
@Published var showCookieRefreshView: Bool
@Published var showTrashView: Bool
```

#### 主要方法

```swift
// 笔记操作
func createNote() async throws
func createNewNote() -> Note
func updateNote(_ note: Note) async throws
func deleteNote(_ note: Note) async throws
func toggleStar(_ note: Note)

// 文件夹操作
func createFolder(name: String) async throws
func renameFolder(_ folder: Folder, newName: String) async throws
func deleteFolder(_ folder: Folder, purge: Bool) async throws

// 同步操作
func syncNotes() async throws
func performFullSync() async
func performIncrementalSync() async
func processPendingOperations() async
func resetSyncStatus()

// 搜索和筛选
var filteredNotes: [Note] { get }

// 内容管理
func ensureNoteHasFullContent(_ note: Note) async
func uploadImageAndInsertToNote(imageURL: URL) async throws -> String

// 状态管理
var pendingOperationsCount: Int { get }
var lastSyncTime: Date? { get }
```

### MiNoteService

#### 主要方法

```swift
// 认证
func setCookie(_ cookie: String)
func isAuthenticated() -> Bool
func checkCookieExpiration() async -> Bool

// 笔记操作
func fetchNotes() async throws -> [Note]
func createNote(_ note: Note) async throws -> Note
func updateNote(_ note: Note) async throws -> Note
func deleteNote(_ note: Note) async throws

// 文件夹操作
func fetchFolders() async throws -> [Folder]
func createFolder(name: String) async throws -> Folder
func deleteFolder(folderId: String, tag: String, purge: Bool) async throws

// 文件操作
func uploadImage(_ imageData: Data, fileName: String) async throws -> [String: Any]

// 同步操作
func performFullSync() async throws -> SyncResult
func performIncrementalSync(syncTag: String) async throws -> SyncResult
```

### DatabaseService

#### 主要方法

```swift
// 笔记操作
func saveNote(_ note: Note) throws
func saveNoteAsync(_ note: Note, completion: @escaping (Error?) -> Void)
func loadNote(noteId: String) throws -> Note?
func deleteNote(noteId: String) throws
func getAllNotes() throws -> [Note]

// 文件夹操作
func saveFolder(_ folder: Folder) throws
func loadFolder(folderId: String) throws -> Folder?
func deleteFolder(folderId: String) throws
func getAllFolders() throws -> [Folder]

// 离线操作
func addOfflineOperation(_ operation: OfflineOperation) throws
func getAllOfflineOperations() throws -> [OfflineOperation]
func deleteOfflineOperation(id: String) throws
func updateOfflineOperationStatus(id: String, status: OfflineOperationStatus, lastError: String?) throws

// 同步状态
func saveSyncStatus(_ status: SyncStatus) throws
func loadSyncStatus() throws -> SyncStatus?

// HTML 缓存
func updateHTMLContentOnly(noteId: String, htmlContent: String, completion: @escaping (Error?) -> Void)
func getHTMLContent(noteId: String) throws -> String?
```

### MainWindowController

#### 主要方法

```swift
// 窗口管理
func showWindow(_ sender: Any?)
func close()
func savableWindowState() -> MainWindowState?
func restoreWindowState(_ state: MainWindowState)

// 工具栏动作
@objc func createNewNote(_ sender: Any?)
@objc func createNewFolder(_ sender: Any?)
@objc func performSync(_ sender: Any?)
@objc func showSettings(_ sender: Any?)
@objc func showLogin(_ sender: Any?)
@objc func showCookieRefresh(_ sender: Any?)
@objc func showHistory(_ sender: Any?)
@objc func showTrash(_ sender: Any?)

// 格式操作
@objc func toggleBold(_ sender: Any?)
@objc func toggleItalic(_ sender: Any?)
@objc func toggleUnderline(_ sender: Any?)
@objc func toggleStrikethrough(_ sender: Any?)
@objc func showFormatMenu(_ sender: Any?)

// 编辑操作
@objc func undo(_ sender: Any?)
@objc func redo(_ sender: Any?)
@objc func cut(_ sender: Any?)
@objc func copy(_ sender: Any?)
@objc func paste(_ sender: Any?)
@objc override func selectAll(_ sender: Any?)
```

### AppDelegate

#### 主要方法

```swift
// 应用程序生命周期
func applicationDidFinishLaunching(_ notification: Notification)
func applicationWillTerminate(_ notification: Notification)
func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool

// 窗口管理
func createMainWindow()
func createNewWindow()
func removeWindowController(_ windowController: MainWindowController)
func getAllWindows() -> [NSWindow]
func bringAllWindowsToFront()

// 菜单动作
@objc func showAboutPanel(_ sender: Any?)
@objc func showSettings(_ sender: Any?)
@objc func createNewWindow(_ sender: Any?)
@objc func showHelp(_ sender: Any?)

// 文件菜单动作
@objc func createNewNote(_ sender: Any?)
@objc func createNewFolder(_ sender: Any?)
@objc func shareNote(_ sender: Any?)
@objc func importNotes(_ sender: Any?)
@objc func exportNote(_ sender: Any?)
@objc func toggleStarNote(_ sender: Any?)
@objc func copyNote(_ sender: Any?)

// 编辑菜单动作
@objc func undo(_ sender: Any?)
@objc func redo(_ sender: Any?)
@objc func cut(_ sender: Any?)
@objc func copy(_ sender: Any?)
@objc func paste(_ sender: Any?)
@objc func selectAll(_ sender: Any?)

// 格式菜单动作
@objc func toggleBold(_ sender: Any?)
@objc func toggleItalic(_ sender: Any?)
@objc func toggleUnderline(_ sender: Any?)
@objc func toggleStrikethrough(_ sender: Any?)
@objc func increaseFontSize(_ sender: Any?)
@objc func decreaseFontSize(_ sender: Any?)
@objc func increaseIndent(_ sender: Any?)
@objc func decreaseIndent(_ sender: Any?)
@objc func alignLeft(_ sender: Any?)
@objc func alignCenter(_ sender: Any?)
@objc func alignRight(_ sender: Any?)
@objc func toggleBulletList(_ sender: Any?)
@objc func toggleNumberedList(_ sender: Any?)
@objc func toggleCheckboxList(_ sender: Any?)
@objc func setHeading1(_ sender: Any?)
@objc func setHeading2(_ sender: Any?)
@objc func setHeading3(_ sender: Any?)
@objc func setBodyText(_ sender: Any?)
```

---

## 数据存储

### 数据库结构

#### notes 表

```sql
CREATE TABLE notes (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    folder_id TEXT NOT NULL DEFAULT '0',
    is_starred INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    tags TEXT,
    raw_data TEXT,
    html_content TEXT
);
```

#### folders 表

```sql
CREATE TABLE folders (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    is_system INTEGER NOT NULL DEFAULT 0,
    is_pinned INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL,
    raw_data TEXT
);
```

#### offline_operations 表

```sql
CREATE TABLE offline_operations (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    note_id TEXT,
    data TEXT NOT NULL,
    created_at REAL NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    retry_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    status TEXT NOT NULL DEFAULT 'pending'
);
```

### 文件存储

#### 图片存储

- **位置**: `~/Documents/MiNoteImages/{folderId}/{fileId}.{ext}`
- **格式**: 支持 PNG、JPEG、GIF 等
- **管理**: 自动创建文件夹，删除笔记时清理图片

#### 配置文件

- **位置**: `UserDefaults`
- **内容**: Cookie、同步状态、用户设置、窗口状态等

---

## 性能优化

### 已实现的优化

1. **数据库索引**: 为常用查询字段添加索引
2. **图片缓存**: 本地缓存图片，避免重复下载
3. **防抖处理**: 保存操作使用防抖，减少不必要的保存
4. **并发处理**: 离线操作支持并发执行
5. **增量同步**: 使用 `syncTag` 实现增量同步，减少数据传输
6. **内存缓存**: 使用 `MemoryCacheManager` 缓存笔记对象
7. **保存队列**: 使用 `SaveQueueManager` 管理保存任务
8. **HTML 缓存**: 缓存 HTML 格式内容，快速显示笔记

### 未来优化方向

1. **图片压缩**: 上传前压缩图片，减少传输时间
2. **批量操作**: 支持批量创建、更新、删除
3. **懒加载**: 笔记列表实现懒加载，提高性能
4. **缓存策略**: 实现更智能的缓存策略
5. **预加载**: 预加载用户可能查看的笔记
6. **性能监控**: 实现性能监控和报告

---

## 安全考虑

### 数据安全

1. **Cookie 存储**: 使用 `UserDefaults` 存储，系统级加密
2. **私密笔记**: 支持密码保护，本地加密存储
3. **网络传输**: 使用 HTTPS 加密传输
4. **本地数据**: 数据库文件使用系统保护

### 认证安全

1. **Cookie 过期检测**: 自动检测并提示重新登录
2. **ServiceToken 提取**: 从 Cookie 中安全提取认证令牌
3. **错误处理**: 妥善处理认证错误，不泄露敏感信息
4. **自动刷新**: Cookie 即将过期时自动刷新

### 隐私保护

1. **本地数据**: 用户数据存储在本地，不上传无关信息
2. **图片缓存**: 图片缓存仅用于本地显示，不分享给第三方
3. **日志信息**: 调试日志不包含敏感用户信息
4. **权限控制**: 仅请求必要的系统权限

---

## 已知问题和限制

### 已知问题

1. **图片预览刷新**: 某些情况下图片预览可能不会立即刷新
2. **同步冲突**: 极端情况下可能出现数据不一致
3. **离线操作**: 大量离线操作可能导致处理时间较长
4. **窗口状态恢复**: 多显示器环境下窗口位置可能恢复不正确
5. **内存使用**: 编辑大型笔记时内存使用可能较高
6. **Web 编辑器性能**: 超大型文档编辑时可能出现性能问题

### 功能限制

1. **不支持富文本格式**: 某些高级格式可能不支持
2. **不支持协作**: 不支持多人协作编辑
3. **不支持附件**: 不支持除图片外的其他附件类型
4. **文件夹层级**: 不支持多级文件夹嵌套
5. **标签系统**: 标签功能较为基础
6. **搜索功能**: 仅支持文本搜索，不支持高级搜索语法

### 平台限制

1. **macOS 版本**: 需要 macOS 14.0 或更高版本
2. **硬件要求**: 需要支持 Metal 的显卡
3. **网络要求**: 需要稳定的网络连接进行同步
4. **存储空间**: 需要足够的本地存储空间

---

## 更新日志

### v1.0.0 (初始版本)
- 支持基本的笔记编辑和同步功能
- 支持富文本格式（加粗、斜体、下划线、删除线、高亮）
- 支持文件夹管理
- 支持图片上传
- 纯 SwiftUI 架构

### v1.1.0 (架构迁移)
- 从纯 SwiftUI 迁移到 AppKit+SwiftUI 混合架构
- 实现完整的 macOS 菜单系统
- 添加原生工具栏支持
- 支持多窗口管理
- 实现窗口状态保存和恢复
- 优化刷新 Cookie、登录、在线状态指示器
- 实现离线操作队列和处理器
- 优化同步机制
- 改进 UI 和用户体验

### v1.2.0 (性能优化)
- 实现内存缓存管理器 (`MemoryCacheManager`)
- 实现保存队列管理器 (`SaveQueueManager`)
- 优化笔记切换性能
- 实现 HTML 内容缓存
- 优化保存机制（四级保存策略）
- 改进错误处理和恢复机制
- 添加更多调试日志和性能监控

### 未来版本计划

#### v1.3.0 (功能增强)
- 支持笔记标签系统
- 支持高级搜索功能
- 支持笔记导出为多种格式
- 支持笔记导入从其他应用
- 改进图片管理和压缩

#### v1.4.0 (协作功能)
- 支持笔记分享
- 支持只读分享链接
- 支持协作编辑（基础版）
- 改进同步冲突解决

#### v2.0.0 (架构重构)
- 模块化架构重构
- 支持插件系统
- 支持主题系统
- 跨平台支持（iOS、iPadOS）

---

## 贡献指南

### 提交代码

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 创建 Pull Request

### 代码审查要点

- **架构一致性**: 符合混合架构设计原则
- **代码质量**: 遵循代码规范，无警告和错误
- **测试覆盖**: 添加必要的单元测试和集成测试
- **文档更新**: 更新相关文档（技术文档、API文档、注释）
- **性能考虑**: 考虑内存使用、响应速度、电池消耗
- **安全性**: 数据加密、认证安全、输入验证

### 开发环境设置

1. **克隆项目**:
   ```bash
   git clone https://github.com/your-username/SwiftUI-MiNote-for-Mac.git
   cd SwiftUI-MiNote-for-Mac
   ```

2. **安装依赖**:
   ```bash
   # 使用 Swift Package Manager
   swift package resolve
   ```

3. **生成 Xcode 项目**:
   ```bash
   # 如果已安装 xcodegen
   xcodegen generate
   ```

4. **打开项目**:
   ```bash
   open MiNoteMac.xcodeproj
   ```

5. **构建和运行**:
   - 在 Xcode 中选择目标设备
   - 按 ⌘R 运行

### 测试要求

1. **单元测试**: 所有新功能需要添加单元测试
2. **集成测试**: 涉及多个模块的功能需要集成测试
3. **UI 测试**: 重要的用户交互需要 UI 测试
4. **性能测试**: 性能敏感的功能需要性能测试
5. **兼容性测试**: 需要测试不同 macOS 版本的兼容性

### 文档要求

1. **代码注释**: 所有公开的 API 需要文档注释
2. **技术文档**: 架构变更需要更新技术文档
3. **API 文档**: 新增的 API 需要更新 API 参考
4. **用户文档**: 用户可见的功能需要更新用户文档
5. **更新日志**: 所有变更需要记录在更新日志中

---

## 许可证

本项目仅供学习和研究使用。

### 第三方依赖许可证

本项目使用了以下第三方开源库：

- **RichTextKit 1.2** - MIT 许可证
  - 版权: Copyright (c) 2022-2024 Daniel Saidi
  - 许可证文件: [RichTextKit-1.2/LICENSE](./RichTextKit-1.2/LICENSE)

### 使用限制

- ✅ **仅用于个人学习和研究目的**
- ✅ **仅访问自己的数据**
- ✅ **不要用于商业用途**
- ✅ **不要大规模自动化访问**
- ✅ **妥善保管认证信息，不要分享给他人**

### 免责声明

**本项目仅供学习和研究使用，不提供任何商业支持或保证。**

使用者需自行承担使用本项目的所有风险。作者不对因使用本项目而产生的任何损失、损害或法律后果承担责任。

---

## 联系方式

如有问题或建议，请通过以下方式联系：

- **GitHub Issues**: [项目 Issues 页面](https://github.com/your-username/SwiftUI-MiNote-for-Mac/issues)
- **Pull Requests**: 欢迎提交改进和修复
- **讨论区**: 项目 GitHub 讨论区

### 问题报告指南

报告问题时请提供以下信息：

1. **问题描述**: 详细描述遇到的问题
2. **重现步骤**: 如何重现问题的步骤
3. **预期行为**: 期望的正常行为
4. **实际行为**: 实际观察到的行为
5. **环境信息**:
   - macOS 版本
   - 应用程序版本
   - 硬件信息（可选）
6. **日志信息**: 相关的错误日志或控制台输出
7. **截图或视频**: 可视化的问题表现（可选）

### 功能请求指南

请求新功能时请提供以下信息：

1. **功能描述**: 详细描述需要的功能
2. **使用场景**: 功能的使用场景和目的
3. **优先级**: 功能的优先级（高/中/低）
4. **相关参考**: 类似功能的参考或示例
5. **实现建议**: 对实现方式的建议（可选）

---

## 致谢

感谢以下项目和贡献者：

- **小米笔记团队**: 提供了优秀的笔记服务和 API
- **SwiftUI 和 AppKit 团队**: 提供了强大的 UI 框架
- **开源社区**: 提供了丰富的开源工具和库
- **项目贡献者**: 所有为项目做出贡献的开发者

特别感谢以下开源项目：

- **RichTextKit**: 提供了优秀的富文本编辑基础
- **Swift Package Manager**: 提供了优秀的依赖管理
- **XcodeGen**: 提供了优秀的项目生成工具

---

**最后更新**: 2026年1月4日

**文档版本**: 2.0.0 (对应应用程序版本 v1.2.0)

**维护者**: 项目维护团队

**状态**: 活跃开发中
