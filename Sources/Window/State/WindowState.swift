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
    private weak var coordinator: AppCoordinator?

    // MARK: - 窗口独立状态

    /// 当前选中的笔记
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

    // MARK: - 共享数据（从 AppCoordinator 同步）

    /// 笔记列表（从 AppCoordinator 同步）
    @Published public var notes: [Note] = []

    /// 文件夹列表（从 AppCoordinator 同步）
    @Published public var folders: [Folder] = []

    /// 当前选中的文件夹（从 AppCoordinator 同步）
    @Published public var selectedFolder: Folder?

    /// 是否正在加载（从 AppCoordinator 同步）
    @Published public var isLoading = false

    /// 错误消息（从 AppCoordinator 同步）
    @Published public var errorMessage: String?

    /// 笔记排序方式（从 AppCoordinator 同步）
    @Published public var sortOrder: NoteSortOrder = .editDate

    /// 排序方向（从 AppCoordinator 同步）
    @Published public var sortDirection: SortDirection = .descending

    /// 是否只显示收藏的笔记（从 AppCoordinator 同步）
    @Published public var showStarredOnly = false

    // MARK: - Private Properties

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    /// 初始化窗口状态
    ///
    /// - Parameter coordinator: AppCoordinator 实例（弱引用）
    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        windowId = UUID()

        print("[WindowState] 初始化窗口状态，ID: \(windowId)")

        setupBindings()
    }

    deinit {
        print("[WindowState] 释放窗口状态，ID: \(windowId)")
    }

    // MARK: - 操作方法

    /// 选择笔记
    ///
    /// 更新窗口的选中状态，并通知 AppCoordinator 加载笔记内容
    ///
    /// - Parameter note: 要选择的笔记
    public func selectNote(_ note: Note) {
        print("[WindowState] 选择笔记: \(note.title)")
        selectedNote = note
        coordinator?.handleNoteSelection(note)
    }

    /// 选择文件夹
    ///
    /// 通知 AppCoordinator 更新文件夹选择，这会触发笔记列表的重新加载
    ///
    /// - Parameter folder: 要选择的文件夹（nil 表示显示所有笔记）
    public func selectFolder(_ folder: Folder?) {
        if let folder {
            print("[WindowState] 选择文件夹: \(folder.name)")
        } else {
            print("[WindowState] 清除文件夹选择")
        }
        coordinator?.handleFolderSelection(folder)
    }

    /// 展开笔记（画廊视图）
    ///
    /// - Parameter note: 要展开的笔记
    public func expandNote(_ note: Note) {
        print("[WindowState] 展开笔记: \(note.title)")
        expandedNote = note
    }

    /// 折叠笔记（画廊视图）
    public func collapseNote() {
        print("[WindowState] 折叠笔记")
        expandedNote = nil
    }

    /// 切换文件夹展开状态
    ///
    /// - Parameter folderId: 文件夹 ID
    public func toggleFolderExpansion(_ folderId: String) {
        if expandedFolders.contains(folderId) {
            expandedFolders.remove(folderId)
            print("[WindowState] 折叠文件夹: \(folderId)")
        } else {
            expandedFolders.insert(folderId)
            print("[WindowState] 展开文件夹: \(folderId)")
        }
    }

    /// 切换侧边栏显示状态
    public func toggleSidebar() {
        showSidebar.toggle()
        print("[WindowState] 侧边栏显示状态: \(showSidebar)")
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
    /// 监听 AppCoordinator 的数据变化，自动刷新 UI
    private func setupBindings() {
        guard let coordinator else {
            print("[WindowState] 警告: AppCoordinator 为 nil，无法设置绑定")
            return
        }

        // 同步笔记列表
        coordinator.noteListViewModel.$notes
            .sink { [weak self] notes in
                guard let self else { return }
                self.notes = notes

                // 如果当前选中的笔记不在新列表中，清除选择
                if let selectedNote,
                   !notes.contains(where: { $0.id == selectedNote.id })
                {
                    print("[WindowState] 选中的笔记已被删除，清除选择")
                    self.selectedNote = nil
                }

                // 如果当前选中的笔记在新列表中，更新为新版本
                if let selectedNote,
                   let updatedNote = notes.first(where: { $0.id == selectedNote.id })
                {
                    // 只有当笔记内容真正变化时才更新
                    if !selectedNote.contentEquals(updatedNote) {
                        print("[WindowState] 更新选中笔记的内容")
                        self.selectedNote = updatedNote
                    }
                }
            }
            .store(in: &cancellables)

        // 同步文件夹列表
        coordinator.folderViewModel.$folders
            .sink { [weak self] folders in
                guard let self else { return }
                self.folders = folders

                // 清理不存在的文件夹展开状态
                let folderIds = Set(folders.map(\.id))
                expandedFolders = expandedFolders.intersection(folderIds)
            }
            .store(in: &cancellables)

        // 同步选中的文件夹
        coordinator.folderViewModel.$selectedFolder
            .sink { [weak self] folder in
                self?.selectedFolder = folder
            }
            .store(in: &cancellables)

        // 同步加载状态
        coordinator.noteListViewModel.$isLoading
            .sink { [weak self] isLoading in
                self?.isLoading = isLoading
            }
            .store(in: &cancellables)

        // 同步错误消息
        coordinator.noteListViewModel.$errorMessage
            .sink { [weak self] errorMessage in
                self?.errorMessage = errorMessage
            }
            .store(in: &cancellables)

        // 同步排序方式
        coordinator.noteListViewModel.$sortOrder
            .sink { [weak self] sortOrder in
                self?.sortOrder = sortOrder
            }
            .store(in: &cancellables)

        // 同步排序方向
        coordinator.noteListViewModel.$sortDirection
            .sink { [weak self] sortDirection in
                self?.sortDirection = sortDirection
            }
            .store(in: &cancellables)

        // 同步收藏筛选
        coordinator.noteListViewModel.$showStarredOnly
            .sink { [weak self] showStarredOnly in
                self?.showStarredOnly = showStarredOnly
            }
            .store(in: &cancellables)

        print("[WindowState] 数据绑定设置完成")
    }
}
