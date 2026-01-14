# Requirements Document

## Introduction

本文档定义了小米笔记 XML 格式与 NSAttributedString 之间双向转换的需求。当前实现基于正则表达式匹配，在处理嵌套格式标签和编辑边界时存在严重问题（如在粗体斜体文本后添加内容时出现 `</b></i><i><b>` 等标签泄露）。新设计将采用基于抽象语法树（AST）的转换算法，确保转换的正确性和可维护性。

参考格式规范：#[[file:docs/小米笔记格式示例.md]]

## Glossary

- **XML_Parser**: 将小米笔记 XML 字符串解析为 AST 的解析器
- **XML_Generator**: 将 AST 转换为小米笔记 XML 字符串的生成器
- **AST_Node**: 抽象语法树节点，表示文档结构的基本单元
- **Block_Element**: 块级元素，代表一行内容（如 `<text>`、`<bullet>`、`<order>`、`<input>`、`<hr>`、`<img>`、`<sound>`、`<quote>`）
- **Inline_Element**: 行内元素，代表文本格式（如 `<b>`、`<i>`、`<u>`、`<delete>`、`<background>`、`<size>`、`<mid-size>`、`<h3-size>`、`<center>`、`<right>`）
- **Format_Span**: 格式跨度，表示一段具有特定格式属性的文本范围
- **Attributed_Converter**: 将 AST 与 NSAttributedString 相互转换的转换器
- **Round_Trip**: 往返转换，指 XML → AST → NSAttributedString → AST → XML 的完整转换过程

## Requirements

### Requirement 1: 块级元素解析

**User Story:** 作为开发者，我希望正确解析所有块级元素类型，以便完整表示笔记内容结构。

#### Acceptance Criteria

1. WHEN 解析 `<text indent="N">内容</text>` 时，THE XML_Parser SHALL 创建文本块节点并保留缩进属性
2. WHEN 解析 `<bullet indent="N" />内容` 时，THE XML_Parser SHALL 创建无序列表节点（注意：内容在标签外部）
3. WHEN 解析 `<order indent="N" inputNumber="M" />内容` 时，THE XML_Parser SHALL 创建有序列表节点并正确处理 inputNumber 规则
4. WHEN 解析 `<input type="checkbox" indent="N" level="M" />内容` 或带 `checked="true"` 的复选框时，THE XML_Parser SHALL 创建复选框节点并保留勾选状态
5. WHEN 解析 `<hr />` 时，THE XML_Parser SHALL 创建分割线节点
6. WHEN 解析 `<img fileid="ID" />` 或 `<img src="URL" />` 时，THE XML_Parser SHALL 创建图片节点并保留所有属性
7. WHEN 解析 `<sound fileid="ID" />` 时，THE XML_Parser SHALL 创建音频节点
8. WHEN 解析 `<quote>多行内容</quote>` 时，THE XML_Parser SHALL 创建引用块节点并递归解析内部的 text 元素

### Requirement 2: 行内格式元素解析

**User Story:** 作为开发者，我希望正确解析所有行内格式标签，包括嵌套情况。

#### Acceptance Criteria

1. WHEN 解析 `<b>文本</b>` 时，THE XML_Parser SHALL 创建粗体格式节点
2. WHEN 解析 `<i>文本</i>` 时，THE XML_Parser SHALL 创建斜体格式节点
3. WHEN 解析 `<u>文本</u>` 时，THE XML_Parser SHALL 创建下划线格式节点
4. WHEN 解析 `<delete>文本</delete>` 时，THE XML_Parser SHALL 创建删除线格式节点
5. WHEN 解析 `<background color="颜色值">文本</background>` 时，THE XML_Parser SHALL 创建高亮格式节点并保留颜色属性
6. WHEN 解析 `<size>文本</size>` 时，THE XML_Parser SHALL 创建大标题格式节点
7. WHEN 解析 `<mid-size>文本</mid-size>` 时，THE XML_Parser SHALL 创建二级标题格式节点
8. WHEN 解析 `<h3-size>文本</h3-size>` 时，THE XML_Parser SHALL 创建三级标题格式节点
9. WHEN 解析 `<center>文本</center>` 时，THE XML_Parser SHALL 创建居中对齐格式节点
10. WHEN 解析 `<right>文本</right>` 时，THE XML_Parser SHALL 创建右对齐格式节点
11. WHEN 解析嵌套格式（如 `<b><i>文本</i></b>`）时，THE XML_Parser SHALL 正确构建嵌套的格式节点树
12. WHEN 解析包含特殊字符（`&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;`）的内容时，THE XML_Parser SHALL 正确解码为原始字符

### Requirement 3: AST 生成 XML

**User Story:** 作为开发者，我希望将 AST 转换回小米笔记 XML 格式，以便保存和同步笔记内容。

#### Acceptance Criteria

1. WHEN 将块级节点转换为 XML 时，THE XML_Generator SHALL 生成正确的块级元素格式
2. WHEN 生成无序列表 XML 时，THE XML_Generator SHALL 输出 `<bullet indent="N" />内容` 格式（内容在标签外部）
3. WHEN 生成有序列表 XML 时，THE XML_Generator SHALL 正确计算 inputNumber 值（首项为实际值-1，后续项为0）
4. WHEN 生成复选框 XML 时，THE XML_Generator SHALL 仅在选中时添加 `checked="true"` 属性
5. WHEN 生成包含嵌套格式的 XML 时，THE XML_Generator SHALL 按照正确的嵌套顺序输出标签（从外到内：标题 → 对齐 → 背景色 → 删除线 → 下划线 → 斜体 → 粗体）
6. WHEN 生成包含特殊字符的 XML 时，THE XML_Generator SHALL 正确转义特殊字符
7. THE XML_Generator SHALL 生成最小化的 XML 输出（合并相邻的相同格式节点）

### Requirement 4: AST 与 NSAttributedString 转换

**User Story:** 作为开发者，我希望在 AST 和 NSAttributedString 之间进行转换，以便在原生编辑器中显示和编辑内容。

#### Acceptance Criteria

1. WHEN 将 AST 转换为 NSAttributedString 时，THE Attributed_Converter SHALL 正确应用所有格式属性（粗体、斜体、下划线、删除线、背景色、标题大小、对齐方式）
2. WHEN 将 NSAttributedString 转换为 AST 时，THE Attributed_Converter SHALL 正确识别所有格式属性并生成对应的 AST_Node
3. WHEN 处理包含附件（图片、复选框、分割线、音频）的内容时，THE Attributed_Converter SHALL 正确转换附件类型并保留所有属性
4. WHEN 处理段落属性（缩进、对齐方式）时，THE Attributed_Converter SHALL 正确保留段落格式
5. WHEN 处理无序列表和有序列表时，THE Attributed_Converter SHALL 正确创建对应的附件和文本内容

### Requirement 5: 格式跨度合并与拆分

**User Story:** 作为开发者，我希望系统能够智能地合并和拆分格式跨度，以避免产生冗余的格式标签。

#### Acceptance Criteria

1. WHEN 相邻的文本具有相同格式属性时，THE Attributed_Converter SHALL 合并为单个 Format_Span
2. WHEN 文本的格式属性在某位置发生变化时，THE Attributed_Converter SHALL 在该位置拆分 Format_Span
3. WHEN 用户在格式化文本末尾添加新内容时，THE Attributed_Converter SHALL 正确处理格式边界，不产生多余的闭合/开启标签
4. WHEN 用户在格式化文本中间插入不同格式的内容时，THE Attributed_Converter SHALL 正确拆分原有格式跨度

### Requirement 6: 往返转换一致性

**User Story:** 作为开发者，我希望往返转换能够保持内容的一致性，确保数据不会在转换过程中丢失或损坏。

#### Acceptance Criteria

1. FOR ALL 有效的小米笔记 XML，解析后再生成的 XML SHALL 与原始 XML 语义等价
2. FOR ALL 有效的 NSAttributedString，转换为 AST 再转换回来 SHALL 保持所有格式属性不变
3. WHEN 进行往返转换时，THE Round_Trip SHALL 保持文本内容完全一致
4. WHEN 进行往返转换时，THE Round_Trip SHALL 保持所有附件信息完全一致（包括图片 fileId、音频 fileId、复选框状态等）

### Requirement 7: 错误处理与回退

**User Story:** 作为开发者，我希望转换过程能够优雅地处理错误，确保即使部分内容转换失败也不会丢失数据。

#### Acceptance Criteria

1. IF 解析 XML 时遇到不支持的元素，THEN THE XML_Parser SHALL 记录警告并跳过该元素，继续处理其余内容
2. IF 解析 XML 时遇到格式错误（如未闭合标签），THEN THE XML_Parser SHALL 返回描述性错误信息
3. IF 转换过程中发生错误，THEN THE Attributed_Converter SHALL 记录详细错误日志并尝试使用纯文本回退
4. WHEN 转换失败时，THE Attributed_Converter SHALL 返回包含原始文本内容的结果，而不是空结果

### Requirement 8: 性能要求

**User Story:** 作为用户，我希望格式转换能够快速完成，不影响编辑体验。

#### Acceptance Criteria

1. WHEN 转换包含 1000 行文本的文档时，THE XML_Parser SHALL 在 100ms 内完成解析
2. WHEN 转换包含 1000 行文本的文档时，THE XML_Generator SHALL 在 100ms 内完成生成
3. WHEN 用户编辑文本时，THE Attributed_Converter SHALL 支持增量转换，只处理变化的部分
