# 统一格式菜单设计文档

## 概述

本设计文档描述统一格式菜单系统的架构设计，该系统为原生编辑器和 Web 编辑器提供一致的格式菜单体验，支持工具栏菜单和菜单栏菜单两种显示位置。

## 架构设计

### 核心组件

```
┌─────────────────────────────────────────────────────────────────┐
│                    FormatMenuProvider (协议)                      │
│  - 统一的格式状态获取和应用接口                                      │
│  - 处理互斥规则和格式切换逻辑                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│  NativeFormatProvider   │     │   WebFormatProvider     │
│  (原生编辑器实现)         │     │   (Web 编辑器实现)       │
└─────────────────────────┘     └─────────────────────────┘
              │                               │
              └───────────────┬───────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FormatStateManager                            │
│  - 管理当前格式状态                                                │
│  - 发布状态变化通知                                                │
│  - 同步工具栏和菜单栏状态                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│   ToolbarFormatMenu     │     │   MenuBarFormatMenu     │
│   (工具栏格式菜单)        │     │   (菜单栏格式菜单)       │
└─────────────────────────┘     └─────────────────────────┘
```

### 格式分类

#### 1. 段落级格式（互斥组）

| 格式 | 标识符 | 说明 |
|------|--------|------|
| 大标题 | `heading1` | 一级标题 |
| 二级标题 | `heading2` | 二级标题 |
| 三级标题 | `heading3` | 三级标题 |
| 正文 | `body` | 默认段落样式 |
| 无序列表 | `bulletList` | 项目符号列表 |
| 有序列表 | `numberedList` | 编号列表 |
| 复选框 | `checkbox` | 待办事项列表 |

**互斥规则**：以上格式互斥，同一段落只能有一种格式。列表格式视为"带列表标记的正文"，无法与标题格式共存。

#### 2. 对齐格式（互斥组）

| 格式 | 标识符 | 说明 |
|------|--------|------|
| 左对齐 | `alignLeft` | 默认对齐方式 |
| 居中 | `alignCenter` | 居中对齐 |
| 右对齐 | `alignRight` | 右对齐 |

**互斥规则**：以上格式互斥，同一段落只能有一种对齐方式。

#### 3. 字符级格式（可叠加）

| 格式 | 标识符 | 说明 |
|------|--------|------|
| 加粗 | `bold` | 粗体文本 |
| 斜体 | `italic` | 斜体文本 |
| 下划线 | `underline` | 下划线文本 |
| 删除线 | `strikethrough` | 删除线文本 |
| 高亮 | `highlight` | 高亮背景 |

**叠加规则**：以上格式可以同时应用到同一文本。

#### 4. 独立格式

| 格式 | 标识符 | 说明 |
|------|--------|------|
| 引用块 | `quote` | 引用块样式，独立于段落格式 |

## 数据结构设计

### FormatState 结构体

```swift
/// 格式状态结构体
/// 表示当前光标或选择处的完整格式状态
struct FormatState: Equatable {
    // MARK: - 段落级格式
    
    /// 当前段落格式（互斥）
    var paragraphFormat: ParagraphFormat = .body
    
    // MARK: - 对齐格式
    
    /// 当前对齐方式（互斥）
    var alignment: AlignmentFormat = .left
    
    // MARK: - 字符级格式（可叠加）
    
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false
    var isStrikethrough: Bool = false
    var isHighlight: Bool = false
    
    // MARK: - 独立格式
    
    var isQuote: Bool = false
    
    // MARK: - 选择模式信息
    
    /// 是否有选中文本
    var hasSelection: Bool = false
    
    /// 选择范围长度
    var selectionLength: Int = 0
}

/// 段落格式枚举
enum ParagraphFormat: String, CaseIterable {
    case heading1 = "heading1"      // 大标题
    case heading2 = "heading2"      // 二级标题
    case heading3 = "heading3"      // 三级标题
    case body = "body"              // 正文
    case bulletList = "bulletList"  // 无序列表
    case numberedList = "numberedList"  // 有序列表
    case checkbox = "checkbox"      // 复选框
    
    var displayName: String {
        switch self {
        case .heading1: return "大标题"
        case .heading2: return "二级标题"
        case .heading3: return "三级标题"
        case .body: return "正文"
        case .bulletList: return "无序列表"
        case .numberedList: return "有序列表"
        case .checkbox: return "复选框"
        }
    }
    
    /// 是否是标题格式
    var isHeading: Bool {
        switch self {
        case .heading1, .heading2, .heading3: return true
        default: return false
        }
    }
    
    /// 是否是列表格式
    var isList: Bool {
        switch self {
        case .bulletList, .numberedList, .checkbox: return true
        default: return false
        }
    }
}

/// 对齐格式枚举
enum AlignmentFormat: String, CaseIterable {
    case left = "left"
    case center = "center"
    case right = "right"
    
    var displayName: String {
        switch self {
        case .left: return "左对齐"
        case .center: return "居中"
        case .right: return "右对齐"
        }
    }
}
```

### FormatMenuProvider 协议

```swift
/// 格式菜单提供者协议
/// 统一原生编辑器和 Web 编辑器的格式操作接口
@MainActor
protocol FormatMenuProvider: AnyObject {
    
    // MARK: - 状态获取
    
    /// 获取当前格式状态
    /// - Returns: 当前格式状态
    func getCurrentFormatState() -> FormatState
    
    /// 检查指定格式是否激活
    /// - Parameter format: 格式类型
    /// - Returns: 是否激活
    func isFormatActive(_ format: TextFormat) -> Bool
    
    // MARK: - 格式应用
    
    /// 应用格式
    /// - Parameter format: 要应用的格式
    /// - Note: 自动处理互斥规则
    func applyFormat(_ format: TextFormat)
    
    /// 切换格式
    /// - Parameter format: 要切换的格式
    /// - Note: 如果格式已激活则移除，否则应用
    func toggleFormat(_ format: TextFormat)
    
    /// 清除段落格式（恢复为正文）
    func clearParagraphFormat()
    
    /// 清除对齐格式（恢复为左对齐）
    func clearAlignmentFormat()
    
    // MARK: - 状态发布
    
    /// 格式状态变化发布者
    var formatStatePublisher: AnyPublisher<FormatState, Never> { get }
    
    // MARK: - 编辑器信息
    
    /// 编辑器类型
    var editorType: EditorType { get }
    
    /// 编辑器是否可用
    var isEditorAvailable: Bool { get }
}
```

## 状态检测规则

### 光标模式（无选择）

当光标位于文本中且没有选中任何文本时：

1. **检测位置**：获取光标前一个字符的格式属性
2. **边界情况**：
   - 光标在文档开头：显示默认格式状态
   - 光标在段落开头：获取该段落的段落级格式
3. **输入属性**：点击格式后，设置 `typingAttributes`，后续输入的文本将带有该格式

```swift
/// 光标模式下的格式状态检测
func detectFormatStateAtCursor(position: Int) -> FormatState {
    var state = FormatState()
    state.hasSelection = false
    
    // 边界检查
    guard position > 0, position <= textStorage.length else {
        return state // 返回默认状态
    }
    
    // 获取光标前一个字符的属性
    let attributePosition = position - 1
    let attributes = textStorage.attributes(at: attributePosition, effectiveRange: nil)
    
    // 检测各种格式...
    state = detectFormatsFromAttributes(attributes)
    
    return state
}
```

### 选择模式（有选择）

当有文本被选中时：

1. **全选检测**：遍历选择范围内的所有字符
2. **激活规则**：只有当选择范围内的**所有字符**都具有某格式时，该格式才显示为激活状态
3. **混合状态**：如果选择范围内有任意字符没有某格式，该格式显示为未激活

```swift
/// 选择模式下的格式状态检测
func detectFormatStateInSelection(range: NSRange) -> FormatState {
    var state = FormatState()
    state.hasSelection = true
    state.selectionLength = range.length
    
    // 初始化为全部激活
    var allBold = true
    var allItalic = true
    var allUnderline = true
    var allStrikethrough = true
    var allHighlight = true
    
    // 遍历选择范围内的每个字符
    textStorage.enumerateAttributes(in: range, options: []) { attributes, _, _ in
        // 检测加粗
        if !isBoldInAttributes(attributes) {
            allBold = false
        }
        // 检测斜体
        if !isItalicInAttributes(attributes) {
            allItalic = false
        }
        // ... 其他格式检测
    }
    
    state.isBold = allBold
    state.isItalic = allItalic
    state.isUnderline = allUnderline
    state.isStrikethrough = allStrikethrough
    state.isHighlight = allHighlight
    
    return state
}
```

## 格式应用规则

### 选择模式下的格式应用

```swift
/// 选择模式下应用格式
func applyFormatToSelection(_ format: TextFormat, range: NSRange) {
    let currentState = detectFormatStateInSelection(range: range)
    let isActive = isFormatActiveInState(format, state: currentState)
    
    if isActive {
        // 格式已激活（所有字符都有）-> 移除格式
        removeFormat(format, from: range)
    } else {
        // 格式未激活（有字符没有）-> 应用到所有字符
        applyFormat(format, to: range)
    }
}
```

### 光标模式下的格式应用

```swift
/// 光标模式下应用格式
func applyFormatAtCursor(_ format: TextFormat) {
    // 切换 typingAttributes
    var typingAttributes = textView.typingAttributes
    
    if isFormatInTypingAttributes(format, typingAttributes) {
        // 移除格式
        removeFormatFromTypingAttributes(format, &typingAttributes)
    } else {
        // 添加格式
        addFormatToTypingAttributes(format, &typingAttributes)
    }
    
    textView.typingAttributes = typingAttributes
}
```

### 互斥格式处理

```swift
/// 应用段落格式（处理互斥）
func applyParagraphFormat(_ format: ParagraphFormat, to range: NSRange) {
    // 1. 先移除当前的段落格式
    clearParagraphFormat(in: range)
    
    // 2. 应用新格式
    switch format {
    case .heading1:
        applyHeading1(to: range)
    case .heading2:
        applyHeading2(to: range)
    case .heading3:
        applyHeading3(to: range)
    case .body:
        // 正文是默认状态，不需要额外操作
        break
    case .bulletList:
        applyBulletList(to: range)
    case .numberedList:
        applyNumberedList(to: range)
    case .checkbox:
        applyCheckbox(to: range)
    }
}

/// 应用对齐格式（处理互斥）
func applyAlignmentFormat(_ alignment: AlignmentFormat, to range: NSRange) {
    // 直接设置对齐方式，自动覆盖之前的对齐
    let paragraphStyle = NSMutableParagraphStyle()
    
    switch alignment {
    case .left:
        paragraphStyle.alignment = .left
    case .center:
        paragraphStyle.alignment = .center
    case .right:
        paragraphStyle.alignment = .right
    }
    
    textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
}
```

## 状态同步机制

### FormatStateManager

```swift
/// 格式状态管理器
/// 负责同步工具栏和菜单栏的格式状态
@MainActor
class FormatStateManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 当前格式状态
    @Published private(set) var currentState: FormatState = FormatState()
    
    /// 当前活动的格式提供者
    @Published private(set) var activeProvider: FormatMenuProvider?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let stateSubject = PassthroughSubject<FormatState, Never>()
    
    // MARK: - Singleton
    
    static let shared = FormatStateManager()
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Public Methods
    
    /// 设置活动的格式提供者
    func setActiveProvider(_ provider: FormatMenuProvider?) {
        // 取消之前的订阅
        cancellables.removeAll()
        
        activeProvider = provider
        
        // 订阅新提供者的状态变化
        provider?.formatStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateState(state)
            }
            .store(in: &cancellables)
        
        // 立即获取当前状态
        if let state = provider?.getCurrentFormatState() {
            updateState(state)
        }
    }
    
    /// 应用格式
    func applyFormat(_ format: TextFormat) {
        activeProvider?.applyFormat(format)
    }
    
    /// 切换格式
    func toggleFormat(_ format: TextFormat) {
        activeProvider?.toggleFormat(format)
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ state: FormatState) {
        currentState = state
        stateSubject.send(state)
        
        // 发送通知以更新菜单栏
        NotificationCenter.default.post(
            name: .formatStateDidChange,
            object: self,
            userInfo: ["state": state]
        )
    }
    
    private func setupNotificationObservers() {
        // 监听编辑器焦点变化
        NotificationCenter.default.addObserver(
            forName: .editorFocusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleEditorFocusChange(notification)
        }
    }
}
```

### 通知定义

```swift
extension Notification.Name {
    /// 格式状态变化通知
    static let formatStateDidChange = Notification.Name("formatStateDidChange")
    
    /// 编辑器焦点变化通知
    static let editorFocusDidChange = Notification.Name("editorFocusDidChange")
    
    /// 请求格式状态更新通知
    static let requestFormatStateUpdate = Notification.Name("requestFormatStateUpdate")
}
```

## 菜单栏集成

### MenuManager 更新

```swift
extension MenuManager {
    
    /// 更新格式菜单状态
    func updateFormatMenuState(_ state: FormatState) {
        // 更新段落格式菜单项
        updateParagraphFormatMenuItems(state.paragraphFormat)
        
        // 更新对齐格式菜单项
        updateAlignmentMenuItems(state.alignment)
        
        // 更新字符格式菜单项
        updateCharacterFormatMenuItems(state)
        
        // 更新引用块菜单项
        updateQuoteMenuItem(state.isQuote)
    }
    
    private func updateParagraphFormatMenuItems(_ format: ParagraphFormat) {
        // 遍历所有段落格式菜单项，设置勾选状态
        for paragraphFormat in ParagraphFormat.allCases {
            let menuItem = findMenuItem(for: paragraphFormat)
            menuItem?.state = (paragraphFormat == format) ? .on : .off
        }
    }
    
    private func updateCharacterFormatMenuItems(_ state: FormatState) {
        findMenuItem(for: .bold)?.state = state.isBold ? .on : .off
        findMenuItem(for: .italic)?.state = state.isItalic ? .on : .off
        findMenuItem(for: .underline)?.state = state.isUnderline ? .on : .off
        findMenuItem(for: .strikethrough)?.state = state.isStrikethrough ? .on : .off
        findMenuItem(for: .highlight)?.state = state.isHighlight ? .on : .off
    }
}
```

## 工具栏菜单集成

### NativeFormatMenuView 更新

```swift
struct NativeFormatMenuView: View {
    @ObservedObject var stateManager: FormatStateManager
    
    var body: some View {
        VStack(spacing: 0) {
            // 字符格式按钮组
            characterFormatButtons
            
            Divider()
            
            // 段落格式列表
            paragraphFormatList
            
            Divider()
            
            // 引用块
            quoteButton
            
            Divider()
            
            // 对齐按钮组
            alignmentButtons
        }
    }
    
    private var characterFormatButtons: some View {
        HStack(spacing: 8) {
            FormatButton(
                format: .bold,
                isActive: stateManager.currentState.isBold,
                action: { stateManager.toggleFormat(.bold) }
            )
            FormatButton(
                format: .italic,
                isActive: stateManager.currentState.isItalic,
                action: { stateManager.toggleFormat(.italic) }
            )
            // ... 其他字符格式按钮
        }
    }
    
    private var paragraphFormatList: some View {
        VStack(spacing: 0) {
            ForEach(ParagraphFormat.allCases, id: \.self) { format in
                ParagraphFormatRow(
                    format: format,
                    isSelected: stateManager.currentState.paragraphFormat == format,
                    action: { stateManager.applyFormat(format.textFormat) }
                )
            }
        }
    }
}
```

## 性能优化

### 防抖处理

```swift
/// 格式状态同步器
class FormatStateSynchronizer {
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.05 // 50ms
    
    /// 调度状态更新（带防抖）
    func scheduleStateUpdate() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.performStateUpdate()
        }
    }
    
    /// 立即执行状态更新（跳过防抖）
    func performImmediateUpdate() {
        debounceTimer?.invalidate()
        performStateUpdate()
    }
}
```

### 增量更新

```swift
/// 只更新变化的格式状态
func updateStateIfChanged(_ newState: FormatState) {
    guard newState != currentState else { return }
    
    // 只发送变化的部分
    let changes = detectChanges(from: currentState, to: newState)
    
    currentState = newState
    
    // 发送增量更新通知
    NotificationCenter.default.post(
        name: .formatStateDidChange,
        object: self,
        userInfo: ["state": newState, "changes": changes]
    )
}
```

## 错误处理

### 格式应用错误

```swift
enum FormatApplicationError: Error {
    case editorNotAvailable
    case invalidRange
    case formatNotSupported(TextFormat)
    case mutualExclusionViolation(TextFormat, TextFormat)
}

extension FormatMenuProvider {
    func applyFormatSafely(_ format: TextFormat) -> Result<Void, FormatApplicationError> {
        guard isEditorAvailable else {
            return .failure(.editorNotAvailable)
        }
        
        do {
            try applyFormat(format)
            return .success(())
        } catch let error as FormatApplicationError {
            return .failure(error)
        } catch {
            return .failure(.formatNotSupported(format))
        }
    }
}
```

## 测试策略

### 单元测试

1. **格式状态检测测试**
   - 光标模式下的格式检测
   - 选择模式下的格式检测
   - 混合格式状态检测

2. **格式应用测试**
   - 字符格式应用和移除
   - 段落格式互斥规则
   - 对齐格式互斥规则

3. **状态同步测试**
   - 工具栏和菜单栏状态同步
   - 编辑器切换时的状态更新

### 集成测试

1. **端到端格式操作测试**
2. **性能测试（响应时间）**
3. **边界条件测试**

## 实现计划

### 阶段 1：核心接口（2 天）
- 定义 `FormatState` 结构体
- 定义 `FormatMenuProvider` 协议
- 实现 `FormatStateManager`

### 阶段 2：原生编辑器实现（3 天）
- 实现 `NativeFormatProvider`
- 更新 `NativeEditorContext`
- 集成格式状态检测

### 阶段 3：菜单集成（2 天）
- 更新 `MenuManager` 格式菜单
- 更新 `NativeFormatMenuView`
- 实现状态同步

### 阶段 4：测试和优化（2 天）
- 编写单元测试
- 性能优化
- 边界条件处理

## 参考文档

- [需求文档](requirements.md)
- [Apple Notes 菜单栏设计规范](.kiro/specs/apple-notes-menu-bar/design.md)
- [原生编辑器设计文档](.kiro/specs/native-rich-text-editor/design.md)
