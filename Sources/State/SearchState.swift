import SwiftUI

/// 搜索状态管理
///
/// 替代 NotesViewModel 中的搜索功能，
/// 负责搜索文本、搜索结果和筛选选项的管理。
@MainActor
final class SearchState: ObservableObject {
    // MARK: - Published 属性

    @Published var searchText = ""
    @Published var searchResults: [Note] = []
    @Published var filterHasTags = false
    @Published var filterHasChecklist = false
    @Published var filterHasImages = false
    @Published var filterHasAudio = false
    @Published var filterIsPrivate = false

    // MARK: - 依赖

    private let noteStore: NoteStore

    // MARK: - 初始化

    init(noteStore: NoteStore = .shared) {
        self.noteStore = noteStore
    }

    // MARK: - 搜索

    /// 从 NoteStore 内存缓存中搜索笔记
    func search(keyword: String) async {
        searchText = keyword

        guard !keyword.isEmpty else {
            searchResults = []
            return
        }

        let allNotes = await noteStore.notes
        searchResults = allNotes.filter { note in
            note.title.localizedCaseInsensitiveContains(keyword) ||
                note.content.localizedCaseInsensitiveContains(keyword)
        }
    }

    /// 清除搜索
    func clearSearch() {
        searchText = ""
        searchResults = []
        filterHasTags = false
        filterHasChecklist = false
        filterHasImages = false
        filterHasAudio = false
        filterIsPrivate = false
    }

    // MARK: - 计算属性

    /// 是否有激活的搜索筛选选项
    var hasSearchFilters: Bool {
        filterHasTags || filterHasChecklist || filterHasImages || filterHasAudio || filterIsPrivate
    }

    /// 当前激活的筛选标签文本
    var filterTagsText: String {
        var tags: [String] = []
        if filterHasTags { tags.append("标签") }
        if filterHasChecklist { tags.append("清单") }
        if filterHasImages { tags.append("图片") }
        if filterHasAudio { tags.append("录音") }
        if filterIsPrivate { tags.append("私密") }
        return tags.joined(separator: "、")
    }
}
