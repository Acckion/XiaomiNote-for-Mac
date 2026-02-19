# 技术栈

## 核心技术

- **语言**: Swift 6.0
- **UI 框架**: AppKit + SwiftUI 混合架构
- **数据存储**: SQLite 3
- **网络请求**: URLSession
- **富文本编辑**: 自定义 Web 编辑器（WebKit）+ 原生编辑器
- **并发处理**: async/await, Task, Actor
- **架构模式**: MVVM + AppKit 控制器

## 构建系统

- **项目生成**: XcodeGen（project.yml）
- **包管理**: Swift Package Manager（本地依赖）
- **IDE**: Xcode 15.0+

## 常用命令

```bash
# 生成 Xcode 项目
xcodegen generate
# 或使用脚本
./scripts/build_xcode_proj.sh

# 构建 Release 版本
./scripts/build_release.sh

# 统计代码行数
./scripts/count_lines.sh

# 构建项目
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug

# 运行测试
xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac -destination 'platform=macOS'

# 清理构建
xcodebuild clean -project MiNoteMac.xcodeproj -scheme MiNoteMac
```

## 关键依赖

项目使用纯 Swift 实现，不依赖外部开源库。所有代码均为原创实现。

## 数据格式

- **本地存储**: SQLite 数据库
- **云端格式**: XML（小米笔记格式）
- **编辑器格式**: HTML（Web 编辑器）/ NSAttributedString（原生编辑器）

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
- 迁移在应用启动时自动执行（`DatabaseService.createTables()` 调用）

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
