





# 原生富文本编辑器设计文档

## 概述

本设计文档基于已批准的需求文档，详细描述了使用 SwiftUI TextEditor、NSTextView 和自定义渲染技术实现原生富文本编辑器的技术架构。该编辑器将 1:1 复刻 Apple Notes 的原生体验，同时保持与小米笔记 XML 格式的完全兼容性。

## 设计原则

### 1. 原生体验优先
- 使用 SwiftUI TextEditor 作为基础编辑器，提供原生的文本编辑体验
- 利用 NSTextAttachment 和自定义渲染实现特殊元素（复选框、分割线、引用块）
- 遵循 Apple Human Interface Guidelines，确保与系统一致的交互体验

### 2. 格式兼容性
- 严格遵循小米笔记 XML 格式规范，确保 100% 兼容性
- 实现双向转换：AttributedString ↔ XiaoMi XML
- 保持现有 Web 编辑器的所有功能特性

### 3. 性能优化
- 使用 AttributedString 的原生性能优势
- 自定义渲染器采用按需绘制策略
- 优化大文档的滚动和编辑性能

## 核心架构

### 系统架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    用户界面层 (SwiftUI)                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   设置界面       │  │   工具栏        │  │   编辑器视图     │ │
│  │ EditorSettings  │  │  Toolbar       │  │ NativeEditor    │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    编辑器管理层                               │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ EditorContext   │  │ FormatManager   │  │ StateManager    │ │
│  │ 编辑器上下文     │  │ 格式管理器       │  │ 状态管理器       │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    渲染和转换层                               │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ CustomRenderer  │  │ FormatConverter │  │ AttachmentMgr   │ │
│  │ 自定义渲染器     │  │ 格式转换器       │  │ 附件管理器       │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    数据存储层                                 │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ AttributedString│  │ XiaoMi XML      │  │ Local Storage   │ │
│  │ 原生富文本格式   │  │ 小米笔记格式     │  │ 本地存储        │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 核心组件设计

### 1. NativeEditorView (SwiftUI 视图)

**职责：** 主编辑器视图，集成 TextEditor 和自定义渲染

**关键特性：**
- 基于 SwiftUI TextEditor 构建
- 集成 NSTextView 的高级功能
- 支持自定义 NSTextAttachment
- 处理用户交互和格式应用

```swift
struct NativeEditorView: View {
    @StateObject private var editorContext: NativeEditorContext
    @State private var attributedText: AttributedString
    
    var body: some View {
        TextEditor(text: $attributedText)
            .textEditorStyle(.plain)
            .onReceive(editorContext.formatChangePublisher) { format in
                applyFormat(format)
            }
    }
}
```
### 2. NativeEditorContext (编辑器上下文)

**职责：** 管理编辑器状态、格式应用和用户交互

**关键特性：**
- 跟踪光标位置和选择范围
- 管理当前格式状态
- 处理格式命令和快捷键
- 与工具栏同步状态

```swift
@MainActor
class NativeEditorContext: ObservableObject {
    @Published var currentFormats: Set<TextFormat> = []
    @Published var cursorPosition: Int = 0
    @Published var selectedRange: NSRange = NSRange(location: 0, length: 0)
    
    private let formatManager: FormatManager
    private let customRenderer: CustomRenderer
    
    func applyFormat(_ format: TextFormat) {
        // 应用格式到选中文本
    }
    
    func insertSpecialElement(_ element: SpecialElement) {
        // 插入特殊元素（复选框、分割线等）
    }
}
```

### 3. CustomRenderer (自定义渲染器)

**职责：** 渲染特殊元素，如复选框、分割线、引用块

**关键特性：**
- 基于 NSTextAttachment 实现
- 支持交互式元素（如可点击的复选框）
- 适配深色/浅色模式
- 优化渲染性能

```swift
class CustomRenderer {
    func createCheckboxAttachment(checked: Bool, level: Int) -> NSTextAttachment {
        let attachment = InteractiveCheckboxAttachment()
        attachment.isChecked = checked
        attachment.level = level
        return attachment
    }
    
    func createHorizontalRuleAttachment() -> NSTextAttachment {
        let attachment = HorizontalRuleAttachment()
        attachment.bounds = CGRect(x: 0, y: 0, width: 300, height: 1)
        return attachment
    }
    
    func createQuoteBlockRenderer() -> NSLayoutManager {
        // 自定义 NSLayoutManager 用于引用块背景渲染
    }
}
```

### 4. FormatConverter (格式转换器)

**职责：** 在 AttributedString 和小米笔记 XML 格式之间转换

**关键特性：**
- 双向转换支持
- 严格遵循小米笔记格式规范
- 处理复杂嵌套格式
- 错误处理和数据验证

```swift
class XiaoMiFormatConverter {
    func attributedStringToXML(_ attributedString: AttributedString) -> String {
        // 将 AttributedString 转换为小米笔记 XML 格式
    }
    
    func xmlToAttributedString(_ xml: String) -> AttributedString {
        // 将小米笔记 XML 转换为 AttributedString
    }
    
    private func processTextElement(_ element: XMLElement) -> AttributedString {
        // 处理 <text> 元素
    }
    
    private func processSpecialElement(_ element: XMLElement) -> NSTextAttachment {
        // 处理特殊元素（bullet, order, checkbox, hr 等）
    }
}
```
## 特殊元素实现设计

### 1. 复选框 (Checkbox) 实现

**技术方案：** 使用自定义 NSTextAttachment 子类

```swift
class InteractiveCheckboxAttachment: NSTextAttachment {
    var isChecked: Bool = false
    var level: Int = 3
    var onToggle: ((Bool) -> Void)?
    
    override func image(forBounds imageBounds: NSRect, 
                       textContainer: NSTextContainer?, 
                       characterIndex charIndex: Int) -> NSImage? {
        return createCheckboxImage(checked: isChecked, level: level)
    }
    
    private func createCheckboxImage(checked: Bool, level: Int) -> NSImage {
        // 根据选中状态和级别创建复选框图像
        // 支持深色/浅色模式适配
    }
}
```

**交互处理：**
- 通过 NSTextView 的点击事件检测
- 更新复选框状态但不保存到 XML（仅编辑器显示）
- 提供视觉反馈和动画效果

### 2. 分割线 (Horizontal Rule) 实现

**技术方案：** 自定义 NSTextAttachment 绘制水平线

```swift
class HorizontalRuleAttachment: NSTextAttachment {
    override func image(forBounds imageBounds: NSRect, 
                       textContainer: NSTextContainer?, 
                       characterIndex charIndex: Int) -> NSImage? {
        return createHorizontalRuleImage(bounds: imageBounds)
    }
    
    private func createHorizontalRuleImage(bounds: NSRect) -> NSImage {
        // 创建水平分割线图像
        // 适配当前主题颜色
    }
}
```

### 3. 引用块 (Quote Block) 实现

**技术方案：** 自定义 NSLayoutManager 绘制背景和边框

```swift
class QuoteBlockLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, 
                                at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        
        // 绘制引用块的左侧边框和背景色
        drawQuoteBlockBackground(for: glyphsToShow, at: origin)
    }
    
    private func drawQuoteBlockBackground(for range: NSRange, at origin: NSPoint) {
        // 实现引用块的视觉样式
    }
}
```

## 格式转换详细设计

### 1. XML 到 AttributedString 转换

**转换流程：**
1. 解析 XML 结构
2. 识别元素类型（text, bullet, order, checkbox, hr, quote, img）
3. 创建对应的 AttributedString 片段或 NSTextAttachment
4. 合并为完整的 AttributedString

**关键转换规则：**

```swift
// 文本元素转换
func convertTextElement(_ element: XMLElement) -> AttributedString {
    let indent = element.attribute("indent")?.intValue ?? 1
    let content = element.stringValue ?? ""
    
    var attributes = AttributeContainer()
    attributes.paragraphStyle = createParagraphStyle(indent: indent)
    
    // 处理富文本标签
    let richText = processRichTextTags(content)
    return AttributedString(richText, attributes: attributes)
}

// 特殊元素转换
func convertSpecialElement(_ element: XMLElement) -> NSTextAttachment {
    switch element.name {
    case "bullet":
        return customRenderer.createBulletAttachment(
            indent: element.attribute("indent")?.intValue ?? 1
        )
    case "order":
        return customRenderer.createOrderAttachment(
            indent: element.attribute("indent")?.intValue ?? 1,
            number: element.attribute("inputNumber")?.intValue ?? 0
        )
    case "input":
        return customRenderer.createCheckboxAttachment(
            checked: false, // XML 中不保存选中状态
            level: element.attribute("level")?.intValue ?? 3
        )
    case "hr":
        return customRenderer.createHorizontalRuleAttachment()
    default:
        return NSTextAttachment()
    }
}
```
### 2. AttributedString 到 XML 转换

**转换流程：**
1. 遍历 AttributedString 的所有字符和属性
2. 识别文本片段和 NSTextAttachment
3. 根据属性和附件类型生成对应的 XML 元素
4. 处理缩进、对齐和富文本格式

**关键转换规则：**

```swift
func convertAttributedStringToXML(_ attributedString: AttributedString) -> String {
    var xmlElements: [String] = []
    
    attributedString.runs.forEach { run in
        if let attachment = run.attachment {
            // 处理特殊元素
            xmlElements.append(convertAttachmentToXML(attachment))
        } else {
            // 处理文本元素
            xmlElements.append(convertTextRunToXML(run))
        }
    }
    
    return xmlElements.joined(separator: "\n")
}

func convertTextRunToXML(_ run: AttributedString.Run) -> String {
    let text = String(run.characters)
    let indent = extractIndentFromParagraphStyle(run.paragraphStyle) ?? 1
    let alignment = extractAlignmentFromParagraphStyle(run.paragraphStyle)
    
    var content = processRichTextAttributes(text, attributes: run.attributes)
    
    // 处理对齐方式
    if alignment == .center {
        content = "<center>\(content)</center>"
    } else if alignment == .right {
        content = "<right>\(content)</right>"
    }
    
    return "<text indent=\"\(indent)\">\(content)</text>"
}
```

## 编辑器选择系统设计

### 1. 设置界面设计

**用户界面：**
- 在应用设置中添加"编辑器"选项卡
- 提供原生编辑器和 Web 编辑器的选择
- 显示各编辑器的特性对比
- 提供系统兼容性检查

```swift
struct EditorSettingsView: View {
    @AppStorage("selectedEditor") private var selectedEditor: EditorType = .native
    @State private var isNativeEditorSupported: Bool = false
    
    var body: some View {
        Form {
            Section("编辑器选择") {
                Picker("默认编辑器", selection: $selectedEditor) {
                    Text("原生编辑器").tag(EditorType.native)
                        .disabled(!isNativeEditorSupported)
                    Text("Web 编辑器").tag(EditorType.web)
                }
                .pickerStyle(.radioGroup)
            }
            
            Section("编辑器特性对比") {
                EditorComparisonView()
            }
        }
        .onAppear {
            checkNativeEditorSupport()
        }
    }
}
```

### 2. 编辑器工厂模式

**设计模式：** 使用工厂模式创建不同类型的编辑器

```swift
protocol EditorProtocol {
    func loadContent(_ content: String)
    func getContent() -> String
    func applyFormat(_ format: TextFormat)
}

class EditorFactory {
    static func createEditor(type: EditorType) -> EditorProtocol {
        switch type {
        case .native:
            return NativeEditor()
        case .web:
            return WebEditor()
        }
    }
}

class NoteEditorCoordinator: ObservableObject {
    @Published var currentEditor: EditorProtocol
    
    init() {
        let editorType = UserDefaults.standard.editorType
        self.currentEditor = EditorFactory.createEditor(type: editorType)
    }
    
    func switchEditor(to type: EditorType) {
        let content = currentEditor.getContent()
        currentEditor = EditorFactory.createEditor(type: type)
        currentEditor.loadContent(content)
    }
}
```
## 性能优化设计

### 1. 渲染性能优化

**策略：**
- 使用视图回收机制减少内存占用
- 实现增量渲染，只更新变化的部分
- 优化 NSTextAttachment 的图像缓存

```swift
class PerformanceOptimizedRenderer {
    private var attachmentCache: [String: NSTextAttachment] = [:]
    private var imageCache: [String: NSImage] = [:]
    
    func getCachedAttachment(for key: String, 
                           factory: () -> NSTextAttachment) -> NSTextAttachment {
        if let cached = attachmentCache[key] {
            return cached
        }
        
        let attachment = factory()
        attachmentCache[key] = attachment
        return attachment
    }
    
    func optimizeForLargeDocuments(_ attributedString: AttributedString) {
        // 对大文档进行分段处理
        // 实现虚拟化滚动
    }
}
```

### 2. 内存管理优化

**策略：**
- 及时释放不再使用的 NSTextAttachment
- 使用弱引用避免循环引用
- 实现图片的懒加载机制

### 3. 转换性能优化

**策略：**
- 缓存转换结果避免重复计算
- 使用异步转换处理大文档
- 实现增量转换机制

## 错误处理和回退机制

### 1. 初始化失败处理

```swift
class NativeEditorInitializer {
    static func initializeNativeEditor() -> Result<NativeEditor, EditorError> {
        // 检查系统版本兼容性
        guard #available(macOS 13.0, *) else {
            return .failure(.systemVersionNotSupported)
        }
        
        // 检查必要的框架可用性
        guard NSClassFromString("NSTextAttachment") != nil else {
            return .failure(.frameworkNotAvailable)
        }
        
        do {
            let editor = try NativeEditor()
            return .success(editor)
        } catch {
            return .failure(.initializationFailed(error))
        }
    }
}
```

### 2. 渲染失败回退

```swift
class SafeRenderer {
    func renderWithFallback(_ element: SpecialElement) -> NSTextAttachment {
        do {
            return try customRenderer.render(element)
        } catch {
            // 回退到基础文本显示
            return createFallbackTextAttachment(for: element)
        }
    }
    
    private func createFallbackTextAttachment(for element: SpecialElement) -> NSTextAttachment {
        // 创建简单的文本替代显示
    }
}
```

### 3. 转换错误处理

```swift
class RobustFormatConverter {
    func convertWithValidation(_ xml: String) -> Result<AttributedString, ConversionError> {
        do {
            let attributedString = try xmlToAttributedString(xml)
            
            // 验证转换结果
            let backConverted = try attributedStringToXML(attributedString)
            guard isEquivalent(original: xml, converted: backConverted) else {
                return .failure(.conversionInconsistent)
            }
            
            return .success(attributedString)
        } catch {
            return .failure(.conversionFailed(error))
        }
    }
}
```

## 测试策略

### 1. 单元测试

**测试范围：**
- 格式转换器的双向转换准确性
- 自定义渲染器的各种元素渲染
- 编辑器上下文的状态管理

### 2. 集成测试

**测试场景：**
- 完整的编辑-保存-加载流程
- 不同编辑器之间的切换
- 复杂文档的性能表现

### 3. 用户界面测试

**测试内容：**
- 各种格式操作的正确性
- 特殊元素的交互行为
- 键盘快捷键的响应

## 部署和迁移策略

### 1. 渐进式部署

**阶段 1：** 基础功能实现
- 文本编辑和基本格式
- 简单的特殊元素（分割线）
- 基础的格式转换

**阶段 2：** 高级功能实现
- 复选框和列表
- 引用块和图片
- 完整的格式转换

**阶段 3：** 优化和完善
- 性能优化
- 错误处理完善
- 用户体验优化

### 2. 数据迁移

**策略：**
- 保持现有数据格式不变
- 提供数据验证和修复工具
- 支持回退到 Web 编辑器

## 正确性属性

基于需求分析，定义以下正确性属性：

### 1. 格式保真性
- **属性：** 任何通过原生编辑器编辑的内容，转换为 XML 后再转换回 AttributedString，应与原始内容在视觉上完全一致
- **验证：** `isVisuallyEquivalent(original, roundTrip(original)) == true`

### 2. 小米笔记兼容性
- **属性：** 生成的 XML 格式必须严格符合小米笔记规范，能够在小米笔记客户端正确显示
- **验证：** 所有 XML 元素和属性都符合小米笔记格式示例

### 3. 交互一致性
- **属性：** 原生编辑器的所有交互行为应与 Apple Notes 保持一致
- **验证：** 用户操作的响应和视觉反馈符合 Apple HIG 标准

### 4. 性能要求
- **属性：** 编辑器初始化时间 < 100ms，大文档（>1000行）滚动帧率 > 60fps
- **验证：** 性能基准测试通过

这个设计为原生富文本编辑器提供了完整的技术架构，确保能够实现所有需求中定义的功能，同时保持高性能和良好的用户体验。