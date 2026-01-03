# Implementation Plan

[Overview]
规范化 MiNoteMac 项目的混合架构，按照功能模块重新组织 View 文件夹下的文件，采用教程中的示例项目结构作为参考模板，保持现有的 AppKit 和 SwiftUI 混合方式不变。

本项目是一个采用 AppKit 和 SwiftUI 混合架构的 macOS 笔记应用，当前 View 文件夹下有 28 个文件，组织不够规范。本实现计划旨在按照教程中的混合项目结构示例，将文件按照功能模块重新组织，提高代码的可读性和可维护性。我们将保持现有的混合架构不变，包括 AppKit 嵌入 SwiftUI 和 SwiftUI 包装 AppKit 的现有实现，仅对文件组织结构进行优化。

[Types]  
本项目使用现有的类型系统，不需要创建新的类型定义。

项目已经定义了完整的类型系统，包括 Note、Folder、UserProfile 等核心数据模型，以及 NotesViewModel 等视图模型。这些类型定义将保持不变，我们只关注文件组织结构的优化。

[Files]
按照功能模块重新组织 View 文件夹下的 28 个文件，创建新的目录结构。

详细文件结构调整计划：

### 新目录结构
```
Sources/MiNoteLibrary/View/
├── AppKitComponents/         // 纯 AppKit 组件
│   ├── NotesListViewController.swift
│   ├── SidebarViewController.swift
│   └── NoteDetailViewController.swift
├── SwiftUIViews/             // 纯 SwiftUI 组件
│   ├── ContentView.swift
│   ├── SidebarView.swift
│   ├── NotesListView.swift
│   ├── NoteDetailView.swift
│   ├── SettingsView.swift
│   ├── LoginView.swift
│   ├── CookieRefreshView.swift
│   ├── TrashView.swift
│   ├── WebEditorView.swift
│   ├── PrivateNotesPasswordInputDialogView.swift
│   ├── PrivateNotesVerificationView.swift
│   ├── OfflineOperationsProgressView.swift
│   ├── NetworkLogView.swift
│   ├── DebugSettingsView.swift
│   ├── MoveNoteView.swift
│   ├── NewNoteView.swift
│   ├── NoteDetailWindowView.swift
│   ├── NoteHistoryView.swift
│   ├── TitleEditorView.swift
│   ├── SearchFilterMenuContent.swift
│   └── SearchFilterPopoverView.swift
├── Bridge/                  // 桥接层组件
│   ├── NotesListHostingController.swift    // SwiftUI 包装器
│   ├── SidebarHostingController.swift      // SwiftUI 包装器
│   ├── WebEditorWrapper.swift              // Web 编辑器包装器
│   ├── WebEditorContext.swift              // 编辑器上下文
│   └── WebFormatMenuView.swift             // 格式菜单视图
└── Shared/                  // 共享组件（混合使用）
    └── OnlineStatusIndicator.swift         // 在线状态指示器
```

### 文件移动详细说明

#### AppKitComponents/ (3个文件)
- `NotesListViewController.swift` - AppKit 表格视图控制器，显示笔记列表
- `SidebarViewController.swift` - AppKit OutlineView 控制器，显示文件夹列表
- `NoteDetailViewController.swift` - AppKit 视图控制器，管理笔记详情编辑区域

#### SwiftUIViews/ (21个文件)
- `ContentView.swift` - 主内容视图，三栏布局容器
- `SidebarView.swift` - SwiftUI 侧边栏视图（当前版本）
- `NotesListView.swift` - SwiftUI 笔记列表视图（旧版本，可能已弃用）
- `NoteDetailView.swift` - SwiftUI 笔记详情视图
- `SettingsView.swift` - 设置视图
- `LoginView.swift` - 登录视图
- `CookieRefreshView.swift` - Cookie 刷新视图
- `TrashView.swift` - 回收站视图
- `WebEditorView.swift` - Web 编辑器视图
- `PrivateNotesPasswordInputDialogView.swift` - 私密笔记密码输入对话框
- `PrivateNotesVerificationView.swift` - 私密笔记验证视图
- `OfflineOperationsProgressView.swift` - 离线操作进度视图
- `NetworkLogView.swift` - 网络日志视图
- `DebugSettingsView.swift` - 调试设置视图
- `MoveNoteView.swift` - 移动笔记视图
- `NewNoteView.swift` - 新建笔记视图
- `NoteDetailWindowView.swift` - 笔记详情窗口视图
- `NoteHistoryView.swift` - 笔记历史视图
- `TitleEditorView.swift` - 标题编辑器视图
- `SearchFilterMenuContent.swift` - 搜索筛选菜单内容
- `SearchFilterPopoverView.swift` - 搜索筛选弹窗视图

#### Bridge/ (5个文件)
- `NotesListHostingController.swift` - 将 NotesListViewController 包装为 SwiftUI 视图
- `SidebarHostingController.swift` - 将 SidebarViewController 包装为 SwiftUI 视图
- `WebEditorWrapper.swift` - Web 编辑器包装器，桥接 SwiftUI 和 Web 视图
- `WebEditorContext.swift` - Web 编辑器上下文，管理编辑器状态
- `WebFormatMenuView.swift` - Web 格式菜单视图，提供文本格式操作

#### Shared/ (1个文件)
- `OnlineStatusIndicator.swift` - 在线状态指示器，在工具栏中使用

### 需要更新的导入语句
移动文件后，需要更新以下文件的导入语句：
1. `ContentView.swift` - 更新 NotesListViewController 和 SidebarViewController 的导入路径
2. `MainWindowController.swift` - 更新各种视图控制器的导入路径
3. `AppDelegate.swift` - 更新设置、登录、Cookie刷新等窗口控制器的导入路径
4. 其他相关文件中的导入语句

[Functions]
更新相关函数中的文件引用路径，确保代码编译通过。

### 需要更新的函数
1. `ContentView` 中的 `NotesListViewControllerWrapper` 结构体 - 更新 NotesListViewController 的引用
2. `MainWindowController` 中的窗口控制器创建方法 - 更新各种视图的引用路径
3. `AppDelegate` 中的菜单动作方法 - 更新窗口控制器的引用路径
4. 所有使用 `@main` 或 `@UIApplicationMain` 的文件 - 确保入口点正确

### 具体修改内容
- 更新所有 `import` 语句中的相对路径
- 更新文件创建和初始化的路径
- 确保 Xcode 项目文件中的文件引用同步更新
- 验证所有桥接组件能正确访问对应的 AppKit 或 SwiftUI 组件

[Classes]
保持现有类结构不变，仅更新文件位置和导入路径。

### 主要类分类
#### AppKit 类 (保留在 AppKitComponents/)
- `NotesListViewController` - 笔记列表视图控制器
- `SidebarViewController` - 侧边栏视图控制器
- `NoteDetailViewController` - 笔记详情视图控制器

#### SwiftUI 类 (移动到 SwiftUIViews/)
- `ContentView` - 主内容视图
- `SidebarView` - 侧边栏视图
- `NoteDetailView` - 笔记详情视图
- 其他所有 SwiftUI 视图组件

#### 桥接类 (移动到 Bridge/)
- `NotesListHostingController` - 托管控制器
- `SidebarHostingController` - 托管控制器
- `WebEditorWrapper` - Web 编辑器包装器

#### 共享类 (移动到 Shared/)
- `OnlineStatusIndicator` - 在线状态指示器

[Dependencies]
本项目没有外部依赖变更，仅涉及内部文件组织结构调整。

现有的依赖关系包括：
- AppKit 框架 - macOS 原生 UI 框架
- SwiftUI 框架 - 现代声明式 UI 框架
- Combine 框架 - 响应式编程框架
- Foundation 框架 - 基础框架

所有依赖保持不变，不需要添加或移除任何包依赖。

[Testing]
文件移动后需要确保所有功能测试通过。

### 测试策略
1. **编译测试** - 确保项目能够成功编译，没有缺失的文件引用
2. **运行时测试** - 启动应用程序，验证主要功能正常工作：
   - 侧边栏显示和文件夹选择
   - 笔记列表显示和选择
   - 笔记编辑和保存
   - 设置、登录、Cookie刷新等对话框
   - 工具栏和菜单功能
3. **集成测试** - 验证混合架构组件之间的交互：
   - AppKit 组件在 SwiftUI 中的嵌入
   - SwiftUI 组件在 AppKit 中的包装
   - 数据流和状态管理
4. **回归测试** - 确保现有功能不受影响

### 测试文件更新
如果存在测试文件，需要相应更新测试文件中的导入路径。

[Implementation Order]
按照逻辑顺序执行文件移动和更新，确保每一步都能编译通过。

### 实施步骤
1. **步骤 1：创建新目录结构**
   - 在 `Sources/MiNoteLibrary/View/` 下创建 `AppKitComponents/` 目录
   - 在 `Sources/MiNoteLibrary/View/` 下创建 `SwiftUIViews/` 目录
   - 在 `Sources/MiNoteLibrary/View/` 下创建 `Bridge/` 目录
   - 在 `Sources/MiNoteLibrary/View/` 下创建 `Shared/` 目录

2. **步骤 2：移动 AppKit 组件**
   - 移动 `NotesListViewController.swift` 到 `AppKitComponents/`
   - 移动 `SidebarViewController.swift` 到 `AppKitComponents/`
   - 移动 `NoteDetailViewController.swift` 到 `AppKitComponents/`
   - 更新相关导入语句

3. **步骤 3：移动 SwiftUI 视图**
   - 移动 21 个 SwiftUI 视图文件到 `SwiftUIViews/` 目录
   - 按照功能分类组织文件
   - 更新相关导入语句

4. **步骤 4：移动桥接组件**
   - 移动 5 个桥接文件到 `Bridge/` 目录
   - 更新相关导入语句

5. **步骤 5：移动共享组件**
   - 移动 `OnlineStatusIndicator.swift` 到 `Shared/` 目录
   - 更新相关导入语句

6. **步骤 6：更新项目配置文件**
   - 更新 `project.yml` 中的文件引用
   - 确保 Xcode 项目文件同步更新

7. **步骤 7：编译和测试**
   - 编译项目，修复所有编译错误
   - 运行应用程序，测试主要功能
   - 验证混合架构组件正常工作

8. **步骤 8：清理和优化**
   - 删除空的原始目录（如果适用）
   - 更新文档中的文件引用
   - 验证代码风格一致性

### 风险缓解
- 每一步完成后都进行编译测试
- 使用版本控制（Git）跟踪所有更改
- 创建备份副本以防需要回滚
- 优先移动依赖较少的文件，逐步处理复杂依赖
