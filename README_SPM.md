# Swift Package Manager 项目说明

## 重要说明

**Swift Package Manager (SPM) 项目不使用 `.xcodeproj` 或 `.xcworkspace` 文件。**

SPM 项目依赖于：
- ✅ **文件夹结构** - 标准的 `Sources/` 目录结构
- ✅ **Package.swift** - 软件包清单文件，包含所有配置
- ❌ **不需要** `.xcodeproj` 或 `.xcworkspace`

## 项目结构

```
SwiftUI-MiNote-for-Mac/
├── Package.swift          # 软件包清单（主要配置文件）
├── Sources/
│   └── MiNoteMac/        # 可执行目标
│       ├── App.swift
│       ├── View/
│       ├── Model/
│       ├── ViewModel/
│       └── Service/
└── README.md
```

## 在 Xcode 中打开项目

### 正确方式：打开 Package.swift

1. **打开 Xcode**
2. **选择 `File → Open...`**（或按 `⌘O`）
3. **选择项目根目录的 `Package.swift` 文件**
4. **点击 "Open"**

Xcode 会自动识别为 Swift Package，你可以：
- ✅ 编辑代码
- ✅ 使用预览功能（需要设置 ENABLE_DEBUG_DYLIB）
- ✅ 运行和调试（`⌘R`）
- ✅ 运行测试（`⌘U`）

### 设置预览功能

打开 Package.swift 后，需要手动设置 `ENABLE_DEBUG_DYLIB`：

1. 在项目导航器中，选择 **"MiNoteMac"** 包
2. 选择 **"MiNoteMac"** 目标（在 TARGETS 下）
3. 点击 **"Build Settings"** 标签页
4. 点击左上角的 **"+"** 按钮，选择 **"Add User-Defined Setting"**
5. 设置：
   - **键名**: `ENABLE_DEBUG_DYLIB`
   - **值**: `YES`
   - 确保在 **Debug** 配置下设置为 `YES`

## Package.swift 说明

当前的 `Package.swift` 配置：

```swift
let package = Package(
    name: "MiNoteMac",                    // 包名
    platforms: [.macOS(.v14)],           // 平台要求
    products: [
        .executable(name: "MiNoteMac", targets: ["MiNoteMac"])  // 可执行产品
    ],
    targets: [
        .executableTarget(                // 可执行目标
            name: "MiNoteMac",
            path: "Sources/MiNoteMac"     // 源代码路径
        ),
    ]
)
```

## 命令行使用

### 构建项目

```bash
# Debug 构建
swift build

# Release 构建
swift build -c release
```

### 运行项目

```bash
# 运行 Debug 版本
swift run

# 运行 Release 版本
swift run -c release
```

### 运行测试

```bash
swift test
```

## 关于 .xcodeproj 文件

**注意**: 项目中包含 `project.yml` 文件，这是用于 XcodeGen 工具的配置文件。

**只有在以下情况下才需要生成 .xcodeproj：**
- 需要使用某些仅支持 .xcodeproj 的 CI/CD 工具
- 需要使用某些第三方工具或插件
- 团队有特殊的工作流程要求

**对于日常开发，推荐直接打开 Package.swift**，因为：
- ✅ 更简单，无需额外工具
- ✅ 保持 SPM 项目的原生结构
- ✅ 支持所有 Xcode 功能
- ✅ 更容易维护和版本控制

## 验证设置

设置完成后：

1. 打开任何 SwiftUI 视图文件（如 `ContentView.swift`）
2. 按 `⌥⌘↩︎` (Option+Command+Return) 打开预览
3. 如果看到预览界面，说明设置成功！

## 故障排除

### 预览不工作

1. **确认设置**: 在 Build Settings 中搜索 `ENABLE_DEBUG_DYLIB`，确认值为 `YES`（Debug 配置）
2. **清理构建**: `Product → Clean Build Folder` (⇧⌘K)
3. **重启 Xcode**
4. **检查 Xcode 版本**: 需要 Xcode 14.0 或更高版本

### 其他问题

- **编译错误**: 清理构建文件夹（`Product → Clean Build Folder`）
- **找不到文件**: 确保文件在 `Sources/MiNoteMac/` 目录下
- **依赖问题**: 检查 `Package.swift` 中的 `dependencies` 配置

