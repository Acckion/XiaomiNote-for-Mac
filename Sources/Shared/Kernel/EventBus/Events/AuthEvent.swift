import Foundation

/// 认证事件
public enum AuthEvent: AppEvent {
    case loggedIn(UserProfile)
    case loggedOut
    case cookieExpired
    case cookieRefreshed
    case tokenRefreshFailed(errorMessage: String)

    // MARK: - AppEvent

    public var id: UUID {
        UUID()
    }

    public var timestamp: Date {
        Date()
    }

    public var source: EventSource {
        .system
    }
}
