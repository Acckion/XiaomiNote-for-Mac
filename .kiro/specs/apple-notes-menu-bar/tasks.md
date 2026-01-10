# 实现计划：Apple Notes 风格菜单栏

## 概述

重构小米笔记的菜单栏系统，按照 Apple Notes 标准实现完整的 macOS 原生菜单体验。优先使用 macOS 标准实现，避免重复造轮子。

## 任务

- [x] 1. 重构 MenuManager 基础架构
  - [x] 1.1 添加 MenuItemTag 枚举定义菜单项标签
    - 创建 `Sources/App/MenuItemTag.swift`
    - 定义段落样式、视图模式、切换状态等标签
    - _Requirements: 4.7, 8.3, 14.6, 14.7_
  - [x] 1.2 添加 MenuState 结构体管理菜单状态
    - 创建 `Sources/App/MenuState.swift`
    - 定义段落样式、视图模式、选中状态等属性
    - _Requirements: 14.4, 14.5, 14.6, 14.7_
  - [x] 1.3 重构 MenuManager 初始化和引用管理
    - 更新 `Sources/App/MenuManager.swift`
    - 添加 MenuState 属性
    - _Requirements: 1.1-1.9_

- [x] 2. 实现应用程序菜单
  - [x] 2.1 重写 setupAppMenu 方法
    - 添加"关于小米笔记"菜单项
    - 添加"设置..."菜单项（⌘,）
    - 添加"隐藏小米笔记"（⌘H）、"隐藏其他"（⌥⌘H）、"全部显示"
    - 添加"退出小米笔记"（⌘Q）
    - 使用标准 NSApplication 选择器
    - _Requirements: 1.1-1.9_

- [x] 3. 实现文件菜单
  - [x] 3.1 重写 setupFileMenu 方法 - 新建和共享部分
    - 添加"新建笔记"（⌘N）、"新建文件夹"（⇧⌘N）、"新建智能文件夹"
    - 添加"共享"菜单项
    - 添加"关闭"（⌘W）使用 `performClose:`
    - _Requirements: 2.1-2.7_
  - [x] 3.2 实现导入导出子菜单
    - 添加"导入至笔记..."、"导入 Markdown..."
    - 创建"导出为"子菜单（PDF、Markdown、纯文本）
    - _Requirements: 2.9-2.14_
  - [x] 3.3 实现笔记操作菜单项
    - 添加"置顶笔记"、"添加到私密笔记"（待实现）、"复制笔记"
    - 添加"打印..."（⌘P）使用 `print:`
    - _Requirements: 2.15-2.19_
  - [ ]* 3.4 编写文件菜单单元测试
    - 验证菜单项存在和顺序
    - 验证快捷键配置
    - _Requirements: 2.1-2.20_

- [x] 4. 实现编辑菜单（使用标准选择器）
  - [x] 4.1 重写 setupEditMenu 方法 - 基础编辑操作
    - 使用 `Selector("undo:")` 和 `Selector("redo:")`
    - 使用 `#selector(NSText.cut(_:))`、`copy(_:)`、`paste(_:)`、`delete(_:)`、`selectAll(_:)`
    - _Requirements: 3.1-3.11_
  - [x] 4.2 实现查找子菜单
    - 创建 createFindSubmenu 方法
    - 使用 `performFindPanelAction:` 和 NSTextFinder.Action 标签
    - 添加"查找..."（⌘F）、"查找下一个"（⌘G）、"查找上一个"（⇧⌘G）、"查找并替换..."（⌥⌘F）
    - _Requirements: 3.17-3.22_
  - [x] 4.3 添加附件和文本处理菜单项
    - 添加"附加文件..."、"添加链接..."（⌘K）
    - 添加"拼写和语法"、"替换"、"转换"、"语音"子菜单（系统标准）
    - 添加"开始听写"、"表情与符号"（⌃⌘空格）
    - _Requirements: 3.12-3.16, 3.23-3.29_
  - [x] 4.4 为所有菜单项添加 SF Symbols 图标
    - 添加 setMenuItemIcon 辅助方法
    - 为应用程序菜单、文件菜单、编辑菜单、格式菜单、视图菜单、帮助菜单添加图标
    - 图标大小 16x16 像素
    - _Requirements: 16.1-16.4_
  - [ ]* 4.5 编写编辑菜单单元测试
    - 验证标准选择器正确绑定
    - 验证查找菜单项使用正确的 NSTextFinder.Action
    - _Requirements: 3.1-3.29_

- [x] 5. 实现格式菜单
  - [x] 5.1 实现段落样式菜单项
    - 添加"标题"、"小标题"、"副标题"、"正文"、"有序列表"、"无序列表"
    - 设置 MenuItemTag 标签支持单选勾选
    - 添加"块引用"菜单项
    - _Requirements: 4.1-4.9_
  - [x] 5.2 实现核对清单子菜单
    - 添加"核对清单"、"标记为已勾选"
    - 创建"更多"子菜单（全部勾选、全部取消勾选、移到底部、删除已勾选）
    - 创建"移动项目"子菜单（向上、向下）
    - _Requirements: 5.1-5.11_
  - [x] 5.3 实现字体和外观菜单项
    - 添加"使用浅色背景显示笔记"（勾选状态）
    - 创建"字体"子菜单（粗体⌘B、斜体⌘I、下划线⌘U、删除线、高亮）
    - _Requirements: 6.1-6.9_
  - [x] 5.4 实现文本对齐和缩进子菜单
    - 创建"文本"子菜单（左对齐、居中、右对齐）
    - 创建"缩进"子菜单（增大⌘]、减小⌘[）
    - _Requirements: 7.1-7.7_
  - [ ]* 5.5 编写段落样式互斥选择属性测试
    - **Property 2: 段落样式互斥选择**
    - **Validates: Requirements 4.7, 14.6**

- [x] 6. 实现显示菜单 ✅ (已提交: 14d6636)
  - [x] 6.1 实现视图模式菜单项 ✅
    - 添加"列表视图"、"画廊视图"（单选勾选）
    - 设置 MenuItemTag 标签
    - _Requirements: 8.1-8.5_
  - [x] 6.2 实现文件夹和笔记数量控制 ✅
    - 添加"隐藏文件夹"、"显示笔记数量"（勾选状态）
    - 添加"附件视图"、"显示附件浏览器"、"在笔记中显示"（待实现标记）
    - _Requirements: 9.1-9.8_
  - [x] 6.3 实现缩放和区域折叠控制 ✅
    - 添加"放大"（⌘+）、"缩小"（⌘-）、"实际大小"（⌘0）
    - 添加"展开区域"、"展开所有区域"、"折叠区域"、"折叠所有区域"
    - _Requirements: 10.1-10.4, 11.1-11.5_
  - [x] 6.4 实现工具栏控制（使用标准选择器） ✅
    - 添加"隐藏工具栏"使用 `toggleToolbarShown:`
    - 添加"自定义工具栏..."使用 `runToolbarCustomizationPalette:`
    - 添加"进入全屏幕"（⌃⌘F）使用 `toggleFullScreen:`
    - _Requirements: 12.1-12.4_
  - [ ]* 6.5 编写视图模式互斥选择属性测试
    - **Property 3: 视图模式互斥选择**
    - **Validates: Requirements 8.3, 14.7**

- [x] 7. 实现窗口菜单（使用系统管理）
  - [x] 7.1 重写 setupWindowMenu 方法
    - 添加"最小化"（⌘M）使用 `performMiniaturize:`
    - 添加"缩放"使用 `performZoom:`
    - 添加"填充"、"居中"
    - 使用 `NSApp.windowsMenu = windowMenu` 注册系统窗口菜单
    - _Requirements: 13.1-13.6_
  - [x] 7.2 添加窗口布局和自定义操作
    - 添加"移动与调整大小"、"全屏幕平铺"子菜单（系统标准）
    - 添加"在新窗口中打开笔记"
    - 添加"前置全部窗口"使用 `arrangeInFront:`
    - _Requirements: 13.7-13.14_

- [x] 8. 实现 MenuActionHandler 扩展
  - [x] 8.1 实现 NSMenuItemValidation 协议
    - 添加 validateMenuItem 方法
    - 根据 MenuItemTag 和 MenuState 返回正确的启用状态
    - _Requirements: 14.1-14.8_
  - [x] 8.2 实现文件菜单动作
    - 实现 createSmartFolder、importMarkdown、exportAsPDF、exportAsMarkdown、exportAsPlainText
    - 实现 addToPrivateNotes（待实现标记）、duplicateNote
    - _Requirements: 2.3, 2.10, 2.12-2.17_
  - [x] 8.3 实现格式菜单动作
    - 实现 setHeading、setSubheading、setSubtitle、setBodyText
    - 实现 toggleOrderedList、toggleUnorderedList、toggleBlockQuote
    - 实现核对清单相关动作
    - 实现 toggleLightBackground、toggleHighlight
    - _Requirements: 4.1-4.9, 5.1-5.11, 6.1-6.9_
  - [x] 8.4 实现显示菜单动作
    - 实现 setListView、setGalleryView
    - 实现 toggleFolderVisibility、toggleNoteCount
    - 实现 zoomIn、zoomOut、actualSize
    - 实现区域折叠相关动作
    - _Requirements: 8.1-8.5, 9.2-9.3, 10.2-10.4, 11.2-11.5_
  - [x] 8.5 实现窗口菜单动作
    - 实现 openNoteInNewWindow
    - _Requirements: 13.10_
  - [ ]* 8.6 编写笔记选中状态与菜单启用状态同步属性测试
    - **Property 1: 笔记选中状态与菜单启用状态同步**
    - **Validates: Requirements 2.20, 14.4**
  - [ ]* 8.7 编写编辑器焦点与格式菜单启用状态同步属性测试
    - **Property 4: 编辑器焦点与格式菜单启用状态同步**
    - **Validates: Requirements 14.5**

- [x] 9. 菜单状态同步集成
  - [x] 9.1 集成 MenuState 与 NotesViewModel
    - 监听笔记选中状态变化
    - 监听视图模式变化
    - 更新 MenuState 并触发菜单刷新
    - _Requirements: 14.4, 14.7_
  - [x] 9.2 集成 MenuState 与编辑器
    - 监听编辑器焦点变化
    - 监听段落样式变化
    - 更新 MenuState 并触发菜单刷新
    - _Requirements: 14.5, 14.6_

- [x] 10. 最终验证和清理
  - [ ]* 10.1 编写快捷键唯一性属性测试
    - **Property 5: 快捷键唯一性**
    - **Validates: Requirements 15.4**
  - [x] 10.2 清理旧的菜单代码
    - 移除不再使用的菜单动作
    - 更新 AppDelegate 中的菜单相关代码
    - _Requirements: 15.1-15.3_
  - [x] 10.3 Checkpoint - 确保所有测试通过
    - 运行所有单元测试和属性测试
    - 如有问题请询问用户

## 备注

- 标记为 `*` 的任务是可选的，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- Checkpoint 任务用于确保增量验证
- 属性测试验证通用正确性属性
- 单元测试验证具体示例和边界情况
