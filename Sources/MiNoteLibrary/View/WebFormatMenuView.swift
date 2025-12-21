import SwiftUI
import AppKit

/// Web格式菜单视图
/// 专为Web编辑器设计的格式菜单，使用WebEditorContext
@available(macOS 14.0, *)
struct WebFormatMenuView: View {
    /// Web编辑器上下文
    @ObservedObject var context: WebEditorContext
    
    @State private var currentStyle: TextStyle = .body
    @State private var isBlockQuote: Bool = false
    
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
    
    /// 文本样式枚举
    enum TextStyle: String, CaseIterable {
        case title = "标题"
        case subtitle = "小标题"
        case subheading = "副标题"
        case body = "正文"
        case bulletList = "无序列表"
        case numberedList = "有序列表"
        
        var displayName: String {
            return rawValue
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
                    Text("I")
                        .font(.system(size: 14, weight: .regular))
                        .italic()
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
                
                // 高亮按钮（暂时禁用，因为Web编辑器可能不支持）
                Button(action: {
                    // 暂时不实现高亮功能
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // 分割线
            Divider()
            
            // 文本样式列表（单选：标题、小标题、副标题、正文、无序列表、有序列表）
            VStack(spacing: 0) {
                ForEach(TextStyle.allCases, id: \.self) { style in
                    Button(action: {
                        handleStyleSelection(style)
                    }) {
                        HStack {
                            // 勾选标记
                            Image(systemName: style == currentStyle ? "checkmark" : "")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)
                                .frame(width: 20, alignment: .leading)
                            
                            Text(style.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(style == currentStyle ? Color.yellow.opacity(0.1) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 块引用上方的分割线
            Divider()
            
            // 块引用（可勾选）
            Button(action: {
                isBlockQuote.toggle()
                handleBlockQuoteToggle()
            }) {
                HStack {
                    // 勾选标记
                    Image(systemName: isBlockQuote ? "checkmark" : "")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                        .frame(width: 20, alignment: .leading)
                    
                    Text("块引用")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isBlockQuote ? Color.yellow.opacity(0.1) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // 块引用下方的分割线
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
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
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
            // 更新当前样式
            if let level = newValue {
                switch level {
                case 1:
                    currentStyle = .title
                case 2:
                    currentStyle = .subtitle
                case 3:
                    currentStyle = .subheading
                default:
                    currentStyle = .body
                }
            } else {
                currentStyle = .body
            }
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
    
    private func handleStyleSelection(_ style: TextStyle) {
        currentStyle = style
        
        switch style {
        case .title:
            context.setHeadingLevel(1)
            onFormatAction?(.heading(1))
        case .subtitle:
            context.setHeadingLevel(2)
            onFormatAction?(.heading(2))
        case .subheading:
            context.setHeadingLevel(3)
            onFormatAction?(.heading(3))
        case .body:
            context.setHeadingLevel(nil)
            onFormatAction?(.heading(0))
        case .bulletList:
            context.toggleBulletList()
            onFormatAction?(.bulletList)
        case .numberedList:
            context.toggleOrderList()
            onFormatAction?(.orderList)
        }
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
}

#Preview {
    WebFormatMenuView(context: WebEditorContext())
        .padding()
}
