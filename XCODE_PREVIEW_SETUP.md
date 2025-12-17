# Xcode 预览设置指南

## 问题

如果看到错误："The executable target "MiNoteMac" needs the build setting "ENABLE_DEBUG_DYLIB" set to "YES" in order to preview."

## 解决方案

### 方法 1：

在 Xcode 中手动设置（推荐）

1. **打开项目**

   - 在 Xcode 中，选择 `File → Open...`
   - 选择 `Package.swift` 文件（不是整个文件夹）
   - 点击 "Open"

2. **设置构建设置**

   **步骤 A：找到目标**

   - 在左侧项目导航器中，找到 **"MiNoteMac"**（最顶层的包名）
   - 点击展开，你会看到：
     - Products
     - Sources
     - **TARGETS** ← 点击这个展开
   - 展开 TARGETS 后，选择 **"MiNoteMac"** 目标

   **如果看不到 TARGETS：**

   - 尝试双击项目导航器中的 **"MiNoteMac"** 包名（最顶层）
   - 或者直接点击项目导航器中的 **"MiNoteMac"**，然后在右侧编辑器区域查看

   **步骤 B：打开 Build Settings**

   - 选择目标后，在右侧编辑器区域顶部，点击 **"Build Settings"** 标签页
   - 如果看不到标签页，确保编辑器区域已展开（可能需要调整窗口大小）

   **步骤 C：添加设置**

   - 在 Build Settings 页面的搜索框中输入 `ENABLE_DEBUG_DYLIB`
   - 如果已存在，直接修改为 `YES`
   - 如果不存在，点击左上角的 **"+"** 按钮，选择 **"Add User-Defined Setting"**
   - 设置：
     - **名称**: `ENABLE_DEBUG_DYLIB`
     - **值**: `YES`
   - 确保在 **Debug** 配置下设置为 `YES`

3. **验证设置**
   - 确保 "Show" 下拉菜单选择 "All" 或 "Customized"
   - 确认 `ENABLE_DEBUG_DYLIB` 显示为 `YES`（Debug 配置）

### 方法 2：使用配置文件

项目已经包含 `Debug.xcconfig` 文件，但需要在 Xcode 中关联：

1. 在 Xcode 中选择 "MiNoteMac" 目标
2. 转到 "Build Settings" 标签页
3. 搜索 "Configuration File" 或 "Based on Configuration File"
4. 为 Debug 配置选择 `Debug.xcconfig`

### 方法 3：使用命令行（临时方案）

如果上述方法不起作用，可以尝试：

```bash
# 清理构建
swift package clean

# 在 Xcode 中重新打开 Package.swift
```

## 验证预览是否工作

1. 打开任何 SwiftUI 视图文件（如 `ContentView.swift`）
2. 按 `⌥⌘↩︎` (Option+Command+Return) 打开预览画布
3. 如果看到预览，说明设置成功
4. 如果仍然看到错误，请检查：
   - Xcode 版本是否支持（需要 Xcode 14+）
   - 是否选择了正确的目标
   - 构建设置是否正确保存

## 注意事项

- 这个设置只影响 Xcode 预览功能，不影响实际编译
- 如果使用命令行编译（`swift build`），不需要这个设置
- 某些情况下，需要重启 Xcode 才能生效
