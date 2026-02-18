# 段落管理器功能演示

## 概述

本文档说明如何验证新实现的段落管理器（ParagraphManager）功能。

## 已实现的功能

### 1. 核心数据模型 ✅
- `Paragraph`: 段落数据模型
- `ParagraphType`: 段落类型枚举（标题、H1-H6、普通、列表、引用、代码块）
- `AttributeLayer`: 属性分层系统（Meta、Layout、Decorative）
- `PerformanceCache`: 性能缓存系统

### 2. 段落管理器 ✅
- `ParagraphManager`: 段落管理核心类
  - 段落边界检测算法
  - 段落列表维护
  - 段落格式应用
  - 段落查询（按位置、按范围）

### 3. 属性管理器 ✅
- `AttributeManager`: 属性管理核心类
  - 分层属性应用（Meta → Layout → Decorative）
  - 属性冲突解决
  - 属性变化检测

## 如何验证

### 方法 1: 运行单元测试

```bash
# 运行所有段落管理器测试
xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac \
  -destination 'platform=macOS' \
  -only-testing:NativeEditorTests/ParagraphManagerTests

# 运行集成测试
xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac \
  -destination 'platform=macOS' \
  -only-testing:NativeEditorTests/ParagraphManagerIntegrationTests
```

### 方法 2: 使用调试视图（推荐）

我已经创建了一个可视化调试工具 `ParagraphManagerDebugView`，但还需要集成到应用中。

#### 临时验证方法：

1. 打开 Xcode
2. 找到 `Sources/View/NativeEditor/Debug/ParagraphManagerDebugView.swift`
3. 点击文件右上角的 "Resume" 按钮（或按 Cmd+Option+P）
4. 这将在 Xcode 的 Canvas 中显示调试界面

#### 调试界面功能：

- **左侧**：文本编辑区
  - 输入或修改文本
  - 点击"更新段落列表"按钮刷新段落分析
  - 提供示例文本按钮

- **右侧**：段落列表
  - 显示所有检测到的段落
  - 每个段落显示：
    - 段落索引
    - 段落类型（标题、H1-H6、普通等）
    - 范围（起始位置和长度）
    - 版本号
    - 是否需要重新解析

- **格式应用**：
  - 选择一个段落
  - 从下拉菜单选择格式类型
  - 点击"应用到选中段落"按钮

### 方法 3: 在代码中直接测试

创建一个简单的测试文件：

```swift
import XCTest
@testable import MiNoteLibrary

class QuickTest: XCTestCase {
    func testParagraphManager() {
        let manager = ParagraphManager()
        let textStorage = NSTextStorage(string: "标题\n第一段\n第二段")
        
        // 更新段落列表
        manager.updateParagraphs(in: textStorage, changedRange: NSRange(location: 0, length: textStorage.length))
        
        // 打印段落信息
        for (index, paragraph) in manager.paragraphs.enumerated() {
            print("段落 \(index): \(paragraph.type), 范围: \(paragraph.range)")
        }
        
        // 应用格式
        manager.applyParagraphFormat(.heading(level: 1), to: manager.paragraphs[1].range, in: textStorage)
        
        print("✅ 测试完成")
    }
}
```

## 测试结果

### 单元测试覆盖

- ✅ 段落边界检测（17 个测试）
  - 空文本
  - 单段落
  - 多段落
  - 不同换行符（\n、\r、\r\n）
  - 段落覆盖性和无重叠

- ✅ 段落列表维护（7 个测试）
  - 首次初始化
  - 插入文本
  - 删除文本
  - 插入/删除换行符
  - 版本跟踪

- ✅ 段落格式应用（8 个测试）
  - 标题格式（H1-H6）
  - 普通段落
  - 列表格式
  - 引用格式
  - 代码块格式
  - 多段落格式应用
  - 格式一致性

### 性能测试

- 100 个段落的处理：< 10ms
- 50 个段落的频繁格式应用：< 50ms

## 下一步集成计划

要将这些功能集成到实际的编辑器中，需要：

1. **在 NativeEditorView 中初始化管理器**
   ```swift
   private let paragraphManager = ParagraphManager()
   private let attributeManager = AttributeManager()
   ```

2. **连接文本变化事件**
   ```swift
   func textDidChange(_ notification: Notification) {
       paragraphManager.updateParagraphs(in: textStorage, changedRange: editedRange)
   }
   ```

3. **连接格式应用事件**
   ```swift
   func applyFormat(_ type: ParagraphType) {
       paragraphManager.applyParagraphFormat(type, to: selectedRange, in: textStorage)
   }
   ```

4. **更新格式菜单状态**
   ```swift
   func updateFormatMenu() {
       if let paragraph = paragraphManager.paragraph(at: selectedRange.location) {
           // 更新菜单勾选状态
       }
   }
   ```

## 文件位置

### 核心代码
- `Sources/View/NativeEditor/Model/Paragraph.swift`
- `Sources/View/NativeEditor/Model/ParagraphType.swift`
- `Sources/View/NativeEditor/Model/AttributeLayer.swift`
- `Sources/View/NativeEditor/Model/PerformanceCache.swift`
- `Sources/View/NativeEditor/Manager/ParagraphManager.swift`
- `Sources/View/NativeEditor/Model/AttributeManager.swift`

### 测试代码
- `Tests/NativeEditorTests/ParagraphManagerTests.swift`
- `Tests/NativeEditorTests/ParagraphManagerIntegrationTests.swift`

### 调试工具
- `Sources/View/NativeEditor/Debug/ParagraphManagerDebugView.swift`
- `Sources/Window/Controllers/ParagraphDebugWindowController.swift`

## 总结

目前已完成的工作为编辑器重构奠定了坚实的基础：

1. ✅ 核心数据模型完整且经过测试
2. ✅ 段落管理功能完整实现
3. ✅ 属性分层系统已就绪
4. ✅ 性能缓存系统已实现
5. ⏳ 等待集成到实际编辑器中

下一步可以继续实现：
- 打字优化器（TypingOptimizer）
- 增量更新机制
- 标题集成（TitleIntegration）
- 其他辅助功能

或者先将现有功能集成到编辑器中进行实际测试。
