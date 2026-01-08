//
//  NativeFormatMenuView.swift
//  MiNoteMac
//
//  原生编辑器格式菜单视图 - 提供富文本格式选项
//

import SwiftUI

/// 原生编辑器格式菜单视图
struct NativeFormatMenuView: View {
    
    // MARK: - Properties
    
    @ObservedObject var context: NativeEditorContext
    var onFormatApplied: ((TextFormat) -> Void)?
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 文本样式部分
            textStyleSection
            
            Divider()
            
            // 段落样式部分
            paragraphStyleSection
            
            Divider()
            
            // 列表样式部分
            listStyleSection
            
            Divider()
            
            // 特殊元素部分
            specialElementSection
        }
        .padding(16)
        .frame(width: 280)
    }
    
    // MARK: - Text Style Section
    
    private var textStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文本样式")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                FormatButton(
                    title: "加粗",
                    icon: "bold",
                    isActive: context.isFormatActive(.bold),
                    shortcut: "⌘B"
                ) {
                    applyFormat(.bold)
                }
                
                FormatButton(
                    title: "斜体",
                    icon: "italic",
                    isActive: context.isFormatActive(.italic),
                    shortcut: "⌘I"
                ) {
                    applyFormat(.italic)
                }
                
                FormatButton(
                    title: "下划线",
                    icon: "underline",
                    isActive: context.isFormatActive(.underline),
                    shortcut: "⌘U"
                ) {
                    applyFormat(.underline)
                }
                
                FormatButton(
                    title: "删除线",
                    icon: "strikethrough",
                    isActive: context.isFormatActive(.strikethrough)
                ) {
                    applyFormat(.strikethrough)
                }
                
                FormatButton(
                    title: "高亮",
                    icon: "highlighter",
                    isActive: context.isFormatActive(.highlight)
                ) {
                    applyFormat(.highlight)
                }
            }
        }
    }
    
    // MARK: - Paragraph Style Section
    
    private var paragraphStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("段落样式")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // 标题样式
            HStack(spacing: 8) {
                FormatButton(
                    title: "大标题",
                    icon: "textformat.size.larger",
                    isActive: context.isFormatActive(.heading1)
                ) {
                    applyFormat(.heading1)
                }
                
                FormatButton(
                    title: "二级标题",
                    icon: "textformat.size",
                    isActive: context.isFormatActive(.heading2)
                ) {
                    applyFormat(.heading2)
                }
                
                FormatButton(
                    title: "三级标题",
                    icon: "textformat.size.smaller",
                    isActive: context.isFormatActive(.heading3)
                ) {
                    applyFormat(.heading3)
                }
            }
            
            // 对齐方式
            HStack(spacing: 8) {
                FormatButton(
                    title: "居中",
                    icon: "text.aligncenter",
                    isActive: context.isFormatActive(.alignCenter)
                ) {
                    applyFormat(.alignCenter)
                }
                
                FormatButton(
                    title: "右对齐",
                    icon: "text.alignright",
                    isActive: context.isFormatActive(.alignRight)
                ) {
                    applyFormat(.alignRight)
                }
            }
        }
    }
    
    // MARK: - List Style Section
    
    private var listStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("列表样式")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                FormatButton(
                    title: "无序列表",
                    icon: "list.bullet",
                    isActive: context.isFormatActive(.bulletList)
                ) {
                    applyFormat(.bulletList)
                }
                
                FormatButton(
                    title: "有序列表",
                    icon: "list.number",
                    isActive: context.isFormatActive(.numberedList)
                ) {
                    applyFormat(.numberedList)
                }
                
                FormatButton(
                    title: "复选框",
                    icon: "checklist",
                    isActive: context.isFormatActive(.checkbox)
                ) {
                    applyFormat(.checkbox)
                }
            }
        }
    }
    
    // MARK: - Special Element Section
    
    private var specialElementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("特殊元素")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                FormatButton(
                    title: "引用",
                    icon: "text.quote",
                    isActive: context.isFormatActive(.quote)
                ) {
                    applyFormat(.quote)
                }
                
                FormatButton(
                    title: "分割线",
                    icon: "minus",
                    isActive: false
                ) {
                    context.insertHorizontalRule()
                    onFormatApplied?(.horizontalRule)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func applyFormat(_ format: TextFormat) {
        context.applyFormat(format)
        onFormatApplied?(format)
    }
}

// MARK: - Format Button

/// 格式按钮组件
struct FormatButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    var shortcut: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isActive ? .white : .primary)
                
                Text(title)
                    .font(.caption2)
                    .foregroundColor(isActive ? .white : .secondary)
                
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 8))
                        .foregroundColor(isActive ? .white.opacity(0.8) : .secondary.opacity(0.6))
                }
            }
            .frame(width: 48, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .help(title + (shortcut != nil ? " (\(shortcut!))" : ""))
    }
}

// MARK: - Preview

#Preview {
    NativeFormatMenuView(context: NativeEditorContext())
        .frame(width: 300, height: 400)
}
