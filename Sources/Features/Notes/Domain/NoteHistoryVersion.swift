import Foundation

/// 笔记历史记录
struct NoteHistoryVersion: Identifiable, Codable, Hashable, Equatable {
    /// 版本号（时间戳）
    let version: Int64

    /// 更新时间（时间戳）
    let updateTime: Int64

    /// ID（用于 Identifiable 协议）
    var id: Int64 {
        version
    }

    /// 格式化后的更新时间
    var formattedUpdateTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(updateTime) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        return formatter.string(from: date)
    }

    /// Hashable 实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(version)
        hasher.combine(updateTime)
    }
}
