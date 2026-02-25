import AppKit
import SwiftUI

/// Liquid Glass 风格的分组头组件
///
/// 实现粘性分组头效果,参考原生编辑器查找栏的实现。
///
/// 关键设计：
/// - 使用 `.background(.regularMaterial)` 提供模糊背景
/// - 分割线位于分组头底部
/// - 配合 NotesListView 中的 .safeAreaInset 实现粘性效果
/// - 不依赖窗口级别的 titlebar 配置,保持独立性
///
struct LiquidGlassSectionHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题文本
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 8) // 内部顶部间距
                .padding(.bottom, 10) // 标题与分割线的间距
                .padding(.horizontal, 10)
            // 底部分割线
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8) // 分割线与下方内容的间距
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 0)
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
