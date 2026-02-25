import Foundation

/// 重试决策
public enum RetryDecision: Sendable {
    /// 延迟重试
    case retry(delay: TimeInterval)
    /// 放弃重试
    case abandon(reason: String)
}

/// 操作失败策略
///
/// 集中管理错误分类和重试决策逻辑，从 OperationProcessor 中提取。
/// 输入：错误 + 当前重试次数 + 配置
/// 输出：重试决策（延迟重试 / 放弃）
public struct OperationFailurePolicy: Sendable {

    private let config: OperationQueueConfig

    public init(config: OperationQueueConfig = .default) {
        self.config = config
    }

    // MARK: - 重试决策

    /// 根据错误和当前状态决定重试策略
    public func decide(error: Error, retryCount: Int) -> RetryDecision {
        let errorType = classifyError(error)

        guard errorType.isRetryable else {
            return .abandon(reason: "不可重试的错误类型: \(errorType.rawValue)")
        }

        guard retryCount < config.maxRetryCount else {
            return .abandon(reason: "超过最大重试次数 \(config.maxRetryCount)")
        }

        let delay = calculateRetryDelay(retryCount: retryCount)
        return .retry(delay: delay)
    }

    // MARK: - 错误分类

    public func classifyError(_ error: Error) -> OperationErrorType {
        if let miNoteError = error as? MiNoteError {
            switch miNoteError {
            case .cookieExpired, .notAuthenticated:
                return .authExpired
            case let .networkError(underlyingError):
                return classifyURLError(underlyingError)
            case .invalidResponse:
                return .serverError
            }
        }

        if let urlError = error as? URLError {
            return classifyURLError(urlError)
        }

        if let nsError = error as? NSError {
            let apiDomains: Set<String> = ["NoteAPI", "FolderAPI", "FileAPI", "UserAPI", "OperationProcessor"]
            if apiDomains.contains(nsError.domain) {
                switch nsError.code {
                case 401:
                    return .authExpired
                case 404:
                    return .notFound
                case 409:
                    return .conflict
                case 500 ... 599:
                    return .serverError
                default:
                    return .unknown
                }
            }

            if nsError.domain == NSURLErrorDomain {
                return classifyURLErrorCode(nsError.code)
            }
        }

        return .unknown
    }

    public func isRetryable(_ error: Error) -> Bool {
        classifyError(error).isRetryable
    }

    // MARK: - 重试延迟计算

    public func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        let baseDelay = config.baseRetryDelay * pow(2.0, Double(retryCount))
        let cappedDelay = min(baseDelay, config.maxRetryDelay)
        let jitter = cappedDelay * Double.random(in: 0 ... 0.25)
        return cappedDelay + jitter
    }

    // MARK: - 私有方法

    private func classifyURLError(_ error: Error) -> OperationErrorType {
        if let urlError = error as? URLError {
            return classifyURLErrorCode(urlError.code.rawValue)
        }
        return .network
    }

    private func classifyURLErrorCode(_ code: Int) -> OperationErrorType {
        switch code {
        case URLError.timedOut.rawValue:
            .timeout
        case URLError.notConnectedToInternet.rawValue,
             URLError.networkConnectionLost.rawValue,
             URLError.cannotFindHost.rawValue,
             URLError.cannotConnectToHost.rawValue,
             URLError.dnsLookupFailed.rawValue:
            .network
        case URLError.badServerResponse.rawValue,
             URLError.cannotParseResponse.rawValue:
            .serverError
        case URLError.userAuthenticationRequired.rawValue:
            .authExpired
        default:
            .network
        }
    }
}
