# 小米笔记 macOS 客户端 - 技术文档

## 目录

1. [项目概述](#项目概述)
2. [技术架构](#技术架构)
3. [核心模块](#核心模块)
4. [数据模型](#数据模型)
5. [服务层](#服务层)
6. [编辑器系统](#编辑器系统)
7. [UI 层](#ui-层)
8. [窗口管理](#窗口管理)
9. [同步机制](#同步机制)
10. [离线操作](#离线操作)
11. [开发指南](#开发指南)

---

## 项目概述

### 项目简介

小米笔记 macOS 客户端是一个使用 **AppKit + SwiftUI 混合架构** 开发的原生 macOS 应用程序，通过调用小米笔记的 Web API 实现完整的笔记管理功能。

### 技术栈

- **开发语言**: Swift 6.0
- **UI 框架**: AppKit + SwiftUI 混合架构
- **窗口管理**: NSWindowController, NSSplitViewController
- **富文本编辑**: 
  - 原生编辑器（NSTextView + NSTextStorage）
  - Web 编辑器（WebKit，备用）
- **数据存储**: SQLite 3
- **网络请求**: URLSession
- **架构模式**: MVVM + AppKit 控制器
- **并发处理**: async/await, Task, Actor
- **项目生成**: XcodeGen

### 系统要求

- macOS 15.0 或更高版本
- Xcode 15.0 或更高版本
- Swift 6.0

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
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                 SwiftUI 视图层 (MVVM)                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │    View     │◄─┤  ViewModel  │◄─┤   Service   │    │
│  │  (SwiftUI)  │  │ (Observable)│  │   Layer     │    │
│  └─────────────┘  └──────┬──────┘  └──────┬──────┘    │
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

### 1. 应用程序层 (App/)

#### AppDelegate
- 应用程序生命周期管理
- 多窗口管理
- 应用程序状态保存和恢复

#### MenuManager
- 完整的 macOS 菜单系统（文件、编辑、格式、显示、窗口、帮助）
- 菜单状态管理和验证
- 格式菜单与编辑器状态同步

#### MenuActionHandler
- 菜单动作处理
- 编辑器命令路由

### 2. 视图模型层 (ViewModel/)

#### NotesViewModel
- 管理应用的主要业务逻辑和状态
- 笔记和文件夹的数据管理
- 同步操作协调
- UI 状态管理

#### ViewStateCoordinator
- 视图状态协调
- 文件夹切换时的状态保存和恢复
- 笔记选择状态管理

#### ViewOptionsManager
- 视图选项管理（列表视图/画廊视图）
- 排序和分组设置

### 3. 服务层 (Service/)

#### MiNoteService
- 小米笔记 API 调用
- Cookie 和 ServiceToken 认证管理
- API 错误处理和重试

#### DatabaseService
- SQLite 数据库操作
- 笔记和文件夹的 CRUD
- 离线操作队列管理
- HTML 内容缓存

#### SyncService
- 完整同步和增量同步
- 冲突解决
- 双向同步

#### StartupSequenceManager
- 应用启动序列管理
- 数据加载协调
- Cookie 有效性检查

#### ScheduledTaskManager
- 定时任务管理
- 自动同步调度

#### AuthenticationStateManager
- 认证状态管理
- Cookie 过期检测

#### SilentCookieRefreshManager
- 静默 Cookie 刷新
- 冷却期机制

#### XiaoMiFormatConverter
- 小米笔记 XML 格式与 NSAttributedString 互转
- 支持图片、语音、复选框等附件

#### Audio*Service
- `AudioRecorderService`: 语音录制
- `AudioUploadService`: 语音上传
- `AudioPlayerService`: 语音播放
- `AudioCacheService`: 语音缓存
- `AudioConverterService`: 格式转换
- `AudioDecryptService`: 语音解密

---

## 数据模型

### Note (笔记模型)

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
    public var rawData: [String: Any]?  // 原始 API 数据
    public var htmlContent: String?     // HTML 缓存内容
}
```

### Folder (文件夹模型)

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

---

## 编辑器系统

### 双编辑器架构

项目支持两种编辑器：

1. **原生编辑器** (NativeEditor/) - 推荐
   - 基于 NSTextView + NSTextStorage
   - 更好的性能和系统集成
   - 支持原生格式菜单

2. **Web 编辑器** (Web/) - 备用
   - 基于 WebKit + JavaScript
   - 兼容性更好

### 原生编辑器组件 (View/NativeEditor/)

#### NativeEditorView
- 主编辑器视图
- NSTextView 包装

#### FormatManager
- 格式应用管理
- 支持加粗、斜体、下划线、删除线、高亮
- 支持标题、列表、对齐

#### FormatStateSynchronizer
- 格式状态同步
- 光标位置格式检测
- 与菜单状态同步

#### CustomAttachments
- 自定义附件支持
- 复选框附件
- 分割线附件

#### ImageAttachment
- 图片附件处理
- 图片加载和显示

#### AudioAttachment
- 语音附件处理
- 语音播放器集成

### 编辑器桥接 (View/Bridge/)

#### NativeEditorContext
- 原生编辑器上下文
- 格式状态管理
- 编辑器命令接口

#### WebEditorContext
- Web 编辑器上下文
- JavaScript 桥接

#### FormatStateManager
- 统一格式状态管理
- 编辑器类型无关的格式接口

#### UnifiedEditorWrapper
- 统一编辑器包装
- 编辑器切换支持

### 格式转换

#### XiaoMiFormatConverter (Service/)
- XML → NSAttributedString
- NSAttributedString → XML
- 支持的元素：
  - 文本格式：加粗、斜体、下划线、删除线、高亮
  - 标题：H1、H2、H3
  - 列表：有序、无序、复选框
  - 附件：图片、语音
  - 其他：分割线、引用块

#### Web 转换器 (Web/modules/converter/)
- `xml-to-html.js`: XML → HTML
- `html-to-xml.js`: HTML → XML

---

## UI 层

### SwiftUI 视图 (View/SwiftUIViews/)

#### NotesListView
- 笔记列表显示
- 支持排序和日期分组
- 列表动画

#### NoteDetailView
- 笔记详情/编辑视图
- 编辑器集成
- 标题编辑

#### SidebarView
- 侧边栏视图
- 文件夹列表
- 系统文件夹

#### GalleryView
- 画廊视图模式
- 卡片式笔记展示

#### AudioPlayerView / AudioRecorderView
- 语音播放器
- 语音录制器

### AppKit 组件 (View/AppKitComponents/)

- 视图控制器
- AppKit 原生组件

### 桥接控制器 (View/Bridge/)

- `NotesListHostingController`: 笔记列表托管
- `SidebarHostingController`: 侧边栏托管
- `NoteDetailHostingController`: 笔记详情托管
- `ContentAreaHostingController`: 内容区域托管
- `GalleryHostingController`: 画廊视图托管

---

## 窗口管理

### MainWindowController

- 主窗口管理和配置
- 三栏分割视图（侧边栏、笔记列表、笔记详情）
- 工具栏系统
- 窗口状态保存和恢复

### 工具栏系统 (ToolbarItem/)

#### MainWindowToolbarDelegate
- 工具栏代理
- 工具栏项验证

#### ToolbarItemFactory
- 工具栏项创建工厂

#### ToolbarVisibilityManager
- 工具栏可见性管理
- 根据视图模式动态调整

### 专用窗口控制器

- `LoginWindowController`: 登录窗口
- `SettingsWindowController`: 设置窗口
- `HistoryWindowController`: 历史记录窗口
- `TrashWindowController`: 回收站窗口
- `CookieRefreshWindowController`: Cookie 刷新窗口
- `DebugWindowController`: 调试窗口
- `SearchPanelController`: 查找替换面板

---

## 同步机制

### 同步类型

#### 完整同步
- 首次启动或手动触发
- 清除本地数据，从云端拉取全部

#### 增量同步
- 定期自动同步
- 使用 `syncTag` 获取增量更改

### 冲突解决

- 基于时间戳比较
- 保留 `modifyDate` 更新的版本

### 同步状态管理

存储在 `sync_status` 表：
- `last_sync_time`: 上次同步时间
- `sync_tag`: 同步标签
- `last_full_sync_time`: 上次完整同步时间

---

## 离线操作

### 离线操作队列

存储在 `offline_operations` 表

**操作类型**:
- `createNote`: 创建笔记
- `updateNote`: 更新笔记
- `deleteNote`: 删除笔记
- `uploadImage`: 上传图片
- `createFolder`: 创建文件夹
- `renameFolder`: 重命名文件夹
- `deleteFolder`: 删除文件夹

### 操作去重和合并

- 同一笔记的多个 `updateNote` → 只保留最新的
- `createNote + updateNote` → 合并为 `createNote`
- `createNote + deleteNote` → 删除两个操作
- `updateNote + deleteNote` → 只保留 `deleteNote`

### 智能重试机制

- 指数退避策略
- 最大重试次数: 3 次
- 区分可重试和不可重试错误

---

## 开发指南

### 常用命令

```bash
# 生成 Xcode 项目
xcodegen generate

# 构建项目
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug

# 运行测试
xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac -destination 'platform=macOS'

# 清理构建
xcodebuild clean -project MiNoteMac.xcodeproj -scheme MiNoteMac
```

### 调试日志

所有调试日志使用统一格式：

```swift
print("[ClassName] 日志内容")
```

**关键日志标记**:
- `[[调试]]`: 重要调试信息
- `[VIEWMODEL]`: ViewModel 相关
- `[MiNoteService]`: API 服务相关
- `[Database]`: 数据库相关
- `[保存流程]`: 笔记保存相关
- `[NativeEditor]`: 原生编辑器相关

### 测试

测试文件位于 `Tests/NativeEditorTests/`：
- 格式应用测试
- 格式状态检测测试
- 编辑器状态一致性测试
- 性能测试

---

**最后更新**: 2026年1月12日
**版本**: 3.0.0
