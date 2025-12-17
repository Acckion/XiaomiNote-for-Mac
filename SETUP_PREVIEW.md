# 设置 Xcode 预览功能 - 详细步骤

## 问题
在 Xcode 中打开 Package.swift 后，找不到 "MiNoteMac" 目标来设置 `ENABLE_DEBUG_DYLIB`。

## 解决方案

### 方法 1：通过项目导航器设置（推荐）

1. **打开 Package.swift**
   - 在 Xcode 中选择 `File → Open...`
   - 选择项目根目录的 `Package.swift` 文件

2. **找到目标设置**
   - 在左侧项目导航器中，找到 **"MiNoteMac"**（包名，显示为文件夹图标）
   - 点击展开，你会看到：
     - **Products**（产品）
     - **Sources**（源代码）
     - **TARGETS**（目标）← 这里！

3. **展开 TARGETS**
   - 点击 **"TARGETS"** 旁边的三角形展开
   - 你会看到 **"MiNoteMac"** 目标

4. **选择目标并打开 Build Settings**
   - 点击 **"MiNoteMac"** 目标
   - 在右侧编辑器区域，点击 **"Build Settings"** 标签页
   - 如果看不到标签页，确保编辑器区域已展开

5. **添加用户定义的设置**
   - 在 Build Settings 页面，点击左上角的 **"+"** 按钮
   - 选择 **"Add User-Defined Setting"**
   - 输入：
     - **名称**: `ENABLE_DEBUG_DYLIB`
     - **值**: `YES`
   - 确保在 **Debug** 配置下设置为 `YES`

### 方法 2：使用搜索框快速定位

1. **打开 Build Settings**
   - 在项目导航器中，选择 **"MiNoteMac"** 包（最顶层）
   - 在右侧编辑器区域，确保显示的是项目设置
   - 如果没有看到设置，尝试双击 **"MiNoteMac"** 包名

2. **搜索设置**
   - 在 Build Settings 页面的搜索框中输入 `ENABLE`
   - 如果已存在，直接修改为 `YES`
   - 如果不存在，使用 **"+"** 按钮添加

### 方法 3：如果仍然找不到目标

如果上述方法都不行，尝试：

1. **确保正确打开项目**
   - 关闭当前窗口
   - 重新打开：`File → Open...` → 选择 `Package.swift`
   - 不要选择整个文件夹，只选择 `Package.swift` 文件

2. **检查 Xcode 版本**
   - 需要 Xcode 14.0 或更高版本
   - 检查：`Xcode → About Xcode`

3. **使用替代方法：编辑 scheme**
   - 在 Xcode 顶部工具栏，点击 scheme 选择器（显示 "MiNoteMac" 的地方）
   - 选择 **"Edit Scheme..."**
   - 在左侧选择 **"Run"**
   - 在右侧选择 **"Info"** 标签页
   - 在 "Build Configuration" 中选择 **"Debug"**
   - 然后回到 Build Settings 页面

### 方法 4：使用配置文件（临时方案）

如果 Xcode 界面操作困难，可以尝试：

1. **创建或编辑 `.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata`**
   - 这个文件可能不存在，需要手动创建

2. **或者使用命令行设置**（需要 Xcode 项目文件）
   - 如果生成了 `.xcodeproj`，可以使用命令行工具设置

## 验证设置

设置完成后：

1. **清理构建**
   - `Product → Clean Build Folder` (⇧⌘K)

2. **测试预览**
   - 打开 `Sources/MiNoteMac/View/ContentView.swift`
   - 按 `⌥⌘↩︎` (Option+Command+Return) 打开预览
   - 如果看到预览界面，说明设置成功！

## 常见问题

### Q: 项目导航器中看不到 TARGETS
**A**: 确保你打开的是 `Package.swift` 文件，而不是整个文件夹。如果还是看不到，尝试：
- 关闭并重新打开 Xcode
- 确保 Xcode 版本 >= 14.0

### Q: Build Settings 标签页在哪里？
**A**: 
- 在右侧编辑器区域的顶部
- 如果看不到，尝试调整窗口大小或使用 `View → Show Toolbar`

### Q: 添加设置后仍然无法预览
**A**: 
1. 确认设置的值是 `YES`（不是 `yes` 或 `true`）
2. 确认是在 **Debug** 配置下
3. 清理构建文件夹（⇧⌘K）
4. 重启 Xcode

## 截图说明（文字描述）

项目导航器应该显示：
```
📦 MiNoteMac
  ├── 📁 Products
  │   └── MiNoteMac (可执行文件)
  ├── 📁 Sources
  │   └── 📁 MiNoteMac
  └── 📁 TARGETS  ← 点击这里展开
      └── MiNoteMac  ← 选择这个目标
```

选择目标后，右侧应该显示：
```
[General] [Signing & Capabilities] [Build Settings] [Build Phases] [Build Rules]
                                      ↑
                              点击这个标签页
```

