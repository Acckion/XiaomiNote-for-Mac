# 实现计划：列表行间距修复

## 概述

修改原生编辑器中所有列表段落样式创建方法，添加行间距和段落间距设置，使列表项与普通正文保持一致的行间距。

## 任务

- [x] 1. 修改 ListFormatHandler.swift
  - [x] 1.1 添加行间距常量定义
    - 添加 `defaultLineSpacing = 4` 常量
    - 添加 `defaultParagraphSpacing = 8` 常量
    - _Requirements: 2.1, 2.2_
  - [x] 1.2 修改 createListParagraphStyle 方法
    - 在方法中添加 `style.lineSpacing = defaultLineSpacing`
    - 在方法中添加 `style.paragraphSpacing = defaultParagraphSpacing`
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 2. 修改 BlockFormatHandler.swift
  - [x] 2.1 添加行间距常量定义
    - 添加 `defaultLineSpacing = 4` 常量
    - 添加 `defaultParagraphSpacing = 8` 常量
    - _Requirements: 2.1, 2.2_
  - [x] 2.2 修改 createListParagraphStyle 方法
    - 在方法中添加 `style.lineSpacing = defaultLineSpacing`
    - 在方法中添加 `style.paragraphSpacing = defaultParagraphSpacing`
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 3. 修改 FormatManager.swift
  - [x] 3.1 添加行间距常量定义
    - 添加 `defaultLineSpacing = 4` 常量
    - 添加 `defaultParagraphSpacing = 8` 常量
    - _Requirements: 2.1, 2.2_
  - [x] 3.2 修改 createListParagraphStyle 方法
    - 在方法中添加 `style.lineSpacing = defaultLineSpacing`
    - 在方法中添加 `style.paragraphSpacing = defaultParagraphSpacing`
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 4. 修改 ListBehaviorHandler.swift
  - [x] 4.1 添加行间距常量定义
    - 添加 `defaultLineSpacing = 4` 常量
    - 添加 `defaultParagraphSpacing = 8` 常量
    - _Requirements: 2.1, 2.2_
  - [x] 4.2 修改段落样式创建代码
    - 在 `createListItemAttributedString` 方法中添加行间距设置
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 5. 检查点 - 确保编译通过
  - 运行 `xcodebuild` 确保所有修改编译通过
  - 如有问题请询问用户

- [ ]* 6. 编写属性测试
  - [ ]* 6.1 编写列表行间距属性测试
    - **Property 1: 列表段落样式行间距一致性**
    - **Validates: Requirements 1.1, 1.2, 1.3**
  - [ ]* 6.2 编写列表段落间距属性测试
    - **Property 2: 列表段落样式段落间距一致性**
    - **Validates: Requirements 1.4**
  - [ ]* 6.3 编写列表缩进计算属性测试
    - **Property 3: 列表缩进计算正确性**
    - **Validates: Requirements 3.1, 3.2, 3.3**

- [ ] 7. 最终检查点 - 确保所有测试通过
  - 运行测试套件确保所有测试通过
  - 如有问题请询问用户

## 备注

- 标记为 `*` 的任务是可选的，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- 检查点确保增量验证
