import Foundation

/// 笔记历史版本数据模型
/// 
/// 表示笔记的一个历史版本，包括版本号和更新时间
public struct NoteHistoryVersion: Identifiable, Codable, Hashable {
    /// 版本标识符（使用 version 或 updateTime 作为 id）
    public var id: String {
        return "\(version)"
    }
    
    /// 更新时间戳（毫秒）
    public let updateTime: Int64
    
    /// 版本号（毫秒时间戳格式）
    public let version: Int64
    
    /// 更新时间的 Date 对象
    public var updateDate: Date {
        return Date(timeIntervalSince1970: TimeInterval(updateTime) / 1000.0)
    }
    
    public init(updateTime: Int64, version: Int64) {
        self.updateTime = updateTime
        self.version = version
    }
    
    // Hashable 实现
    public func hash(into hasher: inout Hasher) {
        hasher.combine(version)
    }
    
    // Equatable 实现
    public static func == (lhs: NoteHistoryVersion, rhs: NoteHistoryVersion) -> Bool {
        return lhs.version == rhs.version
    }
    
    /// 从 API 响应数据创建 NoteHistoryVersion
    static func fromMinoteData(_ data: [String: Any]) -> NoteHistoryVersion? {
        // 处理 updateTime（可能是 Int 或 Int64）
        var updateTime: Int64?
        if let updateTimeInt64 = data["updateTime"] as? Int64 {
            updateTime = updateTimeInt64
        } else if let updateTimeInt = data["updateTime"] as? Int {
            updateTime = Int64(updateTimeInt)
        }
        
        // 处理 version（可能是 Int 或 Int64）
        var version: Int64?
        if let versionInt64 = data["version"] as? Int64 {
            version = versionInt64
        } else if let versionInt = data["version"] as? Int {
            version = Int64(versionInt)
        }
        
        guard let updateTimeValue = updateTime, let versionValue = version else {
            return nil
        }
        
        return NoteHistoryVersion(updateTime: updateTimeValue, version: versionValue)
    }
}

