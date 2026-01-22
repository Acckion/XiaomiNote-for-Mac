//
//  NoteListViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  笔记列表 ViewModel - 负责笔记列表的展示、过滤和排序
//

import Foundation
import Combine

/// 笔记排序选项
enum SortOption: String, Codable {
    case editDate = "editDate"      // 编辑日期
    case createDate = "createDate"  // 创建日期
    case title = "title"            // 标题
}

/// 笔记过滤选项
enum FilterOption: String, Codable {
    case all = "all"                // 全部
    case starred = "starred"        // 收藏
    case folder = "folder"          // 指定文件夹
}

/// 笔记列表 ViewModel
///
/// 负责管理笔记列表的展示逻辑，包括：
/// - 笔记列表加载
/// - 排序和过滤
/// - 选择管理
/// - 搜索功能
@MainActor
final class NoteListViewModel: LoadableViewModel {
    // MARK: - Dependencies

    nonisolated(unsafe) private let noteStorage: NoteStorageProtocol
    nonisolated(unsafe) private let syncService: SyncServiceProtocol

    // MARK: - Published Properties

    /// 笔记列表
    @Published var notes: [Note] = []

    /// 当前选中的笔记ID
    @Published var selectedNoteId: String?

    /// 排序选项
    @Published var sortOption: SortOption = .editDate

    /// 过滤选项
    @Published var filterOption: FilterOption = .all

    /// 当前文件夹ID（当 filterOption 为 .folder 时使用）
    @Published var currentFolderId: String?

    /// 搜索文本
    @Published var searchText = ""

    // MARK: - Computed Properties

    /// 过滤和排序后的笔记列表
    var filteredAndSortedNotes: [Note] {
        let filtered = filterNotes(notes)
        return sortNotes(filtered)
    }

    /// 当前选中的笔记
    var selectedNote: Note? {
        guard let id = selectedNoteId else { return nil }
        return notes.first { $0.id == id }
    }

    // MARK: - Initialization

    init(
        noteStorage: NoteStorageProtocol,
        syncService: SyncServiceProtocol
    ) {
        self.noteStorage = noteStorage
        self.syncService = syncService
        super.init()
    }

    // MARK: - Setup

    override func setupBindings() {
        // 监听同步完成事件，自动刷新笔记列表
        syncService.isSyncing
            .sink { [weak self] isSyncing in
                if !isSyncing {
                    Task { await self?.loadNotes() }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// 加载笔记列表
    func loadNotes() async {
        await withLoadingSafe {
            let loadedNotes = try noteStorage.fetchAllNotes()
            self.notes = loadedNotes
        }
    }

    /// 刷新笔记列表
    func refreshNotes() async {
        await loadNotes()
    }

    /// 选择笔记
    /// - Parameter noteId: 笔记ID
    func selectNote(_ noteId: String?) {
        selectedNoteId = noteId
    }

    /// 删除笔记
    /// - Parameter noteId: 笔记ID
    func deleteNote(_ noteId: String) async {
        await withLoadingSafe {
            try noteStorage.deleteNote(id: noteId)
            notes.removeAll { $0.id == noteId }

            // 如果删除的是当前选中的笔记，清除选择
            if selectedNoteId == noteId {
                selectedNoteId = nil
            }
        }
    }

    /// 切换笔记收藏状态
    /// - Parameter noteId: 笔记ID
    func toggleStarred(_ noteId: String) async {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }

        var note = notes[index]
        note.isStarred.toggle()

        await withLoadingSafe {
            try noteStorage.saveNote(note)
            notes[index] = note
        }
    }

    /// 设置排序选项
    /// - Parameter option: 排序选项
    func setSortOption(_ option: SortOption) {
        sortOption = option
    }

    /// 设置过滤选项
    /// - Parameters:
    ///   - option: 过滤选项
    ///   - folderId: 文件夹ID（当选择 .folder 时需要）
    func setFilterOption(_ option: FilterOption, folderId: String? = nil) {
        filterOption = option
        currentFolderId = folderId
    }

    // MARK: - Private Methods

    /// 过滤笔记
    /// - Parameter notes: 原始笔记列表
    /// - Returns: 过滤后的笔记列表
    private func filterNotes(_ notes: [Note]) -> [Note] {
        var filtered = notes

        // 根据过滤选项过滤
        switch filterOption {
        case .all:
            break
        case .starred:
            filtered = filtered.filter { $0.isStarred }
        case .folder:
            if let folderId = currentFolderId {
                filtered = filtered.filter { $0.folderId == folderId }
            }
        }

        // 根据搜索文本过滤
        if !searchText.isEmpty {
            let lowercasedQuery = searchText.lowercased()
            filtered = filtered.filter {
                $0.title.lowercased().contains(lowercasedQuery) ||
                $0.content.lowercased().contains(lowercasedQuery)
            }
        }

        return filtered
    }

    /// 排序笔记
    /// - Parameter notes: 原始笔记列表
    /// - Returns: 排序后的笔记列表
    private func sortNotes(_ notes: [Note]) -> [Note] {
        switch sortOption {
        case .editDate:
            return notes.sorted { $0.updatedAt > $1.updatedAt }
        case .createDate:
            return notes.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return notes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}
