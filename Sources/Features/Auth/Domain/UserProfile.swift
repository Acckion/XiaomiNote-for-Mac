import Foundation

/// 用户信息数据模型
///
/// 表示当前登录用户的基本信息
public struct UserProfile: Codable, Identifiable, Sendable {
    /// 用户昵称
    public let nickname: String

    /// 用户头像URL
    public let icon: String

    /// 用户ID（使用昵称的哈希值作为ID）
    public var id: String {
        String(nickname.hash)
    }

    enum CodingKeys: String, CodingKey {
        case nickname
        case icon
    }

    public init(nickname: String, icon: String) {
        self.nickname = nickname
        self.icon = icon
    }

    /// 从API响应创建 UserProfile
    ///
    /// - Parameter data: API返回的用户信息字典
    /// - Returns: UserProfile对象，如果数据无效则返回nil
    static func fromAPIResponse(_ data: [String: Any]) -> UserProfile? {
        guard let nickname = data["nickname"] as? String,
              let icon = data["icon"] as? String
        else {
            return nil
        }

        return UserProfile(nickname: nickname, icon: icon)
    }
}
