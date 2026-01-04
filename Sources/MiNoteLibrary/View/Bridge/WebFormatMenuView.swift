import SwiftUI
import AppKit

/// Web格式菜单视图
/// 专为Web编辑器设计的格式菜单，使用WebEditorContext
@available(macOS 14.0, *)
struct WebFormatMenuView: View {
    /// Web编辑器上下文
    @ObservedObject var context: WebEditorContext
    
    var onFormatAction: ((FormatAction) -> Void)?
    
    init(context: WebEditorContext, onFormatAction: ((FormatAction) -> Void)? = nil) {
        self._context = ObservedObject(wrappedValue: context)
        self.onFormatAction = onFormatAction
    }
    
    /// 格式操作枚举
    enum FormatAction {
        case bold
        case italic
        case underline
        case strikethrough
        case highlight
        case textAlignment(TextAlignment)
        case heading(Int)
        case bulletList
        case orderList
        case quote
    }
    
    /// 文本样式枚举（对应小米笔记格式）
    enum TextStyle: String, CaseIterable {
        case title = "大标题"           // <size>
        case subtitle = "二级标题"      // <mid-size>
        case subheading = "三级标题"   // <h3-size>
        case body = "正文"              // 普通文本
        case bulletList = "•  无序列表"    // <bullet>
        case numberedList = "1. 有序列表"  // <order>
        
        var displayName: String {
            return rawValue
        }
        
        /// 对应的标题级别（用于设置 headingLevel）
        var headingLevel: Int? {
            switch self {
            case .title: return 1
            case .subtitle: return 2
            case .subheading: return 3
            default: return nil
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部格式化按钮组（加粗、斜体、下划线、删除线、高亮）
            HStack(spacing: 8) {
                // 加粗按钮
                Button(action: {
                    handleBoldToggle()
                }) {
                    Text("B")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(context.isBold ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isBold ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 斜体按钮
                Button(action: {
                    handleItalicToggle()
                }) {
                    Image(systemName: "italic")
                        .font(.system(size: 16))
                        .foregroundColor(context.isItalic ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isItalic ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 下划线按钮
                Button(action: {
                    handleUnderlineToggle()
                }) {
                    Text("U")
                        .font(.system(size: 14, weight: .regular))
                        .underline()
                        .foregroundColor(context.isUnderline ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isUnderline ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 删除线按钮
                Button(action: {
                    handleStrikethroughToggle()
                }) {
                    Text("S")
                        .font(.system(size: 14, weight: .regular))
                        .strikethrough()
                        .foregroundColor(context.isStrikethrough ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isStrikethrough ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 高亮按钮
                Button(action: {
                    handleHighlightToggle()
                }) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 12))
                        .foregroundColor(context.isHighlighted ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isHighlighted ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // 分割线
            Divider()
            
            // 文本样式列表（单选：大标题、二级标题、三级标题、正文、无序列表、有序列表）
            // 根据编辑器状态动态更新勾选状态（参考 CKEditor 5）
            VStack(spacing: 0) {
                ForEach(TextStyle.allCases, id: \.self) { style in
                    Button(action: {
                        handleStyleSelection(style)
                    }) {
                        HStack {
                            // 勾选标记（根据编辑器状态动态显示）
                            if isStyleSelected(style) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12))
                                    .foregroundColor(.yellow)
                                    .frame(width: 20, alignment: .leading)
                            } else {
                                // 当未选中时显示空白占位符
                                Color.clear
                                    .frame(width: 20, alignment: .leading)
                            }
                            
                            Text(style.displayName)
                                .font(fontForStyle(style))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isStyleSelected(style) ? Color.yellow.opacity(0.1) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 分割线（文本样式列表和引用块之间）
            Divider()
            
            // 引用块（可勾选）
            // 注意：需要添加 isInQuote 状态到 WebEditorContext
            VStack(spacing: 0) {
                Button(action: {
                    handleBlockQuoteToggle()
                }) {
                    HStack {
                        // 勾选标记（根据编辑器状态动态显示）
                        if context.isInQuote {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)
                                .frame(width: 20, alignment: .leading)
                        } else {
                            // 当未选中时显示空白占位符
                            Color.clear
                                .frame(width: 20, alignment: .leading)
                        }
                        
                        Text("引用块")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 0)
                    .background(context.isInQuote ? Color.yellow.opacity(0.1) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            // 分割线（引用块和对齐按钮组之间）
            Divider()
            
            // 对齐按钮组（居左、居中、居右）
            HStack(spacing: 8) {
                // 居左按钮
                Button(action: {
                    handleAlignmentChange(.leading)
                }) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 12))
                        .foregroundColor(context.textAlignment == .leading ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.textAlignment == .leading ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 居中按钮
                Button(action: {
                    handleAlignmentChange(.center)
                }) {
                    Image(systemName: "text.aligncenter")
                        .font(.system(size: 12))
                        .foregroundColor(context.textAlignment == .center ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.textAlignment == .center ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 居右按钮
                Button(action: {
                    handleAlignmentChange(.trailing)
                }) {
                    Image(systemName: "text.alignright")
                        .font(.system(size: 12))
                        .foregroundColor(context.textAlignment == .trailing ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.textAlignment == .trailing ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
        .onChange(of: context.isBold) { oldValue, newValue in
            print("🔄 [WebFormatMenuView] 加粗状态变化: \(oldValue) -> \(newValue)")
        }
        .onChange(of: context.isItalic) { oldValue, newValue in
            print("🔄 [WebFormatMenuView] 斜体状态变化: \(oldValue) -> \(newValue)")
        }
        .onChange(of: context.isUnderline) { oldValue, newValue in
            print("🔄 [WebFormatMenuView] 下划线状态变化: \(oldValue) -> \(newValue)")
        }
        .onChange(of: context.isStrikethrough) { oldValue, newValue in
            print("🔄 [WebFormatMenuView] 删除线状态变化: \(oldValue) -> \(newValue)")
        }
        .onChange(of: context.textAlignment) { oldValue, newValue in
            print("🔄 [WebFormatMenuView] 对齐方式变化: \(oldValue) -> \(newValue)")
        }
        .onChange(of: context.headingLevel) { oldValue, newValue in
            print("🔄 [WebFormatMenuView] 标题级别变化: \(String(describing: oldValue)) -> \(String(describing: newValue))")
            // 状态已由编辑器同步，不需要手动更新 currentStyle
            // currentStyle 会通过 isStyleSelected 方法动态计算
        }
        .onChange(of: context.listType) { oldValue, newValue in
            print("🔄 [WebFormatMenuView] 列表类型变化: \(String(describing: oldValue)) -> \(String(describing: newValue))")
            // 状态已由编辑器同步
        }
        .onChange(of: context.isInQuote) { oldValue, newValue in
            print("🔄 [WebFormatMenuView] 引用块状态变化: \(oldValue) -> \(newValue)")
            // 状态已由编辑器同步
        }
        .onAppear {
            print("✅ [WebFormatMenuView] 已显示，context: \(context)")
            print("   - 加粗: \(context.isBold)")
            print("   - 斜体: \(context.isItalic)")
            print("   - 下划线: \(context.isUnderline)")
            print("   - 删除线: \(context.isStrikethrough)")
            print("   - 对齐方式: \(context.textAlignment)")
            print("   - 标题级别: \(String(describing: context.headingLevel))")
        }
    }
    
    /// 检查样式是否被选中（参考 CKEditor 5 的 isOn 绑定）
    private func isStyleSelected(_ style: TextStyle) -> Bool {
        switch style {
        case .title:
            return context.headingLevel == 1
        case .subtitle:
            return context.headingLevel == 2
        case .subheading:
            return context.headingLevel == 3
        case .body:
            return context.headingLevel == nil && context.listType == nil
        case .bulletList:
            return context.listType == "bullet"
        case .numberedList:
            return context.listType == "order"
        }
    }
    
    private func handleStyleSelection(_ style: TextStyle) {
        switch style {
        case .title:
            // 大标题：使用 <size> 标签
            context.setHeadingLevel(1)
            onFormatAction?(.heading(1))
        case .subtitle:
            // 二级标题：使用 <mid-size> 标签
            context.setHeadingLevel(2)
            onFormatAction?(.heading(2))
        case .subheading:
            // 三级标题：使用 <h3-size> 标签
            context.setHeadingLevel(3)
            onFormatAction?(.heading(3))
        case .body:
            // 正文：清除标题格式
            context.setHeadingLevel(nil)
            onFormatAction?(.heading(0))
        case .bulletList:
            // 无序列表：使用 <bullet> 标签
            context.toggleBulletList()
            onFormatAction?(.bulletList)
        case .numberedList:
            // 有序列表：使用 <order> 标签
            context.toggleOrderList()
            onFormatAction?(.orderList)
        }
        // 不手动更新 currentStyle，由编辑器状态同步
    }
    
    private func handleBlockQuoteToggle() {
        context.toggleQuote()
        onFormatAction?(.quote)
    }
    
    private func handleAlignmentChange(_ alignment: TextAlignment) {
        context.setTextAlignment(alignment)
        onFormatAction?(.textAlignment(alignment))
    }
    
    private func handleUnderlineToggle() {
        context.toggleUnderline()
        onFormatAction?(.underline)
    }
    
    private func handleStrikethroughToggle() {
        context.toggleStrikethrough()
        onFormatAction?(.strikethrough)
    }
    
    private func handleBoldToggle() {
        context.toggleBold()
        onFormatAction?(.bold)
    }
    
    private func handleItalicToggle() {
        context.toggleItalic()
        onFormatAction?(.italic)
    }
    
    private func handleHighlightToggle() {
        context.toggleHighlight()
        onFormatAction?(.highlight)
    }
    
    /// 根据样式返回对应的字体
    private func fontForStyle(_ style: TextStyle) -> Font {
        switch style {
        case .title:
            return .system(size: 16, weight: .bold)
        case .subtitle:
            return .system(size: 14, weight: .semibold)
        case .subheading:
            return .system(size: 13, weight: .medium)
        case .body:
            return .system(size: 13)
        case .bulletList, .numberedList:
            return .system(size: 13)
        }
    }
    
    #Preview {
        WebFormatMenuView(context: WebEditorContext())
            .padding()
    }
}
