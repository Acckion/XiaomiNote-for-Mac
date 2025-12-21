//
//  AttachmentFeaturesDemo.swift
//  Demo
//
//  Created for testing new RichTextKit attachment features.
//  Copyright © 2024. All rights reserved.
//

import RichTextKit
import SwiftUI

/// Demo screen for testing new attachment features:
/// - Checkboxes (待办/勾选框)
/// - Horizontal Rules (分割线)
/// - Block Quotes (引用块)
struct AttachmentFeaturesDemo: View {
    
    @State private var text = NSAttributedString(string: "测试新增的 RichTextKit 功能\n\n")
    @StateObject private var context = RichTextContext()
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            toolbarView
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 编辑器
            RichTextEditor(
                text: $text,
                context: context,
                format: .archivedData
            ) { textView in
                // 配置图片支持
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
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            // 初始化一些示例内容
            setupInitialContent()
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        HStack(spacing: 12) {
            // 撤销/重做
            Group {
                Button {
                    context.handle(.undoLatestChange)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!context.canUndoLatestChange)
                .help("撤销 (⌘Z)")
                
                Button {
                    context.handle(.redoLatestChange)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!context.canRedoLatestChange)
                .help("重做 (⌘⇧Z)")
            }
            
            Divider()
                .frame(height: 20)
            
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
                .frame(height: 20)
            
            // 新增功能按钮
            Group {
                Button {
                    context.insertCheckbox(isChecked: false, withSpace: true)
                } label: {
                    Image(systemName: "checklist")
                }
                .help("插入待办复选框")
                
                Button {
                    context.insertHorizontalRule(withNewlines: true)
                } label: {
                    Image(systemName: "minus")
                }
                .help("插入分割线")
                
                Button {
                    context.insertBlockQuote(withSpace: true)
                    context.applyBlockQuoteStyling()
                } label: {
                    Image(systemName: "quote.bubble")
                }
                .help("插入引用块")
            }
            
            Spacer()
            
            // 状态显示
            VStack(alignment: .trailing, spacing: 2) {
                Text("选中范围: \(context.selectedRange.location), \(context.selectedRange.length)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("可撤销: \(context.canUndoLatestChange ? "是" : "否")")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        let checkboxSection = NSMutableAttributedString(string: "1. 待办复选框功能\n")
        checkboxSection.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ], range: NSRange(location: 0, length: checkboxSection.length))
        content.append(checkboxSection)
        
        content.append(NSAttributedString(string: "点击下面的复选框可以切换选中状态：\n"))
        
        let checkbox1 = RichTextCheckboxAttachment(isChecked: false)
        content.append(NSAttributedString(attachment: checkbox1))
        content.append(NSAttributedString(string: " 未完成的待办事项\n"))
        
        let checkbox2 = RichTextCheckboxAttachment(isChecked: true)
        content.append(NSAttributedString(attachment: checkbox2))
        content.append(NSAttributedString(string: " 已完成的待办事项\n\n"))
        
        // 分割线示例
        let hrSection = NSMutableAttributedString(string: "2. 分割线功能\n")
        hrSection.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ], range: NSRange(location: 0, length: hrSection.length))
        content.append(hrSection)
        
        content.append(NSAttributedString(string: "下面的分割线高度应该与正文行高相同：\n"))
        
        let hr = RichTextHorizontalRuleAttachment()
        content.append(NSAttributedString(string: "\n"))
        content.append(NSAttributedString(attachment: hr))
        content.append(NSAttributedString(string: "\n"))
        
        content.append(NSAttributedString(string: "分割线上方的文本\n"))
        content.append(NSAttributedString(string: "分割线下方的文本\n\n"))
        
        // 引用块示例
        let quoteSection = NSMutableAttributedString(string: "3. 引用块功能\n")
        quoteSection.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ], range: NSRange(location: 0, length: quoteSection.length))
        content.append(quoteSection)
        
        content.append(NSAttributedString(string: "下面的文本使用了引用块样式：\n"))
        
        let blockQuote = RichTextBlockQuoteAttachment(indicatorColor: NSColor.separatorColor)
        let quoteContent = NSMutableAttributedString(attributedString: NSAttributedString(attachment: blockQuote))
        quoteContent.append(NSAttributedString(string: " 这是一段引用文本。引用块会在左侧显示一条竖线，并且有左侧缩进效果。\n"))
        
        // 应用引用块样式
        let quoteStyle = NSMutableParagraphStyle()
        quoteStyle.firstLineHeadIndent = 20
        quoteStyle.headIndent = 20
        quoteContent.addAttribute(.paragraphStyle, value: quoteStyle, range: NSRange(location: 0, length: quoteContent.length))
        
        content.append(quoteContent)
        content.append(NSAttributedString(string: "\n"))
        
        // 设置内容
        text = content
        context.setAttributedString(to: content)
    }
}

#Preview {
    AttachmentFeaturesDemo()
        .frame(width: 800, height: 600)
}

