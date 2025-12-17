# 快速设置预览功能

## 最简单的方法

### 步骤 1：打开项目
1. 打开 Xcode
2. `File → Open...` (⌘O)
3. **选择 `Package.swift` 文件**（不是文件夹！）

### 步骤 2：找到设置位置

**方法 A：通过项目导航器**
1. 在左侧项目导航器中，点击最顶层的 **"MiNoteMac"**（包名）
2. 在右侧编辑器区域，你应该能看到几个标签页：
   - General
   - Signing & Capabilities  
   - **Build Settings** ← 点击这个
   - Build Phases
   - Build Rules

**方法 B：如果看不到标签页**
1. 在项目导航器中，找到 **"MiNoteMac"** 并展开
2. 找到 **"TARGETS"** 并展开
3. 选择 **"MiNoteMac"** 目标
4. 现在应该能看到标签页了

### 步骤 3：添加设置

1. 在 **Build Settings** 标签页中
2. 点击搜索框，输入 `ENABLE`
3. 如果看到 `ENABLE_DEBUG_DYLIB`，直接设置为 `YES`
4. 如果看不到，点击左上角的 **"+"** 按钮
5. 选择 **"Add User-Defined Setting"**
6. 输入：
   - 名称：`ENABLE_DEBUG_DYLIB`
   - 值：`YES`

### 步骤 4：验证

1. 打开 `Sources/MiNoteMac/View/ContentView.swift`
2. 按 `⌥⌘↩︎` 打开预览
3. 如果看到预览，说明成功了！

## 如果还是找不到

### 替代方法：使用 Scheme 设置

1. 在 Xcode 顶部工具栏，找到 scheme 选择器（显示 "MiNoteMac" 的地方）
2. 点击它，选择 **"Edit Scheme..."**
3. 在左侧选择 **"Run"**
4. 在右侧的 **"Info"** 标签页中
5. 确保 **"Build Configuration"** 是 **"Debug"**
6. 关闭对话框
7. 现在再尝试在 Build Settings 中查找

### 或者：直接搜索

1. 在 Xcode 中按 `⌘,` 打开 Preferences
2. 或者在任何地方按 `⌘⇧F` 打开全局搜索
3. 在 Build Settings 页面，使用搜索框输入 `DEBUG_DYLIB`
4. 如果找到，直接修改

## 需要帮助？

如果以上方法都不行，请检查：
- ✅ Xcode 版本 >= 14.0
- ✅ 确实打开了 `Package.swift` 文件（不是文件夹）
- ✅ 项目导航器已展开显示所有内容

