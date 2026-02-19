//
//  SearchViewModel.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  搜索视图模型 - 管理笔记搜索功能
//

import Combine
import Foundation

/// 搜索视图模型
///
/// 负责管理笔记搜索功能，包括：
/// - 搜索笔记
/// - 搜索历史管理
/// - 搜索过滤
/// - 搜索防抖
@MainActor
public final class SearchViewModel: ObservableObject {
    // MARK: - Published Properties

    /// 搜索文本
    @Published public var searchText = ""

    /// 搜索结果
    @Published public var searchResults: [Note] = []

    /// 是否正在搜索
    @Published public var isSearching = false

    /// 搜索历史
    @Published public var searchHistory: [String] = []

    /// 错误消息
    @Published public var errorMessage: String?

    // MARK: - Search Filters

    /// 过滤：包含标签
    @Published public var filterHasTags = false

    /// 过滤：包含清单
    @Published public var filterHasChecklist = false

    /// 过滤：包含图片
    @Published public var filterHasImages = false

    /// 过滤：包含音频
    @Published public var filterHasAudio = false

    /// 过滤：私密笔记
    @Published public var filterIsPrivate = false

    // MARK: - Dependencies

    private let noteStorage: NoteStorageProtocol
    private let noteService: NoteServiceProtocol

    // MARK: - Private Properties

    /// 搜索任务
    private var searchTask: Task<Void, Never>?

    /// 搜索防抖延迟 (300ms)
    private let searchDebounceDelay: TimeInterval = 0.3

    /// 最大搜索历史数量
    private let maxHistoryCount = 10

    /// Cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// 初始化搜索视图模型
    /// - Parameters:
    ///   - noteStorage: 笔记存储服务
    ///   - noteService: 笔记服务
    public init(
        noteStorage: NoteStorageProtocol,
        noteService: NoteServiceProtocol
    ) {
        self.noteStorage = noteStorage
        self.noteService = noteService

        // 加载搜索历史
        loadSearchHistory()

        // 监听搜索文本变化
        setupSearchTextObserver()
    }

    // MARK: - Public Methods

    /// 搜索笔记
    /// - Parameter keyword: 搜索关键词
    public func search(keyword: String) {
        // 取消之前的搜索任务
        searchTask?.cancel()

        // 如果关键词为空，清除搜索结果
        guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        // 创建新的搜索任务
        searchTask = Task {
            // 防抖延迟
            try? await Task.sleep(nanoseconds: UInt64(searchDebounceDelay * 1_000_000_000))

            // 检查任务是否被取消
            guard !Task.isCancelled else { return }

            // 执行搜索
            await performSearch(keyword)
        }
    }

    /// 清除搜索
    public func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        searchResults = []
        isSearching = false
        errorMessage = nil
    }

    /// 添加到搜索历史
    /// - Parameter keyword: 搜索关键词
    public func addToHistory(_ keyword: String) {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果关键词为空，不添加
        guard !trimmedKeyword.isEmpty else { return }

        // 如果已存在，先移除
        searchHistory.removeAll { $0 == trimmedKeyword }

        // 添加到开头
        searchHistory.insert(trimmedKeyword, at: 0)

        // 限制历史数量
        if searchHistory.count > maxHistoryCount {
            searchHistory = Array(searchHistory.prefix(maxHistoryCount))
        }

        // 保存搜索历史
        saveSearchHistory()
    }

    /// 清除搜索历史
    public func clearHistory() {
        searchHistory = []
        saveSearchHistory()
    }

    /// 应用搜索过滤器
    public func applyFilters() {
        // 如果没有搜索结果，不应用过滤器
        guard !searchResults.isEmpty else { return }

        // 重新执行搜索以应用过滤器
        if !searchText.isEmpty {
            Task {
                await performSearch(searchText)
            }
        }
    }

    // MARK: - Private Methods

    /// 执行搜索
    /// - Parameter keyword: 搜索关键词
    private func performSearch(_ keyword: String) async {
        isSearching = true
        errorMessage = nil

        do {
            // 从本地存储搜索
            var results = try noteStorage.searchNotes(query: keyword)

            // 应用过滤器
            results = applyFiltersToResults(results)

            // 更新搜索结果
            searchResults = results

            // 添加到搜索历史
            addToHistory(keyword)
        } catch {
            errorMessage = "搜索失败: \(error.localizedDescription)"
            LogService.shared.error(.viewmodel, "搜索失败: \(error)")
        }

        isSearching = false
    }

    /// 应用过滤器到搜索结果
    /// - Parameter results: 原始搜索结果
    /// - Returns: 过滤后的搜索结果
    private func applyFiltersToResults(_ results: [Note]) -> [Note] {
        var filteredResults = results

        // 过滤：包含标签
        if filterHasTags {
            filteredResults = filteredResults.filter { note in
                // 检查笔记是否包含标签
                // 注意：这里假设 Note 模型有 tags 属性
                // 如果没有，需要从 content 中解析
                !note.content.isEmpty // 简化实现
            }
        }

        // 过滤：包含清单
        if filterHasChecklist {
            filteredResults = filteredResults.filter { note in
                // 检查笔记是否包含清单
                note.content.contains("☐") || note.content.contains("☑")
            }
        }

        // 过滤：包含图片
        if filterHasImages {
            filteredResults = filteredResults.filter { note in
                // 检查笔记是否包含图片
                note.content.contains("<img") || note.content.contains("![")
            }
        }

        // 过滤：包含音频
        if filterHasAudio {
            filteredResults = filteredResults.filter { note in
                // 检查笔记是否包含音频
                note.content.contains("<audio") || note.content.contains("🎵")
            }
        }

        // 过滤：私密笔记
        // 注意: Note 模型目前没有 isPrivate 属性
        // TODO: 如果需要支持私密笔记过滤，需要在 Note 模型中添加 isPrivate 属性
        // if filterIsPrivate {
        //     filteredResults = filteredResults.filter { $0.isPrivate }
        // }

        return filteredResults
    }

    /// 设置搜索文本观察者
    private func setupSearchTextObserver() {
        $searchText
            .sink { [weak self] text in
                self?.search(keyword: text)
            }
            .store(in: &cancellables)
    }

    /// 加载搜索历史
    private func loadSearchHistory() {
        if let history = UserDefaults.standard.array(forKey: "searchHistory") as? [String] {
            searchHistory = history
        }
    }

    /// 保存搜索历史
    private func saveSearchHistory() {
        UserDefaults.standard.set(searchHistory, forKey: "searchHistory")
    }
}
