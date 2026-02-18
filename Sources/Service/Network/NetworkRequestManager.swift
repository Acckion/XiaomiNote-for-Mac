import Combine
import Foundation

/// 网络请求优先级
enum RequestPriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3

    static func < (lhs: RequestPriority, rhs: RequestPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 网络请求
struct NetworkRequest: Identifiable, Hashable {
    let id: String
    let url: String
    let method: String
    let headers: [String: String]?
    let body: Data?
    let priority: RequestPriority
    let cachePolicy: CachePolicy
    let retryOnFailure: Bool

    enum CachePolicy {
        case noCache
        case cache(ttl: TimeInterval) // 缓存时间（秒）
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(method)
        if let body {
            hasher.combine(body)
        }
    }

    static func == (lhs: NetworkRequest, rhs: NetworkRequest) -> Bool {
        lhs.url == rhs.url &&
            lhs.method == rhs.method &&
            lhs.body == rhs.body
    }
}

/// 网络请求结果
struct NetworkResponse {
    let data: Data
    let response: HTTPURLResponse
    let request: NetworkRequest
}

/// 网络请求管理器
///
/// 统一管理所有网络请求，包括：
/// - 请求队列和优先级控制
/// - 请求去重和缓存
/// - 统一的重试机制和错误处理
/// - 请求拦截器
@MainActor
final class NetworkRequestManager: ObservableObject {
    static let shared = NetworkRequestManager()

    // MARK: - 配置

    /// 最大并发请求数
    var maxConcurrentRequests = 5

    /// 请求去重时间窗口（秒）
    var deduplicationWindow: TimeInterval = 0.5

    /// 请求超时时间（秒）
    var requestTimeout: TimeInterval = 30.0

    // MARK: - 依赖服务

    private let errorHandler = NetworkErrorHandler.shared
    private let onlineStateManager = OnlineStateManager.shared

    // MARK: - 请求队列

    /// 待处理请求队列（按优先级排序）
    private var pendingRequests: [NetworkRequest] = []

    /// 正在处理的请求
    private var activeRequests: Set<String> = []

    /// 请求去重字典（key: 请求hash, value: 时间戳）
    private var deduplicationMap: [Int: Date] = [:]

    /// 请求缓存（key: 请求hash, value: (数据, 过期时间)）
    private var cache: [Int: (data: Data, expiresAt: Date)] = [:]

    /// 重试队列（key: 请求ID, value: (请求, 重试次数, 下次重试时间)）
    private var retryQueue: [String: (request: NetworkRequest, retryCount: Int, nextRetryTime: Date)] = [:]

    // MARK: - 状态

    @Published private(set) var activeRequestCount = 0
    @Published private(set) var pendingRequestCount = 0

    // MARK: - 队列和锁

    private let queue = DispatchQueue(label: "NetworkRequestManager", attributes: .concurrent)
    private let processingQueue = DispatchQueue(label: "NetworkRequestManager.processing", qos: .userInitiated)

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupOnlineStateMonitoring()
        startProcessingLoop()
    }

    // MARK: - 初始化设置

    /// 设置在线状态监控
    private func setupOnlineStateMonitoring() {
        onlineStateManager.$isOnline
            .sink { [weak self] isOnline in
                Task { @MainActor in
                    if isOnline {
                        self?.processRetryQueue()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 公共方法

    /// 执行网络请求
    ///
    /// - Parameters:
    ///   - url: 请求URL
    ///   - method: HTTP方法
    ///   - headers: 请求头
    ///   - body: 请求体
    ///   - priority: 请求优先级
    ///   - cachePolicy: 缓存策略
    ///   - retryOnFailure: 是否在失败时重试
    /// - Returns: 网络响应
    /// - Throws: 网络错误
    func request(
        url: String,
        method: String = "GET",
        headers: [String: String]? = nil,
        body: Data? = nil,
        priority: RequestPriority = .normal,
        cachePolicy: NetworkRequest.CachePolicy = .noCache,
        retryOnFailure: Bool = true
    ) async throws -> NetworkResponse {
        let request = NetworkRequest(
            id: UUID().uuidString,
            url: url,
            method: method,
            headers: headers,
            body: body,
            priority: priority,
            cachePolicy: cachePolicy,
            retryOnFailure: retryOnFailure
        )

        return try await executeRequest(request)
    }

    /// 执行请求（内部方法）
    private func executeRequest(_ request: NetworkRequest) async throws -> NetworkResponse {
        // 检查缓存
        if case .cache = request.cachePolicy {
            if let cached = getCachedResponse(for: request) {
                print("[NetworkRequestManager] 使用缓存响应: \(request.url)")
                return cached
            }
        }

        // 检查去重
        if shouldDeduplicate(request) {
            // 等待相同请求完成
            return try await waitForDuplicateRequest(request)
        }

        // 检查在线状态
        guard onlineStateManager.isOnline else {
            // 如果允许重试，加入重试队列
            if request.retryOnFailure {
                addToRetryQueue(request, retryCount: 0)
            }
            throw MiNoteError.networkError(URLError(.notConnectedToInternet))
        }

        // 添加到处理队列
        addToQueue(request)

        // 等待处理
        return try await processRequest(request)
    }

    // MARK: - 请求处理

    /// 处理请求
    private func processRequest(_ request: NetworkRequest) async throws -> NetworkResponse {
        try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: MiNoteError.networkError(URLError(.unknown)))
                    return
                }

                // 标记为正在处理
                Task { @MainActor in
                    self.activeRequests.insert(request.id)
                    self.activeRequestCount = self.activeRequests.count
                }

                // 创建 URLRequest
                guard let url = URL(string: request.url) else {
                    Task { @MainActor in
                        self.activeRequests.remove(request.id)
                        self.activeRequestCount = self.activeRequests.count
                    }
                    continuation.resume(throwing: URLError(.badURL))
                    return
                }

                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = request.method
                urlRequest.allHTTPHeaderFields = request.headers
                urlRequest.httpBody = request.body
                urlRequest.timeoutInterval = requestTimeout

                // 执行请求
                Task {
                    do {
                        let (data, response) = try await URLSession.shared.data(for: urlRequest)

                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw MiNoteError.invalidResponse
                        }

                        // 处理错误响应
                        if httpResponse.statusCode >= 400 {
                            let error = self.handleHTTPError(statusCode: httpResponse.statusCode, request: request)

                            // 检查是否需要重试
                            let shouldRetry = await MainActor.run { self.errorHandler.isRetryable(error, retryCount: 0) }
                            if request.retryOnFailure, shouldRetry {
                                Task { @MainActor in
                                    self.addToRetryQueue(request, retryCount: 0)
                                }
                                continuation.resume(throwing: error)
                                return
                            }

                            continuation.resume(throwing: error)
                            return
                        }

                        // 成功响应
                        let networkResponse = NetworkResponse(
                            data: data,
                            response: httpResponse,
                            request: request
                        )

                        // 缓存响应
                        if case let .cache(ttl) = request.cachePolicy {
                            Task { @MainActor in
                                self.cacheResponse(networkResponse, ttl: ttl)
                            }
                        }

                        // 记录去重
                        Task { @MainActor in
                            self.recordDeduplication(request)
                        }

                        Task { @MainActor in
                            self.activeRequests.remove(request.id)
                            self.activeRequestCount = self.activeRequests.count
                        }

                        continuation.resume(returning: networkResponse)
                    } catch {
                        // 处理错误
                        let handlingResult = await MainActor.run { self.errorHandler.handleError(error, retryCount: 0) }

                        if request.retryOnFailure, handlingResult.shouldRetry {
                            Task { @MainActor in
                                self.addToRetryQueue(request, retryCount: 0)
                            }
                        }

                        Task { @MainActor in
                            self.activeRequests.remove(request.id)
                            self.activeRequestCount = self.activeRequests.count
                        }

                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// 添加到队列
    private func addToQueue(_ request: NetworkRequest) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }

            // 按优先级插入
            var inserted = false
            for (index, existingRequest) in pendingRequests.enumerated() {
                if request.priority > existingRequest.priority {
                    pendingRequests.insert(request, at: index)
                    inserted = true
                    break
                }
            }

            if !inserted {
                pendingRequests.append(request)
            }

            Task { @MainActor in
                self.pendingRequestCount = self.pendingRequests.count
            }
        }
    }

    /// 处理循环
    private func startProcessingLoop() {
        Task {
            while true {
                await processNextRequest()
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            }
        }
    }

    /// 处理下一个请求
    private func processNextRequest() async {
        // 检查并发限制
        guard activeRequestCount < maxConcurrentRequests else {
            return
        }

        // 检查在线状态
        guard onlineStateManager.isOnline else {
            return
        }

        // 获取下一个请求
        let nextRequest = queue.sync {
            pendingRequests.isEmpty ? nil : pendingRequests.removeFirst()
        }

        guard let request = nextRequest else {
            return
        }

        Task { @MainActor in
            self.pendingRequestCount = self.pendingRequests.count
        }

        // 处理请求（不等待完成，继续处理下一个）
        Task {
            _ = try? await processRequest(request)
        }
    }

    // MARK: - 缓存管理

    /// 获取缓存响应
    private func getCachedResponse(for request: NetworkRequest) -> NetworkResponse? {
        let hash = request.hashValue
        guard let cached = cache[hash] else {
            return nil
        }

        // 检查是否过期
        if cached.expiresAt < Date() {
            cache.removeValue(forKey: hash)
            return nil
        }

        // 创建响应（需要从缓存数据重建）
        // 注意：这里简化处理，实际应该保存完整的响应信息
        return nil // 暂时返回nil，需要改进
    }

    /// 缓存响应
    private func cacheResponse(_ response: NetworkResponse, ttl: TimeInterval) {
        let hash = response.request.hashValue
        let expiresAt = Date().addingTimeInterval(ttl)
        cache[hash] = (data: response.data, expiresAt: expiresAt)

        // 清理过期缓存
        cleanupExpiredCache()
    }

    /// 清理过期缓存
    private func cleanupExpiredCache() {
        let now = Date()
        cache = cache.filter { $0.value.expiresAt >= now }
    }

    // MARK: - 去重管理

    /// 检查是否应该去重
    private func shouldDeduplicate(_ request: NetworkRequest) -> Bool {
        let hash = request.hashValue
        guard let lastTime = deduplicationMap[hash] else {
            return false
        }

        let elapsed = Date().timeIntervalSince(lastTime)
        return elapsed < deduplicationWindow
    }

    /// 等待重复请求完成
    private func waitForDuplicateRequest(_ request: NetworkRequest) async throws -> NetworkResponse {
        // 简化实现：直接执行请求（实际应该等待相同请求完成）
        try await executeRequest(request)
    }

    /// 记录去重
    private func recordDeduplication(_ request: NetworkRequest) {
        let hash = request.hashValue
        deduplicationMap[hash] = Date()

        // 清理旧的去重记录
        cleanupDeduplicationMap()
    }

    /// 清理去重映射
    private func cleanupDeduplicationMap() {
        let now = Date()
        deduplicationMap = deduplicationMap.filter { now.timeIntervalSince($0.value) < deduplicationWindow * 10 }
    }

    // MARK: - 重试队列

    /// 添加到重试队列
    private func addToRetryQueue(_ request: NetworkRequest, retryCount: Int) {
        let delay = errorHandler.calculateRetryDelay(retryCount: retryCount)
        let nextRetryTime = Date().addingTimeInterval(delay)

        retryQueue[request.id] = (request: request, retryCount: retryCount, nextRetryTime: nextRetryTime)

        print("[NetworkRequestManager] 添加到重试队列: \(request.url), 重试次数: \(retryCount), 下次重试时间: \(nextRetryTime)")
    }

    /// 处理重试队列
    private func processRetryQueue() {
        let now = Date()
        let readyToRetry = retryQueue.filter { $0.value.nextRetryTime <= now }

        for (id, item) in readyToRetry {
            retryQueue.removeValue(forKey: id)

            let newRetryCount = item.retryCount + 1
            if newRetryCount <= errorHandler.maxRetryCount {
                // 重新添加到队列
                addToQueue(item.request)
            } else {
                print("[NetworkRequestManager] 达到最大重试次数，放弃请求: \(item.request.url)")
            }
        }
    }

    // MARK: - 错误处理

    /// 处理HTTP错误
    private nonisolated func handleHTTPError(statusCode: Int, request _: NetworkRequest) -> Error {
        switch statusCode {
        case 401:
            MiNoteError.cookieExpired
        case 403:
            MiNoteError.notAuthenticated
        case 404:
            NSError(domain: "NetworkRequestManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "资源不存在"])
        case 429:
            NSError(domain: "NetworkRequestManager", code: 429, userInfo: [NSLocalizedDescriptionKey: "请求过于频繁"])
        case 500 ... 599:
            MiNoteError.networkError(NSError(domain: "NetworkRequestManager", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "服务器错误"]))
        default:
            MiNoteError.networkError(NSError(
                domain: "NetworkRequestManager",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP错误: \(statusCode)"]
            ))
        }
    }
}
