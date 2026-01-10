# 需求文档

## 简介

按照 Apple Notes 的标准重构小米笔记的菜单栏系统，提供完整、专业的 macOS 原生菜单体验。菜单栏将包含应用程序菜单、文件菜单、编辑菜单、格式菜单、显示菜单和窗口菜单，涵盖笔记管理、编辑、格式化和视图控制等核心功能。

## 设计原则

1. **优先使用 macOS 标准实现**：对于编辑菜单（剪切/复制/粘贴/撤销/重做）、查找功能、窗口菜单等，使用 AppKit 提供的标准选择器和系统管理功能，避免重复造轮子
2. **利用响应链机制**：使用 `#selector(NSText.cut(_:))` 等标准选择器，让系统自动路由到响应链中的正确响应者
3. **使用系统窗口菜单管理**：通过 `NSApp.setWindowsMenu()` 让系统自动管理窗口列表
4. **使用标准查找面板**：通过 `performFindPanelAction()` 和 `NSTextFinder.Action` 实现标准查找功能

## 术语表

- **Menu_System**: 应用程序的菜单栏系统，负责管理所有菜单项和子菜单
- **Menu_Item**: 单个菜单项，可以是动作项、分隔线或子菜单容器
- **Submenu**: 包含多个菜单项的子菜单
- **Keyboard_Shortcut**: 菜单项的快捷键组合
- **Menu_State**: 菜单项的状态（启用/禁用、勾选/未勾选）
- **Note_Editor**: 笔记编辑器组件
- **View_Mode**: 视图模式（列表视图或画廊视图）
- **Checklist**: 核对清单/待办事项列表
- **Block_Quote**: 块引用格式

## 需求

### 需求 1：应用程序菜单（小米笔记）

**用户故事：** 作为用户，我希望通过应用程序菜单访问关于、设置、窗口控制和退出功能，以便管理应用程序。

#### 验收标准

1. THE Menu_System SHALL 显示"关于小米笔记"菜单项
2. THE Menu_System SHALL 在"关于"项后显示分隔线
3. THE Menu_System SHALL 显示"设置..."菜单项，快捷键为 ⌘,
4. THE Menu_System SHALL 在"设置"项后显示分隔线
5. THE Menu_System SHALL 显示"隐藏小米笔记"菜单项，快捷键为 ⌘H
6. THE Menu_System SHALL 显示"隐藏其他"菜单项，快捷键为 ⌥⌘H
7. THE Menu_System SHALL 显示"全部显示"菜单项
8. THE Menu_System SHALL 在窗口控制项后显示分隔线
9. THE Menu_System SHALL 显示"退出小米笔记"菜单项，快捷键为 ⌘Q

### 需求 2：文件菜单

**用户故事：** 作为用户，我希望通过文件菜单创建、导入、导出和管理笔记，以便高效组织我的内容。

#### 验收标准

1. THE Menu_System SHALL 显示"新建笔记"菜单项，快捷键为 ⌘N
2. THE Menu_System SHALL 显示"新建文件夹"菜单项，快捷键为 ⇧⌘N
3. THE Menu_System SHALL 显示"新建智能文件夹"菜单项
4. THE Menu_System SHALL 在新建项后显示分隔线
5. THE Menu_System SHALL 显示"共享"菜单项
6. THE Menu_System SHALL 在"共享"项后显示分隔线
7. THE Menu_System SHALL 显示"关闭"菜单项，快捷键为 ⌘W
8. THE Menu_System SHALL 在"关闭"项后显示分隔线
9. THE Menu_System SHALL 显示"导入至笔记..."菜单项
10. THE Menu_System SHALL 显示"导入 Markdown..."菜单项
11. THE Menu_System SHALL 在导入项后显示分隔线
12. THE Menu_System SHALL 显示"导出为"子菜单
13. THE Menu_System SHALL 在"导出为"子菜单中包含 PDF、Markdown、纯文本等格式选项
14. THE Menu_System SHALL 在导出项后显示分隔线
15. THE Menu_System SHALL 显示"置顶笔记"菜单项
16. THE Menu_System SHALL 显示"添加到私密笔记"菜单项
17. THE Menu_System SHALL 显示"复制笔记"菜单项
18. THE Menu_System SHALL 在笔记操作项后显示分隔线
19. THE Menu_System SHALL 显示"打印..."菜单项，快捷键为 ⌘P
20. WHEN 没有选中笔记时 THE Menu_System SHALL 禁用笔记相关操作菜单项

### 需求 3：编辑菜单（使用 macOS 标准实现）

**用户故事：** 作为用户，我希望通过编辑菜单执行撤销、剪切、复制、粘贴、查找等操作，以便高效编辑笔记内容。

#### 验收标准

**基础编辑操作（使用标准 NSResponder 选择器）：**
1. THE Menu_System SHALL 显示"撤销"菜单项，使用 `Selector("undo:")` 和快捷键 ⌘Z
2. THE Menu_System SHALL 显示"重做"菜单项，使用 `Selector("redo:")` 和快捷键 ⇧⌘Z
3. THE Menu_System SHALL 在撤销/重做项后显示分隔线
4. THE Menu_System SHALL 显示"剪切"菜单项，使用 `#selector(NSText.cut(_:))` 和快捷键 ⌘X
5. THE Menu_System SHALL 显示"拷贝"菜单项，使用 `#selector(NSText.copy(_:))` 和快捷键 ⌘C
6. THE Menu_System SHALL 显示"粘贴"菜单项，使用 `#selector(NSText.paste(_:))` 和快捷键 ⌘V
7. THE Menu_System SHALL 显示"粘贴并匹配样式"菜单项（待实现标记）
8. THE Menu_System SHALL 显示"粘贴并保留样式"菜单项（待实现标记）
9. THE Menu_System SHALL 显示"删除"菜单项，使用 `#selector(NSText.delete(_:))`
10. THE Menu_System SHALL 显示"全选"菜单项，使用 `#selector(NSText.selectAll(_:))` 和快捷键 ⌘A
11. THE Menu_System SHALL 在基础编辑项后显示分隔线

**附件操作：**
12. THE Menu_System SHALL 显示"附加文件..."菜单项
13. THE Menu_System SHALL 显示"添加链接..."菜单项
14. THE Menu_System SHALL 显示"录音..."菜单项（待实现标记）
15. THE Menu_System SHALL 显示"重命名附件..."菜单项（待实现标记）
16. THE Menu_System SHALL 在附件项后显示分隔线

**查找功能（使用标准 NSTextFinder）：**
17. THE Menu_System SHALL 显示"查找"子菜单
18. THE Menu_System SHALL 使用 `performFindPanelAction:` 和 `NSTextFinder.Action` 实现查找功能
19. THE Menu_System SHALL 在"查找"子菜单中包含"查找..."（⌘F，使用 `.showFindInterface`）
20. THE Menu_System SHALL 在"查找"子菜单中包含"查找下一个"（⌘G，使用 `.nextMatch`）
21. THE Menu_System SHALL 在"查找"子菜单中包含"查找上一个"（⇧⌘G，使用 `.previousMatch`）
22. THE Menu_System SHALL 在"查找"子菜单中包含"查找并替换..."（⌥⌘F，使用 `.showReplaceInterface`）

**文本处理（使用系统标准功能）：**
23. THE Menu_System SHALL 显示"拼写和语法"子菜单，使用系统标准实现
24. THE Menu_System SHALL 显示"替换"子菜单，使用系统标准实现
25. THE Menu_System SHALL 显示"转换"子菜单，使用系统标准实现
26. THE Menu_System SHALL 显示"语音"子菜单，使用系统标准实现
27. THE Menu_System SHALL 在文本处理项后显示分隔线
28. THE Menu_System SHALL 显示"开始听写"菜单项，使用 `NSApplication.shared.startDictation(_:)`
29. THE Menu_System SHALL 显示"表情与符号"菜单项，使用 `NSApplication.shared.orderFrontCharacterPalette(_:)` 和快捷键 ⌃⌘空格

### 需求 4：格式菜单 - 段落样式

**用户故事：** 作为用户，我希望通过格式菜单设置段落样式（标题、正文、列表等），以便组织笔记结构。

#### 验收标准

1. THE Menu_System SHALL 显示"标题"菜单项，支持单选勾选状态
2. THE Menu_System SHALL 显示"小标题"菜单项，支持单选勾选状态
3. THE Menu_System SHALL 显示"副标题"菜单项，支持单选勾选状态
4. THE Menu_System SHALL 显示"正文"菜单项，支持单选勾选状态
5. THE Menu_System SHALL 显示"有序列表"菜单项，支持单选勾选状态
6. THE Menu_System SHALL 显示"无序列表"菜单项，支持单选勾选状态
7. WHEN 用户选择一种段落样式时 THE Menu_System SHALL 在该项显示勾选标记，其他样式项取消勾选
8. THE Menu_System SHALL 在段落样式项后显示分隔线
9. THE Menu_System SHALL 显示"块引用"菜单项

### 需求 5：格式菜单 - 核对清单

**用户故事：** 作为用户，我希望通过格式菜单管理核对清单，以便跟踪待办事项。

#### 验收标准

1. THE Menu_System SHALL 显示"核对清单"菜单项
2. THE Menu_System SHALL 显示"标记为已勾选"菜单项
3. THE Menu_System SHALL 显示"更多"子菜单
4. THE Menu_System SHALL 在"更多"子菜单中显示"全部勾选"菜单项
5. THE Menu_System SHALL 在"更多"子菜单中显示"全部取消勾选"菜单项
6. THE Menu_System SHALL 在"更多"子菜单中显示"将勾选的项目移到底部"菜单项
7. THE Menu_System SHALL 在"更多"子菜单中显示"删除已勾选项目"菜单项
8. THE Menu_System SHALL 在核对清单项后显示分隔线
9. THE Menu_System SHALL 显示"移动项目"子菜单
10. THE Menu_System SHALL 在"移动项目"子菜单中显示"向上"菜单项
11. THE Menu_System SHALL 在"移动项目"子菜单中显示"向下"菜单项

### 需求 6：格式菜单 - 外观和字体

**用户故事：** 作为用户，我希望通过格式菜单设置笔记外观和字体样式，以便自定义笔记显示效果。

#### 验收标准

1. THE Menu_System SHALL 在移动项目后显示分隔线
2. THE Menu_System SHALL 显示"使用浅色背景显示笔记"菜单项，支持勾选状态
3. THE Menu_System SHALL 在外观项后显示分隔线
4. THE Menu_System SHALL 显示"字体"子菜单
5. THE Menu_System SHALL 在"字体"子菜单中显示"粗体"菜单项，快捷键为 ⌘B
6. THE Menu_System SHALL 在"字体"子菜单中显示"斜体"菜单项，快捷键为 ⌘I
7. THE Menu_System SHALL 在"字体"子菜单中显示"下划线"菜单项，快捷键为 ⌘U
8. THE Menu_System SHALL 在"字体"子菜单中显示"删除线"菜单项
9. THE Menu_System SHALL 在"字体"子菜单中显示"高亮"菜单项

### 需求 7：格式菜单 - 文本对齐和缩进

**用户故事：** 作为用户，我希望通过格式菜单设置文本对齐方式和缩进，以便调整笔记排版。

#### 验收标准

1. THE Menu_System SHALL 显示"文本"子菜单
2. THE Menu_System SHALL 在"文本"子菜单中显示"左对齐"菜单项
3. THE Menu_System SHALL 在"文本"子菜单中显示"居中"菜单项
4. THE Menu_System SHALL 在"文本"子菜单中显示"右对齐"菜单项
5. THE Menu_System SHALL 显示"缩进"子菜单
6. THE Menu_System SHALL 在"缩进"子菜单中显示"增大"菜单项，快捷键为 ⌘]
7. THE Menu_System SHALL 在"缩进"子菜单中显示"减小"菜单项，快捷键为 ⌘[

### 需求 8：显示菜单 - 视图模式

**用户故事：** 作为用户，我希望通过显示菜单切换视图模式，以便选择最适合的笔记浏览方式。

#### 验收标准

1. THE Menu_System SHALL 显示"列表视图"菜单项，支持单选勾选状态
2. THE Menu_System SHALL 显示"画廊视图"菜单项，支持单选勾选状态
3. WHEN 用户选择一种视图模式时 THE Menu_System SHALL 在该项显示勾选标记，另一项取消勾选
4. THE Menu_System SHALL 在视图模式项后显示分隔线
5. THE Menu_System SHALL 显示"最近笔记"菜单项（待实现标记）

### 需求 9：显示菜单 - 文件夹和笔记数量

**用户故事：** 作为用户，我希望通过显示菜单控制文件夹和笔记数量的显示，以便自定义界面。

#### 验收标准

1. THE Menu_System SHALL 在"最近笔记"项后显示分隔线
2. THE Menu_System SHALL 显示"隐藏文件夹"菜单项，支持切换状态
3. THE Menu_System SHALL 显示"显示/隐藏笔记数量"菜单项，支持切换状态
4. THE Menu_System SHALL 在文件夹控制项后显示分隔线
5. THE Menu_System SHALL 显示"附件视图"菜单项（待实现标记）
6. THE Menu_System SHALL 在附件视图项后显示分隔线
7. THE Menu_System SHALL 显示"显示附件浏览器"菜单项（待实现标记）
8. THE Menu_System SHALL 显示"在笔记中显示"菜单项（待实现标记）

### 需求 10：显示菜单 - 缩放控制

**用户故事：** 作为用户，我希望通过显示菜单控制视图缩放，以便调整显示大小。

#### 验收标准

1. THE Menu_System SHALL 在附件相关项后显示分隔线
2. THE Menu_System SHALL 显示"放大"菜单项，快捷键为 ⌘+
3. THE Menu_System SHALL 显示"缩小"菜单项，快捷键为 ⌘-
4. THE Menu_System SHALL 显示"实际大小"菜单项，快捷键为 ⌘0

### 需求 11：显示菜单 - 区域折叠

**用户故事：** 作为用户，我希望通过显示菜单控制区域的展开和折叠，以便管理界面布局。

#### 验收标准

1. THE Menu_System SHALL 在缩放控制项后显示分隔线
2. THE Menu_System SHALL 显示"展开区域"菜单项
3. THE Menu_System SHALL 显示"展开所有区域"菜单项
4. THE Menu_System SHALL 显示"折叠区域"菜单项
5. THE Menu_System SHALL 显示"折叠所有区域"菜单项

### 需求 12：显示菜单 - 工具栏控制（使用 macOS 标准实现）

**用户故事：** 作为用户，我希望通过显示菜单控制工具栏的显示和自定义，以便个性化界面。

#### 验收标准

1. THE Menu_System SHALL 在区域折叠项后显示分隔线
2. THE Menu_System SHALL 显示"隐藏工具栏"菜单项，使用 `#selector(NSWindow.toggleToolbarShown(_:))` 实现切换
3. THE Menu_System SHALL 显示"自定义工具栏..."菜单项，使用 `#selector(NSWindow.runToolbarCustomizationPalette(_:))`
4. THE Menu_System SHALL 显示"进入全屏幕"菜单项，使用 `#selector(NSWindow.toggleFullScreen(_:))` 和快捷键 ⌃⌘F

### 需求 13：窗口菜单（使用 macOS 标准实现）

**用户故事：** 作为用户，我希望通过窗口菜单管理应用程序窗口，以便高效组织工作空间。

#### 验收标准

**使用系统窗口菜单管理：**
1. THE Menu_System SHALL 通过 `NSApp.windowsMenu = windowMenu` 注册窗口菜单，让系统自动管理窗口列表
2. THE Menu_System SHALL 显示"最小化"菜单项，使用 `#selector(NSWindow.performMiniaturize(_:))` 和快捷键 ⌘M
3. THE Menu_System SHALL 显示"缩放"菜单项，使用 `#selector(NSWindow.performZoom(_:))`
4. THE Menu_System SHALL 显示"填充"菜单项
5. THE Menu_System SHALL 显示"居中"菜单项，使用 `#selector(NSWindow.center)`
6. THE Menu_System SHALL 在基础窗口控制项后显示分隔线

**窗口布局（使用系统标准功能）：**
7. THE Menu_System SHALL 显示"移动与调整大小"子菜单，使用系统标准实现
8. THE Menu_System SHALL 显示"全屏幕平铺"子菜单，使用系统标准实现
9. THE Menu_System SHALL 在窗口布局项后显示分隔线

**自定义窗口操作：**
10. THE Menu_System SHALL 显示"在新窗口中打开笔记"菜单项
11. THE Menu_System SHALL 在窗口操作项后显示分隔线

**系统自动管理的窗口列表：**
12. THE Menu_System SHALL 让系统自动在窗口菜单中添加和管理打开的窗口列表
13. THE Menu_System SHALL 在窗口列表项后显示分隔线
14. THE Menu_System SHALL 显示"前置全部窗口"菜单项，使用 `#selector(NSApplication.arrangeInFront(_:))`

### 需求 14：菜单状态管理（利用响应链自动管理）

**用户故事：** 作为用户，我希望菜单项能够根据当前上下文正确显示启用/禁用状态，以便了解哪些操作可用。

#### 验收标准

**利用 AppKit 自动菜单启用机制：**
1. THE Menu_System SHALL 启用 `NSMenu.autoenablesItems` 让系统自动管理标准编辑菜单项的启用状态
2. THE Menu_System SHALL 利用响应链机制自动禁用没有响应者的菜单项（如剪切、复制、粘贴）
3. THE Menu_System SHALL 利用 `UndoManager` 自动管理撤销/重做菜单项的启用状态

**自定义菜单项状态管理：**
4. WHEN 没有选中笔记时 THE Menu_System SHALL 禁用"导出为"、"置顶笔记"、"复制笔记"、"打印"等笔记操作菜单项
5. WHEN 编辑器没有焦点时 THE Menu_System SHALL 禁用格式相关菜单项
6. THE Menu_System SHALL 根据当前段落样式更新段落样式菜单项的勾选状态
7. THE Menu_System SHALL 根据当前视图模式更新视图模式菜单项的勾选状态
8. THE Menu_System SHALL 实现 `NSMenuItemValidation` 协议来管理自定义菜单项的启用状态

### 需求 15：快捷键一致性

**用户故事：** 作为用户，我希望菜单快捷键与 macOS 标准和 Apple Notes 保持一致，以便使用熟悉的操作方式。

#### 验收标准

1. THE Menu_System SHALL 为所有标准操作使用 macOS 标准快捷键
2. THE Menu_System SHALL 在菜单项右侧显示对应的快捷键符号
3. THE Menu_System SHALL 确保快捷键不与系统快捷键冲突
4. THE Menu_System SHALL 确保同一快捷键不被多个菜单项使用

### 需求 16：菜单项图标

**用户故事：** 作为用户，我希望菜单项带有图标，以便快速识别菜单功能。

#### 验收标准

1. THE Menu_System SHALL 为所有菜单项设置 SF Symbols 图标
2. THE Menu_System SHALL 使用与功能语义相符的图标
3. THE Menu_System SHALL 设置图标大小为 16x16 像素
4. THE Menu_System SHALL 确保图标在浅色和深色模式下都清晰可见
