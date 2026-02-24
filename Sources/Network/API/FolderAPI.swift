import Foundation

/// 文件夹 API
///
/// 负责文件夹的创建、重命名、删除、详情获取
public struct FolderAPI: Sendable {
    public static let shared = FolderAPI()

    private let client: APIClient

    /// NetworkModule 使用的构造器
    init(client: APIClient) {
        self.client = client
    }

    /// 过渡期兼容构造器（供 static let shared 使用）
    private init() {
        self.client = .shared
    }

    // MARK: - 创建文件夹

    /// 创建文件夹
    ///
    /// - Parameter name: 文件夹名称
    /// - Returns: 包含新创建文件夹信息的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func createFolder(name: String) async throws -> [String: Any] {
        let entry: [String: Any] = [
            "subject": name,
            "createDate": Int(Date().timeIntervalSince1970 * 1000),
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000),
        ]

        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8)
        else {
            throw URLError(.cannotParseResponse)
        }

        let entryEncoded = client.encodeURIComponent(entryJson)
        let serviceTokenEncoded = await client.encodeURIComponent(client.serviceToken)
        let body = "entry=\(entryEncoded)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(client.baseURL)/note/folder"

        var headers = await client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        let json = try await client.performRequest(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8)
        )

        if let code = json["code"] as? Int, code != 0 {
            let message = json["description"] as? String ?? json["message"] as? String ?? "创建文件夹失败"
            throw MiNoteError.networkError(NSError(domain: "FolderAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        return json
    }

    // MARK: - 重命名文件夹

    /// 重命名文件夹
    ///
    /// - Parameters:
    ///   - folderId: 文件夹 ID
    ///   - newName: 新名称
    ///   - existingTag: 现有 tag（版本标识），用于并发控制
    ///   - originalCreateDate: 原始创建时间戳（毫秒），用于保持创建时间不变
    /// - Returns: API 响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func renameFolder(folderId: String, newName: String, existingTag: String, originalCreateDate: Int? = nil) async throws -> [String: Any] {
        let createDate = originalCreateDate ?? Int(Date().timeIntervalSince1970 * 1000)

        let entry: [String: Any] = [
            "id": folderId,
            "tag": existingTag,
            "createDate": createDate,
            "modifyDate": Int(Date().timeIntervalSince1970 * 1000),
            "subject": newName,
            "type": "folder",
        ]

        guard let entryData = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let entryJson = String(data: entryData, encoding: .utf8)
        else {
            throw URLError(.cannotParseResponse)
        }

        let entryEncoded = client.encodeURIComponent(entryJson)
        let serviceTokenEncoded = await client.encodeURIComponent(client.serviceToken)
        let body = "entry=\(entryEncoded)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(client.baseURL)/note/folder/\(folderId)"

        var headers = await client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        let json = try await client.performRequest(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8)
        )

        if let code = json["code"] as? Int, code != 0 {
            let message = json["description"] as? String ?? json["message"] as? String ?? "重命名文件夹失败"
            throw MiNoteError.networkError(NSError(domain: "FolderAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        return json
    }

    // MARK: - 删除文件夹

    /// 删除文件夹
    ///
    /// - Parameters:
    ///   - folderId: 文件夹 ID
    ///   - tag: 文件夹的 tag（版本标识），用于并发控制
    ///   - purge: 是否永久删除（true）还是移到回收站（false）
    /// - Returns: API 响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    func deleteFolder(folderId: String, tag: String, purge: Bool = false) async throws -> [String: Any] {
        let tagEncoded = client.encodeURIComponent(tag)
        let purgeString = purge ? "true" : "false"
        let serviceTokenEncoded = await client.encodeURIComponent(client.serviceToken)
        let body = "tag=\(tagEncoded)&purge=\(purgeString)&serviceToken=\(serviceTokenEncoded)"

        let urlString = "\(client.baseURL)/note/full/\(folderId)/delete"

        var headers = await client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        let json = try await client.performRequest(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8)
        )

        if let code = json["code"] as? Int, code != 0 {
            let message = json["description"] as? String ?? json["message"] as? String ?? "删除文件夹失败"
            throw MiNoteError.networkError(NSError(domain: "FolderAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        return json
    }

    // MARK: - 获取文件夹详情

    /// 获取文件夹详情
    ///
    /// 通过遍历 /note/full/page 分页数据查找目标文件夹信息
    ///
    /// - Parameter folderId: 文件夹 ID
    /// - Returns: 包含文件夹信息的响应字典，格式：{"code": 0, "data": {"entry": {...}}}
    /// - Throws: NSError（文件夹不存在）或 MiNoteError（网络错误等）
    func fetchFolderDetails(folderId: String) async throws -> [String: Any] {
        var syncTag = ""
        var foundFolder: [String: Any]?

        // 遍历所有分页，直到找到目标文件夹或没有更多数据
        while foundFolder == nil {
            let pageResponse = try await fetchPageInternal(syncTag: syncTag)

            if let data = pageResponse["data"] as? [String: Any],
               let folderEntries = data["folders"] as? [[String: Any]]
            {
                // 查找目标文件夹
                for folderEntry in folderEntries {
                    // 处理 ID（可能是 String 或 Int）
                    var entryId: String?
                    if let idString = folderEntry["id"] as? String {
                        entryId = idString
                    } else if let idInt = folderEntry["id"] as? Int {
                        entryId = String(idInt)
                    }

                    if entryId == folderId {
                        foundFolder = folderEntry
                        break
                    }
                }

                if foundFolder != nil {
                    break
                }

                // 检查是否有更多分页（syncTag 在响应顶层，不在 data 中）
                if let nextSyncTag = pageResponse["syncTag"] as? String, !nextSyncTag.isEmpty, nextSyncTag != syncTag {
                    syncTag = nextSyncTag
                } else {
                    break
                }
            } else {
                break
            }
        }

        if let folderEntry = foundFolder {
            return [
                "code": 0,
                "data": [
                    "entry": folderEntry,
                ],
            ]
        } else {
            throw NSError(domain: "FolderAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在: \(folderId)"])
        }
    }

    // MARK: - 内部方法

    /// 获取笔记列表分页（内部方法）
    ///
    /// 直接构建 /note/full/page 请求，避免依赖 NoteAPI
    ///
    /// - Parameter syncTag: 同步标签，用于增量同步。空字符串表示获取第一页
    /// - Returns: 包含笔记和文件夹列表的响应字典
    /// - Throws: MiNoteError（网络错误、认证错误等）
    private func fetchPageInternal(syncTag _: String = "") async throws -> [String: Any] {
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
}
