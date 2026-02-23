import Foundation

// MARK: - SyncEngine 附件处理

extension SyncEngine {

    // MARK: - 附件下载

    /// 下载笔记中的附件
    func downloadNoteImages(from noteDetails: [String: Any], noteId: String, forceRedownload: Bool = false) async throws -> [[String: Any]]? {
        var entry: [String: Any]?
        if let data = noteDetails["data"] as? [String: Any] {
            if let dataEntry = data["entry"] as? [String: Any] {
                entry = dataEntry
            }
        } else if let directEntry = noteDetails["entry"] as? [String: Any] {
            entry = directEntry
        } else if noteDetails["id"] != nil || noteDetails["content"] != nil {
            entry = noteDetails
        }

        guard let entry else {
            LogService.shared.debug(.sync, "无法提取 entry，跳过附件下载: \(noteId)")
            return nil
        }

        var settingData: [[String: Any]] = []

        if let setting = entry["setting"] as? [String: Any],
           let existingData = setting["data"] as? [[String: Any]]
        {
            settingData = existingData
        }

        for index in 0 ..< settingData.count {
            let attachmentData = settingData[index]

            guard let fileId = attachmentData["fileId"] as? String else { continue }
            guard let mimeType = attachmentData["mimeType"] as? String else { continue }

            if mimeType.hasPrefix("image/") {
                let fileType = String(mimeType.dropFirst("image/".count))

                if !forceRedownload {
                    if localStorage.validateImage(fileId: fileId, fileType: fileType) {
                        var updatedData = attachmentData
                        updatedData["localExists"] = true
                        settingData[index] = updatedData
                        continue
                    }
                }

                do {
                    let imageData = try await downloadImageWithRetry(fileId: fileId, type: "note_img")
                    try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)
                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    updatedData["downloaded"] = true
                    settingData[index] = updatedData
                } catch {
                    LogService.shared.error(.sync, "图片下载失败: \(fileId).\(fileType) - \(error.localizedDescription)")
                }
            } else if mimeType.hasPrefix("audio/") {
                if AudioCacheService.shared.isCached(fileId: fileId) {
                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    settingData[index] = updatedData
                    continue
                }

                do {
                    let audioData = try await fileAPI.downloadAudio(fileId: fileId)
                    try AudioCacheService.shared.cacheFile(data: audioData, fileId: fileId, mimeType: mimeType)
                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    updatedData["downloaded"] = true
                    settingData[index] = updatedData
                } catch {
                    LogService.shared.error(.sync, "音频下载失败: \(fileId) - \(error.localizedDescription)")
                }
            }
        }

        // 从 content 中提取额外的附件
        if let content = entry["content"] as? String {
            let allAttachmentData = await extractAndDownloadAllAttachments(
                from: content,
                existingSettingData: settingData,
                forceRedownload: forceRedownload
            )
            settingData = allAttachmentData
        }

        return settingData
    }

    /// 带重试的图片下载
    func downloadImageWithRetry(
        fileId: String,
        type: String,
        maxRetries: Int = 3
    ) async throws -> Data {
        var lastError: Error?

        for attempt in 1 ... maxRetries {
            do {
                return try await fileAPI.downloadFile(fileId: fileId, type: type)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let delay = TimeInterval(attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        LogService.shared.error(.sync, "图片下载失败（已重试 \(maxRetries) 次）: \(fileId)")
        throw lastError ?? SyncError.networkError(NSError(domain: "SyncEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "图片下载失败"]))
    }

    // MARK: - 附件提取

    /// 从 content 中提取所有附件并下载
    func extractAndDownloadAllAttachments(
        from content: String,
        existingSettingData: [[String: Any]],
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        var allSettingData = existingSettingData
        var existingFileIds = Set<String>()

        for entry in existingSettingData {
            if let fileId = entry["fileId"] as? String {
                existingFileIds.insert(fileId)
            }
        }

        let legacyImageData = await extractLegacyImages(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !legacyImageData.isEmpty {
            allSettingData.append(contentsOf: legacyImageData)
            for entry in legacyImageData {
                if let fileId = entry["fileId"] as? String { existingFileIds.insert(fileId) }
            }
        }

        let newImageData = await extractNewFormatImages(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !newImageData.isEmpty {
            allSettingData.append(contentsOf: newImageData)
            for entry in newImageData {
                if let fileId = entry["fileId"] as? String { existingFileIds.insert(fileId) }
            }
        }

        let audioData = await extractAudioAttachments(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !audioData.isEmpty {
            allSettingData.append(contentsOf: audioData)
        }

        return allSettingData
    }

    /// 提取旧版格式图片
    func extractLegacyImages(
        from content: String,
        existingFileIds: Set<String>,
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        let pattern = "\u{263A} ([^<]+)<0/></>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
        if matches.isEmpty { return [] }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            if existingFileIds.contains(fileId) { continue }

            if let entry = await downloadAndCreateSettingEntry(
                fileId: fileId,
                type: "note_img",
                attachmentType: "image",
                forceRedownload: forceRedownload
            ) {
                settingDataEntries.append(entry)
            }
        }

        return settingDataEntries
    }

    /// 提取新版格式图片
    func extractNewFormatImages(
        from content: String,
        existingFileIds: Set<String>,
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        let pattern = "<img[^>]+fileid=\"([^\"]+)\"[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
        if matches.isEmpty { return [] }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            if existingFileIds.contains(fileId) { continue }

            if let entry = await downloadAndCreateSettingEntry(
                fileId: fileId,
                type: "note_img",
                attachmentType: "image",
                forceRedownload: forceRedownload
            ) {
                settingDataEntries.append(entry)
            }
        }

        return settingDataEntries
    }

    /// 提取音频附件
    func extractAudioAttachments(
        from content: String,
        existingFileIds: Set<String>,
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        let pattern = "<sound[^>]+fileid=\"([^\"]+)\"[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
        if matches.isEmpty { return [] }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            if existingFileIds.contains(fileId) { continue }

            if let entry = await downloadAndCreateSettingEntry(
                fileId: fileId,
                type: "note_audio",
                attachmentType: "audio",
                forceRedownload: forceRedownload
            ) {
                settingDataEntries.append(entry)
            }
        }

        return settingDataEntries
    }

    /// 下载附件并创建 setting.data 条目
    func downloadAndCreateSettingEntry(
        fileId: String,
        type: String,
        attachmentType: String,
        forceRedownload: Bool
    ) async -> [String: Any]? {
        var existingFormat: String?
        var fileSize = 0

        if !forceRedownload {
            if attachmentType == "image" {
                let formats = ["jpg", "jpeg", "png", "gif", "webp"]
                for format in formats {
                    if localStorage.validateImage(fileId: fileId, fileType: format) {
                        existingFormat = format
                        if let imageData = localStorage.loadImage(fileId: fileId, fileType: format) {
                            fileSize = imageData.count
                        }
                        break
                    }
                }
            } else if attachmentType == "audio" {
                if AudioCacheService.shared.isCached(fileId: fileId) {
                    existingFormat = "amr"
                    if let cachedFileURL = AudioCacheService.shared.getCachedFile(for: fileId) {
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: cachedFileURL.path),
                           let size = attributes[.size] as? Int
                        {
                            fileSize = size
                        }
                    }
                }
            }
        }

        var downloadedFormat: String?

        if existingFormat == nil {
            do {
                let data = try await downloadImageWithRetry(fileId: fileId, type: type)
                fileSize = data.count

                if attachmentType == "image" {
                    let detectedFormat = detectImageFormat(from: data)
                    downloadedFormat = detectedFormat
                    try localStorage.saveImage(imageData: data, fileId: fileId, fileType: detectedFormat)
                } else if attachmentType == "audio" {
                    let detectedFormat = detectAudioFormat(from: data)
                    downloadedFormat = detectedFormat
                    let mimeType = "audio/\(detectedFormat)"
                    do {
                        try AudioCacheService.shared.cacheFile(data: data, fileId: fileId, mimeType: mimeType)
                    } catch {
                        LogService.shared.error(.sync, "音频保存失败: \(fileId) - \(error)")
                        return nil
                    }
                }
            } catch {
                LogService.shared.error(.sync, "附件下载失败: \(fileId) - \(error.localizedDescription)")
                return nil
            }
        }

        let finalFormat = downloadedFormat ?? existingFormat ?? (attachmentType == "image" ? "jpeg" : "amr")
        let mimeType = attachmentType == "image" ? "image/\(finalFormat)" : "audio/\(finalFormat)"

        return [
            "fileId": fileId,
            "mimeType": mimeType,
            "size": fileSize,
        ]
    }

    // MARK: - 格式检测

    /// 检测图片格式
    func detectImageFormat(from data: Data) -> String {
        guard data.count >= 12 else { return "jpeg" }

        let bytes = [UInt8](data.prefix(12))

        // PNG: 89 50 4E 47
        if bytes.count >= 4, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            return "png"
        }

        // GIF: 47 49 46
        if bytes.count >= 3, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 {
            return "gif"
        }

        // WebP: 52 49 46 46 ... 57 45 42 50
        if bytes.count >= 12, bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50
        {
            return "webp"
        }

        // JPEG: FF D8 FF
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "jpeg"
        }

        return "jpeg"
    }

    /// 检测音频格式
    func detectAudioFormat(from data: Data) -> String {
        guard data.count >= 12 else { return "amr" }

        let bytes = [UInt8](data.prefix(12))

        // AMR: #!AMR\n
        if bytes.count >= 6,
           bytes[0] == 0x23, bytes[1] == 0x21,
           bytes[2] == 0x41, bytes[3] == 0x4D,
           bytes[4] == 0x52, bytes[5] == 0x0A
        {
            return "amr"
        }

        // MP3: ID3 或 0xFF 0xFB
        if bytes.count >= 3,
           (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
           (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0)
        {
            return "mp3"
        }

        // M4A: ftyp
        if bytes.count >= 8,
           bytes[4] == 0x66, bytes[5] == 0x74,
           bytes[6] == 0x79, bytes[7] == 0x70
        {
            return "m4a"
        }

        // WAV: RIFF...WAVE
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49,
           bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x41,
           bytes[10] == 0x56, bytes[11] == 0x45
        {
            return "wav"
        }

        return "amr"
    }
}
