import Foundation

/// 同步 API
///
/// 负责网页版增量同步 API 调用
public struct SyncAPI: Sendable {
    public static let shared = SyncAPI()

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    // MARK: - 增量同步

    /// 执行增量同步（网页版API）
    ///
    /// 使用网页版的 `/note/sync/full/` API 进行增量同步
    ///
    /// - Parameters:
    ///   - syncTag: 同步标签，用于增量同步。空字符串表示获取第一页
    ///   - inactiveTime: 用户不活跃时间（秒），用于优化同步频率
    /// - Returns: 包含笔记和文件夹列表的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func syncFull(syncTag: String = "", inactiveTime: Int = 10) async throws -> [String: Any] {
        var dataDict: [String: Any] = ["note_view": [:]]
        if !syncTag.isEmpty {
            dataDict["note_view"] = ["syncTag": syncTag]
        }

        guard let dataJson = try? JSONSerialization.data(withJSONObject: dataDict, options: []),
              let dataString = String(data: dataJson, encoding: .utf8)
        else {
            throw URLError(.cannotParseResponse)
        }

        let dataEncoded = client.encodeURIComponent(dataString)
        let ts = Int(Date().timeIntervalSince1970 * 1000)

        let urlString = "\(client.baseURL)/note/sync/full/?ts=\(ts)&data=\(dataEncoded)&inactiveTime=\(inactiveTime)"

        return try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )
    }
}
