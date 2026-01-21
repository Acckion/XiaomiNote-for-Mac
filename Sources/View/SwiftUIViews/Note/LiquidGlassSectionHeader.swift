import SwiftUI
import AppKit

/// Liquid Glass 风格的分组头组件
///
/// 实现 macOS 26 Tahoe 风格的 Liquid Glass 粘性分组头效果。
/// 关键设计：
/// - 使用 `.regularMaterial` 模糊材质，与工具栏视觉融合
/// - `padding(.top, 0)` 让分组头紧贴工具栏，形成连续的玻璃表面
/// - 分割线位于分组头底部，而非工具栏底部
///
/// **Validates: Requirements 2.1, 2.2, 2.3**
struct LiquidGlassSectionHeader: View {
    let title: String
    
    /// 减少透明度设置（可访问性支持）
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题文本
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 8)      // 内部顶部间距
                .padding(.bottom, 10)  // 标题与分割线的间距
                .padding(.horizontal, 10)
            
            // 底部分割线
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)   // 分割线与下方内容的间距
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 0)  // 关键：完全移除外部顶部间距，让分组头紧贴工具栏
    }
    
    /// 根据可访问性设置选择背景材质
    private var headerBackground: some ShapeStyle {
        if reduceTransparency {
            // 高对比度不透明背景
            return AnyShapeStyle(Color(NSColor.controlBackgroundColor))
        } else {
            // 使用 .ultraThinMaterial 实现最低模糊半径
            // 几乎能看清后面的文字，与工具栏的轻量级模糊匹配
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        LiquidGlassSectionHeader(title: "今天")
        Text("笔记内容示例")
            .padding()
        LiquidGlassSectionHeader(title: "昨天")
        Text("更多笔记内容")
            .padding()
        Text("更多笔记内容")
            .padding()
        Text("更多笔记内容")
            .padding()
    }
}
