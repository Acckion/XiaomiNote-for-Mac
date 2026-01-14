# Design Document

## Overview

本设计文档描述了基于抽象语法树（AST）的小米笔记 XML 与 NSAttributedString 双向转换算法。

设计灵感来源于业界成熟的富文本编辑器框架：
- **ProseMirror**：使用 Schema 定义文档结构，通过 Node 和 Mark 分离块级元素和行内格式
- **Slate.js**：使用 JSON 作为文档模型，支持灵活的序列化/反序列化
- **Apple Swift Markdown**：使用 Visitor 模式遍历 AST 生成 NSAttributedString

核心思想是引入一个中间表示层（AST），将复杂的格式转换问题分解为三个独立的子问题：

1. **XML → AST**：使用递归下降解析器解析 XML（类似 Slate 的 deserialize）
2. **AST ↔ NSAttributedString**：在 AST 和富文本之间转换（类似 Markdownosaur 的 Visitor 模式）
3. **AST → XML**：使用访问者模式生成 XML（类似 Slate 的 serialize）

关键设计决策：
- **Node + Mark 分离**：参考 ProseMirror，将块级元素（Node）和行内格式（Mark）分开处理
- **扁平化 Mark 表示**：行内格式使用 Mark 集合而非嵌套树，简化合并/拆分逻辑
- **递归序列化**：参考 Slate.js，使用递归函数处理嵌套结构

参考格式规范：#[[file:docs/小米笔记格式示例.md]]

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     XiaoMiFormatConverter                        │
│                       (Facade Pattern)                           │
│  xmlToNSAttributedString() / nsAttributedStringToXML()          │
└─────────────────────────────────────────────────────────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          ▼                       ▼                       ▼
   ┌─────────────┐         ┌───────────┐         ┌─────────────┐
   │  XMLParser  │         │    AST    │         │XMLGenerator │
   │ (Deserialize)│ ──────▶│  (Model)  │◀─────── │ (Serialize) │
   └─────────────┘         └───────────┘         └─────────────┘
          │                       │                       ▲
          │                       │                       │
          ▼                       ▼                       │
   ┌─────────────┐         ┌───────────┐         ┌─────────────┐
   │  Tokenizer  │         │   Mark    │         │MarkNormalizer│
   │ (Lexer)     │         │ Flattener │         │ (Optimizer)  │
   └─────────────┘         └───────────┘         └─────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          ▼                       ▼                       ▼
   ┌─────────────┐         ┌───────────┐         ┌─────────────┐
   │ AST to      │         │  Format   │         │ NSAttr to   │
   │ NSAttr      │         │  Span     │         │ AST         │
   │ Converter   │         │  Merger   │         │ Converter   │
   └─────────────┘         └───────────┘         └─────────────┘
```

### 数据流

**XML → NSAttributedString（解析方向）：**
```
XML String
    │
    ▼ Tokenizer（词法分析）
Token Stream
    │
    ▼ XMLParser（语法分析）
AST (Document → Blocks → Nodes + Marks)
    │
    ▼ ASTToAttributedStringConverter（Visitor 模式）
NSAttributedString
```

**NSAttributedString → XML（生成方向）：**
```
NSAttributedString
    │
    ▼ AttributedStringToASTConverter（属性遍历）
Format Spans (扁平化的格式跨度)
    │
    ▼ FormatSpanMerger（合并相邻相同格式）
Merged Spans
    │
    ▼ MarkNormalizer（构建 Mark 树）
AST (Document → Blocks → Nodes + Marks)
    │
    ▼ XMLGenerator（递归序列化）
XML String
```

## Components and Interfaces

### 1. AST 节点定义

```swift
// MARK: - AST 节点协议

/// AST 节点基础协议
protocol ASTNode {
    /// 节点类型标识
    var nodeType: ASTNodeType { get }
    /// 子节点（用于遍历）
    var children: [ASTNode] { get }
}

/// 节点类型枚举
enum ASTNodeType {
    // 块级元素
    case document
    case textBlock
    case bulletList
    case orderedList
    case checkbox
    case horizontalRule
    case image
    case audio
    case quote
    
    // 行内元素
    case text
    case bold
    case italic
    case underline
    case strikethrough
    case highlight
    case heading1
    case heading2
    case heading3
    case centerAlign
    case rightAlign
}

// MARK: - 块级节点

/// 文档根节点
struct DocumentNode: ASTNode {
    var nodeType: ASTNodeType { .document }
    var blocks: [BlockNode]
    var children: [ASTNode] { blocks }
}

/// 块级节点协议
protocol BlockNode: ASTNode {
    var indent: Int { get }
}

/// 文本块节点
struct TextBlockNode: BlockNode {
    var nodeType: ASTNodeType { .textBlock }
    var indent: Int
    var content: [InlineNode]
    var children: [ASTNode] { content }
}

/// 无序列表节点
struct BulletListNode: BlockNode {
    var nodeType: ASTNodeType { .bulletList }
    var indent: Int
    var content: [InlineNode]
    var children: [ASTNode] { content }
}

/// 有序列表节点
struct OrderedListNode: BlockNode {
    var nodeType: ASTNodeType { .orderedList }
    var indent: Int
    var inputNumber: Int  // 0 表示连续，非0 表示新列表起始值-1
    var content: [InlineNode]
    var children: [ASTNode] { content }
}

/// 复选框节点
struct CheckboxNode: BlockNode {
    var nodeType: ASTNodeType { .checkbox }
    var indent: Int
    var level: Int
    var isChecked: Bool
    var content: [InlineNode]
    var children: [ASTNode] { content }
}

/// 分割线节点
struct HorizontalRuleNode: BlockNode {
    var nodeType: ASTNodeType { .horizontalRule }
    var indent: Int { 1 }
    var children: [ASTNode] { [] }
}

/// 图片节点
struct ImageNode: BlockNode {
    var nodeType: ASTNodeType { .image }
    var indent: Int { 1 }
    var fileId: String?
    var src: String?
    var width: Int?
    var height: Int?
    var children: [ASTNode] { [] }
}

/// 音频节点
struct AudioNode: BlockNode {
    var nodeType: ASTNodeType { .audio }
    var indent: Int { 1 }
    var fileId: String
    var isTemporary: Bool
    var children: [ASTNode] { [] }
}

/// 引用块节点
struct QuoteNode: BlockNode {
    var nodeType: ASTNodeType { .quote }
    var indent: Int { 1 }
    var textBlocks: [TextBlockNode]
    var children: [ASTNode] { textBlocks }
}

// MARK: - 行内节点

/// 行内节点协议
protocol InlineNode: ASTNode {}

/// 纯文本节点
struct TextNode: InlineNode {
    var nodeType: ASTNodeType { .text }
    var text: String
    var children: [ASTNode] { [] }
}

/// 格式化节点（包含子节点）
struct FormattedNode: InlineNode {
    var nodeType: ASTNodeType
    var content: [InlineNode]
    var color: String?  // 仅用于 highlight
    var children: [ASTNode] { content }
    
    init(type: ASTNodeType, content: [InlineNode], color: String? = nil) {
        self.nodeType = type
        self.content = content
        self.color = color
    }
}
```

### 2. XML 解析器

```swift
/// XML 解析器 - 将小米笔记 XML 解析为 AST
class XMLParser {
    
    /// 解析错误类型
    enum ParseError: Error {
        case invalidXML(String)
        case unexpectedEndOfInput
        case unmatchedTag(expected: String, found: String)
        case unsupportedElement(String)
    }
    
    /// 解析 XML 字符串为文档 AST
    /// - Parameter xml: 小米笔记 XML 字符串
    /// - Returns: 文档 AST 节点
    /// - Throws: ParseError
    func parse(_ xml: String) throws -> DocumentNode
    
    /// 解析单行 XML 为块级节点
    /// - Parameter line: XML 行
    /// - Returns: 块级节点
    /// - Throws: ParseError
    private func parseBlock(_ line: String) throws -> BlockNode
    
    /// 解析行内内容为行内节点数组
    /// - Parameter content: 行内内容字符串
    /// - Returns: 行内节点数组
    /// - Throws: ParseError
    private func parseInlineContent(_ content: String) throws -> [InlineNode]
    
    /// 解码 XML 实体
    /// - Parameter text: 包含 XML 实体的文本
    /// - Returns: 解码后的文本
    private func decodeXMLEntities(_ text: String) -> String
}
```

### 3. XML 生成器

```swift
/// XML 生成器 - 将 AST 转换为小米笔记 XML
class XMLGenerator {
    
    /// 格式标签嵌套顺序（从外到内）
    private let formatOrder: [ASTNodeType] = [
        .heading1, .heading2, .heading3,  // 标题最外层
        .centerAlign, .rightAlign,         // 对齐
        .highlight,                         // 背景色
        .strikethrough,                     // 删除线
        .underline,                         // 下划线
        .italic,                            // 斜体
        .bold                               // 粗体最内层
    ]
    
    /// 将文档 AST 转换为 XML 字符串
    /// - Parameter document: 文档 AST 节点
    /// - Returns: XML 字符串
    func generate(_ document: DocumentNode) -> String
    
    /// 将块级节点转换为 XML 行
    /// - Parameter block: 块级节点
    /// - Returns: XML 行字符串
    private func generateBlock(_ block: BlockNode) -> String
    
    /// 将行内节点数组转换为 XML 内容
    /// - Parameter nodes: 行内节点数组
    /// - Returns: XML 内容字符串
    private func generateInlineContent(_ nodes: [InlineNode]) -> String
    
    /// 编码 XML 特殊字符
    /// - Parameter text: 原始文本
    /// - Returns: 编码后的文本
    private func encodeXMLEntities(_ text: String) -> String
}
```

### 4. AST 到 NSAttributedString 转换器

```swift
/// AST 到 NSAttributedString 转换器
class ASTToAttributedStringConverter {
    
    /// 将文档 AST 转换为 NSAttributedString
    /// - Parameters:
    ///   - document: 文档 AST 节点
    ///   - folderId: 文件夹 ID（用于图片加载）
    /// - Returns: NSAttributedString
    func convert(_ document: DocumentNode, folderId: String?) -> NSAttributedString
    
    /// 将块级节点转换为 NSAttributedString
    /// - Parameter block: 块级节点
    /// - Returns: NSAttributedString
    private func convertBlock(_ block: BlockNode) -> NSAttributedString
    
    /// 将行内节点数组转换为 NSAttributedString
    /// - Parameters:
    ///   - nodes: 行内节点数组
    ///   - inheritedAttributes: 继承的属性
    /// - Returns: NSAttributedString
    private func convertInlineNodes(_ nodes: [InlineNode], 
                                    inheritedAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString
    
    /// 获取格式节点对应的属性
    /// - Parameter node: 格式化节点
    /// - Returns: 属性字典
    private func attributesForFormat(_ node: FormattedNode) -> [NSAttributedString.Key: Any]
}
```

### 5. NSAttributedString 到 AST 转换器

```swift
/// NSAttributedString 到 AST 转换器
class AttributedStringToASTConverter {
    
    /// 将 NSAttributedString 转换为文档 AST
    /// - Parameter attributedString: NSAttributedString
    /// - Returns: 文档 AST 节点
    func convert(_ attributedString: NSAttributedString) -> DocumentNode
    
    /// 将单行 NSAttributedString 转换为块级节点
    /// - Parameter line: 单行 NSAttributedString
    /// - Returns: 块级节点
    private func convertLineToBlock(_ line: NSAttributedString) -> BlockNode
    
    /// 将属性运行段转换为行内节点
    /// - Parameter attributedString: NSAttributedString
    /// - Returns: 行内节点数组
    private func convertToInlineNodes(_ attributedString: NSAttributedString) -> [InlineNode]
    
    /// 从属性字典提取格式信息
    /// - Parameter attributes: 属性字典
    /// - Returns: 格式类型集合
    private func extractFormats(from attributes: [NSAttributedString.Key: Any]) -> Set<ASTNodeType>
}
```

### 6. 格式跨度合并器

```swift
/// 格式跨度 - 表示一段具有特定格式的文本（扁平化表示）
/// 
/// 这是解决格式边界问题的关键数据结构。
/// 参考 ProseMirror 的 Mark 概念，将嵌套的格式树扁平化为格式集合。
/// 
/// 例如：`<b><i>文本</i></b>` 表示为 FormatSpan(text: "文本", formats: [.bold, .italic])
/// 
/// 优势：
/// 1. 合并相邻相同格式变得简单（只需比较 formats 集合）
/// 2. 避免了嵌套树结构导致的边界处理复杂性
/// 3. 生成 XML 时可以按照固定顺序重建嵌套结构
struct FormatSpan: Equatable {
    var text: String
    var formats: Set<ASTNodeType>
    var highlightColor: String?
    
    /// 检查两个跨度是否可以合并（格式完全相同）
    func canMerge(with other: FormatSpan) -> Bool {
        return formats == other.formats && highlightColor == other.highlightColor
    }
    
    /// 合并两个跨度
    func merged(with other: FormatSpan) -> FormatSpan {
        return FormatSpan(
            text: text + other.text,
            formats: formats,
            highlightColor: highlightColor
        )
    }
}

/// 格式跨度合并器 - 优化 AST 结构，解决格式边界问题
/// 
/// 核心算法：
/// 1. NSAttributedString → FormatSpan[]：遍历属性运行段，提取格式集合
/// 2. 合并相邻相同格式的跨度
/// 3. FormatSpan[] → InlineNode[]：按照固定的嵌套顺序重建格式树
class FormatSpanMerger {
    
    /// 格式标签的嵌套顺序（从外到内）
    /// 生成 XML 时按此顺序嵌套标签
    private let formatOrder: [ASTNodeType] = [
        .heading1, .heading2, .heading3,  // 标题最外层
        .centerAlign, .rightAlign,         // 对齐
        .highlight,                         // 背景色
        .strikethrough,                     // 删除线
        .underline,                         // 下划线
        .italic,                            // 斜体
        .bold                               // 粗体最内层
    ]
    
    /// 合并相邻的相同格式跨度
    /// 
    /// 这是解决 `</b></i><i><b>` 问题的关键步骤。
    /// 当用户在格式化文本末尾添加内容时，如果新内容继承了相同格式，
    /// 合并后就不会产生多余的闭合/开启标签。
    /// 
    /// - Parameter spans: 格式跨度数组
    /// - Returns: 合并后的格式跨度数组
    func mergeAdjacentSpans(_ spans: [FormatSpan]) -> [FormatSpan] {
        guard !spans.isEmpty else { return [] }
        
        var result: [FormatSpan] = []
        var current = spans[0]
        
        for i in 1..<spans.count {
            let next = spans[i]
            if current.canMerge(with: next) {
                // 格式相同，合并
                current = current.merged(with: next)
            } else {
                // 格式不同，保存当前跨度，开始新跨度
                result.append(current)
                current = next
            }
        }
        result.append(current)
        
        return result
    }
    
    /// 将格式跨度数组转换为行内节点树
    /// 
    /// 按照 formatOrder 的顺序，从外到内构建嵌套的格式节点。
    /// 
    /// - Parameter spans: 格式跨度数组
    /// - Returns: 行内节点数组
    func spansToInlineNodes(_ spans: [FormatSpan]) -> [InlineNode] {
        return spans.map { span in
            var node: InlineNode = TextNode(text: span.text)
            
            // 按照从内到外的顺序包裹格式节点
            for format in formatOrder.reversed() {
                if span.formats.contains(format) {
                    let color = (format == .highlight) ? span.highlightColor : nil
                    node = FormattedNode(type: format, content: [node], color: color)
                }
            }
            
            return node
        }
    }
    
    /// 将行内节点树展平为格式跨度数组
    /// 
    /// 递归遍历节点树，收集每个叶子节点的格式集合。
    /// 
    /// - Parameter nodes: 行内节点数组
    /// - Returns: 格式跨度数组
    func inlineNodesToSpans(_ nodes: [InlineNode]) -> [FormatSpan] {
        var spans: [FormatSpan] = []
        
        func flatten(_ node: InlineNode, formats: Set<ASTNodeType>, highlightColor: String?) {
            if let textNode = node as? TextNode {
                spans.append(FormatSpan(
                    text: textNode.text,
                    formats: formats,
                    highlightColor: highlightColor
                ))
            } else if let formattedNode = node as? FormattedNode {
                var newFormats = formats
                newFormats.insert(formattedNode.nodeType)
                let newColor = formattedNode.color ?? highlightColor
                
                for child in formattedNode.content {
                    flatten(child, formats: newFormats, highlightColor: newColor)
                }
            }
        }
        
        for node in nodes {
            flatten(node, formats: [], highlightColor: nil)
        }
        
        return spans
    }
}
```

## Data Models

### 格式属性映射

| AST 节点类型 | NSAttributedString 属性 | XML 标签 |
|-------------|------------------------|----------|
| bold | .font (bold trait) | `<b>` |
| italic | .obliqueness (0.2) 或 .font (italic trait) | `<i>` |
| underline | .underlineStyle (.single) | `<u>` |
| strikethrough | .strikethroughStyle (.single) | `<delete>` |
| highlight | .backgroundColor | `<background color="">` |
| heading1 | .font (size: 24, weight: bold) | `<size>` |
| heading2 | .font (size: 20, weight: semibold) | `<mid-size>` |
| heading3 | .font (size: 16, weight: medium) | `<h3-size>` |
| centerAlign | .paragraphStyle (alignment: .center) | `<center>` |
| rightAlign | .paragraphStyle (alignment: .right) | `<right>` |

### 附件类型映射

| AST 节点类型 | NSTextAttachment 类型 | XML 标签 |
|-------------|---------------------|----------|
| checkbox | InteractiveCheckboxAttachment | `<input type="checkbox">` |
| horizontalRule | HorizontalRuleAttachment | `<hr />` |
| image | ImageAttachment | `<img>` |
| audio | AudioAttachment | `<sound>` |
| bulletList | BulletAttachment | `<bullet>` |
| orderedList | OrderAttachment | `<order>` |


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: XML 解析往返一致性

*For any* 有效的小米笔记 XML 字符串，解析为 AST 后再生成 XML，生成的 XML 与原始 XML 应该语义等价（文本内容相同，格式属性相同，附件信息相同）。

**Validates: Requirements 6.1, 6.3, 6.4**

### Property 2: NSAttributedString 往返一致性

*For any* 有效的 NSAttributedString，转换为 AST 后再转换回 NSAttributedString，所有格式属性（粗体、斜体、下划线、删除线、背景色、字体大小、对齐方式）和附件信息应该保持不变。

**Validates: Requirements 6.2, 6.3, 6.4**

### Property 3: 嵌套格式解析正确性

*For any* 包含嵌套格式标签的 XML（如 `<b><i>文本</i></b>`），解析后的 AST 树结构应该正确反映嵌套关系，且内层节点的父节点类型应该与外层标签对应。

**Validates: Requirements 2.11**

### Property 4: 格式跨度合并正确性

*For any* 包含相邻相同格式文本的 NSAttributedString，转换为 AST 后，相邻的相同格式文本应该被合并为单个格式节点，生成的 XML 不应包含冗余的闭合/开启标签序列（如 `</b><b>`）。

**Validates: Requirements 5.1, 5.3**

### Property 5: 格式边界处理正确性

*For any* 格式化文本，在其末尾添加新内容后转换为 XML，不应产生多余的格式标签（如 `</b></i><i><b>`），新内容应该正确继承或不继承前面的格式。

**Validates: Requirements 5.3, 5.4**

### Property 6: 特殊字符编解码正确性

*For any* 包含 XML 特殊字符（`<`, `>`, `&`, `"`, `'`）的文本内容，编码后再解码应该得到原始文本。

**Validates: Requirements 2.12, 3.6**

### Property 7: 块级元素解析正确性

*For any* 有效的块级元素 XML（text, bullet, order, checkbox, hr, img, sound, quote），解析后应该生成正确类型的 AST 节点，且所有属性（indent, inputNumber, checked, fileId 等）应该被正确保留。

**Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8**

### Property 8: 错误容错性

*For any* 包含不支持元素的 XML，解析器应该跳过不支持的元素并继续处理其余内容，最终结果应该包含所有可解析的内容。

**Validates: Requirements 7.1**

## Error Handling

### 解析错误处理

```swift
enum ParseError: Error, LocalizedError {
    case invalidXML(String)           // XML 格式无效
    case unexpectedEndOfInput         // 意外的输入结束
    case unmatchedTag(expected: String, found: String)  // 标签不匹配
    case unsupportedElement(String)   // 不支持的元素
    
    var errorDescription: String? {
        switch self {
        case .invalidXML(let message):
            return "无效的 XML 格式: \(message)"
        case .unexpectedEndOfInput:
            return "意外的输入结束"
        case .unmatchedTag(let expected, let found):
            return "标签不匹配: 期望 </\(expected)>，找到 </\(found)>"
        case .unsupportedElement(let element):
            return "不支持的元素: \(element)"
        }
    }
}
```

### 错误恢复策略

1. **跳过不支持的元素**：遇到不支持的块级元素时，记录警告并跳过，继续处理下一行
2. **纯文本回退**：当行内内容解析失败时，将整个内容作为纯文本处理
3. **保留原始内容**：当整个转换失败时，返回包含原始纯文本的结果

### 日志记录

```swift
/// 转换日志级别
enum LogLevel {
    case debug
    case info
    case warning
    case error
}

/// 记录转换过程中的事件
func log(_ level: LogLevel, _ message: String, context: [String: Any]? = nil)
```

## Testing Strategy

### 单元测试

1. **解析器测试**
   - 测试各种块级元素的解析
   - 测试各种行内格式的解析
   - 测试嵌套格式的解析
   - 测试特殊字符的解码

2. **生成器测试**
   - 测试各种 AST 节点的 XML 生成
   - 测试格式标签的嵌套顺序
   - 测试特殊字符的编码

3. **转换器测试**
   - 测试 AST 到 NSAttributedString 的转换
   - 测试 NSAttributedString 到 AST 的转换
   - 测试附件类型的转换

4. **格式跨度合并器测试**
   - 测试相邻相同格式的合并
   - 测试格式变化点的拆分

### 属性测试

使用 Swift 的属性测试框架（如 SwiftCheck）实现以下属性测试：

1. **XML 往返测试**
   - 生成随机有效的 XML
   - 验证 parse → generate 后语义等价

2. **NSAttributedString 往返测试**
   - 生成随机的 NSAttributedString
   - 验证 toAST → fromAST 后属性不变

3. **格式边界测试**
   - 生成格式化文本
   - 在末尾添加内容
   - 验证不产生冗余标签

4. **特殊字符测试**
   - 生成包含特殊字符的文本
   - 验证编解码往返一致

### 测试配置

- 每个属性测试运行至少 100 次迭代
- 使用 shrinking 来找到最小失败用例
- 测试标签格式：`Feature: xml-attributedstring-converter, Property N: 属性描述`
