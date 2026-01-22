import Foundation

/// 分页协议
@MainActor
protocol Pageable {
    associatedtype Item

    var items: [Item] { get }
    var hasMore: Bool { get }
    var isLoading: Bool { get }

    func loadMore() async throws
    func refresh() async throws
}

/// 分页信息
struct PageInfo {
    let page: Int
    let pageSize: Int
    let totalCount: Int

    var hasMore: Bool {
        return page * pageSize < totalCount
    }
}
