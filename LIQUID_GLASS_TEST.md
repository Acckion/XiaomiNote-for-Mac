# Liquid Glass 粘性分组头测试

## 测试目标
验证粘性分组头的切换逻辑是否正确，确保在滚动时能够正确显示当前区域的分组标题。

## 实现方案

### 方案演进

#### 第一次尝试（失败）
- **逻辑**: 使用"已通过工具栏的分组"来判断
- **问题**: 当所有分组都滚动过去后，会错误地切换回第一个分组（"今天"）
- **日志证据**: 
  ```
  [StickyHeader] ⬆️ 已通过工具栏的分组: []
  [StickyHeader] 🔝 在顶部，显示第一个分组: 今天
  [StickyHeader] 🔄 更新粘性头: 本月 -> 今天  // 错误！
  ```

#### 第二次尝试（失败）
- **逻辑**: 使用"当前可见分组头的上一个分组"
- **问题**: 在区域内没有分组头时判断异常，仍然会出现错误切换

#### 第三次尝试（当前实现）✅
- **逻辑**: 找到区域内显示的第一篇笔记，通过笔记来判断应该显示哪个粘性头
- **优势**: 
  - 直接基于笔记位置，更加准确
  - 避免了分组头位置判断的边界情况
  - 逻辑更简单清晰

### 技术实现

1. **添加笔记位置追踪**
   ```swift
   struct NotePositionPreferenceKey: PreferenceKey {
       struct NotePosition: Equatable {
           let noteId: String
           let section: String
           let yPosition: CGFloat
       }
   }
   ```

2. **在每个笔记行添加位置追踪**
   ```swift
   GeometryReader { geometry in
       pinnedNoteRow(note: note, showDivider: index < notes.count - 1)
           .preference(
               key: NotePositionPreferenceKey.self,
               value: [NotePositionPreferenceKey.NotePosition(
                   noteId: note.id,
                   section: sectionKey,
                   yPosition: geometry.frame(in: .global).minY
               )]
           )
   }
   .frame(height: 70) // 笔记行的固定高度
   ```

3. **隐藏第一个分组头（避免重复显示）**
   ```swift
   GeometryReader { geometry in
       LiquidGlassSectionHeader(title: sectionKey)
           .opacity(sectionKey == firstSection ? 0 : 1) // 隐藏第一个分组头
           .preference(
               key: SectionHeaderPreferenceKey.self,
               value: [sectionKey: geometry.frame(in: .global).minY]
           )
   }
   .frame(height: sectionKey == firstSection ? 1 : 44) // 第一个分组头高度为1（避免空白），其他为44
   ```

4. **新的切换逻辑**
   ```swift
   private func updateCurrentVisibleSection(notePositions: [NotePositionPreferenceKey.NotePosition]) {
       let toolbarHeight: CGFloat = 52 + 10
       
       // 找到第一个在工具栏下方可见的笔记（Y >= toolbarHeight）
       let visibleNotes = notePositions
           .filter { $0.yPosition >= toolbarHeight }
           .sorted { $0.yPosition < $1.yPosition }
       
       if let firstVisibleNote = visibleNotes.first {
           // 显示第一个可见笔记所属的分组
           currentVisibleSection = firstVisibleNote.section
       } else {
           // 所有笔记都滚动过去了，显示最后一个分组
           currentVisibleSection = allSections.last
       }
   }
   ```

## 测试步骤

1. **启动应用**
   - 打开"所有笔记"文件夹
   - 确保开启日期分组

2. **从顶部向下滚动**
   - 验证粘性头切换顺序：今天 → 昨天 → 本周 → 本月 → 2025年
   - 每次切换应该平滑，没有闪烁或跳跃

3. **滚动到底部**
   - 验证粘性头显示最后一个分组（如"2025年"）
   - 不应该错误地切换回"今天"

4. **从底部向上滚动**
   - 验证粘性头切换顺序：2025年 → 本月 → 本周 → 昨天 → 今天
   - 切换应该与向下滚动时对称

5. **边界情况测试**
   - 在顶部时：应该显示第一个分组
   - 在底部时：应该显示最后一个分组
   - 快速滚动时：切换应该跟上滚动速度

## 预期结果

- ✅ 粘性头始终显示当前可见区域的第一篇笔记所属的分组
- ✅ 滚动到底部时显示最后一个分组，不会错误地切换回第一个分组
- ✅ 只有第一个分组头被隐藏，避免重复显示
- ✅ 第一个分组头高度为1（最小高度），避免头部出现大片空白
- ✅ 切换过程平滑，没有闪烁或跳跃

## 调试日志格式

```
[StickyHeader] 📍 笔记位置信息:
[StickyHeader]   笔记 49013983... 分组: 今天, Y=96.0
[StickyHeader]   笔记 47730500... 分组: 今天, Y=166.0
[StickyHeader] 🎯 工具栏高度: 62.0
[StickyHeader] 👁️ 第一个可见笔记: 49013983..., 分组: 今天
[StickyHeader] 🔄 更新粘性头: nil -> 今天
```

## 已知问题

### 已修复：粘性分组头透明度问题 ✅

**问题描述**：
当笔记列表宽度与工具栏宽度一致时,SwiftUI 会自动将 `.safeAreaInset` 的内容与工具栏合并,导致模糊效果变为透明效果,文字可读性降低。

**根本原因**：
1. 之前尝试通过设置 `window.titlebarAppearsTransparent = true` 和 `window.titlebarSeparatorStyle = .none` 来实现"融合"效果
2. 这导致 SwiftUI 认为粘性头应该与工具栏合并,在某些布局情况下会自动移除模糊效果
3. 手动移除 `.background` 后,粘性头完全透明,文字不可读

**解决方案**：
1. **不在主窗口设置 `titlebarAppearsTransparent` 和 `titlebarSeparatorStyle`**
   - 保持窗口的默认配置(有标题栏分割线)
   - 让粘性分组头独立显示,不依赖与工具栏的"融合"

2. **在 `LiquidGlassSectionHeader` 中使用 `.background(.regularMaterial)`**
   - 使用系统标准的模糊材质
   - 不试图与工具栏融合,保持独立性
   - 确保在任何布局情况下都有正确的模糊效果

**关键理解**：
- 原生编辑器的查找栏(`NSTextView.usesFindBar = true`)是 AppKit 的标准机制,系统会自动处理其与工具栏的关系
- SwiftUI 的 `.safeAreaInset` 不是标准的 AppKit 机制,不应该期望它能自动与工具栏融合
- **正确的做法是让粘性头独立显示,使用标准的模糊材质,而不是试图模仿 Liquid Glass 的"融合"效果**

**参考资料**：
- ` research` 第 5.1 节 - "玻璃采样玻璃（Glass on Glass）陷阱"
- 原生编辑器查找栏使用的是 `NSScrollView.findBarPosition = .aboveContent`,这是 AppKit 的标准机制
- SwiftUI 的 `.safeAreaInset` 是一个不同的实现,不应该期望相同的行为

### 已修复：粘性分组头缺少模糊背景 ✅

**问题描述**：
`LiquidGlassSectionHeader` 定义了 `headerBackground` 属性（返回 `.regularMaterial`），但在 `body` 中没有实际使用它，导致粘性分组头没有模糊效果，文字可读性降低。

**解决方案**：
在 `LiquidGlassSectionHeader.swift` 的 `body` 中添加 `.background(headerBackground)` 修饰符：
```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        // ... 内容 ...
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 0)
    // 应用模糊材质背景
    .background(headerBackground)
}
```

**关键点**：
1. `headerBackground` 根据可访问性设置返回不同的背景：
   - 正常模式：`.regularMaterial`（模糊效果）
   - 高对比度模式：不透明背景色
2. 这个 `.background` 是应用在粘性头组件本身，不违反"严禁使用任何形式的.background"的要求（那个要求是针对 ScrollView 层级）
3. `.safeAreaInset` 保持不变，继续使用

## 后续优化

1. 可以考虑添加切换动画，使粘性头切换更加平滑
2. 可以优化笔记行高度的计算，使其更加准确（目前固定为70）
3. 可以考虑添加防抖机制，避免频繁更新

## 参考资料

- ` research` - macOS 26 Tahoe Liquid Glass 设计调查报告
- `Sources/View/NativeEditor/Core/NativeEditorView.swift` 第 72 行 - 原生编辑器查找栏实现参考
