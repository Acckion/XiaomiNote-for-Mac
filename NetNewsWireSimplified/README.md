# NetNewsWire Simplified

这是一个基于NetNewsWire的自定义工具栏和三分栏视图的精简实现，专注于MacOS界面部分，移除了所有Service代码和业务逻辑依赖。

## 项目目标

1. **研究NetNewsWire的自定义工具栏实现** - 展示了如何创建自定义工具栏按钮、搜索框和系统工具栏项
2. **研究三分栏视图布局** - 实现了侧边栏、时间线列表和详情视图的三栏分割布局
3. **精简代码结构** - 移除了所有Service、网络、数据库等业务逻辑代码
4. **保持编译通过** - 确保项目可以正常编译和运行

## 项目结构

```
NetNewsWireSimplified/
├── Package.swift                    # Swift Package Manager配置文件
├── Sources/
│   ├── App.swift                    # 应用入口和AppDelegate
│   ├── NotesViewModel.swift         # 简化的视图模型，使用模拟数据
│   ├── MainWindowController.swift   # 主窗口控制器，包含工具栏实现
│   ├── SidebarViewController.swift  # 侧边栏视图控制器（第一栏）
│   ├── TimelineContainerViewController.swift # 时间线列表视图控制器（第二栏）
│   └── DetailViewController.swift   # 详情视图控制器（第三栏）
└── README.md
```

## 核心特性

### 1. 自定义工具栏
- 实现了完整的NSToolbarDelegate协议
- 支持自定义工具栏按钮（新建笔记、新建文件夹、刷新、星标等）
- 集成了系统搜索框（NSSearchToolbarItem）
- 支持工具栏项验证（NSUserInterfaceValidations）
- 工具栏支持用户自定义和自动保存配置

### 2. 三分栏视图
- 使用NSSplitViewController实现三栏布局
- 第一栏：侧边栏（文件夹列表），使用NSOutlineView
- 第二栏：时间线列表（笔记列表），使用NSTableView
- 第三栏：详情视图（笔记内容编辑），使用NSTextView
- 支持各栏的最小/最大宽度设置和折叠功能

### 3. 数据模型
- 简化的Folder和Note数据结构
- 使用Combine框架进行数据绑定
- 模拟数据用于演示界面交互
- 移除了所有网络、数据库、同步等复杂业务逻辑

### 4. 界面交互
- 侧边栏文件夹选择
- 时间线笔记选择
- 笔记内容编辑
- 工具栏按钮操作
- 搜索功能

## 编译和运行

```bash
# 进入项目目录
cd NetNewsWireSimplified

# 编译项目
swift build

# 运行应用
swift run
```

## 技术要点

### 工具栏实现
- 使用`NSToolbar(identifier:)`创建工具栏
- 实现`toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)`提供工具栏项
- 使用`NSSearchToolbarItem`集成搜索功能
- 实现`NSUserInterfaceValidations`进行工具栏项状态验证

### 三栏布局
- 使用`NSSplitViewController`作为窗口内容控制器
- 使用`NSSplitViewItem`配置各栏属性（最小/最大厚度、可折叠等）
- 侧边栏使用`sidebarWithViewController`初始化
- 时间线列表使用`contentListWithViewController`初始化

### 数据绑定
- 使用`@Published`属性包装器发布数据变化
- 使用Combine的`sink`订阅数据变化
- 在视图控制器中更新UI响应数据变化

## 与原始NetNewsWire的区别

1. **移除Service层**：删除了所有网络服务、数据库服务、同步服务等
2. **简化数据模型**：使用简单的内存数据结构替代复杂的Core Data模型
3. **移除业务逻辑**：只保留界面交互，移除所有业务规则和状态管理
4. **专注MacOS**：只保留MacOS相关代码，移除iOS、iPadOS等其他平台代码
5. **模拟数据**：使用硬编码的模拟数据替代真实数据源

## 学习价值

这个精简项目非常适合学习以下技术：
- macOS AppKit应用程序架构
- 自定义工具栏的实现
- 复杂窗口布局（三分栏视图）
- Combine数据绑定在AppKit中的应用
- 视图控制器之间的通信和数据传递

## 许可证

本项目基于NetNewsWire的开源代码进行精简，仅供学习和研究使用。
