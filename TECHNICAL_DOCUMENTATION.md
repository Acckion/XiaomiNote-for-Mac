# 小米笔记 macOS 客户端 - 技术文档

## 目录

1. [项目概述](#项目概述)
2. [技术架构](#技术架构)
3. [核心模块](#核心模块)
4. [数据模型](#数据模型)
5. [服务层](#服务层)
6. [UI 层](#ui-层)
7. [同步机制](#同步机制)
8. [离线操作](#离线操作)
9. [Web 编辑器](#web-编辑器)
10. [开发指南](#开发指南)
11. [API 参考](#api-参考)

---

## 项目概述

### 项目简介

小米笔记 macOS 客户端是一个使用 SwiftUI 开发的原生 macOS 应用程序，通过调用小米笔记的 Web API 实现完整的笔记管理功能。

### 技术栈

- **开发语言**: Swift 6.0
- **UI 框架**: SwiftUI (macOS 14.0+)
- **富文本编辑**: 自定义 Web 编辑器（基于 CKEditor 5）
- **数据存储**: SQLite 3
- **网络请求**: URLSession
- **架构模式**: MVVM (Model-View-ViewModel)
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
│   │   │   └── PrivateNotesPasswordManager.swift # 私密笔记密码管理
│   │   ├── View/                # UI 视图组件
│   │   │   ├── ContentView.swift            # 主内容视图（三栏布局）
│   │   │   ├── NotesListView.swift          # 笔记列表视图
│   │   │   ├── NoteDetailView.swift         # 笔记详情/编辑视图
│   │   │   ├── SidebarView.swift            # 侧边栏视图
│   │   │   ├── WebEditorView.swift          # Web 编辑器视图
│   │   │   └── ...
│   │   ├── ViewModel/           # 视图模型
│   │   │   └── NotesViewModel.swift        # 主视图模型
│   │   └── Web/                 # Web 编辑器相关文件
│   │       ├── editor.html                  # 编辑器 HTML
│   │       ├── xml-to-html.js               # XML 转 HTML 转换器
│   │       └── html-to-xml.js               # HTML 转 XML 转换器
│   └── MiNoteMac/               # 应用程序入口
│       └── App.swift
├── build/                       # 构建产物
├── MiNoteMac.xcodeproj/        # Xcode 项目文件
└── README.md                    # 项目说明
```

---

## 技术架构

### 架构模式

项目采用 **MVVM (Model-View-ViewModel)** 架构模式：

```
┌─────────────┐
│    View     │  SwiftUI 视图层
│  (SwiftUI)  │
└──────┬──────┘
       │ @ObservedObject
       │ @Published
       ▼
┌─────────────┐
│  ViewModel  │  业务逻辑层
│ (Observable)│  状态管理
└──────┬──────┘
       │ 调用
       ▼
┌─────────────┐
│   Service   │  服务层
│   Layer     │  API、数据库、文件
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    Model    │  数据模型层
│  (Struct)   │
└─────────────┘
```

### 数据流

1. **用户操作** → View 触发事件
2. **ViewModel** 处理业务逻辑，更新 `@Published` 状态
3. **Service** 执行具体操作（API 调用、数据库操作等）
4. **Model** 数据更新
5. **ViewModel** 状态变化触发 View 自动更新

### 线程模型

- **主线程**: 所有 UI 更新和 ViewModel 操作（使用 `@MainActor`）
- **后台线程**: 网络请求、数据库操作、文件 I/O
- **并发处理**: 使用 `async/await` 和 `Task` 进行异步操作

---

## 核心模块

### 1. 数据模型层 (Model)

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
}
```

**关键特性**:
- `content`: 存储为 XML 格式，兼容小米笔记服务器
- `rawData`: 保存完整的 API 响应数据，包含 `tag`、`createDate` 等字段
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

### 2. 服务层 (Service)

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

**数据库表结构**:

1. **notes 表**: 存储笔记数据
   - `id`, `title`, `content`, `folder_id`, `is_starred`
   - `created_at`, `updated_at`, `tags`, `raw_data`

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

#### OfflineOperationQueue (离线操作队列)

**职责**:
- 管理离线操作的存储和查询
- 操作去重和合并
- 操作优先级管理

**操作类型**:
- `createNote`: 创建笔记
- `updateNote`: 更新笔记
- `deleteNote`: 删除笔记
- `uploadImage`: 上传图片
- `createFolder`: 创建文件夹
- `renameFolder`: 重命名文件夹
- `deleteFolder`: 删除文件夹

**操作状态**:
- `pending`: 待处理
- `processing`: 处理中
- `completed`: 已完成
- `failed`: 失败

#### OfflineOperationProcessor (离线操作处理器)

**职责**:
- 执行离线操作
- 实现智能重试机制（指数退避）
- 并发处理多个操作
- 错误处理和分类

**配置参数**:
- `maxConcurrentOperations`: 最大并发操作数（默认 3）
- `maxRetryCount`: 最大重试次数（默认 3）
- `retryDelay`: 重试延迟（默认 5 秒）

### 3. 视图模型层 (ViewModel)

#### NotesViewModel

**职责**:
- 管理应用的主要业务逻辑和状态
- 笔记和文件夹的数据管理
- 同步操作协调
- UI 状态管理（加载、错误、搜索等）

**主要状态**:
- `notes: [Note]`: 笔记列表
- `folders: [Folder]`: 文件夹列表
- `selectedNote: Note?`: 当前选中的笔记
- `selectedFolder: Folder?`: 当前选中的文件夹
- `searchText: String`: 搜索文本
- `isSyncing: Bool`: 是否正在同步

**主要方法**:
- `loadNotes()`: 加载笔记列表
- `createNote()`: 创建新笔记
- `updateNote(_:)`: 更新笔记
- `deleteNote(_:)`: 删除笔记
- `syncNotes()`: 同步笔记
- `processPendingOperations()`: 处理离线操作

**线程安全**:
- 使用 `@MainActor` 确保所有操作在主线程执行

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

---

## UI 层

### ContentView (主内容视图)

**布局结构**:
- 使用 `NavigationSplitView` 实现三栏布局
- 左侧：侧边栏（文件夹列表）
- 中间：笔记列表
- 右侧：笔记编辑器

**响应式设计**:
- 根据窗口大小动态调整各栏宽度
- 最小窗口宽度：650px
- 各栏有最小、理想、最大宽度限制

**工具栏**:
- 搜索框（支持文本搜索和筛选）
- 同步按钮
- 设置按钮
- 新建笔记按钮

### NotesListView (笔记列表视图)

**功能特性**:
- 按时间分组显示（今天、昨天、本周、本月、本年）
- 支持搜索高亮
- 显示笔记预览（标题、修改时间、内容预览、图片预览）
- 文件夹信息显示（在特定条件下）
- 支持滑动操作（删除、置顶）

**文件夹信息显示逻辑**:
- 显示场景：
  - 选中"所有笔记"文件夹
  - 选中"置顶"文件夹
  - 有搜索文本或筛选条件
- 不显示场景：
  - 选中"未分类"文件夹
  - 选中其他具体文件夹

### NoteDetailView (笔记详情/编辑视图)

**功能特性**:
- 标题编辑
- 富文本内容编辑（使用 Web 编辑器）
- 自动保存（本地立即保存，云端延迟上传）
- 格式工具栏（加粗、斜体、下划线、删除线、高亮等）
- 列表支持（有序列表、无序列表、复选框）
- 图片插入和显示
- 撤销/重做功能

**保存机制**:
- **本地保存**: 立即保存到数据库（防抖 500ms）
- **云端上传**: 延迟上传（防抖 2 秒），离线时添加到离线队列

### WebEditorView (Web 编辑器视图)

**技术实现**:
- 使用 `WKWebView` 加载 HTML 编辑器
- JavaScript 桥接实现双向通信
- XML ↔ HTML 格式转换

**编辑器功能**:
- 富文本格式（加粗、斜体、下划线、删除线、高亮）
- 标题（H1、H2、H3）
- 列表（有序、无序、复选框）
- 文本对齐（左、中、右）
- 缩进
- 图片插入
- 撤销/重做

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

#### 调试工具

- **Xcode 调试器**: 设置断点、查看变量
- **控制台日志**: 查看 `print` 输出
- **网络日志**: `NetworkLogger` 记录所有网络请求
- **数据库查看**: 使用 SQLite 工具查看数据库文件

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
```

#### 主要方法

```swift
// 笔记操作
func createNote() async throws
func updateNote(_ note: Note) async throws
func deleteNote(_ note: Note) async throws
func toggleStar(_ note: Note)

// 文件夹操作
func createFolder(name: String) async throws
func renameFolder(_ folder: Folder, newName: String) async throws
func deleteFolder(_ folder: Folder, purge: Bool) async throws

// 同步操作
func syncNotes() async throws
func processPendingOperations() async

// 搜索和筛选
var filteredNotes: [Note] { get }
```

### MiNoteService

#### 主要方法

```swift
// 认证
func setCookie(_ cookie: String)
func isAuthenticated() -> Bool

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
```

### DatabaseService

#### 主要方法

```swift
// 笔记操作
func saveNote(_ note: Note) throws
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
```

### LocalStorageService

#### 主要方法

```swift
// 图片操作
func saveImage(fileId: String, fileType: String, data: Data) throws
func loadImage(fileId: String, fileType: String) -> Data?
func deleteImage(fileId: String, fileType: String) throws

// 配置操作
func saveFolders(_ folders: [Folder]) throws
func loadFolders() throws -> [Folder]
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
    raw_data TEXT
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
- **内容**: Cookie、同步状态、用户设置等

---

## 性能优化

### 已实现的优化

1. **数据库索引**: 为常用查询字段添加索引
2. **图片缓存**: 本地缓存图片，避免重复下载
3. **防抖处理**: 保存操作使用防抖，减少不必要的保存
4. **并发处理**: 离线操作支持并发执行
5. **增量同步**: 使用 `syncTag` 实现增量同步，减少数据传输

### 未来优化方向

1. **图片压缩**: 上传前压缩图片，减少传输时间
2. **批量操作**: 支持批量创建、更新、删除
3. **懒加载**: 笔记列表实现懒加载，提高性能
4. **缓存策略**: 实现更智能的缓存策略

---

## 安全考虑

### 数据安全

1. **Cookie 存储**: 使用 `UserDefaults` 存储，系统级加密
2. **私密笔记**: 支持密码保护，本地加密存储
3. **网络传输**: 使用 HTTPS 加密传输

### 认证安全

1. **Cookie 过期检测**: 自动检测并提示重新登录
2. **ServiceToken 提取**: 从 Cookie 中安全提取认证令牌
3. **错误处理**: 妥善处理认证错误，不泄露敏感信息

---

## 已知问题和限制

### 已知问题

1. **图片预览刷新**: 某些情况下图片预览可能不会立即刷新
2. **同步冲突**: 极端情况下可能出现数据不一致
3. **离线操作**: 大量离线操作可能导致处理时间较长

### 功能限制

1. **不支持富文本格式**: 某些高级格式可能不支持
2. **不支持协作**: 不支持多人协作编辑
3. **不支持附件**: 不支持除图片外的其他附件类型

---

## 更新日志

### v1.0.0
- 初始版本
- 支持基本的笔记编辑和同步功能
- 支持富文本格式
- 支持文件夹管理
- 支持图片上传

### v1.1.0
- 优化刷新 Cookie、登录、在线状态指示器
- 实现离线操作队列和处理器
- 优化同步机制
- 改进 UI 和用户体验

---

## 贡献指南

### 提交代码

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 创建 Pull Request

### 代码审查

- 确保代码符合项目规范
- 添加必要的测试
- 更新相关文档

---

## 许可证

本项目仅供学习和研究使用。

### 第三方依赖

- **RichTextKit 1.2**: MIT 许可证

---

## 联系方式

如有问题或建议，请提交 Issue 或 Pull Request。

---

**最后更新**: 2024年12月

