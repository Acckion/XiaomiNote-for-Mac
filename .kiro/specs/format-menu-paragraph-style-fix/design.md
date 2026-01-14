# 设计文档

## 概述

本设计文档描述了如何修复格式菜单中段落样式显示和应用不正确的问题。核心修复包括：

1. **调整字体大小检测阈值**: 将三级标题的最小字体大小从 14pt 提高到 15pt，避免将正文（13pt）误判为三级标题
2. **修正标题和正文的字体大小**: 
   - 正文字体大小：15pt → 13pt
   - 三级标题字体大小：15pt → 16pt
3. **优化格式检测优先级**: 确保优先使用 `headingLevel` 自定义属性，只在属性不存在时才使用字体大小判断
4. **完善默认值处理**: 当无法确定段落样式时，默认返回"正文"而不是其他样式
5. **修复格式应用逻辑**: 确保应用"正文"格式时正确设置字体大小为 13pt 并移除 headingLevel 属性

## 问题分析

### 当前问题

1. **字体大小设置不一致**:
   - `FormatAttributesBuilder.swift` 中：`bodyFontSize = 15pt`, `heading3FontSize = 15pt`
   - 正文和三级标题使用相同的字体大小，导致无法区分

2. **字体大小阈值不合理**:
   - 当前阈值：三级标题 >= 14pt
   - 问题：14pt 和 15pt 的文本都被识别为三级标题

3. **格式应用不完整**:
   - 应用"正文"格式时，只移除了 `headingLevel` 属性
   - 但没有将字体大小重置为 13pt
   - 导致文本保留了标题的字体大小（如 15pt），被误判为三级标题

### 问题场景

**场景 1**: 选中大标题内容，点击"正文"菜单
1. 系统移除 `headingLevel` 属性
2. 字体大小变为 15pt（错误！应该是 13pt）
3. 检测时没有 `headingLevel` 属性，通过字体大小判断
4. 15pt 在 [14, 16) 范围内 → 被识别为三级标题
5. 格式菜单显示"三级标题"（错误！）

**场景 2**: 再次点击"正文"菜单
1. 系统认为当前是三级标题，切换为正文
2. 但实际上已经是正文格式，导致行为混乱

## 架构

### 当前架构

```
NativeEditorContext
  ├── updateCurrentFormats()          # 格式状态更新入口
  ├── detectFontFormats()             # 字体格式检测（包含标题检测）
  ├── getCurrentParagraphStyleString() # 获取段落样式字符串
  ├── detectParagraphStyleFromFormats() # 从格式集合推导段落样式
  └── clearHeadingFormat()            # 清除标题格式（需要修复）

FormatAttributesBuilder
  ├── heading1FontSize = 22pt         # 大标题字体大小
  ├── heading2FontSize = 18pt         # 二级标题字体大小
  ├── heading3FontSize = 15pt         # 三级标题字体大小（需要改为 16pt）
  └── bodyFontSize = 15pt             # 正文字体大小（需要改为 13pt）

FormatStateManager
  ├── updateState()                   # 格式状态更新（带防抖）
  └── postFormatStateNotification()   # 发送格式状态通知

MenuManager
  ├── updateFormatMenuState()         # 更新格式菜单状态
  ├── updateParagraphFormatMenuItems() # 更新段落格式菜单项
  └── convertToParagraphStyle()       # 格式转换
```

### 修复后的流程

```
用户输入文本或应用格式
    ↓
NativeEditorContext.updateCurrentFormats()
    ↓
detectFontFormats() - 检测标题格式
    ├── 1. 优先检查 headingLevel 属性
    ├── 2. 如果没有属性，检查字体大小
    │   ├── >= 20pt → 大标题
    │   ├── >= 17pt → 二级标题
    │   ├── >= 15pt → 三级标题（修复：从 14pt 提高到 15pt）
    │   └── < 15pt → 正文（修复：从 < 14pt 改为 < 15pt）
    └── 3. 默认返回正文
    ↓
detectParagraphStyleFromFormats() - 转换为段落样式字符串
    ├── heading1 → "heading"
    ├── heading2 → "subheading"
    ├── heading3 → "subtitle"
    └── 其他 → "body"（修复点）
    ↓
FormatStateManager.updateState() - 更新格式状态
    ↓
MenuManager.updateFormatMenuState() - 更新菜单勾选状态
```

## 组件和接口

### 1. FormatAttributesBuilder 修改

**当前实现问题:**
```swift
// 当前代码（有问题）
private static let heading3FontSize: CGFloat = 15
private static let bodyFontSize: CGFloat = 15  // 与三级标题相同！
```

**修复后实现:**
```swift
// 修复后代码
private static let heading1FontSize: CGFloat = 22  // 保持不变
private static let heading2FontSize: CGFloat = 18  // 保持不变
private static let heading3FontSize: CGFloat = 16  // 从 15pt 改为 16pt
private static let bodyFontSize: CGFloat = 13      // 从 15pt 改为 13pt
```

**关键变更:**
- 三级标题字体大小: 15pt → 16pt
- 正文字体大小: 15pt → 13pt
- 确保三级标题和正文有明显的字体大小差异

### 2. NativeEditorContext 修改

#### 修改方法: `detectFontFormats()`

**当前实现问题:**
```swift
// 当前代码（有问题）
if fontSize >= 14 && fontSize < 16 {
    formats.insert(.heading3)  // 14pt 和 15pt 都被误判为三级标题
}
```

**修复后实现:**
```swift
// 修复后代码
if fontSize >= 20 {
    formats.insert(.heading1)
} else if fontSize >= 17 && fontSize < 20 {
    formats.insert(.heading2)
} else if fontSize >= 15 && fontSize < 17 {
    formats.insert(.heading3)
}
// 小于 15pt 的不添加任何标题格式，默认为正文
```

**关键变更:**
- 三级标题最小字体大小: 14pt → 15pt
- 二级标题最小字体大小: 16pt → 17pt
- 小于 15pt 的字体不再被识别为任何标题

#### 修改方法: `clearHeadingFormat()`

**当前实现问题:**
```swift
// 当前代码（有问题）
func clearHeadingFormat() {
    // 只移除格式标记，没有重置字体大小
    currentFormats.remove(.heading1)
    currentFormats.remove(.heading2)
    currentFormats.remove(.heading3)
    // ...
}
```

**修复后实现:**
```swift
// 修复后代码
func clearHeadingFormat() {
    // 1. 移除所有标题格式标记
    currentFormats.remove(.heading1)
    currentFormats.remove(.heading2)
    currentFormats.remove(.heading3)
    toolbarButtonStates[.heading1] = false
    toolbarButtonStates[.heading2] = false
    toolbarButtonStates[.heading3] = false
    
    // 2. 重置字体大小为正文大小（13pt）
    // 这是关键修复：确保文本真正变为正文格式
    resetFontSizeToBody()
    
    // 3. 发布格式变化
    formatChangeSubject.send(.heading1)
    hasUnsavedChanges = true
}

/// 重置字体大小为正文大小
private func resetFontSizeToBody() {
    // 获取选中范围或光标位置
    let range = selectedRange.length > 0 ? selectedRange : NSRange(location: cursorPosition, length: 0)
    
    // 如果没有选中文本，不需要重置字体大小
    guard range.length > 0 else { return }
    
    // 创建可变副本
    let mutableText = nsAttributedText.mutableCopy() as! NSMutableAttributedString
    
    // 遍历选中范围，重置字体大小
    mutableText.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
        if let font = value as? NSFont {
            // 创建新字体，保留字体特性（加粗、斜体），但使用正文字体大小
            let traits = font.fontDescriptor.symbolicTraits
            let newFont: NSFont
            
            if traits.isEmpty {
                newFont = NSFont.systemFont(ofSize: 13)
            } else {
                let descriptor = NSFont.systemFont(ofSize: 13).fontDescriptor.withSymbolicTraits(traits)
                newFont = NSFont(descriptor: descriptor, size: 13) ?? NSFont.systemFont(ofSize: 13)
            }
            
            mutableText.addAttribute(.font, value: newFont, range: subRange)
        }
    }
    
    // 更新编辑器内容
    updateNSContent(mutableText)
}
```

#### 修改方法: `detectParagraphStyleFromFormats()`

**当前实现:**
```swift
// 当前代码（已经正确）
private func detectParagraphStyleFromFormats(_ formats: Set<TextFormat>) -> String {
    if formats.contains(.heading1) {
        return "heading"
    } else if formats.contains(.heading2) {
        return "subheading"
    } else if formats.contains(.heading3) {
        return "subtitle"
    } else if formats.contains(.numberedList) {
        return "orderedList"
    } else if formats.contains(.bulletList) {
        return "unorderedList"
    } else if formats.contains(.quote) {
        return "blockQuote"
    } else {
        // 明确的默认值：正文
        return "body"
    }
}
```

**无需修改**，这个方法已经正确实现了默认值处理。

### 3. 字体大小阈值常量

**新增常量定义:**
```swift
// 在 NativeEditorContext 或 FormatManager 中定义
private enum FontSizeThreshold {
    static let heading1: CGFloat = 20.0    // 大标题最小字体
    static let heading2: CGFloat = 17.0    // 二级标题最小字体
    static let heading3: CGFloat = 15.0    // 三级标题最小字体
    static let body: CGFloat = 15.0        // 正文最大字体（不含）
}
```

### 4. 格式检测优先级

**检测顺序（按优先级）:**
1. **headingLevel 自定义属性** - 最高优先级，最可靠
2. **字体大小** - 备用检测方式
3. **默认值** - 无法确定时返回"正文"

## 数据模型

### ParagraphFormat 枚举

```swift
public enum ParagraphFormat: String, CaseIterable, Sendable {
    case heading1 = "heading1"      // 大标题 (>= 20pt, 字体大小 22pt)
    case heading2 = "heading2"      // 二级标题 (>= 17pt, 字体大小 18pt)
    case heading3 = "heading3"      // 三级标题 (>= 15pt, 字体大小 16pt)
    case body = "body"              // 正文 (< 15pt, 字体大小 13pt)
    case bulletList = "bulletList"
    case numberedList = "numberedList"
    case checkbox = "checkbox"
}
```

### 段落样式字符串映射

| ParagraphFormat | 段落样式字符串 | 应用时字体大小 | 检测阈值范围 |
|----------------|--------------|--------------|------------|
| heading1       | "heading"    | 22pt         | >= 20pt    |
| heading2       | "subheading" | 18pt         | 17-20pt    |
| heading3       | "subtitle"   | 16pt         | 15-17pt    |
| body           | "body"       | 13pt         | < 15pt     |

## 正确性属性

*属性是一个特征或行为，应该在系统的所有有效执行中保持为真——本质上是关于系统应该做什么的形式化陈述。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### 属性 1: 正文字体大小识别

*对于任何* 没有 headingLevel 属性且字体大小小于 15pt 的文本，格式检测应该将其识别为正文而不是任何标题格式

**验证需求: 1.1, 1.3, 2.5, 4.4**

### 属性 2: 标题属性优先级

*对于任何* 同时具有 headingLevel 属性和特定字体大小的文本，格式检测应该优先使用 headingLevel 属性的值，忽略字体大小

**验证需求: 2.1, 2.2, 4.5**

### 属性 3: 字体大小阈值正确性

*对于任何* 没有 headingLevel 属性的文本：
- 字体大小 >= 20pt 应识别为大标题
- 字体大小 >= 17pt 且 < 20pt 应识别为二级标题
- 字体大小 >= 15pt 且 < 17pt 应识别为三级标题
- 字体大小 < 15pt 应识别为正文

**验证需求: 4.1, 4.2, 4.3, 4.4**

### 属性 4: 菜单状态互斥性

*对于任何* 段落样式状态，格式菜单中应该有且仅有一个段落样式菜单项被勾选

**验证需求: 1.4, 1.5, 3.2, 3.3**

### 属性 5: 默认值一致性

*对于任何* 无法确定段落样式的情况（没有 headingLevel 属性且字体大小在正常范围内），格式检测应该始终返回"正文"作为默认值

**验证需求: 5.1, 5.4, 5.5**

### 属性 6: 状态同步及时性

*对于任何* 光标位置变化或格式变化事件，格式菜单的状态更新应该在 50ms 内完成

**验证需求: 3.1, 3.4**

### 属性 7: 双向同步一致性

*对于任何* 通过菜单切换的段落样式，格式检测应该立即反映新的样式状态，且再次检测时应该返回相同的样式

**验证需求: 3.5**

### 属性 8: 新段落样式继承

*对于任何* 在正文段落末尾按回车创建的新段落，应该继承正文样式（13pt）；在标题段落末尾按回车创建的新段落，应该恢复为正文样式（13pt）

**验证需求: 5.2, 5.3**

### 属性 9: 格式应用字体大小一致性

*对于任何* 应用正文格式的操作，文本的字体大小应该被设置为 13pt；应用三级标题格式的操作，文本的字体大小应该被设置为 16pt

**验证需求: 1.6, 1.7, 4.6, 4.7**

## 错误处理

### 1. 字体属性缺失

**场景**: 文本没有 `.font` 属性

**处理策略**:
- 返回空的格式集合
- 默认段落样式为"正文"
- 记录警告日志

### 2. 字体大小异常

**场景**: 字体大小为负数或异常大的值

**处理策略**:
- 忽略字体大小检测
- 仅依赖 headingLevel 属性
- 如果 headingLevel 也不存在，默认为"正文"

### 3. 格式集合为空

**场景**: 检测到的格式集合为空

**处理策略**:
- `detectParagraphStyleFromFormats()` 返回 "body"
- 菜单状态勾选"正文"菜单项
- 这是正常情况，不需要记录错误

### 4. 多个标题格式同时存在

**场景**: 格式集合中同时包含多个标题格式

**处理策略**:
- 使用 `validateMutuallyExclusiveFormats()` 验证
- 保留优先级最高的标题（heading1 > heading2 > heading3）
- 移除其他标题格式

## 测试策略

### 单元测试

**测试文件**: `Tests/NativeEditorTests/ParagraphStyleDetectionTests.swift`

**测试用例**:
1. `testBodyTextDetection_DefaultFontSize()` - 测试默认字体大小（13pt）识别为正文
2. `testBodyTextDetection_SmallFontSize()` - 测试小字体（< 15pt）识别为正文
3. `testHeading3Detection_MinimumFontSize()` - 测试三级标题最小字体（15pt）
4. `testHeading2Detection_MinimumFontSize()` - 测试二级标题最小字体（17pt）
5. `testHeading1Detection_MinimumFontSize()` - 测试大标题最小字体（20pt）
6. `testHeadingLevelPriority()` - 测试 headingLevel 属性优先级
7. `testDefaultValueWhenUndetermined()` - 测试无法确定时的默认值
8. `testMenuStateExclusivity()` - 测试菜单状态互斥性

### 属性测试

**测试文件**: `Tests/NativeEditorTests/ParagraphStylePropertyTests.swift`

**属性测试**:
1. **属性 1**: 生成随机字体大小（< 15pt）和文本内容，验证都被识别为正文
2. **属性 2**: 生成随机 headingLevel 值和字体大小，验证优先使用 headingLevel
3. **属性 3**: 生成随机字体大小，验证阈值判断的正确性
4. **属性 4**: 生成随机段落样式，验证菜单状态互斥性
5. **属性 5**: 生成各种边界情况，验证默认值一致性
6. **属性 6**: 测量状态更新时间，验证在 50ms 内完成
7. **属性 7**: 模拟菜单操作，验证双向同步一致性
8. **属性 8**: 模拟回车操作，验证新段落样式继承

**配置**: 每个属性测试运行 100 次迭代

### 集成测试

**测试场景**:
1. 用户在空白编辑器中输入文本，验证格式菜单显示"正文"
2. 用户应用大标题格式，验证格式菜单显示"大标题"
3. 用户在大标题后按回车，验证新段落格式菜单显示"正文"
4. 用户移动光标到不同段落，验证格式菜单实时更新

## 性能考虑

### 1. 格式检测性能

**当前性能**: 格式检测在每次光标移动时触发，使用 50ms 防抖

**优化措施**:
- 保持现有的防抖机制
- 字体大小阈值检测是 O(1) 操作，性能影响可忽略
- 避免在检测过程中进行复杂计算

### 2. 菜单状态更新性能

**目标**: 状态更新在 50ms 内完成

**实现**:
- 使用 `FormatStateManager` 的防抖机制
- 批量更新菜单项状态，避免多次刷新
- 只更新变化的菜单项

## 向后兼容性

### 1. 现有文档兼容性

**影响**: 现有文档中 14pt 的文本可能之前被识别为三级标题，修复后会被识别为正文

**迁移策略**:
- 不需要迁移现有文档
- 如果文本之前被正确标记了 `headingLevel` 属性，不会受影响
- 如果文本只是通过字体大小被识别为标题，修复后会更准确

### 2. API 兼容性

**影响**: 无 API 变更，只是内部检测逻辑调整

**兼容性**: 完全向后兼容

## 实现注意事项

### 1. 代码修改位置

**主要修改文件**:
- `Sources/View/Bridge/NativeEditorContext.swift`
  - `detectFontFormats()` 方法
  - `detectParagraphStyleFromFormats()` 方法

**次要修改文件**:
- `Sources/View/NativeEditor/Format/FormatManager.swift`（如果需要添加常量定义）

### 2. 测试覆盖率

**目标**: 新增代码测试覆盖率 > 90%

**重点测试**:
- 字体大小阈值边界条件
- headingLevel 属性优先级
- 默认值处理
- 菜单状态同步

### 3. 调试日志

**保留现有日志**:
```swift
print("[NativeEditorContext] detectFontFormats - 检测到 headingLevel: \(headingLevel)")
print("[NativeEditorContext] detectFontFormats - 通过字体大小检测到xxx标题: \(fontSize)")
```

**新增日志**:
```swift
print("[NativeEditorContext] detectFontFormats - 字体大小 \(fontSize)pt 小于阈值，识别为正文")
```

## 部署计划

### 阶段 1: 代码修改和单元测试
- 修改 `detectFontFormats()` 方法
- 修改 `detectParagraphStyleFromFormats()` 方法
- 编写单元测试

### 阶段 2: 属性测试
- 编写属性测试
- 运行 100 次迭代验证

### 阶段 3: 集成测试
- 手动测试各种场景
- 验证格式菜单显示正确

### 阶段 4: 代码审查和部署
- 代码审查
- 合并到主分支
- 发布更新

## 风险评估

### 低风险
- 字体大小阈值调整：只影响没有 headingLevel 属性的文本
- 默认值处理：使系统更健壮

### 中风险
- 现有文档显示变化：14pt 文本可能从"三级标题"变为"正文"
- 缓解措施：这实际上是修复，使显示更准确

### 高风险
- 无

## 总结

本设计通过调整字体大小检测阈值和完善默认值处理，修复了格式菜单中段落样式显示不正确的问题。核心修改包括：

1. 将三级标题最小字体大小从 14pt 提高到 15pt
2. 将二级标题最小字体大小从 16pt 提高到 17pt
3. 明确默认段落样式为"正文"
4. 保持 headingLevel 属性的最高优先级

这些修改确保了正文内容（通常为 13pt）不会被误判为三级标题，同时保持了对现有标题格式的正确识别。
