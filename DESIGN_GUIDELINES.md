# 小米笔记 macOS 客户端 - 设计规范

## 概述

本文档总结了小米笔记 macOS 客户端从纯 SwiftUI 迁移到 AppKit+SwiftUI 混合架构后的设计规范和文件结构，供后续开发遵循。

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

#### 1.3 数据流向

1. 用户操作 → AppKit 控制器接收
2. AppKit 控制器 → 调用 ViewModel 方法
3. ViewModel → 调用 Service 执行操作
4. Service → 更新 Model 数据
5. ViewModel → 更新 @Published 状态
6. SwiftUI View → 自动重新渲染

### 2. 文件结构规范

#### 2.1 目录结构

```
Sources/MiNoteLibrary/
├── Model/              # 数据模型
│   ├── Note.swift
│   ├── Folder.swift
│   ├── DeletedNote.swift
│   ├── NoteHistoryVersion.swift
│   └── UserProfile.swift
├── Service/            # 服务层
│   ├── MiNoteService.swift          # 小米笔记 API 服务
│   ├── DatabaseService.swift        # SQLite 数据库服务
│   ├── LocalStorageService.swift    # 本地文件存储服务
│   ├── SyncService.swift           # 同步服务
│   ├── OfflineOperationQueue.swift # 离线操作队列
│   ├── OfflineOperationProcessor.swift # 离线操作处理器
│   ├── NetworkMonitor.swift        # 网络状态监控
│   ├── AuthenticationStateManager.swift # 认证状态管理
│   ├── PrivateNotesPasswordManager.swift # 私密笔记密码管理
│   ├── SaveQueueManager.swift      # 保存队列管理器
│   └── MemoryCacheManager.swift    # 内存缓存管理器
├── View/               # UI 视图组件
│   ├── AppKitComponents/           # AppKit 视图控制器
│   │   ├── NoteDetailViewController.swift
│   │   ├── NotesListViewController.swift
│   │   └── SidebarViewController.swift
│   ├── Bridge/                     # SwiftUI-AppKit 桥接
│   │   ├── NotesListHostingController.swift
│   │   ├── SidebarHostingController.swift
│   │   ├── WebEditorContext.swift
│   │   ├── WebEditorWrapper.swift
│   │   └── WebFormatMenuView.swift
│   ├── Shared/                     # 共享视图组件
│   │   └── OnlineStatusIndicator.swift
│   └── SwiftUIViews/               # SwiftUI 视图
│       ├── ContentView.swift            # 主内容视图（三栏布局）
│       ├── NotesListView.swift          # 笔记列表视图
│       ├── NoteDetailView.swift         # 笔记详情/编辑视图
│       ├── SidebarView.swift            # 侧边栏视图
│       ├── WebEditorView.swift          # Web 编辑器视图
│       └── ... (其他视图)
├── ViewModel/          # 视图模型
│   └── NotesViewModel.swift        # 主视图模型
├── Window/             # 窗口控制器
│   ├── MainWindowController.swift       # 主窗口控制器
│   ├── LoginWindowController.swift      # 登录窗口控制器
│   ├── SettingsWindowController.swift   # 设置窗口控制器
│   ├── HistoryWindowController.swift    # 历史记录窗口控制器
│   ├── TrashWindowController.swift      # 回收站窗口控制器
│   ├── CookieRefreshWindowController.swift # Cookie刷新窗口控制器
│   ├── DebugWindowController.swift      # 调试窗口控制器
│   ├── WindowStateManager.swift         # 窗口状态管理器
│   └── ... (其他窗口控制器)
├── Extensions/         # 扩展
│   └── NSWindow+MiNote.swift
├── Helper/             # 辅助工具
│   └── NoteMoveHelper.swift
└── Web/                 # Web 编辑器相关文件
    ├── editor.html                  # 编辑器 HTML
    ├── xml-to-html.js               # XML 转 HTML 转换器
    └── html-to-xml.js               # HTML 转 XML 转换器
```

#### 2.2 文件命名规范

- **Swift 文件**: PascalCase，如 `NoteDetailViewController.swift`
- **资源文件**: snake_case，如 `editor.html`
- **配置文件**: kebab-case，如 `project.yml`
- **目录名**: PascalCase 或 camelCase，保持一致性

#### 2.3 代码组织规范

1. **每个文件一个主要类型**: 每个 Swift 文件应该只包含一个主要的类、结构体或枚举
2. **扩展分离**: 扩展可以放在单独的文件中，特别是大型扩展
3. **相关功能分组**: 相关功能放在同一个目录中
4. **依赖关系清晰**: 避免循环依赖，保持依赖关系单向

### 3. 代码规范

#### 3.1 命名规范

- **类型名**: PascalCase，如 `Note`, `NotesViewModel`
- **变量和函数名**: camelCase，如 `selectedNote`, `loadNotes()`
- **常量**: camelCase，如 `baseURL`, `maxRetryCount`
- **私有成员**: 使用 `private` 关键字
- **协议名**: 以 `-able` 或 `-ing` 结尾，如 `Codable`, `Observable`

#### 3.2 注释规范

- **文档注释**: 使用 `///` 为公开的 API 添加文档注释
- **复杂逻辑**: 在复杂逻辑前添加行内注释
- **TODO 和 FIXME**: 使用 `// TODO:` 和 `// FIXME:` 标记待办事项
- **调试日志**: 使用统一的日志格式 `print("[ClassName] 日志内容")`

#### 3.3 错误处理规范

- **可恢复错误**: 使用 `throw` 抛出，调用方处理
- **不可恢复错误**: 使用 `fatalError()` 或 `assert()`
- **用户友好错误**: 显示清晰的错误信息，提供解决方案
- **错误日志**: 记录详细的错误信息，便于调试

#### 3.4 线程安全规范

- **UI 操作**: 必须在主线程执行，使用 `@MainActor`
- **后台操作**: 使用 `async/await` 在后台线程执行
- **数据库操作**: 使用 `DatabaseService` 的并发队列
- **网络请求**: 使用 `URLSession` 的异步 API

### 4. 窗口和视图管理规范

#### 4.1 窗口控制器规范

1. **继承关系**: 窗口控制器应该继承自 `NSWindowController`
2. **状态管理**: 实现 `savableWindowState()` 和 `restoreWindowState(_:)`
3. **工具栏**: 使用 `NSToolbar` 和自定义工具栏项
4. **生命周期**: 正确处理窗口的创建、显示、隐藏、关闭

#### 4.2 视图控制器规范

1. **AppKit 视图控制器**: 继承自 `NSViewController`，管理特定区域的 UI
2. **SwiftUI 托管**: 使用 `NSHostingController` 包装 SwiftUI 视图
3. **状态传递**: 通过 ViewModel 在视图间传递状态
4. **生命周期**: 正确处理 `viewDidLoad()`、`viewWillAppear()` 等

#### 4.3 SwiftUI 视图规范

1. **视图结构**: 使用 `View` 协议实现声明式 UI
2. **状态管理**: 使用 `@State`, `@StateObject`, `@ObservedObject` 管理状态
3. **数据绑定**: 使用 `@Binding` 实现父子视图数据传递
4. **性能优化**: 使用 `EquatableView` 或自定义 `Equatable` 实现优化渲染

### 5. 数据管理规范

#### 5.1 数据模型规范

1. **值类型优先**: 优先使用结构体 (`struct`) 而不是类 (`class`)
2. **不可变性**: 尽可能使用 `let` 声明不可变属性
3. **Codable 支持**: 实现 `Codable` 协议支持序列化和反序列化
4. **Equatable/Hashable**: 实现 `Equatable` 和 `Hashable` 协议支持比较和哈希

#### 5.2 数据库操作规范

1. **线程安全**: 所有数据库操作必须通过 `DatabaseService` 的并发队列
2. **错误处理**: 正确处理数据库操作错误
3. **事务管理**: 使用事务确保数据一致性
4. **性能优化**: 为常用查询字段添加索引

#### 5.3 网络请求规范

1. **认证管理**: 使用 `MiNoteService` 管理 Cookie 和认证
2. **错误处理**: 正确处理网络错误和服务器错误
3. **重试机制**: 实现智能重试机制
4. **离线支持**: 网络不可用时将操作加入离线队列

### 6. 性能优化规范

#### 6.1 内存优化

1. **缓存策略**: 合理使用内存缓存和磁盘缓存
2. **图片优化**: 压缩图片，按需加载
3. **对象生命周期**: 及时释放不再使用的对象
4. **循环引用**: 避免强引用循环，使用 `weak` 或 `unowned`

#### 6.2 响应速度优化

1. **异步操作**: 使用 `async/await` 避免阻塞主线程
2. **防抖机制**: 减少不必要的操作（如保存、搜索）
3. **懒加载**: 按需加载数据和视图
4. **预加载**: 预加载可能需要的资源

#### 6.3 电池消耗优化

1. **网络请求**: 合并请求，减少频率
2. **定时任务**: 合理设置定时器间隔
3. **后台任务**: 优化后台同步和处理
4. **资源使用**: 减少不必要的 CPU 和内存使用

### 7. 安全规范

#### 7.1 数据安全

1. **敏感数据**: 使用系统提供的安全存储（如 Keychain）
2. **网络传输**: 使用 HTTPS 加密传输
3. **本地存储**: 数据库文件使用系统保护
4. **密码管理**: 使用安全的密码管理方案

#### 7.2 认证安全

1. **Cookie 管理**: 安全存储和管理 Cookie
2. **过期检测**: 自动检测 Cookie 过期并提示重新登录
3. **错误处理**: 妥善处理认证错误，不泄露敏感信息
4. **自动刷新**: Cookie 即将过期时自动刷新

#### 7.3 隐私保护

1. **数据最小化**: 只收集必要的数据
2. **本地处理**: 尽可能在本地处理数据
3. **日志脱敏**: 调试日志不包含敏感用户信息
4. **权限控制**: 仅请求必要的系统权限

### 8. 测试规范

#### 8.1 单元测试

1. **测试覆盖**: 所有公开的 API 应该有单元测试
2. **测试隔离**: 测试应该相互独立，不依赖外部状态
3. **测试数据**: 使用模拟数据而不是真实数据
4. **异步测试**: 正确处理异步操作的测试

#### 8.2 集成测试

1. **端到端测试**: 测试完整的用户流程
2. **数据一致性**: 测试数据在不同模块间的一致性
3. **错误处理**: 测试错误处理流程
4. **性能测试**: 测试关键路径的性能

#### 8.3 UI 测试

1. **用户交互**: 测试重要的用户交互
2. **界面状态**: 测试界面在不同状态下的表现
3. **可访问性**: 测试可访问性支持
4. **多语言**: 测试多语言支持

### 9. 文档规范

#### 9.1 代码文档

1. **API 文档**: 所有公开的 API 应该有文档注释
2. **架构文档**: 记录架构设计和决策
3. **流程文档**: 记录重要的业务流程
4. **部署文档**: 记录部署和发布流程

#### 9.2 用户文档

1. **使用指南**: 提供清晰的使用指南
2. **常见问题**: 提供常见问题解答
3. **故障排除**: 提供故障排除指南
4. **更新日志**: 记录版本更新内容

### 10. 开发流程规范

#### 10.1 新功能开发流程

1. **需求分析**: 明确功能需求和界面设计
2. **架构设计**: 确定使用 AppKit 还是 SwiftUI，或混合使用
3. **数据模型**: 设计或扩展数据模型
4. **服务层**: 实现业务逻辑和数据操作
5. **ViewModel**: 实现状态管理和业务逻辑
6. **UI 层**: 实现界面（AppKit 控制器或 SwiftUI 视图）
7. **测试**: 单元测试和集成测试
8. **文档**: 更新技术文档和 API 文档

#### 10.2 代码审查要点

- **架构一致性**: 符合混合架构设计原则
- **代码质量**: 遵循代码规范，无警告和错误
- **性能考虑**: 内存使用、响应速度、电池消耗
- **安全性**: 数据加密、认证安全、输入验证
- **可维护性**: 代码清晰、注释完整、易于修改

#### 10.3 版本发布流程

1. **功能完成**: 所有功能开发完成并通过测试
2. **代码审查**: 通过代码审查
3. **集成测试**: 通过集成测试
4. **性能测试**: 通过性能测试
5. **文档更新**: 更新所有相关文档
6. **版本发布**: 发布新版本

---

## 附录

### A. 常用工具和命令

```bash
# 生成 Xcode 项目
xcodegen generate

# 构建项目
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug

# 运行测试
xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac -destination 'platform=macOS'

# 清理构建产物
xcodebuild clean -project MiNoteMac.xcodeproj -scheme MiNoteMac
```

### B. 推荐开发工具

1. **Xcode**: 主要开发工具
2. **Git**: 版本控制
3. **XcodeGen**: 项目生成工具
4. **SwiftLint**: 代码规范检查
5. **Instruments**: 性能分析工具

### C. 参考资源

1. [Apple 开发者文档](https://developer.apple.com/documentation/)
2. [SwiftUI 官方文档](https://developer.apple.com/documentation/swiftui/)
3. [AppKit 官方文档](https://developer.apple.com/documentation/appkit/)
4. [Swift 官方文档](https://docs.swift.org/swift-book/)

---

**最后更新**: 2026年1月4日  
**版本**: 1.0.0  
**维护者**: 项目维护团队  
**状态**: 活跃维护中
