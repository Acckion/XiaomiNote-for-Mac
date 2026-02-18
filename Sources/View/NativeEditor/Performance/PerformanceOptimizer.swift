//
//  PerformanceOptimizer.swift
//  MiNoteMac
//
//  性能优化器 - 负责编辑器渲染和响应性能优化
//  需求: 11.1, 11.2, 11.3, 11.4, 11.5
//

import AppKit
import Combine
import SwiftUI

// MARK: - 性能指标

/// 性能指标结构
struct PerformanceMetrics {
    /// 初始化时间（毫秒）
    var initializationTime: Double = 0

    /// 渲染时间（毫秒）
    var renderTime: Double = 0

    /// 格式应用时间（毫秒）
    var formatApplicationTime: Double = 0

    /// 内容转换时间（毫秒）
    var conversionTime: Double = 0

    /// 缓存命中率
    var cacheHitRate: Double = 0

    /// 内存使用量（字节）
    var memoryUsage: Int64 = 0

    /// 文档行数
    var documentLineCount = 0

    /// 附件数量
    var attachmentCount = 0

    /// 时间戳
    var timestamp = Date()

    /// 格式化的描述
    var description: String {
        """
        性能指标:
        - 初始化时间: \(String(format: "%.2f", initializationTime))ms
        - 渲染时间: \(String(format: "%.2f", renderTime))ms
        - 格式应用时间: \(String(format: "%.2f", formatApplicationTime))ms
        - 转换时间: \(String(format: "%.2f", conversionTime))ms
        - 缓存命中率: \(String(format: "%.1f", cacheHitRate * 100))%
        - 内存使用: \(ByteCountFormatter.string(fromByteCount: memoryUsage, countStyle: .memory))
        - 文档行数: \(documentLineCount)
        - 附件数量: \(attachmentCount)
        """
    }
}

// MARK: - 缓存配置

/// 缓存配置
struct CacheConfiguration {
    /// 附件缓存最大数量
    var maxAttachmentCacheSize = 200

    /// 图像缓存最大数量
    var maxImageCacheSize = 50

    /// 图像缓存最大内存（字节）
    var maxImageCacheMemory: Int64 = 100 * 1024 * 1024 // 100MB

    /// 渲染结果缓存最大数量
    var maxRenderCacheSize = 100

    /// 缓存过期时间（秒）
    var cacheExpirationTime: TimeInterval = 300 // 5分钟

    /// 是否启用增量渲染
    var enableIncrementalRendering = true

    /// 增量渲染阈值（行数）
    var incrementalRenderingThreshold = 100

    /// 默认配置
    static let `default` = CacheConfiguration()

    /// 高性能配置（更大的缓存）
    static let highPerformance = CacheConfiguration(
        maxAttachmentCacheSize: 500,
        maxImageCacheSize: 100,
        maxImageCacheMemory: 200 * 1024 * 1024,
        maxRenderCacheSize: 200,
        cacheExpirationTime: 600,
        enableIncrementalRendering: true,
        incrementalRenderingThreshold: 50
    )

    /// 低内存配置（更小的缓存）
    static let lowMemory = CacheConfiguration(
        maxAttachmentCacheSize: 50,
        maxImageCacheSize: 20,
        maxImageCacheMemory: 30 * 1024 * 1024,
        maxRenderCacheSize: 30,
        cacheExpirationTime: 120,
        enableIncrementalRendering: true,
        incrementalRenderingThreshold: 200
    )
}

// MARK: - 缓存条目

/// 缓存条目
struct CacheEntry<T> {
    let value: T
    let createdAt: Date
    var lastAccessedAt: Date
    var accessCount: Int

    init(value: T) {
        self.value = value
        self.createdAt = Date()
        self.lastAccessedAt = Date()
        self.accessCount = 1
    }

    mutating func recordAccess() {
        lastAccessedAt = Date()
        accessCount += 1
    }

    func isExpired(expirationTime: TimeInterval) -> Bool {
        Date().timeIntervalSince(lastAccessedAt) > expirationTime
    }
}

// MARK: - LRU 缓存

/// LRU 缓存实现
class LRUCache<Key: Hashable, Value> {
    private var cache: [Key: CacheEntry<Value>] = [:]
    private var accessOrder: [Key] = []
    private let maxSize: Int
    private let expirationTime: TimeInterval
    private let lock = NSLock()

    /// 缓存命中次数
    private(set) var hitCount = 0

    /// 缓存未命中次数
    private(set) var missCount = 0

    /// 缓存命中率
    var hitRate: Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0
    }

    init(maxSize: Int, expirationTime: TimeInterval = 300) {
        self.maxSize = maxSize
        self.expirationTime = expirationTime
    }

    /// 获取缓存值
    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard var entry = cache[key] else {
            missCount += 1
            return nil
        }

        // 检查是否过期
        if entry.isExpired(expirationTime: expirationTime) {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            missCount += 1
            return nil
        }

        // 更新访问记录
        entry.recordAccess()
        cache[key] = entry

        // 更新访问顺序
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)

        hitCount += 1
        return entry.value
    }

    /// 设置缓存值
    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }

        // 如果已存在，更新
        if cache[key] != nil {
            cache[key] = CacheEntry(value: value)
            accessOrder.removeAll { $0 == key }
            accessOrder.append(key)
            return
        }

        // 如果缓存已满，移除最久未使用的
        while cache.count >= maxSize {
            if let oldestKey = accessOrder.first {
                cache.removeValue(forKey: oldestKey)
                accessOrder.removeFirst()
            }
        }

        // 添加新条目
        cache[key] = CacheEntry(value: value)
        accessOrder.append(key)
    }

    /// 移除缓存值
    func remove(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }

    /// 清除所有缓存
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        accessOrder.removeAll()
        hitCount = 0
        missCount = 0
    }

    /// 清除过期条目
    func clearExpired() {
        lock.lock()
        defer { lock.unlock() }

        let expiredKeys = cache.filter { $0.value.isExpired(expirationTime: expirationTime) }.map(\.key)
        for key in expiredKeys {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }

    /// 当前缓存大小
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
}

// MARK: - 性能优化器

/// 性能优化器 - 负责编辑器渲染和响应性能优化
@MainActor
class PerformanceOptimizer {

    // MARK: - Singleton

    static let shared = PerformanceOptimizer()

    // MARK: - Properties

    /// 缓存配置
    private(set) var configuration: CacheConfiguration

    /// 附件缓存
    private var attachmentCache: LRUCache<String, NSTextAttachment>

    /// 图像缓存
    private var imageCache: LRUCache<String, NSImage>

    /// 渲染结果缓存
    private var renderCache: LRUCache<String, NSAttributedString>

    /// 性能指标
    var currentMetrics = PerformanceMetrics()

    /// 性能指标历史
    private var metricsHistory: [PerformanceMetrics] = []

    /// 最大历史记录数
    private let maxMetricsHistory = 100

    /// 是否启用性能监控
    var isMonitoringEnabled = true

    /// 性能警告阈值（毫秒）
    var performanceWarningThreshold: Double = 100

    /// 性能指标发布者
    private let metricsSubject = PassthroughSubject<PerformanceMetrics, Never>()

    /// 性能指标发布者
    var metricsPublisher: AnyPublisher<PerformanceMetrics, Never> {
        metricsSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    private init() {
        self.configuration = .default
        self.attachmentCache = LRUCache(
            maxSize: configuration.maxAttachmentCacheSize,
            expirationTime: configuration.cacheExpirationTime
        )
        self.imageCache = LRUCache(
            maxSize: configuration.maxImageCacheSize,
            expirationTime: configuration.cacheExpirationTime
        )
        self.renderCache = LRUCache(
            maxSize: configuration.maxRenderCacheSize,
            expirationTime: configuration.cacheExpirationTime
        )

        // 监听内存警告
        setupMemoryWarningObserver()
    }

    // MARK: - Configuration

    /// 更新缓存配置
    func updateConfiguration(_ newConfiguration: CacheConfiguration) {
        configuration = newConfiguration

        // 重新创建缓存
        attachmentCache = LRUCache(
            maxSize: newConfiguration.maxAttachmentCacheSize,
            expirationTime: newConfiguration.cacheExpirationTime
        )
        imageCache = LRUCache(
            maxSize: newConfiguration.maxImageCacheSize,
            expirationTime: newConfiguration.cacheExpirationTime
        )
        renderCache = LRUCache(
            maxSize: newConfiguration.maxRenderCacheSize,
            expirationTime: newConfiguration.cacheExpirationTime
        )
    }

    // MARK: - Attachment Caching

    /// 获取缓存的附件
    func getCachedAttachment(key: String) -> NSTextAttachment? {
        attachmentCache.get(key)
    }

    /// 缓存附件
    func cacheAttachment(key: String, attachment: NSTextAttachment) {
        attachmentCache.set(key, value: attachment)
    }

    /// 获取或创建附件
    func getOrCreateAttachment(key: String, factory: () -> NSTextAttachment) -> NSTextAttachment {
        if let cached = attachmentCache.get(key) {
            return cached
        }

        let attachment = factory()
        attachmentCache.set(key, value: attachment)
        return attachment
    }

    // MARK: - Image Caching

    /// 获取缓存的图像
    func getCachedImage(key: String) -> NSImage? {
        imageCache.get(key)
    }

    /// 缓存图像
    func cacheImage(key: String, image: NSImage) {
        imageCache.set(key, value: image)
    }

    /// 获取或创建图像
    func getOrCreateImage(key: String, factory: () -> NSImage?) -> NSImage? {
        if let cached = imageCache.get(key) {
            return cached
        }

        guard let image = factory() else {
            return nil
        }

        imageCache.set(key, value: image)
        return image
    }

    // MARK: - Render Caching

    /// 获取缓存的渲染结果
    func getCachedRender(key: String) -> NSAttributedString? {
        renderCache.get(key)
    }

    /// 缓存渲染结果
    func cacheRender(key: String, attributedString: NSAttributedString) {
        renderCache.set(key, value: attributedString)
    }

    // MARK: - Performance Measurement

    /// 测量操作执行时间
    func measureTime<T>(_ operation: String, block: () throws -> T) rethrows -> T {
        guard isMonitoringEnabled else {
            return try block()
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000 // 转换为毫秒

        // 记录性能指标
        recordOperationTime(operation: operation, duration: duration)

        // 检查性能警告
        if duration > performanceWarningThreshold {
            print("[PerformanceOptimizer] 性能警告: \(operation) 耗时 \(String(format: "%.2f", duration))ms")
        }

        return result
    }

    /// 测量异步操作执行时间
    func measureTimeAsync<T>(_ operation: String, block: () async throws -> T) async rethrows -> T {
        guard isMonitoringEnabled else {
            return try await block()
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000

        recordOperationTime(operation: operation, duration: duration)

        if duration > performanceWarningThreshold {
            print("[PerformanceOptimizer] 性能警告: \(operation) 耗时 \(String(format: "%.2f", duration))ms")
        }

        return result
    }

    /// 记录操作时间
    private func recordOperationTime(operation: String, duration: Double) {
        switch operation {
        case "initialization":
            currentMetrics.initializationTime = duration
        case "render":
            currentMetrics.renderTime = duration
        case "formatApplication":
            currentMetrics.formatApplicationTime = duration
        case "conversion":
            currentMetrics.conversionTime = duration
        default:
            break
        }

        currentMetrics.timestamp = Date()
    }

    /// 更新缓存命中率
    func updateCacheHitRate() {
        let attachmentHitRate = attachmentCache.hitRate
        let imageHitRate = imageCache.hitRate
        let renderHitRate = renderCache.hitRate

        // 计算加权平均
        currentMetrics.cacheHitRate = (attachmentHitRate + imageHitRate + renderHitRate) / 3
    }

    /// 更新文档统计
    func updateDocumentStats(lineCount: Int, attachmentCount: Int) {
        currentMetrics.documentLineCount = lineCount
        currentMetrics.attachmentCount = attachmentCount
    }

    /// 更新内存使用
    func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            currentMetrics.memoryUsage = Int64(info.resident_size)
        }
    }

    /// 记录当前指标到历史
    func recordMetrics() {
        updateCacheHitRate()
        updateMemoryUsage()

        metricsHistory.append(currentMetrics)

        // 限制历史记录数量
        if metricsHistory.count > maxMetricsHistory {
            metricsHistory.removeFirst()
        }

        // 发布指标
        metricsSubject.send(currentMetrics)
    }

    /// 获取性能报告
    func getPerformanceReport() -> String {
        updateCacheHitRate()
        updateMemoryUsage()

        var report = """
        ========== 性能报告 ==========
        时间: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))

        当前指标:
        \(currentMetrics.description)

        缓存状态:
        - 附件缓存: \(attachmentCache.count)/\(configuration.maxAttachmentCacheSize) (命中率: \(String(format: "%.1f", attachmentCache.hitRate * 100))%)
        - 图像缓存: \(imageCache.count)/\(configuration.maxImageCacheSize) (命中率: \(String(format: "%.1f", imageCache.hitRate * 100))%)
        - 渲染缓存: \(renderCache.count)/\(configuration.maxRenderCacheSize) (命中率: \(String(format: "%.1f", renderCache.hitRate * 100))%)

        """

        // 添加历史统计
        if !metricsHistory.isEmpty {
            let avgInitTime = metricsHistory.map(\.initializationTime).reduce(0, +) / Double(metricsHistory.count)
            let avgRenderTime = metricsHistory.map(\.renderTime).reduce(0, +) / Double(metricsHistory.count)

            report += """

            历史统计 (最近 \(metricsHistory.count) 次):
            - 平均初始化时间: \(String(format: "%.2f", avgInitTime))ms
            - 平均渲染时间: \(String(format: "%.2f", avgRenderTime))ms
            """
        }

        report += "\n================================"

        return report
    }

    // MARK: - Cache Management

    /// 清除所有缓存
    func clearAllCaches() {
        attachmentCache.clear()
        imageCache.clear()
        renderCache.clear()

        print("[PerformanceOptimizer] 所有缓存已清除")
    }

    /// 清除过期缓存
    func clearExpiredCaches() {
        attachmentCache.clearExpired()
        imageCache.clearExpired()
        renderCache.clearExpired()
    }

    /// 获取缓存统计
    func getCacheStats() -> (attachments: Int, images: Int, renders: Int) {
        (attachmentCache.count, imageCache.count, renderCache.count)
    }

    // MARK: - Memory Management

    /// 设置内存警告观察者
    private func setupMemoryWarningObserver() {
        // 监听系统内存压力通知
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryPressure()
            }
        }
    }

    /// 处理内存压力
    private func handleMemoryPressure() {
        // 清除过期缓存
        clearExpiredCaches()

        // 如果内存使用过高，切换到低内存配置
        updateMemoryUsage()
        if currentMetrics.memoryUsage > configuration.maxImageCacheMemory * 2 {
            print("[PerformanceOptimizer] 内存压力过高，切换到低内存配置")
            updateConfiguration(.lowMemory)
        }
    }

    // MARK: - Incremental Rendering

    /// 检查是否应该使用增量渲染
    func shouldUseIncrementalRendering(lineCount: Int) -> Bool {
        configuration.enableIncrementalRendering &&
            lineCount > configuration.incrementalRenderingThreshold
    }

    /// 计算可见范围
    func calculateVisibleRange(
        scrollView: NSScrollView,
        textView: NSTextView,
        lineHeight: CGFloat
    ) -> NSRange {
        let visibleRect = scrollView.documentVisibleRect
        let textContainer = textView.textContainer
        let layoutManager = textView.layoutManager

        guard let container = textContainer, let layout = layoutManager else {
            return NSRange(location: 0, length: textView.string.count)
        }

        // 计算可见区域的字符范围
        let glyphRange = layout.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // 扩展范围以包含缓冲区
        let bufferLines = 10
        let bufferChars = Int(CGFloat(bufferLines) * lineHeight)

        let start = max(0, charRange.location - bufferChars)
        let end = min(textView.string.count, charRange.location + charRange.length + bufferChars)

        return NSRange(location: start, length: end - start)
    }
}

// MARK: - 增量渲染支持

/// 增量渲染管理器
@MainActor
class IncrementalRenderManager {

    /// 渲染块大小（行数）
    var chunkSize = 50

    /// 当前渲染进度
    private(set) var currentProgress: Double = 0

    /// 是否正在渲染
    private(set) var isRendering = false

    /// 渲染完成回调
    var onRenderComplete: (() -> Void)?

    /// 渲染进度回调
    var onProgressUpdate: ((Double) -> Void)?

    /// 增量渲染文档
    func renderIncrementally(
        content: String,
        textStorage: NSTextStorage,
        converter: @escaping (String) throws -> NSAttributedString
    ) async {
        guard !isRendering else { return }

        isRendering = true
        currentProgress = 0

        let lines = content.components(separatedBy: .newlines)
        let totalLines = lines.count
        var processedLines = 0

        // 分块处理
        for chunkStart in stride(from: 0, to: totalLines, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, totalLines)
            let chunkLines = Array(lines[chunkStart ..< chunkEnd])
            let chunkContent = chunkLines.joined(separator: "\n")

            do {
                let attributedChunk = try converter(chunkContent)

                // 在主线程更新 UI
                await MainActor.run {
                    if chunkStart == 0 {
                        textStorage.setAttributedString(attributedChunk)
                    } else {
                        textStorage.append(NSAttributedString(string: "\n"))
                        textStorage.append(attributedChunk)
                    }
                }

                processedLines = chunkEnd
                currentProgress = Double(processedLines) / Double(totalLines)
                onProgressUpdate?(currentProgress)

                // 让出 CPU 时间
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms

            } catch {
                print("[IncrementalRenderManager] 渲染块失败: \(error)")
            }
        }

        isRendering = false
        currentProgress = 1.0
        onRenderComplete?()
    }

    /// 取消渲染
    func cancelRendering() {
        isRendering = false
    }
}

// MARK: - 编辑器初始化优化器

/// 编辑器初始化优化器 - 确保快速初始化
/// 需求: 11.1
@MainActor
class EditorInitializationOptimizer {

    /// 预加载的资源
    private static var preloadedResources: [String: Any] = [:]

    /// 是否已预加载
    private static var isPreloaded = false

    /// 预加载资源
    static func preloadResources() {
        guard !isPreloaded else { return }

        let startTime = CFAbsoluteTimeGetCurrent()

        // 预加载字体 - 使用 FontSizeManager 统一管理
        // _Requirements: 1.1, 1.2, 1.3, 1.4_
        _ = NSFont.systemFont(ofSize: FontSizeConstants.body) // 14pt 正文
        _ = NSFont.systemFont(ofSize: FontSizeConstants.heading1) // 23pt 大标题
        _ = NSFont.systemFont(ofSize: FontSizeConstants.heading2) // 20pt 二级标题
        _ = NSFont.systemFont(ofSize: FontSizeConstants.heading3) // 17pt 三级标题

        // 预加载颜色
        _ = NSColor.textColor
        _ = NSColor.textBackgroundColor
        _ = NSColor.systemBlue

        // 预加载渲染器
        _ = CustomRenderer.shared

        // 预加载格式管理器
        _ = FormatManager.shared

        isPreloaded = true

        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000

        print("[EditorInitializationOptimizer] 资源预加载完成，耗时: \(String(format: "%.2f", duration))ms")
    }

    /// 创建优化的文本视图
    static func createOptimizedTextView() -> NSTextView {
        let textView = NSTextView()

        // 禁用不必要的功能以提高性能
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false

        // 优化文本容器
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        // 设置合理的默认值
        // 使用 FontSizeConstants.body (14pt) 保持与 FontSizeManager 一致
        // _Requirements: 1.4_
        textView.font = NSFont.systemFont(ofSize: FontSizeConstants.body)
        textView.textColor = .textColor

        return textView
    }

    /// 测量初始化时间
    static func measureInitializationTime<T>(_ block: () -> T) -> (result: T, duration: Double) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = block()
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000

        // 记录到性能优化器
        PerformanceOptimizer.shared.currentMetrics.initializationTime = duration

        // 检查是否超过阈值
        if duration > 100 {
            print("[EditorInitializationOptimizer] 警告: 初始化时间超过 100ms (\(String(format: "%.2f", duration))ms)")
        }

        return (result, duration)
    }
}
