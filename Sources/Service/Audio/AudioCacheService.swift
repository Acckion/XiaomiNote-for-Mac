import Foundation

/// 缓存音频文件元数据
struct CachedAudioFile: Codable {
    /// 文件 ID
    let fileId: String

    /// 本地文件路径（相对于缓存目录）
    let localPath: String

    /// 文件大小（字节）
    let fileSize: Int64

    /// MIME 类型
    let mimeType: String

    /// 缓存时间
    let cachedAt: Date

    /// 最后访问时间
    var lastAccessedAt: Date
}

/// 语音文件缓存服务
///
/// 负责管理语音文件的本地缓存，包括：
/// - 缓存文件的读写
/// - 缓存大小管理
/// - LRU 淘汰策略
/// - 缓存清理
actor AudioCacheService {

    // MARK: - 单例

    static let shared = AudioCacheService()

    // MARK: - 属性

    /// 文件管理器
    private let fileManager = FileManager.default

    /// 缓存目录
    private let cacheDirectory: URL

    /// 元数据文件路径
    private let metadataFilePath: URL

    /// 最大缓存大小（字节）- 100 MB
    let maxCacheSize: Int64 = 100 * 1024 * 1024

    /// 缓存元数据（fileId -> CachedAudioFile）
    private var cacheMetadata: [String: CachedAudioFile] = [:]

    // MARK: - 初始化

    init() {
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appBundleID = Bundle.main.bundleIdentifier ?? "com.mi.note.mac"
        let appDirectory = appSupportDirectory.appendingPathComponent(appBundleID)
        self.cacheDirectory = appDirectory.appendingPathComponent("audio")
        self.metadataFilePath = appDirectory.appendingPathComponent("audio_cache_metadata.json")

        // 目录创建和元数据加载在 actor 初始化后通过 nonisolated 方法处理
    }

    /// 初始化缓存目录和元数据（需要在首次使用前调用）
    func initializeIfNeeded() {
        createCacheDirectoryIfNeeded()
        if cacheMetadata.isEmpty {
            loadMetadata()
        }
    }

    // MARK: - 目录管理

    /// 创建缓存目录（如果不存在）
    private func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                LogService.shared.error(.audio, "创建缓存目录失败: \(error)")
            }
        }
    }

    // MARK: - 元数据管理

    /// 加载缓存元数据
    private func loadMetadata() {
        guard fileManager.fileExists(atPath: metadataFilePath.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: metadataFilePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadataArray = try decoder.decode([CachedAudioFile].self, from: data)

            cacheMetadata = Dictionary(uniqueKeysWithValues: metadataArray.map { ($0.fileId, $0) })

            validateCacheFiles()
        } catch {
            LogService.shared.error(.audio, "加载缓存元数据失败: \(error)")
            cacheMetadata = [:]
        }
    }

    /// 保存缓存元数据
    private func saveMetadata() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(Array(cacheMetadata.values))
            try data.write(to: metadataFilePath)
        } catch {
            LogService.shared.error(.audio, "保存缓存元数据失败: \(error)")
        }
    }

    /// 验证缓存文件是否存在，移除无效的元数据
    private func validateCacheFiles() {
        var invalidFileIds: [String] = []

        for (fileId, metadata) in cacheMetadata {
            let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)
            if !fileManager.fileExists(atPath: filePath.path) {
                invalidFileIds.append(fileId)
            }
        }

        for fileId in invalidFileIds {
            cacheMetadata.removeValue(forKey: fileId)
        }
    }

    // MARK: - 缓存读写方法

    /// 获取缓存的音频文件路径
    ///
    /// - Parameter fileId: 文件 ID
    /// - Returns: 本地文件 URL，如果未缓存则返回 nil
    func getCachedFile(for fileId: String) -> URL? {
        initializeIfNeededSync()

        guard var metadata = cacheMetadata[fileId] else {
            return nil
        }

        let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)

        guard fileManager.fileExists(atPath: filePath.path) else {
            cacheMetadata.removeValue(forKey: fileId)
            saveMetadata()
            return nil
        }

        metadata.lastAccessedAt = Date()
        cacheMetadata[fileId] = metadata
        saveMetadata()

        return filePath
    }

    /// 缓存音频文件
    ///
    /// - Parameters:
    ///   - data: 音频文件数据
    ///   - fileId: 文件 ID
    ///   - mimeType: MIME 类型
    /// - Returns: 缓存后的本地文件 URL
    /// - Throws: 缓存失败时抛出错误
    @discardableResult
    func cacheFile(data: Data, fileId: String, mimeType: String) throws -> URL {
        initializeIfNeededSync()

        createCacheDirectoryIfNeeded()

        let currentSize = calculateCacheSize()
        let dataSize = Int64(data.count)

        if currentSize + dataSize > maxCacheSize {
            let targetSize = maxCacheSize - dataSize - (10 * 1024 * 1024)
            evictLeastRecentlyUsedInternal(targetSize: max(0, targetSize))
        }

        let fileExtension = Self.getFileExtension(for: mimeType)
        let fileName = "\(fileId).\(fileExtension)"
        let filePath = cacheDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: filePath, options: .atomic)
        } catch {
            LogService.shared.error(.audio, "缓存文件失败: \(error)")
            throw error
        }

        let metadata = CachedAudioFile(
            fileId: fileId,
            localPath: fileName,
            fileSize: dataSize,
            mimeType: mimeType,
            cachedAt: Date(),
            lastAccessedAt: Date()
        )
        cacheMetadata[fileId] = metadata

        saveMetadata()

        return filePath
    }

    /// 检查文件是否已缓存
    ///
    /// - Parameter fileId: 文件 ID
    /// - Returns: 是否已缓存
    func isCached(fileId: String) -> Bool {
        initializeIfNeededSync()

        guard let metadata = cacheMetadata[fileId] else {
            return false
        }

        let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)
        return fileManager.fileExists(atPath: filePath.path)
    }

    /// 根据 MIME 类型获取文件扩展名
    private nonisolated static func getFileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "audio/mpeg", "audio/mp3":
            "mp3"
        case "audio/mp4", "audio/m4a":
            "m4a"
        case "audio/wav", "audio/wave":
            "wav"
        case "audio/aac":
            "aac"
        case "audio/ogg":
            "ogg"
        default:
            "mp3"
        }
    }

    /// 同步初始化检查
    private func initializeIfNeededSync() {
        if cacheMetadata.isEmpty {
            createCacheDirectoryIfNeeded()
            loadMetadata()
        }
    }

    // MARK: - 缓存清理方法

    /// 获取当前缓存大小（字节）
    ///
    /// - Returns: 缓存总大小
    func getCacheSize() -> Int64 {
        initializeIfNeededSync()
        return calculateCacheSize()
    }

    /// 计算缓存大小（内部方法，不触发初始化）
    private func calculateCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        for metadata in cacheMetadata.values {
            totalSize += metadata.fileSize
        }
        return totalSize
    }

    /// 获取缓存大小（格式化字符串）
    ///
    /// - Returns: 格式化的缓存大小字符串
    func getFormattedCacheSize() -> String {
        let size = getCacheSize()
        return Self.formatBytes(size)
    }

    /// 清理所有缓存
    func clearCache() {
        for metadata in cacheMetadata.values {
            let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)
            try? fileManager.removeItem(at: filePath)
        }

        cacheMetadata.removeAll()

        saveMetadata()
    }

    func removeCache(for fileId: String) {
        guard let metadata = cacheMetadata[fileId] else {
            return
        }

        let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)
        try? fileManager.removeItem(at: filePath)

        cacheMetadata.removeValue(forKey: fileId)

        saveMetadata()
    }

    /// 使用 LRU 策略淘汰缓存，直到缓存大小小于目标大小
    ///
    /// - Parameter targetSize: 目标缓存大小（字节）
    func evictLeastRecentlyUsed(targetSize: Int64) {
        evictLeastRecentlyUsedInternal(targetSize: targetSize)
    }

    /// LRU 淘汰内部实现
    private func evictLeastRecentlyUsedInternal(targetSize: Int64) {
        var currentSize = cacheMetadata.values.reduce(0) { $0 + $1.fileSize }

        guard currentSize > targetSize else {
            return
        }

        let sortedMetadata = cacheMetadata.values.sorted { $0.lastAccessedAt < $1.lastAccessedAt }

        var evictedCount = 0
        var evictedSize: Int64 = 0

        for metadata in sortedMetadata {
            if currentSize <= targetSize {
                break
            }

            let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)
            try? fileManager.removeItem(at: filePath)

            cacheMetadata.removeValue(forKey: metadata.fileId)

            currentSize -= metadata.fileSize
            evictedSize += metadata.fileSize
            evictedCount += 1
        }

        if evictedCount > 0 {
            saveMetadata()
        }
    }

    func removeCacheForNote(noteId _: String, fileIds: [String]) {
        for fileId in fileIds {
            removeCache(for: fileId)
        }
    }

    // MARK: - 辅助方法

    /// 格式化字节数为可读字符串
    private nonisolated static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 获取缓存统计信息
    ///
    /// - Returns: 缓存统计信息字典
    func getCacheStats() -> [String: Any] {
        initializeIfNeededSync()

        let totalSize = cacheMetadata.values.reduce(0) { $0 + $1.fileSize }

        return [
            "fileCount": cacheMetadata.count,
            "totalSize": totalSize,
            "formattedSize": Self.formatBytes(totalSize),
            "maxSize": maxCacheSize,
            "formattedMaxSize": Self.formatBytes(maxCacheSize),
            "usagePercent": Double(totalSize) / Double(maxCacheSize) * 100,
        ]
    }

    /// 获取缓存目录路径
    ///
    /// - Returns: 缓存目录 URL
    nonisolated func getCacheDirectoryPath() -> URL {
        cacheDirectory
    }
}
