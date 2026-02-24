import CryptoKit
import Foundation

/// 文件 API
///
/// 负责文件上传（三步流程：请求上传 -> 上传块 -> 提交）和下载，
/// 支持图片、音频、通用文件
public struct FileAPI: Sendable {
    public static let shared = FileAPI()

    private let client: APIClient

    /// NetworkModule 使用的构造器
    init(client: APIClient) {
        self.client = client
    }

    /// 过渡期兼容构造器（供 static let shared 使用）
    private init() {
        self.client = .shared
    }

    /// 音频下载信息
    struct AudioDownloadInfo {
        let url: URL
        let secureKey: String?
    }

    // MARK: - 哈希计算

    /// 计算文件的SHA1哈希值
    private func sha1Hash(of data: Data) -> String {
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 计算文件的MD5哈希值
    private func md5Hash(of data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 根据文件扩展名获取MIME类型
    private func mimeTypeForExtension(_ ext: String) -> String {
        let mimeTypes: [String: String] = [
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "webp": "image/webp",
            "pdf": "application/pdf",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ppt": "application/vnd.ms-powerpoint",
            "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "txt": "text/plain",
            "md": "text/markdown",
            "zip": "application/zip",
            "rar": "application/x-rar-compressed",
            "mp3": "audio/mpeg",
            "mp4": "video/mp4",
            "mov": "video/quicktime",
        ]

        return mimeTypes[ext] ?? "application/octet-stream"
    }

    // MARK: - 图片上传

    /// 上传图片到小米服务器（新API）
    ///
    /// 三步上传流程：请求上传 -> 上传文件块 -> 提交上传
    ///
    /// - Parameters:
    ///   - imageData: 图片数据
    ///   - fileName: 文件名
    ///   - mimeType: MIME 类型（如 "image/jpeg", "image/png"）
    /// - Returns: 包含文件ID的响应字典
    func uploadImage(imageData: Data, fileName: String, mimeType: String) async throws -> [String: Any] {
        guard await client.isAuthenticated() else {
            throw MiNoteError.notAuthenticated
        }

        let sha1 = sha1Hash(of: imageData)
        let md5 = md5Hash(of: imageData)
        let fileSize = imageData.count

        // 第一步：请求上传
        let requestUploadResponse = try await requestImageUpload(
            fileName: fileName,
            fileSize: fileSize,
            sha1: sha1,
            md5: md5,
            mimeType: mimeType
        )

        // 检查文件是否已存在
        var fileId: String?

        // 情况1：服务器有缓存（文件已存在）
        if let existingFileId = requestUploadResponse["fileId"] as? String {
            fileId = existingFileId
        }
        // 情况2：服务器无缓存（新文件）
        else if let storage = requestUploadResponse["storage"] as? [String: Any] {
            let exists = storage["exists"] as? Bool ?? false

            if exists {
                if let existingFileId = storage["fileId"] as? String {
                    fileId = existingFileId
                } else {
                    throw MiNoteError.invalidResponse
                }
            } else {
                guard let uploadId = storage["uploadId"] as? String,
                      let kss = storage["kss"] as? [String: Any],
                      let blockMetas = kss["block_metas"] as? [[String: Any]],
                      let firstBlockMeta = blockMetas.first,
                      let blockMeta = firstBlockMeta["block_meta"] as? String,
                      let fileMeta = kss["file_meta"] as? String,
                      let nodeUrls = kss["node_urls"] as? [String],
                      let nodeUrl = nodeUrls.first
                else {
                    throw MiNoteError.invalidResponse
                }

                // 第二步：实际上传文件数据，获取 commit_meta
                let commitMeta = try await uploadFileChunk(
                    fileData: imageData,
                    nodeUrl: nodeUrl,
                    fileMeta: fileMeta,
                    blockMeta: blockMeta,
                    chunkPos: 0
                )

                // 第三步：提交上传，获取 fileId
                fileId = try await commitImageUpload(
                    uploadId: uploadId,
                    fileSize: fileSize,
                    sha1: sha1,
                    fileMeta: fileMeta,
                    commitMeta: commitMeta
                )
            }
        }

        guard let finalFileId = fileId else {
            throw MiNoteError.invalidResponse
        }

        return [
            "fileId": finalFileId,
            "digest": sha1,
            "mimeType": mimeType,
        ]
    }

    // MARK: - 语音文件上传

    /// 上传语音文件到小米服务器
    ///
    /// 语音文件上传流程与图片相同，使用 `note_img` 类型。
    /// 完整流程分为三步：
    /// 1. 请求上传（request_upload_file）- 获取 uploadId 和 KSS 信息
    /// 2. 上传文件块（upload_block_chunk）- 上传实际文件数据
    /// 3. 提交上传（commit）- 确认上传完成，获取 fileId
    ///
    /// - Parameters:
    ///   - audioData: 语音文件数据
    ///   - fileName: 文件名（如 "recording.mp3"）
    ///   - mimeType: MIME 类型，推荐使用 "audio/mpeg"
    /// - Returns: 包含 fileId、digest、mimeType 的字典
    /// - Throws: MiNoteError（未认证、网络错误、响应无效等）
    public func uploadAudio(audioData: Data, fileName: String, mimeType: String = "audio/mpeg") async throws -> [String: Any] {
        guard await client.isAuthenticated() else {
            throw MiNoteError.notAuthenticated
        }

        let sha1 = sha1Hash(of: audioData)
        let md5 = md5Hash(of: audioData)
        let fileSize = audioData.count

        // 第一步：请求上传
        // 语音文件必须使用 note_img 类型（与图片相同）
        let requestUploadResponse = try await requestAudioUpload(
            fileName: fileName,
            fileSize: fileSize,
            sha1: sha1,
            md5: md5,
            mimeType: mimeType
        )

        var fileId: String?

        // 情况1：服务器有缓存（文件已存在）
        if let existingFileId = requestUploadResponse["fileId"] as? String {
            fileId = existingFileId
        }
        // 情况2：服务器无缓存（需要实际上传）
        else if let storage = requestUploadResponse["storage"] as? [String: Any] {
            let exists = storage["exists"] as? Bool ?? false

            if exists {
                if let existingFileId = storage["fileId"] as? String {
                    fileId = existingFileId
                } else {
                    throw MiNoteError.invalidResponse
                }
            } else {
                guard let uploadId = storage["uploadId"] as? String,
                      let kss = storage["kss"] as? [String: Any],
                      let blockMetas = kss["block_metas"] as? [[String: Any]],
                      let firstBlockMeta = blockMetas.first,
                      let blockMeta = firstBlockMeta["block_meta"] as? String,
                      let fileMeta = kss["file_meta"] as? String,
                      let nodeUrls = kss["node_urls"] as? [String],
                      let nodeUrl = nodeUrls.first
                else {
                    throw MiNoteError.invalidResponse
                }

                // 第二步：上传文件块
                let commitMeta = try await uploadFileChunk(
                    fileData: audioData,
                    nodeUrl: nodeUrl,
                    fileMeta: fileMeta,
                    blockMeta: blockMeta,
                    chunkPos: 0
                )

                // 第三步：提交上传
                fileId = try await commitAudioUpload(
                    uploadId: uploadId,
                    fileSize: fileSize,
                    sha1: sha1,
                    fileMeta: fileMeta,
                    commitMeta: commitMeta
                )
            }
        }

        guard let finalFileId = fileId else {
            throw MiNoteError.invalidResponse
        }

        return [
            "fileId": finalFileId,
            "digest": sha1,
            "mimeType": mimeType,
        ]
    }

    // MARK: - 语音文件下载

    /// 获取语音文件下载 URL 和解密密钥
    ///
    /// 使用 `/file/full/v2` API 获取语音文件的下载 URL。
    /// 该 API 返回 KSS 格式的响应，包含分块下载 URL 和解密密钥。
    ///
    /// - Parameter fileId: 语音文件 ID（如 `1315204657.jgHyouv563iSF_XCE4jhAg`）
    /// - Returns: 下载信息（URL 和解密密钥）
    /// - Throws: MiNoteError（未认证、网络错误、响应无效等）
    func getAudioDownloadInfo(fileId: String) async throws -> AudioDownloadInfo {
        guard await client.isAuthenticated() else {
            throw MiNoteError.notAuthenticated
        }

        let ts = Int(Date().timeIntervalSince1970 * 1000)
        // 使用 note_img 类型（与上传时相同）
        let urlString = "\(client.baseURL)/file/full/v2?ts=\(ts)&type=note_img&fileid=\(client.encodeURIComponent(fileId))"

        let json = try await client.performRequest(
            url: urlString,
            method: "GET",
            headers: client.getHeaders()
        )

        guard let code = json["code"] as? Int, code == 0 else {
            throw MiNoteError.invalidResponse
        }

        guard let dataDict = json["data"] as? [String: Any] else {
            throw MiNoteError.invalidResponse
        }

        // 尝试简单格式
        if let downloadURLString = dataDict["url"] as? String,
           let downloadURL = URL(string: downloadURLString)
        {
            return AudioDownloadInfo(url: downloadURL, secureKey: nil)
        }

        // 尝试 KSS 格式
        if let kss = dataDict["kss"] as? [String: Any],
           let blocks = kss["blocks"] as? [[String: Any]],
           let firstBlock = blocks.first,
           let urls = firstBlock["urls"] as? [String],
           let firstURLString = urls.first
        {
            // 将 http:// 转换为 https://，避免 ATS 安全策略阻止
            let secureURLString = firstURLString.hasPrefix("http://")
                ? firstURLString.replacingOccurrences(of: "http://", with: "https://")
                : firstURLString

            let secureKey = kss["secure_key"] as? String

            if let downloadURL = URL(string: secureURLString) {
                return AudioDownloadInfo(url: downloadURL, secureKey: secureKey)
            }
        }

        throw MiNoteError.invalidResponse
    }

    /// 获取语音文件下载 URL（兼容旧接口）
    ///
    /// - Parameter fileId: 语音文件 ID
    /// - Returns: 下载 URL
    /// - Throws: MiNoteError
    public func getAudioDownloadURL(fileId: String) async throws -> URL {
        let info = try await getAudioDownloadInfo(fileId: fileId)
        return info.url
    }

    /// 下载语音文件
    ///
    /// 下载指定 fileId 的语音文件数据。
    /// 该方法会先获取下载 URL 和解密密钥，然后下载实际的音频数据，
    /// 最后使用密钥解密数据。
    ///
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - progressHandler: 下载进度回调（可选），参数为已下载字节数和总字节数
    /// - Returns: 解密后的音频文件数据
    /// - Throws: MiNoteError（未认证、网络错误、下载失败等）
    public func downloadAudio(fileId: String, progressHandler: ((Int64, Int64) -> Void)? = nil) async throws -> Data {
        guard await client.isAuthenticated() else {
            throw MiNoteError.notAuthenticated
        }

        // 第一步：获取下载 URL 和解密密钥
        let downloadInfo = try await getAudioDownloadInfo(fileId: fileId)

        // 第二步：下载音频数据（下载请求不需要认证头，URL 已包含认证信息）
        let manager = await MainActor.run { NetworkRequestManager.shared }
        let response = try await manager.request(
            url: downloadInfo.url.absoluteString,
            method: "GET",
            retryOnFailure: true
        )

        guard response.response.statusCode == 200 else {
            throw MiNoteError.networkError(URLError(.badServerResponse))
        }

        guard !response.data.isEmpty else {
            throw MiNoteError.invalidResponse
        }

        // 第三步：解密数据（如果有密钥）
        var audioData = response.data
        if let secureKey = downloadInfo.secureKey, !secureKey.isEmpty {
            audioData = AudioDecryptService.shared.decrypt(data: response.data, secureKey: secureKey)
        }

        // 验证下载的音频数据
        let format = AudioConverterService.shared.getAudioFormat(audioData)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("downloaded_audio_check.mp3")
        try? audioData.write(to: tempURL)
        let probeResult = AudioConverterService.shared.probeAudioFileDetailed(tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        // 调用进度回调（下载完成）
        progressHandler?(Int64(audioData.count), Int64(audioData.count))

        return audioData
    }

    /// 下载语音文件并缓存
    ///
    /// 下载语音文件并自动缓存到本地。如果文件已缓存，直接返回缓存路径。
    ///
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - mimeType: MIME 类型（默认 "audio/mpeg"）
    ///   - progressHandler: 下载进度回调（可选）
    /// - Returns: 本地缓存文件 URL
    /// - Throws: MiNoteError（未认证、网络错误、缓存失败等）
    public func downloadAndCacheAudio(
        fileId: String,
        mimeType: String = "audio/mpeg",
        progressHandler: ((Int64, Int64) -> Void)? = nil
    ) async throws -> URL {
        // 检查缓存
        if let cachedURL = await AudioCacheService.shared.getCachedFile(for: fileId) {
            return cachedURL
        }

        // 下载文件
        let audioData = try await downloadAudio(fileId: fileId, progressHandler: progressHandler)

        // 缓存文件
        return try await AudioCacheService.shared.cacheFile(data: audioData, fileId: fileId, mimeType: mimeType)
    }

    // MARK: - 通用文件上传/下载

    /// 上传文件到小米服务器（multipart/form-data）
    ///
    /// - Parameters:
    ///   - fileData: 文件数据
    ///   - fileName: 文件名
    ///   - mimeType: MIME 类型（如 "image/jpeg", "image/png", "application/pdf" 等）
    /// - Returns: 包含文件ID的响应字典
    func uploadFile(fileData: Data, fileName: String, mimeType: String) async throws -> [String: Any] {
        let boundary = "----WebKitFormBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let urlString = "\(client.baseURL)/file/upload"

        var headers = await client.getHeaders()
        headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        headers["Content-Length"] = "\(body.count)"

        // uploadFile 接受 200 和 201，performRequest 只接受 200，需要直接使用 NetworkRequestManager
        let manager = await MainActor.run { NetworkRequestManager.shared }
        let response = try await manager.request(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body,
            retryOnFailure: true
        )

        if response.response.statusCode == 401 {
            let responseString = String(data: response.data, encoding: .utf8) ?? ""
            try await client.handle401Error(responseBody: responseString, urlString: urlString)
        }

        guard response.response.statusCode == 200 || response.response.statusCode == 201 else {
            throw MiNoteError.networkError(URLError(.badServerResponse))
        }

        let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] ?? [:]

        if let code = json["code"] as? Int, code != 0 {
            let message = json["message"] as? String ?? "上传失败"
            throw MiNoteError.networkError(NSError(domain: "FileAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        return json
    }

    /// 从文件URL上传文件
    ///
    /// - Parameter fileURL: 文件URL
    /// - Returns: 包含文件ID的响应字典
    func uploadFile(from fileURL: URL) async throws -> [String: Any] {
        guard fileURL.isFileURL else {
            throw MiNoteError.networkError(URLError(.badURL))
        }

        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        let fileExtension = (fileURL.pathExtension as NSString).lowercased
        let mimeType = mimeTypeForExtension(fileExtension)

        return try await uploadFile(fileData: fileData, fileName: fileName, mimeType: mimeType)
    }

    /// 下载文件
    ///
    /// - Parameters:
    ///   - fileId: 文件ID
    ///   - type: 文件类型，默认 "note_img"
    /// - Returns: 文件数据
    func downloadFile(fileId: String, type: String = "note_img") async throws -> Data {
        var urlComponents = URLComponents(string: "\(client.baseURL)/file/full")
        urlComponents?.queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "fileid", value: fileId),
        ]

        guard let urlString = urlComponents?.url?.absoluteString else {
            throw URLError(.badURL)
        }

        // 返回 Data，不能使用 performRequest（它返回 [String: Any]），直接使用 NetworkRequestManager
        let manager = await MainActor.run { NetworkRequestManager.shared }
        let response = try await manager.request(
            url: urlString,
            method: "GET",
            headers: client.getHeaders(),
            retryOnFailure: true
        )

        if response.response.statusCode == 401 {
            let responseBody = String(data: response.data, encoding: .utf8) ?? ""
            try await client.handle401Error(responseBody: responseBody, urlString: urlString)
        }

        guard response.response.statusCode == 200 else {
            throw MiNoteError.networkError(URLError(.badServerResponse))
        }

        return response.data
    }

    // MARK: - 内部上传流程

    /// 请求图片上传（第一步）
    private func requestImageUpload(fileName: String, fileSize: Int, sha1: String, md5: String, mimeType: String) async throws -> [String: Any] {
        let urlString = "\(client.baseURL)/file/v2/user/request_upload_file"

        let dataDict: [String: Any] = [
            "type": "note_img",
            "storage": [
                "filename": fileName,
                "size": fileSize,
                "sha1": sha1,
                "mimeType": mimeType,
                "kss": [
                    "block_infos": [
                        [
                            "blob": [:] as [String: Any],
                            "size": fileSize,
                            "md5": md5,
                            "sha1": sha1,
                        ],
                    ],
                ],
            ],
        ]

        guard let dataJson = try? JSONSerialization.data(withJSONObject: dataDict, options: [.sortedKeys]),
              let dataString = String(data: dataJson, encoding: .utf8)
        else {
            throw MiNoteError.invalidResponse
        }

        let dataEncoded = client.encodeURIComponent(dataString)
        let serviceTokenEncoded = await client.encodeURIComponent(client.serviceToken)
        let body = "data=\(dataEncoded)&serviceToken=\(serviceTokenEncoded)"

        var headers = await client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        let json = try await client.performRequest(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8)
        )

        guard let code = json["code"] as? Int, code == 0,
              let responseDataDict = json["data"] as? [String: Any]
        else {
            throw MiNoteError.invalidResponse
        }

        return responseDataDict
    }

    /// 请求语音文件上传（第一步）
    ///
    /// 语音文件必须使用 `note_img` 类型，与图片上传相同。
    private func requestAudioUpload(fileName: String, fileSize: Int, sha1: String, md5: String, mimeType: String) async throws -> [String: Any] {
        let urlString = "\(client.baseURL)/file/v2/user/request_upload_file"

        // 手动构建 JSON 字符串，确保字段顺序与图片上传完全一致
        let dataString = """
        {"type":"note_img","storage":{"filename":"\(fileName)","size":\(fileSize),"sha1":"\(sha1)","mimeType":"\(
            mimeType
        )","kss":{"block_infos":[{"blob":{},"size":\(fileSize),"md5":"\(md5)","sha1":"\(sha1)"}]}}}
        """

        let dataEncoded = client.encodeURIComponent(dataString)
        let serviceTokenEncoded = await client.encodeURIComponent(client.serviceToken)
        let body = "data=\(dataEncoded)&serviceToken=\(serviceTokenEncoded)"

        var headers = await client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        let json = try await client.performRequest(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8)
        )

        guard let code = json["code"] as? Int, code == 0,
              let dataDict = json["data"] as? [String: Any]
        else {
            throw MiNoteError.invalidResponse
        }

        return dataDict
    }

    /// 上传文件块到KSS（第二步）
    ///
    /// - Returns: commit_meta，用于后续提交上传
    private func uploadFileChunk(fileData: Data, nodeUrl: String, fileMeta: String, blockMeta: String, chunkPos: Int) async throws -> String {
        var urlString = "\(nodeUrl)/upload_block_chunk"
        urlString += "?chunk_pos=\(chunkPos)"
        urlString += "&&file_meta=\(client.encodeURIComponent(fileMeta))"
        urlString += "&block_meta=\(client.encodeURIComponent(blockMeta))"

        let headers = [
            "Content-Type": "application/octet-stream",
            "Content-Length": "\(fileData.count)",
        ]

        let manager = await MainActor.run { NetworkRequestManager.shared }
        let response = try await manager.request(
            url: urlString,
            method: "POST",
            headers: headers,
            body: fileData,
            retryOnFailure: true
        )

        guard response.response.statusCode == 200 || response.response.statusCode == 201 else {
            throw MiNoteError.networkError(URLError(.badServerResponse))
        }

        // 尝试从响应中解析 commit_meta
        if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
           let commitMeta = json["commit_meta"] as? String
        {
            return commitMeta
        } else if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let commitMeta = dataDict["commit_meta"] as? String
        {
            return commitMeta
        } else {
            // 如果响应中没有 commit_meta，使用 blockMeta 作为 fallback
            return blockMeta
        }
    }

    /// 提交图片上传（第三步）
    private func commitImageUpload(uploadId: String, fileSize: Int, sha1: String, fileMeta: String, commitMeta: String) async throws -> String {
        let urlString = "\(client.baseURL)/file/v2/user/commit"

        let commitData: [String: Any] = [
            "storage": [
                "uploadId": uploadId,
                "size": fileSize,
                "sha1": sha1,
                "kss": [
                    "file_meta": fileMeta,
                    "commit_metas": [
                        [
                            "commit_meta": commitMeta,
                        ],
                    ],
                ],
            ],
        ]

        guard let commitJson = try? JSONSerialization.data(withJSONObject: commitData, options: [.sortedKeys]),
              let commitString = String(data: commitJson, encoding: .utf8)
        else {
            throw MiNoteError.invalidResponse
        }

        let commitEncoded = client.encodeURIComponent(commitString)
        let serviceTokenEncoded = await client.encodeURIComponent(client.serviceToken)
        let body = "commit=\(commitEncoded)&serviceToken=\(serviceTokenEncoded)"

        var headers = await client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        let manager = await MainActor.run { NetworkRequestManager.shared }
        let response = try await manager.request(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8),
            retryOnFailure: true
        )

        if response.response.statusCode == 401 {
            let responseString = String(data: response.data, encoding: .utf8) ?? ""
            try await client.handle401Error(responseBody: responseString, urlString: urlString)
        }

        guard response.response.statusCode == 200 else {
            throw MiNoteError.networkError(URLError(.badServerResponse))
        }

        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw MiNoteError.invalidResponse
        }

        guard let code = json["code"] as? Int, code == 0,
              let dataDict = json["data"] as? [String: Any],
              let fileId = dataDict["fileId"] as? String
        else {
            throw MiNoteError.invalidResponse
        }

        return fileId
    }

    /// 提交语音文件上传（第三步）
    private func commitAudioUpload(uploadId: String, fileSize: Int, sha1: String, fileMeta: String, commitMeta: String) async throws -> String {
        let urlString = "\(client.baseURL)/file/v2/user/commit"

        // 手动构建 JSON 字符串，确保字段顺序正确
        let commitDataString = """
        {"storage":{"uploadId":"\(uploadId)","size":\(fileSize),"sha1":"\(sha1)","kss":{"file_meta":"\(fileMeta)","commit_metas":[{"commit_meta":"\(
            commitMeta
        )"}]}}}
        """

        let commitEncoded = client.encodeURIComponent(commitDataString)
        let serviceTokenEncoded = await client.encodeURIComponent(client.serviceToken)
        let body = "commit=\(commitEncoded)&serviceToken=\(serviceTokenEncoded)"

        var headers = await client.getPostHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"

        let manager = await MainActor.run { NetworkRequestManager.shared }
        let response = try await manager.request(
            url: urlString,
            method: "POST",
            headers: headers,
            body: body.data(using: .utf8),
            retryOnFailure: true
        )

        if response.response.statusCode == 401 {
            let responseString = String(data: response.data, encoding: .utf8) ?? ""
            try await client.handle401Error(responseBody: responseString, urlString: urlString)
        }

        guard response.response.statusCode == 200 else {
            throw MiNoteError.networkError(URLError(.badServerResponse))
        }

        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw MiNoteError.invalidResponse
        }

        guard let code = json["code"] as? Int, code == 0,
              let dataDict = json["data"] as? [String: Any],
              let fileId = dataDict["fileId"] as? String
        else {
            throw MiNoteError.invalidResponse
        }

        return fileId
    }
}
