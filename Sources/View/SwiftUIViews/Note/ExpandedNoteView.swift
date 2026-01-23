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
/// 从画廊视图点击笔记后的全屏编辑模式
/// 导航功能已移至工具栏的返回按钮
/// 支持 Escape 键返回画廊视图
/// _Requirements: 6.1, 6.2, 6.4, 6.5, 7.5_
@available(macOS 14.0, *)
struct ExpandedNoteView: View {
    
    // MARK: - 属性
    
    /// 应用协调器（共享数据层）
    let coordinator: AppCoordinator
    
    /// 窗口状态（窗口独立状态）
    @ObservedObject var windowState: WindowState
    
    /// 动画命名空间（用于 matchedGeometryEffect）
    var animation: Namespace.ID
    
    // MARK: - 状态
    
    /// 是否正在执行收起动画
    @State private var isCollapsing = false
    
    // MARK: - 视图
    
    var body: some View {
        // 直接显示笔记编辑器，不需要额外的包装层
        // 导航功能已移至工具栏的返回按钮
        editorContent
            .background(Color(NSColor.windowBackgroundColor))
            // Escape 键返回画廊视图
            // _Requirements: 7.5_
            .onKeyPress(.escape) {
                collapseToGallery()
                return .handled
            }
    }
    
    // MARK: - 子视图
    
    /// 编辑器内容
    /// _Requirements: 6.2_
    @ViewBuilder
    private var editorContent: some View {
        if let note = windowState.expandedNote {
            NoteDetailView(
                coordinator: coordinator,
                windowState: windowState
            )
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
            windowState.collapseNote()
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
        @Namespace private var animation
        
        var body: some View {
            let coordinator = AppCoordinator()
            let windowState = WindowState(coordinator: coordinator)
            
            // 设置一个展开的笔记用于预览
            windowState.expandedNote = Note(
                id: "preview-1",
                title: "预览笔记",
                content: "<new-format/><text indent=\"1\">这是一个预览笔记的内容。</text>",
                folderId: "0",
                isStarred: false,
                createdAt: Date(),
                updatedAt: Date(),
                tags: []
            )
            
            return ExpandedNoteView(
                coordinator: coordinator,
                windowState: windowState,
                animation: animation
            )
            .frame(width: 800, height: 600)
        }
    }
    
    return PreviewWrapper()
}
