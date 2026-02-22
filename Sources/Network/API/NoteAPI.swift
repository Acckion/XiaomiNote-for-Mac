import Foundation

/// 笔记 API
///
/// 负责所有笔记相关的网络请求，包括：
/// - 笔记 CRUD 操作（创建、更新、删除、恢复）
/// - 笔记列表获取（分页、私密、回收站）
/// - 笔记详情获取
/// - 笔记历史记录管理
public final class NoteAPI: @unchecked Sendable {
    public static let shared = NoteAPI()

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    // MARK: - 创建笔记

    /// 创建新笔记
    ///
    /// - Parameters:
    ///   - title: 笔记标题（存储在extraInfo中）
    ///   - content: 笔记内容（XML格式）
    ///   - folderId: 文件夹ID，默认为"0"（所有笔记）
    /// - Returns: 包含新创建笔记信息的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func createNote(title: String, content: String, folderId: String = "0") async throws -> [String: Any] {
        // 移除 content 中的 <new-format/> 前缀（上传时不需要）
        var cleanedContent = content
        if cleanedContent.hasPrefix("<new-format/>") {
            cleanedContent = String(cleanedContent.dropFirst("<new-format/>".count))
        }

        let extraInfoDict: [String: Any] = [
            "note_content_type": "common",
            "web_images": "",
            "mind_content_plain_text": "",
            "title": title,
            "mind_content": "",
        ]

        guard let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfoDict),
              let extraInfoString = String(data: extraInfoData, encoding: .utf8)
        else {
            throw URLError(.cannotParseResponse)
        }

        let entry: [String: Any] = [
            "content": cleanedContent,
            "colorId": 0,
            "folderId": folderId,
            "createDate": Int(Date().timeIntervalSince1970 * 1000),
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000),
            "extraInfo": extraInfoString,
        ]

        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8)
        else {
            throw URLError(.cannotParseResponse)
        }

        let entryEncoded = client.encodeURIComponent(entryJson)
        let serviceTokenEncoded = client.encodeURIComponent(client.serviceToken)
        let body = "entry=\(entryEncoded)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(client.baseURL)/note/note"

        var headers = client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        let json = try await client.performRequest(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8)
        )

        if let code = json["code"] as? Int, code != 0 {
            let message = json["description"] as? String ?? json["message"] as? String ?? "创建笔记失败"
            throw MiNoteError.networkError(NSError(domain: "NoteAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        return json
    }

    // MARK: - 更新笔记

    /// 更新笔记
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - title: 笔记标题
    ///   - content: 笔记内容（XML格式）
    ///   - folderId: 文件夹ID
    ///   - existingTag: 现有tag（版本标识），用于并发控制。如果为空，会从服务器获取最新tag
    ///   - originalCreateDate: 原始创建时间戳（毫秒），用于保持创建时间不变
    ///   - imageData: 图片数据数组（setting.data），用于保存笔记中的图片引用
    /// - Returns: 更新后的笔记信息
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func updateNote(
        noteId: String,
        title: String,
        content: String,
        folderId: String = "0",
        existingTag: String = "",
        originalCreateDate: Int? = nil,
        imageData: [[String: Any]]? = nil
    ) async throws -> [String: Any] {
        let createDate = originalCreateDate ?? Int(Date().timeIntervalSince1970 * 1000)

        let extraInfoDict: [String: Any] = [
            "note_content_type": "common",
            "web_images": "",
            "mind_content_plain_text": "",
            "title": title,
            "mind_content": "",
        ]

        guard let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfoDict),
              let extraInfoString = String(data: extraInfoData, encoding: .utf8)
        else {
            throw URLError(.cannotParseResponse)
        }

        // 移除 content 中的 <new-format/> 前缀（上传时不需要）
        var cleanedContent = content
        if cleanedContent.hasPrefix("<new-format/>") {
            cleanedContent = String(cleanedContent.dropFirst("<new-format/>".count))
        }

        var setting: [String: Any] = [
            "themeId": 0,
            "stickyTime": 0,
            "version": 0,
        ]
        if let imageData, !imageData.isEmpty {
            setting["data"] = imageData
        }

        let entry: [String: Any] = [
            "id": noteId,
            "tag": existingTag,
            "status": "normal",
            "createDate": createDate,
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000),
            "colorId": 0,
            "content": cleanedContent,
            "setting": setting,
            "folderId": folderId,
            "alertDate": 0,
            "extraInfo": extraInfoString,
        ]

        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8)
        else {
            throw URLError(.cannotParseResponse)
        }

        let entryEncoded = client.encodeURIComponent(entryJson)
        let serviceTokenEncoded = client.encodeURIComponent(client.serviceToken)
        let body = "entry=\(entryEncoded)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(client.baseURL)/note/note/\(noteId)"

        var headers = client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        return try await client.performRequest(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8)
        )
    }

    // MARK: - 删除笔记

    /// 删除笔记
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - tag: 笔记的tag（版本标识），用于并发控制
    ///   - purge: 是否永久删除（true）还是移到回收站（false）
    /// - Returns: API响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func deleteNote(noteId: String, tag: String, purge: Bool = false) async throws -> [String: Any] {
        let tagEncoded = client.encodeURIComponent(tag)
        let purgeString = purge ? "true" : "false"
        let serviceTokenEncoded = client.encodeURIComponent(client.serviceToken)
        let body = "tag=\(tagEncoded)&purge=\(purgeString)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(client.baseURL)/note/full/\(noteId)/delete"

        var headers = client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        return try await client.performRequest(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8)
        )
    }

    // MARK: - 恢复回收站笔记

    /// 恢复回收站笔记
    ///
    /// 从回收站恢复笔记到原文件夹
    /// API端点: POST https://i.mi.com/note/note/{noteId}/restore
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - tag: 笔记的tag（版本标识），用于并发控制
    /// - Returns: API响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func restoreDeletedNote(noteId: String, tag: String) async throws -> [String: Any] {
        let tagEncoded = client.encodeURIComponent(tag)
        let serviceTokenEncoded = client.encodeURIComponent(client.serviceToken)
        let body = "tag=\(tagEncoded)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(client.baseURL)/note/note/\(noteId)/restore"

        var headers = client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        return try await client.performRequest(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8)
        )
    }

    // MARK: - 获取笔记详情

    /// 获取笔记详情（完整内容）
    ///
    /// 笔记列表API只返回摘要（snippet），需要调用此方法获取完整内容
    ///
    /// - Parameter noteId: 笔记ID
    /// - Returns: 包含完整笔记内容的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchNoteDetails(noteId: String) async throws -> [String: Any] {
        var urlComponents = URLComponents(string: "\(client.baseURL)/note/note/\(noteId)/")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        return try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )
    }

    // MARK: - 获取笔记列表（分页）

    /// 获取笔记列表（分页）
    ///
    /// 用于同步功能，支持完整同步和增量同步
    ///
    /// 注意：完整同步和增量同步都使用此方法，但syncTag参数仅用于内部逻辑，
    /// 不会作为查询参数发送到服务器。服务器无法解析syncTag查询参数。
    ///
    /// 使用示例：
    /// 1. 完整同步（第一次同步）：`fetchPage()` 不带syncTag参数
    /// 2. 增量同步（通过修改时间判断）：`fetchPage()` 然后比较笔记的modifyDate
    ///
    /// 响应格式：{"data": {"entries": [...], "folders": [...], "syncTag": "..."}}
    ///
    /// - Parameter syncTag: 同步标签，用于增量同步。空字符串表示获取第一页
    /// - Returns: 包含笔记和文件夹列表的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchPage(syncTag _: String = "") async throws -> [String: Any] {
        var urlComponents = URLComponents(string: "\(client.baseURL)/note/full/page")

        // syncTag 仅用于内部逻辑，不会发送到服务器
        let queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "limit", value: "200"),
        ]

        urlComponents?.queryItems = queryItems

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        return try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )
    }

    // MARK: - 获取私密笔记列表

    /// 获取私密笔记列表
    ///
    /// 获取指定文件夹（通常是私密笔记文件夹，folderId=2）的笔记列表
    ///
    /// - Parameters:
    ///   - folderId: 文件夹ID，默认为2（私密笔记）
    ///   - limit: 每页数量，默认200
    /// - Returns: 包含笔记列表的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchPrivateNotes(folderId: String = "2", limit: Int = 200) async throws -> [String: Any] {
        var urlComponents = URLComponents(string: "\(client.baseURL)/note/full/folder")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "folderId", value: folderId),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        let json = try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )

        if let code = json["code"] as? Int, code != 0 {
            let message = json["description"] as? String ?? json["message"] as? String ?? "获取私密笔记失败"
            throw MiNoteError.networkError(NSError(domain: "NoteAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        return json
    }

    // MARK: - 获取回收站笔记列表

    /// 获取回收站笔记列表
    ///
    /// 从服务器获取已删除的笔记列表
    ///
    /// - Parameters:
    ///   - limit: 每页返回的记录数，默认 200
    ///   - ts: 时间戳（可选，如果不提供则使用当前时间）
    /// - Returns: 包含 entries、folders、lastPage、expireInterval、syncTag 的字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchDeletedNotes(limit: Int = 200, ts: Int64? = nil) async throws -> [String: Any] {
        let timestamp = ts ?? Int64(Date().timeIntervalSince1970 * 1000)

        var urlComponents = URLComponents(string: "\(client.baseURL)/note/deleted/page")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(timestamp)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "_dc", value: "\(timestamp)"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        let json = try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )

        if let code = json["code"] as? Int, code != 0 {
            let message = json["description"] as? String ?? json["message"] as? String ?? "获取回收站笔记失败"
            throw MiNoteError.networkError(NSError(domain: "NoteAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        return json
    }

    // MARK: - 笔记历史记录

    /// 获取笔记历史记录列表
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - timestamp: 时间戳（毫秒），可选，默认为当前时间
    /// - Returns: 包含历史记录列表的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func fetchNoteHistoryVersions(noteId: String, timestamp: Int? = nil) async throws -> [String: Any] {
        let ts = timestamp ?? Int(Date().timeIntervalSince1970 * 1000)

        var urlComponents = URLComponents(string: "\(client.baseURL)/note/full/history/times")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(ts)"),
            URLQueryItem(name: "id", value: noteId),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        let json = try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )

        if let code = json["code"] as? Int, code != 0 {
            let message = json["description"] as? String ?? json["message"] as? String ?? "获取笔记历史记录失败"
            throw MiNoteError.networkError(NSError(domain: "NoteAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        return json
    }

    /// 获取笔记历史记录列表（另一个入口）
    ///
    /// - Parameter noteId: 笔记ID
    /// - Returns: 包含历史记录列表的响应字典，其中 data.tvList 是版本数组
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func getNoteHistoryTimes(noteId: String) async throws -> [String: Any] {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        var urlComponents = URLComponents(string: "\(client.baseURL)/note/full/history/times")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(ts)"),
            URLQueryItem(name: "id", value: noteId),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        return try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )
    }

    /// 获取笔记历史记录内容
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - version: 版本号（时间戳）
    /// - Returns: 包含历史记录笔记数据的响应字典，格式与普通笔记相同
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func getNoteHistory(noteId: String, version: Int64) async throws -> [String: Any] {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        var urlComponents = URLComponents(string: "\(client.baseURL)/note/full/history")
        urlComponents?.queryItems = [
            URLQueryItem(name: "ts", value: "\(ts)"),
            URLQueryItem(name: "id", value: noteId),
            URLQueryItem(name: "version", value: "\(version)"),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        return try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )
    }

    /// 恢复笔记历史记录
    ///
    /// - Parameters:
    ///   - noteId: 笔记ID
    ///   - version: 要恢复的版本号（时间戳）
    /// - Returns: API响应字典，包含恢复后的笔记信息
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func restoreNoteHistory(noteId: String, version: Int64) async throws -> [String: Any] {
        let urlString = "\(client.baseURL)/note/note/\(noteId)/history"

        let serviceTokenEncoded = client.encodeURIComponent(client.serviceToken)
        let body = "id=\(noteId)&version=\(version)&serviceToken=\(serviceTokenEncoded)"

        var headers = client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        return try await client.performRequest(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8)
        )
    }
}
