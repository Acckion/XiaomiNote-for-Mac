# 实现计划：列表缩进对齐优化

## 概述

优化有序列表和无序列表的显示效果，调整列表附件尺寸和渲染位置，使列表标记与普通正文左边缘对齐。

## 任务

- [x] 1. 优化 BulletAttachment 渲染
  - [x] 1.1 调整 BulletAttachment 的 attachmentWidth 从 20pt 到 16pt
    - 修改 `Sources/View/NativeEditor/Attachment/CustomAttachments.swift`
    - 更新 `attachmentWidth` 属性默认值
    - _Requirements: 1.1, 4.1_
  - [x] 1.2 修改项目符号渲染位置为左对齐
    - 修改 `createBulletImage()` 方法中的 bulletX 计算
    - 将符号从居中改为左对齐（x = 2 或小值）
    - _Requirements: 1.1, 1.4_
  - [x] 1.3 调整 attachmentBounds 返回值
    - 确保 x 坐标基于缩进级别正确计算
    - _Requirements: 3.1, 3.2_

- [x] 2. 优化 OrderAttachment 渲染
  - [x] 2.1 调整 OrderAttachment 的 attachmentWidth 从 24pt 到 20pt
    - 修改 `Sources/View/NativeEditor/Attachment/CustomAttachments.swift`
    - 更新 `attachmentWidth` 属性默认值
    - _Requirements: 1.2, 4.2_
  - [x] 2.2 修改编号渲染位置为左对齐
    - 修改 `createOrderImage()` 方法中的 textX 计算
    - 将编号从右对齐改为左对齐（x = 2 或小值）
    - _Requirements: 1.2, 1.4_
  - [x] 2.3 调整 attachmentBounds 返回值
    - 确保 x 坐标基于缩进级别正确计算
    - _Requirements: 3.1, 3.2_

- [ ] 3. 优化 InteractiveCheckboxAttachment 渲染
  - [ ] 3.1 调整复选框附件的宽度和位置
    - 修改 `Sources/View/NativeEditor/Attachment/CustomAttachments.swift`
    - 确保复选框左对齐渲染
    - _Requirements: 1.3, 1.4_

- [ ] 4. 更新 ListFormatHandler 常量
  - [ ] 4.1 更新列表宽度常量
    - 修改 `Sources/View/NativeEditor/Format/ListFormatHandler.swift`
    - 更新 `bulletWidth` 从 24pt 到 16pt
    - 更新 `orderNumberWidth` 从 28pt 到 20pt
    - 更新 `checkboxWidth` 从 24pt 到 18pt
    - _Requirements: 2.2, 4.1, 4.2_
  - [ ] 4.2 验证 createListParagraphStyle 方法
    - 确保 firstLineHeadIndent 和 headIndent 计算正确
    - _Requirements: 2.1, 2.2, 2.3_

- [ ] 5. 检查点 - 验证基本功能
  - 确保所有修改编译通过
  - 手动测试列表显示效果
  - 确保列表标记与正文左边缘对齐

- [ ]* 6. 编写属性测试
  - [ ]* 6.1 编写列表标记位置对齐属性测试
    - **Property 1: 列表标记位置对齐**
    - **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 3.1, 3.2**
  - [ ]* 6.2 编写悬挂缩进正确性属性测试
    - **Property 2: 悬挂缩进正确性**
    - **Validates: Requirements 2.1, 2.2, 2.3**
  - [ ]* 6.3 编写附件尺寸合理性属性测试
    - **Property 3: 附件尺寸合理性**
    - **Validates: Requirements 4.1, 4.2, 4.3**
  - [ ]* 6.4 编写间距一致性属性测试
    - **Property 4: 间距一致性**
    - **Validates: Requirements 5.3**

- [ ] 7. 最终检查点
  - 确保所有测试通过
  - 验证不同缩进级别的列表显示正确
  - 如有问题请询问用户

## 备注

- 标记为 `*` 的任务是可选的，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- 检查点用于确保增量验证
