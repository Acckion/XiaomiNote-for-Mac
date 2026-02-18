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
final class AudioCacheService: @unchecked Sendable {

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

    /// 元数据访问锁
    private let metadataLock = NSLock()

    // MARK: - 初始化

    private init() {
        // 配置缓存目录：~/Library/Application Support/{bundleId}/audio/
        // 与图片存储目录 images/ 保持一致的结构
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appBundleID = Bundle.main.bundleIdentifier ?? "com.mi.note.mac"
        let appDirectory = appSupportDirectory.appendingPathComponent(appBundleID)
        self.cacheDirectory = appDirectory.appendingPathComponent("audio")
        self.metadataFilePath = appDirectory.appendingPathComponent("audio_cache_metadata.json")

        // 创建缓存目录
        createCacheDirectoryIfNeeded()

        // 加载缓存元数据
        loadMetadata()

        print("[AudioCache] 初始化完成")
        print("[AudioCache]   - 缓存目录: \(cacheDirectory.path)")
        print("[AudioCache]   - 最大缓存大小: \(maxCacheSize / 1024 / 1024) MB")
        print("[AudioCache]   - 当前缓存文件数: \(cacheMetadata.count)")
    }

    // MARK: - 目录管理

    /// 创建缓存目录（如果不存在）
    private func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
                print("[AudioCache] 创建缓存目录: \(cacheDirectory.path)")
            } catch {
                print("[AudioCache] ❌ 创建缓存目录失败: \(error)")
            }
        }
    }

    // MARK: - 元数据管理

    /// 加载缓存元数据
    private func loadMetadata() {
        metadataLock.lock()
        defer { metadataLock.unlock() }

        guard fileManager.fileExists(atPath: metadataFilePath.path) else {
            print("[AudioCache] 元数据文件不存在，使用空缓存")
            return
        }

        do {
            let data = try Data(contentsOf: metadataFilePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadataArray = try decoder.decode([CachedAudioFile].self, from: data)

            // 转换为字典
            cacheMetadata = Dictionary(uniqueKeysWithValues: metadataArray.map { ($0.fileId, $0) })

            // 验证缓存文件是否存在
            validateCacheFiles()

            print("[AudioCache] 加载元数据成功，共 \(cacheMetadata.count) 个缓存文件")
        } catch {
            print("[AudioCache] ❌ 加载元数据失败: \(error)")
            cacheMetadata = [:]
        }
    }

    /// 保存缓存元数据
    private func saveMetadata() {
        metadataLock.lock()
        defer { metadataLock.unlock() }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(Array(cacheMetadata.values))
            try data.write(to: metadataFilePath)
            print("[AudioCache] 保存元数据成功")
        } catch {
            print("[AudioCache] ❌ 保存元数据失败: \(error)")
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

        // 移除无效的元数据
        for fileId in invalidFileIds {
            cacheMetadata.removeValue(forKey: fileId)
            print("[AudioCache] 移除无效缓存元数据: \(fileId)")
        }

        if !invalidFileIds.isEmpty {
            print("[AudioCache] 清理了 \(invalidFileIds.count) 个无效缓存记录")
        }
    }

    // MARK: - 缓存读写方法

    /// 获取缓存的音频文件路径
    ///
    /// - Parameter fileId: 文件 ID
    /// - Returns: 本地文件 URL，如果未缓存则返回 nil
    func getCachedFile(for fileId: String) -> URL? {
        metadataLock.lock()
        defer { metadataLock.unlock() }

        guard var metadata = cacheMetadata[fileId] else {
            print("[AudioCache] 缓存未命中: \(fileId)")
            return nil
        }

        let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)

        // 验证文件是否存在
        guard fileManager.fileExists(atPath: filePath.path) else {
            // 文件不存在，移除元数据
            cacheMetadata.removeValue(forKey: fileId)
            saveMetadataAsync()
            print("[AudioCache] 缓存文件不存在，移除元数据: \(fileId)")
            return nil
        }

        // 更新最后访问时间
        metadata.lastAccessedAt = Date()
        cacheMetadata[fileId] = metadata
        saveMetadataAsync()

        print("[AudioCache] ✅ 缓存命中: \(fileId)")
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
        // 确保缓存目录存在
        createCacheDirectoryIfNeeded()

        // 检查是否需要清理缓存
        let currentSize = getCacheSize()
        let dataSize = Int64(data.count)

        if currentSize + dataSize > maxCacheSize {
            // 需要清理缓存以腾出空间
            let targetSize = maxCacheSize - dataSize - (10 * 1024 * 1024) // 预留 10MB 空间
            evictLeastRecentlyUsed(targetSize: max(0, targetSize))
        }

        // 生成文件名
        let fileExtension = getFileExtension(for: mimeType)
        let fileName = "\(fileId).\(fileExtension)"
        let filePath = cacheDirectory.appendingPathComponent(fileName)

        // 写入文件
        do {
            try data.write(to: filePath, options: .atomic)
            print("[AudioCache] ✅ 缓存文件成功: \(fileName), 大小: \(data.count) 字节")
            print("[AudioCache]   - 路径: \(filePath.path)")
        } catch {
            print("[AudioCache] ❌ 缓存文件失败: \(error)")
            print("[AudioCache]   - 目标路径: \(filePath.path)")
            print("[AudioCache]   - 目录存在: \(fileManager.fileExists(atPath: cacheDirectory.path))")
            throw error
        }

        // 更新元数据
        metadataLock.lock()
        let metadata = CachedAudioFile(
            fileId: fileId,
            localPath: fileName,
            fileSize: dataSize,
            mimeType: mimeType,
            cachedAt: Date(),
            lastAccessedAt: Date()
        )
        cacheMetadata[fileId] = metadata
        metadataLock.unlock()

        saveMetadataAsync()

        return filePath
    }

    /// 检查文件是否已缓存
    ///
    /// - Parameter fileId: 文件 ID
    /// - Returns: 是否已缓存
    func isCached(fileId: String) -> Bool {
        metadataLock.lock()
        defer { metadataLock.unlock() }

        guard let metadata = cacheMetadata[fileId] else {
            return false
        }

        // 验证文件是否存在
        let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)
        return fileManager.fileExists(atPath: filePath.path)
    }

    /// 根据 MIME 类型获取文件扩展名
    private func getFileExtension(for mimeType: String) -> String {
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
            "mp3" // 默认使用 mp3
        }
    }

    /// 异步保存元数据
    private func saveMetadataAsync() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.saveMetadata()
        }
    }

    // MARK: - 缓存清理方法

    /// 获取当前缓存大小（字节）
    ///
    /// - Returns: 缓存总大小
    func getCacheSize() -> Int64 {
        metadataLock.lock()
        defer { metadataLock.unlock() }

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
        return formatBytes(size)
    }

    /// 清理所有缓存
    func clearCache() {
        metadataLock.lock()

        // 删除所有缓存文件
        for metadata in cacheMetadata.values {
            let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)
            try? fileManager.removeItem(at: filePath)
        }

        // 清空元数据
        cacheMetadata.removeAll()

        metadataLock.unlock()

        // 保存空的元数据
        saveMetadata()

        print("[AudioCache] ✅ 清理所有缓存完成")
    }

    /// 清理指定文件的缓存
    ///
    /// - Parameter fileId: 文件 ID
    func removeCache(for fileId: String) {
        metadataLock.lock()

        guard let metadata = cacheMetadata[fileId] else {
            metadataLock.unlock()
            print("[AudioCache] 缓存不存在: \(fileId)")
            return
        }

        // 删除文件
        let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)
        try? fileManager.removeItem(at: filePath)

        // 移除元数据
        cacheMetadata.removeValue(forKey: fileId)

        metadataLock.unlock()

        saveMetadataAsync()

        print("[AudioCache] ✅ 移除缓存: \(fileId)")
    }

    /// 使用 LRU 策略淘汰缓存，直到缓存大小小于目标大小
    ///
    /// - Parameter targetSize: 目标缓存大小（字节）
    func evictLeastRecentlyUsed(targetSize: Int64) {
        metadataLock.lock()

        var currentSize = cacheMetadata.values.reduce(0) { $0 + $1.fileSize }

        // 如果当前大小已经小于目标大小，无需清理
        guard currentSize > targetSize else {
            metadataLock.unlock()
            return
        }

        // 按最后访问时间排序（最久未访问的在前）
        let sortedMetadata = cacheMetadata.values.sorted { $0.lastAccessedAt < $1.lastAccessedAt }

        var evictedCount = 0
        var evictedSize: Int64 = 0

        for metadata in sortedMetadata {
            // 如果已经达到目标大小，停止清理
            if currentSize <= targetSize {
                break
            }

            // 删除文件
            let filePath = cacheDirectory.appendingPathComponent(metadata.localPath)
            try? fileManager.removeItem(at: filePath)

            // 移除元数据
            cacheMetadata.removeValue(forKey: metadata.fileId)

            currentSize -= metadata.fileSize
            evictedSize += metadata.fileSize
            evictedCount += 1

            print("[AudioCache] LRU 淘汰: \(metadata.fileId), 大小: \(formatBytes(metadata.fileSize))")
        }

        metadataLock.unlock()

        if evictedCount > 0 {
            saveMetadataAsync()
            print("[AudioCache] ✅ LRU 淘汰完成: 清理 \(evictedCount) 个文件，释放 \(formatBytes(evictedSize))")
        }
    }

    /// 清理与指定笔记相关的语音缓存
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Parameter fileIds: 该笔记包含的语音文件 ID 列表
    func removeCacheForNote(noteId: String, fileIds: [String]) {
        for fileId in fileIds {
            removeCache(for: fileId)
        }
        print("[AudioCache] 清理笔记 \(noteId) 的语音缓存: \(fileIds.count) 个文件")
    }

    // MARK: - 辅助方法

    /// 格式化字节数为可读字符串
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 获取缓存统计信息
    ///
    /// - Returns: 缓存统计信息字典
    func getCacheStats() -> [String: Any] {
        metadataLock.lock()
        defer { metadataLock.unlock() }

        let totalSize = cacheMetadata.values.reduce(0) { $0 + $1.fileSize }

        return [
            "fileCount": cacheMetadata.count,
            "totalSize": totalSize,
            "formattedSize": formatBytes(totalSize),
            "maxSize": maxCacheSize,
            "formattedMaxSize": formatBytes(maxCacheSize),
            "usagePercent": Double(totalSize) / Double(maxCacheSize) * 100,
        ]
    }

    /// 获取缓存目录路径
    ///
    /// - Returns: 缓存目录 URL
    func getCacheDirectoryPath() -> URL {
        cacheDirectory
    }
}
