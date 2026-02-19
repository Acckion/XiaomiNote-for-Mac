//
//  NoteListViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  笔记列表视图模型 - 管理笔记列表的展示和交互
//

import Combine
import Foundation
import SwiftUI

/// 笔记列表视图模型
///
/// 负责管理笔记列表的展示和交互，包括：
/// - 加载笔记列表
/// - 按文件夹过滤笔记
/// - 按收藏状态过滤笔记
/// - 笔记排序（按修改时间、创建时间、标题）
/// - 笔记选择状态管理
/// - 笔记删除
/// - 笔记移动到文件夹
///
/// **设计原则**:
/// - 单一职责：只负责笔记列表相关的功能
/// - 依赖注入：通过构造函数注入依赖，而不是使用单例
/// - 可测试性：所有依赖都可以被 Mock，便于单元测试
///
/// **线程安全**：使用 @MainActor 确保所有 UI 更新在主线程执行
@MainActor
public final class NoteListViewModel: ObservableObject {
    // MARK: - Published Properties

    /// 笔记列表（原始数据）
    @Published public var notes: [Note] = []

    /// 当前选中的笔记
    @Published public var selectedNote: Note?

    /// 当前选中的文件夹
    @Published public var selectedFolder: Folder?

    /// 笔记排序方式
    @Published public var sortOrder: NoteSortOrder = .editDate

    /// 排序方向
    @Published public var sortDirection: SortDirection = .descending

    /// 是否只显示收藏的笔记
    @Published public var showStarredOnly = false

    /// 是否正在加载
    @Published public var isLoading = false

    /// 错误消息（用于显示错误提示）
    @Published public var errorMessage: String?

    // MARK: - Dependencies

    /// 笔记存储服务（本地数据库）
    private let noteStorage: NoteStorageProtocol

    /// 笔记网络服务（云端 API）
    private let noteService: NoteServiceProtocol

    // MARK: - Private Properties

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// 初始化笔记列表视图模型
    ///
    /// - Parameters:
    ///   - noteStorage: 笔记存储服务（本地数据库）
    ///   - noteService: 笔记网络服务（云端 API）
    public init(
        noteStorage: NoteStorageProtocol,
        noteService: NoteServiceProtocol
    ) {
        self.noteStorage = noteStorage
        self.noteService = noteService
    }

    // MARK: - Computed Properties

    /// 过滤和排序后的笔记列表
    ///
    /// 根据当前的过滤条件和排序设置，返回处理后的笔记列表
    public var filteredNotes: [Note] {
        var result = notes

        // 按文件夹过滤
        if let folder = selectedFolder {
            result = result.filter { $0.folderId == folder.id }
        }

        // 按收藏状态过滤
        if showStarredOnly {
            result = result.filter(\.isStarred)
        }

        // 排序
        result = sortNotes(result, by: sortOrder, direction: sortDirection)

        return result
    }

    // MARK: - Public Methods

    /// 加载笔记列表
    ///
    /// 从本地数据库加载所有笔记
    public func loadNotes() async {
        isLoading = true
        errorMessage = nil

        do {
            notes = try noteStorage.fetchAllNotes()
            LogService.shared.info(.viewmodel, "加载了 \(notes.count) 条笔记")
        } catch {
            errorMessage = "加载笔记失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "加载笔记失败: \(error)")
        }

        isLoading = false
    }

    /// 按文件夹过滤笔记
    ///
    /// - Parameter folder: 要过滤的文件夹，nil 表示显示所有笔记
    public func filterNotes(by folder: Folder?) {
        selectedFolder = folder
    }

    /// 设置排序方式
    ///
    /// - Parameters:
    ///   - order: 排序字段
    ///   - direction: 排序方向
    public func setSortOrder(by order: NoteSortOrder, direction: SortDirection) {
        sortOrder = order
        sortDirection = direction
    }

    /// 选择笔记
    ///
    /// - Parameter note: 要选择的笔记
    public func selectNote(_ note: Note) {
        selectedNote = note
    }

    /// 删除笔记
    ///
    /// - Parameter note: 要删除的笔记
    public func deleteNote(_ note: Note) async {
        do {
            // 从本地数据库删除
            try noteStorage.deleteNote(id: note.id)

            // 从列表中移除
            notes.removeAll { $0.id == note.id }

            // 如果删除的是当前选中的笔记，清除选择
            if selectedNote?.id == note.id {
                selectedNote = nil
            }

            LogService.shared.info(.viewmodel, "删除笔记: \(note.title)")
        } catch {
            errorMessage = "删除笔记失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "删除笔记失败: \(error)")
        }
    }

    /// 移动笔记到文件夹
    ///
    /// - Parameters:
    ///   - note: 要移动的笔记
    ///   - folder: 目标文件夹
    public func moveNote(_ note: Note, to folder: Folder) async {
        do {
            // 更新笔记的文件夹ID
            var updatedNote = note
            updatedNote.folderId = folder.id

            // 保存到本地数据库
            try noteStorage.saveNote(updatedNote)

            // 更新列表中的笔记
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = updatedNote
            }

            LogService.shared.info(.viewmodel, "移动笔记 '\(note.title)' 到文件夹 '\(folder.name)'")
        } catch {
            errorMessage = "移动笔记失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "移动笔记失败: \(error)")
        }
    }

    /// 切换收藏状态
    ///
    /// - Parameter note: 要切换收藏状态的笔记
    public func toggleStar(_ note: Note) async {
        do {
            // 更新笔记的收藏状态
            var updatedNote = note
            updatedNote.isStarred.toggle()

            // 保存到本地数据库
            try noteStorage.saveNote(updatedNote)

            // 更新列表中的笔记
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = updatedNote
            }
        } catch {
            errorMessage = "更新收藏状态失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "更新收藏状态失败: \(error)")
        }
    }

    // MARK: - Private Methods

    /// 对笔记列表进行排序
    ///
    /// - Parameters:
    ///   - notes: 要排序的笔记列表
    ///   - order: 排序字段
    ///   - direction: 排序方向
    /// - Returns: 排序后的笔记列表
    private func sortNotes(_ notes: [Note], by order: NoteSortOrder, direction: SortDirection) -> [Note] {
        let sorted: [Note] = switch order {
        case .editDate:
            notes.sorted { (note1: Note, note2: Note) -> Bool in
                note1.updatedAt > note2.updatedAt
            }
        case .createDate:
            notes.sorted { (note1: Note, note2: Note) -> Bool in
                note1.createdAt > note2.createdAt
            }
        case .title:
            notes.sorted { (note1: Note, note2: Note) -> Bool in
                note1.title.localizedCompare(note2.title) == .orderedAscending
            }
        }

        return direction == .ascending ? sorted.reversed() : sorted
    }
}
