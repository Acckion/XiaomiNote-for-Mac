//
//  NativeFormatMenuView.swift
//  MiNoteMac
//
//  原生编辑器格式菜单视图 - 提供富文本格式选项
//  外观样式与 WebFormatMenuView 保持一致
//

import SwiftUI

/// 文本样式枚举（对应小米笔记格式）
enum NativeTextStyle: String, CaseIterable {
    case title = "大标题"           // <size>
    case subtitle = "二级标题"      // <mid-size>
    case subheading = "三级标题"   // <h3-size>
    case body = "正文"              // 普通文本
    case bulletList = "•  无序列表"    // <bullet>
    case numberedList = "1. 有序列表"  // <order>
    
    var displayName: String {
        return rawValue
    }
    
    /// 对应的 TextFormat
    var textFormat: TextFormat? {
        switch self {
        case .title: return .heading1
        case .subtitle: return .heading2
        case .subheading: return .heading3
        case .body: return nil
        case .bulletList: return .bulletList
        case .numberedList: return .numberedList
        }
    }
}

/// 原生编辑器格式菜单视图
/// 外观样式与 WebFormatMenuView 保持一致
struct NativeFormatMenuView: View {
    
    // MARK: - Properties
    
    @ObservedObject var context: NativeEditorContext
    @StateObject private var stateChecker = EditorStateConsistencyChecker.shared
    var onFormatApplied: ((TextFormat) -> Void)?
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // 状态提示（当编辑器不可编辑时显示）
            if !stateChecker.formatButtonsEnabled {
                stateWarningView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }
            
            // 顶部格式化按钮组（加粗、斜体、下划线、删除线、高亮）
            HStack(spacing: 8) {
                // 加粗按钮
                Button(action: {
                    applyFormat(.bold)
                }) {
                    Text("B")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(context.isFormatActive(.bold) ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isFormatActive(.bold) ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled)
                
                // 斜体按钮
                Button(action: {
                    applyFormat(.italic)
                }) {
                    Image(systemName: "italic")
                        .font(.system(size: 16))
                        .foregroundColor(context.isFormatActive(.italic) ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isFormatActive(.italic) ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled)
                
                // 下划线按钮
                Button(action: {
                    applyFormat(.underline)
                }) {
                    Text("U")
                        .font(.system(size: 14, weight: .regular))
                        .underline()
                        .foregroundColor(context.isFormatActive(.underline) ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isFormatActive(.underline) ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled)
                
                // 删除线按钮
                Button(action: {
                    applyFormat(.strikethrough)
                }) {
                    Text("S")
                        .font(.system(size: 14, weight: .regular))
                        .strikethrough()
                        .foregroundColor(context.isFormatActive(.strikethrough) ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isFormatActive(.strikethrough) ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled)
                
                // 高亮按钮
                Button(action: {
                    applyFormat(.highlight)
                }) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 12))
                        .foregroundColor(context.isFormatActive(.highlight) ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isFormatActive(.highlight) ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled)
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
                    .disabled(!stateChecker.formatButtonsEnabled)
                }
            }
            
            // 分割线（文本样式列表和引用块之间）
            Divider()
            
            // 引用块（可勾选）
            VStack(spacing: 0) {
                Button(action: {
                    applyFormat(.quote)
                }) {
                    HStack {
                        // 勾选标记（根据编辑器状态动态显示）
                        if context.isFormatActive(.quote) {
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
                    .background(context.isFormatActive(.quote) ? Color.yellow.opacity(0.1) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled)
            }
            
            // 分割线（引用块和对齐按钮组之间）
            Divider()
            
            // 对齐按钮组（居左、居中、居右）
            HStack(spacing: 8) {
                // 居左按钮（默认状态，当没有居中和居右时为激活）
                Button(action: {
                    // 清除居中和居右格式，恢复默认左对齐
                    clearAlignmentFormats()
                }) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 12))
                        .foregroundColor(isLeftAlignmentActive() ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(isLeftAlignmentActive() ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled)
                
                // 居中按钮
                Button(action: {
                    applyFormat(.alignCenter)
                }) {
                    Image(systemName: "text.aligncenter")
                        .font(.system(size: 12))
                        .foregroundColor(context.isFormatActive(.alignCenter) ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isFormatActive(.alignCenter) ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled)
                
                // 居右按钮
                Button(action: {
                    applyFormat(.alignRight)
                }) {
                    Image(systemName: "text.alignright")
                        .font(.system(size: 12))
                        .foregroundColor(context.isFormatActive(.alignRight) ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(context.isFormatActive(.alignRight) ? Color.yellow : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!stateChecker.formatButtonsEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 200)
        .onAppear {
            print("✅ [NativeFormatMenuView] onAppear 开始")
            logFormatState()
            
            // 格式菜单显示时，保持编辑器焦点状态为 true
            if !context.isEditorFocused {
                print("🔧 [NativeFormatMenuView] 设置编辑器焦点状态为 true（格式菜单显示）")
                context.setEditorFocused(true)
            }
            
            // 更新 EditorStateConsistencyChecker 的状态
            if context.isEditorFocused && context.nsAttributedText.length > 0 {
                print("🔧 [NativeFormatMenuView] 更新 EditorStateConsistencyChecker 状态为 editable")
                stateChecker.updateState(.editable, reason: "格式菜单显示")
            }
            
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
        .onChange(of: context.isEditorFocused) { oldValue, newValue in
            print("🔄 [NativeFormatMenuView] 编辑器焦点状态变化: \(oldValue) -> \(newValue)")
            if newValue && context.nsAttributedText.length > 0 {
                stateChecker.updateState(.editable, reason: "编辑器获得焦点")
            }
        }
    }
    
    // MARK: - State Warning View
    
    /// 状态警告视图
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
    
    // MARK: - Helper Methods
    
    /// 检查样式是否被选中
    private func isStyleSelected(_ style: NativeTextStyle) -> Bool {
        switch style {
        case .title:
            return context.isFormatActive(.heading1)
        case .subtitle:
            return context.isFormatActive(.heading2)
        case .subheading:
            return context.isFormatActive(.heading3)
        case .body:
            // 正文：没有标题格式且没有列表格式
            return !context.isFormatActive(.heading1) &&
                   !context.isFormatActive(.heading2) &&
                   !context.isFormatActive(.heading3) &&
                   !context.isFormatActive(.bulletList) &&
                   !context.isFormatActive(.numberedList)
        case .bulletList:
            return context.isFormatActive(.bulletList)
        case .numberedList:
            return context.isFormatActive(.numberedList)
        }
    }
    
    /// 检查左对齐是否激活（默认状态）
    private func isLeftAlignmentActive() -> Bool {
        // 居左是默认状态，当没有居中和居右时为激活
        return !context.isFormatActive(.alignCenter) && !context.isFormatActive(.alignRight)
    }
    
    /// 清除对齐格式（恢复默认左对齐）
    private func clearAlignmentFormats() {
        context.clearAlignmentFormat()
        onFormatApplied?(.alignCenter)
    }
    
    /// 处理样式选择
    private func handleStyleSelection(_ style: NativeTextStyle) {
        switch style {
        case .title:
            applyFormat(.heading1)
        case .subtitle:
            applyFormat(.heading2)
        case .subheading:
            applyFormat(.heading3)
        case .body:
            // 正文：清除标题格式（应用 heading1 再取消，或者直接设置为普通段落）
            // 这里需要一个清除标题格式的方法
            context.clearHeadingFormat()
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
    
    private func applyFormat(_ format: TextFormat) {
        // 验证格式操作是否允许
        guard stateChecker.validateFormatOperation(format) else {
            print("⚠️ [NativeFormatMenuView] 格式操作被拒绝: \(format.displayName)")
            return
        }
        
        // 使用菜单应用方式，确保一致性检查
        context.applyFormat(format, method: .menu)
        onFormatApplied?(format)
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
        print("   - 引用: \(context.isFormatActive(.quote))")
        print("   - 当前格式集合: \(context.currentFormats)")
        print("   - 光标位置: \(context.cursorPosition)")
        print("   - 选择范围: \(context.selectedRange)")
    }
}

// MARK: - Preview

#Preview {
    NativeFormatMenuView(context: NativeEditorContext())
        .frame(width: 220, height: 400)
}
