# 实现计划：复选框列表支持

## 概述

本任务列表描述了在原生编辑器中实现复选框列表支持的步骤。复选框列表的核心逻辑复用现有的 `ListBehaviorHandler` 和 `ListFormatHandler`，主要工作是扩展 `ListFormatHandler` 以支持复选框格式的应用、切换和移除。

## 任务

- [x] 1. 扩展 ListFormatHandler 支持复选框列表
  - [x] 1.1 实现 applyCheckboxList 方法
    - 在行首插入 InteractiveCheckboxAttachment
    - 设置 listType 属性为 .checkbox
    - 设置 listIndent、checkboxLevel、checkboxChecked 属性
    - 设置正确的段落样式
    - 处理标题格式互斥
    - _Requirements: 1.1, 1.4, 1.5, 7.1, 7.3, 7.4_

  - [x] 1.2 实现 removeCheckboxList 方法
    - 查找并移除 InteractiveCheckboxAttachment
    - 移除列表相关属性
    - 重置段落样式
    - _Requirements: 1.2_

  - [x] 1.3 实现 toggleCheckboxList 方法
    - 检测当前行列表类型
    - 如果是复选框，调用 removeCheckboxList
    - 如果是其他列表，先移除再应用复选框
    - 如果不是列表，调用 applyCheckboxList
    - _Requirements: 1.2, 1.3_

  - [ ] 1.4 编写属性测试验证复选框格式应用
    - **Property 1: 复选框格式应用正确性**
    - **Validates: Requirements 1.1, 1.4, 1.5**

  - [ ]* 1.5 编写属性测试验证复选框列表切换
    - **Property 2: 复选框列表切换行为**
    - **Validates: Requirements 1.2, 1.3**

- [ ] 2. 检查点 - 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户

- [ ] 3. 验证 ListBehaviorHandler 对复选框的支持
  - [ ] 3.1 验证回车键处理支持复选框
    - 确认 handleEnterKey 正确处理 .checkbox 类型
    - 确认 createNewListItem 创建未勾选的新复选框
    - 确认空复选框回车取消格式
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [ ] 3.2 验证删除键处理支持复选框
    - 确认 handleBackspaceKey 正确处理复选框列表
    - 确认空复选框删除只移除标记
    - 确认有内容复选框删除合并到上一行
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [ ] 3.3 验证光标限制支持复选框
    - 确认 getContentStartPosition 正确识别 InteractiveCheckboxAttachment
    - 确认 isInListMarkerArea 正确检测复选框区域
    - 确认 adjustCursorPosition 正确调整光标
    - _Requirements: 4.1, 4.2_

  - [ ] 3.4 验证勾选状态切换
    - 确认 toggleCheckboxState 正确切换状态
    - 确认切换后光标位置不变
    - _Requirements: 5.1, 5.3_

  - [ ]* 3.5 编写属性测试验证回车键分割行为
    - **Property 3: 复选框回车键分割行为**
    - **Validates: Requirements 2.1, 2.2, 2.3**

  - [ ]* 3.6 编写属性测试验证空复选框回车取消
    - **Property 4: 空复选框回车键取消行为**
    - **Validates: Requirements 2.4, 2.5**

  - [ ]* 3.7 编写属性测试验证删除键行为
    - **Property 5: 复选框删除键行为**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4**

  - [ ]* 3.8 编写属性测试验证光标限制
    - **Property 6: 复选框光标限制**
    - **Validates: Requirements 4.1, 4.2**

  - [ ]* 3.9 编写属性测试验证勾选状态切换
    - **Property 7: 复选框勾选状态切换**
    - **Validates: Requirements 5.1, 5.3**

- [ ] 4. 检查点 - 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户

- [-] 5. 集成 FormatManager 和工具栏
  - [x] 5.1 更新 FormatManager.toggleCheckboxList 方法
    - 调用 ListFormatHandler.toggleCheckboxList
    - 确保与现有格式管理逻辑一致
    - _Requirements: 1.1, 1.2, 1.3_

  - [ ] 5.2 验证工具栏按钮集成
    - 确认 toggleCheckbox 正确调用 FormatManager
    - 确认按钮状态正确更新
    - _Requirements: 1.1_

- [ ] 6. 验证 XML 格式转换
  - [ ] 6.1 验证复选框 XML 解析
    - 确认 processCheckboxElementToNSAttributedString 创建正确的附件
    - 确认 indent、level、checked 属性正确解析
    - _Requirements: 6.1, 6.2_

  - [ ] 6.2 验证复选框 XML 导出
    - 确认 convertNSLineToXML 正确检测 InteractiveCheckboxAttachment
    - 确认生成正确的 XML 格式
    - 确认 checked 属性正确导出
    - _Requirements: 6.3, 6.4_

  - [ ]* 6.3 编写属性测试验证 XML Round Trip
    - **Property 8: 复选框 XML 解析导出 Round Trip**
    - **Validates: Requirements 6.1, 6.2, 6.3, 6.4**

- [ ] 7. 验证格式互斥
  - [ ] 7.1 验证复选框与标题互斥
    - 确认应用复选框到标题行时移除标题格式
    - 确认保留字体特性（加粗、斜体）
    - 确认使用正文字体大小
    - _Requirements: 7.1, 7.3, 7.4_

  - [ ] 7.2 验证标题与复选框互斥
    - 确认应用标题到复选框行时移除复选框格式
    - _Requirements: 7.2_

  - [ ]* 7.3 编写属性测试验证格式互斥
    - **Property 9: 复选框与标题互斥**
    - **Validates: Requirements 7.1, 7.3, 7.4**

- [ ] 8. 最终检查点 - 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户

## 注意事项

- 任务标记 `*` 的为可选任务（测试相关），可以跳过以加快 MVP 开发
- 每个任务引用具体的需求以便追溯
- 检查点确保增量验证
- 属性测试验证通用正确性属性
- 单元测试验证特定示例和边界情况
