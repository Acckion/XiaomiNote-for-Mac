//
//  ImageStorageManager.swift
//  MiNoteMac
//
//  图片存储管理器 - 处理图片的本地存储和加载
//  需求: 10.1, 10.2
//

import AppKit
import Foundation

/// 图片存储管理器 - 负责图片的本地存储和加载
@MainActor
class ImageStorageManager {
    
    // MARK: - Singleton
    
    static let shared = ImageStorageManager()
    
    // MARK: - Properties
    
    /// 本地存储服务
    private let localStorage = LocalStorageService.shared
    
    /// 图片缓存
    private var imageCache: [String: NSImage] = [:]
    
    /// 缓存大小限制
    private let maxCacheSize = 50
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 保存图片到本地存储
    /// - Parameters:
    ///   - image: 要保存的图片
    ///   - folderId: 文件夹 ID
    /// - Returns: 保存结果，包含文件 ID 和 URL
    func saveImage(_ image: NSImage, folderId: String) -> (fileId: String, url: URL)? {
        // 生成唯一的文件 ID
        let fileId = generateFileId()
        
        // 将图片转换为 JPEG 数据
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            print("[ImageStorageManager] 无法将图片转换为 JPEG 数据")
            return nil
        }
        
        do {
            // 保存到本地存储
            let url = try localStorage.saveImage(imageData, imageId: fileId, folderId: folderId)
            
            // 添加到缓存
            let cacheKey = "\(folderId)/\(fileId)"
            addToCache(image, forKey: cacheKey)
            
            print("[ImageStorageManager] 图片保存成功: \(fileId)")
            return (fileId, url)
        } catch {
            print("[ImageStorageManager] 保存图片失败: \(error)")
            return nil
        }
    }
    
    /// 保存图片数据到本地存储
    /// - Parameters:
    ///   - imageData: 图片数据
    ///   - folderId: 文件夹 ID
    /// - Returns: 保存结果，包含文件 ID 和 URL
    func saveImageData(_ imageData: Data, folderId: String) -> (fileId: String, url: URL)? {
        let fileId = generateFileId()
        
        do {
            let url = try localStorage.saveImage(imageData, imageId: fileId, folderId: folderId)
            
            // 尝试创建图片并添加到缓存
            if let image = NSImage(data: imageData) {
                let cacheKey = "\(folderId)/\(fileId)"
                addToCache(image, forKey: cacheKey)
            }
            
            print("[ImageStorageManager] 图片数据保存成功: \(fileId)")
            return (fileId, url)
        } catch {
            print("[ImageStorageManager] 保存图片数据失败: \(error)")
            return nil
        }
    }
    
    /// 从本地存储加载图片
    /// - Parameters:
    ///   - fileId: 文件 ID
    ///   - folderId: 文件夹 ID
    /// - Returns: 加载的图片，如果失败则返回 nil
    func loadImage(fileId: String, folderId: String) -> NSImage? {
        let cacheKey = "\(folderId)/\(fileId)"
        
        // 检查缓存
        if let cached = imageCache[cacheKey] {
            return cached
        }
        
        // 从本地存储加载
        guard let imageData = localStorage.getImage(imageId: fileId, folderId: folderId) else {
            print("[ImageStorageManager] 无法加载图片: \(fileId)")
            return nil
        }
        
        guard let image = NSImage(data: imageData) else {
            print("[ImageStorageManager] 无法解析图片数据: \(fileId)")
            return nil
        }
        
        // 添加到缓存
        addToCache(image, forKey: cacheKey)
        
        return image
    }
    
    /// 异步加载图片
    /// - Parameters:
    ///   - fileId: 文件 ID
    ///   - folderId: 文件夹 ID
    ///   - completion: 完成回调
    func loadImageAsync(fileId: String, folderId: String, completion: @escaping @Sendable (NSImage?) -> Void) {
        let cacheKey = "\(folderId)/\(fileId)"
        
        // 检查缓存
        if let cached = imageCache[cacheKey] {
            completion(cached)
            return
        }
        
        // 在后台线程加载
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let imageData = LocalStorageService.shared.getImage(imageId: fileId, folderId: folderId)
            let image = imageData.flatMap { NSImage(data: $0) }
            
            DispatchQueue.main.async {
                if let image = image {
                    self?.addToCache(image, forKey: cacheKey)
                }
                completion(image)
            }
        }
    }
    
    /// 检查图片是否存在
    /// - Parameters:
    ///   - fileId: 文件 ID
    ///   - folderId: 文件夹 ID
    /// - Returns: 是否存在
    func imageExists(fileId: String, folderId: String) -> Bool {
        return localStorage.imageExists(imageId: fileId, folderId: folderId)
    }
    
    /// 生成 minote:// URL
    /// - Parameters:
    ///   - fileId: 文件 ID
    ///   - folderId: 文件夹 ID
    /// - Returns: minote:// URL 字符串
    func generateMinoteURL(fileId: String, folderId: String) -> String {
        return "minote://images/\(folderId)/\(fileId).jpg"
    }
    
    /// 解析 minote:// URL
    /// - Parameter urlString: URL 字符串
    /// - Returns: 解析结果，包含 fileId 和 folderId
    func parseMinoteURL(_ urlString: String) -> (fileId: String, folderId: String)? {
        guard urlString.hasPrefix("minote://") else {
            return nil
        }
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        if pathComponents.count >= 3 && pathComponents[0] == "images" {
            let folderId = pathComponents[1]
            let fileName = pathComponents[2]
            let fileId = (fileName as NSString).deletingPathExtension
            return (fileId, folderId)
        }
        
        return nil
    }
    
    // MARK: - Cache Management
    
    /// 清除缓存
    func clearCache() {
        imageCache.removeAll()
    }
    
    /// 从缓存中移除指定图片
    func removeFromCache(fileId: String, folderId: String) {
        let cacheKey = "\(folderId)/\(fileId)"
        imageCache.removeValue(forKey: cacheKey)
    }
    
    /// 获取缓存统计信息
    func getCacheStats() -> (count: Int, maxSize: Int) {
        return (imageCache.count, maxCacheSize)
    }
    
    // MARK: - Private Methods
    
    /// 生成唯一的文件 ID
    private func generateFileId() -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let random = Int.random(in: 1000...9999)
        return "img_\(timestamp)_\(random)"
    }
    
    /// 添加到缓存
    private func addToCache(_ image: NSImage, forKey key: String) {
        // 如果缓存已满，移除最早的项
        if imageCache.count >= maxCacheSize {
            if let firstKey = imageCache.keys.first {
                imageCache.removeValue(forKey: firstKey)
            }
        }
        
        imageCache[key] = image
    }
}

// MARK: - NSImage Extension

extension NSImage {
    /// 将图片转换为 JPEG 数据
    /// - Parameter compressionQuality: 压缩质量（0.0 - 1.0）
    /// - Returns: JPEG 数据
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
    
    /// 将图片转换为 PNG 数据
    /// - Returns: PNG 数据
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmapRep.representation(using: .png, properties: [:])
    }
    
    /// 调整图片大小
    /// - Parameter newSize: 新尺寸
    /// - Returns: 调整后的图片
    func resized(to newSize: NSSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        
        newImage.unlockFocus()
        return newImage
    }
    
    /// 按最大宽度调整图片大小
    /// - Parameter maxWidth: 最大宽度
    /// - Returns: 调整后的图片
    func resizedToMaxWidth(_ maxWidth: CGFloat) -> NSImage {
        guard size.width > maxWidth else {
            return self
        }
        
        let ratio = maxWidth / size.width
        let newSize = NSSize(width: maxWidth, height: size.height * ratio)
        return resized(to: newSize)
    }
}
