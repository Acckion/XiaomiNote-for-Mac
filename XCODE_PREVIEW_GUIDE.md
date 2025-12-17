# Xcode 预览指南

## 设置 ENABLE_DEBUG_DYLIB

要在Xcode中预览SwiftUI视图，需要为可执行目标设置ENABLE_DEBUG_DYLIB构建设置：

### 方法1：使用Xcode构建设置
1. 在Xcode中，选择项目导航器中的"MiNoteMac"包
2. 选择"MiNoteMac"目标
3. 转到"Build Settings"标签页
4. 搜索"ENABLE_DEBUG_DYLIB"
5. 如果没有找到，点击"+"按钮添加用户定义的构建设置
6. 设置键为`ENABLE_DEBUG_DYLIB`，值为`YES`

### 方法2：使用配置文件（推荐）
1. 我已经创建了`Debug.xcconfig`文件
2. 在Xcode中，选择"MiNoteMac"目标
3. 转到"Build Settings"标签页
4. 找到"Based on Configuration File"设置
5. 为Debug配置选择`Debug.xcconfig`

## 预览UI界面

### 步骤1：打开预览画布
1. 在Xcode中打开任何SwiftUI视图文件（如ContentView.swift、NotesListView.swift等）
2. 点击编辑器右上角的"Adjust Editor Options"按钮（看起来像三个水平线）
3. 选择"Canvas"或使用快捷键`⌥⌘↩︎`（Option+Command+Return）

### 步骤2：启用预览
1. 如果预览显示"Preview update paused"，点击"Resume"按钮
2. 如果显示"ENABLE_DEBUG_DYLIB"错误，请按照上述步骤设置构建设置

### 步骤3：查看不同视图的预览
- **ContentView.swift**: 主应用程序的三栏布局预览
- **NotesListView.swift**: 笔记列表预览
- **NoteDetailView.swift**: 笔记编辑器预览
- **NewNoteView.swift**: 新建笔记表单预览
- **LoginView.swift**: 登录界面预览
- **SettingsView.swift**: 设置界面预览

## 应用程序架构

### UI设计标准
- 使用macOS 26设计标准（与Apple备忘录应用一致）
- 三栏布局：侧边栏（文件夹）、内容列表（笔记）、详情编辑器
- 使用NavigationSplitView实现响应式布局
- 支持暗色模式和系统外观

### 数据模型
- **Note.swift**: 笔记数据模型，直接使用小米笔记API格式
- **Folder.swift**: 文件夹数据模型
- 避免不必要的格式转换，保持与小米笔记API的一致性

### 网络服务
- **MiNoteService.swift**: 移植自TypeScript的小米笔记API
- 支持异步网络请求
- 使用WebKit进行OAuth登录

### 视图模型
- **NotesViewModel.swift**: 使用@MainActor确保UI更新在主线程
- 管理应用程序状态和业务逻辑

## 测试功能

### 已实现的功能
1. ✅ 完整的项目计划和架构设计
2. ✅ 与macOS备忘录一致的UI界面
3. ✅ 从云端拉取部分代码（MiNoteService.swift）
4. ✅ 初步的文件编辑代码（NoteDetailView.swift）
5. ✅ 三栏导航布局
6. ✅ 笔记创建、编辑、删除功能
7. ✅ 收藏/取消收藏功能
8. ✅ 搜索和过滤功能
9. ✅ 登录界面（WebView）
10. ✅ 设置界面

### 待测试的功能
1. 实际连接小米笔记API
2. 同步功能测试
3. 文件存储和本地缓存
4. 离线模式支持

## 运行应用程序

### 在Xcode中运行
1. 选择"MiNoteMac"方案
2. 点击运行按钮（▶️）或按`⌘R`
3. 应用程序将启动并显示登录界面（如果未认证）

### 命令行运行
```bash
cd SwiftUI-MiNote-for-Mac
swift run
```

## 故障排除

### 常见问题
1. **预览不工作**: 确保ENABLE_DEBUG_DYLIB设置为YES
2. **编译错误**: 清理构建文件夹（Product → Clean Build Folder）
3. **登录问题**: 检查网络连接和小米账号凭证
4. **UI布局问题**: 确保使用macOS 14或更高版本

### 重置预览
如果预览卡住或显示错误：
1. 关闭预览画布
2. 清理构建文件夹（`⇧⌘K`）
3. 重新打开预览画布

## 下一步开发

根据原始需求，已完成：
- [x] 完成整个项目的计划
- [x] 做出大体框架和UI界面
- [x] 写出从云端拉取部分代码
- [x] 写出初步的文件编辑代码

下一步建议：
1. 测试与小米笔记API的实际连接
2. 实现完整的同步功能
3. 添加本地文件存储
4. 优化性能和用户体验
5. 添加单元测试和UI测试
