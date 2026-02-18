# IncrementalUpdateManager 使用指南

## 概述

`IncrementalUpdateManager` 是编辑器增量更新机制的核心组件，负责优化编辑器性能，只更新受影响的段落，跳过未变化的段落。

## 主要功能

### 1. 受影响段落识别

识别哪些段落受到文本变化的影响：

```swift
let manager = IncrementalUpdateManager(paragraphManager: paragraphManager)

// 识别受影响的段落
let affectedParagraphs = manager.identifyAffectedParagraphs(
    changedRange: NSRange(location: 10, length: 5),
    in: textStorage
)

print("受影响的段落数: \(affectedParagraphs.count)")
```

### 2. 段落版本跟踪

跟踪段落的版本号，判断是否需要更新：

```swift
// 递增段落版本
let updatedParagraph = manager.incrementParagraphVersion(paragraph)

// 检查是否需要更新
let needsUpdate = manager.shouldUpdateParagraph(
    paragraph,
    lastProcessedVersion: 5
)

// 标记需要重新解析
let markedParagraph = manager.markParagraphNeedsReparse(paragraph)

// 清除重新解析标记
let clearedParagraph = manager.clearParagraphReparseFlag(paragraph)
```

### 3. 增量更新执行

执行增量更新，只处理受影响的段落：

```swift
// 执行增量更新
let updatedCount = manager.performIncrementalUpdate(
    changedRange: NSRange(location: 10, length: 5),
    in: textStorage
) { paragraph in
    // 更新段落的处理逻辑
    print("更新段落: \(paragraph.range)")
    // 应用格式、重新解析等操作
}

print("共更新 \(updatedCount) 个段落")
```

### 4. 批量操作

批量更新多个段落的版本：

```swift
// 批量递增版本
let updatedParagraphs = manager.batchIncrementVersions(paragraphs)

// 过滤需要更新的段落
let lastProcessedVersions: [Int: Int] = [
    0: 5,   // 位置 0 的段落上次处理版本为 5
    100: 3  // 位置 100 的段落上次处理版本为 3
]

let needsUpdate = manager.filterParagraphsNeedingUpdate(
    paragraphs,
    lastProcessedVersions: lastProcessedVersions
)
```

## 使用场景

### 场景 1: 文本输入时的增量更新

```swift
func textDidChange(_ notification: Notification) {
    guard let textStorage = notification.object as? NSTextStorage else { return }
    
    // 获取变化范围
    let changedRange = textStorage.editedRange
    
    // 执行增量更新
    let updatedCount = incrementalUpdateManager.performIncrementalUpdate(
        changedRange: changedRange,
        in: textStorage
    ) { paragraph in
        // 只更新受影响的段落
        applyFormatting(to: paragraph, in: textStorage)
    }
    
    print("增量更新完成，更新了 \(updatedCount) 个段落")
}
```

### 场景 2: 格式应用时的优化

```swift
func applyFormat(_ format: ParagraphType, to range: NSRange) {
    // 识别受影响的段落
    let affectedParagraphs = incrementalUpdateManager.identifyAffectedParagraphs(
        changedRange: range,
        in: textStorage
    )
    
    // 只更新受影响的段落
    for paragraph in affectedParagraphs {
        if paragraph.needsReparse {
            // 完整重新解析
            fullReparse(paragraph)
        } else {
            // 只更新格式
            updateFormatOnly(paragraph)
        }
    }
}
```

### 场景 3: 版本跟踪和缓存

```swift
class EditorState {
    var lastProcessedVersions: [Int: Int] = [:]
    
    func updateParagraphs(_ paragraphs: [Paragraph]) {
        // 过滤出需要更新的段落
        let needsUpdate = incrementalUpdateManager.filterParagraphsNeedingUpdate(
            paragraphs,
            lastProcessedVersions: lastProcessedVersions
        )
        
        // 只处理需要更新的段落
        for paragraph in needsUpdate {
            processParagraph(paragraph)
            
            // 更新版本记录
            lastProcessedVersions[paragraph.range.location] = paragraph.version
        }
        
        print("跳过了 \(paragraphs.count - needsUpdate.count) 个未变化的段落")
    }
}
```

## 性能优化策略

### 1. 元属性变化检测

系统会检测以下元属性的变化：
- 段落类型（`.paragraphType`）
- 列表类型（`.listType`）
- 标题标记（`.isTitle`）
- 列表级别（`.listLevel`）

只有当这些元属性变化时，才会触发完整的段落重新解析。

### 2. 版本号机制

每个段落都有一个版本号：
- 段落内容变化时，版本号递增
- 通过比较版本号，快速判断段落是否需要更新
- 避免重复处理未变化的段落

### 3. 重新解析标记

使用 `needsReparse` 标记：
- 当元属性变化时，标记为需要重新解析
- 当段落结构变化时，标记为需要重新解析
- 只有标记的段落才会执行完整解析

## 调试支持

启用调试日志以查看详细的更新过程：

```swift
let manager = IncrementalUpdateManager(
    paragraphManager: paragraphManager,
    enableDebugLog: true  // 启用调试日志
)

// 执行操作时会输出详细日志
manager.performIncrementalUpdate(changedRange: range, in: textStorage) { paragraph in
    // ...
}
```

输出示例：
```
[IncrementalUpdateManager] 🚀 开始增量更新，变化范围: {10, 5}
[IncrementalUpdateManager] 🔍 识别受影响的段落，变化范围: {10, 5}
[IncrementalUpdateManager]    找到 2 个交集段落
[IncrementalUpdateManager]    ✓ 段落 {0, 15} 受影响: 范围交集
[IncrementalUpdateManager]    - 段落 {15, 20} 未受影响
[IncrementalUpdateManager] ✅ 识别完成，共 1 个受影响段落
[IncrementalUpdateManager]    更新段落 {0, 15}
[IncrementalUpdateManager] ✅ 增量更新完成，共更新 1 个段落
```

## 统计信息

使用 `IncrementalUpdateStatistics` 结构体获取更新统计：

```swift
let stats = IncrementalUpdateStatistics(
    totalParagraphs: 100,
    affectedParagraphs: 10,
    updatedParagraphs: 3
)

print(stats.description)
// 输出：
// 增量更新统计:
// - 总段落数: 100
// - 受影响段落: 10
// - 实际更新: 3
// - 跳过: 7
// - 效率: 70.0%
```

## 最佳实践

1. **及时更新版本号**：在段落内容变化后立即递增版本号
2. **合理使用重新解析标记**：只在必要时标记需要重新解析
3. **维护版本记录**：保存上次处理的版本号，用于后续比较
4. **批量操作**：尽可能使用批量方法处理多个段落
5. **启用调试日志**：在开发阶段启用日志，帮助理解更新流程

## 与其他组件的协作

### 与 ParagraphManager 协作

```swift
// ParagraphManager 负责段落边界检测和列表维护
paragraphManager.updateParagraphs(in: textStorage, changedRange: range)

// IncrementalUpdateManager 负责优化更新策略
incrementalUpdateManager.performIncrementalUpdate(
    changedRange: range,
    in: textStorage
) { paragraph in
    // 应用格式
}
```

### 与 TypingOptimizer 协作

```swift
// TypingOptimizer 判断是否为简单输入
if typingOptimizer.isSimpleTyping(change: text, at: location, in: textStorage) {
    // 简单输入，跳过完整解析
    applyTypingAttributes()
} else {
    // 复杂变化，使用增量更新
    incrementalUpdateManager.performIncrementalUpdate(
        changedRange: range,
        in: textStorage
    ) { paragraph in
        fullReparse(paragraph)
    }
}
```

## 相关文档

- [Paragraph.swift](../Model/Paragraph.swift) - 段落数据模型
- [ParagraphManager.swift](../Manager/ParagraphManager.swift) - 段落管理器
- [TypingOptimizer.swift](./TypingOptimizer.swift) - 打字优化器
- [Spec 69 设计文档](../../../../.kiro/specs/69-paper-inspired-editor-refactor/design.md)
