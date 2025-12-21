import SwiftUI
import AppKit
import RichTextKit

/// 格式菜单视图
/// 包含格式化按钮和文本样式列表
/// 使用 RichTextContext 实现与编辑器的双向同步
@available(macOS 14.0, *)
struct FormatMenuView: View {
    /// RichTextContext（用于格式栏同步）
    @ObservedObject var context: RichTextContext
    
    @State private var currentStyle: TextStyle = .body
    @State private var isBlockQuote: Bool = false
    
    var onFormatAction: ((MiNoteEditor.FormatAction) -> Void)?
    
    init(context: RichTextContext, onFormatAction: ((MiNoteEditor.FormatAction) -> Void)? = nil) {
        self._context = ObservedObject(wrappedValue: context)
        self.onFormatAction = onFormatAction
    }
    
    /// 从 context 获取格式状态
    private var isBold: Bool {
        context.hasStyle(RichTextStyle.bold)
    }
    
    /// 从 context 获取斜体状态
    /// 确保与粗体、下划线等操作一致
    private var isItalic: Bool {
        context.hasStyle(RichTextStyle.italic)
    }
    
    private var isUnderline: Bool {
        context.hasStyle(RichTextStyle.underlined)
    }
    
    private var isStrikethrough: Bool {
        context.hasStyle(RichTextStyle.strikethrough)
    }
    
    private var isHighlight: Bool {
        // 检查是否有背景色（高亮）
        // ColorRepresentable 在 macOS 上就是 NSColor
        if let backgroundColor = context.color(for: .background) as? NSColor {
            // 检查背景色是否不是透明色（即存在高亮）
            return backgroundColor.alphaComponent > 0
        }
        return false
    }
    
    private var textAlignment: NSTextAlignment {
        context.paragraphStyle.alignment
    }
    
    
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
            // 顶部格式化按钮组（加粗、斜体、下划线、高亮）
            HStack(spacing: 8) {
                // 加粗按钮
                Button(action: {
                    print("🔘 [FormatMenuView] 点击加粗按钮，当前状态: \(isBold)")
                    handleBoldToggle()
                }) {
                    Text("B")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isBold ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(isBold ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 斜体按钮（与粗体、下划线等操作一致）
                Button(action: {
                    print("🔘 [FormatMenuView] 点击斜体按钮，当前状态: \(isItalic)")
                    handleItalicToggle()
                }) {
                    Text("I")
                        .font(.system(size: 14, weight: .regular))
                        .italic()
                        .foregroundColor(isItalic ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(isItalic ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 下划线按钮
                Button(action: {
                    // 不在这里更新 isUnderline，让通知来更新（确保状态同步）
                    handleUnderlineToggle()
                }) {
                    Text("U")
                        .font(.system(size: 14, weight: .regular))
                        .underline()
                        .foregroundColor(isUnderline ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(isUnderline ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 删除线按钮
                Button(action: {
                    // 不在这里更新 isStrikethrough，让通知来更新（确保状态同步）
                    handleStrikethroughToggle()
                }) {
                    Text("S")
                        .font(.system(size: 14, weight: .regular))
                        .strikethrough()
                        .foregroundColor(isStrikethrough ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(isStrikethrough ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 高亮按钮
                Button(action: {
                    // 不在这里更新 isHighlight，让通知来更新（确保状态同步）
                    handleHighlightToggle()
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(isHighlight ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(isHighlight ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // 分割线
            Divider()
            
            // 文本样式列表（单选：标题、小标题、副标题、正文、无序列表、有序列表）
            VStack(spacing: 0) {
                ForEach(TextStyle.allCases, id: \.self) { style in
                    Button(action: {
                        // 不在这里更新 currentStyle，让通知来更新（确保状态同步）
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
                    // 不在这里更新 textAlignment，让通知来更新（确保状态同步）
                    handleAlignmentChange(.left)
                }) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 12))
                        .foregroundColor(textAlignment == .left ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(textAlignment == .left ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 居中按钮
                Button(action: {
                    // 不在这里更新 textAlignment，让通知来更新（确保状态同步）
                    handleAlignmentChange(.center)
                }) {
                    Image(systemName: "text.aligncenter")
                        .font(.system(size: 12))
                        .foregroundColor(textAlignment == .center ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(textAlignment == .center ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // 居右按钮
                Button(action: {
                    // 不在这里更新 textAlignment，让通知来更新（确保状态同步）
                    handleAlignmentChange(.right)
                }) {
                    Image(systemName: "text.alignright")
                        .font(.system(size: 12))
                        .foregroundColor(textAlignment == .right ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(textAlignment == .right ? Color.yellow : Color.clear)
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
        // 监听 context 的变化，确保格式栏自动更新
        // 注意：由于 context 是 @ObservedObject，当 context.styles 或 context.paragraphStyle 变化时，
        // 视图会自动重新计算 isBold, isItalic 等计算属性，从而更新按钮状态
        .onChange(of: context.styles) { oldValue, newValue in
            print("🔄 [FormatMenuView] context.styles 变化: \(newValue)")
            print("   - 加粗: \(newValue[RichTextStyle.bold] ?? false)")
            print("   - 斜体: \(newValue[RichTextStyle.italic] ?? false)")
            print("   - 下划线: \(newValue[RichTextStyle.underlined] ?? false)")
            print("   - 删除线: \(newValue[RichTextStyle.strikethrough] ?? false)")
        }
        .onChange(of: context.colors) { oldValue, newValue in
            // 当颜色变化时（特别是背景色/高亮），更新按钮状态
            print("🔄 [FormatMenuView] context.colors 变化: \(newValue)")
            let oldHighlight = (oldValue[.background] as? NSColor)?.alphaComponent ?? 0 > 0
            let newHighlight = (newValue[.background] as? NSColor)?.alphaComponent ?? 0 > 0
            if oldHighlight != newHighlight {
                print("   - 高亮状态变化: \(oldHighlight) -> \(newHighlight)")
            }
        }
        .onChange(of: context.selectedRange) { oldValue, newValue in
            print("🔄 [FormatMenuView] context.selectedRange 变化: location=\(newValue.location), length=\(newValue.length)")
        }
        .onChange(of: context.paragraphStyle.alignment) { oldValue, newValue in
            print("🔄 [FormatMenuView] context.paragraphStyle.alignment 变化: \(newValue.rawValue)")
        }
        .onAppear {
            print("✅ [FormatMenuView] 已显示，context: \(context)")
            print("   - 当前格式状态: \(context.styles)")
            print("   - 选中范围: \(context.selectedRange)")
            print("   - 对齐方式: \(context.paragraphStyle.alignment.rawValue)")
        }
    }
    
    private func handleStyleSelection(_ style: TextStyle) {
        // 通过通知发送样式操作（与对齐方式相同的逻辑）
        switch style {
        case .title:
            NotificationCenter.default.post(
                name: NSNotification.Name("MiNoteEditorFormatAction"),
                object: MiNoteEditor.FormatAction.heading(1)
            )
        case .subtitle:
            NotificationCenter.default.post(
                name: NSNotification.Name("MiNoteEditorFormatAction"),
                object: MiNoteEditor.FormatAction.heading(2)
            )
        case .subheading:
            NotificationCenter.default.post(
                name: NSNotification.Name("MiNoteEditorFormatAction"),
                object: MiNoteEditor.FormatAction.heading(3)
            )
        case .body:
            // TODO: 实现正文样式
            break
        case .bulletList:
            // TODO: 实现无序列表
            break
        case .numberedList:
            // TODO: 实现有序列表
            break
        }
    }
    
    private func handleBlockQuoteToggle() {
        // TODO: 实现块引用切换
    }
    
    private func handleAlignmentChange(_ alignment: NSTextAlignment) {
        // 使用 RichTextContext 直接设置对齐
        context.paragraphStyle.alignment = alignment
        // 同时发送通知（向后兼容）
        NotificationCenter.default.post(
            name: NSNotification.Name("MiNoteEditorFormatAction"),
            object: MiNoteEditor.FormatAction.textAlignment(alignment)
        )
        onFormatAction?(.textAlignment(alignment))
    }
    
    private func handleUnderlineToggle() {
        // 使用 RichTextContext 直接切换格式
        context.toggleStyle(RichTextStyle.underlined)
        // 同时发送通知（向后兼容）
        NotificationCenter.default.post(
            name: NSNotification.Name("MiNoteEditorFormatAction"),
            object: MiNoteEditor.FormatAction.underline
        )
        onFormatAction?(.underline)
    }
    
    private func handleStrikethroughToggle() {
        // 使用 RichTextContext 直接切换格式
        context.toggleStyle(RichTextStyle.strikethrough)
        // 同时发送通知（向后兼容）
        NotificationCenter.default.post(
            name: NSNotification.Name("MiNoteEditorFormatAction"),
            object: MiNoteEditor.FormatAction.strikethrough
        )
        onFormatAction?(.strikethrough)
    }
    
    private func handleBoldToggle() {
        print("🔧 [FormatMenuView] handleBoldToggle - 切换前: \(context.hasStyle(RichTextStyle.bold))")
        // 使用 RichTextContext 直接切换格式
        context.toggleStyle(RichTextStyle.bold)
        print("🔧 [FormatMenuView] handleBoldToggle - 切换后: \(context.hasStyle(RichTextStyle.bold))")
        // 同时发送通知（向后兼容）
        NotificationCenter.default.post(
            name: NSNotification.Name("MiNoteEditorFormatAction"),
            object: MiNoteEditor.FormatAction.bold
        )
        onFormatAction?(.bold)
    }
    
    private func handleItalicToggle() {
        print("🔧 [FormatMenuView] handleItalicToggle - 切换前: \(context.hasStyle(RichTextStyle.italic))")
        // 使用 RichTextContext 直接切换格式（与粗体、下划线等操作一致）
        context.toggleStyle(RichTextStyle.italic)
        print("🔧 [FormatMenuView] handleItalicToggle - 切换后: \(context.hasStyle(RichTextStyle.italic))")
        print("🔧 [FormatMenuView] handleItalicToggle - context.styles: \(context.styles)")
        // 同时发送通知（向后兼容）
        NotificationCenter.default.post(
            name: NSNotification.Name("MiNoteEditorFormatAction"),
            object: MiNoteEditor.FormatAction.italic
        )
        onFormatAction?(.italic)
    }
    
    private func handleHighlightToggle() {
        print("🔧 [FormatMenuView] handleHighlightToggle - 切换前: \(isHighlight)")
        // 使用 RichTextContext 切换高亮背景色
        if isHighlight {
            // 移除高亮：设置为透明色
            context.setColor(.background, to: NSColor.clear)
        } else {
            // 添加高亮：使用黄色半透明（与小米笔记颜色一致）
            let highlightColor = NSColor(hex: "9affe8af") ?? NSColor.yellow.withAlphaComponent(0.5)
            context.setColor(.background, to: highlightColor)
        }
        print("🔧 [FormatMenuView] handleHighlightToggle - 切换后: \(isHighlight)")
        // 同时发送通知（向后兼容）
        NotificationCenter.default.post(
            name: NSNotification.Name("MiNoteEditorFormatAction"),
            object: MiNoteEditor.FormatAction.highlight
        )
        onFormatAction?(.highlight)
    }
}

#Preview {
    FormatMenuView(context: RichTextContext())
        .padding()
}

