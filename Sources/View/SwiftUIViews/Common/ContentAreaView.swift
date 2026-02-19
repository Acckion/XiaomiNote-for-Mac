//
//  ContentAreaView.swift
//  MiNoteMac
//
//  内容区域视图 - 根据视图模式显示不同的内容
//

import AppKit
import SwiftUI

// MARK: - 通知名称扩展

extension Notification.Name {
    /// 返回画廊视图请求通知
    static let backToGalleryRequested = Notification.Name("backToGalleryRequested")
}

// MARK: - ContentAreaView

/// 内容区域视图
///
/// 根据视图模式（列表/画廊）显示不同的内容，并管理展开笔记状态
/// 负责协调 GalleryView 和 ExpandedNoteView 之间的动画过渡
@available(macOS 14.0, *)
struct ContentAreaView: View {

    // MARK: - 属性

    /// 应用协调器（共享数据层）
    let coordinator: AppCoordinator

    /// 窗口状态（窗口独立状态）
    @ObservedObject var windowState: WindowState

    /// 视图选项管理器
    @ObservedObject var optionsManager: ViewOptionsManager

    // MARK: - 状态

    /// 动画命名空间（用于 matchedGeometryEffect）
    @Namespace private var animation

    // MARK: - 视图

    var body: some View {
        ZStack {
            switch optionsManager.viewMode {
            case .list:
                // 列表模式：笔记列表 + 编辑器
                listModeContent

            case .gallery:
                // 画廊模式：根据是否有展开的笔记显示不同内容
                galleryModeContent
            }
        }
        // 动画配置：easeInOut，时长 350ms
        .animation(.easeInOut(duration: 0.35), value: windowState.expandedNote?.id)
        // 同步 expandedNote 状态到 notesViewModel（用于工具栏可见性管理）
        .onChange(of: windowState.expandedNote?.id) { _, newValue in
            coordinator.notesViewModel.isGalleryExpanded = (newValue != nil)
        }
        // 视图模式切换时重置展开状态
        .onChange(of: optionsManager.viewMode) { _, newMode in
            if newMode == .list {
                windowState.expandedNote = nil
                coordinator.notesViewModel.isGalleryExpanded = false
            }
        }
        // 监听返回画廊视图的通知
        .onReceive(NotificationCenter.default.publisher(for: .backToGalleryRequested)) { _ in
            withAnimation(.easeInOut(duration: 0.35)) {
                windowState.expandedNote = nil
            }
        }
    }

    // MARK: - 子视图

    /// 列表模式内容
    /// 使用 HSplitView 实现可调整宽度的分隔符
    private var listModeContent: some View {
        HSplitView {
            // 笔记列表
            NotesListView(
                coordinator: coordinator,
                windowState: windowState
            )
            .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)

            // 笔记详情编辑器
            NoteDetailView(
                coordinator: coordinator,
                windowState: windowState
            )
            .frame(minWidth: 400)
        }
    }

    /// 画廊模式内容
    @ViewBuilder
    private var galleryModeContent: some View {
        if let _ = windowState.expandedNote {
            // 展开模式：显示笔记编辑器
            ExpandedNoteView(
                coordinator: coordinator,
                windowState: windowState,
                animation: animation
            )
            .transition(expandedTransition)
        } else {
            // 画廊模式：显示笔记卡片网格
            GalleryView(
                coordinator: coordinator,
                windowState: windowState,
                optionsManager: optionsManager,
                animation: animation
            )
            .transition(.opacity)
        }
    }

    /// 展开视图的过渡动画
    private var expandedTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        )
    }
}

// MARK: - Preview

@available(macOS 14.0, *)
#Preview {
    // 创建预览用的 AppCoordinator 和 WindowState
    let coordinator = AppCoordinator()
    let windowState = WindowState(coordinator: coordinator)

    return ContentAreaView(
        coordinator: coordinator,
        windowState: windowState,
        optionsManager: .shared
    )
    .frame(width: 1000, height: 700)
}
