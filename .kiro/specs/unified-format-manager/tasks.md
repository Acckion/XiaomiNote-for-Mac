# 实现计划: 统一格式管理器

## 概述

本计划将实现 UnifiedFormatManager，整合原生编辑器中所有格式处理逻辑，确保格式应用、换行继承和 typingAttributes 同步使用统一的处理流程。

## 任务

- [x] 1. 创建 UnifiedFormatManager 基础结构
  - [x] 1.1 创建 UnifiedFormatManager.swift 文件
    - 创建单例类结构
    - 添加 textView 和 editorContext 弱引用属性
    - 实现 register 和 unregister 方法
    - _Requirements: 8.1, 8.2, 9.1_

  - [x] 1.2 创建 FormatCategory 枚举
    - 定义 inline、blockTitle、blockList、blockQuote、alignment 分类
    - 为 TextFormat 添加 category 计算属性
    - 为 TextFormat 添加 shouldInheritOnNewLine 计算属性
    - _Requirements: 3.1-3.6_

  - [x] 1.3 创建 NewLineContext 结构体
    - 定义 currentLineRange、currentBlockFormat、currentAlignment 属性
    - 定义 isListItemEmpty、shouldInheritFormat 属性
    - _Requirements: 8.3_

- [x] 2. 实现内联格式处理
  - [x] 2.1 创建 InlineFormatHandler 结构体
    - 实现 apply 方法，统一处理加粗、斜体、下划线、删除线、高亮
    - 实现字体特性处理（加粗、斜体）
    - 实现属性切换处理（下划线、删除线、高亮）
    - _Requirements: 1.1, 1.2, 1.3_

  - [x] 2.2 实现斜体 obliqueness 后备方案
    - 检测字体是否支持斜体
    - 不支持时使用 obliqueness 属性
    - _Requirements: 1.5_

  - [x] 2.3 实现多格式同时应用
    - 确保多个内联格式可以同时生效
    - 格式切换时保留其他已有格式
    - _Requirements: 1.4_

  - [ ]* 2.4 编写属性测试：多格式同时应用
    - **Property 7: 多格式同时应用**
    - **验证: 需求 1.4**

- [x] 3. 实现块级格式处理
  - [x] 3.1 创建 BlockFormatHandler 结构体
    - 实现 apply 方法，处理标题、列表、引用格式
    - 实现 detect 方法，检测当前行的块级格式
    - 实现 removeBlockFormat 方法，移除块级格式
    - _Requirements: 3.1-3.6_

  - [x] 3.2 实现块级格式互斥逻辑
    - 应用新块级格式时自动移除旧格式
    - 标题和列表互斥
    - _Requirements: 3.7_

  - [x] 3.3 实现空列表项检测
    - 检测列表项是否只包含列表符号
    - 支持有序列表、无序列表、Checkbox
    - _Requirements: 5.4, 5.5, 5.6_

  - [ ]* 3.4 编写属性测试：块级格式互斥
    - **Property 8: 块级格式互斥**
    - **验证: 需求 3.1-3.7**

- [x] 4. 实现换行处理
  - [x] 4.1 创建 NewLineHandler 结构体
    - 实现 handleNewLine 方法
    - 实现 shouldInheritFormat 方法
    - 实现 handleEmptyListItem 方法
    - _Requirements: 8.1, 8.3, 8.4_

  - [x] 4.2 实现内联格式换行清除
    - 换行时清除 typingAttributes 中的所有内联格式
    - 包括加粗、斜体、下划线、删除线、高亮
    - _Requirements: 2.1-2.6_

  - [ ]* 4.3 编写属性测试：内联格式换行清除
    - **Property 1: 内联格式换行清除**
    - **验证: 需求 2.1-2.6**

  - [x] 4.4 实现标题格式换行不继承
    - 标题行换行后新行变为普通正文
    - _Requirements: 4.1-4.4_

  - [ ]* 4.5 编写属性测试：标题格式换行清除
    - **Property 2: 标题格式换行清除**
    - **验证: 需求 4.1-4.4**

  - [x] 4.6 实现列表格式换行继承
    - 非空列表项换行后继承列表格式
    - 有序列表序号递增
    - _Requirements: 5.1-5.3_

  - [ ]* 4.7 编写属性测试：列表格式换行继承
    - **Property 3: 列表格式换行继承**
    - **验证: 需求 5.1-5.3**

  - [x] 4.8 实现空列表项回车取消格式
    - 空列表项回车变为普通正文
    - 不换行，只移除格式
    - _Requirements: 5.4-5.6_

  - [ ]* 4.9 编写属性测试：空列表项回车取消格式
    - **Property 4: 空列表项回车取消格式**
    - **验证: 需求 5.4-5.6**

  - [x] 4.10 实现引用格式换行继承
    - 引用块换行后继承引用格式
    - _Requirements: 6.1, 6.2_

  - [ ]* 4.11 编写属性测试：引用格式换行继承
    - **Property 5: 引用格式换行继承**
    - **验证: 需求 6.1, 6.2**

  - [x] 4.12 实现对齐属性换行继承
    - 换行后继承对齐属性
    - _Requirements: 7.1-7.3_

  - [ ]* 4.13 编写属性测试：对齐属性换行继承
    - **Property 6: 对齐属性换行继承**
    - **验证: 需求 7.1-7.3**

- [x] 5. 实现统一入口
  - [x] 5.1 实现 UnifiedFormatManager.applyFormat
    - 根据格式类型调用对应的处理器
    - 内联格式调用 InlineFormatHandler
    - 块级格式调用 BlockFormatHandler
    - _Requirements: 9.1, 9.5_

  - [x] 5.2 实现 UnifiedFormatManager.handleNewLine
    - 调用 NewLineHandler 处理换行
    - 返回是否已处理换行
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

  - [x] 5.3 实现 UnifiedFormatManager.syncTypingAttributes
    - 根据换行上下文设置 typingAttributes
    - 清除内联格式，保留需要继承的格式
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

  - [x] 5.4 实现 UnifiedFormatManager.detectFormatState
    - 检测光标位置的格式状态
    - 返回完整的 FormatState
    - _Requirements: 1.3_

- [x] 6. 集成到 NativeEditorView
  - [x] 6.1 修改 NativeTextView.keyDown 方法
    - 回车键调用 UnifiedFormatManager.handleNewLine
    - 根据返回值决定是否执行默认行为
    - _Requirements: 8.2_

  - [x] 6.2 修改格式应用调用
    - 工具栏格式应用调用 UnifiedFormatManager.applyFormat
    - 菜单格式应用调用 UnifiedFormatManager.applyFormat
    - 快捷键格式应用调用 UnifiedFormatManager.applyFormat
    - _Requirements: 9.2, 9.3, 9.4_

  - [x] 6.3 修改 CursorFormatManager 集成
    - 光标变化时调用 UnifiedFormatManager.detectFormatState
    - 格式切换时调用 UnifiedFormatManager.syncTypingAttributes
    - _Requirements: 10.2, 10.3_

- [x] 7. 清理旧代码
  - [x] 7.1 移除 NativeTextView 中的 clearHighlightFromTypingAttributes 方法
    - 该逻辑已整合到 UnifiedFormatManager
    - _Requirements: 2.5_

  - [x] 7.2 移除 Coordinator 中分散的格式处理逻辑
    - applyFontTrait 和 toggleAttribute 逻辑已整合
    - _Requirements: 1.1, 1.2_

- [x] 8. Checkpoint - 确保所有测试通过
  - 运行所有属性测试
  - 运行所有单元测试
  - 如有问题请询问用户

## 备注

- 标记 `*` 的任务为可选任务，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求，确保可追溯性
- Checkpoint 任务用于验证增量进度
- 属性测试验证通用正确性属性
- 单元测试验证具体示例和边界情况
