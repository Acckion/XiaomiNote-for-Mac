import Foundation

/// 网络错误处理器
///
/// 统一处理网络请求错误，包括错误分类、重试策略和错误恢复
@MainActor
final class NetworkErrorHandler {
    @available(*, deprecated, message: "使用 NetworkModule 注入的实例")
    static let shared = NetworkErrorHandler()

    // MARK: - 配置

    /// 最大重试次数
    var maxRetryCount = 3

    /// 初始重试延迟（秒）
    var initialRetryDelay: TimeInterval = 1.0

    /// 最大重试延迟（秒）
    var maxRetryDelay: TimeInterval = 30.0

    /// 重试退避倍数
    var retryBackoffMultiplier = 2.0

    init() {}

    // MARK: - 错误分类

    /// 错误类型
    enum ErrorType {
        case networkError // 网络错误（可重试）
        case authenticationError // 认证错误（需要用户操作）
        case serverError // 服务器错误（根据状态码决定）
        case clientError // 客户端错误（不重试）
        case businessError // 业务错误（不重试）
    }

    /// 错误处理策略
    enum ErrorStrategy {
        case retry // 自动重试
        case retryWithDelay // 延迟后重试
        case requireUserAction // 需要用户操作
        case noRetry // 不重试
    }

    /// 错误处理结果
    struct ErrorHandlingResult {
        let strategy: ErrorStrategy
        let retryDelay: TimeInterval?
        let shouldRetry: Bool
        let userMessage: String?

        static func retry(delay: TimeInterval? = nil) -> ErrorHandlingResult {
            ErrorHandlingResult(
                strategy: delay != nil ? .retryWithDelay : .retry,
                retryDelay: delay,
                shouldRetry: true,
                userMessage: nil
            )
        }

        static func requireUserAction(message: String) -> ErrorHandlingResult {
            ErrorHandlingResult(
                strategy: .requireUserAction,
                retryDelay: nil,
                shouldRetry: false,
                userMessage: message
            )
        }

        static func noRetry(message: String? = nil) -> ErrorHandlingResult {
            ErrorHandlingResult(
                strategy: .noRetry,
                retryDelay: nil,
                shouldRetry: false,
                userMessage: message
            )
        }
    }

    // MARK: - 错误分类

    /// 分类错误类型
    func classifyError(_ error: Error) -> ErrorType {
        // MiNoteError 分类
        if let miNoteError = error as? MiNoteError {
            switch miNoteError {
            case .cookieExpired, .notAuthenticated:
                return .authenticationError
            case .networkError:
                return .networkError
            case .invalidResponse:
                return .serverError
            }
        }

        // URLError 分类
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost:
                return .networkError
            case .badURL, .unsupportedURL, .fileDoesNotExist:
                return .clientError
            default:
                return .networkError
            }
        }

        // NSError 分类
        if let nsError = error as NSError? {
            // HTTP 状态码分类
            if nsError.domain == NSURLErrorDomain {
                return .networkError
            }

            // 服务器错误（5xx）
            if nsError.code >= 500, nsError.code < 600 {
                return .serverError
            }

            // 客户端错误（4xx）
            if nsError.code >= 400, nsError.code < 500 {
                // 429 限流错误
                if nsError.code == 429 {
                    return .serverError
                }
                // 401/403 认证错误
                if nsError.code == 401 || nsError.code == 403 {
                    return .authenticationError
                }
                return .clientError
            }
        }

        // 默认：网络错误
        return .networkError
    }

    // MARK: - 错误处理策略

    /// 获取错误处理策略
    func handleError(_ error: Error, retryCount: Int, httpStatusCode: Int? = nil) -> ErrorHandlingResult {
        let errorType = classifyError(error)

        switch errorType {
        case .networkError:
            // 网络错误：自动重试（指数退避）
            if retryCount < maxRetryCount {
                let delay = calculateRetryDelay(retryCount: retryCount)
                return .retry(delay: delay)
            } else {
                return .noRetry(message: "网络连接失败，请检查网络设置")
            }

        case .authenticationError:
            // 认证错误：需要用户操作
            if let miNoteError = error as? MiNoteError {
                switch miNoteError {
                case .cookieExpired:
                    return .requireUserAction(message: "登录已过期，请重新登录")
                case .notAuthenticated:
                    return .requireUserAction(message: "未登录，请先登录")
                default:
                    return .requireUserAction(message: "认证失败，请重新登录")
                }
            }
            return .requireUserAction(message: "认证失败，请重新登录")

        case .serverError:
            // 服务器错误：根据状态码决定
            if let statusCode = httpStatusCode {
                // 429 限流：延迟后重试
                if statusCode == 429 {
                    if retryCount < maxRetryCount {
                        let delay = calculateRetryDelay(retryCount: retryCount)
                        return .retry(delay: delay)
                    } else {
                        return .noRetry(message: "请求过于频繁，请稍后再试")
                    }
                }
                // 5xx 错误：自动重试
                if statusCode >= 500, statusCode < 600 {
                    if retryCount < maxRetryCount {
                        let delay = calculateRetryDelay(retryCount: retryCount)
                        return .retry(delay: delay)
                    } else {
                        return .noRetry(message: "服务器错误，请稍后再试")
                    }
                }
            }
            // 默认：不重试
            return .noRetry(message: "服务器错误")

        case .clientError:
            // 客户端错误：不重试
            if let statusCode = httpStatusCode {
                if statusCode == 404 {
                    return .noRetry(message: "资源不存在")
                } else if statusCode == 400 {
                    return .noRetry(message: "请求参数错误")
                }
            }
            return .noRetry(message: "请求错误")

        case .businessError:
            // 业务错误：不重试
            return .noRetry(message: error.localizedDescription)
        }
    }

    // MARK: - 重试延迟计算

    /// 计算重试延迟（指数退避）
    func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        let delay = initialRetryDelay * pow(retryBackoffMultiplier, Double(retryCount))
        return min(delay, maxRetryDelay)
    }

    // MARK: - 错误恢复

    /// 判断错误是否可重试
    func isRetryable(_ error: Error, retryCount: Int) -> Bool {
        let result = handleError(error, retryCount: retryCount)
        return result.shouldRetry && retryCount < maxRetryCount
    }

    /// 判断错误是否需要用户操作
    func requiresUserAction(_ error: Error) -> Bool {
        let errorType = classifyError(error)
        return errorType == .authenticationError
    }
}
