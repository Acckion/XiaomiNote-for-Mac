# MiNoteMac 开发指南

小米笔记 macOS 客户端：一个使用 Swift 开发的原生 macOS 应用，用于同步和管理小米笔记。

## 项目概述

- **语言**: Swift 6.0
- **UI 框架**: AppKit + SwiftUI 混合架构
- **数据存储**: SQLite 3
- **网络请求**: URLSession
- **项目生成**: XcodeGen
- **最低系统要求**: macOS 15.0+

## 项目结构

```
Sources/
├── App/                    # 应用程序入口（AppDelegate, MenuManager）
├── Model/                  # 数据模型（Note, Folder 等）
├── Service/                # 业务服务层（模块化）
│   ├── Audio/              # 音频服务
│   ├── Network/            # 网络服务（MiNoteService）
│   ├── Sync/               # 同步服务
│   ├── Storage/            # 存储服务（DatabaseService）
│   ├── Editor/             # 编辑器服务
│   └── Core/               # 核心服务
├── ViewModel/              # 视图模型（NotesViewModel）
├── View/                   # UI 视图组件
│   ├── AppKitComponents/   # AppKit 视图控制器
│   ├── Bridge/             # SwiftUI-AppKit 桥接
│   ├── NativeEditor/       # 原生富文本编辑器
│   ├── SwiftUIViews/       # SwiftUI 视图
│   └── Shared/             # 共享组件
├── Window/                 # 窗口控制器
├── ToolbarItem/            # 工具栏组件
├── Extensions/             # Swift 扩展
└── Web/                    # Web 编辑器（备用）

Tests/                      # 测试代码
References/                 # 参考项目（不参与编译）
```

## 构建命令

```bash
# 生成 Xcode 项目（修改 project.yml 后必须执行）
xcodegen generate

# 构建 Release 版本
./scripts/build_release.sh

# 构建 Debug 版本
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug

# 运行测试
xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac -destination 'platform=macOS'
```

## 代码规范

### 禁止事项

- 禁止在代码、注释、控制台输出中使用 emoji
- 禁止添加过多解释性注释，代码应当自解释
- 禁止提交敏感信息（Cookie、密钥等）
- 禁止提交构建产物（.build/、build/）

### 注释规范

- 只在复杂逻辑或非显而易见的实现处添加注释
- 注释使用中文
- 避免注释描述"做什么"，而应描述"为什么"
- 公开 API 使用文档注释（///）

### 日志规范

- 调试日志统一使用 `[[调试]]` 前缀
- 日志信息使用中文
- 避免在生产代码中保留过多调试日志

### 命名规范

- 类型名使用 PascalCase
- 变量和函数名使用 camelCase
- 常量使用 camelCase 或 UPPER_SNAKE_CASE
- 文件名与主要类型名一致

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

### 关键文件

- `AppDelegate.swift`: 应用生命周期、菜单系统
- `MainWindowController.swift`: 主窗口、工具栏、分割视图
- `NotesViewModel.swift`: 主业务逻辑和状态管理
- `MiNoteService.swift`: 小米笔记 API 调用
- `DatabaseService.swift`: SQLite 数据库操作
- `SyncService.swift`: 云端同步逻辑
- `NativeEditorView.swift`: 原生富文本编辑器

## 数据格式

- **本地存储**: SQLite 数据库
- **云端格式**: XML（小米笔记格式）
- **编辑器格式**: NSAttributedString（原生编辑器）/ HTML（Web 编辑器）

## Git 提交规范

```
<type>(<scope>): <subject>
```

类型：feat, fix, refactor, perf, style, docs, test, chore, revert

示例：
- `feat(editor): 添加原生富文本编辑器支持`
- `fix(sync): 修复离线操作队列重复执行问题`
- `docs: 更新技术文档`

## 注意事项

1. 修改 `project.yml` 后必须执行 `xcodegen generate`
2. 提交前确保代码可以编译通过
3. 大型任务拆分为多个小提交
4. 每个提交应该是可编译、可运行的状态
5. 本项目不依赖外部开源库，所有代码均为原创实现
