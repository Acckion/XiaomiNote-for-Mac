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

## 数据库迁移指南

项目使用版本化迁移机制管理数据库结构变更，迁移文件位于 `Sources/Service/Storage/DatabaseMigrationManager.swift`。

### 添加新迁移

在 `DatabaseMigrationManager.migrations` 数组中添加新条目：

```swift
static let migrations: [Migration] = [
    // 已有迁移...
    
    // 新增迁移
    Migration(
        version: 2,  // 版本号递增
        description: "添加笔记归档字段",
        sql: "ALTER TABLE notes ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0;"
    ),
]
```

### 迁移规则

- 版本号必须递增（1, 2, 3...），不能跳跃或修改已发布的迁移
- 每个迁移是原子操作，失败会自动回滚
- SQL 语句建议使用 `IF NOT EXISTS` / `IF EXISTS` 增强健壮性
- 迁移在应用启动时自动执行

### 常见迁移类型

```swift
// 添加列
"ALTER TABLE notes ADD COLUMN new_field TEXT;"

// 添加索引
"CREATE INDEX IF NOT EXISTS idx_name ON table(column);"

// 创建新表
"CREATE TABLE IF NOT EXISTS new_table (id TEXT PRIMARY KEY, ...);"

// 删除索引
"DROP INDEX IF EXISTS idx_name;"
```

### 注意事项

- SQLite 不支持 `DROP COLUMN`，需要重建表
- 复杂迁移可使用多条 SQL 语句，用分号分隔
- 测试迁移时可删除本地数据库文件（位于 `~/Library/Application Support/com.mi.note.mac/minote.db`）

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
