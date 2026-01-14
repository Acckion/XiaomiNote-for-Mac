# Spec 文档更新总结

## 问题发现

通过添加详细的调试日志，我们发现了问题的根本原因：

### 原始问题
用户报告：选中大标题内容，点击格式菜单中的"正文"，内容显示为正文格式，但菜单显示"三级标题"。

### 调试日志显示
```
[NativeEditorContext] ℹ️ 没有检测到 headingLevel 属性，将尝试通过字体大小判断
[NativeEditorContext] 📏 字体信息:
[NativeEditorContext]   - 字体名称: .AppleSystemUIFont
[NativeEditorContext]   - 字体大小: 15.0pt
[NativeEditorContext] 🔍 开始通过字体大小判断标题类型...
[NativeEditorContext]   当前阈值: 大标题>=20pt, 二级标题>=16pt, 三级标题>=14pt
[NativeEditorContext] ✅ 字体大小 15.0pt 在 [14, 16) 范围内，识别为【三级标题】
```

### 根本原因

1. **字体大小设置不一致**:
   - `FormatAttributesBuilder.swift` 中定义：
     - `bodyFontSize = 15pt`
     - `heading3FontSize = 15pt`
   - **正文和三级标题使用相同的字体大小！**

2. **字体大小阈值不合理**:
   - 当前阈值：三级标题 >= 14pt
   - 15pt 被识别为三级标题

3. **格式应用不完整**:
   - `clearHeadingFormat()` 方法只移除了 `headingLevel` 属性
   - **没有将字体大小重置为正文大小（13pt）**
   - 导致文本保留了 15pt 的字体大小，被误判为三级标题

## 解决方案

### 1. 修改字体大小常量

**文件**: `Sources/View/Bridge/FormatAttributesBuilder.swift`

```swift
// 修改前
private static let heading3FontSize: CGFloat = 15
private static let bodyFontSize: CGFloat = 15  // 问题：与三级标题相同

// 修改后
private static let heading3FontSize: CGFloat = 16  // 从 15pt 改为 16pt
private static let bodyFontSize: CGFloat = 13      // 从 15pt 改为 13pt
```

### 2. 调整字体大小检测阈值

**文件**: `Sources/View/Bridge/NativeEditorContext.swift`

**方法**: `detectFontFormats()`

```swift
// 修改前
if fontSize >= 14 && fontSize < 16 {
    formats.insert(.heading3)  // 14pt 和 15pt 都被识别为三级标题
}

// 修改后
if fontSize >= 15 && fontSize < 17 {
    formats.insert(.heading3)  // 只有 15pt 和 16pt 被识别为三级标题
}
// 小于 15pt 的不添加任何标题格式，默认为正文
```

### 3. 添加字体大小重置方法

**文件**: `Sources/View/Bridge/NativeEditorContext.swift`

**新增方法**: `resetFontSizeToBody()`

```swift
/// 重置字体大小为正文大小
private func resetFontSizeToBody() {
    // 获取选中范围
    let range = selectedRange.length > 0 ? selectedRange : NSRange(location: cursorPosition, length: 0)
    guard range.length > 0 else { return }
    
    // 创建可变副本
    let mutableText = nsAttributedText.mutableCopy() as! NSMutableAttributedString
    
    // 遍历选中范围，重置字体大小为 13pt
    mutableText.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
        if let font = value as? NSFont {
            // 保留字体特性（加粗、斜体），但使用正文字体大小
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

### 4. 修改 clearHeadingFormat() 方法

**文件**: `Sources/View/Bridge/NativeEditorContext.swift`

**方法**: `clearHeadingFormat()`

```swift
// 修改前
func clearHeadingFormat() {
    // 只移除格式标记，没有重置字体大小
    currentFormats.remove(.heading1)
    currentFormats.remove(.heading2)
    currentFormats.remove(.heading3)
    // ...
}

// 修改后
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
```

## 更新的文档

### 1. requirements.md
- 添加了需求 1.6 和 1.7：明确应用正文格式时应设置字体大小为 13pt
- 添加了需求 4.6 和 4.7：明确应用三级标题格式时应设置字体大小为 16pt
- 更新了需求 2.4 和 2.5：明确 13pt 和 14pt 应被识别为正文

### 2. design.md
- 添加了"问题分析"章节，详细说明了问题的根本原因
- 更新了 `FormatAttributesBuilder` 的修改方案
- 添加了 `resetFontSizeToBody()` 方法的设计
- 更新了 `clearHeadingFormat()` 方法的设计
- 添加了属性 9：格式应用字体大小一致性
- 更新了数据模型表格，添加了"应用时字体大小"和"检测阈值范围"列

### 3. tasks.md
- 添加了任务 1：修改字体大小常量定义
- 添加了任务 3：实现 resetFontSizeToBody() 方法
- 添加了任务 4：修改 clearHeadingFormat() 方法
- 更新了任务 7：测试正文格式识别和应用
- 添加了相应的单元测试和属性测试任务

## 修复后的行为

### 场景 1：选中大标题，点击"正文"
1. 系统移除 `headingLevel` 属性
2. **系统将字体大小重置为 13pt**（新增）
3. 检测时没有 `headingLevel` 属性，通过字体大小判断
4. 13pt < 15pt → 被识别为正文
5. 格式菜单显示"正文"（正确！）

### 场景 2：输入默认文本
1. 默认字体大小为 13pt
2. 没有 `headingLevel` 属性
3. 13pt < 15pt → 被识别为正文
4. 格式菜单显示"正文"（正确！）

### 场景 3：应用三级标题格式
1. 系统设置 `headingLevel = 3`
2. **系统将字体大小设置为 16pt**（修改）
3. 检测时优先使用 `headingLevel` 属性
4. 格式菜单显示"三级标题"（正确！）

## 字体大小对照表

| 段落样式 | 应用时字体大小 | 检测阈值范围 | 修改说明 |
|---------|--------------|------------|---------|
| 大标题   | 22pt         | >= 20pt    | 保持不变 |
| 二级标题 | 18pt         | 17-20pt    | 阈值从 16pt 提高到 17pt |
| 三级标题 | 16pt         | 15-17pt    | 字体大小从 15pt 改为 16pt，阈值从 14pt 提高到 15pt |
| 正文     | 13pt         | < 15pt     | 字体大小从 15pt 改为 13pt，阈值从 < 14pt 改为 < 15pt |

## 下一步

1. **实现任务 1**：修改 `FormatAttributesBuilder.swift` 中的字体大小常量
2. **实现任务 2**：修改 `NativeEditorContext.detectFontFormats()` 中的阈值
3. **实现任务 3**：添加 `resetFontSizeToBody()` 方法
4. **实现任务 4**：修改 `clearHeadingFormat()` 方法
5. **测试验证**：运行单元测试和集成测试

## 调试日志

调试日志已经添加到以下方法：
- `updateCurrentFormats()` - 显示完整的格式检测流程
- `detectFontFormats()` - 显示字体大小判断的详细过程
- `detectParagraphStyleFromFormats()` - 显示段落样式转换过程

这些日志将帮助你验证修复是否正确。
