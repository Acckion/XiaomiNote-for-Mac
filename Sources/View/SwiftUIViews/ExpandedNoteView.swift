//
//  ExpandedNoteView.swift
//  MiNoteMac
//
//  展开笔记视图 - 从画廊视图点击笔记后的全屏编辑模式
//

import SwiftUI
import AppKit

// MARK: - ExpandedNoteView

/// 展开笔记视图
/// 
/// 从画廊视图点击笔记后的全屏编辑模式，包含返回按钮和笔记编辑器
/// 支持 Escape 键返回画廊视图
/// _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 7.5_
@available(macOS 14.0, *)
struct ExpandedNoteView: View {
    
    // MARK: - 属性
    
    /// 笔记视图模型
    @ObservedObject var viewModel: NotesViewModel
    
    /// 展开的笔记（绑定，用于控制展开/收起）
    @Binding var expandedNote: Note?
    
    /// 动画命名空间（用于 matchedGeometryEffect）
    var animation: Namespace.ID
    
    // MARK: - 状态
    
    /// 是否正在执行收起动画
    @State private var isCollapsing = false
    
    // MARK: - 视图
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            topToolbar
            
            Divider()
            
            // 笔记编辑器
            editorContent
        }
        .background(Color(NSColor.windowBackgroundColor))
        // Escape 键返回画廊视图
        // _Requirements: 7.5_
        .onKeyPress(.escape) {
            collapseToGallery()
            return .handled
        }
    }
    
    // MARK: - 子视图
    
    /// 顶部工具栏
    /// _Requirements: 6.3_
    private var topToolbar: some View {
        HStack(spacing: 12) {
            // 返回按钮
            Button(action: {
                collapseToGallery()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                    Text("返回")
                        .font(.system(size: 14))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            
            Spacer()
            
            // 笔记标题（可选显示）
            if let note = expandedNote {
                Text(note.title.isEmpty ? "无标题" : note.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 占位符，保持布局平衡
            Color.clear
                .frame(width: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    /// 编辑器内容
    /// _Requirements: 6.2_
    @ViewBuilder
    private var editorContent: some View {
        if let note = expandedNote {
            NoteDetailView(viewModel: viewModel)
                .matchedGeometryEffect(id: note.id, in: animation)
        } else {
            // 空状态（理论上不应该出现）
            emptyStateView
        }
    }
    
    /// 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("未选择笔记")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 方法
    
    /// 收起到画廊视图
    /// _Requirements: 6.4, 6.5_
    private func collapseToGallery() {
        guard !isCollapsing else { return }
        isCollapsing = true
        
        // 使用 easeInOut 动画，时长 350ms
        // _Requirements: 6.5_
        withAnimation(.easeInOut(duration: 0.35)) {
            expandedNote = nil
        }
        
        // 重置状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isCollapsing = false
        }
    }
}

// MARK: - Preview

@available(macOS 14.0, *)
#Preview {
    struct PreviewWrapper: View {
        @State private var expandedNote: Note? = Note(
            id: "preview-1",
            title: "预览笔记",
            content: "<new-format/><text indent=\"1\">这是一个预览笔记的内容。</text>",
            folderId: "0",
            isStarred: false,
            createdAt: Date(),
            updatedAt: Date(),
            tags: []
        )
        @Namespace private var animation
        
        var body: some View {
            ExpandedNoteView(
                viewModel: NotesViewModel(),
                expandedNote: $expandedNote,
                animation: animation
            )
            .frame(width: 800, height: 600)
        }
    }
    
    return PreviewWrapper()
}
