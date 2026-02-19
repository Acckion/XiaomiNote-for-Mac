//
//  NativeFormatMenuView.swift
//  MiNoteMac
//
//  原生编辑器格式菜单视图 - 提供富文本格式选项
//
//  _Requirements: 9.1, 9.2, 9.3_
//

import SwiftUI

/// 文本样式枚举（对应小米笔记格式）
enum NativeTextStyle: String, CaseIterable {
    case title = "大标题" // <size>
    case subtitle = "二级标题" // <mid-size>
    case subheading = "三级标题" // <h3-size>
    case body = "正文" // 普通文本
    case bulletList = "•  无序列表" // <bullet>
    case numberedList = "1. 有序列表" // <order>

    var displayName: String {
        rawValue
    }

    /// 对应的 TextFormat
    var textFormat: TextFormat? {
        switch self {
        case .title: .heading1
        case .subtitle: .heading2
        case .subheading: .heading3
        case .body: nil
        case .bulletList: .bulletList
        case .numberedList: .numberedList
        }
    }

    /// 对应的 ParagraphFormat（用于与 FormatStateManager 集成）
    /// _Requirements: 9.1_
    var paragraphFormat: ParagraphFormat {
        switch self {
        case .title: .heading1
        case .subtitle: .heading2
        case .subheading: .heading3
        case .body: .body
        case .bulletList: .bulletList
        case .numberedList: .numberedList
        }
    }
}

/// 原生编辑器格式菜单视图
/// _Requirements: 9.1, 9.2, 9.3_
struct NativeFormatMenuView: View {

    // MARK: - Properties

    @ObservedObject var context: NativeEditorContext
    @StateObject private var stateChecker = EditorStateConsistencyChecker.shared
    /// 格式状态管理器 - 用于统一工具栏和菜单栏的格式状态
    /// _Requirements: 9.1_
    @ObservedObject private var stateManager = FormatStateManager.shared
    var onFormatApplied: ((TextFormat) -> Void)?

    /// 是否在标题段落中（用于禁用格式按钮）
    @State private var isInTitleParagraph = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 状态提示（当编辑器不可编辑时显示）
            if !stateChecker.formatButtonsEnabled || isInTitleParagraph {
                stateWarningView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }

            // 顶部格式化按钮组（加粗、斜体、下划线、删除线、高亮）
            HStack(spacing: 8) {
                // 加粗按钮
                // _Requirements: 9.2_
                Button(action: {
                    applyFormat(.bold)
                }) {
                    Text("B")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(stateManager.currentState.isBold ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(stateManager.currentState.isBold ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled || isInTitleParagraph)

                // 斜体按钮
                // _Requirements: 9.2_
                Button(action: {
                    applyFormat(.italic)
                }) {
                    Image(systemName: "italic")
                        .font(.system(size: 16))
                        .foregroundColor(stateManager.currentState.isItalic ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(stateManager.currentState.isItalic ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled || isInTitleParagraph)

                // 下划线按钮
                // _Requirements: 9.2_
                Button(action: {
                    applyFormat(.underline)
                }) {
                    Text("U")
                        .font(.system(size: 14, weight: .regular))
                        .underline()
                        .foregroundColor(stateManager.currentState.isUnderline ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(stateManager.currentState.isUnderline ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled || isInTitleParagraph)

                // 删除线按钮
                // _Requirements: 9.2_
                Button(action: {
                    applyFormat(.strikethrough)
                }) {
                    Text("S")
                        .font(.system(size: 14, weight: .regular))
                        .strikethrough()
                        .foregroundColor(stateManager.currentState.isStrikethrough ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(stateManager.currentState.isStrikethrough ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled || isInTitleParagraph)

                // 高亮按钮
                // _Requirements: 9.2_
                Button(action: {
                    applyFormat(.highlight)
                }) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 12))
                        .foregroundColor(stateManager.currentState.isHighlight ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(stateManager.currentState.isHighlight ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled || isInTitleParagraph)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // 分割线
            Divider()

            // 文本样式列表（单选：大标题、二级标题、三级标题、正文、无序列表、有序列表）
            VStack(spacing: 0) {
                ForEach(NativeTextStyle.allCases, id: \.self) { style in
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
                    .disabled(!stateChecker.formatButtonsEnabled || isInTitleParagraph)
                }
            }

            // 分割线（文本样式列表和引用块之间）
            Divider()

            // 引用块（可勾选）
            // _Requirements: 9.2_
            VStack(spacing: 0) {
                Button(action: {
                    applyFormat(.quote)
                }) {
                    HStack {
                        // 勾选标记（根据 stateManager 状态动态显示）
                        if stateManager.currentState.isQuote {
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
                    .padding(.vertical, 8)
                    .background(stateManager.currentState.isQuote ? Color.yellow.opacity(0.1) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled || isInTitleParagraph)
            }

            // 分割线（引用块和对齐按钮组之间）
            Divider()

            // 对齐按钮组（居左、居中、居右）
            // _Requirements: 9.2_
            HStack(spacing: 8) {
                // 居左按钮（默认状态，当没有居中和居右时为激活）
                Button(action: {
                    // 清除居中和居右格式，恢复默认左对齐
                    clearAlignmentFormats()
                }) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 12))
                        .foregroundColor(stateManager.currentState.alignment == .left ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(stateManager.currentState.alignment == .left ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled || isInTitleParagraph)

                // 居中按钮
                Button(action: {
                    applyFormat(.alignCenter)
                }) {
                    Image(systemName: "text.aligncenter")
                        .font(.system(size: 12))
                        .foregroundColor(stateManager.currentState.alignment == .center ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(stateManager.currentState.alignment == .center ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled || isInTitleParagraph)

                // 居右按钮
                Button(action: {
                    applyFormat(.alignRight)
                }) {
                    Image(systemName: "text.alignright")
                        .font(.system(size: 12))
                        .foregroundColor(stateManager.currentState.alignment == .right ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(stateManager.currentState.alignment == .right ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled || isInTitleParagraph)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 200)
        .onAppear {
            // 格式菜单显示时，保持编辑器焦点状态为 true
            if !context.isEditorFocused {
                context.setEditorFocused(true)
            }

            // 更新 EditorStateConsistencyChecker 的状态
            if context.isEditorFocused, context.nsAttributedText.length > 0 {
                stateChecker.updateState(.editable, reason: "格式菜单显示")
            }

            // 检查是否在标题段落中
            isInTitleParagraph = checkIfInTitleParagraph()

            // 请求从 textView 同步内容
            context.requestContentSync()

            // 强制刷新 FormatStateManager 状态
            // _Requirements: 9.1_
            stateManager.forceRefresh()

            // 使用延迟确保同步完成后再更新格式状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                context.forceUpdateFormats()
                stateManager.forceRefresh()
                // 再次检查标题段落状态
                isInTitleParagraph = checkIfInTitleParagraph()
            }
        }
        .onChange(of: stateManager.currentState) { _, _ in
        }
        .onChange(of: context.currentFormats) { _, _ in
        }
        .onChange(of: stateChecker.formatButtonsEnabled) { _, _ in
        }
        .onChange(of: context.isEditorFocused) { _, newValue in
            if newValue, context.nsAttributedText.length > 0 {
                stateChecker.updateState(.editable, reason: "编辑器获得焦点")
            }
        }
        .onChange(of: context.selectedRange) { _, _ in
            // 当光标位置变化时，重新检查是否在标题段落中
            isInTitleParagraph = checkIfInTitleParagraph()
        }
        .onChange(of: context.nsAttributedText) { _, _ in
            // 当内容变化时，重新检查是否在标题段落中
            isInTitleParagraph = checkIfInTitleParagraph()
        }
    }

    // MARK: - State Warning View

    /// 状态警告视图
    private var stateWarningView: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(warningMessage)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.1))
        )
    }

    /// 警告消息
    private var warningMessage: String {
        if isInTitleParagraph {
            "标题格式不可修改"
        } else {
            stateChecker.currentState.userMessage ?? "格式操作不可用"
        }
    }

    // MARK: - Helper Methods

    /// 检查当前光标是否在标题段落中
    /// - Returns: 是否在标题段落中
    private func checkIfInTitleParagraph() -> Bool {
        let textStorage = context.nsAttributedText
        let cursorPosition = context.selectedRange.location

        // 检查光标位置是否在标题段落中
        if cursorPosition < textStorage.length {
            // 获取光标所在行的范围
            let string = textStorage.string as NSString
            let lineRange = string.lineRange(for: NSRange(location: cursorPosition, length: 0))

            // 检查该行是否有 .isTitle 属性
            if lineRange.location < textStorage.length {
                let attributes = textStorage.attributes(at: lineRange.location, effectiveRange: nil)
                if let isTitle = attributes[.isTitle] as? Bool, isTitle {
                    return true
                }
            }
        }

        return false
    }

    /// 检查样式是否被选中
    /// 使用 FormatStateManager 的状态来判断
    private func isStyleSelected(_ style: NativeTextStyle) -> Bool {
        stateManager.currentState.paragraphFormat == style.paragraphFormat
    }

    /// 清除对齐格式（恢复默认左对齐）
    private func clearAlignmentFormats() {
        // 检查是否在标题段落中，如果是则禁止格式操作
        if isInTitleParagraph {
            return
        }

        // 使用 FormatStateManager 清除对齐格式
        if stateManager.hasActiveEditor {
            stateManager.clearAlignmentFormat()
        } else {
            context.clearAlignmentFormat()
        }
        onFormatApplied?(.alignCenter)
    }

    /// 处理样式选择
    private func handleStyleSelection(_ style: NativeTextStyle) {
        // 检查是否在标题段落中，如果是则禁止格式操作
        if isInTitleParagraph {
            return
        }

        switch style {
        case .title:
            applyFormat(.heading1)
        case .subtitle:
            applyFormat(.heading2)
        case .subheading:
            applyFormat(.heading3)
        case .body:
            // 正文：清除段落格式
            if stateManager.hasActiveEditor {
                stateManager.clearParagraphFormat()
            } else {
                context.clearHeadingFormat()
            }
            onFormatApplied?(.heading1)
        case .bulletList:
            applyFormat(.bulletList)
        case .numberedList:
            applyFormat(.numberedList)
        }
    }

    /// 根据样式返回对应的字体
    private func fontForStyle(_ style: NativeTextStyle) -> Font {
        switch style {
        case .title:
            .system(size: 16, weight: .bold)
        case .subtitle:
            .system(size: 14, weight: .semibold)
        case .subheading:
            .system(size: 13, weight: .medium)
        case .body:
            .system(size: 13)
        case .bulletList, .numberedList:
            .system(size: 13)
        }
    }

    /// 应用格式
    /// 使用 FormatStateManager 确保工具栏和菜单栏状态同步
    /// _Requirements: 9.3_
    private func applyFormat(_ format: TextFormat) {
        // 检查是否在标题段落中，如果是则禁止格式操作
        if isInTitleParagraph {
            return
        }

        // 验证格式操作是否允许
        guard stateChecker.validateFormatOperation(format) else {
            return
        }

        // 优先使用 FormatStateManager 应用格式，确保状态同步
        if stateManager.hasActiveEditor {
            stateManager.toggleFormat(format)
        } else {
            // 回退到直接使用 context
            context.applyFormat(format, method: .menu)
        }

        onFormatApplied?(format)
    }
}

// MARK: - Debug Logging Extension

extension NativeFormatMenuView {
    /// 打印当前格式状态（调试用）
    private func logFormatState() {
        // 调试日志已移除
    }
}

// MARK: - Preview

#Preview {
    NativeFormatMenuView(context: NativeEditorContext())
        .frame(width: 220, height: 400)
}
