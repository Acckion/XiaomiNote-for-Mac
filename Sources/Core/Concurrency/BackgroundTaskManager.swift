import Foundation

/// 后台任务管理器
actor BackgroundTaskManager {

    private init() {}

    /// 在后台执行任务
    func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        try await operation()
    }

    /// 在后台执行多个任务并等待全部完成
    func executeAll<T: Sendable>(_ operations: [@Sendable () async throws -> T]) async throws -> [T] {
        try await withThrowingTaskGroup(of: T.self) { group in
            for operation in operations {
                group.addTask {
                    try await operation()
                }
            }

            var results: [T] = []
            for try await result in group {
                results.append(result)
            }

            return results
        }
    }
}
