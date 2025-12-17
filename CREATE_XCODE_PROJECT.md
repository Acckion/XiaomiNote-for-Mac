# 在 Xcode 中使用 Swift Package Manager 项目

## 重要说明

**Swift Package Manager 项目不使用 `.xcodeproj` 或 `.xcworkspace` 文件。**

SPM 项目使用：
- ✅ **Package.swift** - 软件包清单文件（主要配置）
- ✅ **文件夹结构** - 标准的 `Sources/` 目录结构
- ❌ **不需要** `.xcodeproj` 或 `.xcworkspace`

## 方法 1：直接打开 Package.swift（推荐，标准方式）

Swift Package Manager 项目可以直接在 Xcode 中打开，无需创建任何项目文件：

1. **打开 Xcode**
2. **选择 `File → Open...`**（或按 `⌘O`）
3. **选择项目根目录的 `Package.swift` 文件**
4. **点击 "Open"**

Xcode 会自动识别为 Swift Package，你可以：
- 编辑代码
- 使用预览功能（需要设置 ENABLE_DEBUG_DYLIB）
- 运行和调试

### 设置预览功能

打开 Package.swift 后：

1. 在项目导航器中，选择 "MiNoteMac" 包
2. 选择 "MiNoteMac" 目标（在 TARGETS 下）
3. 点击 "Build Settings" 标签页
4. 点击左上角的 "+" 按钮，选择 "Add User-Defined Setting"
5. 设置：
   - **键名**: `ENABLE_DEBUG_DYLIB`
   - **值**: `YES`
   - 确保在 **Debug** 配置下设置为 `YES`

## 方法 2：生成 .xcodeproj 文件（仅特殊需求）

**注意**: 只有在特殊情况下才需要生成 `.xcodeproj` 文件，例如：
- 需要使用某些仅支持 .xcodeproj 的 CI/CD 工具
- 需要使用某些第三方工具或插件
- 团队有特殊的工作流程要求

**对于日常开发，强烈推荐使用方法 1**（直接打开 Package.swift）。

如果你确实需要标准的 .xcodeproj 文件，可以：

### 选项 A：使用 Xcode GUI 创建

1. 打开 Xcode
2. 选择 `File → New → Project...`
3. 选择 "macOS" → "App"
4. 填写项目信息：
   - Product Name: `MiNoteMac`
   - Organization Identifier: 你的组织标识
   - Language: Swift
   - Interface: SwiftUI
5. 保存项目
6. 删除自动生成的代码文件
7. 将 `Sources/MiNoteMac` 中的所有文件添加到项目
8. 在 Build Settings 中设置 `ENABLE_DEBUG_DYLIB = YES`

### 选项 B：使用 XcodeGen 生成项目（推荐，已配置）

项目已包含 `project.yml` 配置文件，只需：

```bash
# 1. 安装 XcodeGen（如果还没有）
brew install xcodegen

# 2. 生成 Xcode 项目
xcodegen generate

# 3. 打开生成的项目
open MiNoteMac.xcodeproj
```

**注意**: `project.yml` 已配置 `ENABLE_DEBUG_DYLIB: YES`，生成的项目可以直接使用预览功能！

## 推荐方案

**对于开发，强烈推荐使用方法 1**（直接打开 Package.swift），因为：
- ✅ **标准方式** - 这是 SPM 项目的正确打开方式
- ✅ **更简单** - 无需额外工具或配置
- ✅ **保持原生结构** - 不改变 SPM 项目的结构
- ✅ **完整支持** - 支持所有 Xcode 功能（编辑、预览、调试、测试）
- ✅ **易于维护** - 配置集中在 Package.swift 中
- ✅ **版本控制友好** - 不需要跟踪 .xcodeproj 文件

只需要在 Xcode 中设置 `ENABLE_DEBUG_DYLIB = YES` 即可启用预览功能。

## 验证设置

设置完成后：

1. 打开任何 SwiftUI 视图文件（如 `ContentView.swift`）
2. 按 `⌥⌘↩︎` (Option+Command+Return) 打开预览
3. 如果看到预览界面，说明设置成功！

## 故障排除

如果预览仍然不工作：

1. **清理构建**: `Product → Clean Build Folder` (⇧⌘K)
2. **重启 Xcode**
3. **检查 Xcode 版本**: 需要 Xcode 14.0 或更高版本
4. **确认设置**: 在 Build Settings 中搜索 `ENABLE_DEBUG_DYLIB`，确认值为 `YES`（Debug 配置）

