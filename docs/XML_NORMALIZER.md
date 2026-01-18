# XMLNormalizer 技术文档

## 概述

XMLNormalizer 是一个用于规范化 XML 内容的组件,主要用于解决笔记内容比较时的格式差异问题。通过将不同格式的 XML 内容规范化为统一格式,可以准确识别实际的内容变化,避免因格式差异导致的误判。

## 设计目标

1. **语义比较优先**：比较内容的语义,而不是字符串表示
2. **保守更新策略**：有疑问时保持原时间戳
3. **向后兼容**：兼容所有现有的 XML 格式
4. **高性能**：规范化耗时 < 10ms

## 核心功能

### 1. 图片格式规范化

#### 问题背景
小米笔记的图片格式经历了多个版本的演变:
- **旧版格式**：`☺ <fileId><0/><description/>` 或 `☺ <fileId><imgshow/><description/>`
- **新版格式**：`<img fileid="<fileId>" imgdes="<description>" imgshow="<show>" width="<width>" height="<height>" />`

这导致相同的图片在不同时间保存时可能使用不同的格式,从而被误判为内容变化。

#### 解决方案
将所有图片格式统一为规范化的新版格式:
```xml
<img fileid="<fileId>" imgdes="<description>" imgshow="<show>" />
```

**规范化规则**:
1. 识别旧版格式并转换为新版格式
2. 移除尺寸属性（width, height）,因为它们可能因渲染而变化
3. 保留所有有语义的属性（fileid, imgdes, imgshow）
4. 统一属性顺序（按字母顺序：fileid → imgdes → imgshow）
5. 保留空值属性（如 `imgdes=""`）

#### 实现细节
```swift
private func normalizeImageFormat(_ xml: String) -> String {
    // 1. 处理旧版图片格式
    let oldFormatPattern = "☺\\s+([^<]+)<(0|imgshow)\\s*/><([^>]*)\\s*/>"
    // 转换为新版格式
    
    // 2. 处理新版图片格式
    let newFormatPattern = "<img\\s+([^>]+?)\\s*/>"
    // 移除尺寸属性,统一属性顺序
}
```

### 2. 空格和换行规范化

#### 问题背景
XML 内容中的空格和换行符可能因编辑器、操作系统或保存方式的不同而产生差异:
- 标签之间的空格数量不同
- 换行符类型不同（\n vs \r\n）
- 多余的空白字符

#### 解决方案
规范化所有空白字符:
1. 标签之间的空白字符规范化为单个空格
2. 标签内的文本内容保持不变（保留有意义的空格）
3. 移除字符串开头和结尾的空白字符

#### 实现细节
```swift
private func removeExtraWhitespace(_ xml: String) -> String {
    var result = ""
    var insideTag = false
    var insideQuotes = false
    var lastCharWasWhitespace = false
    
    for char in xml {
        // 处理引号、标签、空白字符
        // 在标签之间规范化空白为单个空格
        // 在标签内保留空格
    }
    
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

### 3. 属性顺序规范化

#### 问题背景
XML 标签的属性顺序可能不同,但语义相同:
```xml
<img width="500" fileid="123" height="666" />
<img fileid="123" height="666" width="500" />
```

#### 解决方案
将所有标签的属性按字母顺序排序:
```xml
<img fileid="123" height="666" width="500" />
```

#### 实现细节
```swift
private func normalizeAttributeOrder(_ xml: String) -> String {
    // 1. 匹配所有 XML 标签
    let tagPattern = "<(\\w+)\\s+([^>]+?)(\\s*/?)>"
    
    // 2. 解析属性
    let attrPattern = "(\\w+)\\s*=\\s*\"([^\"]*)\""
    
    // 3. 按字母顺序排序
    attributes.sort { $0.0 < $1.0 }
    
    // 4. 重新组装标签
}
```

### 4. 属性值规范化

#### 问题背景
属性值可能有不同的表示方式:
- 数字前导零：`indent="01"` vs `indent="1"`
- 布尔值表示：`"0"/"1"` vs `"false"/"true"`

#### 解决方案
统一属性值的表示方式:
1. 移除数字前导零（但保留有意义的 "0"）
2. 统一布尔值表示（小米笔记使用 "0"/"1"）

#### 实现细节
```swift
private func normalizeAttributeValues(_ xml: String) -> String {
    // 移除数字前导零
    let numberAttrPattern = "(\\w+)\\s*=\\s*\"0+(\\d+)\""
    // 替换为不带前导零的数字
}
```

## 使用方法

### 基本用法
```swift
let normalizer = XMLNormalizer.shared
let normalizedXML = normalizer.normalize(originalXML)
```

### 在内容变化检测中使用
```swift
private func hasContentActuallyChanged(
    currentContent: String,
    savedContent: String,
    currentTitle: String,
    originalTitle: String
) -> Bool {
    // 使用 XMLNormalizer 进行语义比较
    let normalizedCurrent = XMLNormalizer.shared.normalize(currentContent)
    let normalizedSaved = XMLNormalizer.shared.normalize(savedContent)
    
    let contentChanged = normalizedCurrent != normalizedSaved
    let titleChanged = currentTitle != originalTitle
    
    return contentChanged || titleChanged
}
```

## 性能考虑

### 性能目标
- XML 规范化耗时 < 10ms
- 不影响笔记切换性能

### 性能优化策略
1. **高效的正则表达式**：使用优化的正则表达式模式
2. **从后往前替换**：避免索引变化问题
3. **性能监控**：记录规范化耗时,超过阈值时警告

### 性能监控
```swift
func normalize(_ xml: String) -> String {
    let startTime = CFAbsoluteTimeGetCurrent()
    
    // 规范化操作
    
    let elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
    
    if elapsedTime > 10 {
        print("[XMLNormalizer] ⚠️ 规范化耗时超过阈值: \(String(format: "%.2f", elapsedTime))ms")
    }
    
    return normalized
}
```

## 测试覆盖

### 单元测试
项目包含 27 个单元测试,覆盖以下场景:

#### 图片格式测试（11 个）
- 旧版格式转换（带 `<0/>` 标签）
- 旧版格式转换（带 `<imgshow/>` 标签）
- 新版格式规范化（移除尺寸属性）
- 混合格式处理
- 空值属性保留
- 特殊字符处理
- 性能测试

#### 空格处理测试（8 个）
- 移除标签之间的多余空格
- 保留标签内的有意义空格
- 移除多余的换行符
- 移除开头和结尾的空白字符
- 属性值中的空格保留
- 混合空白字符处理
- 自闭合标签前后的空白
- 复杂嵌套结构的空白处理

#### 属性顺序测试（3 个）
- 属性顺序规范化
- 多个标签的属性顺序规范化
- 自闭合标签的属性顺序规范化

#### 属性值测试（3 个）
- 移除数字前导零
- 保留有意义的零
- 保留空值属性

#### 综合测试（2 个）
- 完整的规范化流程
- 幂等性测试（规范化两次应得到相同结果）

### 测试示例
```swift
func testNormalizeOldImageFormatWithZero() async throws {
    let input = "☺ 1315204657.mqD6sEiru5CFpGR0vUZaMA<0/><\/>"
    let result = normalizer.normalize(input)
    let expected = "<img fileid=\"1315204657.mqD6sEiru5CFpGR0vUZaMA\" imgdes=\"\" imgshow=\"0\" />"
    XCTAssertEqual(result, expected)
}

func testNormalizationIdempotence() async throws {
    let input = "<img imgshow=\"0\" width=\"500\" fileid=\"123\" height=\"666\" imgdes=\"测试\" />"
    let result1 = normalizer.normalize(input)
    let result2 = normalizer.normalize(result1)
    XCTAssertEqual(result1, result2, "规范化应该是幂等的")
}
```

## 正确性属性

### 属性 1：幂等性
对同一个 XML 内容多次规范化,结果应该相同:
```
∀ xml: String,
  normalize(xml) == normalize(normalize(xml))
```

### 属性 2：语义等价性
语义相同但格式不同的 XML,规范化后应该相同:
```
∀ xml1, xml2: String,
  semanticallyEqual(xml1, xml2) ⟹ normalize(xml1) == normalize(xml2)
```

### 属性 3：时间戳保持不变
仅查看笔记（无编辑）时,时间戳应保持不变:
```
∀ note: Note,
  viewOnly(note) ⟹ note.updatedAt_before == note.updatedAt_after
```

### 属性 4：实际编辑更新时间戳
实际编辑笔记时,时间戳应该更新:
```
∀ note: Note,
  actualEdit(note) ⟹ note.updatedAt_after > note.updatedAt_before
```

## 错误处理

### 解析错误
如果 XML 格式不正确,无法解析:
- 记录错误日志
- 返回原始内容（保守策略）

### 规范化失败
如果规范化过程中出现异常:
- 记录错误日志
- 返回原始内容（保守策略）

### 性能超时
如果规范化耗时超过阈值:
- 记录警告日志
- 返回规范化结果（但提示性能问题）

## 向后兼容性

### 兼容性保证
- 兼容所有现有的 XML 格式（旧版和新版）
- 不影响现有的保存和同步逻辑
- 不改变现有的数据结构

### 迁移策略
- 无需数据迁移
- 新旧代码可以共存
- 逐步替换旧的内容比较逻辑

## 监控和日志

### 关键日志点
1. XML 规范化开始和结束
2. 内容变化检测结果
3. 时间戳更新决策
4. 性能指标（耗时）

### 日志格式
```
[内容检测] ═══════════════════════════════════════
[内容检测] 📊 检测结果: 内容变化=false, 标题变化=false
[内容检测] 📏 原始内容长度: 当前=122, 保存=103
[内容检测] 📏 规范化后长度: 当前=122, 保存=122
[内容检测] ⏱️ 检测耗时: 5.23ms
[内容检测] ✅ 内容无变化（规范化后相同）
[内容检测] ℹ️ 原始内容有差异（19 字符），但规范化后相同 - 这是格式化差异
[内容检测] 🕐 时间戳决策: 保持不变
[内容检测] ═══════════════════════════════════════
```

## 未来扩展

### 支持更多格式差异
- 音频附件格式差异
- 列表格式差异
- 表格格式差异

### 智能内容比较
- 使用语义分析而不是字符串比较
- 支持更复杂的内容变化检测

### 用户可配置
- 允许用户配置是否自动更新时间戳
- 允许用户配置内容比较的敏感度

## 参考资料

- [Spec 57: 笔记查看时时间戳保持不变](../.kiro/specs/57-note-view-timestamp-preservation/requirements.md)
- [设计文档](../.kiro/specs/57-note-view-timestamp-preservation/design.md)
- [任务列表](../.kiro/specs/57-note-view-timestamp-preservation/tasks.md)
- [进度报告](../.kiro/specs/57-note-view-timestamp-preservation/PROGRESS_REPORT.md)

## 总结

XMLNormalizer 是一个关键组件,通过规范化 XML 内容,实现了基于语义的内容比较,解决了因格式差异导致的时间戳误更新问题。该组件设计精良,性能优秀,测试覆盖全面,为笔记应用提供了可靠的内容变化检测能力。
