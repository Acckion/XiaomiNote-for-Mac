# 需求文档

## 简介

修复原生编辑器中空行在保存时丢失的问题。当用户在编辑器中创建空行（按回车键），编辑器能正确显示空行，但保存后空行会丢失。问题根源在于 AttributedString 转换到 XML 的过程中，空行被错误地跳过。

## 术语表

- **AttributedString**: NSAttributedString，富文本字符串，包含文本内容和格式属性
- **AST**: 抽象语法树（Abstract Syntax Tree），用于表示文档结构的中间表示
- **XML**: 小米笔记使用的存储格式
- **空行**: 只包含换行符、没有其他内容的行
- **TextBlockNode**: AST 中表示文本块的节点类型

## 需求

### 需求 1：空行保留

**用户故事：** 作为用户，我希望在编辑器中创建的空行能够被正确保存，以便我可以使用空行来组织笔记内容的视觉结构。

#### 验收标准

1. WHEN 用户在编辑器中按下回车键创建空行 THEN 系统 SHALL 在 AttributedString 中保留该空行
2. WHEN AttributedString 包含空行被转换为 AST THEN 系统 SHALL 为每个空行生成一个空内容的 TextBlockNode
3. WHEN AST 包含空内容的 TextBlockNode 被转换为 XML THEN 系统 SHALL 生成 `<text indent="1"></text>` 格式的 XML 元素
4. WHEN 从云端同步包含空行的笔记 THEN 系统 SHALL 正确解析并显示空行

### 需求 2：空行格式继承

**用户故事：** 作为用户，我希望空行能够保留其缩进级别，以便在列表或缩进内容中创建的空行能保持正确的缩进。

#### 验收标准

1. WHEN 用户在缩进内容后创建空行 THEN 系统 SHALL 保留该空行的缩进级别
2. WHEN 空行有缩进属性被转换为 XML THEN 系统 SHALL 在 `<text>` 标签中包含正确的 `indent` 属性值

### 需求 3：连续空行处理

**用户故事：** 作为用户，我希望能够创建多个连续的空行，以便在笔记中添加更大的视觉间隔。

#### 验收标准

1. WHEN 用户创建多个连续空行 THEN 系统 SHALL 保留所有空行
2. WHEN 多个连续空行被转换为 XML THEN 系统 SHALL 为每个空行生成独立的 `<text indent="N"></text>` 元素

### 需求 4：往返一致性

**用户故事：** 作为用户，我希望笔记在保存和重新加载后保持完全一致，包括所有空行。

#### 验收标准

1. FOR ALL 包含空行的有效文档，将其转换为 XML 再解析回来 SHALL 产生等价的文档结构
2. WHEN 笔记被保存到云端并重新同步 THEN 系统 SHALL 保留所有空行的位置和数量
