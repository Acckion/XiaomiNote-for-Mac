# Liquid Glass 粘性分组头实现方案分析

## 问题诊断

### 核心问题
SwiftUI 的 `.safeAreaInset(edge: .top)` 在 splitview 宽度与工具栏一致时会被系统自动融合,导致粘性头变透明。

### 问题原因
1. **SwiftUI 的 `.safeAreaInset` 不是 AppKit 的标准机制**
   - 原生编辑器的查找栏使用 `NSTextView.usesFindBar = true`,这是 AppKit 的标准机制
   - 系统会自动处理 AppKit 标准机制的融合行为
   - 但 SwiftUI 的 `.safeAreaInset` 不在系统的自动处理范围内

2. **系统的自动融合行为**
   - 当 splitview 宽度与工具栏宽度完全一致时
   - macOS 26 Tahoe 会自动将它们"融合"以实现 Liquid Glass 效果
   - 这导致粘性头变成透明的

3. **这是 SwiftUI 的 bug,不是我们的实现问题**
   - 参考: https://developer.apple.com/forums/thread/801623
   - macOS 26 在处理 `titlebarAppearsTransparent` 和 splitview 时有已知的 bug

## 解决方案对比

### 方案 A: 添加 `.background(.regularMaterial)` (推荐)

**优点:**
- 实现简单,只需修改一行代码
- 功能完全正常,粘性头不会透明
- 性能最优

**缺点:**
- 与原生 Apple Notes 有轻微视觉差异
- 粘性头会有自己的模糊背景,而不是与工具栏完全融合

**实现:**
```swift
struct LiquidGlassSectionHeader: View {
    let title: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .padding(.horizontal, 10)
            
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 0)
        .background(.regularMaterial) // 添加这一行
    }
}
```

### 方案 B: 使用 AppKit 的 NSScrollView.addFloatingSubview (完美但复杂)

**优点:**
- 使用 AppKit 的标准 API,避免 SwiftUI 的 bug
- 可以实现与原生 Apple Notes 完全一致的效果
- 系统会自动处理融合行为

**缺点:**
- 需要完全重写笔记列表,使用 NSTableView 替代 SwiftUI List
- 工作量巨大,需要重构大量代码
- 失去 SwiftUI 的便利性

**参考资料:**
- [NSScrollView floating subviews](https://casualprogrammer.com/blog/2020/12-30-appkit_notes_nsscrol.html)
- [Apple WWDC13: Introducing NSScrollView floating subviews](https://developer.apple.com/videos/play/wwdc2013/)

**实现示例:**
```swift
// 在 AppKit 中使用 NSScrollView
let scrollView = NSScrollView()
let headerView = NSView() // 粘性头视图

// 添加为浮动子视图（垂直方向固定,水平方向跟随滚动）
scrollView.addFloatingSubview(headerView, for: .vertical)

// 设置约束
NSLayoutConstraint.activate([
    headerView.topAnchor.constraint(equalTo: scrollView.topAnchor),
    headerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
    headerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
    headerView.heightAnchor.constraint(equalToConstant: 44)
])
```

### 方案 C: 强制 splitview 宽度略小于工具栏 (不推荐)

**优点:**
- 可以避免系统的自动融合行为
- 不需要修改粘性头代码

**缺点:**
- 影响用户体验,用户无法将笔记列表拖到与工具栏一致的宽度
- 治标不治本,只是绕过了问题

**实现:**
```swift
// 在 MainWindowController.swift 中
notesListSplitViewItem.maximumThickness = 348 // 略小于工具栏宽度
```

### 方案 D: 接受当前效果 (临时方案)

**优点:**
- 不需要任何修改
- 等待 Apple 修复 SwiftUI 的 bug

**缺点:**
- 在 splitview 宽度与工具栏一致时,粘性头会透明
- 用户体验不佳

## 推荐方案

**短期方案 (立即实施)**: 方案 A - 添加 `.background(.regularMaterial)`
- 简单可靠,功能完全正常
- 虽然与原生有轻微差异,但用户体验良好

**长期方案 (未来考虑)**: 方案 B - 使用 AppKit 重写
- 如果需要完美复刻原生 Apple Notes
- 可以在未来版本中逐步迁移到 AppKit 实现

## 技术细节

### SwiftUI ScrollView vs NSScrollView

| 特性 | SwiftUI ScrollView | NSScrollView |
|------|-------------------|--------------|
| 粘性头 API | `.safeAreaInset` (有 bug) | `.addFloatingSubview` (标准 API) |
| 系统融合 | 不支持自动融合 | 支持自动融合 |
| 实现复杂度 | 简单 | 复杂 |
| 性能 | 良好 | 优秀 |
| 与 Liquid Glass 兼容性 | 部分兼容 (有 bug) | 完全兼容 |

### macOS 26 Tahoe 的已知问题

根据 Apple Developer Forums 的报告:
- FB20341654: `titlebarAppearsTransparent` 在某些情况下不生效
- macOS 26 在处理 splitview 和工具栏时有自动融合的 bug
- 这些问题预计会在未来的 macOS 更新中修复

## 结论

1. **当前问题是 SwiftUI 的 bug,不是我们的实现问题**
2. **推荐使用方案 A** (添加 `.background(.regularMaterial)`),简单可靠
3. **如果需要完美效果**,可以考虑方案 B (使用 AppKit 重写),但工作量巨大
4. **不要使用方案 C** (限制宽度),会影响用户体验

## 参考资料

1. [macOS 26 Tahoe Liquid Glass 设计调查报告]( research)
2. [NSScrollView floating subviews](https://casualprogrammer.com/blog/2020/12-30-appkit_notes_nsscrol.html)
3. [Apple Developer Forums: Window title bar in macOS 26](https://developer.apple.com/forums/thread/801623)
4. [SwiftUI safeAreaInset documentation](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:))
5. [NSScrollView addFloatingSubview documentation](https://developer.apple.com/documentation/appkit/nsscrollview/1403497-addfloatingsubview)
