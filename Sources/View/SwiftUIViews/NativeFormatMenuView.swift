//
//  NativeFormatMenuView.swift
//  MiNoteMac
//
//  原生编辑器格式菜单视图 - 提供富文本格式选项
//  需求: 4.3 - 当编辑器处于不可编辑状态时，格式菜单应禁用所有格式按钮
//

import SwiftUI

/// 原生编辑器格式菜单视图
struct NativeFormatMenuView: View {
    
    // MARK: - Properties
    
    @ObservedObject var context: NativeEditorContext
    @StateObject private var stateChecker = EditorStateConsistencyChecker.shared
    var onFormatApplied: ((TextFormat) -> Void)?
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 状态提示（当编辑器不可编辑时显示）
            if !stateChecker.formatButtonsEnabled {
                stateWarningView
            }
            
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
        .onAppear {
            print("✅ [NativeFormatMenuView] onAppear 开始")
            logFormatState()
            
            // 请求从 textView 同步内容
            context.requestContentSync()
            
            // 使用延迟确保同步完成后再更新格式状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("🔄 [NativeFormatMenuView] 延迟后更新格式状态")
                context.forceUpdateFormats()
                logFormatState()
            }
        }
        .onChange(of: context.currentFormats) { oldValue, newValue in
            print("🔄 [NativeFormatMenuView] 格式状态变化: \(oldValue.map { $0.displayName }) -> \(newValue.map { $0.displayName })")
        }
        .onChange(of: stateChecker.formatButtonsEnabled) { oldValue, newValue in
            print("🔄 [NativeFormatMenuView] 按钮启用状态变化: \(oldValue) -> \(newValue)")
        }
    }
    
    // MARK: - State Warning View
    
    /// 状态警告视图（需求 4.3）
    private var stateWarningView: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            Text(stateChecker.currentState.userMessage ?? "格式操作不可用")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.1))
        )
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
                    isEnabled: stateChecker.formatButtonsEnabled,
                    shortcut: "⌘B"
                ) {
                    applyFormat(.bold)
                }
                
                FormatButton(
                    title: "斜体",
                    icon: "italic",
                    isActive: context.isFormatActive(.italic),
                    isEnabled: stateChecker.formatButtonsEnabled,
                    shortcut: "⌘I"
                ) {
                    applyFormat(.italic)
                }
                
                FormatButton(
                    title: "下划线",
                    icon: "underline",
                    isActive: context.isFormatActive(.underline),
                    isEnabled: stateChecker.formatButtonsEnabled,
                    shortcut: "⌘U"
                ) {
                    applyFormat(.underline)
                }
                
                FormatButton(
                    title: "删除线",
                    icon: "strikethrough",
                    isActive: context.isFormatActive(.strikethrough),
                    isEnabled: stateChecker.formatButtonsEnabled
                ) {
                    applyFormat(.strikethrough)
                }
                
                FormatButton(
                    title: "高亮",
                    icon: "highlighter",
                    isActive: context.isFormatActive(.highlight),
                    isEnabled: stateChecker.formatButtonsEnabled
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
                    isActive: context.isFormatActive(.heading1),
                    isEnabled: stateChecker.formatButtonsEnabled
                ) {
                    applyFormat(.heading1)
                }
                
                FormatButton(
                    title: "二级标题",
                    icon: "textformat.size",
                    isActive: context.isFormatActive(.heading2),
                    isEnabled: stateChecker.formatButtonsEnabled
                ) {
                    applyFormat(.heading2)
                }
                
                FormatButton(
                    title: "三级标题",
                    icon: "textformat.size.smaller",
                    isActive: context.isFormatActive(.heading3),
                    isEnabled: stateChecker.formatButtonsEnabled
                ) {
                    applyFormat(.heading3)
                }
            }
            
            // 对齐方式
            HStack(spacing: 8) {
                FormatButton(
                    title: "居中",
                    icon: "text.aligncenter",
                    isActive: context.isFormatActive(.alignCenter),
                    isEnabled: stateChecker.formatButtonsEnabled
                ) {
                    applyFormat(.alignCenter)
                }
                
                FormatButton(
                    title: "右对齐",
                    icon: "text.alignright",
                    isActive: context.isFormatActive(.alignRight),
                    isEnabled: stateChecker.formatButtonsEnabled
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
                    isActive: context.isFormatActive(.bulletList),
                    isEnabled: stateChecker.formatButtonsEnabled
                ) {
                    applyFormat(.bulletList)
                }
                
                FormatButton(
                    title: "有序列表",
                    icon: "list.number",
                    isActive: context.isFormatActive(.numberedList),
                    isEnabled: stateChecker.formatButtonsEnabled
                ) {
                    applyFormat(.numberedList)
                }
                
                FormatButton(
                    title: "复选框",
                    icon: "checklist",
                    isActive: context.isFormatActive(.checkbox),
                    isEnabled: stateChecker.formatButtonsEnabled
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
                    isActive: context.isFormatActive(.quote),
                    isEnabled: stateChecker.formatButtonsEnabled
                ) {
                    applyFormat(.quote)
                }
                
                FormatButton(
                    title: "分割线",
                    icon: "minus",
                    isActive: false,
                    isEnabled: stateChecker.formatButtonsEnabled
                ) {
                    context.insertHorizontalRule()
                    onFormatApplied?(.horizontalRule)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func applyFormat(_ format: TextFormat) {
        // 需求 4.3: 验证格式操作是否允许
        guard stateChecker.validateFormatOperation(format) else {
            print("⚠️ [NativeFormatMenuView] 格式操作被拒绝: \(format.displayName)")
            return
        }
        
        // 需求 5.4: 使用菜单应用方式，确保一致性检查
        context.applyFormat(format, method: .menu)
        onFormatApplied?(format)
    }
}

// MARK: - Format Button

/// 格式按钮组件
/// 需求: 4.3 - 支持禁用状态
struct FormatButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    var isEnabled: Bool = true
    var shortcut: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(buttonForegroundColor)
                
                Text(title)
                    .font(.caption2)
                    .foregroundColor(buttonTextColor)
                
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 8))
                        .foregroundColor(buttonShortcutColor)
                }
            }
            .frame(width: 48, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(buttonBackgroundColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(helpText)
    }
    
    // MARK: - Computed Properties
    
    /// 按钮前景色
    private var buttonForegroundColor: Color {
        if !isEnabled {
            return .secondary.opacity(0.5)
        }
        return isActive ? .white : .primary
    }
    
    /// 按钮文本颜色
    private var buttonTextColor: Color {
        if !isEnabled {
            return .secondary.opacity(0.5)
        }
        return isActive ? .white : .secondary
    }
    
    /// 快捷键颜色
    private var buttonShortcutColor: Color {
        if !isEnabled {
            return .secondary.opacity(0.3)
        }
        return isActive ? .white.opacity(0.8) : .secondary.opacity(0.6)
    }
    
    /// 按钮背景色
    private var buttonBackgroundColor: Color {
        if !isEnabled {
            return Color.secondary.opacity(0.05)
        }
        return isActive ? Color.accentColor : Color.secondary.opacity(0.1)
    }
    
    /// 帮助文本
    private var helpText: String {
        var text = title
        if let shortcut = shortcut {
            text += " (\(shortcut))"
        }
        if !isEnabled {
            text += " - 不可用"
        }
        return text
    }
}

// MARK: - Debug Logging Extension

extension NativeFormatMenuView {
    /// 打印当前格式状态（调试用）
    private func logFormatState() {
        print("✅ [NativeFormatMenuView] 已显示，context: \(context)")
        print("   - 加粗: \(context.isFormatActive(.bold))")
        print("   - 斜体: \(context.isFormatActive(.italic))")
        print("   - 下划线: \(context.isFormatActive(.underline))")
        print("   - 删除线: \(context.isFormatActive(.strikethrough))")
        print("   - 高亮: \(context.isFormatActive(.highlight))")
        print("   - 大标题: \(context.isFormatActive(.heading1))")
        print("   - 二级标题: \(context.isFormatActive(.heading2))")
        print("   - 三级标题: \(context.isFormatActive(.heading3))")
        print("   - 居中: \(context.isFormatActive(.alignCenter))")
        print("   - 右对齐: \(context.isFormatActive(.alignRight))")
        print("   - 无序列表: \(context.isFormatActive(.bulletList))")
        print("   - 有序列表: \(context.isFormatActive(.numberedList))")
        print("   - 复选框: \(context.isFormatActive(.checkbox))")
        print("   - 引用: \(context.isFormatActive(.quote))")
        print("   - 当前格式集合: \(context.currentFormats)")
        print("   - 光标位置: \(context.cursorPosition)")
        print("   - 选择范围: \(context.selectedRange)")
    }
}

// MARK: - Preview

#Preview {
    NativeFormatMenuView(context: NativeEditorContext())
        .frame(width: 300, height: 400)
}
