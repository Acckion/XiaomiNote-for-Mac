//
//  NoteEditorViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  笔记编辑器 ViewModel - 负责笔记编辑功能
//

import Foundation
import Combine

/// 笔记编辑器 ViewModel
///
/// 负责管理笔记编辑相关的逻辑，包括：
/// - 笔记内容编辑
/// - 自动保存
/// - 标题提取
/// - 编辑状态管理
@MainActor
final class NoteEditorViewModel: LoadableViewModel {
    // MARK: - Dependencies

    private let noteStorage: NoteStorageProtocol
    private let noteService: NoteServiceProtocol

    // MARK: - Published Properties

    /// 当前编辑的笔记
    @Published var currentNote: Note?

    /// 笔记标题
    @Published var title: String = ""

    /// 笔记内容
    @Published var content: String = ""

    /// 是否有未保存的更改
    @Published var hasUnsavedChanges: Bool = false

    /// 是否正在保存
    @Published var isSaving: Bool = false

    /// 最后保存时间
    @Published var lastSavedTime: Date?

    // MARK: - Private Properties

    /// 自动保存定时器
    private var autoSaveTimer: Timer?

    /// 自动保存延迟（秒）
    private let autoSaveDelay: TimeInterval = 2.0

    // MARK: - Initialization

    init(
        noteStorage: NoteStorageProtocol,
        noteService: NoteServiceProtocol
    ) {
        self.noteStorage = noteStorage
        self.noteService = noteService
        super.init()
    }

    // deinit 会自动清理，Timer 会在对象销毁时失效

    // MARK: - Setup

    override func setupBindings() {
        // 监听标题和内容变化，标记为有未保存的更改
        Publishers.CombineLatest($title, $content)
            .dropFirst() // 跳过初始值
            .sink { [weak self] _, _ in
                self?.hasUnsavedChanges = true
                self?.scheduleAutoSave()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// 加载笔记
    /// - Parameter noteId: 笔记ID
    func loadNote(_ noteId: String) async {
        await withLoadingSafe {
            guard let note = try noteStorage.fetchNote(id: noteId) else {
                throw NSError(domain: "NoteEditor", code: 404, userInfo: [NSLocalizedDescriptionKey: "Note not found"])
            }

            self.currentNote = note
            self.title = note.title
            self.content = note.content
            self.hasUnsavedChanges = false
        }
    }

    /// 创建新笔记
    /// - Parameter folderId: 文件夹ID
    func createNewNote(in folderId: String) {
        let newNote = Note(
            id: UUID().uuidString,
            title: "Untitled",
            content: "",
            folderId: folderId,
            isStarred: false,
            createdAt: Date(),
            updatedAt: Date()
        )

        currentNote = newNote
        title = newNote.title
        content = newNote.content
        hasUnsavedChanges = true
    }

    /// 保存笔记
    func saveNote() async {
        guard var note = currentNote else { return }
        guard hasUnsavedChanges else { return }

        isSaving = true
        defer { isSaving = false }

        // 更新笔记内容
        note.title = title.isEmpty ? "Untitled" : title
        note.content = content
        note.updatedAt = Date()

        await withLoadingSafe {
            // 保存到本地存储
            try noteStorage.saveNote(note)

            // 同步到服务器
            _ = try await noteService.updateNote(note)

            self.currentNote = note
            self.hasUnsavedChanges = false
            self.lastSavedTime = Date()
        }
    }

    /// 删除当前笔记
    func deleteCurrentNote() async {
        guard let note = currentNote else { return }

        await withLoadingSafe {
            try noteStorage.deleteNote(id: note.id)
            try await noteService.deleteNote(id: note.id)

            self.currentNote = nil
            self.title = ""
            self.content = ""
            self.hasUnsavedChanges = false
        }
    }

    /// 切换收藏状态
    func toggleStarred() async {
        guard var note = currentNote else { return }

        note.isStarred.toggle()

        await withLoadingSafe {
            try noteStorage.saveNote(note)
            self.currentNote = note
        }
    }

    /// 移动笔记到指定文件夹
    /// - Parameter folderId: 目标文件夹ID
    func moveToFolder(_ folderId: String) async {
        guard var note = currentNote else { return }

        note.folderId = folderId
        note.updatedAt = Date()

        await withLoadingSafe {
            try noteStorage.saveNote(note)
            self.currentNote = note
        }
    }

    /// 清除当前笔记
    func clearNote() {
        currentNote = nil
        title = ""
        content = ""
        hasUnsavedChanges = false
        autoSaveTimer?.invalidate()
    }

    // MARK: - Private Methods

    /// 安排自动保存
    private func scheduleAutoSave() {
        autoSaveTimer?.invalidate()

        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.saveNote()
            }
        }
    }
}
