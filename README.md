# 小米笔记 macOS 客户端

一个使用 SwiftUI 开发的 macOS 客户端，用于同步和管理小米笔记。

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

**详细的风险说明和法律建议请参考**: [法律声明与风险提示](./LEGAL_NOTICE.md)

---

## 项目简介

本项目是一个原生 macOS 应用程序，提供了完整的小米笔记同步功能，包括：

- 📝 富文本编辑（支持加粗、斜体、下划线、删除线、高亮等格式）
- 📁 文件夹管理
- ⭐ 笔记收藏
- 🔄 云端同步
- 📷 图片支持
- 🔍 笔记搜索
- 📋 列表支持（有序列表、无序列表、复选框）
- 💾 离线编辑和自动同步

## 技术栈

- **语言**: Swift 6.0
- **UI 框架**: AppKit + SwiftUI 混合架构
- **窗口管理**: NSWindowController, NSSplitViewController
- **富文本编辑**: 自定义 Web 编辑器（基于 CKEditor 5 风格）
- **数据存储**: SQLite 3
- **网络请求**: URLSession
- **架构模式**: MVVM (Model-View-ViewModel) + AppKit 控制器
- **并发处理**: async/await, Task, Actor
- **包管理**: Swift Package Manager (SPM)
- **最低系统要求**: macOS 14.0+
## 项目结构

```
SwiftUI-MiNote-for-Mac/
├── Sources/
│   ├── App/                    # 应用程序入口（AppDelegate、菜单、窗口管理）
│   │   ├── App.swift           # SwiftUI 应用入口
│   │   ├── AppDelegate.swift   # AppKit 应用委托
│   │   ├── AppStateManager.swift
│   │   ├── MenuActionHandler.swift
│   │   ├── MenuManager.swift
│   │   ├── WindowManager.swift
│   │   └── Assets.xcassets/    # 应用图标和颜色资源
│   ├── Model/                  # 数据模型（Note, Folder, UserProfile 等）
│   ├── Service/                # 业务服务层（API、数据库、同步、缓存等）
│   ├── View/                   # UI视图组件
│   │   ├── AppKitComponents/   # AppKit 视图控制器
│   │   ├── Bridge/             # SwiftUI-AppKit 桥接控制器
│   │   ├── Shared/             # 共享视图组件
│   │   └── SwiftUIViews/       # SwiftUI 视图
│   ├── ViewModel/              # 视图模型
│   ├── Window/                 # 窗口控制器和状态管理
│   ├── Extensions/             # Swift 扩展
│   ├── Helper/                 # 辅助工具类
│   └── Web/                    # Web 编辑器相关文件（HTML/JS）
├── References/                  # 参考文档和资源
├── project.yml                  # XcodeGen 配置文件
├── Info.plist                   # 应用程序信息配置
├── Debug.xcconfig              # 调试配置
├── build_release.sh            # Release版本构建脚本
├── build_xcode_proj.sh         # Xcode项目构建脚本
├── DESIGN_GUIDELINES.md        # 设计规范
├── TECHNICAL_DOCUMENTATION.md  # 技术文档
└── todo_list.md                # 待办事项
```
## 快速开始

### 环境要求

- macOS 14.0 或更高版本
- Xcode 15.0 或更高版本
- Swift 6.0

### 安装依赖

项目使用 Swift Package Manager 管理依赖，所有依赖都是本地的：

```bash
# 依赖会自动解析
swift package resolve
```

### 构建项目

#### 使用 Xcode

1. 使用 XcodeGen 生成 Xcode 项目（如果还没有）：

   ```bash
   # 如果已安装 xcodegen
   xcodegen generate
   ```

2. 打开 `MiNoteMac.xcodeproj`

3. 选择目标设备并运行（⌘R）

### 创建 Xcode 项目

如果需要重新生成 Xcode 项目：

```bash
./build_xcode_proj.sh
```

## 功能特性

### 富文本编辑

- 支持多种文本格式：加粗、斜体、下划线、删除线、高亮
- 支持标题（大标题、二级标题、三级标题）
- 支持文本对齐（左对齐、居中、右对齐）
- 支持缩进

### 列表支持

- 无序列表（bullet points）
- 有序列表（numbered lists）
- 复选框列表（checkboxes）

### 图片支持

- 插入图片到笔记
- 图片自动上传到云端
- 本地图片缓存

### 文件夹管理

- 创建、重命名、删除文件夹
- 文件夹层级结构
- 笔记分类管理

### 云端同步

- 自动同步笔记到小米笔记服务器
- 离线编辑支持
- 冲突处理
- Cookie 自动刷新

### 数据存储

项目采用双重存储策略：

- **本地存储**: 使用 RTF 格式（archivedData）存储富文本，保证格式完整性和编辑体验
- **云端存储**: 使用 XML 格式（小米笔记格式）存储，与小米笔记服务器兼容

详细说明请参考：

- [文本存储方式说明.md](./文本存储方式说明.md)
- [笔记保存和上传流程说明.md](./笔记保存和上传流程说明.md)

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

### 代码结构

- **App**: 应用程序入口和系统集成（AppDelegate、菜单、窗口管理）
- **Model**: 数据模型定义（Note, Folder, UserProfile 等）
- **Service**: 业务逻辑层（MiNoteService, DatabaseService, LocalStorageService, SyncService 等）
- **ViewModel**: 视图模型（NotesViewModel）
- **View**: UI 视图组件（AppKit 控制器 + SwiftUI 视图）
- **Window**: 窗口控制器和状态管理（MainWindowController, LoginWindowController 等）
- **Extensions**: Swift 扩展
- **Helper**: 辅助工具类
- **Web**: Web 编辑器相关文件

### 关键文件

- `App/AppDelegate.swift`: AppKit 应用委托，管理应用程序生命周期和菜单系统
- `App/App.swift`: SwiftUI 应用入口
- `Window/MainWindowController.swift`: 主窗口控制器，管理窗口、工具栏和分割视图
- `ViewModel/NotesViewModel.swift`: 主视图模型，管理应用状态和业务逻辑
- `Service/MiNoteService.swift`: 小米笔记 API 服务
- `Service/DatabaseService.swift`: SQLite 数据库服务
- `Service/SyncService.swift`: 同步服务
- `View/AppKitComponents/NoteDetailViewController.swift`: 笔记详情 AppKit 视图控制器
- `View/AppKitComponents/NotesListViewController.swift`: 笔记列表 AppKit 视图控制器
- `View/AppKitComponents/SidebarViewController.swift`: 侧边栏 AppKit 视图控制器
### 调试

项目使用统一的调试日志格式，所有调试信息以 `[[调试]]` 开头，方便在控制台中搜索和过滤。

## 已知问题

请参考 [issuesAndFeatures.txt](./issuesAndFeatures.txt) 了解当前已知问题和待完成功能。

## 文档

- [TECHNICAL_DOCUMENTATION.md](./TECHNICAL_DOCUMENTATION.md) - 详细的技术文档，包含架构设计、核心模块、API参考等
- [DESIGN_GUIDELINES.md](./DESIGN_GUIDELINES.md) - 设计规范，包含文件结构、代码规范、开发流程等
- [文本存储方式说明.md](./文本存储方式说明.md) - 详细的数据存储格式说明
- [笔记保存和上传流程说明.md](./笔记保存和上传流程说明.md) - 完整的保存和同步流程
- [小米笔记格式示例.txt](./小米笔记格式示例.txt) - 小米笔记 XML 格式示例
## 依赖说明

本项目使用纯 Swift 实现，不依赖外部富文本编辑框架。编辑器基于自定义的 Web 编辑器实现，使用 HTML/JavaScript 技术栈。

### 核心技术栈

- **Swift 6.0**: 主要开发语言
- **AppKit + SwiftUI**: 混合 UI 框架
- **SQLite 3**: 本地数据存储
- **WebKit**: 富文本编辑器核心
- **URLSession**: 网络请求
- **async/await**: 并发处理

## 法律声明

本项目仅供个人学习和研究使用。详细的风险说明和法律建议请参考 [法律声明与风险提示](./LEGAL_NOTICE.md)。

## 许可证

本项目仅供学习和研究使用。

### 第三方依赖许可证

本项目使用纯 Swift 实现，不依赖外部开源库。所有代码均为原创实现。

## 贡献

欢迎提交 Issue 和 Pull Request。

## 注意事项

- 构建产物（`build/` 目录）已添加到 `.gitignore`，不会提交到仓库
- 备份目录和副本目录不应提交到仓库

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


### v2.0.0: 架构重构
- 采用 AppKit+SwiftUI 混合架构
- 实现完整的 macOS 菜单系统
- 支持多窗口管理
- 优化窗口状态保存和恢复

### v2.1.0: 架构优化和功能增强
- 优化颜色主题系统，使用系统强调色
- 优化项目结构和构建配置
- 优化格式菜单和搜索框筛选菜单样式

### v2.2.0: 新增同步功能
- 新增轻量化同步功能，间隔时间自动同步

#### v2.2.1: 在线状态管理
- 能够异步检测在线状态
- 能够自动刷新cookie

#### v2.2.2: 查找与替换
- 优化工具栏样式
- 新增查找和替换

### v2.3.0 beta: 原生笔记编辑器
- 新增原生笔记编辑器
- 存在大量bug
