//
//  RichTextKitAttachmentTestApp.swift
//  RichTextKit 新增功能测试应用
//
//  用于测试新增的 RichTextKit 附件功能：
//  - 待办复选框（Checkbox）
//  - 分割线（Horizontal Rule）
//  - 引用块（Block Quote）
//

import SwiftUI
import RichTextKit
import AppKit

@main
struct RichTextKitAttachmentTestApp: App {
    var body: some Scene {
        WindowGroup {
            AttachmentTestView()
                .frame(minWidth: 900, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 700)
    }
}

struct AttachmentTestView: View {
    @State private var text = NSAttributedString(string: "")
    @StateObject private var context = RichTextContext()
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            toolbarView
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 编辑器
            RichTextEditor(
                text: $text,
                context: context,
                format: .archivedData
            ) { textView in
                textView.imageConfiguration = .init(
                    pasteConfiguration: .enabled,
                    dropConfiguration: .enabled,
                    maxImageSize: (
                        width: .points(600),
                        height: .points(800)
                    )
                )
            }
            .richTextEditorStyle(.standard)
            .richTextEditorConfig(
                .init(
                    isScrollingEnabled: true,
                    isScrollBarsVisible: true,
                    isContinuousSpellCheckingEnabled: true
                )
            )
        }
        .onAppear {
            setupInitialContent()
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        HStack(spacing: 16) {
            // 撤销/重做
            Group {
                Button {
                    context.handle(.undoLatestChange)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16))
                }
                .disabled(!context.canUndoLatestChange)
                .help("撤销 (⌘Z)")
                
                Button {
                    context.handle(.redoLatestChange)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 16))
                }
                .disabled(!context.canRedoLatestChange)
                .help("重做 (⌘⇧Z)")
            }
            
            Divider()
                .frame(height: 24)
            
            // 格式按钮
            Group {
                Button {
                    context.toggleStyle(.bold)
                } label: {
                    Text("B")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(context.hasStyle(.bold) ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.hasStyle(.bold) ? Color.blue : Color.clear)
                        .cornerRadius(6)
                }
                .help("加粗")
                
                Button {
                    context.toggleStyle(.italic)
                } label: {
                    Text("I")
                        .font(.system(size: 14))
                        .italic()
                        .foregroundColor(context.hasStyle(.italic) ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.hasStyle(.italic) ? Color.blue : Color.clear)
                        .cornerRadius(6)
                }
                .help("斜体")
            }
            
            Divider()
                .frame(height: 24)
            
            // 新增功能按钮
            Group {
                Button {
                    context.insertCheckbox(isChecked: false, withSpace: true)
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 16))
                }
                .help("插入待办复选框")
                
                Button {
                    context.insertHorizontalRule(withNewlines: true)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16))
                }
                .help("插入分割线")
                
                Button {
                    context.insertBlockQuote(withSpace: true)
                    context.applyBlockQuoteStyling()
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 16))
                }
                .help("插入引用块")
            }
            
            Spacer()
            
            // 状态显示
            VStack(alignment: .trailing, spacing: 4) {
                Text("选中: \(context.selectedRange.location), \(context.selectedRange.length)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    if context.hasStyle(.bold) {
                        Text("B")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    if context.hasStyle(.italic) {
                        Text("I")
                            .font(.caption)
                            .italic()
                    }
                }
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupInitialContent() {
        let content = NSMutableAttributedString()
        
        // 标题
        let title = NSAttributedString(
            string: "RichTextKit 新增功能测试\n\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 24),
                .foregroundColor: NSColor.labelColor
            ]
        )
        content.append(title)
        
        // 复选框示例
        let checkboxTitle = NSMutableAttributedString(string: "1. 待办复选框功能\n")
        checkboxTitle.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ], range: NSRange(location: 0, length: checkboxTitle.length))
        content.append(checkboxTitle)
        
        content.append(NSAttributedString(string: "点击下面的复选框可以切换选中状态（在深色模式下应显示为白色）：\n\n"))
        
        let checkbox1 = RichTextCheckboxAttachment(isChecked: false)
        content.append(NSAttributedString(attachment: checkbox1))
        content.append(NSAttributedString(string: " 未完成的待办事项\n"))
        
        let checkbox2 = RichTextCheckboxAttachment(isChecked: true)
        content.append(NSAttributedString(attachment: checkbox2))
        content.append(NSAttributedString(string: " 已完成的待办事项\n\n"))
        
        // 分割线示例
        let hrTitle = NSMutableAttributedString(string: "2. 分割线功能\n")
        hrTitle.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ], range: NSRange(location: 0, length: hrTitle.length))
        content.append(hrTitle)
        
        content.append(NSAttributedString(string: "下面的分割线高度应该与正文行高相同：\n\n"))
        
        content.append(NSAttributedString(string: "分割线上方的文本\n"))
        let hr = RichTextHorizontalRuleAttachment()
        content.append(NSAttributedString(string: "\n"))
        content.append(NSAttributedString(attachment: hr))
        content.append(NSAttributedString(string: "\n"))
        content.append(NSAttributedString(string: "分割线下方的文本\n\n"))
        
        // 引用块示例
        let quoteTitle = NSMutableAttributedString(string: "3. 引用块功能\n")
        quoteTitle.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ], range: NSRange(location: 0, length: quoteTitle.length))
        content.append(quoteTitle)
        
        content.append(NSAttributedString(string: "下面的文本使用了引用块样式（左侧有竖线，并有缩进）：\n\n"))
        
        let blockQuote = RichTextBlockQuoteAttachment(indicatorColor: NSColor.separatorColor)
        let quoteContent = NSMutableAttributedString(attributedString: NSAttributedString(attachment: blockQuote))
        quoteContent.append(NSAttributedString(string: " 这是一段引用文本。引用块会在左侧显示一条竖线，并且有左侧缩进效果。\n"))
        
        // 应用引用块样式
        let quoteStyle = NSMutableParagraphStyle()
        quoteStyle.firstLineHeadIndent = 20
        quoteStyle.headIndent = 20
        quoteContent.addAttribute(.paragraphStyle, value: quoteStyle, range: NSRange(location: 0, length: quoteContent.length))
        
        content.append(quoteContent)
        content.append(NSAttributedString(string: "\n\n"))
        
        // 使用说明
        let instructions = NSMutableAttributedString(string: "使用说明：\n")
        instructions.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor
        ], range: NSRange(location: 0, length: instructions.length))
        content.append(instructions)
        
        content.append(NSAttributedString(string: "• 点击工具栏上的按钮可以插入新的元素\n"))
        content.append(NSAttributedString(string: "• 点击复选框可以切换选中状态\n"))
        content.append(NSAttributedString(string: "• 分割线高度会自动匹配正文行高\n"))
        content.append(NSAttributedString(string: "• 引用块可以通过工具栏按钮应用样式\n"))
        
        // 设置内容
        text = content
        context.setAttributedString(to: content)
    }
}

#Preview {
    AttachmentTestView()
        .frame(width: 900, height: 700)
}

