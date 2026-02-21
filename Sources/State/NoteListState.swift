import SwiftUI

/// 笔记列表状态管理
///
/// 替代 NotesViewModel 中的笔记列表管理功能，
/// 负责笔记的过滤、排序、选择和基本操作。
@MainActor
final class NoteListState: ObservableObject {
    // MARK: - Published 属性

    @Published var notes: [Note] = []
    @Published var selectedNote: Note?
    @Published var notesListSortField: NoteSortOrder = .editDate
    @Published var notesListSortDirection: SortDirection = .descending
    @Published var isLoading = false
    @Published var isGalleryExpanded = false

    /// 由外部设置的搜索和文件夹上下文
    @Published var searchText = ""
    @Published var selectedFolder: Folder?
    @Published var selectedFolderId: String?

    /// 搜索筛选属性
    @Published var filterHasTags = false
    @Published var filterHasChecklist = false
    @Published var filterHasImages = false
    @Published var filterHasAudio = false
    @Published var filterIsPrivate = false

    // MARK: - 依赖

    private let eventBus: EventBus
    private let noteStore: NoteStore

    // MARK: - 事件订阅任务

    private var listChangedTask: Task<Void, Never>?
    private var savedTask: Task<Void, Never>?

    // MARK: - 初始化

    init(eventBus: EventBus = .shared, noteStore: NoteStore) {
        self.eventBus = eventBus
        self.noteStore = noteStore
    }

    // MARK: - 生命周期

    func start() async {
        isLoading = true
        defer { isLoading = false }

        let storeNotes = await noteStore.notes
        notes = storeNotes

        listChangedTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: NoteEvent.self)
            for await event in stream {
                guard !Task.isCancelled else { break }
                switch event {
                case let .listChanged(updatedNotes):
                    notes = updatedNotes
                case let .saved(note):
                    updateNoteInList(note)
                default:
                    break
                }
            }
        }
    }

    func stop() {
        listChangedTask?.cancel()
        savedTask?.cancel()
        listChangedTask = nil
        savedTask = nil
    }

    // MARK: - 笔记选择

    func selectNote(_ note: Note) {
        selectedNote = note
    }

    // MARK: - 笔记操作

    func deleteNote(_ note: Note) async {
        await eventBus.publish(NoteEvent.deleted(noteId: note.id, tag: note.serverTag))
    }

    func toggleStar(_ note: Note) async {
        await eventBus.publish(NoteEvent.starred(noteId: note.id, isStarred: !note.isStarred))
    }

    func moveNote(_ note: Note, toFolder folderId: String) async {
        await eventBus.publish(NoteEvent.moved(noteId: note.id, fromFolder: note.folderId, toFolder: folderId))
    }

    func createNewNote(inFolder folderId: String) async {
        let now = Date()
        let note = Note(
            id: UUID().uuidString,
            title: "",
            content: "",
            folderId: folderId,
            createdAt: now,
            updatedAt: now
        )
        await eventBus.publish(NoteEvent.created(note))
    }

    // MARK: - 就地更新

    /// 更新列表中的单条笔记，返回是否成功
    @discardableResult
    func updateNoteInPlace(_ note: Note) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else {
            return false
        }
        notes[index] = note
        if selectedNote?.id == note.id {
            selectedNote = note
        }
        return true
    }

    /// 批量更新笔记
    func batchUpdateNotes(_ updates: [(noteId: String, update: (inout Note) -> Void)]) {
        for (noteId, update) in updates {
            guard let index = notes.firstIndex(where: { $0.id == noteId }) else { continue }
            update(&notes[index])
            if selectedNote?.id == noteId {
                selectedNote = notes[index]
            }
        }
    }

    /// 更新笔记时间戳，返回是否成功
    @discardableResult
    func updateNoteTimestamp(_ noteId: String, timestamp: Date) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else {
            return false
        }
        notes[index].updatedAt = timestamp
        if selectedNote?.id == noteId {
            selectedNote = notes[index]
        }
        return true
    }

    // MARK: - 过滤和排序

    /// 过滤后的笔记列表
    ///
    /// 根据搜索文本、选中的文件夹和筛选选项过滤笔记，并按排序设置排序
    var filteredNotes: [Note] {
        let filtered: [Note] = if searchText.isEmpty {
            if let folder = selectedFolder {
                if folder.id == "starred" {
                    notes.filter(\.isStarred)
                } else if folder.id == "0" {
                    notes
                } else if folder.id == "2" {
                    notes.filter { $0.folderId == "2" }
                } else if folder.id == "uncategorized" {
                    notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }
                } else {
                    notes.filter { $0.folderId == folder.id }
                }
            } else {
                notes
            }
        } else {
            notes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                    note.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        let filteredBySearchOptions = filtered.filter { note in
            if filterHasTags, note.tags.isEmpty { return false }
            if filterHasChecklist, !noteHasChecklist(note) { return false }
            if filterHasImages, !noteHasImages(note) { return false }
            if filterHasAudio, !noteHasAudio(note) { return false }
            if filterIsPrivate, note.folderId != "2" { return false }
            return true
        }

        return sortNotes(filteredBySearchOptions, by: notesListSortField, direction: notesListSortDirection)
    }

    // MARK: - 排序

    /// 稳定排序：主排序键相同时使用 id 作为次要排序键
    private func sortNotes(_ notes: [Note], by sortOrder: NoteSortOrder, direction: SortDirection) -> [Note] {
        let sorted: [Note] = switch sortOrder {
        case .editDate:
            notes.sorted {
                $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt < $1.updatedAt
            }
        case .createDate:
            notes.sorted {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
            }
        case .title:
            notes.sorted {
                let comparison = $0.title.localizedCompare($1.title)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
        }
        return direction == .descending ? sorted.reversed() : sorted
    }

    // MARK: - 内容检测辅助方法

    func noteHasChecklist(_ note: Note) -> Bool {
        let content = note.primaryXMLContent.lowercased()
        return content.contains("checkbox") ||
            content.contains("type=\"checkbox\"") ||
            (content.contains("<input") && content.contains("checkbox"))
    }

    func noteHasImages(_ note: Note) -> Bool {
        let content = note.primaryXMLContent.lowercased()
        if content.contains("<img") || content.contains("image") || content.contains("fileid") {
            return true
        }
        return note.hasImages
    }

    func noteHasAudio(_ note: Note) -> Bool {
        note.hasAudio
    }

    // MARK: - 计算属性

    /// 未分类文件夹（虚拟文件夹）
    var uncategorizedFolder: Folder {
        let count = notes.count(where: { $0.folderId == "0" || $0.folderId.isEmpty })
        return Folder(id: "uncategorized", name: "未分类", count: count, isSystem: false)
    }

    // MARK: - 内部方法

    /// 更新列表中的单条笔记（事件驱动）
    private func updateNoteInList(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            if selectedNote?.id == note.id {
                selectedNote = note
            }
        }
    }
}
