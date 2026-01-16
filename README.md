# 小米笔记 macOS 客户端

一个使用 Swift 开发的原生 macOS 客户端，用于同步和管理小米笔记。

---

## ⚠️ 重要风险提示

> **在使用本项目之前，请务必仔细阅读以下内容！**

### 项目性质

本项目是一个**个人学习和研究项目**，通过调用小米笔记的 Web API 实现客户端功能。

### 使用风险

使用本项目可能涉及以下风险：

- ⚠️ **服务条款风险**: 可能违反小米笔记的服务条款
- ⚠️ **法律风险**: 不同地区对 API 使用和逆向工程的法律规定不同
- ⚠️ **数据安全风险**: 需要妥善保管认证信息（Cookie）
- ⚠️ **账号风险**: 使用第三方客户端可能导致账号被限制或封禁

### 使用建议

- ✅ **仅用于个人学习和研究目的**
- ✅ **仅访问自己的数据**
- ✅ **不要用于商业用途**
- ✅ **不要大规模自动化访问**
- ✅ **妥善保管认证信息，不要分享给他人**

### 免责声明

**本项目仅供学习和研究使用，不提供任何商业支持或保证。**

使用者需自行承担使用本项目的所有风险。作者不对因使用本项目而产生的任何损失、损害或法律后果承担责任。

---

## 项目简介

本项目是一个原生 macOS 应用程序，提供了完整的小米笔记同步功能，包括：

- 📝 富文本编辑（支持加粗、斜体、下划线、删除线、高亮等格式）
- 📁 文件夹管理
- ⭐ 笔记收藏
- 🔄 云端同步（增量同步、离线操作队列）
- 📷 图片支持（上传、缓存、显示）
- 🎵 语音笔记（录制、上传、播放）
- 🔍 笔记搜索和查找替换
- 📋 列表支持（有序列表、无序列表、复选框）
- 💾 离线编辑和自动同步
- 🖼️ 多种视图模式（列表视图、画廊视图）

## 技术栈

- **语言**: Swift 6.0
- **UI 框架**: AppKit + SwiftUI 混合架构
- **窗口管理**: NSWindowController, NSSplitViewController
- **富文本编辑**: 
  - 原生编辑器（NSTextView，推荐）
  - Web 编辑器（WebKit，备用）
- **数据存储**: SQLite 3
- **网络请求**: URLSession
- **架构模式**: MVVM + AppKit 控制器
- **并发处理**: async/await, Task, Actor
- **包管理**: Swift Package Manager (SPM)
- **项目生成**: XcodeGen
- **最低系统要求**: macOS 15.0+

## 项目结构

```
Sources/
├── App/                    # 应用程序入口
│   ├── App.swift           # SwiftUI 应用入口
│   ├── AppDelegate.swift   # AppKit 应用委托
│   ├── AppStateManager.swift
│   ├── MenuManager.swift   # 菜单系统管理
│   ├── MenuActionHandler.swift
│   ├── MenuState.swift     # 菜单状态
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
│   ├── StartupSequenceManager.swift # 启动序列管理
│   ├── ScheduledTaskManager.swift  # 定时任务管理
│   ├── AuthenticationStateManager.swift # 认证状态管理
│   ├── SilentCookieRefreshManager.swift # 静默 Cookie 刷新
│   ├── XiaoMiFormatConverter.swift # 小米格式转换器
│   ├── Audio*Service.swift         # 语音相关服务
│   └── ...
│
├── ViewModel/              # 视图模型
│   ├── NotesViewModel.swift        # 主视图模型
│   ├── ViewState.swift             # 视图状态
│   ├── ViewStateCoordinator.swift  # 视图状态协调器
│   ├── ViewOptionsManager.swift    # 视图选项管理
│   └── NoteUpdateEvent.swift       # 笔记更新事件
│
├── View/                   # UI 视图组件
│   ├── AppKitComponents/   # AppKit 视图控制器
│   ├── Bridge/             # SwiftUI-AppKit 桥接
│   │   ├── NativeEditorContext.swift   # 原生编辑器上下文
│   │   ├── WebEditorContext.swift      # Web 编辑器上下文
│   │   ├── FormatStateManager.swift    # 格式状态管理
│   │   ├── UnifiedEditorWrapper.swift  # 统一编辑器包装
│   │   └── ...
│   ├── NativeEditor/       # 原生富文本编辑器
│   │   ├── NativeEditorView.swift      # 编辑器视图
│   │   ├── FormatManager.swift         # 格式管理
│   │   ├── FormatStateSynchronizer.swift # 格式状态同步
│   │   ├── CustomAttachments.swift     # 自定义附件
│   │   ├── ImageAttachment.swift       # 图片附件
│   │   ├── AudioAttachment.swift       # 语音附件
│   │   └── ...
│   ├── SwiftUIViews/       # SwiftUI 视图
│   │   ├── NotesListView.swift         # 笔记列表
│   │   ├── NoteDetailView.swift        # 笔记详情
│   │   ├── SidebarView.swift           # 侧边栏
│   │   ├── GalleryView.swift           # 画廊视图
│   │   ├── AudioPlayerView.swift       # 语音播放器
│   │   ├── AudioRecorderView.swift     # 语音录制器
│   │   └── ...
│   └── Shared/             # 共享组件
│
├── Window/                 # 窗口控制器
│   ├── MainWindowController.swift
│   ├── LoginWindowController.swift
│   ├── SettingsWindowController.swift
│   ├── SearchPanelController.swift     # 查找替换面板
│   └── ...
│
├── ToolbarItem/            # 工具栏组件
│   ├── MainWindowToolbarDelegate.swift
│   ├── ToolbarItemFactory.swift
│   └── ToolbarVisibilityManager.swift
│
├── Extensions/             # Swift 扩展
├── Helper/                 # 辅助工具
│
└── Web/                    # Web 编辑器
    ├── editor.html
    └── modules/
        └── converter/      # 格式转换器
            ├── xml-to-html.js
            └── html-to-xml.js

Tests/
└── NativeEditorTests/      # 原生编辑器测试
```

## 快速开始

### 环境要求

- macOS 15.0 或更高版本
- Xcode 15.0 或更高版本
- Swift 6.0

### 构建项目

```bash
# 生成 Xcode 项目
xcodegen generate
# 或使用脚本
./build_xcode_proj.sh

# 构建 Release 版本
./build_release.sh

# 构建项目
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug

# 运行测试
xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac -destination 'platform=macOS'

# 清理构建
xcodebuild clean -project MiNoteMac.xcodeproj -scheme MiNoteMac
```

## 功能特性

### 富文本编辑

- 支持多种文本格式：加粗、斜体、下划线、删除线、高亮
- 支持标题（大标题、二级标题、三级标题）
- 支持文本对齐（左对齐、居中、右对齐）
- 支持缩进
- 双编辑器支持：原生编辑器（推荐）和 Web 编辑器

### 列表支持

- 无序列表（bullet points）
- 有序列表（numbered lists）
- 复选框列表（checkboxes）

### 图片支持

- 插入图片到笔记
- 图片自动上传到云端
- 本地图片缓存

### 语音笔记

- 录制语音并上传
- 播放语音附件
- 支持语音格式转换

### 文件夹管理

- 创建、重命名、删除文件夹
- 文件夹层级结构
- 笔记分类管理

### 视图模式

- 列表视图：传统笔记列表
- 画廊视图：卡片式展示
- 支持排序和日期分组

### 云端同步

- 自动同步笔记到小米笔记服务器
- 增量同步（使用 syncTag）
- 离线编辑支持
- 冲突处理
- Cookie 自动刷新

### 查找替换

- 笔记内容搜索
- 查找和替换功能

### 数据存储

项目采用双重存储策略：

- **本地存储**: SQLite 数据库存储笔记元数据和内容
- **云端存储**: XML 格式（小米笔记格式）与服务器兼容
- **编辑器格式**: 
  - 原生编辑器：NSAttributedString
  - Web 编辑器：HTML

## 配置说明

### 登录配置

应用程序首次启动时需要登录小米账号。登录信息会安全地存储在本地。

### 数据库

应用程序使用 SQLite 数据库存储本地笔记数据，数据库文件位于：

```
~/Library/Application Support/MiNoteMac/database.sqlite
```

### 图片存储

图片文件存储在：

```
~/Documents/MiNoteImages/
```

## 开发说明

### 架构分层

```
AppKit 控制器层 (AppDelegate, WindowController)
        ↓
SwiftUI 视图层 (View + ViewModel)
        ↓
服务层 (Service)
        ↓
数据模型层 (Model)
```

### 关键文件

- `AppDelegate.swift`: 应用生命周期、菜单系统
- `MainWindowController.swift`: 主窗口、工具栏、分割视图
- `NotesViewModel.swift`: 主业务逻辑和状态管理
- `MiNoteService.swift`: 小米笔记 API 调用
- `DatabaseService.swift`: SQLite 数据库操作
- `NativeEditorView.swift`: 原生富文本编辑器
- `XiaoMiFormatConverter.swift`: 小米格式转换

### 调试

项目使用统一的调试日志格式，所有调试信息以 `[[调试]]` 开头，方便在控制台中搜索和过滤。

## 文档

- [TECHNICAL_DOCUMENTATION.md](./TECHNICAL_DOCUMENTATION.md) - 详细的技术文档
- [DESIGN_GUIDELINES.md](./DESIGN_GUIDELINES.md) - 设计规范

## 依赖说明

本项目使用纯 Swift 实现，不依赖外部开源库。所有代码均为原创实现。

## 许可证

本项目仅供学习和研究使用。

## 更新日志

### v3.3.0 (2026-01-16)

#### 核心优化
- 统一操作队列架构重构，提升同步可靠性
- 优化笔记选择和时间戳处理逻辑
- 改进启动数据加载流程
- 完善视图状态同步机制

#### 编辑器增强
- 优化原生编辑器格式应用性能
- 改进中文输入法兼容性
- 完善附件选择机制
- 优化列表格式处理

#### 用户体验
- 优化笔记列表排序和显示
- 改进工具栏可见性管理
- 完善格式菜单状态同步
- 优化代码结构和模块化

### v3.0.0

#### 原生编辑器
- 新增原生富文本编辑器（NSTextView），替代 Web 编辑器作为默认编辑器
- 实现完整的格式状态同步机制
- 支持图片和语音附件
- 实现复选框同步功能
- 格式菜单与编辑器状态实时同步

#### 语音笔记
- 新增语音录制功能
- 支持语音上传到云端
- 实现语音播放器
- 修复语音格式兼容性问题

#### 视图增强
- 新增画廊视图模式
- 实现笔记列表排序和日期分组
- 添加笔记列表移动动画
- 优化视图状态持久化

#### 菜单系统
- 实现完整的显示菜单（视图模式、缩放、工具栏控制）
- 格式菜单勾选状态与编辑器同步
- 动态菜单标题支持

#### 同步优化
- 新增启动序列管理器
- 优化 Cookie 自动刷新机制
- 改进视图状态同步

### v2.3.0 beta
- 新增原生笔记编辑器（实验性）

### v2.2.0
- 新增轻量化同步功能
- 在线状态管理和 Cookie 自动刷新
- 查找和替换功能

### v2.1.0
- 优化颜色主题系统
- 优化项目结构和构建配置

### v2.0.0
- 采用 AppKit+SwiftUI 混合架构
- 实现完整的 macOS 菜单系统
- 支持多窗口管理

### v1.2.0
- 实现内存缓存管理器
- 实现保存队列管理器
- 优化笔记切换性能

### v1.1.0
- 从纯 SwiftUI 迁移到 AppKit+SwiftUI 混合架构
- 实现离线操作队列

### v1.0.0
- 初始版本，支持基本的笔记编辑和同步功能
