# Implementation Plan: XML-AttributedString 双向转换器

## Overview

基于 AST 的小米笔记 XML 与 NSAttributedString 双向转换器实现。采用 Node + Mark 分离的设计，通过扁平化格式跨度解决格式边界问题。

## Tasks

- [x] 1. 定义 AST 节点数据模型
  - [x] 1.1 创建 AST 节点协议和类型枚举
    - 创建 `Sources/Service/Editor/AST/ASTNode.swift`
    - 定义 `ASTNode` 协议、`ASTNodeType` 枚举
    - 定义块级节点协议 `BlockNode` 和行内节点协议 `InlineNode`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 2.1-2.10_

  - [x] 1.2 实现块级节点类型
    - 创建 `Sources/Service/Editor/AST/BlockNodes.swift`
    - 实现 `DocumentNode`, `TextBlockNode`, `BulletListNode`, `OrderedListNode`
    - 实现 `CheckboxNode`, `HorizontalRuleNode`, `ImageNode`, `AudioNode`, `QuoteNode`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8_

  - [x] 1.3 实现行内节点类型
    - 创建 `Sources/Service/Editor/AST/InlineNodes.swift`
    - 实现 `TextNode`, `FormattedNode`
    - _Requirements: 2.1-2.11_

- [x] 2. 实现 XML 解析器
  - [x] 2.1 实现 XML 词法分析器（Tokenizer）
    - 创建 `Sources/Service/Editor/Parser/XMLTokenizer.swift`
    - 实现标签识别、属性提取、文本内容提取
    - 实现 XML 实体解码（`&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;`）
    - _Requirements: 2.12_

  - [x] 2.2 实现块级元素解析
    - 创建 `Sources/Service/Editor/Parser/XMLParser.swift`
    - 实现 `<text>`, `<bullet>`, `<order>`, `<input type="checkbox">` 解析
    - 实现 `<hr>`, `<img>`, `<sound>`, `<quote>` 解析
    - 处理块级元素的特殊格式（bullet/order/checkbox 内容在标签外部）
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8_

  - [x] 2.3 实现行内格式解析
    - 实现 `<b>`, `<i>`, `<u>`, `<delete>`, `<background>` 解析
    - 实现 `<size>`, `<mid-size>`, `<h3-size>` 解析
    - 实现 `<center>`, `<right>` 解析
    - 支持嵌套格式的递归解析
    - _Requirements: 2.1-2.11_

  - [x] 2.4 编写 XML 解析器属性测试
    - **Property 7: 块级元素解析正确性**
    - **Validates: Requirements 1.1-1.8**

  - [x] 2.5 编写嵌套格式解析属性测试
    - **Property 3: 嵌套格式解析正确性**
    - **Validates: Requirements 2.11**

- [x] 3. 实现 XML 生成器
  - [x] 3.1 实现块级元素生成
    - 创建 `Sources/Service/Editor/Generator/XMLGenerator.swift`
    - 实现各种块级节点到 XML 的转换
    - 处理块级元素的特殊格式（bullet/order/checkbox 内容在标签外部）
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 3.2 实现行内格式生成
    - 实现格式标签的正确嵌套顺序（标题→对齐→背景色→删除线→下划线→斜体→粗体）
    - 实现 XML 实体编码
    - _Requirements: 3.5, 3.6_

  - [x] 3.3 编写 XML 往返测试
    - **Property 1: XML 解析往返一致性**
    - **Validates: Requirements 6.1, 6.3, 6.4**

- [-] 4. 实现格式跨度合并器
  - [x] 4.1 实现 FormatSpan 数据结构
    - 创建 `Sources/Service/Editor/Converter/FormatSpan.swift`
    - 实现 `FormatSpan` 结构体
    - 实现 `canMerge` 和 `merged` 方法
    - _Requirements: 5.1, 5.2_

  - [x] 4.2 实现格式跨度合并逻辑
    - 创建 `Sources/Service/Editor/Converter/FormatSpanMerger.swift`
    - 实现 `mergeAdjacentSpans` 方法
    - 实现 `spansToInlineNodes` 方法（按固定顺序重建嵌套结构）
    - 实现 `inlineNodesToSpans` 方法（扁平化格式树）
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 4.3 编写格式跨度合并属性测试
    - **Property 4: 格式跨度合并正确性**
    - **Validates: Requirements 5.1, 5.3**

  - [x] 4.4 编写格式边界处理属性测试
    - **Property 5: 格式边界处理正确性**
    - **Validates: Requirements 5.3, 5.4**

- [x] 5. Checkpoint - 确保核心组件测试通过
  - 确保所有测试通过，如有问题请询问用户

- [x] 6. 实现 AST 到 NSAttributedString 转换器
  - [x] 6.1 实现块级节点转换
    - 创建 `Sources/Service/Editor/Converter/ASTToAttributedStringConverter.swift`
    - 实现 `DocumentNode`, `TextBlockNode` 转换
    - 实现 `BulletListNode`, `OrderedListNode`, `CheckboxNode` 转换（创建对应附件）
    - 实现 `HorizontalRuleNode`, `ImageNode`, `AudioNode`, `QuoteNode` 转换
    - _Requirements: 4.1, 4.3, 4.4, 4.5_

  - [x] 6.2 实现行内节点转换
    - 实现格式属性映射（bold→font trait, italic→obliqueness 等）
    - 实现递归属性继承（Visitor 模式）
    - _Requirements: 4.1, 4.2_

- [x] 7. 实现 NSAttributedString 到 AST 转换器
  - [x] 7.1 实现属性提取和格式识别
    - 创建 `Sources/Service/Editor/Converter/AttributedStringToASTConverter.swift`
    - 实现从 NSAttributedString 属性提取格式类型
    - 实现附件类型识别
    - _Requirements: 4.2, 4.3_

  - [x] 7.2 实现格式跨度生成
    - 遍历属性运行段，生成 FormatSpan 数组
    - 调用 FormatSpanMerger 合并相邻相同格式
    - 调用 spansToInlineNodes 重建格式树
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 7.3 编写 NSAttributedString 往返测试
    - **Property 2: NSAttributedString 往返一致性**
    - **Validates: Requirements 6.2, 6.3, 6.4**
    - **测试状态**: ✅ 所有 14 个测试通过
    - **修复问题**: 修复了 `resolveFontAttributes` 中 fontSize 类型转换问题（Double vs CGFloat）

- [-] 8. 实现特殊字符编解码
  - [ ] 8.1 实现 XML 实体编解码工具
    - 创建 `Sources/Service/Editor/Utils/XMLEntityCodec.swift`
    - 实现 `encode` 和 `decode` 方法
    - 支持 `<`, `>`, `&`, `"`, `'` 的编解码
    - _Requirements: 2.12, 3.6_

  - [ ] 8.2 编写特殊字符编解码属性测试
    - **Property 6: 特殊字符编解码正确性**
    - **Validates: Requirements 2.12, 3.6**

- [ ] 9. 实现错误处理
  - [ ] 9.1 实现解析错误类型和错误恢复
    - 创建 `Sources/Service/Editor/Parser/ParseError.swift`
    - 实现错误类型枚举
    - 实现跳过不支持元素的逻辑
    - 实现纯文本回退逻辑
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [ ] 9.2 编写错误容错性属性测试
    - **Property 8: 错误容错性**
    - **Validates: Requirements 7.1**

- [ ] 10. 集成到现有转换器
  - [ ] 10.1 更新 XiaoMiFormatConverter
    - 修改 `Sources/Service/Editor/XiaoMiFormatConverter.swift`
    - 将 `xmlToNSAttributedString` 方法改为使用新的 AST 解析器
    - 将 `nsAttributedStringToXML` 方法改为使用新的 AST 生成器
    - 保留原有方法作为回退
    - _Requirements: 所有_

  - [ ] 10.2 添加功能开关
    - 添加配置项控制是否使用新转换器
    - 便于逐步迁移和回退
    - _Requirements: 7.3, 7.4_

- [ ] 11. Final Checkpoint - 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户

## Notes

- 所有任务均为必需，确保代码质量
- 每个任务引用了具体的需求条款以便追溯
- 属性测试验证核心正确性属性
- 建议按顺序执行，确保增量进展
