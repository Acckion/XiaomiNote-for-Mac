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
