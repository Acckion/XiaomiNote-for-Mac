import Foundation
import AppKit

/// 笔记预览服务
///
/// 负责加载和缓存笔记的图片预览。
/// 使用内存缓存避免重复加载同一图片。
///
/// **使用方式**：
/// ```swift
/// let service = NotePreviewService.shared
/// if let image = service.loadPreviewImage(fileId: "xxx", fileType: "png") {
///     // 使用图片
/// }
/// ```
@MainActor
public class NotePreviewService: ObservableObject {
    /// 单例实例
    public static let shared = NotePreviewService()
    
    /// 内存缓存：fileId -> NSImage
    private var imageCache: [String: NSImage] = [:]
    
    /// 缓存大小限制（最多缓存的图片数量）
    private let maxCacheSize = 100
    
    /// LRU 缓存访问顺序记录
    private var cacheAccessOrder: [String] = []
    
    /// 本地存储服务
    private let localStorage = LocalStorageService.shared
    
    private init() {
        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: NSApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 公共方法
    
    /// 加载预览图片
    ///
    /// 首先检查内存缓存，如果缓存中没有则从本地存储加载。
    /// 加载成功后会自动缓存到内存中。
    ///
    /// - Parameters:
    ///   - fileId: 文件ID（完整格式：userId.fileId）
    ///   - fileType: 文件类型（如 "png", "jpg"）
    /// - Returns: NSImage 对象，如果加载失败则返回 nil
    public func loadPreviewImage(fileId: String, fileType: String) -> NSImage? {
        // 1. 检查缓存
        if let cached = getCachedImage(fileId: fileId) {
            return cached
        }
        
        // 2. 从本地存储加载
        guard let imageData = localStorage.loadImage(fileId: fileId, fileType: fileType) else {
            return nil
        }
        
        // 3. 创建 NSImage
        guard let image = NSImage(data: imageData) else {
            print("[NotePreviewService] 无法从数据创建 NSImage: \(fileId)")
            return nil
        }
        
        // 4. 缓存图片
        cacheImage(image, forFileId: fileId)
        
        return image
    }
    
    /// 清除所有缓存
    public func clearCache() {
        imageCache.removeAll()
        cacheAccessOrder.removeAll()
        print("[NotePreviewService] 缓存已清除")
    }
    
    /// 清除指定图片的缓存
    ///
    /// - Parameter fileId: 要清除的图片 fileId
    public func clearCache(forFileId fileId: String) {
        imageCache.removeValue(forKey: fileId)
        cacheAccessOrder.removeAll { $0 == fileId }
    }
    
    /// 获取缓存统计信息
    ///
    /// - Returns: (缓存数量, 最大缓存数量)
    public func getCacheStats() -> (count: Int, maxSize: Int) {
        return (imageCache.count, maxCacheSize)
    }
    
    // MARK: - 私有方法
    
    /// 从缓存中获取图片
    private func getCachedImage(fileId: String) -> NSImage? {
        guard let image = imageCache[fileId] else {
            return nil
        }
        
        // 更新访问顺序（LRU）
        updateAccessOrder(fileId: fileId)
        
        return image
    }
    
    /// 缓存图片
    private func cacheImage(_ image: NSImage, forFileId fileId: String) {
        // 检查缓存大小，如果超过限制则移除最旧的图片
        if imageCache.count >= maxCacheSize {
            evictOldestImage()
        }
        
        // 添加到缓存
        imageCache[fileId] = image
        updateAccessOrder(fileId: fileId)
    }
    
    /// 更新访问顺序（LRU）
    private func updateAccessOrder(fileId: String) {
        // 移除旧的访问记录
        cacheAccessOrder.removeAll { $0 == fileId }
        
        // 添加到末尾（最新访问）
        cacheAccessOrder.append(fileId)
    }
    
    /// 移除最旧的图片（LRU 策略）
    private func evictOldestImage() {
        guard let oldestFileId = cacheAccessOrder.first else {
            return
        }
        
        imageCache.removeValue(forKey: oldestFileId)
        cacheAccessOrder.removeFirst()
        
        print("[NotePreviewService] 移除最旧的缓存图片: \(oldestFileId)")
    }
    
    /// 处理内存警告
    @objc private func handleMemoryWarning() {
        print("[NotePreviewService] 收到内存警告，清除缓存")
        clearCache()
    }
}
