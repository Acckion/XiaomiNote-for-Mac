import Foundation

/// 认证事件
enum AuthEvent: AppEvent {
    case loggedIn(UserProfile)
    case loggedOut
    case cookieExpired
    case cookieRefreshed
    case tokenRefreshFailed(errorMessage: String)

    // MARK: - AppEvent

    var id: UUID {
        UUID()
    }

    var timestamp: Date {
        Date()
    }

    var source: EventSource {
        .system
    }
}
