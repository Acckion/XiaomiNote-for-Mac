# RichTextKit 新增功能测试说明

## 测试应用位置

已创建两个测试方式：

### 方式 1：独立测试应用
文件：`RichTextKitAttachmentTestApp.swift`

这是一个独立的 SwiftUI 应用，可以直接运行。

**运行方法：**
1. 在 Xcode 中打开项目
2. 创建一个新的 Target（如果需要）
3. 将 `RichTextKitAttachmentTestApp.swift` 添加到项目中
4. 运行应用

### 方式 2：在 Demo 应用中测试
文件：`RichTextKit-1.2/Demo/Demo/AttachmentFeaturesDemo.swift`

已集成到 RichTextKit 的 Demo 应用中。

**运行方法：**
1. 打开 `RichTextKit-1.2/Demo/Demo.xcodeproj`
2. 运行 Demo 应用
3. 在菜单栏选择 "RichTextKit" > "测试新增功能"

## 测试功能

### 1. 待办复选框（Checkbox）
- ✅ 点击工具栏的复选框按钮插入
- ✅ 点击复选框可以切换选中/未选中状态
- ✅ 深色模式下显示为白色
- ✅ 支持存档/解档

### 2. 分割线（Horizontal Rule）
- ✅ 点击工具栏的分割线按钮插入
- ✅ 高度自动匹配正文行高
- ✅ 填满整个宽度
- ✅ 深色模式下显示为白色

### 3. 引用块（Block Quote）
- ✅ 点击工具栏的引用块按钮插入
- ✅ 左侧显示竖线指示器
- ✅ 自动应用左侧缩进
- ✅ 支持自定义颜色

## 测试步骤

1. **测试复选框：**
   - 点击复选框按钮插入
   - 点击已插入的复选框，观察状态切换
   - 切换到深色模式，检查是否为白色

2. **测试分割线：**
   - 点击分割线按钮插入
   - 检查高度是否与正文行高一致
   - 检查是否填满宽度

3. **测试引用块：**
   - 选中一段文本
   - 点击引用块按钮
   - 检查左侧是否有竖线和缩进

## 注意事项

- 所有新功能都使用 `archivedData` 格式保存，支持图片附件
- 复选框的点击功能通过 `trackMouse` 方法实现
- 分割线高度通过 `cellFrame` 方法动态计算
- 引用块样式通过段落样式和附件组合实现

