import Foundation
import Combine

/// 支持分页的 ViewModel 基类
@MainActor
class PageableViewModel<Item>: LoadableViewModel, Pageable {
    // MARK: - Published Properties
    @Published var items: [Item] = []
    @Published var hasMore = true
    @Published var isLoadingMore = false

    // MARK: - Private Properties
    private var currentPage = 0
    private let pageSize = 50

    // MARK: - Pageable
    func loadMore() async throws {
        guard hasMore && !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        let newItems = try await fetchPage(page: currentPage + 1, pageSize: pageSize)

        if newItems.count < pageSize {
            hasMore = false
        }

        items.append(contentsOf: newItems)
        currentPage += 1
    }

    func refresh() async throws {
        currentPage = 0
        hasMore = true
        items = []

        try await loadMore()
    }

    // MARK: - Abstract Methods
    /// 子类实现此方法来获取分页数据
    func fetchPage(page: Int, pageSize: Int) async throws -> [Item] {
        fatalError("Subclass must implement fetchPage")
    }
}
