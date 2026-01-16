# 小米笔记 macOS 客户端 - 设计规范

## 概述

本文档总结了小米笔记 macOS 客户端的设计规范和开发指南。

---

## 架构设计规范

### 1. 混合架构原则

#### 1.1 架构分层

```
AppKit 控制器层 (AppDelegate, WindowController, ViewController)
        ↓
SwiftUI 视图层 (View, ViewModel)
        ↓
服务层 (Service)
        ↓
数据模型层 (Model)
```

#### 1.2 各层职责

- **AppKit 控制器层**: 窗口管理、菜单系统、工具栏、应用程序生命周期
- **SwiftUI 视图层**: 声明式 UI、状态管理、用户交互
- **服务层**: 业务逻辑、数据操作、网络请求、数据库访问
- **数据模型层**: 数据结构定义、数据持久化

### 2. 文件结构规范

#### 2.1 目录结构

```
Sources/
├── App/                # 应用程序入口和系统集成
├── Model/              # 数据模型
├── Service/            # 服务层
├── ViewModel/          # 视图模型
├── View/               # UI 视图组件
│   ├── AppKitComponents/   # AppKit 视图控制器
│   ├── Bridge/             # SwiftUI-AppKit 桥接
│   ├── NativeEditor/       # 原生富文本编辑器
│   ├── SwiftUIViews/       # SwiftUI 视图
│   └── Shared/             # 共享视图组件
├── Window/             # 窗口控制器
├── ToolbarItem/        # 工具栏组件
├── Extensions/         # 扩展
├── Helper/             # 辅助工具
└── Web/                # Web 编辑器相关文件
```

#### 2.2 文件命名规范

- **Swift 文件**: PascalCase，如 `NoteDetailViewController.swift`
- **资源文件**: snake_case，如 `editor.html`
- **配置文件**: kebab-case，如 `project.yml`

### 3. 代码规范

#### 3.1 命名规范

- **类型名**: PascalCase，如 `Note`, `NotesViewModel`
- **变量和函数名**: camelCase，如 `selectedNote`, `loadNotes()`
- **常量**: camelCase，如 `baseURL`, `maxRetryCount`
- **私有成员**: 使用 `private` 关键字

#### 3.2 注释规范

- **文档注释**: 使用 `///` 为公开的 API 添加文档注释
- **复杂逻辑**: 在复杂逻辑前添加行内注释
- **TODO 和 FIXME**: 使用 `// TODO:` 和 `// FIXME:` 标记待办事项
- **调试日志**: 使用统一的日志格式 `print("[ClassName] 日志内容")`

#### 3.3 线程安全规范

- **UI 操作**: 必须在主线程执行，使用 `@MainActor`
- **后台操作**: 使用 `async/await` 在后台线程执行
- **数据库操作**: 使用 `DatabaseService` 的并发队列
- **网络请求**: 使用 `URLSession` 的异步 API

### 4. 编辑器开发规范

#### 4.1 原生编辑器

- 使用 `NSTextView` + `NSTextStorage`
- 格式状态通过 `FormatStateSynchronizer` 同步
- 附件使用 `NSTextAttachment` 子类

#### 4.2 格式转换

- 使用 `XiaoMiFormatConverter` 进行格式转换
- XML 与 NSAttributedString 双向转换
- 保持与小米笔记服务器格式兼容

#### 4.3 菜单同步

- 格式菜单状态通过 `Notification` 同步
- 使用 `FormatStateManager` 管理统一状态

### 5. 窗口和视图管理规范

#### 5.1 窗口控制器规范

- 继承自 `NSWindowController`
- 实现 `savableWindowState()` 和 `restoreWindowState(_:)`
- 使用 `NSToolbar` 和自定义工具栏项

#### 5.2 SwiftUI 视图规范

- 使用 `View` 协议实现声明式 UI
- 使用 `@State`, `@StateObject`, `@ObservedObject` 管理状态
- 使用 `@Binding` 实现父子视图数据传递

### 6. 性能优化规范

#### 6.1 内存优化

- 合理使用内存缓存和磁盘缓存
- 图片按需加载和压缩
- 避免强引用循环

#### 6.2 响应速度优化

- 使用 `async/await` 避免阻塞主线程
- 实现防抖机制减少不必要的操作
- 按需加载数据和视图

### 7. 开发流程规范

#### 7.1 新功能开发流程

1. **需求分析**: 明确功能需求和界面设计
2. **架构设计**: 确定使用 AppKit 还是 SwiftUI
3. **数据模型**: 设计或扩展数据模型
4. **服务层**: 实现业务逻辑和数据操作
5. **ViewModel**: 实现状态管理和业务逻辑
6. **UI 层**: 实现界面
7. **测试**: 单元测试和集成测试
8. **文档**: 更新技术文档

#### 7.2 代码审查要点

- 架构一致性
- 代码质量
- 性能考虑
- 安全性
- 可维护性

---

## 附录

### A. 常用命令

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

### B. 推荐开发工具

1. **Xcode**: 主要开发工具
2. **Git**: 版本控制
3. **XcodeGen**: 项目生成工具
4. **Instruments**: 性能分析工具

---

**最后更新**: 2026年1月16日
**版本**: 3.3.0
