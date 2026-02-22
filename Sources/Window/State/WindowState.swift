//
//  WindowState.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  窗口状态管理器 - 管理单个窗口的 UI 状态
//

import Combine
import Foundation
import SwiftUI

/// 窗口状态管理器
///
/// 负责管理单个窗口的 UI 状态，包括：
/// - 选中的笔记和文件夹
/// - 展开的笔记（画廊视图）
/// - 滚动位置
/// - 文件夹展开状态
/// - 侧边栏显示状态
///
/// **设计原则**:
/// - 每个窗口有独立的 WindowState 实例
/// - 弱引用 AppCoordinator 避免循环引用
/// - 通过 AppCoordinator 访问共享数据
/// - 使用 @Published 属性支持 SwiftUI 绑定
///
/// **线程安全**: 使用 @MainActor 确保所有操作在主线程执行
@MainActor
public final class WindowState: ObservableObject {
    // MARK: - 共享数据层引用

    /// AppCoordinator 引用（弱引用避免循环引用）
    private(set) weak var coordinator: AppCoordinator?

    // MARK: - 窗口独立状态

    /// 当前选中的笔记（从 NoteListState 单向同步）
    @Published public var selectedNote: Note?

    /// 当前展开的笔记（用于画廊视图）
    @Published public var expandedNote: Note?

    /// 笔记列表滚动位置
    @Published public var scrollPosition: CGFloat = 0

    /// 文件夹展开状态（存储展开的文件夹 ID）
    @Published public var expandedFolders: Set<String> = []

    /// 是否显示侧边栏
    @Published public var showSidebar = true

    /// 窗口唯一标识符
    public let windowId: UUID

    // MARK: - Private Properties

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    /// 初始化窗口状态
    ///
    /// - Parameter coordinator: AppCoordinator 实例（弱引用）
    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.windowId = UUID()

        LogService.shared.debug(.window, "初始化窗口状态，ID: \(windowId)")

        setupBindings()
    }

    deinit {
        // deinit 不在 MainActor 上，无法调用 LogService（MainActor 隔离）
    }

    // MARK: - 操作方法

    /// 选择笔记
    ///
    /// 通过 AppCoordinator 处理笔记选择
    public func selectNote(_ note: Note) {
        coordinator?.handleNoteSelection(note)
    }

    /// 选择文件夹
    ///
    /// 通知 AppCoordinator 更新文件夹选择
    public func selectFolder(_ folder: Folder?) {
        coordinator?.handleFolderSelection(folder)
    }

    /// 展开笔记（画廊视图）
    ///
    /// - Parameter note: 要展开的笔记
    public func expandNote(_ note: Note) {
        expandedNote = note
    }

    /// 折叠笔记（画廊视图）
    public func collapseNote() {
        expandedNote = nil
    }

    /// 切换文件夹展开状态
    ///
    /// - Parameter folderId: 文件夹 ID
    public func toggleFolderExpansion(_ folderId: String) {
        if expandedFolders.contains(folderId) {
            expandedFolders.remove(folderId)
        } else {
            expandedFolders.insert(folderId)
        }
    }

    /// 切换侧边栏显示状态
    public func toggleSidebar() {
        showSidebar.toggle()
    }

    /// 更新滚动位置
    ///
    /// - Parameter position: 新的滚动位置
    public func updateScrollPosition(_ position: CGFloat) {
        scrollPosition = position
    }

    // MARK: - 私有方法

    /// 设置数据绑定
    ///
    /// 从 NoteListState 单向同步 selectedNote
    private func setupBindings() {
        guard let coordinator else {
            LogService.shared.warning(.window, "AppCoordinator 为 nil，无法设置绑定")
            return
        }

        // 从 NoteListState 单向同步 selectedNote
        coordinator.noteListState.$selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                if selectedNote?.id != note?.id {
                    selectedNote = note
                }
            }
            .store(in: &cancellables)

        // 同步文件夹列表（仅用于清理展开状态）
        coordinator.folderState.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] folders in
                guard let self else { return }
                let folderIds = Set(folders.map(\.id))
                expandedFolders = expandedFolders.intersection(folderIds)
            }
            .store(in: &cancellables)
    }
}
