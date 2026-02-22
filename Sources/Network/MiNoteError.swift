import Foundation

/// 小米笔记 API 错误类型
enum MiNoteError: Error {
    case cookieExpired
    case notAuthenticated
    case networkError(Error)
    case invalidResponse
}

extension MiNoteError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cookieExpired:
            "Cookie已过期，请重新登录"
        case .notAuthenticated:
            "未登录，请先登录小米账号"
        case let .networkError(error):
            "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            "服务器返回无效响应"
        }
    }
}
