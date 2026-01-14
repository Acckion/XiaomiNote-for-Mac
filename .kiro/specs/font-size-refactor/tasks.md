# Implementation Plan: Font Size Refactor

## Overview

本实现计划将字体大小管理系统重构为统一的 FontSizeManager，确保所有组件使用一致的字体大小常量和检测逻辑。

## Tasks

- [x] 1. 创建 FontSizeManager 核心组件
  - [x] 1.1 创建 `Sources/View/NativeEditor/Format/FontSizeManager.swift` 文件
    - 定义字体大小常量：H1=23, H2=20, H3=17, Body=14
    - 实现 `fontSize(for:)` 方法
    - 实现 `detectParagraphFormat(fontSize:)` 方法
    - 实现 `detectHeadingLevel(fontSize:)` 方法
    - 实现 `createFont(for:traits:)` 方法
    - 实现 `createFont(ofSize:traits:)` 方法
    - 实现 `defaultFont` 计算属性
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 6.1, 6.2, 6.3, 6.4, 6.5_

- [x] 2. 修改核心格式管理组件
  - [x] 2.1 修改 `FormatManager.swift`
    - 将 `heading1Size`, `heading2Size`, `heading3Size` 改为计算属性
    - 将 `defaultFont` 改为计算属性
    - 修改 `applyHeadingStyle` 方法使用 `.regular` 字重
    - 修改 `applyHeading1/2/3` 方法移除 weight 参数
    - 修改 `getHeadingLevel` 方法使用 FontSizeManager
    - _Requirements: 2.1, 2.2, 2.3, 4.1, 4.2, 4.3, 4.4_

  - [x] 2.2 修改 `FormatAttributesBuilder.swift`
    - 将 `heading1FontSize`, `heading2FontSize`, `heading3FontSize`, `bodyFontSize` 改为计算属性
    - 将 `defaultFont` 改为计算属性
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 2.3 修改 `BlockFormatHandler.swift`
    - 将 `heading1Size`, `heading2Size`, `heading3Size`, `bodyFontSize` 改为计算属性
    - 更新 `defaultFont` 为 14pt
    - 修改 `applyHeadingFormat` 方法使用 `.regular` 字重
    - _Requirements: 2.1, 2.2, 2.3, 5.1, 5.2_

- [x] 3. 修改格式检测组件
  - [x] 3.1 修改 `NativeEditorContext.swift`
    - 修改 `resetFontSizeToBody` 方法使用 FontSizeManager
    - 修改 `detectFontFormats` 方法使用 FontSizeManager 的检测逻辑
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 6.2, 6.3, 6.4, 6.5_

  - [x] 3.2 修改 `NativeFormatProvider.swift`
    - 修改 `detectParagraphFormat` 方法使用 FontSizeManager
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 3.3 修改 `MixedFormatStateHandler.swift`
    - 修改字体大小检测逻辑使用 FontSizeManager
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 3.4 修改 `CrossParagraphFormatHandler.swift`
    - 修改标题字体大小获取使用 FontSizeManager
    - _Requirements: 4.1, 4.2, 4.3_

- [x] 4. 修改 XML 转换组件
  - [x] 4.1 修改 `XiaoMiFormatConverter.swift`
    - 修改 `processRichTextTags` 中的标签映射使用 FontSizeManager
    - 修改 `processNSAttributesToXMLTags` 中的标题检测使用 FontSizeManager
    - 移除标题的加粗字重
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_

  - [x] 4.2 修改 `ASTToAttributedStringConverter.swift`
    - 修改默认字体使用 FontSizeManager
    - 修改 `attributesForFormat` 方法使用 FontSizeManager
    - 移除标题的加粗字重
    - _Requirements: 7.4, 7.5, 7.6_

  - [x] 4.3 修改 `AttributedStringToASTConverter.swift`
    - 修改标题检测逻辑使用 FontSizeManager
    - _Requirements: 7.1, 7.2, 7.3_

- [x] 5. 修改其他格式处理组件
  - [x] 5.1 修改 `NewLineHandler.swift`
    - 更新 `defaultFont` 为 14pt
    - _Requirements: 8.1, 8.3_

  - [x] 5.2 修改 `InlineFormatHandler.swift`
    - 更新 `defaultFont` 为 14pt
    - _Requirements: 4.5_

  - [x] 5.3 修改 `MixedFormatApplicationHandler.swift`
    - 修改默认字体使用 FontSizeManager
    - _Requirements: 4.5_

  - [x] 5.4 修改 `NativeEditorView.swift`
    - 修改默认字体为 14pt
    - 修改列表项字体大小为 14pt
    - _Requirements: 5.1, 5.2_

  - [x] 5.5 修改 `PerformanceOptimizer.swift`
    - 修改预加载字体使用 FontSizeManager
    - 修改默认字体设置为 14pt
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 6. Checkpoint - 编译验证
  - [x] 确保所有修改后项目可以正常编译
  - [x] 检查是否有遗漏的字体大小硬编码
  - [x] 移除 Native Editor 中的 headingLevel 属性依赖
    - NativeEditorContext.detectFontFormats() 现在只使用 FontSizeManager 检测
    - FormatManager.applyHeadingStyle() 不再设置 headingLevel 属性
    - BlockFormatHandler.detectHeadingLevel() 只使用字体大小检测
    - CursorFormatManager 使用 FontSizeManager.detectParagraphFormat()
  - [x] Web Editor 的 headingLevel 保持不变（JavaScript 编辑器的正常工作方式）

- [ ]* 7. 编写单元测试
  - [ ]* 7.1 创建 `FontSizeManagerTests.swift`
    - 测试字体大小常量值
    - 测试 `fontSize(for:)` 方法
    - 测试 `detectParagraphFormat(fontSize:)` 方法
    - 测试 `createFont(for:traits:)` 方法
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 6.2, 6.3, 6.4, 6.5_

  - [ ]* 7.2 更新现有测试文件
    - 更新 `FormatApplicationPropertyTests.swift` 中的字体大小期望值
    - 更新 `FormatStateDetectionPropertyTests.swift` 中的检测阈值
    - 更新 `XiaoMiFormatConverterTests.swift` 中的字体大小期望值
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 7.1, 7.2, 7.3_

- [ ]* 8. 编写属性测试
  - [ ]* 8.1 编写标题格式字重属性测试
    - **Property 1: Heading format uses regular weight**
    - **Validates: Requirements 2.1, 2.2, 2.3**

  - [ ]* 8.2 编写格式检测一致性属性测试
    - **Property 3: Format detection consistency**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4**

  - [ ]* 8.3 编写行级字体大小统一性属性测试
    - **Property 6: Line font size uniformity invariant**
    - **Validates: Requirements 5.3**

  - [ ]* 8.4 编写 XML 往返属性测试
    - **Property 10: XML round-trip consistency**
    - **Validates: Requirements 7.7**

- [ ] 9. Final Checkpoint - 测试验证
  - 运行所有测试确保通过
  - 手动测试格式菜单功能
  - 如有问题请询问用户

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases

