# 实现计划：笔记列表视图功能扩展

## 概述

本实现计划将笔记列表视图功能扩展分解为可执行的编码任务，包括视图选项管理、工具栏按钮、画廊视图和展开视图的实现。

## 任务

- [x] 1. 实现视图选项状态管理
  - [x] 1.1 创建 ViewMode 枚举和 ViewOptionsState 结构体
    - 在 `Sources/ViewModel/` 目录下创建 `ViewOptionsState.swift`
    - 定义 `ViewMode` 枚举（list, gallery）
    - 定义 `ViewOptionsState` 结构体，包含 sortOrder、sortDirection、isDateGroupingEnabled、viewMode
    - 实现 Codable 协议以支持持久化
    - 添加 displayName 和 icon 扩展属性
    - _Requirements: 4.2, 4.3_

  - [x] 1.2 创建 ViewOptionsManager 管理器
    - 在 `Sources/ViewModel/` 目录下创建 `ViewOptionsManager.swift`
    - 实现单例模式
    - 实现 UserDefaults 持久化逻辑
    - 实现 setSortOrder、setSortDirection、toggleDateGrouping、setViewMode 方法
    - _Requirements: 2.9, 3.6, 4.7_

  - [ ]* 1.3 编写设置持久化属性测试
    - **Property 2: 设置持久化往返**
    - **验证: 需求 2.9, 3.6, 4.7**

- [x] 2. 实现视图选项菜单
  - [x] 2.1 创建 MenuItemButton 组件
    - 在 `Sources/View/SwiftUIViews/` 目录下创建 `ViewOptionsMenuView.swift`
    - 实现可复用的菜单项按钮组件
    - 支持标题、图标、选中状态显示
    - _Requirements: 2.4, 2.8, 3.5, 4.6_

  - [x] 2.2 实现 ViewOptionsMenuView 视图
    - 实现排序方式部分（编辑时间、创建时间、标题）
    - 实现排序方向部分（升序、降序）
    - 实现日期分组开关
    - 实现视图模式选择（列表视图、画廊视图）
    - 添加分隔线
    - _Requirements: 2.1, 2.2, 2.6, 3.2, 4.2_

- [x] 3. 实现工具栏视图选项按钮
  - [x] 3.1 添加工具栏按钮标识符
    - 在 `Sources/Window/ToolbarIdentifiers.swift` 中添加 `.viewOptions` 标识符
    - _Requirements: 1.1_

  - [x] 3.2 实现工具栏按钮和 Popover
    - 在 `MainWindowController.swift` 中添加视图选项按钮
    - 实现点击显示 Popover 菜单
    - 实现点击外部关闭菜单
    - _Requirements: 1.2, 1.3, 1.4_

  - [x] 3.3 更新 MainWindowToolbarDelegate
    - 在 `Sources/ToolbarItem/MainWindowToolbarDelegate.swift` 中添加视图选项按钮支持
    - _Requirements: 1.1_

- [ ] 4. 检查点 - 确保视图选项功能正常
  - 确保所有测试通过，如有问题请询问用户

- [x] 5. 更新 NotesListView 支持日期分组开关
  - [x] 5.1 集成 ViewOptionsManager
    - 在 `NotesListView.swift` 中添加 `@ObservedObject var optionsManager: ViewOptionsManager`
    - 根据 `isDateGroupingEnabled` 切换分组/平铺显示
    - _Requirements: 3.3, 3.4_

  - [ ]* 5.2 编写日期分组正确性属性测试
    - **Property 3: 日期分组正确性**
    - **验证: 需求 3.3**

  - [ ]* 5.3 编写排序一致性属性测试
    - **Property 1: 排序一致性**
    - **验证: 需求 2.3, 2.7**

- [ ] 6. 实现笔记卡片视图
  - [ ] 6.1 创建 NoteCardView 组件
    - 在 `Sources/View/SwiftUIViews/` 目录下创建 `NoteCardView.swift`
    - 实现标题、内容预览、日期显示
    - 实现缩略图加载和显示
    - 实现锁定图标显示
    - 实现悬停效果和预加载
    - _Requirements: 5.2, 5.3, 5.4, 7.2, 7.3_

  - [ ]* 6.2 编写卡片内容完整性属性测试
    - **Property 4: 卡片内容完整性**
    - **验证: 需求 5.2**

- [ ] 7. 实现画廊视图
  - [ ] 7.1 创建 GalleryView 组件
    - 在 `Sources/View/SwiftUIViews/` 目录下创建 `GalleryView.swift`
    - 实现响应式网格布局
    - 实现平铺和分组两种显示模式
    - 实现滚动和键盘导航
    - _Requirements: 5.1, 5.5, 5.7, 5.8, 5.9, 7.4_

  - [ ]* 7.2 编写视图状态一致性属性测试
    - **Property 5: 视图状态一致性**
    - **验证: 需求 5.8, 8.1, 8.3, 8.4, 8.5**

- [ ] 8. 实现展开笔记视图
  - [ ] 8.1 创建 ExpandedNoteView 组件
    - 在 `Sources/View/SwiftUIViews/` 目录下创建 `ExpandedNoteView.swift`
    - 实现返回按钮
    - 集成 NoteDetailView
    - 实现 Escape 键返回
    - _Requirements: 6.2, 6.3, 7.5_

  - [ ] 8.2 实现展开/收起动画
    - 使用 matchedGeometryEffect 实现平滑过渡
    - 设置 easeInOut 动画时长 350ms
    - _Requirements: 6.1, 6.4, 6.5_

  - [ ]* 8.3 编写选择状态同步属性测试
    - **Property 6: 选择状态同步**
    - **验证: 需求 6.6**

- [ ] 9. 检查点 - 确保画廊视图功能正常
  - 确保所有测试通过，如有问题请询问用户

- [ ] 10. 实现内容区域视图切换
  - [ ] 10.1 创建 ContentAreaView 组件
    - 在 `Sources/View/SwiftUIViews/` 目录下创建 `ContentAreaView.swift`
    - 根据 viewMode 切换列表模式和画廊模式
    - 管理 expandedNote 状态
    - _Requirements: 4.3, 4.4, 4.5_

  - [ ] 10.2 更新 MainWindowController 集成 ContentAreaView
    - 修改 `setupWindowContent()` 方法
    - 将笔记列表和详情区域替换为 ContentAreaView
    - _Requirements: 4.3, 4.4, 4.5_

- [ ] 11. 实现右键菜单和状态同步
  - [ ] 11.1 为 NoteCardView 添加右键菜单
    - 复用 NotesListView 中的 noteContextMenu
    - _Requirements: 7.1_

  - [ ] 11.2 实现状态同步
    - 确保文件夹切换时画廊视图更新
    - 确保搜索时画廊视图过滤
    - 确保笔记变更时画廊视图刷新
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

  - [ ]* 11.3 编写数据变更反映属性测试
    - **Property 7: 数据变更反映**
    - **验证: 需求 8.2**

- [ ] 12. 最终检查点 - 确保所有功能正常
  - 确保所有测试通过，如有问题请询问用户

## 备注

- 标记为 `*` 的任务是可选的测试任务，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以确保可追溯性
- 检查点用于确保增量验证
- 属性测试验证通用正确性属性

