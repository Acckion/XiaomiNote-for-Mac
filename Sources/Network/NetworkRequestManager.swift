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
        case cache(ttl: TimeInterval)
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
/// 所有网络请求统一通过队列调度执行，保证：
/// - 单一执行路径：入队 → 后台循环取出 → 执行 → 通知调用者
/// - 请求优先级排序和并发数控制
/// - 请求去重和缓存
/// - 统一的重试机制和错误处理
/// - 401 自动刷新 Cookie 并重试
@MainActor
public final class NetworkRequestManager: ObservableObject {

    // MARK: - 配置

    var maxConcurrentRequests = 5
    var deduplicationWindow: TimeInterval = 0.5
    var requestTimeout: TimeInterval = 30.0

    // MARK: - 依赖

    private let errorHandler = NetworkErrorHandler.shared
    private var onlineStateManager: OnlineStateManager?

    /// 注入的 APIClient（NetworkModule 创建时传入，用于 401 刷新后获取新 headers）
    private var apiClient: APIClient?

    // MARK: - 队列状态

    private var pendingRequests: [NetworkRequest] = []
    private var activeRequests: Set<String> = []

    /// 调用者等待字典：request() 入队后通过 continuation 等待队列执行结果
    /// 重试队列的请求没有 continuation（fire-and-forget）
    private var continuations: [String: CheckedContinuation<NetworkResponse, Error>] = [:]

    private var deduplicationMap: [Int: Date] = [:]
    private var cache: [Int: (data: Data, expiresAt: Date)] = [:]
    private var retryQueue: [String: (request: NetworkRequest, retryCount: Int, nextRetryTime: Date)] = [:]

    // MARK: - 状态

    @Published private(set) var activeRequestCount = 0
    @Published private(set) var pendingRequestCount = 0

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    init() {
        startProcessingLoop()
    }

    /// 设置 APIClient 引用（NetworkModule 创建后回调设置，解决循环依赖）
    func setAPIClient(_ client: APIClient) {
        apiClient = client
    }

    /// 设置 OnlineStateManager 引用（SyncModule 创建后回调设置，解决跨模块依赖）
    public func setOnlineStateManager(_ manager: OnlineStateManager) {
        onlineStateManager = manager
        setupOnlineStateMonitoring()
    }

    private func setupOnlineStateMonitoring() {
        guard let onlineStateManager else { return }
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

    /// 执行网络请求（唯一公共入口）
    ///
    /// 请求入队后由后台循环统一调度执行，调用者通过 continuation 等待结果。
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

        // 检查缓存
        if case .cache = request.cachePolicy,
           let cached = getCachedResponse(for: request)
        {
            return cached
        }

        // 检查去重
        if shouldDeduplicate(request) {
            LogService.shared.debug(.network, "请求去重，跳过: \(request.method) \(request.url)")
            throw MiNoteError.networkError(URLError(.cancelled))
        }

        // 离线时直接加入重试队列
        guard onlineStateManager?.isOnline != false else {
            if request.retryOnFailure {
                addToRetryQueue(request, retryCount: 0)
            }
            throw MiNoteError.networkError(URLError(.notConnectedToInternet))
        }

        // 入队并等待执行结果
        return try await withCheckedThrowingContinuation { continuation in
            self.continuations[request.id] = continuation
            self.enqueue(request)
        }
    }

    // MARK: - 队列管理

    /// 按优先级入队
    private func enqueue(_ request: NetworkRequest) {
        var inserted = false
        for (index, existing) in pendingRequests.enumerated() {
            if request.priority > existing.priority {
                pendingRequests.insert(request, at: index)
                inserted = true
                break
            }
        }
        if !inserted {
            pendingRequests.append(request)
        }
        pendingRequestCount = pendingRequests.count
    }

    /// 后台处理循环：统一从队列取出请求并执行
    private func startProcessingLoop() {
        Task {
            while true {
                processNextBatch()
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }

    /// 从队列取出请求并发起执行（不阻塞循环）
    private func processNextBatch() {
        guard onlineStateManager?.isOnline != false else { return }

        while activeRequestCount < maxConcurrentRequests, !pendingRequests.isEmpty {
            let request = pendingRequests.removeFirst()
            pendingRequestCount = pendingRequests.count

            activeRequests.insert(request.id)
            activeRequestCount = activeRequests.count

            Task {
                await self.executeAndComplete(request)
            }
        }
    }

    // MARK: - 请求执行

    /// 执行请求并通过 continuation 通知调用者
    private func executeAndComplete(_ request: NetworkRequest) async {
        do {
            let response = try await performHTTPRequest(request)

            // 缓存响应
            if case let .cache(ttl) = request.cachePolicy {
                cacheResponse(response, ttl: ttl)
            }
            recordDeduplication(request)

            // 通知调用者（如果有）
            if let continuation = continuations.removeValue(forKey: request.id) {
                continuation.resume(returning: response)
            }
        } catch {
            // 可重试错误加入重试队列
            if request.retryOnFailure, errorHandler.isRetryable(error, retryCount: 0) {
                addToRetryQueue(request, retryCount: 0)
            }

            // 通知调用者（如果有）
            if let continuation = continuations.removeValue(forKey: request.id) {
                continuation.resume(throwing: error)
            }
        }

        activeRequests.remove(request.id)
        activeRequestCount = activeRequests.count
    }

    /// 执行 HTTP 请求（纯网络操作）
    private func performHTTPRequest(_ request: NetworkRequest) async throws -> NetworkResponse {
        guard let url = URL(string: request.url) else {
            throw URLError(.badURL)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.allHTTPHeaderFields = request.headers
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = requestTimeout

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MiNoteError.invalidResponse
        }

        // 401：自动刷新 Cookie 并重试
        if httpResponse.statusCode == 401 {
            return try await handle401WithRefresh(urlRequest: urlRequest, request: request)
        }

        // 其他 HTTP 错误
        if httpResponse.statusCode >= 400 {
            throw handleHTTPError(statusCode: httpResponse.statusCode)
        }

        return NetworkResponse(data: data, response: httpResponse, request: request)
    }

    // MARK: - 401 处理

    private func handle401WithRefresh(
        urlRequest: URLRequest,
        request: NetworkRequest
    ) async throws -> NetworkResponse {
        let hasPassToken = await PassTokenManager.shared.hasStoredPassToken()
        guard hasPassToken else {
            await EventBus.shared.publish(AuthEvent.tokenRefreshFailed(errorMessage: "未存储 PassToken"))
            throw MiNoteError.notAuthenticated
        }

        do {
            _ = try await PassTokenManager.shared.refreshServiceToken()
        } catch {
            await EventBus.shared.publish(
                AuthEvent.tokenRefreshFailed(errorMessage: error.localizedDescription)
            )
            throw MiNoteError.cookieExpired
        }

        await EventBus.shared.publish(AuthEvent.cookieRefreshed)

        // 使用新 Cookie 重建请求并重试
        var retryRequest = urlRequest
        if let client = apiClient {
            let newHeaders = await client.getHeaders()
            retryRequest.allHTTPHeaderFields = newHeaders
        }
        if let originalHeaders = urlRequest.allHTTPHeaderFields {
            for (key, value) in originalHeaders where key != "Cookie" {
                retryRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        let (data, response) = try await URLSession.shared.data(for: retryRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MiNoteError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw MiNoteError.cookieExpired
        }

        return NetworkResponse(data: data, response: httpResponse, request: request)
    }

    // MARK: - 错误处理

    private nonisolated func handleHTTPError(statusCode: Int) -> Error {
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

    // MARK: - 缓存管理

    private func getCachedResponse(for request: NetworkRequest) -> NetworkResponse? {
        let hash = request.hashValue
        guard let cached = cache[hash] else { return nil }

        if cached.expiresAt < Date() {
            cache.removeValue(forKey: hash)
            return nil
        }

        return nil
    }

    private func cacheResponse(_ response: NetworkResponse, ttl: TimeInterval) {
        let hash = response.request.hashValue
        cache[hash] = (data: response.data, expiresAt: Date().addingTimeInterval(ttl))
        cleanupExpiredCache()
    }

    private func cleanupExpiredCache() {
        let now = Date()
        cache = cache.filter { $0.value.expiresAt >= now }
    }

    // MARK: - 去重管理

    private func shouldDeduplicate(_ request: NetworkRequest) -> Bool {
        let hash = request.hashValue
        guard let lastTime = deduplicationMap[hash] else { return false }
        return Date().timeIntervalSince(lastTime) < deduplicationWindow
    }

    private func recordDeduplication(_ request: NetworkRequest) {
        deduplicationMap[request.hashValue] = Date()
        let now = Date()
        deduplicationMap = deduplicationMap.filter { now.timeIntervalSince($0.value) < deduplicationWindow * 10 }
    }

    // MARK: - 重试队列

    private func addToRetryQueue(_ request: NetworkRequest, retryCount: Int) {
        let delay = errorHandler.calculateRetryDelay(retryCount: retryCount)
        retryQueue[request.id] = (
            request: request,
            retryCount: retryCount,
            nextRetryTime: Date().addingTimeInterval(delay)
        )
    }

    /// 恢复在线后，将重试队列中到期的请求重新入队执行
    private func processRetryQueue() {
        let now = Date()
        let readyToRetry = retryQueue.filter { $0.value.nextRetryTime <= now }

        for (id, item) in readyToRetry {
            retryQueue.removeValue(forKey: id)

            let newRetryCount = item.retryCount + 1
            if newRetryCount <= errorHandler.maxRetryCount {
                // 重新入队，无 continuation（fire-and-forget）
                enqueue(item.request)
            }
        }
    }
}
